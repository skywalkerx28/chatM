import SwiftUI
import Foundation

struct HomeView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var navigateToChat = false
    
    // Mock data for favorites - replace with actual data model later
    @State private var favorites: [Favorite] = [
        Favorite(id: UUID().uuidString, name: "Math-262", lastActivity: "2 hours ago", memberCount: 45),
        Favorite(id: UUID().uuidString, name: "Study Group", lastActivity: "5 hours ago", memberCount: 12),
        Favorite(id: UUID().uuidString, name: "CHEM-233", lastActivity: "1 day ago", memberCount: 8)
    ]
    
    // Mock data for trending subnets
    @State private var trendingSubnets: [TrendingSubnet] = [
        TrendingSubnet(id: UUID().uuidString, name: "COMP-330", description: "Theory of Computation study group discussing automata and complexity", memberCount: 89, activity: ""),
        TrendingSubnet(id: UUID().uuidString, name: "PHYS-232", description: "Heat and waves problem sets collaboration", memberCount: 67, activity: ""),
        TrendingSubnet(id: UUID().uuidString, name: "Midterm Prep", description: "General midterm preparation across all subjects", memberCount: 234, activity: ""),
        TrendingSubnet(id: UUID().uuidString, name: "BIOL-200", description: "Cell biology lab reports and lecture discussions", memberCount: 56, activity: ""),
    ]
    
    @State private var showAnnouncementsRoom = false
    @State private var showRoomsList = false
    
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
                        Text("LOGGED IN AS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.primaryred)
                        Text(getUsername().uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.primaryred)
                    }
                    
                    Spacer()
                    
                    // Logout button
                    Button(action: {
                        Task {
                            await AuthService.signOut()
                            await MainActor.run { auth.isAuthenticated = false }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18, weight: .medium))
                            Text("LOG OUT")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                        // Trending section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TRENDING")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.primaryred)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(trendingSubnets) { subnet in
                                        TrendingCard(subnet: subnet) {
                                            navigateToChat = true
                                        }
                                    }
                                }
                                .padding(.horizontal)
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
                                    if let conversation = announcementsConversation {
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
                                        if let conversation = announcementsConversation {
                                            showAnnouncementsRoom = true
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, index < recentAnnouncements.count - 1 ? 8 : 0)
                                }
                                
                                if announcementsMessages.count > 5 {
                                    Button(action: {
                                        if let conversation = announcementsConversation {
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
                            
                            // Show favorite rooms or prompt to join
                            let favoriteRooms = ConversationStore.shared.getFavoriteConversations()
                            
                            if favoriteRooms.isEmpty {
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
                                ForEach(Array(favoriteRooms.prefix(3).enumerated()), id: \.element.conversation.id) { index, joinedConv in
                                    RoomQuickAccessCard(joinedConversation: joinedConv) {
                                        // Open the specific room
                                        if joinedConv.conversation.isAnnouncements {
                                            showAnnouncementsRoom = true
                                        } else {
                                            showRoomsList = true
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, index < min(favoriteRooms.count, 3) - 1 ? 8 : 0)
                                }
                                
                                if favoriteRooms.count > 3 {
                                    Button(action: {
                                        showRoomsList = true
                                    }) {
                                        Text("VIEW ALL \(favoriteRooms.count) ROOMS")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(textColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Favorites section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("FAVORITES")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primaryred)
                                
                                Spacer()
                                
                                Button(action: {
                                    // TODO: Show available subnets to add to favorites
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(textColor)
                                }
                            }
                            .padding(.horizontal)
                            
                            if favorites.isEmpty {
                                EmptyFavoritesView {
                                    navigateToChat = true
                                }
                                .padding(.horizontal)
                            } else {
                                ForEach(favorites) { favorite in
                                    FavoriteRow(favorite: favorite) {
                                        navigateToChat = true
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
        .onAppear {
            // Auto-join system conversations when HomeView appears
            if let campusId = MembershipCredentialManager.shared.currentProfile()?.campus_id {
                ConversationStore.shared.autoJoinSystemConversations(campusId: campusId)
            }
        }
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
    }
    
    private func getUsername() -> String {
        // Try to get username from MembershipCredentialManager
        if let profile = MembershipCredentialManager.shared.currentProfile() {
            return profile.handle
        }
        return "user"
    }
}

// MARK: - Data Models
struct Favorite: Identifiable {
    let id: String
    let name: String
    let lastActivity: String
    let memberCount: Int
}

struct TrendingSubnet: Identifiable {
    let id: String
    let name: String
    let description: String
    let memberCount: Int
    let activity: String
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
private struct TrendingCard: View {
    let subnet: TrendingSubnet
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
            VStack(alignment: .leading, spacing: 12) {
                // Header with name and activity indicator
                HStack {
                    Text(subnet.name.uppercased())
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Spacer()
                    
                    Text(subnet.activity)
                        .font(.system(size: 16))
                }
                
                // Description
                Text(subnet.description)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Footer with member count
                HStack {
                    Label {
                        Text("\(subnet.memberCount)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(textColor)
                    
                    Spacer()
                    
                    Text("TAP TO JOIN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primaryred, lineWidth: 0.5)
                        )
                }
            }
            .padding(16)
            .frame(width: 280)
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
        .buttonStyle(PlainButtonStyle())
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

private struct FavoriteRow: View {
    let favorite: Favorite
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(favorite.name.uppercased())
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                
                HStack {
                    Label {
                        Text("\(favorite.memberCount)")
                            .font(.system(size: 12, design: .monospaced))
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(secondaryTextColor)
                    
                    Spacer()
                    
                    Text(favorite.lastActivity.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
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
}

private struct EmptyFavoritesView: View {
    let onNavigateToChat: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color { 
        Color.black 
    }
    
    private var secondaryTextColor: Color { 
        Color.black.opacity(0.6) 
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 40))
                .foregroundColor(secondaryTextColor)
            
            Text("NO FAVORITES YET")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor)
            
            Text("Your most interacted subnets will appear here")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
            
            Button(action: onNavigateToChat) {
                Text("GO TO PUBLIC CHAT")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(textColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    HomeView(auth: AuthManager())
        .environmentObject(ChatViewModel())
}
