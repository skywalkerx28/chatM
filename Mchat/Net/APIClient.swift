import Foundation

struct UserProfile: Decodable { let handle: String; let campus_id: String; let aid: String; let created_at: String }

enum APIClient {
    static func me(idToken: String) async throws -> UserProfile {
        var req = URLRequest(url: URL(string: "\(Config.apiBaseURL)/me")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain:"ChatM.API", code:1) }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
    static func issue(idToken: String, devicePubBase64: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(Config.apiBaseURL)/issue")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["device_pub": devicePubBase64])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain:"ChatM.API", code:2) }
        return data
    }
}


