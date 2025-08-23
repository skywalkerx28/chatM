import Foundation
import Amplify
import AWSCognitoAuthPlugin
import AWSPluginsCore

struct AuthService {
    static func isSignedIn() async -> Bool {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            return session.isSignedIn
        } catch {
            return false
        }
    }

    static func ensureSignedOut() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn {
                _ = await Amplify.Auth.signOut()
            }
        } catch {
            // ignore
        }
    }
    static func signUp(email: String, password: String, username: String, campusId: String? = nil) async throws -> String {
        var attrs = [
            AuthUserAttribute(.email, value: email),
            AuthUserAttribute(.preferredUsername, value: username)
        ]
        
        // Add campus_id if provided, or derive from email domain
        let finalCampusId = campusId ?? deriveCampusFromEmail(email)
        attrs.append(AuthUserAttribute(.custom("campus_id"), value: finalCampusId))
        // Generate an internal username that is opaque to the user.
        let internalUsername = "u_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = try await Amplify.Auth.signUp(
            username: internalUsername,
            password: password,
            options: .init(userAttributes: attrs)
        )
        return internalUsername
    }

    static func signUp(email: String, password: String) async throws {
        // Fallback helper that also respects email-alias pools by generating an internal username
        let attrs = [AuthUserAttribute(.email, value: email)]
        let internalUsername = "u_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = try await Amplify.Auth.signUp(username: internalUsername, password: password, options: .init(userAttributes: attrs))
    }
    static func confirm(username: String, code: String) async throws {
        _ = try await Amplify.Auth.confirmSignUp(for: username, confirmationCode: code)
    }
    static func signIn(username: String, password: String) async throws {
        await ensureSignedOut()
        let r = try await Amplify.Auth.signIn(username: username, password: password)
        guard r.isSignedIn else { throw NSError(domain: "ChatM.Auth", code: 1) }
    }
    static func idToken() async throws -> String {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard let provider = session as? AuthCognitoTokensProvider else {
            throw NSError(domain: "ChatM.Auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Cognito tokens provider available"])
        }
        let tokens = try provider.getCognitoTokens().get()
        return tokens.idToken
    }
    
    static func getAllTokens() async throws -> (idToken: String, accessToken: String, refreshToken: String?) {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard let provider = session as? AuthCognitoTokensProvider else {
            throw NSError(domain: "ChatM.Auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Cognito tokens provider available"])
        }
        let tokens = try provider.getCognitoTokens().get()
        return (
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
    }
    static func signOut() async {
        _ = await Amplify.Auth.signOut()
    }
    
    /// Derive campus ID from email domain
    private static func deriveCampusFromEmail(_ email: String) -> String {
        let domain = email.split(separator: "@").last?.lowercased() ?? ""
        
        // Map common university domains to campus IDs
        switch domain {
        case "mail.mcgill.ca", "mcgill.ca":
            return "mcgill"
        case "gmail.com":
            return "mcgill"
        // Add more universities as needed
        default:
            // For unknown domains, intelligently extract the main domain name
            return extractMainDomainName(from: domain)
        }
    }
    
    /// Extract the main domain name from a full domain, removing TLDs and subdomains
    private static func extractMainDomainName(from fullDomain: String) -> String {
        let parts = fullDomain.split(separator: ".")
        
        // Common TLDs to remove
        let commonTLDs = ["com", "ca", "edu", "org", "net", "gov", "mil", "int", "ac", "co"]
        
        // If domain has multiple parts, try to extract the main institution name
        if parts.count >= 2 {
            let lastPart = String(parts.last ?? "")
            let secondLastPart = parts.count >= 2 ? String(parts[parts.count - 2]) : ""
            
            // If last part is a common TLD, use the second-to-last part as main domain
            if commonTLDs.contains(lastPart) {
                // For cases like "mail.mcgill.ca" or "student.ubc.ca", prefer the institution name
                if parts.count >= 3 {
                    let thirdLastPart = String(parts[parts.count - 3])
                    // If middle part looks like an institution (longer than subdomain prefixes)
                    if secondLastPart.count > 3 && !["mail", "www", "student", "alumni", "staff"].contains(secondLastPart) {
                        return String(secondLastPart.prefix(8)) // Ensure 8-char limit
                    } else if thirdLastPart.count > 2 {
                        return String(thirdLastPart.prefix(8)) // Use institution name
                    }
                }
                return String(secondLastPart.prefix(8)) // Default to second-to-last
            }
        }
        
        // Fallback: use first part of domain, truncated to 8 chars
        let firstPart = parts.first.map(String.init) ?? fullDomain
        return String(firstPart.prefix(8))
    }
}


