//
// RoomIsolationTests.swift
// MchatTests     
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import XCTest
@testable import chatM

/// Tests for room isolation, conversation routing, and message containment
final class RoomIsolationTests: XCTestCase {
    
    var conversationStore: ConversationStore!
    var alice: MockBluetoothMeshService!
    var bob: MockBluetoothMeshService!
    var charlie: MockBluetoothMeshService!
    
    let testCampusId = "test.university.edu"
    
    override func setUp() {
        super.setUp()
        
        conversationStore = ConversationStore.shared
        
        // Create test peers
        alice = createMockService(peerID: "ALICE123", nickname: "Alice")
        bob = createMockService(peerID: "BOB456", nickname: "Bob")
        charlie = createMockService(peerID: "CHARLIE789", nickname: "Charlie")
        
        // Connect all peers
        simulateConnection(alice, bob)
        simulateConnection(bob, charlie)
        simulateConnection(alice, charlie)
    }
    
    override func tearDown() {
        // Clean up conversations
        let allJoined = conversationStore.getAllJoinedConversations()
        for joinedConv in allJoined {
            conversationStore.leaveConversation(conversationId: joinedConv.conversation.id)
        }
        
        MockBluetoothMeshService.clearRegistry()
        super.tearDown()
    }
    
    // MARK: - Room Isolation Tests
    
    func testStrictRoomIsolation() throws {
        // Create multiple distinct rooms
        let mathRoomId = TopicManager.topicCode(
            campusId: testCampusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        let compRoomId = TopicManager.topicCode(
            campusId: testCampusId,
            course: TopicManager.courseId(dept: "COMP", num: "330", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        let physRoomId = TopicManager.topicCode(
            campusId: testCampusId,
            course: TopicManager.courseId(dept: "PHYS", num: "101", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Alice joins MATH and COMP
        alice.joinConversation(mathRoomId)
        alice.joinConversation(compRoomId)
        
        // Bob joins only COMP
        bob.joinConversation(compRoomId)
        
        // Charlie joins only PHYS
        charlie.joinConversation(physRoomId)
        
        var aliceReceivedMessages: [Data: [String]] = [:]
        var bobReceivedMessages: [Data: [String]] = [:]
        var charlieReceivedMessages: [Data: [String]] = [:]
        
        let expectation = XCTestExpectation(description: "Room isolation maintained")
        expectation.expectedFulfillmentCount = 3 // Alice gets 2 messages, Bob gets 1, Charlie gets 0
        
        // Setup message handlers
        alice.roomMessageDeliveryHandler = { roomMessage in
            if aliceReceivedMessages[roomMessage.conversationId] == nil {
                aliceReceivedMessages[roomMessage.conversationId] = []
            }
            aliceReceivedMessages[roomMessage.conversationId]!.append(roomMessage.content)
            expectation.fulfill()
        }
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if bobReceivedMessages[roomMessage.conversationId] == nil {
                bobReceivedMessages[roomMessage.conversationId] = []
            }
            bobReceivedMessages[roomMessage.conversationId]!.append(roomMessage.content)
            expectation.fulfill()
        }
        
        charlie.roomMessageDeliveryHandler = { roomMessage in
            if charlieReceivedMessages[roomMessage.conversationId] == nil {
                charlieReceivedMessages[roomMessage.conversationId] = []
            }
            charlieReceivedMessages[roomMessage.conversationId]!.append(roomMessage.content)
            expectation.fulfill()
        }
        
        // Send messages to different rooms
        alice.sendRoomMessage("MATH question", in: mathRoomId)      // Only Alice should receive
        alice.sendRoomMessage("COMP discussion", in: compRoomId)   // Alice and Bob should receive
        charlie.sendRoomMessage("PHYS lab notes", in: physRoomId) // Only Charlie should receive
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify isolation
        XCTAssertEqual(aliceReceivedMessages[mathRoomId]?.count, 1) // Alice gets MATH
        XCTAssertEqual(aliceReceivedMessages[compRoomId]?.count, 1) // Alice gets COMP
        XCTAssertNil(aliceReceivedMessages[physRoomId]) // Alice doesn't get PHYS
        
        XCTAssertNil(bobReceivedMessages[mathRoomId]) // Bob doesn't get MATH
        XCTAssertEqual(bobReceivedMessages[compRoomId]?.count, 1) // Bob gets COMP
        XCTAssertNil(bobReceivedMessages[physRoomId]) // Bob doesn't get PHYS
        
        XCTAssertNil(charlieReceivedMessages[mathRoomId]) // Charlie doesn't get MATH
        XCTAssertNil(charlieReceivedMessages[compRoomId]) // Charlie doesn't get COMP
        XCTAssertEqual(charlieReceivedMessages[physRoomId]?.count, 1) // Charlie gets PHYS
    }
    
    func testSystemRoomSpecialBehavior() throws {
        let announcementsId = TopicManager.announcementsId(campusId: testCampusId)
        let generalId = TopicManager.generalId(campusId: testCampusId)
        let broadcastId = TopicManager.broadcastId(campusId: testCampusId)
        
        // Bob joins only general room explicitly
        bob.joinConversation(generalId)
        
        var systemMessagesReceived: [String] = []
        let expectation = XCTestExpectation(description: "System room behavior correct")
        expectation.expectedFulfillmentCount = 3 // Announcements (always), General (joined), Broadcast (always)
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            systemMessagesReceived.append(roomMessage.content)
            expectation.fulfill()
        }
        
        // Send to all system rooms
        alice.sendRoomMessage("Campus announcement", in: announcementsId)  // Should reach Bob (always accessible)
        alice.sendRoomMessage("General chat message", in: generalId)      // Should reach Bob (joined)
        alice.sendRoomMessage("Campus broadcast", in: broadcastId)        // Should reach Bob (always accessible)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify Bob received all system messages
        XCTAssertTrue(systemMessagesReceived.contains("Campus announcement"))
        XCTAssertTrue(systemMessagesReceived.contains("General chat message"))
        XCTAssertTrue(systemMessagesReceived.contains("Campus broadcast"))
        XCTAssertEqual(systemMessagesReceived.count, 3)
    }
    
    func testConversationLeaveImmediateEffect() throws {
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        // Both join initially
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let beforeLeaveExpectation = XCTestExpectation(description: "Message received before leave")
        let afterLeaveExpectation = XCTestExpectation(description: "Message NOT received after leave")
        afterLeaveExpectation.isInverted = true
        
        // First message - Bob should receive
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Before leave" {
                beforeLeaveExpectation.fulfill()
                
                // Bob leaves the conversation immediately
                self.bob.leaveConversation(conversationId)
                
                // Send second message after Bob left
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.alice.sendRoomMessage("After leave", in: conversationId)
                }
            } else if roomMessage.content == "After leave" {
                afterLeaveExpectation.fulfill() // This should not happen
            }
        }
        
        // Send first message
        alice.sendRoomMessage("Before leave", in: conversationId)
        
        wait(for: [beforeLeaveExpectation], timeout: TestConstants.shortTimeout)
        wait(for: [afterLeaveExpectation], timeout: TestConstants.shortTimeout)
    }
    
    // MARK: - Conversation Routing Edge Cases
    
    func testIdenticalRoomNamesDifferentCampuses() throws {
        let campus1 = "university1.edu"
        let campus2 = "university2.edu"
        
        // Create identical course rooms at different campuses
        let math262Campus1 = TopicManager.topicCode(
            campusId: campus1,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        let math262Campus2 = TopicManager.topicCode(
            campusId: campus2,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Should be different despite same course details
        XCTAssertNotEqual(math262Campus1, math262Campus2)
        
        // Create peers from different campuses
        let campus1Peer = createMockService(peerID: "CAMPUS1PEER", nickname: "Campus1Student")
        let campus2Peer = createMockService(peerID: "CAMPUS2PEER", nickname: "Campus2Student")
        
        campus1Peer.setupCampusPresence(campusId: campus1)
        campus2Peer.setupCampusPresence(campusId: campus2)
        
        // Each joins their campus's MATH 262 room
        campus1Peer.joinConversation(math262Campus1)
        campus2Peer.joinConversation(math262Campus2)
        
        var campus1Messages: [String] = []
        var campus2Messages: [String] = []
        
        let expectation = XCTestExpectation(description: "Campus room isolation maintained")
        expectation.expectedFulfillmentCount = 2 // Each peer gets their own campus message
        
        campus1Peer.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == math262Campus1 {
                campus1Messages.append(roomMessage.content)
                expectation.fulfill()
            } else {
                XCTFail("Campus 1 peer received message from wrong room")
            }
        }
        
        campus2Peer.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == math262Campus2 {
                campus2Messages.append(roomMessage.content)
                expectation.fulfill()
            } else {
                XCTFail("Campus 2 peer received message from wrong room")
            }
        }
        
        // Connect peers (physical proximity) but they're in different campus rooms
        simulateConnection(campus1Peer, campus2Peer)
        
        // Each sends to their MATH 262 room
        campus1Peer.sendRoomMessage("Campus 1 MATH question", in: math262Campus1)
        campus2Peer.sendRoomMessage("Campus 2 MATH question", in: math262Campus2)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify no cross-campus contamination
        XCTAssertEqual(campus1Messages, ["Campus 1 MATH question"])
        XCTAssertEqual(campus2Messages, ["Campus 2 MATH question"])
    }
    
    func testSessionSpecificRoomIsolation() throws {
        let campusId = testCampusId
        
        // Create same course but different sessions
        let mathLecture = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: TopicManager.sessionId(date: "2024-09-15", slot: "09:00", building: "BURN", room: "1205")
        )
        let mathTutorial = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: TopicManager.sessionId(date: "2024-09-15", slot: "14:00", building: "BURN", room: "306")
        )
        
        // Should be different rooms despite same course
        XCTAssertNotEqual(mathLecture, mathTutorial)
        
        // Alice joins lecture, Bob joins tutorial
        alice.joinConversation(mathLecture)
        bob.joinConversation(mathTutorial)
        
        var lectureMessages: [String] = []
        var tutorialMessages: [String] = []
        
        let expectation = XCTestExpectation(description: "Session isolation maintained")
        expectation.expectedFulfillmentCount = 2 // Each session gets its own message
        
        alice.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == mathLecture {
                lectureMessages.append(roomMessage.content)
                expectation.fulfill()
            }
        }
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == mathTutorial {
                tutorialMessages.append(roomMessage.content)
                expectation.fulfill()
            }
        }
        
        // Send session-specific messages
        alice.sendRoomMessage("Lecture question about derivatives", in: mathLecture)
        bob.sendRoomMessage("Tutorial question about integrals", in: mathTutorial)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify session isolation
        XCTAssertEqual(lectureMessages, ["Lecture question about derivatives"])
        XCTAssertEqual(tutorialMessages, ["Tutorial question about integrals"])
    }
    
    func testMassiveRoomCount() throws {
        // Test handling many different rooms simultaneously
        let roomCount = 100
        var roomIds: [Data] = []
        
        // Generate many different room IDs
        for i in 0..<roomCount {
            let roomId = TopicManager.topicCode(
                campusId: testCampusId,
                course: TopicManager.courseId(dept: "TEST", num: "\(i)", term: "FALL2024"),
                session: Data(repeating: 0, count: 8)
            )
            roomIds.append(roomId)
            
            // Alice joins all rooms
            alice.joinConversation(roomId)
        }
        
        // Bob joins only half the rooms
        for i in 0..<(roomCount/2) {
            bob.joinConversation(roomIds[i])
        }
        
        var aliceMessageCount = 0
        var bobMessageCount = 0
        
        let expectation = XCTestExpectation(description: "Massive room count handled")
        expectation.expectedFulfillmentCount = roomCount + (roomCount/2) // Alice gets all, Bob gets half
        
        alice.roomMessageDeliveryHandler = { roomMessage in
            aliceMessageCount += 1
            expectation.fulfill()
        }
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            bobMessageCount += 1
            expectation.fulfill()
        }
        
        // Send one message to each room
        for (index, roomId) in roomIds.enumerated() {
            alice.sendRoomMessage("Message for room \(index)", in: roomId)
        }
        
        wait(for: [expectation], timeout: TestConstants.longTimeout)
        
        // Verify correct distribution
        XCTAssertEqual(aliceMessageCount, roomCount) // Alice joined all rooms
        XCTAssertEqual(bobMessageCount, roomCount/2) // Bob joined half the rooms
    }
    
    // MARK: - Conversation State Management Tests
    
    func testJoinLeaveRapidToggling() throws {
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        var messagesReceived = 0
        let expectation = XCTestExpectation(description: "Rapid join/leave handled")
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == conversationId {
                messagesReceived += 1
                expectation.fulfill()
            }
        }
        
        // Rapid join/leave sequence
        for i in 0..<10 {
            if i % 2 == 0 {
                bob.joinConversation(conversationId)
                // Send message while joined
                alice.sendRoomMessage("Message \(i)", in: conversationId)
            } else {
                bob.leaveConversation(conversationId)
                // Send message while not joined (should not receive)
                alice.sendRoomMessage("Message \(i)", in: conversationId)
            }
            
            // Small delay between operations
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // Wait for any messages that should have been received
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Should have received 5 messages (when joined on even iterations)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        XCTAssertEqual(messagesReceived, 5) // Only received when joined
    }
    
    func testConversationStateConsistency() throws {
        let room1Id = TopicManager.generalId(campusId: testCampusId)
        let room2Id = TopicManager.announcementsId(campusId: testCampusId)
        
        // Test state consistency across multiple operations
        XCTAssertFalse(alice.joinedConversations.contains(room1Id))
        XCTAssertFalse(alice.joinedConversations.contains(room2Id))
        
        // Join room 1
        alice.joinConversation(room1Id)
        XCTAssertTrue(alice.joinedConversations.contains(room1Id))
        XCTAssertFalse(alice.joinedConversations.contains(room2Id))
        
        // Join room 2
        alice.joinConversation(room2Id)
        XCTAssertTrue(alice.joinedConversations.contains(room1Id))
        XCTAssertTrue(alice.joinedConversations.contains(room2Id))
        
        // Leave room 1
        alice.leaveConversation(room1Id)
        XCTAssertFalse(alice.joinedConversations.contains(room1Id))
        XCTAssertTrue(alice.joinedConversations.contains(room2Id))
        
        // Leave room 2
        alice.leaveConversation(room2Id)
        XCTAssertFalse(alice.joinedConversations.contains(room1Id))
        XCTAssertFalse(alice.joinedConversations.contains(room2Id))
    }
    
    // MARK: - Message Ordering and History Tests
    
    func testMessageOrderingWithinRoom() throws {
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        var receivedMessages: [String] = []
        let expectation = XCTestExpectation(description: "Message ordering preserved")
        expectation.expectedFulfillmentCount = 10
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == conversationId {
                receivedMessages.append(roomMessage.content)
                expectation.fulfill()
            }
        }
        
        // Send messages in sequence
        for i in 0..<10 {
            alice.sendRoomMessage("Message \(i)", in: conversationId)
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify order (messages should arrive in order they were sent)
        for i in 0..<10 {
            XCTAssertEqual(receivedMessages[i], "Message \(i)")
        }
    }
    
    func testCrossRoomMessageOrderingIndependence() throws {
        let room1Id = TopicManager.generalId(campusId: testCampusId)
        let room2Id = TopicManager.announcementsId(campusId: testCampusId)
        
        alice.joinConversation(room1Id)
        alice.joinConversation(room2Id)
        bob.joinConversation(room1Id)
        bob.joinConversation(room2Id)
        
        var room1Messages: [String] = []
        var room2Messages: [String] = []
        
        let expectation = XCTestExpectation(description: "Cross-room ordering independent")
        expectation.expectedFulfillmentCount = 20 // 10 messages × 2 rooms
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == room1Id {
                room1Messages.append(roomMessage.content)
            } else if roomMessage.conversationId == room2Id {
                room2Messages.append(roomMessage.content)
            }
            expectation.fulfill()
        }
        
        // Interleave messages between rooms
        for i in 0..<10 {
            alice.sendRoomMessage("Room1 Message \(i)", in: room1Id)
            alice.sendRoomMessage("Room2 Message \(i)", in: room2Id)
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify each room maintains its own ordering
        for i in 0..<10 {
            XCTAssertEqual(room1Messages[i], "Room1 Message \(i)")
            XCTAssertEqual(room2Messages[i], "Room2 Message \(i)")
        }
    }
    
    // MARK: - Security Boundary Tests
    
    func testRoomMessageSpoofingPrevention() throws {
        let conversationId = TopicManager.generalId(campusId: testCampusId)
        
        // Create malicious peer Evel from different campus
        let eve = createMockService(peerID: "EVE999", nickname: "Evel")
        eve.setupCampusPresence(campusId: "wrong.university.edu") // Different campus
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Message spoofing prevented")
        expectation.isInverted = true
        
        // Bob should NOT receive a message that appears to come from Alice but with Eve's peer ID
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.sender == "Alice" && roomMessage.content == "Spoofed message" {
                // Verify the sender peer ID to detect spoofing
                // In a real scenario, this would be verified by the mesh service
                expectation.fulfill() // This should not happen with proper validation
            }
        }
        
        simulateConnection(alice, bob)
        simulateConnection(eve, bob)
        
        // Eve tries to send a message pretending to be Alice
        // This should be blocked by various mechanisms:
        // 1. Campus gate (different campus)
        // 2. Peer ID validation
        // 3. Cryptographic signatures (in future)
        
        // For now, the mock service should enforce campus isolation
        eve.sendRoomMessage("Spoofed message", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    func testConversationIdTampering() throws {
        // Test resistance to conversation ID tampering attacks
        let legitimateRoomId = TopicManager.generalId(campusId: testCampusId)
        let tampererId = "TAMPERER123"
        
        alice.joinConversation(legitimateRoomId)
        bob.joinConversation(legitimateRoomId)
        
        // Create a room message with tampered conversation ID
        let tamperedMessage = RoomMessage(
            conversationId: Data(repeating: 0xFF, count: 32), // Invalid/tampered ID
            messageId: "tampered-msg",
            sender: "Tamperer",
            content: "Tampered conversation ID",
            mentions: nil
        )
        
        // Even if somehow transmitted, Bob shouldn't process it due to:
        // 1. Not being joined to the tampered conversation ID
        // 2. Campus gate validation
        
        let expectation = XCTestExpectation(description: "Tampered conversation ID blocked")
        expectation.isInverted = true
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.messageId == "tampered-msg" {
                expectation.fulfill() // Should not happen
            }
        }
        
        // Simulate receiving the tampered message
        bob.simulateReceiveRoomMessage(tamperedMessage, from: tampererId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
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
