import Foundation

final class CampusGate {
    private var presence: [String: (String, TimeInterval)] = [:]
    private let presenceTTL: TimeInterval = 15 * 60

    func acceptPresence(senderId: String, campusId: String, exp: Int) {
        let now = Date().timeIntervalSince1970
        let until = now + min(TimeInterval(exp - Int(now)), presenceTTL)
        presence[senderId] = (campusId, until)
    }

    func shouldAcceptMessage(from senderId: String, topicCampusId: String) -> Bool {
        guard let (campusId, until) = presence[senderId] else { return false }
        guard campusId == topicCampusId else { return false }
        return Date().timeIntervalSince1970 < until
    }
}


