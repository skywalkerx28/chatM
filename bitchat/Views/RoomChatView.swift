//
// RoomChatView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
import Foundation

/// Individual room/conversation chat view
/// Adapts the main ContentView design for room-specific conversations
struct RoomChatView: View {
    // MARK: - Properties
    
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showPeerList = false
    @State private var showSidebar = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var showMessageActions = false
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: String?
    @State private var lastScrollTime: Date = .distantPast
    @State private var scrollThrottleTimer: Timer?
    @State private var autocompleteDebounceTimer: Timer?
    @State private var showRoomInfo = false
    
    let conversationId: Data
    let conversation: Conversation
    
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
    
    private var roomMessages: [BitchatMessage] {
        return viewModel.getMessagesForConversation(conversationId)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main room chat view
                VStack(spacing: 0) {
                    roomHeaderView
                    Divider()
                    roomMessagesView
                    Divider()
                    roomInputView
                }
                .background(backgroundColor)
                .foregroundColor(textColor)
                
                // Sidebar overlay (peer list)
                HStack(spacing: 0) {
                    // Tap to dismiss area
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSidebar = false
                                sidebarDragOffset = 0
                            }
                        }
                    
                    // Sidebar content
                    if showSidebar || sidebarDragOffset != 0 {
                        roomSidebarView
                            #if os(macOS)
                            .frame(width: min(300, max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.4))
                            #else
                            .frame(width: max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.7)
                            #endif
                            .transition(.move(edge: .trailing))
                    } else {
                        Color.clear
                            #if os(macOS)
                            .frame(width: min(300, max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.4))
                            #else
                            .frame(width: max(0, geometry.size.width.isNaN ? 300 : geometry.size.width) * 0.7)
                            #endif
                    }
                }
                .offset(x: {
                    let dragOffset = sidebarDragOffset.isNaN ? 0 : sidebarDragOffset
                    let width = geometry.size.width.isNaN ? 0 : max(0, geometry.size.width)
                    return showSidebar ? -dragOffset : width - dragOffset
                }())
                .animation(.easeInOut(duration: 0.25), value: showSidebar)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onAppear {
            // Mark conversation as read when view appears
            viewModel.selectConversation(conversationId)
            
            // Focus text field after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            // Mark conversation as read when leaving
            viewModel.markConversationAsRead(conversationId)
            
            // Clean up timers
            scrollThrottleTimer?.invalidate()
            autocompleteDebounceTimer?.invalidate()
        }
        .sheet(isPresented: $showRoomInfo) {
            RoomInfoView(conversation: conversation)
        }
        .confirmationDialog(
            selectedMessageSender.map { "@\($0)" } ?? "Actions",
            isPresented: $showMessageActions,
            titleVisibility: .visible
        ) {
            Button("private message") {
                if let peerID = selectedMessageSenderID {
                    // Switch to private chat with this peer
                    viewModel.startPrivateChat(with: peerID)
                    dismiss() // Go back to main view where private chat will open
                }
            }
            
            Button("hug") {
                if let sender = selectedMessageSender {
                    sendRoomMessage("/hug @\(sender)")
                }
            }
            
            Button("slap") {
                if let sender = selectedMessageSender {
                    sendRoomMessage("/slap @\(sender)")
                }
            }
            
            Button("BLOCK", role: .destructive) {
                if let sender = selectedMessageSender {
                    sendRoomMessage("/block \(sender)")
                }
            }
            
            Button("cancel", role: .cancel) {}
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.width.isNaN ? 0 : value.translation.width
                    if !showSidebar && translation < 0 {
                        sidebarDragOffset = max(translation, -300)
                    } else if showSidebar && translation > 0 {
                        sidebarDragOffset = min(-300 + translation, 0)
                    }
                }
                .onEnded { value in
                    let translation = value.translation.width.isNaN ? 0 : value.translation.width
                    let velocity = value.velocity.width.isNaN ? 0 : value.velocity.width
                    withAnimation(.easeOut(duration: 0.2)) {
                        if !showSidebar {
                            if translation < -100 || (translation < -50 && velocity < -500) {
                                showSidebar = true
                                sidebarDragOffset = 0
                            } else {
                                sidebarDragOffset = 0
                            }
                        } else {
                            if translation > 100 || (translation > 50 && velocity > 500) {
                                showSidebar = false
                                sidebarDragOffset = 0
                            } else {
                                sidebarDragOffset = 0
                            }
                        }
                    }
                }
        )
    }
    
    // MARK: - Room Header View
    
    private var roomHeaderView: some View {
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
            
            // Room name and info
            Button(action: { showRoomInfo = true }) {
                HStack(spacing: 4) {
                    // Room type icon
                    Image(systemName: conversation.isAnnouncements ? "megaphone.fill" : 
                                     conversation.isGeneral ? "message.fill" : "book.fill")
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                    
                    Text(conversation.displayName)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Room: \(conversation.displayName)")
            .accessibilityHint("Tap for room information")
            
            Spacer()
            
            // Participant count and room controls
            HStack(spacing: 8) {
                // Unread indicator for other rooms
                let totalUnreadCount = viewModel.getTotalUnreadRoomCount()
                if totalUnreadCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "message.badge.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.orange)
                        
                        Text("\(totalUnreadCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.orange)
                    }
                    .accessibilityLabel("\(totalUnreadCount) unread room messages")
                }
                
                // Participant count (approximate based on connected peers)
                let participantCount = viewModel.connectedPeers.count + 1 // +1 for self
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    Text("\(participantCount)")
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundColor(participantCount > 1 ? textColor : Color.primaryred)
                .accessibilityLabel("\(participantCount) participants")
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar.toggle()
                        sidebarDragOffset = 0
                    }
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(backgroundColor.opacity(0.95))
    }
    
    // MARK: - Room Messages View
    
    private var roomMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Show room messages with windowing for performance
                    let windowedMessages = roomMessages.suffix(100)
                    
                    ForEach(windowedMessages, id: \.id) { message in
                        VStack(alignment: .leading, spacing: 0) {
                            if message.sender == "system" {
                                // System messages
                                Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                // Regular room messages with natural text wrapping
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .top, spacing: 0) {
                                        // Single text view for natural wrapping
                                        Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // Delivery status indicator for our own messages
                                        if message.sender == viewModel.nickname,
                                           let status = message.deliveryStatus {
                                            DeliveryStatusView(status: status, colorScheme: colorScheme)
                                                .padding(.leading, 4)
                                        }
                                    }
                                    
                                    // Check for plain URLs for link previews
                                    let urls = message.content.extractURLs()
                                    if !urls.isEmpty {
                                        ForEach(urls.prefix(3).indices, id: \.self) { index in
                                            let urlInfo = urls[index]
                                            LazyLinkPreviewView(url: urlInfo.url, title: nil)
                                                .padding(.top, 3)
                                                .padding(.horizontal, 1)
                                                .id("\(message.id)-\(urlInfo.url.absoluteString)")
                                        }
                                    }
                                }
                            }
                        }
                        .id(message.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Only show actions for messages from other users
                            if message.sender != "system" && message.sender != viewModel.nickname {
                                selectedMessageSender = message.sender
                                selectedMessageSenderID = message.senderPeerID
                                showMessageActions = true
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(backgroundColor)
            .onTapGesture(count: 3) {
                // Triple-tap to clear room messages
                viewModel.joinedConversations[conversationId] = []
            }
            .onChange(of: roomMessages.count) { _ in
                if !roomMessages.isEmpty {
                    // Throttle scroll animations to prevent excessive UI updates
                    let now = Date()
                    if now.timeIntervalSince(lastScrollTime) > 0.5 {
                        lastScrollTime = now
                        proxy.scrollTo(roomMessages.suffix(100).last?.id, anchor: .bottom)
                    } else {
                        // Schedule a delayed scroll
                        scrollThrottleTimer?.invalidate()
                        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            lastScrollTime = Date()
                            proxy.scrollTo(roomMessages.suffix(100).last?.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Room Input View
    
    private var roomInputView: some View {
        VStack(spacing: 0) {
            // @mentions autocomplete (reuse existing logic)
            if viewModel.showAutocomplete && !viewModel.autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.autocompleteSuggestions.prefix(4)), id: \.self) { suggestion in
                        Button(action: {
                            _ = viewModel.completeNickname(suggestion, in: &messageText)
                        }) {
                            HStack {
                                Text("@\(suggestion)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(textColor)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(Color.gray.opacity(0.1))
                    }
                }
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
            }
            
            HStack(alignment: .center, spacing: 4) {
                TextField("type a message to \(conversation.displayName)...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(textColor)
                    .focused($isTextFieldFocused)
                    .padding(.leading, 12)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: messageText) { newValue in
                        // Cancel previous debounce timer
                        autocompleteDebounceTimer?.invalidate()
                        
                        // Debounce autocomplete updates
                        autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                            let cursorPosition = newValue.count
                            viewModel.updateAutocomplete(for: newValue, cursorPosition: cursorPosition)
                        }
                    }
                    .onSubmit {
                        sendRoomMessage()
                    }
                
                Button(action: { sendRoomMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(messageText.isEmpty ? Color.gray : textColor)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .accessibilityLabel("Send message to \(conversation.displayName)")
                .accessibilityHint(messageText.isEmpty ? "Enter a message to send" : "Double tap to send")
            }
            .padding(.vertical, 8)
            .background(backgroundColor.opacity(0.95))
        }
    }
    
    // MARK: - Room Sidebar View
    
    private var roomSidebarView: some View {
        HStack(spacing: 0) {
            // Grey vertical bar for visual continuity
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("PARTICIPANTS")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor)
                    Spacer()
                }
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(backgroundColor.opacity(0.95))
                
                Divider()
                
                // Participants list
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        // Room info section
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: conversation.isAnnouncements ? "megaphone.fill" : 
                                                 conversation.isGeneral ? "message.fill" : "book.fill")
                                    .font(.system(size: 10))
                                Text("ROOM INFO")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(secondaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Name: \(conversation.displayName)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(textColor)
                                
                                Text("ID: \(conversationId.hexEncodedString().prefix(16))...")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                
                                if let courseInfo = conversation.courseInfo {
                                    Text("Course: \(courseInfo.department)-\(courseInfo.number)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(textColor)
                                    
                                    Text("Term: \(courseInfo.term)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                }
                                
                                Text("Campus: \(conversation.campusId)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                        
                        Divider()
                            .padding(.horizontal, 12)
                        
                        // Participants section
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10))
                                Text("PARTICIPANTS")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(secondaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            
                            // Show yourself first
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor)
                                
                                Text("\(viewModel.nickname) (you)")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(textColor)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            
                            // Show connected peers
                            if viewModel.connectedPeers.isEmpty {
                                Text("nobody else online...")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                            } else {
                                let peerNicknames = viewModel.meshService.getPeerNicknames()
                                
                                ForEach(viewModel.connectedPeers, id: \.self) { peerID in
                                    let peerNickname = peerNicknames[peerID] ?? "anon\(peerID.prefix(4))"
                                    
                                    HStack(spacing: 4) {
                                        // Connection indicator
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(textColor)
                                        
                                        Text(peerNickname)
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(textColor)
                                        
                                        Spacer()
                                        
                                        // Encryption status
                                        let encryptionStatus = viewModel.getEncryptionStatus(for: peerID)
                                        if let icon = encryptionStatus.icon {
                                            Image(systemName: icon)
                                                .font(.system(size: 10))
                                                .foregroundColor(encryptionStatus == .noiseVerified ? textColor : 
                                                               encryptionStatus == .noiseSecured ? textColor :
                                                               encryptionStatus == .noiseHandshaking ? Color.orange :
                                                               Color.primaryred)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Start private chat with this peer
                                        viewModel.startPrivateChat(with: peerID)
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showSidebar = false
                                            sidebarDragOffset = 0
                                        }
                                        dismiss() // Go back to main view where private chat will open
                                    }
                                    .onTapGesture(count: 2) {
                                        // Show fingerprint on double tap
                                        viewModel.showFingerprint(for: peerID)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            
            Spacer()
        }
        .background(backgroundColor)
    }
    
    // MARK: - Actions
    
    private func sendRoomMessage(_ content: String? = nil) {
        let messageContent = content ?? messageText
        
        // Parse mentions from the content
        let mentions = parseMentions(from: messageContent)
        
        // Send message to this conversation
        viewModel.sendToConversation(messageContent, conversationId: conversationId, mentions: mentions)
        
        // Clear input field only if we used the text field
        if content == nil {
            messageText = ""
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseMentions(from content: String) -> [String] {
        let pattern = "@([\\p{L}0-9_]+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: content, options: [], range: NSRange(location: 0, length: content.count)) ?? []
        
        var mentions: [String] = []
        let peerNicknames = viewModel.meshService.getPeerNicknames()
        let allNicknames = Set(peerNicknames.values).union([viewModel.nickname])
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: content) {
                let mentionedName = String(content[range])
                if allNicknames.contains(mentionedName) {
                    mentions.append(mentionedName)
                }
            }
        }
        
        return Array(Set(mentions)) // Remove duplicates
    }
}

// MARK: - Room Info View

/// Shows detailed information about a room/conversation
struct RoomInfoView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var viewModel: ChatViewModel
    
    private var textColor: Color {
        colorScheme == .dark ? Color.primaryred : Color.primaryred
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.primaryred.opacity(0.8) : Color.primaryred.opacity(0.8)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Room identity
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROOM IDENTITY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Name:")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                Text(conversation.displayName)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(textColor)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Type:")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                Text(conversation.isAnnouncements ? "Announcements" : 
                                     conversation.isGeneral ? "General Chat" : "Course Room")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(textColor)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Campus:")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                Text(conversation.campusId)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(textColor)
                                Spacer()
                            }
                        }
                    }
                    
                    // Course details (if applicable)
                    if let courseInfo = conversation.courseInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COURSE DETAILS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Course:")
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                    Text("\(courseInfo.department)-\(courseInfo.number)")
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(textColor)
                                    Spacer()
                                }
                                
                                HStack {
                                    Text("Term:")
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(secondaryTextColor)
                                    Text(courseInfo.term)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(textColor)
                                    Spacer()
                                }
                                
                                if let sessionInfo = courseInfo.sessionInfo {
                                    HStack {
                                        Text("Session:")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(secondaryTextColor)
                                        Text("\(sessionInfo.slot)")
                                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                                            .foregroundColor(textColor)
                                        Spacer()
                                    }
                                    
                                    HStack {
                                        Text("Location:")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(secondaryTextColor)
                                        Text("\(sessionInfo.building) \(sessionInfo.room)")
                                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                                            .foregroundColor(textColor)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Technical details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TECHNICAL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Conversation ID:")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                            
                            Text(conversation.idHex)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.gray)
                                .textSelection(.enabled)
                        }
                    }
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        // Toggle favorite
                        Button(action: {
                            ConversationStore.shared.toggleFavorite(conversationId: conversation.id)
                        }) {
                            HStack {
                                let isFavorite = ConversationStore.shared.getJoinedConversation(conversation.id)?.isFavorite ?? false
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .foregroundColor(isFavorite ? Color.yellow : textColor)
                                Text(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(textColor)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(textColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Leave room (only for non-system rooms)
                        if !conversation.isSystemConversation {
                            Button(action: {
                                viewModel.leaveConversation(conversationId: conversation.id)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "door.left.hand.open")
                                        .foregroundColor(Color.primaryred)
                                    Text("Leave Room")
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color.primaryred)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primaryred.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            }
            .background(backgroundColor)
            .navigationTitle("Room Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(textColor)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Announcements Room") {
    let sampleConversation = Conversation.announcements(campusId: "mcgill")
    let mockViewModel = ChatViewModel()
    
    RoomChatView(
        conversationId: sampleConversation.id,
        conversation: sampleConversation
    )
    .environmentObject(mockViewModel)
}

#Preview("Course Room") {
    let sampleConversation = Conversation.course(
        department: "COMP",
        number: "262", 
        term: "FALL2024",
        campusId: "mcgill"
    )
    
    let mockViewModel = ChatViewModel()
    
    RoomChatView(
        conversationId: sampleConversation.id,
        conversation: sampleConversation
    )
    .environmentObject(mockViewModel)
}

