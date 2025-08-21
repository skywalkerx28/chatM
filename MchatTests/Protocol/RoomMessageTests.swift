//
// RoomMessageTests.swift
// MchatTests           
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import XCTest
@testable import chatM

/// Tests for RoomMessage binary encoding and decoding
final class RoomMessageTests: XCTestCase {
    
    // MARK: - Test Data
    
    private func createTestConversationId() -> Data {
        // Create a deterministic 32-byte conversation ID for testing
        return Data(repeating: 0x42, count: 32)
    }
    
    private func createTestRoomMessage(withMentions: Bool = false) -> RoomMessage {
        let mentions = withMentions ? ["alice", "bob"] : nil
        return RoomMessage(
            conversationId: createTestConversationId(),
            messageId: "test-message-123",
            sender: "testuser",
            content: "Hello, this is a test room message!",
            timestamp: Date(timeIntervalSince1970: 1640995200), // Fixed timestamp for deterministic tests
            mentions: mentions
        )
    }
    
    // MARK: - Basic Encoding/Decoding Tests
    
    func testBasicRoomMessageEncoding() throws {
        let message = createTestRoomMessage()
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode room message")
            return
        }
        
        // Verify minimum expected size
        // 1 (flags) + 1 (conv_id_len) + 32 (conv_id) + 8 (timestamp) + 
        // 1 (msg_id_len) + msg_id + 1 (sender_len) + sender + 2 (content_len) + content
        let expectedMinSize = 1 + 1 + 32 + 8 + 1 + message.messageId.count + 1 + message.sender.count + 2 + message.content.count
        XCTAssertGreaterThanOrEqual(encoded.count, expectedMinSize)
        
        // Verify flags byte
        let flags = encoded[0]
        XCTAssertEqual(flags & 0x02, 0) // isEncrypted should be false
        XCTAssertEqual(flags & 0x04, 0) // hasMentions should be false
        
        // Verify conversation ID length
        XCTAssertEqual(encoded[1], 0x20) // 32 bytes
        
        // Verify conversation ID
        let conversationIdData = encoded[2..<34]
        XCTAssertEqual(Data(conversationIdData), createTestConversationId())
    }
    
    func testBasicRoomMessageDecoding() throws {
        let originalMessage = createTestRoomMessage()
        guard let encoded = originalMessage.encode() else {
            XCTFail("Failed to encode original message")
            return
        }
        
        guard let decodedMessage = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message")
            return
        }
        
        // Verify all fields match
        XCTAssertEqual(decodedMessage.conversationId, originalMessage.conversationId)
        XCTAssertEqual(decodedMessage.messageId, originalMessage.messageId)
        XCTAssertEqual(decodedMessage.sender, originalMessage.sender)
        XCTAssertEqual(decodedMessage.content, originalMessage.content)
        XCTAssertEqual(decodedMessage.mentions, originalMessage.mentions)
        
        // Verify timestamp (allow small precision difference)
        let timeDiff = abs(decodedMessage.timestamp.timeIntervalSince(originalMessage.timestamp))
        XCTAssertLessThan(timeDiff, 0.001) // Less than 1ms difference
    }
    
    func testRoomMessageWithMentionsEncoding() throws {
        let message = createTestRoomMessage(withMentions: true)
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode room message with mentions")
            return
        }
        
        // Verify flags byte has mentions flag set
        let flags = encoded[0]
        XCTAssertEqual(flags & 0x04, 0x04) // hasMentions should be true
        
        // Decode and verify mentions are preserved
        guard let decodedMessage = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message with mentions")
            return
        }
        
        XCTAssertEqual(decodedMessage.mentions, ["alice", "bob"])
    }
    
    func testRoomMessageWithoutMentionsEncoding() throws {
        let message = createTestRoomMessage(withMentions: false)
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode room message without mentions")
            return
        }
        
        // Verify flags byte has mentions flag clear
        let flags = encoded[0]
        XCTAssertEqual(flags & 0x04, 0) // hasMentions should be false
        
        // Decode and verify no mentions
        guard let decodedMessage = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message without mentions")
            return
        }
        
        XCTAssertNil(decodedMessage.mentions)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyContentRoomMessage() throws {
        var message = createTestRoomMessage()
        let messageWithEmptyContent = RoomMessage(
            conversationId: message.conversationId,
            messageId: message.messageId,
            sender: message.sender,
            content: "", // Empty content
            timestamp: message.timestamp,
            mentions: nil
        )
        
        guard let encoded = messageWithEmptyContent.encode() else {
            XCTFail("Failed to encode room message with empty content")
            return
        }
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message with empty content")
            return
        }
        
        XCTAssertEqual(decoded.content, "")
        XCTAssertEqual(decoded.sender, message.sender)
    }
    
    func testLongContentRoomMessage() throws {
        let longContent = String(repeating: "This is a very long message content. ", count: 100) // ~3700 characters
        
        let message = RoomMessage(
            conversationId: createTestConversationId(),
            messageId: "long-test",
            sender: "testuser",
            content: longContent,
            timestamp: Date(),
            mentions: nil
        )
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode room message with long content")
            return
        }
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message with long content")
            return
        }
        
        XCTAssertEqual(decoded.content, longContent)
    }
    
    func testManyMentionsRoomMessage() throws {
        let manyMentions = (1...50).map { "user\($0)" }
        
        let message = RoomMessage(
            conversationId: createTestConversationId(),
            messageId: "mentions-test",
            sender: "testuser",
            content: "Testing many mentions",
            timestamp: Date(),
            mentions: manyMentions
        )
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode room message with many mentions")
            return
        }
        guard let decoded = RoomMessage.decode(from: encoded) else {
            XCTFail("Failed to decode room message with many mentions")
            return
        }
        
        XCTAssertEqual(decoded.mentions?.count, manyMentions.count)
        XCTAssertEqual(Set(decoded.mentions ?? []), Set(manyMentions))
    }
    
    // MARK: - Malformed Data Tests
    
    func testDecodingTooShortData() {
        let shortData = Data([0x00, 0x20]) // Only flags and conversation ID length
        let decoded = RoomMessage.decode(from: shortData)
        XCTAssertNil(decoded, "Should fail to decode data that's too short")
    }
    
    func testDecodingInvalidConversationIdLength() {
        var data = Data()
        data.append(0x00) // flags
        data.append(0x10) // invalid conversation ID length (should be 0x20)
        data.append(Data(repeating: 0x42, count: 16)) // wrong size conversation ID
        
        let decoded = RoomMessage.decode(from: data)
        XCTAssertNil(decoded, "Should fail to decode with invalid conversation ID length")
    }
    
    func testDecodingCorruptedData() {
        let corruptedData = Data(repeating: 0xFF, count: 100)
        let decoded = RoomMessage.decode(from: corruptedData)
        XCTAssertNil(decoded, "Should fail to decode corrupted data")
    }
    
    // MARK: - Round-trip Tests
    
    func testMultipleRoundTrips() throws {
        // Test multiple different messages to ensure encoding/decoding is consistent
        let testMessages = [
            createTestRoomMessage(withMentions: false),
            createTestRoomMessage(withMentions: true),
            RoomMessage(conversationId: createTestConversationId(), sender: "short", content: "hi", mentions: nil),
            RoomMessage(conversationId: Data(repeating: 0x00, count: 32), sender: "zeroconv", content: "zero conversation ID", mentions: ["test"])
        ]
        
        for (index, originalMessage) in testMessages.enumerated() {
            guard let encoded = originalMessage.encode() else {
                XCTFail("Failed to encode test message \(index)")
                continue
            }
            guard let decoded = RoomMessage.decode(from: encoded) else {
                XCTFail("Failed to decode test message \(index)")
                continue
            }
            
            // Verify all fields match
            XCTAssertEqual(decoded.conversationId, originalMessage.conversationId, "Conversation ID mismatch for message \(index)")
            XCTAssertEqual(decoded.messageId, originalMessage.messageId, "Message ID mismatch for message \(index)")
            XCTAssertEqual(decoded.sender, originalMessage.sender, "Sender mismatch for message \(index)")
            XCTAssertEqual(decoded.content, originalMessage.content, "Content mismatch for message \(index)")
            XCTAssertEqual(decoded.mentions, originalMessage.mentions, "Mentions mismatch for message \(index)")
            
            // Verify timestamp precision
            let timeDiff = abs(decoded.timestamp.timeIntervalSince(originalMessage.timestamp))
            XCTAssertLessThan(timeDiff, 0.001, "Timestamp precision issue for message \(index)")
        }
    }
    
    // MARK: - TopicManager Integration Tests
    
    func testAnnouncementsConversationId() throws {
        let campusId = "test.university.edu"
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        
        // Verify it's exactly 32 bytes
        XCTAssertEqual(announcementsId.count, 32)
        
        // Verify it's deterministic (same campus should produce same ID)
        let announcementsId2 = TopicManager.announcementsId(campusId: campusId)
        XCTAssertEqual(announcementsId, announcementsId2)
        
        // Verify different campus produces different ID
        let differentCampusId = TopicManager.announcementsId(campusId: "other.university.edu")
        XCTAssertNotEqual(announcementsId, differentCampusId)
    }
    
    func testGeneralConversationId() throws {
        let campusId = "test.university.edu"
        let generalId = TopicManager.generalId(campusId: campusId)
        
        // Verify it's exactly 32 bytes
        XCTAssertEqual(generalId.count, 32)
        
        // Verify it's deterministic
        let generalId2 = TopicManager.generalId(campusId: campusId)
        XCTAssertEqual(generalId, generalId2)
        
        // Verify it's different from announcements
        let announcementsId = TopicManager.announcementsId(campusId: campusId)
        XCTAssertNotEqual(generalId, announcementsId)
    }
    
    func testCourseConversationId() throws {
        let campusId = "test.university.edu"
        let courseData = TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024")
        let sessionData = Data(repeating: 0, count: 8) // Empty session for course-only room
        let courseTopicCode = TopicManager.topicCode(campusId: campusId, course: courseData, session: sessionData)
        
        // Verify it's exactly 32 bytes
        XCTAssertEqual(courseTopicCode.count, 32)
        
        // Verify it's deterministic
        let courseData2 = TopicManager.courseId(dept: "MATH", num: "262", term: "FALL2024")
        let sessionData2 = Data(repeating: 0, count: 8)
        let courseTopicCode2 = TopicManager.topicCode(campusId: campusId, course: courseData2, session: sessionData2)
        XCTAssertEqual(courseTopicCode, courseTopicCode2)
        
        // Verify different course produces different ID
        let differentCourseData = TopicManager.courseId(dept: "COMP", num: "330", term: "FALL2024")
        let differentTopicCode = TopicManager.topicCode(campusId: campusId, course: differentCourseData, session: sessionData)
        XCTAssertNotEqual(courseTopicCode, differentTopicCode)
    }
    
    // MARK: - Performance Tests
    
    func testEncodingPerformance() throws {
        let message = createTestRoomMessage(withMentions: true)
        
        measure {
            // Measure encoding performance
            for _ in 0..<1000 {
                _ = message.encode() // This can return nil, but we don't need to handle it in performance test
            }
        }
    }
    
    func testDecodingPerformance() throws {
        let message = createTestRoomMessage(withMentions: true)
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode message for performance test")
            return
        }
        
        measure {
            // Measure decoding performance
            for _ in 0..<1000 {
                _ = RoomMessage.decode(from: encoded)
            }
        }
    }
    
    // MARK: - Convenience Method Tests
    
    func testCreateConvenienceMethod() throws {
        let conversationId = createTestConversationId()
        let message = RoomMessage.create(
            for: conversationId,
            sender: "testuser",
            content: "Test message",
            mentions: ["alice"]
        )
        
        XCTAssertEqual(message.conversationId, conversationId)
        XCTAssertEqual(message.sender, "testuser")
        XCTAssertEqual(message.content, "Test message")
        XCTAssertEqual(message.mentions, ["alice"])
        XCTAssertFalse(message.messageId.isEmpty)
    }
    
    // MARK: - Conversation ID Routing Tests
    
    func testConversationIdValidation() throws {
        // Test that conversation IDs must be exactly 32 bytes
        let validId = Data(repeating: 0x42, count: 32)
        let tooShort = Data(repeating: 0x42, count: 16)
        let tooLong = Data(repeating: 0x42, count: 64)
        
        // Valid conversation ID should work
        let validMessage = RoomMessage(conversationId: validId, sender: "test", content: "test")
        XCTAssertNotNil(validMessage.encode())
        
        // Invalid sizes should be rejected during creation validation
        XCTAssertEqual(validId.count, 32)
        XCTAssertNotEqual(tooShort.count, 32)
        XCTAssertNotEqual(tooLong.count, 32)
    }
    
    func testSystemConversationIdGeneration() throws {
        let campusId = "test.university.edu"
        
        // Test announcements ID generation
        let announcementsId1 = TopicManager.announcementsId(campusId: campusId)
        let announcementsId2 = TopicManager.announcementsId(campusId: campusId)
        XCTAssertEqual(announcementsId1, announcementsId2) // Deterministic
        XCTAssertEqual(announcementsId1.count, 32) // Correct size
        
        // Test general ID generation
        let generalId1 = TopicManager.generalId(campusId: campusId)
        let generalId2 = TopicManager.generalId(campusId: campusId)
        XCTAssertEqual(generalId1, generalId2) // Deterministic
        XCTAssertEqual(generalId1.count, 32) // Correct size
        
        // Test broadcast ID generation  
        let broadcastId1 = TopicManager.broadcastId(campusId: campusId)
        let broadcastId2 = TopicManager.broadcastId(campusId: campusId)
        XCTAssertEqual(broadcastId1, broadcastId2) // Deterministic
        XCTAssertEqual(broadcastId1.count, 32) // Correct size
        
        // All system IDs should be different
        XCTAssertNotEqual(announcementsId1, generalId1)
        XCTAssertNotEqual(announcementsId1, broadcastId1)
        XCTAssertNotEqual(generalId1, broadcastId1)
    }
    
    func testDMConversationIdGeneration() throws {
        let campusId = "test.university.edu"
        let peerA = "PEER1234"
        let peerB = "PEER5678"
        
        // Test DM ID generation
        let dmId1 = TopicManager.dmId(peerA: peerA, peerB: peerB, campusId: campusId)
        let dmId2 = TopicManager.dmId(peerA: peerA, peerB: peerB, campusId: campusId)
        XCTAssertEqual(dmId1, dmId2) // Deterministic
        XCTAssertEqual(dmId1.count, 32) // Correct size
        
        // Order shouldn't matter (sorted internally)
        let dmIdReversed = TopicManager.dmId(peerA: peerB, peerB: peerA, campusId: campusId)
        XCTAssertEqual(dmId1, dmIdReversed) // Same regardless of order
        
        // Different peers should produce different IDs
        let differentDmId = TopicManager.dmId(peerA: peerA, peerB: "PEER9999", campusId: campusId)
        XCTAssertNotEqual(dmId1, differentDmId)
    }
    
    // MARK: - MchatMessage Integration Tests
    
    func testRoomMessageToMchatMessageConversion() throws {
        let roomMessage = createTestRoomMessage(withMentions: true)
        let senderPeerID = "PEER1234"
        
        // Convert to MchatMessage
        let mchatMessage = MchatMessage(roomMessage: roomMessage, senderPeerID: senderPeerID)
        
        // Verify all fields are correctly mapped
        XCTAssertEqual(mchatMessage.id, roomMessage.messageId)
        XCTAssertEqual(mchatMessage.sender, roomMessage.sender)
        XCTAssertEqual(mchatMessage.content, roomMessage.content)
        XCTAssertEqual(mchatMessage.timestamp, roomMessage.timestamp)
        XCTAssertEqual(mchatMessage.mentions, roomMessage.mentions)
        XCTAssertEqual(mchatMessage.conversationId, roomMessage.conversationId)
        XCTAssertEqual(mchatMessage.senderPeerID, senderPeerID)
        XCTAssertFalse(mchatMessage.isPrivate) // Room messages are not private
        XCTAssertFalse(mchatMessage.isRelay) // Initial messages are not relays
    }
    
    func testMchatMessageToRoomMessageConversion() throws {
        let conversationId = createTestConversationId()
        let mchatMessage = MchatMessage(
            id: "test-id",
            sender: "testuser",
            content: "Test content",
            timestamp: Date(),
            isRelay: false,
            originalSender: nil,
            isPrivate: false,
            recipientNickname: nil,
            senderPeerID: "PEER1234",
            mentions: ["alice", "bob"],
            deliveryStatus: nil,
            conversationId: conversationId
        )
        
        // Convert to RoomMessage
        guard let roomMessage = mchatMessage.toRoomMessage() else {
            XCTFail("Failed to convert MchatMessage to RoomMessage")
            return
        }
        
        // Verify all fields are correctly mapped
        XCTAssertEqual(roomMessage.messageId, mchatMessage.id)
        XCTAssertEqual(roomMessage.sender, mchatMessage.sender)
        XCTAssertEqual(roomMessage.content, mchatMessage.content)
        XCTAssertEqual(roomMessage.timestamp, mchatMessage.timestamp)
        XCTAssertEqual(roomMessage.mentions, mchatMessage.mentions)
        XCTAssertEqual(roomMessage.conversationId, mchatMessage.conversationId)
    }
    
    func testMchatMessageWithoutConversationIdConversionFails() throws {
        let mchatMessage = MchatMessage(
            sender: "testuser",
            content: "Legacy broadcast message",
            timestamp: Date(),
            isRelay: false,
            conversationId: nil // No conversation ID
        )
        
        // Should fail to convert to RoomMessage without conversationId
        XCTAssertNil(mchatMessage.toRoomMessage())
        
        // Should work with default conversationId
        let defaultConversationId = createTestConversationId()
        let roomMessage = mchatMessage.toRoomMessage(defaultConversationId: defaultConversationId)
        XCTAssertNotNil(roomMessage)
        XCTAssertEqual(roomMessage?.conversationId, defaultConversationId)
    }
    
    // MARK: - Binary Format Validation Tests
    
    func testBinaryEncodingUtilsConsistency() throws {
        let message = createTestRoomMessage(withMentions: true)
        
        guard let encoded = message.encode() else {
            XCTFail("Failed to encode message")
            return
        }
        
        // Manually verify the binary format uses BinaryEncodingUtils correctly
        var offset = 0
        
        // Flags
        guard let flags = encoded.readUInt8(at: &offset) else {
            XCTFail("Failed to read flags")
            return
        }
        XCTAssertEqual(flags & 0x04, 0x04) // hasMentions should be set
        
        // Conversation ID length
        guard let convIdLength = encoded.readUInt8(at: &offset) else {
            XCTFail("Failed to read conversation ID length")
            return
        }
        XCTAssertEqual(convIdLength, 32)
        
        // Conversation ID
        guard let conversationId = encoded.readFixedBytes(at: &offset, count: 32) else {
            XCTFail("Failed to read conversation ID")
            return
        }
        XCTAssertEqual(conversationId, message.conversationId)
        
        // Timestamp
        guard let timestamp = encoded.readDate(at: &offset) else {
            XCTFail("Failed to read timestamp")
            return
        }
        let timeDiff = abs(timestamp.timeIntervalSince(message.timestamp))
        XCTAssertLessThan(timeDiff, 0.001)
        
        // MessageId
        guard let messageId = encoded.readString(at: &offset, maxLength: 255) else {
            XCTFail("Failed to read message ID")
            return
        }
        XCTAssertEqual(messageId, message.messageId)
        
        // Sender
        guard let sender = encoded.readString(at: &offset, maxLength: 255) else {
            XCTFail("Failed to read sender")
            return
        }
        XCTAssertEqual(sender, message.sender)
        
        // Content
        guard let content = encoded.readString(at: &offset, maxLength: 65535) else {
            XCTFail("Failed to read content")
            return
        }
        XCTAssertEqual(content, message.content)
    }
    
    // MARK: - Stress Tests for Room Messages
    
    func testMassiveConversationIdGeneration() throws {
        let campusId = "test.university.edu"
        var generatedIds: Set<Data> = []
        
        // Generate many different conversation IDs
        let departments = ["MATH", "COMP", "PHYS", "CHEM", "BIOL", "ECON", "PSYC", "HIST", "ENGL", "PHIL"]
        let numbers = ["100", "101", "200", "201", "300", "301", "400", "401", "500", "501"]
        let terms = ["FALL2024", "WINTER2024", "SPRING2024", "SUMMER2024"]
        
        for dept in departments {
            for num in numbers {
                for term in terms {
                    let courseData = TopicManager.courseId(dept: dept, num: num, term: term)
                    let sessionData = Data(repeating: 0, count: 8)
                    let topicCode = TopicManager.topicCode(campusId: campusId, course: courseData, session: sessionData)
                    
                    // Verify no collisions
                    XCTAssertFalse(generatedIds.contains(topicCode), 
                                 "Collision detected for \(dept)-\(num) \(term)")
                    XCTAssertEqual(topicCode.count, 32, "Invalid size for \(dept)-\(num) \(term)")
                    generatedIds.insert(topicCode)
                }
            }
        }
        
        // Add system conversations
        generatedIds.insert(TopicManager.announcementsId(campusId: campusId))
        generatedIds.insert(TopicManager.generalId(campusId: campusId))
        generatedIds.insert(TopicManager.broadcastId(campusId: campusId))
        
        // Add DM conversations
        let peerIds = ["PEER1", "PEER2", "PEER3", "PEER4", "PEER5"]
        for i in 0..<peerIds.count {
            for j in (i+1)..<peerIds.count {
                let dmId = TopicManager.dmId(peerA: peerIds[i], peerB: peerIds[j], campusId: campusId)
                XCTAssertFalse(generatedIds.contains(dmId), "DM collision detected")
                generatedIds.insert(dmId)
            }
        }
        
        let expectedCount = departments.count * numbers.count * terms.count + 3 + (peerIds.count * (peerIds.count - 1) / 2)
        XCTAssertEqual(generatedIds.count, expectedCount)
        
        print("Generated \(generatedIds.count) unique conversation IDs without collisions")
    }
}
