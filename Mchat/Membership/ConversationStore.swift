import Foundation

/// Manages joined conversations and their local state
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()
    
    private init() {
        loadJoinedConversations()
    }
    
    // MARK: - Storage Keys
    
    private let joinedConversationsKey = "mchat.joined_conversations"
    private let favoriteConversationsKey = "mchat.favorite_conversations"
    
    // MARK: - Published State
    
    @Published private(set) var joinedConversations: [Data: JoinedConversation] = [:]
    @Published private(set) var favoriteConversations: Set<Data> = []
    
    // MARK: - Joined Conversation Model
    
    struct JoinedConversation: Codable {
        let conversation: Conversation
        var isFavorite: Bool
        var isMuted: Bool
        var lastReadAt: Date?
        var unreadCount: Int
        let joinedAt: Date
        
        // Note: Room password encryption keys would go here in future implementation
        // var symmetricKeyMaterial: Data?  // For encrypted rooms
        
        init(conversation: Conversation, isFavorite: Bool = false, isMuted: Bool = false) {
            self.conversation = conversation
            self.isFavorite = isFavorite
            self.isMuted = isMuted
            self.lastReadAt = nil
            self.unreadCount = 0
            self.joinedAt = Date()
        }
        
        mutating func markAsRead() {
            self.lastReadAt = Date()
            self.unreadCount = 0
        }
        
        mutating func incrementUnreadCount() {
            self.unreadCount += 1
        }
    }
    
    // MARK: - Public Interface
    
    /// Check if user has joined a specific conversation
    func isJoined(_ conversationId: Data) -> Bool {
        return joinedConversations[conversationId] != nil
    }
    
    /// Get joined conversation details
    func getJoinedConversation(_ conversationId: Data) -> JoinedConversation? {
        return joinedConversations[conversationId]
    }
    
    /// Get all joined conversations
    func getAllJoinedConversations() -> [JoinedConversation] {
        return Array(joinedConversations.values).sorted { $0.joinedAt > $1.joinedAt }
    }
    
    /// Get favorite conversations only
    func getFavoriteConversations() -> [JoinedConversation] {
        return joinedConversations.values.compactMap { joinedConv in
            joinedConv.isFavorite ? joinedConv : nil
        }.sorted { $0.conversation.displayName < $1.conversation.displayName }
    }
    
    /// Join a conversation
    func joinConversation(_ conversation: Conversation) {
        let joinedConversation = JoinedConversation(conversation: conversation)
        joinedConversations[conversation.id] = joinedConversation
        saveJoinedConversations()
    }
    
    /// Leave a conversation
    func leaveConversation(conversationId: Data) {
        joinedConversations.removeValue(forKey: conversationId)
        favoriteConversations.remove(conversationId)
        saveJoinedConversations()
        saveFavoriteConversations()
    }
    
    /// Toggle favorite status for a conversation
    func toggleFavorite(conversationId: Data, isFavorite: Bool? = nil) {
        guard var joinedConv = joinedConversations[conversationId] else { return }
        
        let newFavoriteStatus = isFavorite ?? !joinedConv.isFavorite
        joinedConv.isFavorite = newFavoriteStatus
        joinedConversations[conversationId] = joinedConv
        
        if newFavoriteStatus {
            favoriteConversations.insert(conversationId)
        } else {
            favoriteConversations.remove(conversationId)
        }
        
        saveJoinedConversations()
        saveFavoriteConversations()
    }
    
    /// Toggle mute status for a conversation
    func toggleMute(conversationId: Data, isMuted: Bool? = nil) {
        guard var joinedConv = joinedConversations[conversationId] else { return }
        
        joinedConv.isMuted = isMuted ?? !joinedConv.isMuted
        joinedConversations[conversationId] = joinedConv
        saveJoinedConversations()
    }
    
    /// Mark conversation as read
    func markAsRead(conversationId: Data) {
        guard var joinedConv = joinedConversations[conversationId] else { return }
        
        joinedConv.markAsRead()
        joinedConversations[conversationId] = joinedConv
        saveJoinedConversations()
    }
    
    /// Increment unread count for a conversation
    func incrementUnreadCount(conversationId: Data) {
        guard var joinedConv = joinedConversations[conversationId] else { return }
        
        joinedConv.incrementUnreadCount()
        joinedConversations[conversationId] = joinedConv
        saveJoinedConversations()
    }
    
    /// Get total unread count across all conversations
    func getTotalUnreadCount() -> Int {
        return joinedConversations.values.reduce(0) { $0 + $1.unreadCount }
    }
    
    /// Get unread count for non-muted conversations
    func getUnmutedUnreadCount() -> Int {
        return joinedConversations.values.compactMap { joinedConv in
            joinedConv.isMuted ? nil : joinedConv.unreadCount
        }.reduce(0, +)
    }
    
    // MARK: - Auto-Join System Conversations
    
    /// Automatically join system conversations (Announcements, General) for a campus
    func autoJoinSystemConversations(campusId: String) {
        // Auto-join Announcements
        let announcements = Conversation.announcements(campusId: campusId)
        if !isJoined(announcements.id) {
            joinConversation(announcements)
        }
    }
    
    // MARK: - Persistence
    
    private func saveJoinedConversations() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            // Convert Data keys to hex strings for JSON serialization
            let serializableDict = Dictionary(uniqueKeysWithValues: 
                joinedConversations.map { (key, value) in
                    (key.hexEncodedString(), value)
                }
            )
            
            let data = try encoder.encode(serializableDict)
            UserDefaults.standard.set(data, forKey: joinedConversationsKey)
            UserDefaults.standard.synchronize()
        } catch {
            print("Failed to save joined conversations: \(error)")
        }
    }
    
    private func loadJoinedConversations() {
        guard let data = UserDefaults.standard.data(forKey: joinedConversationsKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let serializableDict = try decoder.decode([String: JoinedConversation].self, from: data)
            
            // Convert hex string keys back to Data
            joinedConversations = Dictionary(uniqueKeysWithValues:
                serializableDict.compactMap { (hexKey, value) in
                    guard let key = Data(hexString: hexKey) else { return nil }
                    return (key, value)
                }
            )
            
            // Rebuild favorites set
            favoriteConversations = Set(
                joinedConversations.compactMap { (key, value) in
                    value.isFavorite ? key : nil
                }
            )
            
        } catch {
            print("Failed to load joined conversations: \(error)")
            // Reset to empty state on error
            joinedConversations = [:]
            favoriteConversations = []
        }
    }
    
    private func saveFavoriteConversations() {
        let favoriteHexStrings = favoriteConversations.map { $0.hexEncodedString() }
        UserDefaults.standard.set(favoriteHexStrings, forKey: favoriteConversationsKey)
        UserDefaults.standard.synchronize()
    }
}


