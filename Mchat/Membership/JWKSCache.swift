import Foundation
import Security

struct JWK: Decodable {
    let kty: String
    let kid: String
    let use: String?
    let n: String? // modulus (base64url)
    let e: String? // exponent (base64url)
    let crv: String?
    let x: String?
    let y: String?
    let alg: String?
}

struct JWKS: Decodable {
    let keys: [JWK]
}

final class JWKSCache {
    static let shared = JWKSCache()
    private init() {}
    
    private var keysByKid: [String: SecKey] = [:]
    private var lastFetch: Date?
    private let cacheTTL: TimeInterval = 6 * 60 * 60 // 6 hours
    
    private func base64urlDecode(_ str: String) -> Data? {
        var s = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (s.count % 4)
        if padding < 4 { s += String(repeating: "=", count: padding) }
        return Data(base64Encoded: s)
    }
    
    func getKey(kid: String, region: String, userPoolId: String) async -> SecKey? {
        if let k = keysByKid[kid], let last = lastFetch, Date().timeIntervalSince(last) < cacheTTL {
            return k
        }
        await fetchJWKS(region: region, userPoolId: userPoolId)
        return keysByKid[kid]
    }
    
    private func fetchJWKS(region: String, userPoolId: String) async {
        let urlStr = "https://cognito-idp.\(region).amazonaws.com/\(userPoolId)/.well-known/jwks.json"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let jwks = try JSONDecoder().decode(JWKS.self, from: data)
            var newMap: [String: SecKey] = [:]
            for jwk in jwks.keys where jwk.kty == "RSA", let n = jwk.n, let e = jwk.e,
                                          let nData = base64urlDecode(n), let eData = base64urlDecode(e) {
                if let key = rsaPublicKey(modulus: nData, exponent: eData, kid: jwk.kid) {
                    newMap[jwk.kid] = key
                }
            }
            if !newMap.isEmpty {
                keysByKid = newMap
                lastFetch = Date()
            }
        } catch {
            // ignore
        }
    }
    
    private func rsaPublicKey(modulus: Data, exponent: Data, kid: String) -> SecKey? {
        // Build ASN.1 RSAPublicKey (SEQUENCE of modulus INTEGER and exponent INTEGER)
        func asn1Length(_ length: Int) -> Data {
            if length < 128 { return Data([UInt8(length)]) }
            var len = length
            var bytes: [UInt8] = []
            while len > 0 { bytes.insert(UInt8(len & 0xFF), at: 0); len >>= 8 }
            return Data([0x80 | UInt8(bytes.count)] + bytes)
        }
        func asn1Integer(_ data: Data) -> Data {
            var d = data
            if d.first ?? 0 >= 0x80 { d.insert(0x00, at: 0) } // ensure positive
            var out = Data([0x02])
            out.append(asn1Length(d.count))
            out.append(d)
            return out
        }
        let modulusInt = asn1Integer(modulus)
        let exponentInt = asn1Integer(exponent)
        var seq = Data([0x30])
        let body = modulusInt + exponentInt
        seq.append(asn1Length(body.count))
        seq.append(body)
        
        let keyData = seq
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: modulus.count * 8,
            kSecAttrIsPermanent as String: false,
            kSecAttrApplicationTag as String: "chatm.jwks.\(kid)"
        ]
        return SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, nil)
    }
}
