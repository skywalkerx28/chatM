//
// MchatProtocol.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

///
/// # MchatProtocol
///
/// Defines the Mchat-specific protocol extensions for room/channel messaging,
/// building on top of the existing BitChat protocol foundation.
///
/// ## Overview
/// MchatProtocol implements conversation-based messaging with:
/// - Deterministic conversation IDs for room isolation
/// - CampusGate integration for access control
/// - Binary encoding optimized for BLE constraints
/// - Support for campus-wide announcements and general rooms
///
/// ## Room Message Format
/// ```
/// RoomMessage Binary Layout:
/// +-------+------------------+-----------------+----------+
/// | Flags | ConversationId   | Timestamp       | Sender   |
/// |1 byte | 32 bytes         | 8 bytes         | Variable |
/// +-------+------------------+-----------------+----------+
/// | MessageId | Content       | Mentions        |
/// | Variable  | Variable      | Optional        |
/// +-----------+---------------+-----------------+
/// ```
///
/// ## Flag Bits
/// - Bit 0: Reserved for future use
/// - Bit 1: isEncrypted (reserved for room passwords - not implemented yet)
/// - Bit 2: hasMentions (mentions array present)
/// - Bits 3-7: Reserved for future extensions
///

import Foundation

// MARK: - Room Message Structure

/// Represents a message sent to a specific conversation/channel.
/// Contains conversation ID for routing and optional metadata.
struct RoomMessage {
    let conversationId: Data        // 32 bytes - deterministic conversation identifier
    let messageId: String          // Unique message identifier
    let sender: String             // Sender's nickname
    let content: String            // Message content
    let timestamp: Date            // Message timestamp
    let mentions: [String]?        // Optional array of mentioned usernames
    
    // Flag bits
    private let isEncrypted: Bool = false  // Reserved for future room password feature
    private var hasMentions: Bool { mentions?.isEmpty == false }
    
    init(conversationId: Data, messageId: String? = nil, sender: String, content: String, timestamp: Date? = nil, mentions: [String]? = nil) {
        self.conversationId = conversationId
        self.messageId = messageId ?? UUID().uuidString
        self.sender = sender
        self.content = content
        self.timestamp = timestamp ?? Date()
        self.mentions = mentions
    }
}

// MARK: - Binary Encoding

extension RoomMessage {
    
    /// Encodes the room message to binary format for transmission
    func encode() -> Data? {
        var data = Data()
        
        // Flags (1 byte)
        var flags: UInt8 = 0
        if isEncrypted { flags |= 0x02 }  // Bit 1
        if hasMentions { flags |= 0x04 }  // Bit 2
        data.append(flags)
        
        // ConversationIdLength (1 byte) - fixed to 32
        data.append(0x20) // Always 32 bytes
        
        // ConversationId (32 bytes)
        data.append(conversationId)
        
        // Timestamp (8 bytes, milliseconds since epoch)
        let timestampMillis = UInt64(timestamp.timeIntervalSince1970 * 1000)
        for i in (0..<8).reversed() {
            data.append(UInt8((timestampMillis >> (i * 8)) & 0xFF))
        }
        
        // MessageId (variable length, max 255)
        if let messageIdData = messageId.data(using: .utf8) {
            data.append(UInt8(min(messageIdData.count, 255)))
            data.append(messageIdData.prefix(255))
        } else {
            data.append(0) // Should not happen if messageId is always set
        }
        
        // Sender (variable length, max 255)
        if let senderData = sender.data(using: .utf8) {
            data.append(UInt8(min(senderData.count, 255)))
            data.append(senderData.prefix(255))
        } else {
            data.append(0) // Should not happen if sender is always set
        }
        
        // Content (variable length, max 65535)
        if let contentData = content.data(using: .utf8) {
            let length = UInt16(min(contentData.count, 65535))
            // Encode length as 2 bytes, big-endian
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
            data.append(contentData.prefix(Int(length)))
        } else {
            data.append(contentsOf: [0, 0]) // Should not happen if content is always set
        }
        
        // Optional fields
        if let mentions = mentions, !mentions.isEmpty {
            data.append(UInt8(min(mentions.count, 255))) // Number of mentions
            for mention in mentions.prefix(255) {
                if let mentionData = mention.data(using: .utf8) {
                    data.append(UInt8(min(mentionData.count, 255)))
                    data.append(mentionData.prefix(255))
                } else {
                    data.append(0) // Should not happen if mention is always set
                }
            }
        }
        
        return data
    }
    
    /// Decodes a room message from binary format
    static func decode(from data: Data) -> RoomMessage? {
        guard data.count >= 44 else { return nil } // Minimum size check
        
        var offset = 0
        
        // Flags
        guard offset < data.count else { return nil }
        let flags = data[offset]; offset += 1
        let hasMentions = (flags & 0x04) != 0
        
        // ConversationId length
        guard offset < data.count else { return nil }
        let conversationIdLength = Int(data[offset]); offset += 1
        guard conversationIdLength == 32 else { return nil } // Must be exactly 32 bytes
        
        // ConversationId
        guard offset + 32 <= data.count else { return nil }
        let conversationId = data[offset..<offset+32]
        offset += 32
        
        // Timestamp
        guard offset + 8 <= data.count else { return nil }
        let timestampData = data[offset..<offset+8]
        let timestampMillis = timestampData.reduce(0) { result, byte in
            (result << 8) | UInt64(byte)
        }
        offset += 8
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
        
        // MessageId
        guard offset < data.count else { return nil }
        let messageIdLength = Int(data[offset]); offset += 1
        guard offset + messageIdLength <= data.count else { return nil }
        let messageId = String(data: data[offset..<offset+messageIdLength], encoding: .utf8) ?? UUID().uuidString
        offset += messageIdLength
        
        // Sender
        guard offset < data.count else { return nil }
        let senderLength = Int(data[offset]); offset += 1
        guard offset + senderLength <= data.count else { return nil }
        let sender = String(data: data[offset..<offset+senderLength], encoding: .utf8) ?? "unknown"
        offset += senderLength
        
        // Content
        guard offset + 2 <= data.count else { return nil }
        let contentLengthData = data[offset..<offset+2]
        let contentLength = Int(contentLengthData.reduce(0) { result, byte in
            (result << 8) | UInt16(byte)
        })
        offset += 2
        guard offset + contentLength <= data.count else { return nil }
        let content = String(data: data[offset..<offset+contentLength], encoding: .utf8) ?? ""
        offset += contentLength
        
        // Mentions (if present)
        var mentions: [String]? = nil
        if hasMentions && offset < data.count {
            let mentionCount = Int(data[offset]); offset += 1
            if mentionCount > 0 {
                mentions = []
                for _ in 0..<mentionCount {
                    guard offset < data.count else { break }
                    let length = Int(data[offset]); offset += 1
                    guard offset + length <= data.count else { break }
                    if let mention = String(data: data[offset..<offset+length], encoding: .utf8) {
                        mentions?.append(mention)
                    }
                    offset += length
                }
            }
        }
        
        return RoomMessage(
            conversationId: Data(conversationId),
            messageId: messageId,
            sender: sender,
            content: content,
            timestamp: timestamp,
            mentions: mentions
        )
    }
}

// MARK: - Convenience Extensions

extension RoomMessage {
    /// Create a room message for a specific conversation
    static func create(for conversationId: Data, sender: String, content: String, mentions: [String]? = nil) -> RoomMessage {
        return RoomMessage(
            conversationId: conversationId,
            sender: sender,
            content: content,
            mentions: mentions
        )
    }
}
