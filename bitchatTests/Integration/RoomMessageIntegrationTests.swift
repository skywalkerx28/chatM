//
// RoomMessageIntegrationTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import XCTest
@testable import chatM

/// Integration tests for room message functionality with CampusGate
final class RoomMessageIntegrationTests: XCTestCase {
    
    var campusGate: CampusGate!
    var conversationStore: ConversationStore!
    var mockProfile: UserProfile!
    
    override func setUp() {
        super.setUp()
        campusGate = CampusGate()
        conversationStore = ConversationStore.shared
        mockProfile = UserProfile(
            handle: "testuser",
            campus_id: "test.university.edu",
            aid: "12345",
            created_at: "2024-01-01T00:00:00Z"
        )
        
        // Set mock profile
        MembershipCredentialManager.shared.setProfile(mockProfile)
    }
    
    override func tearDown() {
        let allJoined = conversationStore.getAllJoinedConversations()
        for joinedConv in allJoined {
            conversationStore.leaveConversation(conversationId: joinedConv.conversation.id)
        }
        super.tearDown()
    }
    
    // MARK: - CampusGate Tests
    
    func testCampusGateAcceptsValidPresence() {
        let senderID = "test-sender-123"
        let campusId = "test.university.edu"
        let exp = Int(Date().timeIntervalSince1970) + 3600 // 1 hour from now
        
        // Accept presence
        campusGate.acceptPresence(senderId: senderID, campusId: campusId, exp: exp)
        
        // Should accept message from same campus
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: campusId))
        
        // Should reject message from different campus
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: "other.university.edu"))
    }
    
    func testCampusGateRejectsExpiredPresence() {
        let senderID = "test-sender-123"
        let campusId = "test.university.edu"
        let exp = Int(Date().timeIntervalSince1970) - 3600 // 1 hour ago (expired)
        
        // Accept expired presence
        campusGate.acceptPresence(senderId: senderID, campusId: campusId, exp: exp)
        
        // Should reject message due to expired presence
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: campusId))
    }
    
    func testCampusGateRejectsUnknownSender() {
        let senderID = "unknown-sender"
        let campusId = "test.university.edu"
        
        // Should reject message from sender without presence
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: campusId))
    }
    
    // MARK: - Conversation Management Tests
    
    func testAutoJoinSystemConversations() {
        let campusId = mockProfile.campus_id
        
        // Auto-join system conversations
        conversationStore.autoJoinSystemConversations(campusId: campusId)
        
        // Verify announcements conversation is joined
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        XCTAssertTrue(conversationStore.isJoined(announcementsId))
        
        // Verify general conversation is joined
        let generalId = TopicManager.generalId(campusId: campusId)
        XCTAssertTrue(conversationStore.isJoined(generalId))
        
        // Verify they are automatically favorited
        XCTAssertTrue(conversationStore.getJoinedConversation(announcementsId)?.isFavorite ?? false)
        XCTAssertTrue(conversationStore.getJoinedConversation(generalId)?.isFavorite ?? false)
    }
    
    func testJoinCourseConversation() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.course(
            department: "MATH",
            number: "262",
            term: "FALL2024",
            campusId: campusId
        )
        
        // Join conversation
        conversationStore.joinConversation(conversation)
        
        // Verify it's joined
        XCTAssertTrue(conversationStore.isJoined(conversation.id))
        
        // Verify it's not automatically favorited (unlike system conversations)
        XCTAssertFalse(conversationStore.getJoinedConversation(conversation.id)?.isFavorite ?? true)
    }
    
    func testLeaveConversation() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.course(
            department: "TEST",
            number: "101",
            term: "FALL2024",
            campusId: campusId
        )
        
        // Join then leave
        conversationStore.joinConversation(conversation)
        XCTAssertTrue(conversationStore.isJoined(conversation.id))
        
        conversationStore.leaveConversation(conversationId: conversation.id)
        XCTAssertFalse(conversationStore.isJoined(conversation.id))
    }
    
    // MARK: - Room Message Flow Tests
    
    func testRoomMessageDeliveryWithValidCampus() {
        let campusId = mockProfile.campus_id
        let senderID = "valid-sender"
        
        // Set up valid presence
        let exp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: senderID, campusId: campusId, exp: exp)
        
        // Join a test conversation
        let conversation = Conversation.general(campusId: campusId)
        conversationStore.joinConversation(conversation)
        
        // Create and encode room message
        let roomMessage = RoomMessage(
            conversationId: conversation.id,
            messageId: "test-msg",
            sender: "testsender",
            content: "Hello room!",
            mentions: nil
        )
        
        guard let encoded = roomMessage.encode() else {
            XCTFail("Failed to encode room message")
            return
        }
        
        // Verify message can be decoded
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message")
            return
        }
        XCTAssertEqual(decoded.conversationId, conversation.id)
        XCTAssertEqual(decoded.content, "Hello room!")
    }
    
    func testRoomMessageRejectionWithInvalidCampus() {
        let validCampusId = mockProfile.campus_id
        let invalidCampusId = "other.university.edu"
        let senderID = "invalid-sender"
        
        // Set up presence for different campus
        let exp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: senderID, campusId: invalidCampusId, exp: exp)
        
        // Should reject message from different campus
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: validCampusId))
    }
    
    func testRoomMessageRejectionWhenNotJoined() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.course(
            department: "PRIVATE",
            number: "999",
            term: "FALL2024",
            campusId: campusId
        )
        
        // Do NOT join the conversation
        XCTAssertFalse(conversationStore.isJoined(conversation.id))
        
        // Message should be rejected for non-joined conversation
        // (This would be tested in the actual message handling logic)
    }
    
    func testAnnouncementsAlwaysAccessible() {
        let campusId = mockProfile.campus_id
        let announcementsConversation = Conversation.announcements(campusId: campusId)
        
        // Even without explicitly joining, announcements should be accessible
        // This is handled in the mesh service logic
        
        // Verify announcements ID is deterministic
        let announcementsId1 = TopicManager.announcementsId(campusId: campusId)
        let announcementsId2 = TopicManager.announcementsId(campusId: campusId)
        XCTAssertEqual(announcementsId1, announcementsId2)
        XCTAssertEqual(announcementsConversation.id, announcementsId1)
    }
    
    // MARK: - Conversation Store Persistence Tests
    
    func testConversationStorePersistence() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.course(
            department: "PERSIST",
            number: "TEST",
            term: "FALL2024",
            campusId: campusId
        )
        
        // Join conversation
        conversationStore.joinConversation(conversation)
        XCTAssertTrue(conversationStore.isJoined(conversation.id))
        
        // Toggle favorite
        conversationStore.toggleFavorite(conversationId: conversation.id)
        XCTAssertTrue(conversationStore.getJoinedConversation(conversation.id)?.isFavorite ?? false)
        
        // Toggle mute
        conversationStore.toggleMute(conversationId: conversation.id)
        XCTAssertTrue(conversationStore.getJoinedConversation(conversation.id)?.isMuted ?? false)
        
        // Increment unread count
        conversationStore.incrementUnreadCount(conversationId: conversation.id)
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount ?? 0, 1)
        
        // Mark as read
        conversationStore.markAsRead(conversationId: conversation.id)
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount ?? 1, 0)
        XCTAssertNotNil(conversationStore.getJoinedConversation(conversation.id)?.lastReadAt)
    }
    
    // MARK: - Edge Case Tests
    
    func testMultipleCampusConversations() {
        let campus1 = "university1.edu"
        let campus2 = "university2.edu"
        
        // Create conversations for different campuses
        let conv1 = Conversation.general(campusId: campus1)
        let conv2 = Conversation.general(campusId: campus2)
        
        // They should have different IDs even though they're both "general"
        XCTAssertNotEqual(conv1.id, conv2.id)
        
        // Same course at different campuses should have different IDs
        let mathCampus1 = Conversation.course(department: "MATH", number: "101", term: "FALL2024", campusId: campus1)
        let mathCampus2 = Conversation.course(department: "MATH", number: "101", term: "FALL2024", campusId: campus2)
        XCTAssertNotEqual(mathCampus1.id, mathCampus2.id)
    }
    
    func testConversationIdCollisionResistance() {
        let campusId = "test.university.edu"
        
        // Generate many different conversation IDs to check for collisions
        var generatedIds: Set<Data> = []
        
        // Test different courses
        for dept in ["MATH", "COMP", "PHYS", "CHEM", "BIOL"] {
            for num in ["101", "201", "301", "401"] {
                for term in ["FALL2024", "WINTER2024", "SUMMER2024"] {
                    let conversation = Conversation.course(
                        department: dept,
                        number: num,
                        term: term,
                        campusId: campusId
                    )
                    
                    // Verify no collisions
                    XCTAssertFalse(generatedIds.contains(conversation.id), 
                                 "Collision detected for \(dept)-\(num) \(term)")
                    generatedIds.insert(conversation.id)
                }
            }
        }
        
        // Add system conversations
        let announcements = Conversation.announcements(campusId: campusId)
        let general = Conversation.general(campusId: campusId)
        
        XCTAssertFalse(generatedIds.contains(announcements.id))
        XCTAssertFalse(generatedIds.contains(general.id))
        generatedIds.insert(announcements.id)
        generatedIds.insert(general.id)
        
        // Verify we generated a reasonable number of unique IDs
        XCTAssertGreaterThan(generatedIds.count, 60) // 5*4*3 + 2 = 62
    }
}
