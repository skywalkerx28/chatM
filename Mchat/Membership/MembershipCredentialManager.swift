import Foundation

final class MembershipCredentialManager {
    static let shared = MembershipCredentialManager()
    private init() {}

    private var profile: UserProfile?
    private var credential: MembershipCredential?

    func setProfile(_ p: UserProfile) { profile = p }
    func currentProfile() -> UserProfile? { profile }

    func setCredential(_ c: MembershipCredential) { credential = c }
    func currentCredential() -> MembershipCredential? { credential }

    func presenceBlob() -> Data? {
        guard let p = profile, let c = credential else { return nil }
        let obj: [String: Any] = [
            "t": "presence",
            "campus_id": p.campus_id,
            "handle": p.handle,
            "credential": [
                "campus_id": c.campus_id,
                "device_pub": c.device_pub,
                "exp": c.exp,
                "kid": c.kid
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: obj)
    }
}


