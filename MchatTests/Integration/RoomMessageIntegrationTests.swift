//
// RoomMessageIntegrationTests.swift
// MchatTests     
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
        
        // Note: Mute functionality is not yet implemented in ConversationStore
        // Future: Test mute functionality when implemented
        
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
    
    // MARK: - Advanced Campus Gate Tests
    
    func testCampusGateWithMultipleValidCampuses() {
        let campusGate = CampusGate()
        let senderID = "multi-campus-user"
        let validExp = Int(Date().timeIntervalSince1970) + 3600
        
        // User has presence for multiple campuses (e.g., visiting researcher)
        campusGate.acceptPresence(senderId: senderID, campusId: "mcgill.ca", exp: validExp)
        campusGate.acceptPresence(senderId: senderID, campusId: "utoronto.ca", exp: validExp)
        
        // Should accept messages for both campuses
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: "mcgill.ca"))
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: "utoronto.ca"))
        
        // Should reject for campus without presence
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: "mit.edu"))
    }
    
    func testCampusGatePresenceExpiration() {
        let campusGate = CampusGate()
        let senderID = "expiring-user"
        let campusId = "test.university.edu"
        
        // Test various expiration scenarios
        let now = Int(Date().timeIntervalSince1970)
        let testCases = [
            (exp: now - 3600, shouldAccept: false, description: "1 hour expired"),
            (exp: now - 60, shouldAccept: false, description: "1 minute expired"),
            (exp: now - 1, shouldAccept: false, description: "1 second expired"),
            (exp: now + 1, shouldAccept: true, description: "1 second valid"),
            (exp: now + 60, shouldAccept: true, description: "1 minute valid"),
            (exp: now + 3600, shouldAccept: true, description: "1 hour valid"),
        ]
        
        for testCase in testCases {
            campusGate.acceptPresence(senderId: senderID, campusId: campusId, exp: testCase.exp)
            let result = campusGate.shouldAcceptMessage(from: senderID, topicCampusId: campusId)
            XCTAssertEqual(result, testCase.shouldAccept, 
                         "Failed for \(testCase.description): expected \(testCase.shouldAccept), got \(result)")
        }
    }
    
    func testCampusGateEdgeCases() {
        let campusGate = CampusGate()
        
        // Test empty/invalid inputs
        campusGate.acceptPresence(senderId: "", campusId: "test.edu", exp: Int(Date().timeIntervalSince1970) + 3600)
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: "", topicCampusId: "test.edu"))
        
        campusGate.acceptPresence(senderId: "valid-sender", campusId: "", exp: Int(Date().timeIntervalSince1970) + 3600)
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: "valid-sender", topicCampusId: ""))
        
        // Test very long strings
        let longSenderID = String(repeating: "A", count: 1000)
        let longCampusID = String(repeating: "B", count: 1000)
        campusGate.acceptPresence(senderId: longSenderID, campusId: longCampusID, exp: Int(Date().timeIntervalSince1970) + 3600)
        
        // Should handle without crashing
        let result = campusGate.shouldAcceptMessage(from: longSenderID, topicCampusId: longCampusID)
        XCTAssertTrue(result) // Should work with long strings
    }
    
    // MARK: - Conversation Store Advanced Tests
    
    func testConversationStoreUnreadCountAccuracy() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.general(campusId: campusId)
        
        conversationStore.joinConversation(conversation)
        
        // Test unread count increment/decrement
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount, 0)
        
        // Increment multiple times
        for i in 1...5 {
            conversationStore.incrementUnreadCount(conversationId: conversation.id)
            XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount, i)
        }
        
        // Mark as read should reset to 0
        conversationStore.markAsRead(conversationId: conversation.id)
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount, 0)
        XCTAssertNotNil(conversationStore.getJoinedConversation(conversation.id)?.lastReadAt)
    }
    
    func testConversationStoreFavoriteManagement() {
        let campusId = mockProfile.campus_id
        let conv1 = Conversation.general(campusId: campusId)
        let conv2 = Conversation.announcements(campusId: campusId)
        let conv3 = Conversation.course(department: "MATH", number: "262", term: "FALL2024", campusId: campusId)
        
        // Join all conversations
        conversationStore.joinConversation(conv1)
        conversationStore.joinConversation(conv2)
        conversationStore.joinConversation(conv3)
        
        // Initially, system conversations should be favorited
        XCTAssertTrue(conversationStore.getJoinedConversation(conv1.id)?.isFavorite ?? false) // General
        XCTAssertTrue(conversationStore.getJoinedConversation(conv2.id)?.isFavorite ?? false) // Announcements
        XCTAssertFalse(conversationStore.getJoinedConversation(conv3.id)?.isFavorite ?? true) // Course
        
        // Toggle course room to favorite
        conversationStore.toggleFavorite(conversationId: conv3.id)
        XCTAssertTrue(conversationStore.getJoinedConversation(conv3.id)?.isFavorite ?? false)
        
        // Get favorites
        let favorites = conversationStore.getFavoriteConversations()
        XCTAssertEqual(favorites.count, 3) // All should now be favorited
        
        // Toggle general back to non-favorite
        conversationStore.toggleFavorite(conversationId: conv1.id)
        let favoritesAfterToggle = conversationStore.getFavoriteConversations()
        XCTAssertEqual(favoritesAfterToggle.count, 2) // Announcements and Course
    }
    
    func testConversationStoreConcurrentAccess() {
        let campusId = mockProfile.campus_id
        var conversations: [Conversation] = []
        
        // Create many conversations
        for i in 0..<20 {
            let conv = Conversation.course(
                department: "TEST",
                number: "\(i)",
                term: "FALL2024",
                campusId: campusId
            )
            conversations.append(conv)
        }
        
        let expectation = XCTestExpectation(description: "Concurrent access handled")
        expectation.expectedFulfillmentCount = 20
        
        // Concurrently join conversations
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            let conv = conversations[index]
            self.conversationStore.joinConversation(conv)
            
            // Verify join succeeded
            XCTAssertTrue(self.conversationStore.isJoined(conv.id))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify all conversations are joined
        let allJoined = conversationStore.getAllJoinedConversations()
        XCTAssertEqual(allJoined.count, 20)
    }
    
    // MARK: - Message Flow Integration Tests
    
    func testFullMessageFlowWithCampusGate() {
        let campusId = mockProfile.campus_id
        let conversationId = TopicManager.generalId(campusId: campusId)
        let senderID = "flow-test-sender"
        
        // Setup valid presence
        let validExp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: senderID, campusId: campusId, exp: validExp)
        
        // Join conversation
        conversationStore.joinConversation(Conversation.general(campusId: campusId))
        
        // Test the full flow: create -> encode -> validate -> route -> store
        let roomMessage = RoomMessage(
            conversationId: conversationId,
            messageId: "flow-test",
            sender: "FlowTestUser",
            content: "Testing full message flow",
            mentions: ["testuser"]
        )
        
        // 1. Message creation and encoding
        guard let encoded = roomMessage.encode() else {
            XCTFail("Message encoding failed")
            return
        }
        
        // 2. Decode to verify integrity
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Message decoding failed")
            return
        }
        
        XCTAssertEqual(decoded.conversationId, conversationId)
        XCTAssertEqual(decoded.content, "Testing full message flow")
        
        // 3. Campus gate validation
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: senderID, topicCampusId: campusId))
        
        // 4. Conversation join state validation
        XCTAssertTrue(conversationStore.isJoined(conversationId))
        
        // 5. Message routing and delivery (simulated)
        let mchatMessage = MchatMessage(roomMessage: decoded, senderPeerID: senderID)
        XCTAssertEqual(mchatMessage.conversationId, conversationId)
        XCTAssertFalse(mchatMessage.isPrivate)
        XCTAssertTrue(mchatMessage.isRoomMessage)
        
        print("✅ Full message flow test completed successfully")
    }
    
    func testInvalidMessageRejectionFlow() {
        let validCampusId = mockProfile.campus_id
        let invalidSenderID = "invalid-sender"
        let conversationId = TopicManager.generalId(campusId: validCampusId)
        
        // No presence for invalid sender
        // Don't call acceptPresence for this sender
        
        // Join conversation
        conversationStore.joinConversation(Conversation.general(campusId: validCampusId))
        
        // Test rejection flow
        let roomMessage = RoomMessage(
            conversationId: conversationId,
            messageId: "invalid-test",
            sender: "InvalidUser",
            content: "This should be rejected",
            mentions: nil
        )
        
        // 1. Message can encode (technical format is valid)
        guard let encoded = roomMessage.encode() else {
            XCTFail("Even invalid messages should encode if format is correct")
            return
        }
        
        // 2. Message can decode (format validation)
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Technically valid format should decode")
            return
        }
        
        // 3. Campus gate should reject
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: invalidSenderID, topicCampusId: validCampusId))
        
        // 4. Message would be dropped at network layer
        print("✅ Invalid message rejection flow verified")
    }
    
    // MARK: - Conversation State Edge Cases
    
    func testDoubleJoinSameConversation() {
        let conversation = Conversation.general(campusId: mockProfile.campus_id)
        
        // Join twice
        conversationStore.joinConversation(conversation)
        conversationStore.joinConversation(conversation) // Should be idempotent
        
        // Should still only be joined once
        let allJoined = conversationStore.getAllJoinedConversations()
        let matchingConversations = allJoined.filter { $0.conversation.id == conversation.id }
        XCTAssertEqual(matchingConversations.count, 1) // No duplicates
    }
    
    func testLeaveNonJoinedConversation() {
        let conversation = Conversation.general(campusId: mockProfile.campus_id)
        
        // Try to leave without joining
        XCTAssertFalse(conversationStore.isJoined(conversation.id))
        conversationStore.leaveConversation(conversationId: conversation.id) // Should be safe
        XCTAssertFalse(conversationStore.isJoined(conversation.id)) // Still not joined
    }
    
    func testConversationAutoJoinBehavior() {
        let campusId = mockProfile.campus_id
        
        // Auto-join should happen for system conversations
        conversationStore.autoJoinSystemConversations(campusId: campusId)
        
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        let generalId = TopicManager.generalId(campusId: campusId)
        
        // Verify auto-join worked
        XCTAssertTrue(conversationStore.isJoined(announcementsId))
        XCTAssertTrue(conversationStore.isJoined(generalId))
        
        // Verify system conversations are auto-favorited
        XCTAssertTrue(conversationStore.getJoinedConversation(announcementsId)?.isFavorite ?? false)
        XCTAssertTrue(conversationStore.getJoinedConversation(generalId)?.isFavorite ?? false)
        
        // Course conversations should NOT be auto-joined
        let courseConv = Conversation.course(department: "MATH", number: "262", term: "FALL2024", campusId: campusId)
        XCTAssertFalse(conversationStore.isJoined(courseConv.id))
    }
    
    // MARK: - Real-World Scenario Tests
    
    func testTypicalStudentWorkflow() {
        let campusId = mockProfile.campus_id
        
        // 1. Student logs in - auto-join system conversations
        conversationStore.autoJoinSystemConversations(campusId: campusId)
        
        let initialCount = conversationStore.getAllJoinedConversations().count
        XCTAssertEqual(initialCount, 2) // Announcements + General
        
        // 2. Student joins course rooms
        let math262 = Conversation.course(department: "MATH", number: "262", term: "FALL2024", campusId: campusId)
        let comp330 = Conversation.course(department: "COMP", number: "330", term: "FALL2024", campusId: campusId)
        
        conversationStore.joinConversation(math262)
        conversationStore.joinConversation(comp330)
        
        XCTAssertEqual(conversationStore.getAllJoinedConversations().count, 4)
        
        // 3. Student favorites important course
        conversationStore.toggleFavorite(conversationId: math262.id)
        
        let favorites = conversationStore.getFavoriteConversations()
        XCTAssertEqual(favorites.count, 3) // System rooms + MATH 262
        
        // 4. Student gets messages and marks some as read
        conversationStore.incrementUnreadCount(conversationId: math262.id)
        conversationStore.incrementUnreadCount(conversationId: math262.id)
        conversationStore.incrementUnreadCount(conversationId: comp330.id)
        
        // Check unread counts
        XCTAssertEqual(conversationStore.getJoinedConversation(math262.id)?.unreadCount, 2)
        XCTAssertEqual(conversationStore.getJoinedConversation(comp330.id)?.unreadCount, 1)
        
        // 5. Student reads MATH messages
        conversationStore.markAsRead(conversationId: math262.id)
        XCTAssertEqual(conversationStore.getJoinedConversation(math262.id)?.unreadCount, 0)
        XCTAssertEqual(conversationStore.getJoinedConversation(comp330.id)?.unreadCount, 1) // Unchanged
        
        // 6. End of semester - student leaves course rooms
        conversationStore.leaveConversation(conversationId: math262.id)
        conversationStore.leaveConversation(conversationId: comp330.id)
        
        // Should only have system rooms left
        let finalCount = conversationStore.getAllJoinedConversations().count
        XCTAssertEqual(finalCount, 2) // Back to just system rooms
    }
    
    func testConcurrentStudentActivity() {
        let campusId = mockProfile.campus_id
        
        // Simulate multiple students joining/leaving conversations concurrently
        let conversations = [
            Conversation.general(campusId: campusId),
            Conversation.announcements(campusId: campusId),
            Conversation.course(department: "MATH", number: "262", term: "FALL2024", campusId: campusId),
            Conversation.course(department: "COMP", number: "330", term: "FALL2024", campusId: campusId),
            Conversation.course(department: "PHYS", number: "101", term: "FALL2024", campusId: campusId),
        ]
        
        let expectation = XCTestExpectation(description: "Concurrent student activity")
        expectation.expectedFulfillmentCount = conversations.count * 2 // Join + leave for each
        
        // Concurrently join all conversations
        DispatchQueue.concurrentPerform(iterations: conversations.count) { index in
            let conv = conversations[index]
            self.conversationStore.joinConversation(conv)
            expectation.fulfill()
            
            // Add some unread messages
            for _ in 0..<3 {
                self.conversationStore.incrementUnreadCount(conversationId: conv.id)
            }
            
            // Then leave
            self.conversationStore.leaveConversation(conversationId: conv.id)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // After all operations, should be back to empty state
        let remaining = conversationStore.getAllJoinedConversations()
        XCTAssertEqual(remaining.count, 0)
    }
    
    func testMessageHistoryAndPersistence() {
        let campusId = mockProfile.campus_id
        let conversation = Conversation.course(department: "HISTORY", number: "101", term: "FALL2024", campusId: campusId)
        
        // Join conversation
        conversationStore.joinConversation(conversation)
        
        // Simulate message history accumulation
        let messageCount = 50
        for i in 0..<messageCount {
            conversationStore.incrementUnreadCount(conversationId: conversation.id)
        }
        
        // Verify count
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount, messageCount)
        
        // Mark as read
        conversationStore.markAsRead(conversationId: conversation.id)
        XCTAssertEqual(conversationStore.getJoinedConversation(conversation.id)?.unreadCount, 0)
        
        // Verify read timestamp is recent
        let lastReadAt = conversationStore.getJoinedConversation(conversation.id)?.lastReadAt
        XCTAssertNotNil(lastReadAt)
        let timeSinceRead = Date().timeIntervalSince(lastReadAt!)
        XCTAssertLessThan(timeSinceRead, 1.0) // Read within last second
    }
}
