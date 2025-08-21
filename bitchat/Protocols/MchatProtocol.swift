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
    /// Uses BinaryEncodingUtils for consistent and efficient encoding
    func encode() -> Data? {
        var data = Data()
        
        // Flags (1 byte)
        var flags: UInt8 = 0
        if isEncrypted { flags |= 0x02 }  // Bit 1
        if hasMentions { flags |= 0x04 }  // Bit 2
        data.appendUInt8(flags)
        
        // ConversationIdLength (1 byte) - fixed to 32
        data.appendUInt8(0x20) // Always 32 bytes
        
        // ConversationId (32 bytes)
        data.append(conversationId)
        
        // Timestamp (8 bytes, milliseconds since epoch) - use utility function
        data.appendDate(timestamp)
        
        // MessageId (variable length, max 255) - use utility function
        data.appendString(messageId, maxLength: 255)
        
        // Sender (variable length, max 255) - use utility function
        data.appendString(sender, maxLength: 255)
        
        // Content (variable length, max 65535) - use utility function  
        data.appendString(content, maxLength: 65535)
        
        // Optional fields - mentions array
        if let mentions = mentions, !mentions.isEmpty {
            data.appendUInt8(UInt8(min(mentions.count, 255))) // Number of mentions
            for mention in mentions.prefix(255) {
                data.appendString(mention, maxLength: 255)
            }
        }
        
        return data
    }
    
    /// Decodes a room message from binary format
    /// Uses BinaryEncodingUtils for consistent and safe decoding
    static func decode(from data: Data) -> RoomMessage? {
        guard data.count >= 44 else { return nil } // Minimum size check
        
        var offset = 0
        
        // Flags - use utility function
        guard let flags = data.readUInt8(at: &offset) else { return nil }
        let hasMentions = (flags & 0x04) != 0
        
        // ConversationId length - use utility function
        guard let conversationIdLength = data.readUInt8(at: &offset),
              conversationIdLength == 32 else { return nil } // Must be exactly 32 bytes
        
        // ConversationId - use utility function
        guard let conversationId = data.readFixedBytes(at: &offset, count: 32) else { return nil }
        
        // Timestamp - use utility function
        guard let timestamp = data.readDate(at: &offset) else { return nil }
        
        // MessageId - use utility function
        guard let messageId = data.readString(at: &offset, maxLength: 255) else { return nil }
        
        // Sender - use utility function
        guard let sender = data.readString(at: &offset, maxLength: 255) else { return nil }
        
        // Content - use utility function
        guard let content = data.readString(at: &offset, maxLength: 65535) else { return nil }
        
        // Mentions (if present) - use utility functions
        var mentions: [String]? = nil
        if hasMentions {
            guard let mentionCount = data.readUInt8(at: &offset) else { return nil }
            if mentionCount > 0 {
                mentions = []
                for _ in 0..<mentionCount {
                    guard let mention = data.readString(at: &offset, maxLength: 255) else { break }
                    mentions?.append(mention)
                }
            }
        }
        
        return RoomMessage(
            conversationId: conversationId,
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
