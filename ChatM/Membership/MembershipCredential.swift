import Foundation

struct MembershipCredential: Codable {
    let campus_id: String
    let device_pub: String
    let iat: Int
    let exp: Int
    let kid: String
}


