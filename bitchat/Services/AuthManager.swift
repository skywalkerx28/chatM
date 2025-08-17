//
// AuthManager.swift
// chatM
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import SwiftUI
#if os(iOS)
import AuthenticationServices
import CryptoKit
#endif

public final class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""

    // Stored tokens
    private(set) var accessToken: String? = nil
    private(set) var idToken: String? = nil
    private(set) var refreshToken: String? = nil
    private(set) var accessTokenExpiry: Date? = nil

    // Config from Info.plist
    private let cognitoDomain: String
    private let clientId: String
    private let redirectURI: String

    // PKCE state
    #if os(iOS)
    private var currentCodeVerifier: String? = nil
    private var currentState: String? = nil
    private var authSession: ASWebAuthenticationSession? = nil
    #endif

    override init() {
        let bundle = Bundle.main
        self.cognitoDomain = (bundle.object(forInfoDictionaryKey: "CognitoDomain") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.clientId = (bundle.object(forInfoDictionaryKey: "CognitoClientId") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.redirectURI = (bundle.object(forInfoDictionaryKey: "CognitoRedirectURI") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "chatm://auth/callback"

        super.init()
        loadFromKeychain()
        Task { @MainActor in
            if let expiry = accessTokenExpiry, expiry.timeIntervalSinceNow < 60 {
                await refreshIfNeeded()
            } else {
                self.isAuthenticated = (self.accessToken != nil)
            }
        }
    }

    @MainActor
    func startSignIn() {
        #if os(iOS)
        guard !cognitoDomain.isEmpty, !clientId.isEmpty, !redirectURI.isEmpty else {
            self.statusMessage = "Missing Cognito configuration. Set CognitoDomain and CognitoClientId in Info.plist."
            return
        }

        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)
        currentCodeVerifier = codeVerifier
        currentState = UUID().uuidString

        var components = URLComponents(string: cognitoDomain + "/oauth2/authorize")!
        let scope = "openid email"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: currentState)
        ]

        guard let url = components.url else { return }

        isLoading = true
        statusMessage = "Opening sign-in..."
        let scheme = "chatm"

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.statusMessage = "Sign-in canceled"
                    print("Auth error: \(error)")
                    return
                }
                guard let callbackURL = callbackURL else {
                    self.statusMessage = "No callback URL"
                    return
                }

                self.handleRedirectURL(callbackURL)
            }
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        self.authSession = session
        _ = session.start()
        #else
        // Non-iOS platforms skip auth for now
        self.isAuthenticated = true
        #endif
    }

    @MainActor
    func handleRedirectURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value

        if let expected = currentState, let returned = state, expected != returned {
            self.statusMessage = "State mismatch"
            return
        }
        guard let code = code else {
            self.statusMessage = "No auth code returned"
            return
        }

        Task { @MainActor in
            await exchangeCodeForTokens(code: code)
        }
    }

    @MainActor
    func signOut() {
        accessToken = nil
        idToken = nil
        refreshToken = nil
        accessTokenExpiry = nil
        isAuthenticated = false
        statusMessage = "Signed out"

        _ = KeychainManager.shared.delete(forKey: "auth_access_token")
        _ = KeychainManager.shared.delete(forKey: "auth_id_token")
        _ = KeychainManager.shared.delete(forKey: "auth_refresh_token")
        _ = KeychainManager.shared.delete(forKey: "auth_expiry")
    }

    @MainActor
    func refreshIfNeeded() async {
        guard let expiry = accessTokenExpiry else { return }
        if expiry.timeIntervalSinceNow > 60 { return }
        guard let refreshToken = refreshToken else { return }

        guard !cognitoDomain.isEmpty, !clientId.isEmpty else { return }

        var request = URLRequest(url: URL(string: cognitoDomain + "/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]

        request.httpBody = Self.formURLEncoded(items: bodyItems).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.statusMessage = "Refresh failed"
                return
            }
            try self.handleTokenResponseData(data)
            self.statusMessage = "Session refreshed"
        } catch {
            self.statusMessage = "Refresh error"
        }
    }

    // MARK: - Private

    @MainActor
    private func exchangeCodeForTokens(code: String) async {
        guard let verifier = currentCodeVerifier else { return }
        guard !cognitoDomain.isEmpty, !clientId.isEmpty, !redirectURI.isEmpty else {
            self.statusMessage = "Missing Cognito configuration"
            return
        }

        var request = URLRequest(url: URL(string: cognitoDomain + "/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]

        request.httpBody = Self.formURLEncoded(items: bodyItems).data(using: .utf8)

        isLoading = true
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            isLoading = false
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.statusMessage = "Token exchange failed"
                return
            }
            try handleTokenResponseData(data)
            self.isAuthenticated = true
            self.statusMessage = "Signed in"
            await self.postSignInBootstrap()
        } catch {
            isLoading = false
            self.statusMessage = "Token exchange error"
        }
    }

    @MainActor
    private func postSignInBootstrap() async {
        guard let idToken = self.idToken else { return }
        do {
            let profile = try await APIClient.me(idToken: idToken)
            MembershipCredentialManager.shared.setProfile(profile)
            let noiseService = NoiseEncryptionService()
            let devicePubBase64 = Data(noiseService.getStaticPublicKeyData()).base64EncodedString()
            let credData = try await APIClient.issue(idToken: idToken, devicePubBase64: devicePubBase64)
            if let credential = try? JSONDecoder().decode(MembershipCredential.self, from: credData) {
                MembershipCredentialManager.shared.setCredential(credential)
            }
        } catch {
            self.statusMessage = "Profile bootstrap failed"
        }
    }

    @MainActor
    private func handleTokenResponseData(_ data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let accessToken = json?["access_token"] as? String
        let idToken = json?["id_token"] as? String
        let refreshToken = json?["refresh_token"] as? String ?? self.refreshToken // may be absent on refresh
        let expiresIn = json?["expires_in"] as? Double

        self.accessToken = accessToken
        self.idToken = idToken
        self.refreshToken = refreshToken

        if let expiresIn = expiresIn {
            self.accessTokenExpiry = Date().addingTimeInterval(expiresIn)
        } else {
            self.accessTokenExpiry = Date().addingTimeInterval(3600)
        }

        if let accessToken = accessToken { _ = KeychainManager.shared.save(accessToken, forKey: "auth_access_token") }
        if let idToken = idToken { _ = KeychainManager.shared.save(idToken, forKey: "auth_id_token") }
        if let refreshToken = refreshToken { _ = KeychainManager.shared.save(refreshToken, forKey: "auth_refresh_token") }
        if let expiry = accessTokenExpiry {
            let timestamp = String(Int64(expiry.timeIntervalSince1970))
            _ = KeychainManager.shared.save(timestamp, forKey: "auth_expiry")
        }
    }

    private func loadFromKeychain() {
        if let at = KeychainManager.shared.retrieve(forKey: "auth_access_token") { self.accessToken = at }
        if let it = KeychainManager.shared.retrieve(forKey: "auth_id_token") { self.idToken = it }
        if let rt = KeychainManager.shared.retrieve(forKey: "auth_refresh_token") { self.refreshToken = rt }
        if let expStr = KeychainManager.shared.retrieve(forKey: "auth_expiry"), let ts = TimeInterval(expStr) {
            self.accessTokenExpiry = Date(timeIntervalSince1970: ts)
        }
        self.isAuthenticated = (self.accessToken != nil)
    }

    private static func formURLEncoded(items: [URLQueryItem]) -> String {
        items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }

    #if os(iOS)
    private static func generateCodeVerifier() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = ""
        for _ in 0..<64 { result.append(chars.randomElement()!) }
        return result
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        let hashed = Data(digest)
        return base64URLEncode(hashed)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    #endif
}

#if os(iOS)
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
#endif


