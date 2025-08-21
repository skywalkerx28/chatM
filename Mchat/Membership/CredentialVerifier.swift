import Foundation
import CryptoKit

struct CampusCredential {
    let userId: String
    let campusId: String
    let exp: Date
}

final class CredentialVerifier {
    static let shared = CredentialVerifier()
    private init() {}
    
    func verifyJWT(_ jwt: String, region: String, userPoolId: String) async -> CampusCredential? {
        // Split JWT
        let parts = jwt.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let headerData = base64urlDecode(parts[0]),
              let payloadData = base64urlDecode(parts[1]),
              let sigData = base64urlDecode(parts[2]) else { return nil }
        
        // Parse header to get kid and alg
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let kid = header["kid"] as? String,
              let alg = header["alg"] as? String else { return nil }
        
        // Only support RS256 now (Cognito default); ES256 can be added similarly
        guard alg == "RS256" else { return nil }
        
        // Recreate signing input
        let signingInput = Data((parts[0] + "." + parts[1]).utf8)
        
        // Fetch JWKS key
        guard let secKey = await JWKSCache.shared.getKey(kid: kid, region: region, userPoolId: userPoolId) else { return nil }
        
        // Verify RSASSA-PKCS1-v1_5 with SHA256
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, signingInput as CFData, sigData as CFData, &error)
        guard ok else { return nil }
        
        // Decode payload and extract claims
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
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
