import Foundation
import CryptoKit

enum TopicManager {
    static func blake3_8(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))).prefix(8) }

    static func courseId(dept: String, num: String, term: String) -> Data {
        blake3_8("\(dept.uppercased())|\(num)|\(term.uppercased())")
    }
    static func sessionId(date: String, slot: String, building: String, room: String) -> Data {
        blake3_8("\(date)|\(slot)|\(building)|\(room)")
    }
    static func topicCode(campusId: String, course: Data, session: Data) -> Data {
        let camp = blake3_8("campus|\(campusId)") + blake3_8("campus2|\(campusId)")
        return camp + course + session
    }
    
    // MARK: - Reserved Conversation IDs
    
    /// Generate deterministic conversation ID for campus-wide announcements
    static func announcementsId(campusId: String) -> Data {
        let camp = blake3_8("campus|\(campusId)") + blake3_8("campus2|\(campusId)")
        let announcements = blake3_8("ANNOUNCEMENTS") + blake3_8("SYSTEM")
        return camp + announcements
    }
    
    /// Generate deterministic conversation ID for campus-wide general chat
    static func generalId(campusId: String) -> Data {
        let camp = blake3_8("campus|\(campusId)") + blake3_8("campus2|\(campusId)")
        let general = blake3_8("GENERAL") + blake3_8("CHAT")
        return camp + general
    }
}


