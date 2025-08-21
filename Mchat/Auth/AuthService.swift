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
    static func signUp(email: String, password: String, username: String) async throws -> String {
        let attrs = [
            AuthUserAttribute(.email, value: email),
            AuthUserAttribute(.preferredUsername, value: username)
        ]
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
    static func signOut() async {
        _ = await Amplify.Auth.signOut()
    }
}


