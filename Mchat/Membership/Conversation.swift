import Foundation

/// Represents a conversation/channel in the Mchat system
struct Conversation: Codable, Identifiable, Equatable {
    let id: Data                    // 32-byte deterministic conversation ID
    let displayName: String         // Human-readable name (e.g., "MATH-262", "Announcements")
    let campusId: String           // Campus this conversation belongs to
    let isAnnouncements: Bool      // Whether this is the special announcements channel
    let isGeneral: Bool            // Whether this is the general campus channel
    let courseInfo: CourseInfo?    // Optional course details for academic conversations
    let joinedAt: Date            // When user joined this conversation
    
    /// Course information for academic conversations
    struct CourseInfo: Codable, Equatable {
        let department: String     // e.g., "MATH"
        let number: String        // e.g., "262"
        let term: String          // e.g., "FALL2024"
        let sessionInfo: SessionInfo?
        
        struct SessionInfo: Codable, Equatable {
            let date: String      // e.g., "2024-01-15"
            let slot: String      // e.g., "10:00-11:30"
            let building: String  // e.g., "BURNSIDE"
            let room: String      // e.g., "1B45"
        }
    }
    
    init(id: Data, displayName: String, campusId: String, isAnnouncements: Bool = false, isGeneral: Bool = false, courseInfo: CourseInfo? = nil, joinedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.campusId = campusId
        self.isAnnouncements = isAnnouncements
        self.isGeneral = isGeneral
        self.courseInfo = courseInfo
        self.joinedAt = joinedAt ?? Date()
    }
    
    // MARK: - Convenience Initializers
    
    /// Create announcements conversation for a campus
    static func announcements(campusId: String) -> Conversation {
        let id = TopicManager.announcementsId(campusId: campusId)
        return Conversation(
            id: id,
            displayName: "Announcements",
            campusId: campusId,
            isAnnouncements: true
        )
    }
    
    /// Create general conversation for a campus
    static func general(campusId: String) -> Conversation {
        let id = TopicManager.generalId(campusId: campusId)
        return Conversation(
            id: id,
            displayName: "General",
            campusId: campusId,
            isGeneral: true
        )
    }
    
    /// Create Schulich School conversation for campus
    static func schulich(campusId: String) -> Conversation {
        let id = TopicManager.schulichId(campusId: campusId)
        return Conversation(
            id: id,
            displayName: "Schulich",
            campusId: campusId
        )
    }
    
    /// Create course conversation
    static func course(department: String, number: String, term: String, campusId: String, sessionInfo: CourseInfo.SessionInfo? = nil) -> Conversation {
        let courseData = TopicManager.courseId(dept: department, num: number, term: term)
        let sessionData = sessionInfo.map { info in
            TopicManager.sessionId(date: info.date, slot: info.slot, building: info.building, room: info.room)
        } ?? Data(repeating: 0, count: 8)
        
        let id = TopicManager.topicCode(campusId: campusId, course: courseData, session: sessionData)
        
        let displayName = sessionInfo != nil 
            ? "\(department)-\(number) (\(sessionInfo!.slot))"
            : "\(department)-\(number)"
        
        let courseInfo = CourseInfo(
            department: department,
            number: number,
            term: term,
            sessionInfo: sessionInfo
        )
        
        return Conversation(
            id: id,
            displayName: displayName,
            campusId: campusId,
            courseInfo: courseInfo
        )
    }
    
    // MARK: - Computed Properties
    
    /// Whether this conversation is a system/reserved conversation
    var isSystemConversation: Bool {
        return isAnnouncements || isGeneral
    }
    
    /// Whether this conversation is course-related
    var isCourseConversation: Bool {
        return courseInfo != nil
    }
    
    /// Hex string representation of the conversation ID for debugging
    var idHex: String {
        return id.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Extensions

extension Conversation {
    /// Check if two conversations represent the same room (by ID)
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        return lhs.id == rhs.id
    }
    
    /// Hash based on conversation ID for use in sets/dictionaries
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
