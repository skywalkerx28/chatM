import Foundation
@testable import chatM

/// Mock credential verifier for testing - bypasses JWT signature verification
class MockCredentialVerifier {
    static let shared = MockCredentialVerifier()
    private init() {}
    
    func verifyJWT(_ jwt: String) -> CampusCredential? {
        // Parse JWT payload without signature verification for tests
        let parts = jwt.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let payloadData = base64urlDecode(parts[1]),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let sub = payload["sub"] as? String,
              let campusId = payload["campus_id"] as? String,
              let exp = payload["exp"] as? Double else { return nil }
        
        return CampusCredential(userId: sub, campusId: campusId, exp: Date(timeIntervalSince1970: exp))
    }
    
    private func base64urlDecode(_ str: String) -> Data? {
        var s = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (s.count % 4)
        if padding < 4 { s += String(repeating: "=", count: padding) }
        return Data(base64Encoded: s)
    }
}
