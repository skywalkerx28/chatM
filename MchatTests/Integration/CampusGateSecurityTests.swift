//
// CampusGateSecurityTests.swift
// MchatTests   
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import XCTest
@testable import chatM

/// Comprehensive tests for campus-gate security enforcement and room isolation
final class CampusGateSecurityTests: XCTestCase {
    
    var campusGate: CampusGate!
    var conversationStore: ConversationStore!
    var alice: MockBluetoothMeshService!
    var bob: MockBluetoothMeshService!
    var eve: MockBluetoothMeshService! // Malicious peer
    
    override func setUp() {
        super.setUp()
        
        campusGate = CampusGate()
        conversationStore = ConversationStore.shared
        
        // Create mock services
        alice = createMockService(peerID: "ALICE123", nickname: "Alice", campusId: "mcgill.ca")
        bob = createMockService(peerID: "BOB5678", nickname: "Bob", campusId: "mcgill.ca")
        eve = createMockService(peerID: "EVE9999", nickname: "Eve", campusId: "wrong.university.edu")
        
        // Setup valid campus presence for Alice and Bob
        let validExp = Int(Date().timeIntervalSince1970) + 3600 // 1 hour from now
        campusGate.acceptPresence(senderId: alice.myPeerID, campusId: "mcgill.ca", exp: validExp)
        campusGate.acceptPresence(senderId: bob.myPeerID, campusId: "mcgill.ca", exp: validExp)
        
        // Eve has presence for different campus
        campusGate.acceptPresence(senderId: eve.myPeerID, campusId: "evil.university.edu", exp: validExp)
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
    
    // MARK: - Campus Gate Enforcement Tests
    
    func testValidCampusMessageAccepted() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Alice and Bob join the same conversation
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Valid campus message accepted")
        
        // Bob should receive Alice's message
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Valid campus message" && 
               roomMessage.conversationId == conversationId {
                expectation.fulfill()
            }
        }
        
        // Connect peers
        simulateConnection(alice, bob)
        
        // Alice sends room message
        alice.sendRoomMessage("Valid campus message", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    func testInvalidCampusMessageRejected() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Alice joins conversation
        alice.joinConversation(conversationId)
        // Eve tries to join conversation for different campus
        eve.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Invalid campus message rejected")
        expectation.isInverted = true // Should NOT be fulfilled
        
        // Alice should NOT receive Eve's message
        alice.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Cross-campus infiltration attempt" {
                expectation.fulfill() // This should not happen
            }
        }
        
        // Connect peers
        simulateConnection(alice, eve)
        
        // Eve tries to send to Alice's campus conversation (should be blocked)
        eve.sendRoomMessage("Cross-campus infiltration attempt", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    func testExpiredPresenceRejection() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        let expiredPeerID = "EXPIRED123"
        
        // Setup expired presence
        let expiredTime = Int(Date().timeIntervalSince1970) - 3600 // 1 hour ago
        campusGate.acceptPresence(senderId: expiredPeerID, campusId: campusId, exp: expiredTime)
        
        // Should reject message from expired presence
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: expiredPeerID, topicCampusId: campusId))
    }
    
    func testPresenceUpdateOverwritesPrevious() throws {
        let peerID = "UPDATE123"
        let campusId = "mcgill.ca"
        
        // Setup expired presence first
        let expiredTime = Int(Date().timeIntervalSince1970) - 3600
        campusGate.acceptPresence(senderId: peerID, campusId: campusId, exp: expiredTime)
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: peerID, topicCampusId: campusId))
        
        // Update with valid presence
        let validTime = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: peerID, campusId: campusId, exp: validTime)
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: peerID, topicCampusId: campusId))
    }
    
    // MARK: - Room Isolation Tests
    
    func testCrossRoomMessageIsolation() throws {
        let campusId = "mcgill.ca"
        let mathConversationId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        let compConversationId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "COMP", num: "330", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Alice joins MATH, Bob joins COMP
        alice.joinConversation(mathConversationId)
        bob.joinConversation(compConversationId)
        
        let expectation = XCTestExpectation(description: "Cross-room isolation maintained")
        expectation.isInverted = true // Should NOT be fulfilled
        
        // Bob should NOT receive Alice's MATH message
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "MATH homework question" {
                expectation.fulfill() // This should not happen
            }
        }
        
        // Connect peers
        simulateConnection(alice, bob)
        
        // Alice sends to MATH room
        alice.sendRoomMessage("MATH homework question", in: mathConversationId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    func testAnnouncementsAlwaysAccessible() throws {
        let campusId = "mcgill.ca"
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        
        // Bob doesn't explicitly join announcements
        XCTAssertFalse(bob.joinedConversations.contains(announcementsId))
        
        let expectation = XCTestExpectation(description: "Announcements accessible without join")
        
        // Bob should still receive announcements
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Important campus announcement" &&
               roomMessage.conversationId == announcementsId {
                expectation.fulfill()
            }
        }
        
        // Connect peers
        simulateConnection(alice, bob)
        
        // Alice sends announcement
        alice.sendRoomMessage("Important campus announcement", in: announcementsId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    func testJoinStateEnforcement() throws {
        let campusId = "mcgill.ca"
        let privateRoomId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "PRIVATE", num: "999", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Only Alice joins the private room
        alice.joinConversation(privateRoomId)
        // Bob does NOT join
        
        let expectation = XCTestExpectation(description: "Non-joined room message blocked")
        expectation.isInverted = true // Should NOT be fulfilled
        
        // Bob should NOT receive Alice's private room message
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == privateRoomId {
                expectation.fulfill() // This should not happen
            }
        }
        
        // Connect peers
        simulateConnection(alice, bob)
        
        // Alice sends to private room
        alice.sendRoomMessage("Secret meeting notes", in: privateRoomId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    // MARK: - Multi-Campus Scenario Tests
    
    func testMultiCampusEnvironment() throws {
        // Create additional peers from different campuses
        let utoronto = createMockService(peerID: "UTORONTO1", nickname: "Toronto1", campusId: "utoronto.ca")
        let concordia = createMockService(peerID: "CONCORDIA1", nickname: "Concordia1", campusId: "concordia.ca")
        
        // Setup presence for each campus
        let validExp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: utoronto.myPeerID, campusId: "utoronto.ca", exp: validExp)
        campusGate.acceptPresence(senderId: concordia.myPeerID, campusId: "concordia.ca", exp: validExp)
        
        // Create campus-specific conversations
        let mcgillGeneral = TopicManager.generalId(campusId: "mcgill.ca")
        let utorontoGeneral = TopicManager.generalId(campusId: "utoronto.ca")
        let concordiaGeneral = TopicManager.generalId(campusId: "concordia.ca")
        
        // Each peer joins their campus's general room
        alice.joinConversation(mcgillGeneral)
        utoronto.joinConversation(utorontoGeneral)
        concordia.joinConversation(concordiaGeneral)
        
        var receivedMessages: [String: String] = [:]
        let expectation = XCTestExpectation(description: "Campus isolation maintained")
        expectation.expectedFulfillmentCount = 3 // Each peer should only receive their own campus message
        
        // Setup message handlers
        alice.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == mcgillGeneral {
                receivedMessages["alice"] = roomMessage.content
                expectation.fulfill()
            } else {
                XCTFail("Alice received message from wrong campus")
            }
        }
        
        utoronto.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == utorontoGeneral {
                receivedMessages["utoronto"] = roomMessage.content
                expectation.fulfill()
            } else {
                XCTFail("UofT peer received message from wrong campus")
            }
        }
        
        concordia.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == concordiaGeneral {
                receivedMessages["concordia"] = roomMessage.content
                expectation.fulfill()
            } else {
                XCTFail("Concordia peer received message from wrong campus")
            }
        }
        
        // Connect all peers (simulating physical proximity)
        simulateConnection(alice, utoronto)
        simulateConnection(alice, concordia)
        simulateConnection(utoronto, concordia)
        
        // Each peer sends to their campus general room
        alice.sendRoomMessage("McGill campus message", in: mcgillGeneral)
        utoronto.sendRoomMessage("UofT campus message", in: utorontoGeneral)
        concordia.sendRoomMessage("Concordia campus message", in: concordiaGeneral)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify each peer only received their campus message
        XCTAssertEqual(receivedMessages["alice"], "McGill campus message")
        XCTAssertEqual(receivedMessages["utoronto"], "UofT campus message")
        XCTAssertEqual(receivedMessages["concordia"], "Concordia campus message")
        XCTAssertEqual(receivedMessages.count, 3) // No cross-campus leakage
    }
    
    // MARK: - Room Message Relay Security Tests
    
    func testSecureRelayWithCampusValidation() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Create a chain: Alice -> Bob -> Charlie (all same campus)
        let charlie = createMockService(peerID: "CHARLIE999", nickname: "Charlie", campusId: campusId)
        let validExp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: charlie.myPeerID, campusId: campusId, exp: validExp)
        
        // All join the conversation
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        charlie.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Secure relay with campus validation")
        
        // Charlie should receive the relayed message
        charlie.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Relayed secure message" &&
               roomMessage.conversationId == conversationId {
                expectation.fulfill()
            }
        }
        
        // Connect in chain: Alice -> Bob -> Charlie
        simulateConnection(alice, bob)
        simulateConnection(bob, charlie)
        
        // Alice sends message (should reach Charlie via Bob with campus validation)
        alice.sendRoomMessage("Relayed secure message", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
    }
    
    func testMaliciousRelayAttemptBlocked() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Alice and Bob join legitimate conversation
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Malicious relay blocked")
        expectation.isInverted = true // Should NOT be fulfilled
        
        // Bob should NOT receive Eve's forged message
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == "Forged message from Eve" {
                expectation.fulfill() // This should not happen
            }
        }
        
        // Connect Alice-Bob and Eve-Bob
        simulateConnection(alice, bob)
        simulateConnection(eve, bob)
        
        // Eve tries to send to McGill conversation (should be blocked by campus gate)
        eve.sendRoomMessage("Forged message from Eve", in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.shortTimeout)
    }
    
    // MARK: - Edge Case Security Tests
    
    func testMalformedConversationIdHandling() throws {
        // Test various malformed conversation IDs
        let malformedIds = [
            Data(), // Empty
            Data(repeating: 0x00, count: 16), // Too short
            Data(repeating: 0xFF, count: 64), // Too long
            Data(repeating: 0x00, count: 32), // All zeros (might be valid)
        ]
        
        for (index, malformedId) in malformedIds.enumerated() {
            let roomMessage = RoomMessage(
                conversationId: malformedId,
                messageId: "test-\(index)",
                sender: "testuser",
                content: "Test content",
                mentions: nil
            )
            
            // Should encode without crashing
            let encoded = roomMessage.encode()
            
            if malformedId.count == 32 {
                // 32-byte IDs (even all zeros) should encode successfully
                XCTAssertNotNil(encoded, "32-byte conversation ID should encode")
                
                // Should also decode successfully
                if let encoded = encoded {
                    let decoded = RoomMessage.decode(from: encoded)
                    XCTAssertNotNil(decoded, "32-byte conversation ID should decode")
                }
            } else {
                // Non-32-byte IDs should still encode (validation happens elsewhere)
                // But decoding should handle gracefully
                if let encoded = encoded {
                    let decoded = RoomMessage.decode(from: encoded)
                    // The decode might fail due to invalid length, which is acceptable
                }
            }
        }
    }
    
    func testPresenceSpamPrevention() throws {
        let spammerID = "SPAMMER123"
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Accept presence initially
        let validExp = Int(Date().timeIntervalSince1970) + 3600
        campusGate.acceptPresence(senderId: spammerID, campusId: campusId, exp: validExp)
        
        // Verify initial acceptance
        XCTAssertTrue(campusGate.shouldAcceptMessage(from: spammerID, topicCampusId: campusId))
        
        // Simulate presence spam by setting expired presence
        let expiredTime = Int(Date().timeIntervalSince1970) - 1
        campusGate.acceptPresence(senderId: spammerID, campusId: campusId, exp: expiredTime)
        
        // Should now be rejected
        XCTAssertFalse(campusGate.shouldAcceptMessage(from: spammerID, topicCampusId: campusId))
    }
    
    func testConcurrentPresenceUpdates() throws {
        let peerID = "CONCURRENT123"
        let campusId = "mcgill.ca"
        
        // Simulate concurrent presence updates
        let group = DispatchGroup()
        let iterations = 100
        
        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let exp = Int(Date().timeIntervalSince1970) + Int.random(in: 1...7200) // Random future time
                self.campusGate.acceptPresence(senderId: peerID, campusId: campusId, exp: exp)
                group.leave()
            }
        }
        
        group.wait()
        
        // After all updates, should still be functional (no crashes)
        let result = campusGate.shouldAcceptMessage(from: peerID, topicCampusId: campusId)
        // Result could be true or false depending on final state, but no crash
        XCTAssertNotNil(result) // Just verify it returns something
    }
    
    // MARK: - Message Content Security Tests
    
    func testLargeMessageHandling() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        // Create very large message content
        let largeContent = String(repeating: "A", count: 64000) // Near max size
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let expectation = XCTestExpectation(description: "Large message handled correctly")
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.content == largeContent && roomMessage.conversationId == conversationId {
                expectation.fulfill()
            }
        }
        
        simulateConnection(alice, bob)
        
        // Should handle large content gracefully
        alice.sendRoomMessage(largeContent, in: conversationId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
    }
    
    func testSpecialCharacterHandling() throws {
        let campusId = "mcgill.ca" 
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        // Test various special characters and encodings
        let specialMessages = [
            "Unicode: 👋🌍🚀💻🎓",
            "Newlines:\nLine 1\nLine 2\nLine 3",
            "Quotes: \"Hello\" and 'World'",
            "Math: ∑∏∫∂∇√∞≠≤≥±×÷",
            "Languages: 中文 العربية русский 日本語",
            "Zero-width: ‌‍﻿", // Zero-width chars
            String(repeating: "\0", count: 10), // Null bytes
        ]
        
        var receivedCount = 0
        let expectation = XCTestExpectation(description: "Special characters handled")
        expectation.expectedFulfillmentCount = specialMessages.count
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            receivedCount += 1
            expectation.fulfill()
        }
        
        simulateConnection(alice, bob)
        
        // Send all special character messages
        for message in specialMessages {
            alice.sendRoomMessage(message, in: conversationId)
        }
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        XCTAssertEqual(receivedCount, specialMessages.count)
    }
    
    // MARK: - Performance and Stress Tests
    
    func testHighVolumeRoomMessages() throws {
        let campusId = "mcgill.ca"
        let conversationId = TopicManager.generalId(campusId: campusId)
        
        alice.joinConversation(conversationId)
        bob.joinConversation(conversationId)
        
        let messageCount = 500
        var receivedCount = 0
        let expectation = XCTestExpectation(description: "High volume room messages")
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if roomMessage.conversationId == conversationId {
                receivedCount += 1
                if receivedCount == messageCount {
                    expectation.fulfill()
                }
            }
        }
        
        simulateConnection(alice, bob)
        
        // Send many messages rapidly
        for i in 0..<messageCount {
            alice.sendRoomMessage("Message \(i)", in: conversationId)
        }
        
        wait(for: [expectation], timeout: TestConstants.longTimeout)
        XCTAssertEqual(receivedCount, messageCount)
    }
    
    func testMixedRoomTypesSimultaneous() throws {
        let campusId = "mcgill.ca"
        
        // Create multiple conversation types
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        let generalId = TopicManager.generalId(campusId: campusId)
        let broadcastId = TopicManager.broadcastId(campusId: campusId)
        let mathRoomId = TopicManager.topicCode(
            campusId: campusId,
            course: TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024"),
            session: Data(repeating: 0, count: 8)
        )
        
        // Join all rooms
        alice.joinConversation(generalId)
        alice.joinConversation(mathRoomId)
        bob.joinConversation(generalId)
        bob.joinConversation(mathRoomId)
        
        var messagesByRoom: [Data: [String]] = [:]
        let expectation = XCTestExpectation(description: "Mixed room types handled correctly")
        expectation.expectedFulfillmentCount = 8 // 4 messages × 2 receivers
        
        bob.roomMessageDeliveryHandler = { roomMessage in
            if messagesByRoom[roomMessage.conversationId] == nil {
                messagesByRoom[roomMessage.conversationId] = []
            }
            messagesByRoom[roomMessage.conversationId]!.append(roomMessage.content)
            expectation.fulfill()
        }
        
        simulateConnection(alice, bob)
        
        // Send to different room types simultaneously
        alice.sendRoomMessage("Announcement message", in: announcementsId)
        alice.sendRoomMessage("General chat message", in: generalId)
        alice.sendRoomMessage("Broadcast message", in: broadcastId)
        alice.sendRoomMessage("Math homework question", in: mathRoomId)
        
        wait(for: [expectation], timeout: TestConstants.defaultTimeout)
        
        // Verify messages went to correct rooms
        XCTAssertEqual(messagesByRoom[announcementsId]?.first, "Announcement message")
        XCTAssertEqual(messagesByRoom[generalId]?.first, "General chat message")
        XCTAssertEqual(messagesByRoom[broadcastId]?.first, "Broadcast message")
        XCTAssertEqual(messagesByRoom[mathRoomId]?.first, "Math homework question")
    }
    
    // MARK: - Helper Methods
    
    private func createMockService(peerID: String, nickname: String, campusId: String) -> MockBluetoothMeshService {
        let service = MockBluetoothMeshService()
        service.myPeerID = peerID
        service.mockNickname = nickname
        service.setupCampusPresence(campusId: campusId)
        return service
    }
    
    private func simulateConnection(_ peer1: MockBluetoothMeshService, _ peer2: MockBluetoothMeshService) {
        peer1.simulateConnectedPeer(peer2.myPeerID)
        peer2.simulateConnectedPeer(peer1.myPeerID)
    }
}
