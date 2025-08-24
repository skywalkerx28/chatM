import Foundation
import CryptoKit

enum TopicManager {
    static func sha256_8(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))).prefix(8) }

    static func courseId(dept: String, num: String, term: String) -> Data {
        sha256_8("\(dept.uppercased())|\(num)|\(term.uppercased())")
    }
    static func sessionId(date: String, slot: String, building: String, room: String) -> Data {
        sha256_8("\(date)|\(slot)|\(building)|\(room)")
    }
    static func topicCode(campusId: String, course: Data, session: Data) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        return camp + course + session
    }
    
        // MARK: - Reserved Conversation IDs

    /// Generate deterministic conversation ID for campus-wide announcements
    static func announcementsId(campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        let announcements = sha256_8("ANNOUNCEMENTS") + sha256_8("SYSTEM")
        return camp + announcements
    }

    /// Generate deterministic conversation ID for campus-wide general chat
    static func generalId(campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        let general = sha256_8("GENERAL") + sha256_8("CHAT")
        return camp + general
    }

    /// Generate deterministic conversation ID for campus-wide broadcast messages
    /// This replaces legacy broadcast messages with a proper conversation ID
    static func broadcastId(campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        let broadcast = sha256_8("BROADCAST") + sha256_8("PUBLIC")
        return camp + broadcast
    }

    /// Generate deterministic conversation ID for Schulich 
    static func schulichId(campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        let schulich = sha256_8("SCHULICH") + sha256_8("BUSINESS")
        return camp + schulich
    }

    /// Generate deterministic conversation ID for 1:1 DM conversations using canonical user IDs
    /// Uses sorted user IDs to ensure same ID regardless of who initiates
    static func canonicalDmId(userIdA: String, userIdB: String, campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        
        // Sort user IDs to ensure deterministic ordering
        let sortedUsers = [userIdA, userIdB].sorted()
        let dm1 = sha256_8("CDM|\(sortedUsers[0])") // CDM = Canonical DM
        let dm2 = sha256_8("CDM|\(sortedUsers[1])")
        
        return camp + dm1 + dm2
    }
    
    /// Generate deterministic conversation ID for 1:1 DM conversations (legacy using peer IDs)
    /// Uses sorted peer IDs to ensure same ID regardless of who initiates
    /// @deprecated Use canonicalDmId instead for stable user identity
    static func dmId(peerA: String, peerB: String, campusId: String) -> Data {
        let camp = sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
        
        // Sort peer IDs to ensure deterministic ordering
        let sortedPeers = [peerA, peerB].sorted()
        let dm1 = sha256_8("DM|\(sortedPeers[0])")
        let dm2 = sha256_8("DM|\(sortedPeers[1])")
        
        return camp + dm1 + dm2
    }
    
    // MARK: - Campus Prefix Utilities
    
    /// Generate 16-byte campus prefix for a given campus ID
    static func campusPrefix16(campusId: String) -> Data {
        return sha256_8("campus|\(campusId)") + sha256_8("campus2|\(campusId)")
    }
    
    /// Extract campus prefix from conversation ID (first 16 bytes)
    static func extractCampusPrefix16(from conversationId: Data) -> Data? {
        guard conversationId.count >= 16 else { return nil }
        return conversationId.prefix(16)
    }
    
    /// Check if conversation ID matches campus
    static func isConversationForCampus(conversationId: Data, campusId: String) -> Bool {
        guard let extractedPrefix = extractCampusPrefix16(from: conversationId) else { return false }
        let expectedPrefix = campusPrefix16(campusId: campusId)
        return extractedPrefix == expectedPrefix
    }
}


