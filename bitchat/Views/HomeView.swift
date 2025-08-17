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
        TrendingSubnet(id: UUID().uuidString, name: "Research Collab", description: "Finding research opportunities and lab positions", memberCount: 112, activity: "")
    ]
    
    // Mock data for announcements
    @State private var announcements: [Announcement] = [
        Announcement(id: UUID().uuidString, title: "STUDY PARTNER NEEDED", content: "Looking for someone to review MATH-262 material before Thursday's midterm", author: "alex_m", timestamp: "10 MIN AGO", category: .studyGroup),
        Announcement(id: UUID().uuidString, title: "RESEARCH PARTICIPANTS", content: "Psych study on memory and learning. 1hr session, $20 compensation. Email psych.study@mail", author: "sarah_lab", timestamp: "45 MIN AGO", category: .research),
        Announcement(id: UUID().uuidString, title: "LOST CALCULATOR", content: "Left my TI-84 in Burnside 1B23 after calc lecture. Please message if found!", author: "john_doe", timestamp: "2 HOURS AGO", category: .lostFound),
        Announcement(id: UUID().uuidString, title: "ECON TUTOR AVAILABLE", content: "Offering tutoring for ECON-230/231. $25/hr, flexible schedule", author: "econ_ta", timestamp: "3 HOURS AGO", category: .tutoring)
    ]
    
    private var backgroundColor: Color { 
        colorScheme == .dark ? Color.black : Color.white 
    }
    
    private var textColor: Color { 
        Color.primaryred 
    }
    
    private var secondaryTextColor: Color { 
        Color.primaryred.opacity(0.8) 
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
                            .foregroundColor(secondaryTextColor)
                        Text(getUsername().uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(textColor)
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
                        .foregroundColor(textColor)
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
                                .foregroundColor(textColor)
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
                                    .foregroundColor(textColor)
                                
                                Spacer()
                                
                                Button(action: {
                                    // TODO: Add new announcement
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(textColor)
                                }
                            }
                            .padding(.horizontal)
                            
                            if announcements.isEmpty {
                                Text("NO ANNOUNCEMENTS YET")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(Array(announcements.prefix(5).enumerated()), id: \.element.id) { index, announcement in
                                    AnnouncementCard(announcement: announcement) {
                                        navigateToChat = true
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, index < 4 && announcements.count > index + 1 ? 8 : 0)
                                }
                                
                                if announcements.count > 5 {
                                    Button(action: {
                                        navigateToChat = true
                                    }) {
                                        Text("VIEW ALL \(announcements.count) ANNOUNCEMENTS")
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
                                    .foregroundColor(textColor)
                                
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
        .fullScreenCover(isPresented: $navigateToChat) {
            ContentView()
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
        Color.primaryred 
    }
    
    private var secondaryTextColor: Color { 
        Color.primaryred.opacity(0.8) 
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
                                .stroke(textColor, lineWidth: 1)
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
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
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
        Color.primaryred 
    }
    
    private var secondaryTextColor: Color { 
        Color.primaryred.opacity(0.8) 
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
                            .stroke(textColor.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
        Color.primaryred 
    }
    
    private var secondaryTextColor: Color { 
        Color.primaryred.opacity(0.8) 
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
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
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
        Color.primaryred 
    }
    
    private var secondaryTextColor: Color { 
        Color.primaryred.opacity(0.8) 
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
