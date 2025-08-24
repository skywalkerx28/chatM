import SwiftUI
import Foundation

struct HomeView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var navigateToChat = false
    @State private var showAnnouncementsRoom = false
    @State private var showRoomsList = false
    @State private var showRoomChat = false
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        Color.black
    }
    
    private var secondaryTextColor: Color { 
        Color.black.opacity(0.6) 
    }
    
    // MARK: - Computed Properties for Announcements
    
    private var announcementsConversation: Conversation? {
        guard let campusId = MembershipCredentialManager.shared.currentProfile()?.campus_id else { return nil }
        return Conversation.announcements(campusId: campusId)
    }
    
    private var announcementsMessages: [BitchatMessage] {
        guard let conversation = announcementsConversation else { return [] }
        return chatViewModel.getMessagesForConversation(conversation.id)
    }
    
    private var recentAnnouncements: [BitchatMessage] {
        // Get the 5 most recent announcements
        return Array(announcementsMessages.suffix(5).reversed())
    }
    
    private var announcementsUnreadCount: Int {
        guard let conversation = announcementsConversation else { return 0 }
        return chatViewModel.unreadRoomMessages.contains(conversation.id) ? 1 : 0
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header
                HStack(alignment: .center) {
                    // Username at top left
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@" + getUsername().uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.primaryred)
                    }
                    
                    Spacer()
                    
                    // Logout button
                    Button(action: {
                        Task {
                            // Sign out from Cognito
                            await AuthService.signOut()
                            // Clear local auth state and tokens
                            await MainActor.run {
                                auth.signOut()
                                MembershipCredentialManager.shared.setProfile(nil)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .foregroundColor(Color.primaryred)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .background(backgroundColor)
                
                // Divider
                Rectangle()
                    .fill(textColor.opacity(0.1))
                    .frame(height: 1)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Main Meshes section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MAIN MESHES")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.primaryred)
                                .padding(.horizontal)
                            
                            // Main rooms list
                            if let campusId = MembershipCredentialManager.shared.currentProfile()?.campus_id {
                                VStack(spacing: 12) {
                                    ForEach(getMainMeshRooms(campusId: campusId), id: \.conversation.id) { roomData in
                                        MainMeshRoomTile(
                                            roomData: roomData,
                                            onAction: { action in
                                                switch action {
                                                case .join:
                                                    ConversationStore.shared.joinConversation(roomData.conversation)
                                                case .open:
                                                    chatViewModel.selectedConversation = roomData.conversation.id
                                                    showRoomChat = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.top, 20)
                        
                        // Announcements section  
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("ANNOUNCEMENTS")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primaryred)
                                
                                // Unread badge
                                if announcementsUnreadCount > 0 {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(Color.orange)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if announcementsConversation != nil {
                                        showAnnouncementsRoom = true
                                    }
                                }) {
                                    Image(systemName: "arrow.up.right.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(textColor)
                                }
                                .accessibilityLabel("Open Announcements room")
                            }
                            .padding(.horizontal)
                            
                            if recentAnnouncements.isEmpty {
                                VStack(spacing: 8) {
                                    Text("NO ANNOUNCEMENTS YET")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    
                                    Text("Campus announcements will appear here")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(secondaryTextColor.opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(.vertical, 20)
                            } else {
                                ForEach(Array(recentAnnouncements.enumerated()), id: \.element.id) { index, message in
                                    AnnouncementMessageCard(message: message) {
                                        if announcementsConversation != nil {
                                            showAnnouncementsRoom = true
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, index < recentAnnouncements.count - 1 ? 8 : 0)
                                }
                                
                                if announcementsMessages.count > 5 {
                                    Button(action: {
                                        if announcementsConversation != nil {
                                            showAnnouncementsRoom = true
                                        }
                                    }) {
                                        Text("VIEW ALL \(announcementsMessages.count) ANNOUNCEMENTS")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(textColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Rooms section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("MY ROOMS")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primaryred)
                                
                                // Unread room messages badge
                                let totalUnreadRooms = chatViewModel.getTotalUnreadRoomCount()
                                if totalUnreadRooms > 0 {
                                    Text("\(totalUnreadRooms)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(backgroundColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(10)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    showRoomsList = true
                                }) {
                                    Image(systemName: "arrow.up.right.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(textColor)
                                }
                                .accessibilityLabel("View all rooms")
                            }
                            .padding(.horizontal)
                            
                            // Show my rooms or prompt to join (excluding Announcements which has its own section)
                            let allMyRooms = ConversationStore.shared.getAllJoinedConversations()
                            let myRooms = allMyRooms.filter { !$0.conversation.isAnnouncements }
                            
                            if myRooms.isEmpty {
                                VStack(spacing: 8) {
                                    Text("NO ROOMS JOINED")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    
                                    Button(action: {
                                        showRoomsList = true
                                    }) {
                                        Text("JOIN YOUR FIRST ROOM")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(textColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(Color.primaryred, lineWidth: 0.5)
                                            )
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal)
                            } else {
                                ForEach(Array(myRooms.prefix(3).enumerated()), id: \.element.conversation.id) { index, joinedConv in
                                    RoomQuickAccessCard(joinedConversation: joinedConv) {
                                        // Open the specific room directly
                                        chatViewModel.selectedConversation = joinedConv.conversation.id
                                        showRoomChat = true
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, index < min(myRooms.count, 3) - 1 ? 8 : 0)
                                }
                                
                                if myRooms.count > 3 {
                                    Button(action: {
                                        showRoomsList = true
                                    }) {
                                        Text("VIEW ALL \(myRooms.count) ROOMS")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(textColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .background(backgroundColor)
            }
            .background(backgroundColor)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { }
        .fullScreenCover(isPresented: $navigateToChat) {
            ContentView()
                .environmentObject(chatViewModel)
        }
        .sheet(isPresented: $showAnnouncementsRoom) {
            if let conversation = announcementsConversation {
                RoomChatView(conversationId: conversation.id, conversation: conversation)
                    .environmentObject(chatViewModel)
            }
        }
        .sheet(isPresented: $showRoomsList) {
            RoomsListView()
                .environmentObject(chatViewModel)
        }
        .sheet(isPresented: $showRoomChat) {
            if let selectedConversationId = chatViewModel.selectedConversation,
               let campusId = MembershipCredentialManager.shared.currentProfile()?.campus_id {
                // Find the conversation from main mesh rooms or joined conversations
                let mainRooms = getMainMeshRooms(campusId: campusId)
                
                // First check main mesh rooms
                if let roomData = mainRooms.first(where: { $0.conversation.id == selectedConversationId }) {
                    RoomChatView(conversationId: selectedConversationId, conversation: roomData.conversation)
                        .environmentObject(chatViewModel)
                } else {
                    // Check joined conversations for other rooms
                    let joinedConversations = ConversationStore.shared.getAllJoinedConversations()
                    if let joinedConv = joinedConversations.first(where: { $0.conversation.id == selectedConversationId }) {
                        RoomChatView(conversationId: selectedConversationId, conversation: joinedConv.conversation)
                            .environmentObject(chatViewModel)
                    }
                }
            }
        }
    }
    
    private func getUsername() -> String {
        // Try to get username from MembershipCredentialManager
        if let profile = MembershipCredentialManager.shared.currentProfile() {
            print("HomeView: Profile found: userId=\(profile.userId), username=\(profile.username)")
            return profile.username
        }
        print("HomeView: No profile found in MembershipCredentialManager")
        
        // Debug: Check if AuthManager thinks we're authenticated
        print("HomeView: AuthManager.isAuthenticated = \(auth.isAuthenticated)")
        
        return "user"
    }
    
    /// Returns the list of main mesh rooms to display in the quick access section
    /// This is extensible - add new main rooms here as they're created
    private func getMainMeshRooms(campusId: String) -> [MainMeshRoomData] {
        var rooms: [MainMeshRoomData] = []
        
        // General room (campus-wide chat)
        let generalConversation = Conversation.general(campusId: campusId)
        let isGeneralJoined = ConversationStore.shared.isJoined(generalConversation.id)
        
        rooms.append(MainMeshRoomData(
            conversation: generalConversation,
            isJoined: isGeneralJoined,
            displayName: "GENERAL",
            description: "Campus-wide general discussions and informal chats with all verified students",
            badge: "CAMPUS-WIDE",
            iconName: "bubble.left.and.bubble.right"
        ))
        
        // Schulich room 
        let schulichConversation = Conversation.schulich(campusId: campusId)
        let isSchulichJoined = ConversationStore.shared.isJoined(schulichConversation.id)
        
        rooms.append(MainMeshRoomData(
            conversation: schulichConversation,
            isJoined: isSchulichJoined,
            displayName: "SCHULICH",
            description: "Schulich School of Business discussions, networking, and academic collaboration",
            badge: "BUSINESS",
            iconName: "building.columns"
        ))
        
        // TODO: Add more main rooms here as they're created
        // Example for future rooms:
        /*
        let studyHallConversation = Conversation.studyHall(campusId: campusId)
        let isStudyHallJoined = ConversationStore.shared.isJoined(studyHallConversation.id)
        
        rooms.append(MainMeshRoomData(
            conversation: studyHallConversation,
            isJoined: isStudyHallJoined,
            displayName: "STUDY HALL",
            description: "Campus study sessions and academic collaboration",
            badge: "ACADEMIC",
            iconName: "book.fill"
        ))
        */
        
        return rooms
    }
}

// MARK: - Data Models

enum MainMeshRoomAction {
    case join
    case open
}

struct MainMeshRoomData {
    let conversation: Conversation
    let isJoined: Bool
    let displayName: String
    let description: String
    let badge: String?
    let iconName: String
}

enum AnnouncementCategory {
    case studyGroup
    case research
    case lostFound
    case tutoring
    case general
    
    var icon: String {
        switch self {
        case .studyGroup: return "book.fill"
        case .research: return "magnifyingglass"
        case .lostFound: return "questionmark.circle"
        case .tutoring: return "graduationcap.fill"
        case .general: return "megaphone.fill"
        }
    }
}

struct Announcement: Identifiable {
    let id: String
    let title: String
    let content: String
    let author: String
    let timestamp: String
    let category: AnnouncementCategory
}

// MARK: - Subviews
private struct MainMeshRoomTile: View {
    let roomData: MainMeshRoomData
    let onAction: (MainMeshRoomAction) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        colorScheme == .dark ? Color.white : Color.black 
    }
    
    private var secondaryTextColor: Color { 
        textColor.opacity(0.6) 
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with room name and badge
            HStack {
                Text(roomData.displayName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Badge (if present)
                if let badge = roomData.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.2))
                        )
                }
            }
            
            // Description
            Text(roomData.description)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action button
            HStack {
                Image(systemName: roomData.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                
                Spacer()
                
                Button(action: {
                    onAction(roomData.isJoined ? .open : .join)
                }) {
                    Text(roomData.isJoined ? "OPEN" : "JOIN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(roomData.isJoined ? .white : textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(roomData.isJoined ? Color.primaryred : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primaryred, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .shadow(color: textColor.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primaryred, lineWidth: 0.5)
                )
        )
    }
}

private struct AnnouncementCard: View {
    let announcement: Announcement
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        Color.black 
    }
    
    private var secondaryTextColor: Color { 
        Color.black.opacity(0.6) 
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header with category icon and timestamp
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: announcement.category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(textColor)
                        
                        Text(announcement.title)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(textColor)
                    }
                    
                    Spacer()
                    
                    Text(announcement.timestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                
                // Content
                Text(announcement.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Author
                HStack {
                    Text("@\(announcement.author)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Spacer()
                    
                    Text("TAP TO REPLY")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Card view for displaying announcement messages from the Announcements room
private struct AnnouncementMessageCard: View {
    let message: BitchatMessage
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        Color.black 
    }
    
    private var secondaryTextColor: Color { 
        Color.black.opacity(0.6) 
    }
    
    private var timeAgoText: String {
        let now = Date()
        let interval = now.timeIntervalSince(message.timestamp)
        
        if interval < 60 {
            return "JUST NOW"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) MIN AGO"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) HOUR\(hours == 1 ? "" : "S") AGO"
        } else {
            let days = Int(interval / 86400)
            return "\(days) DAY\(days == 1 ? "" : "S") AGO"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header with timestamp
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 12))
                            .foregroundColor(textColor)
                        
                        Text("CAMPUS ANNOUNCEMENT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(textColor)
                    }
                    
                    Spacer()
                    
                    Text(timeAgoText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                
                // Content (truncated for home view)
                Text(message.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Author
                HStack {
                    Text("@\(message.sender)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Spacer()
                    
                    Text("TAP TO VIEW ROOM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Quick access card for favorite rooms on the home screen
private struct RoomQuickAccessCard: View {
    let joinedConversation: ConversationStore.JoinedConversation
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        Color.black 
    }
    
    private var secondaryTextColor: Color { 
        Color.black.opacity(0.6) 
    }
    
    private var conversation: Conversation {
        joinedConversation.conversation
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Room type icon
                    Image(systemName: conversation.isAnnouncements ? "megaphone.fill" : 
                                     conversation.isGeneral ? "message.fill" : "book.fill")
                        .font(.system(size: 12))
                        .foregroundColor(conversation.isAnnouncements ? Color.blue :
                                       conversation.isGeneral ? textColor :
                                       Color.green)
                    
                    Text(conversation.displayName.uppercased())
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Spacer()
                    
                    // Unread count badge
                    if joinedConversation.unreadCount > 0 {
                        Text("\(joinedConversation.unreadCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(backgroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                
                // Room description
                HStack {
                    if conversation.isAnnouncements {
                        Text("Campus-wide announcements")
                    } else if conversation.isGeneral {
                        Text("General campus chat")
                    } else if let courseInfo = conversation.courseInfo {
                        Text("\(courseInfo.department) \(courseInfo.number) • \(courseInfo.term)")
                    } else {
                        Text("Room conversation")
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                
                // Activity indicator
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(secondaryTextColor)
                    
                    if let lastRead = joinedConversation.lastReadAt {
                        Text("Read \(formatTimeAgo(lastRead))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text("Never read")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    HomeView(auth: AuthManager())
        .environmentObject(ChatViewModel())
}
