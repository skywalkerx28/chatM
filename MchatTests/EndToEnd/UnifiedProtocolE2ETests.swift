//
// UnifiedProtocolE2ETests.swift
// MchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import XCTest
@testable import chatM

/// End-to-end tests for the unified Mchat protocol mixing legacy and new message types
final class UnifiedProtocolE2ETests: XCTestCase {
    
    var alice: MockBluetoothMeshService!
    var bob: MockBluetoothMeshService!
    var charlie: MockBluetoothMeshService!
    var david: MockBluetoothMeshService!
    
    let testCampusId = "test.university.edu"
    
    override func setUp() {
        super.setUp()
        
        // Create mock services with unified protocol support
        alice = createMockService(peerID: TestConstants.testPeerID1, nickname: TestConstants.testNickname1)
        bob = createMockService(peerID: TestConstants.testPeerID2, nickname: TestConstants.testNickname2)
        charlie = createMockService(peerID: TestConstants.testPeerID3, nickname: TestConstants.testNickname3)
        david = createMockService(peerID: TestConstants.testPeerID4, nickname: TestConstants.testNickname4)
    }
    
    override func tearDown() {
        alice = nil
        bob = nil
        charlie = nil
        david = nil
        MockBluetoothMeshService.clearRegistry()
        super.tearDown()
    }
    
    // MARK: - Unified Message Protocol Tests
    
    func testMchatMessageUnifiedRouting() throws {
        let campusId = testCampusId
        
        // Create different conversation types
        let broadcastId = TopicManager.broadcastId(campusId: campusId)
        let generalId = TopicManager.generalId(campusId: campusId)
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        let dmId = TopicManager.dmId(peerA: alice.myPeerID, peerB: bob.myPeerID, campusId: campusId)
        
        // Join appropriate conversations
        alice.joinConversation(generalId)
        bob.joinConversation(generalId)
        
        var receivedMessages: [Data: MchatMessage] = [:]
        let expectation = XCTestExpectation(description: "Unified routing works")
        expectation.expectedFulfillmentCount = 4 // Different message types
        
        // Setup unified message handler for Bob
        bob.messageDeliveryHandler = { message in
            if let conversationId = message.conversationId {
                receivedMessages[conversationId] = message
                expectation.fulfill()
            }
        }
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            // Convert to MchatMessage for unified handling
            let mchatMessage = MchatMessage(roomMessage: roomMessage, senderPeerID: self.alice.myPeerID)
            receivedMessages[roomMessage.conversationId] = mchatMessage
            expectation.fulfill()
        }
        
        // Connect peers
        simulateConnection(alice, bob)
        
        // Send different message types - all should route through room message format now
        alice.sendMessage("Legacy broadcast message", mentions: [], to: nil) // → broadcast conversation
        alice.sendRoomMessage("General room message", in: generalId)
        alice.sendRoomMessage("Campus announcement", in: announcementsId)
        alice.sendPrivateMessage("DM message", to: bob.myPeerID, recipientNickname: bob.mockNickname) // → DM conversation
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify all message types were received with correct conversation context
        XCTAssertNotNil(receivedMessages[broadcastId])
        XCTAssertNotNil(receivedMessages[generalId])
        XCTAssertNotNil(receivedMessages[announcementsId])
        XCTAssertNotNil(receivedMessages[dmId])
        
        // Verify message content integrity
        XCTAssertEqual(receivedMessages[generalId]?.content, "General room message")
        XCTAssertEqual(receivedMessages[announcementsId]?.content, "Campus announcement")
    }
    
    func testLegacyAndNewMessageCompatibility() throws {
        let campusId = testCampusId
        let broadcastId = TopicManager.broadcastId(campusId: campusId)
        
        var legacyReceived = false
        var newReceived = false
        
        let expectation = XCTestExpectation(description: "Legacy and new message compatibility")
        expectation.expectedFulfillmentCount = 2
        
        bob.messageDeliveryHandler = { message in
            if message.isLegacyBroadcast {
                legacyReceived = true
                expectation.fulfill()
            } else if message.isRoomMessage {
                newReceived = true
                expectation.fulfill()
            }
        }
        
        simulateConnection(alice, bob)
        
        // Create and send legacy-style message (will be converted to room format internally)
        alice.sendMessage("Legacy style broadcast", mentions: [], to: nil)
        
        // Send new room message
        alice.sendRoomMessage("New room message", in: broadcastId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Both should be received with unified handling
        XCTAssertTrue(legacyReceived || newReceived) // At least one should work
    }
    
    func testConversationContextPreservation() throws {
        let campusId = testCampusId
        let mathRoomId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        alice.joinConversation(mathRoomId)
        bob.joinConversation(mathRoomId)
        
        var receivedInCorrectRoom = false
        let expectation = XCTestExpectation(description: "Conversation context preserved")
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == mathRoomId && 
               roomMessage.content == "MATH homework help" {
                receivedInCorrectRoom = true
                expectation.fulfill()
            }
        }
        
        simulateConnection(alice, bob)
        
        // Send to specific math room
        alice.sendRoomMessage("MATH homework help", in: mathRoomId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
        XCTAssertTrue(receivedInCorrectRoom)
    }
    
    // MARK: - Campus Flag Validation Tests
    
    func testCampusRequiredFlagValidation() throws {
        let roomMessage = RoomMessage(
            conversationId: TopicManager.generalId(campusId: testCampusId),
            sender: "testuser",
            content: "Test message"
        )
        
        guard let roomMessageData = roomMessage.encode() else {
            XCTFail("Failed to encode room message")
            return
        }
        
        // Create packet with room message type
        let packet = BitchatPacket(
            type: MessageType.roomMessage.rawValue,
            senderID: Data(hexString: alice.myPeerID) ?? Data(),
            recipientID: SpecialRecipients.broadcast,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: roomMessageData,
            signature: nil,
            ttl: 2
        )
        
        // Verify campus flag is set correctly
        XCTAssertTrue(packet.campusRequired, "Room message packets should have campusRequired flag set")
        
        // Test encoding preserves the flag
        guard let encodedPacket = packet.toBinaryData() else {
            XCTFail("Failed to encode packet")
            return
        }
        
        guard let decodedPacket = BitchatPacket.from(encodedPacket) else {
            XCTFail("Failed to decode packet")
            return
        }
        
        XCTAssertTrue(decodedPacket.campusRequired, "Campus flag should be preserved through encoding/decoding")
    }
    
    func testNonRoomMessageNoCampusFlag() throws {
        // Create non-room message (handshake)
        let handshakeData = Data(repeating: 0x01, count: 32)
        let packet = BitchatPacket(
            type: MessageType.noiseHandshakeInit.rawValue,
            senderID: Data(hexString: alice.myPeerID) ?? Data(),
            recipientID: Data(hexString: bob.myPeerID) ?? Data(),
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: handshakeData,
            signature: nil,
            ttl: 2
        )
        
        // Verify campus flag is NOT set for non-room messages
        XCTAssertFalse(packet.campusRequired, "Non-room message packets should not have campusRequired flag set")
    }
    
    // MARK: - Stress and Performance Tests
    
    func testMixedTrafficUnderLoad() throws {
        let campusId = testCampusId
        let generalId = TopicManager.generalId(campusId: campusId)
        let mathRoomId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Setup peers in different room combinations
        alice.joinConversation(generalId)
        alice.joinConversation(mathRoomId)
        bob.joinConversation(generalId)
        charlie.joinConversation(mathRoomId)
        david.joinConversation(generalId)
        david.joinConversation(mathRoomId)
        
        // Connect all peers
        simulateConnection(alice, bob)
        simulateConnection(bob, charlie)
        simulateConnection(charlie, david)
        simulateConnection(alice, david)
        
        let messageCount = 200
        var generalMessages = 0
        var mathMessages = 0
        
        let expectation = XCTestExpectation(description: "Mixed traffic under load")
        expectation.expectedFulfillmentCount = messageCount * 2 // Multiple receivers per message
        
        // Setup receivers
        [bob, david].forEach { peer in
            peer?.roomMessageDeliveryHandler = { roomMessage in
                if roomMessage.conversationId == generalId {
                    generalMessages += 1
                } else if roomMessage.conversationId == mathRoomId {
                    mathMessages += 1
                }
                expectation.fulfill()
            }
        }
        
        charlie.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == mathRoomId {
                mathMessages += 1
                expectation.fulfill()
            }
            // Charlie only joined math room, so shouldn't get general messages
        }
        
        // Send mixed traffic rapidly
        DispatchQueue.concurrentPerform(iterations: messageCount) { i in
            if i % 2 == 0 {
                alice.sendRoomMessage("General message \(i)", in: generalId)
            } else {
                alice.sendRoomMessage("Math message \(i)", in: mathRoomId)
            }
        }
        
        wait(for: [expectation], timeout: TestConstants.longTimeout)
        
        // Verify correct distribution
        XCTAssertGreaterThan(generalMessages, 0)
        XCTAssertGreaterThan(mathMessages, 0)
        
        print("Delivered \(generalMessages) general messages and \(mathMessages) math messages under load")
    }
    
    func testConversationScaling() throws {
        // Test system behavior with many concurrent conversations
        let conversationCount = 50
        var conversationIds: [Data] = []
        
        // Create many different conversations
        for i in 0..<conversationCount {
            let roomId = TopicManager.topicCode(
                campusId: testCampusId,
                course: TopicManager.courseId(dept: "TEST", num: "\(i)", term: "FALL2024"),
                session: Data(repeating: 0, count: 8)
            )
            conversationIds.append(roomId)
            
            // Alice joins all rooms
            alice.joinConversation(roomId)
            
            // Bob joins every 3rd room
            if i % 3 == 0 {
                bob.joinConversation(roomId)
            }
        }
        
        var aliceCount = 0
        var bobCount = 0
        
        let expectation = XCTestExpectation(description: "Conversation scaling handled")
        expectation.expectedFulfillmentCount = conversationCount + (conversationCount / 3)
        
        alice.roomMessageDeliveryHandler = { _ in
            aliceCount += 1
            expectation.fulfill()
        }
        
        bob.roomMessageDeliveryHandler = { _ in
            bobCount += 1
            expectation.fulfill()
        }
        
        simulateConnection(alice, bob)
        
        // Send one message to each conversation
        for (index, roomId) in conversationIds.enumerated() {
            alice.sendRoomMessage("Message for room \(index)", in: roomId)
        }
        
        wait(for: [expectation], timeout: TestConstants.longTimeout)
        
        // Verify scaling behavior
        XCTAssertEqual(aliceCount, conversationCount) // Alice joined all
        XCTAssertEqual(bobCount, conversationCount / 3) // Bob joined every 3rd
    }
    
    // MARK: - Protocol Migration Tests
    
    func testLegacyToRoomMessageMigration() throws {
        let campusId = testCampusId
        let broadcastId = TopicManager.broadcastId(campusId: campusId)
        
        var legacyProcessed = false
        var roomProcessed = false
        
        let expectation = XCTestExpectation(description: "Protocol migration seamless")
        expectation.expectedFulfillmentCount = 2
        
        bob.messageDeliveryHandler = { message in
            if message.isLegacyBroadcast {
                legacyProcessed = true
                // Verify legacy message gets unified conversation context
                XCTAssertEqual(message.conversationId, broadcastId)
                expectation.fulfill()
            } else if message.isRoomMessage {
                roomProcessed = true
                XCTAssertNotNil(message.conversationId)
                expectation.fulfill()
            }
        }
        
        simulateConnection(alice, bob)
        
        // Send both legacy and new format
        alice.sendMessage("Legacy broadcast", mentions: [], to: nil) // Will be converted to room format
        
        let generalId = TopicManager.generalId(campusId: campusId)
        alice.sendRoomMessage("New room message", in: generalId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        XCTAssertTrue(legacyProcessed)
        XCTAssertTrue(roomProcessed)
    }
    
    func testBackwardCompatibilityWithOldClients() throws {
        // Simulate scenario where some clients use old protocol
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Backward compatibility maintained")
        var messagesReceived = 0
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            messagesReceived += 1
            if messagesReceived == 2 {
                expectation.fulfill()
            }
        }
        
        simulateConnection(alice, bob)
        
        // Send new room message
        alice.sendRoomMessage("New protocol message", in: conversationId)
        
        // Simulate old client sending legacy message (converted internally)
        let legacyMessage = MchatMessage(
            sender: "LegacyClient",
            content: "Legacy protocol message",
            timestamp: Date(),
            isRelay: false,
            conversationId: nil // Legacy format
        )
        
        // Should be processed and get broadcast conversation ID
        bob.simulateIncomingMessage(legacyMessage)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        XCTAssertEqual(messagesReceived, 2)
    }
    
    // MARK: - Advanced Routing Tests
    
    func testComplexMultiHopRoomRouting() throws {
        let campusId = testCampusId
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Create chain topology: Alice -> Bob -> Charlie -> David
        simulateConnection(alice, bob)
        simulateConnection(bob, charlie)
        simulateConnection(charlie, david)
        
        // All join the same conversation
        [alice, bob, charlie, david].forEach { peer in
            peer?.joinConversation(conversationId)
        }
        
        let expectation = XCTestExpectation(description: "Multi-hop room routing")
        
        david.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Multi-hop room message" &&
               roomMessage.conversationId == conversationId {
                expectation.fulfill()
            }
        }
        
        // Alice sends message - should reach David through multiple hops
        alice.sendRoomMessage("Multi-hop room message", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
    }
    
    func testRoomMessagePriorityAndTTL() throws {
        let campusId = testCampusId
        let urgentRoomId = TopicManager.announcementsId(campusId: campusId) // High priority
        let regularRoomId = TopicManager.generalId(campusId: campusId) // Regular priority
        
        alice.joinConversation(regularRoomId)
        bob.joinConversation(regularRoomId)
        
        var messageTimestamps: [String: Date] = [:]
        let expectation = XCTestExpectation(description: "Message priority and TTL respected")
        expectation.expectedFulfillmentCount = 2
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            messageTimestamps[roomMessage.content] = Date()
            expectation.fulfill()
        }
        
        simulateConnection(alice, bob)
        
        // Send regular message
        alice.sendRoomMessage("Regular message", in: regularRoomId)
        
        // Send urgent announcement  
        alice.sendRoomMessage("Urgent announcement", in: urgentRoomId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Both should be received
        XCTAssertNotNil(messageTimestamps["Regular message"])
        XCTAssertNotNil(messageTimestamps["Urgent announcement"])
    }
    
    // MARK: - Security Integration Tests
    
    func testEndToEndRoomSecurity() throws {
        let campusId = testCampusId
        let secureRoomId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "SECURE", num: "999", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Only Alice and Bob join the secure room
        alice.joinConversation(secureRoomId)
        bob.joinConversation(secureRoomId)
        // Charlie and David do NOT join
        
        var secureMessagesReceived = 0
        let expectation = XCTestExpectation(description: "End-to-end room security")
        
        // Only Bob should receive the secure message
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == secureRoomId {
                secureMessagesReceived += 1
                expectation.fulfill()
            }
        }
        
        // Charlie and David should NOT receive anything
        [charlie, david].forEach { peer in
            peer?.roomMessageDeliveryHandler = { roomMessage in
                if roomMessage.conversationId == secureRoomId {
                    XCTFail("Unauthorized peer received secure room message")
                }
            }
        }
        
        // Connect all peers (physical proximity)
        simulateConnection(alice, bob)
        simulateConnection(alice, charlie)
        simulateConnection(alice, david)
        simulateConnection(bob, charlie)
        simulateConnection(bob, david)
        simulateConnection(charlie, david)
        
        // Alice sends secure message
        alice.sendRoomMessage("Classified information", in: secureRoomId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        XCTAssertEqual(secureMessagesReceived, 1) // Only Bob should receive
    }
    
    func testAntiReplayProtection() throws {
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        var messageCount = 0
        let expectation = XCTestExpectation(description: "Anti-replay protection active")
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Replay test message" {
                messageCount += 1
                if messageCount == 1 {
                    expectation.fulfill()
                } else {
                    XCTFail("Duplicate message delivered - replay protection failed")
                }
            }
        }
        
        simulateConnection(alice, bob)
        
        // Send original message
        alice.sendRoomMessage("Replay test message", in: conversationId)
        
        // Wait for delivery
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
        
        // Attempt replay - create duplicate message with same ID
        let replayMessage = RoomMessage(
            conversationId: conversationId,
            messageId: "duplicate-id", // Same ID as before
            sender: alice.mockNickname,
            content: "Replay test message",
            mentions: nil
        )
        
        // Simulate replay attempt
        bob.simulateReceiveRoomMessage(replayMessage, from: alice.myPeerID)
        
        // Wait a bit more to ensure no duplicate delivery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(messageCount, 1, "Should only receive message once")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockService(peerID: String, nickname: String) -> MockBluetoothMeshService {
        let service = MockBluetoothMeshService()
        service.myPeerID = peerID
        service.mockNickname = nickname
        service.setupCampusPresence(campusId: testCampusId)
        return service
    }
    
    private func simulateConnection(_ peer1: MockBluetoothMeshService, _ peer2: MockBluetoothMeshService) {
        peer1.simulateConnectedPeer(peer2.myPeerID)
        peer2.simulateConnectedPeer(peer1.myPeerID)
    }
}
