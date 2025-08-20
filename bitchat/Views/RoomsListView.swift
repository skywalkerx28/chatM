//
// RoomsListView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Displays and manages the list of joined rooms/conversations
struct RoomsListView: View {
    // MARK: - Properties
    
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showJoinRoomSheet = false
    @State private var selectedConversation: Conversation? = nil
    @State private var showRoomChat = false
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.primaryred : Color.primaryred
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.primaryred.opacity(0.8) : Color.primaryred.opacity(0.8)
    }
    
    private var joinedConversations: [ConversationStore.JoinedConversation] {
        return ConversationStore.shared.getAllJoinedConversations()
    }
    
    private var favoriteConversations: [ConversationStore.JoinedConversation] {
        return ConversationStore.shared.getFavoriteConversations()
    }
    
    private var regularConversations: [ConversationStore.JoinedConversation] {
        return joinedConversations.filter { !$0.isFavorite }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header matching app style
                headerView
                
                Divider()
                
                // Rooms list content
                if joinedConversations.isEmpty {
                    emptyStateView
                } else {
                    roomsListContent
                }
            }
            .background(backgroundColor)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showJoinRoomSheet) {
            JoinRoomView()
        }
        .sheet(isPresented: $showRoomChat) {
            if let conversation = selectedConversation {
                RoomChatView(conversationId: conversation.id, conversation: conversation)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 0) {
            // Back button
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Title
            Text("ROOMS")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
            
            Spacer()
            
            // Total unread count and join button
            HStack(spacing: 8) {
                // Unread count badge
                let totalUnread = viewModel.getTotalUnreadRoomCount()
                if totalUnread > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "message.badge.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.orange)
                        
                        Text("\(totalUnread)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.orange)
                    }
                    .accessibilityLabel("\(totalUnread) unread messages")
                }
                
                // Join room button
                Button(action: { showJoinRoomSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(textColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join new room")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(backgroundColor.opacity(0.95))
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "message.fill")
                .font(.system(size: 48))
                .foregroundColor(secondaryTextColor.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Rooms Joined")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                
                Text("Join a room to start chatting with your classmates")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showJoinRoomSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("JOIN A ROOM")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(backgroundColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(textColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Rooms List Content
    
    private var roomsListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Favorites section
                if !favoriteConversations.isEmpty {
                    sectionHeader(title: "FAVORITES", icon: "star.fill")
                    
                    ForEach(favoriteConversations, id: \.conversation.id) { joinedConv in
                        roomRow(joinedConv)
                            .onTapGesture {
                                openRoom(joinedConv.conversation)
                            }
                    }
                    
                    if !regularConversations.isEmpty {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                
                // All rooms section
                if !regularConversations.isEmpty {
                    sectionHeader(title: favoriteConversations.isEmpty ? "JOINED ROOMS" : "OTHER ROOMS", 
                                icon: "message.fill")
                    
                    ForEach(regularConversations, id: \.conversation.id) { joinedConv in
                        roomRow(joinedConv)
                            .onTapGesture {
                                openRoom(joinedConv.conversation)
                            }
                    }
                }
                
                // Join new room section
                Button(action: { showJoinRoomSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                            .foregroundColor(textColor)
                        
                        Text("Join New Room")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(textColor)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(textColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 16)
            }
            .padding(.vertical, 8)
        }
        .background(backgroundColor)
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(secondaryTextColor)
            
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    // MARK: - Room Row
    
    private func roomRow(_ joinedConv: ConversationStore.JoinedConversation) -> some View {
        let conversation = joinedConv.conversation
        let unreadCount = joinedConv.unreadCount
        let hasUnread = unreadCount > 0
        let isSelected = viewModel.selectedConversation == conversation.id
        
        return HStack(spacing: 8) {
            // Room type icon
            VStack {
                Image(systemName: conversation.isAnnouncements ? "megaphone.fill" : 
                                 conversation.isGeneral ? "message.fill" : "book.fill")
                    .font(.system(size: 16))
                    .foregroundColor(conversation.isAnnouncements ? Color.blue :
                                   conversation.isGeneral ? textColor :
                                   Color.green)
                Spacer()
            }
            
            // Room details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayName)
                        .font(.system(size: 14, weight: hasUnread ? .bold : .medium, design: .monospaced))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Unread count badge
                    if hasUnread {
                        Text("\(unreadCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(backgroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                }
                
                // Room description/subtitle
                HStack {
                    if conversation.isAnnouncements {
                        Text("Campus-wide announcements")
                    } else if conversation.isGeneral {
                        Text("General campus chat")
                    } else if let courseInfo = conversation.courseInfo {
                        Text("\(courseInfo.department) \(courseInfo.number) • \(courseInfo.term)")
                    } else {
                        Text(conversation.campusId)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                
                // Last activity indicator
                if let lastRead = joinedConv.lastReadAt {
                    Text("Last read: \(formatRelativeTime(lastRead))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                } else {
                    Text("Never read")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
            
            // Action buttons
            VStack(spacing: 8) {
                // Favorite button
                Button(action: {
                    ConversationStore.shared.toggleFavorite(conversationId: conversation.id)
                }) {
                    Image(systemName: joinedConv.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(joinedConv.isFavorite ? Color.yellow : secondaryTextColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(joinedConv.isFavorite ? "Remove from favorites" : "Add to favorites")
                
                // Mute button
                Button(action: {
                    ConversationStore.shared.toggleMute(conversationId: conversation.id)
                }) {
                    Image(systemName: joinedConv.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                        .font(.system(size: 14))
                        .foregroundColor(joinedConv.isMuted ? Color.orange : secondaryTextColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(joinedConv.isMuted ? "Unmute" : "Mute")
                
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isSelected ? textColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            // Context menu actions
            Button(action: {
                ConversationStore.shared.toggleFavorite(conversationId: conversation.id)
            }) {
                Label(joinedConv.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: joinedConv.isFavorite ? "star.slash" : "star")
            }
            
            Button(action: {
                ConversationStore.shared.toggleMute(conversationId: conversation.id)
            }) {
                Label(joinedConv.isMuted ? "Unmute" : "Mute",
                      systemImage: joinedConv.isMuted ? "speaker.wave.2" : "speaker.slash")
            }
            
            if !conversation.isSystemConversation {
                Divider()
                
                Button(role: .destructive, action: {
                    viewModel.leaveConversation(conversationId: conversation.id)
                }) {
                    Label("Leave Room", systemImage: "door.left.hand.open")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func openRoom(_ conversation: Conversation) {
        selectedConversation = conversation
        showRoomChat = true
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
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

// MARK: - Join Room View

/// Modal view for joining new rooms
struct JoinRoomView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var joinMethod: JoinMethod = .course
    @State private var department = ""
    @State private var courseNumber = ""
    @State private var term = "FALL2024"
    @State private var conversationIdHex = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    enum JoinMethod: CaseIterable {
        case course
        case conversationId
        
        var title: String {
            switch self {
            case .course:
                return "Join by Course"
            case .conversationId:
                return "Join by ID"
            }
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.primaryred : Color.primaryred
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.primaryred.opacity(0.8) : Color.primaryred.opacity(0.8)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Join method picker
                Picker("Join Method", selection: $joinMethod) {
                    ForEach(JoinMethod.allCases, id: \.self) { method in
                        Text(method.title)
                            .tag(method)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Join form based on selected method
                switch joinMethod {
                case .course:
                    courseJoinForm
                case .conversationId:
                    conversationIdJoinForm
                }
                
                Spacer()
                
                // Join button
                Button(action: joinRoom) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("JOIN ROOM")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(backgroundColor)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(textColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canJoin)
            }
            .padding()
            .background(backgroundColor)
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(textColor)
                }
            }
        }
        .alert("Join Room", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Course Join Form
    
    private var courseJoinForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("COURSE INFORMATION")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                
                VStack(spacing: 12) {
                    // Department
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Department (e.g., MATH, COMP)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        
                        TextField("MATH", text: $department)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                    }
                    
                    // Course number
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Course Number")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        
                        TextField("262", text: $courseNumber)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    
                    // Term
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Term")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        
                        TextField("FALL2024", text: $term)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                    }
                }
            }
            
            // Preview
            if !department.isEmpty && !courseNumber.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    Text("Room: \(department.uppercased())-\(courseNumber)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Conversation ID Join Form
    
    private var conversationIdJoinForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONVERSATION ID")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("64-character hex conversation ID")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    TextField("Enter conversation ID...", text: $conversationIdHex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            
            // Validation feedback
            if !conversationIdHex.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: isValidConversationId ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isValidConversationId ? Color.green : Color.red)
                    
                    Text(isValidConversationId ? "Valid conversation ID" : "Invalid format (must be 64 hex characters)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(isValidConversationId ? Color.green : Color.red)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Computed Properties for Join Logic
    
    private var canJoin: Bool {
        switch joinMethod {
        case .course:
            return !department.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !courseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .conversationId:
            return isValidConversationId
        }
    }
    
    private var isValidConversationId: Bool {
        let trimmed = conversationIdHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 64 && trimmed.allSatisfy { char in
            char.isWholeNumber || ("a"..."f").contains(char.lowercased()) || ("A"..."F").contains(char)
        }
    }
    
    // MARK: - Join Action
    
    private func joinRoom() {
        guard let campusId = MembershipCredentialManager.shared.currentProfile()?.campus_id else {
            alertMessage = "No campus profile available. Please ensure you're signed in."
            showingAlert = true
            return
        }
        
        let conversation: Conversation
        
        switch joinMethod {
        case .course:
            let dept = department.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let num = courseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let termValue = term.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            
            conversation = Conversation.course(
                department: dept,
                number: num,
                term: termValue,
                campusId: campusId
            )
            
        case .conversationId:
            guard let conversationIdData = Data(hexString: conversationIdHex.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                alertMessage = "Invalid conversation ID format."
                showingAlert = true
                return
            }
            
            // Create a generic conversation with the provided ID
            conversation = Conversation(
                id: conversationIdData,
                displayName: "Room \(conversationIdHex.prefix(8))",
                campusId: campusId
            )
        }
        
        // Check if already joined
        if ConversationStore.shared.isJoined(conversation.id) {
            alertMessage = "You're already joined to this room."
            showingAlert = true
            return
        }
        
        // Join the conversation
        viewModel.joinConversation(conversation)
        
        dismiss()
    }
}

// MARK: - Extensions

// MARK: - Previews

#Preview("Empty Rooms List") {
    let mockViewModel = ChatViewModel()
    
    RoomsListView()
        .environmentObject(mockViewModel)
}

#Preview("Rooms List with Data") {
    let mockViewModel = ChatViewModel()
    
    RoomsListView()
        .environmentObject(mockViewModel)
        .onAppear {
            // Create some sample conversations and add them to the store
            let announcementsConv = Conversation.announcements(campusId: "mcgill")
            let generalConv = Conversation.general(campusId: "mcgill")
            
            let courseConv = Conversation.course(
                department: "COMP",
                number: "262",
                term: "FALL2024", 
                campusId: "mcgill"
            )
            
            // Add them to the conversation store
            ConversationStore.shared.joinConversation(announcementsConv)
            ConversationStore.shared.joinConversation(generalConv)
            ConversationStore.shared.joinConversation(courseConv)
            
            // Simulate some unread messages
            ConversationStore.shared.incrementUnreadCount(conversationId: announcementsConv.id)
            ConversationStore.shared.incrementUnreadCount(conversationId: announcementsConv.id)
            ConversationStore.shared.incrementUnreadCount(conversationId: courseConv.id)
        }
}

#Preview("Join Room View") {
    let mockViewModel = ChatViewModel()
    
    JoinRoomView()
        .environmentObject(mockViewModel)
}
