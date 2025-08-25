//
// AuthManager.swift
// chatM
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import SwiftUI

public final class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""

    // Stored tokens
    private(set) var accessToken: String? = nil
    private(set) var idToken: String? = nil
    private(set) var refreshToken: String? = nil
    private(set) var accessTokenExpiry: Date? = nil

    // Note: All interactive authentication is handled via Amplify in AuthView.
    // This manager now focuses on token storage, gating, and post-sign-in bootstrap.

    override init() {
        super.init()
        loadFromKeychain()
        Task { @MainActor in
            self.isAuthenticated = (self.accessToken != nil)
            // If we're authenticated but don't have a profile, bootstrap
            if self.isAuthenticated && MembershipCredentialManager.shared.currentProfile() == nil {
                await postSignInBootstrapWithBackoff()
            }
        }
    }

    @MainActor
    func setAuthenticatedFromAmplify(idToken: String, accessToken: String, refreshToken: String? = nil) {
        // Set tokens in memory
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiry = Date().addingTimeInterval(3600) // Default 1 hour

        // Save to keychain
        if !idToken.isEmpty {
            _ = KeychainManager.shared.save(idToken, forKey: "auth_id_token")
        }
        if !accessToken.isEmpty {
            _ = KeychainManager.shared.save(accessToken, forKey: "auth_access_token")
        }
        if let refreshToken = refreshToken, !refreshToken.isEmpty {
            _ = KeychainManager.shared.save(refreshToken, forKey: "auth_refresh_token")
        }
        if let expiry = accessTokenExpiry {
            let timestamp = String(Int64(expiry.timeIntervalSince1970))
            _ = KeychainManager.shared.save(timestamp, forKey: "auth_expiry")
        }

        // Set authenticated
        self.isAuthenticated = true

        // Kick off bootstrap immediately to fetch profile and bind identity
        Task { @MainActor in
            await self.postSignInBootstrapWithBackoff()
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

    // MARK: - Private

    @MainActor
    private func postSignInBootstrap() async {
        guard let idToken = self.idToken else {
            self.statusMessage = "Authentication token missing"
            return
        }
        do {
            let profile = try await APIClient.me(idToken: idToken)
            MembershipCredentialManager.shared.setProfile(profile)

            // Bind canonical identity for self
            let noiseService = NoiseEncryptionService()
            let selfFingerprint = noiseService.getIdentityFingerprint()
            SecureIdentityStateManager.shared.setCanonicalIdentity(
                fingerprint: selfFingerprint,
                userId: profile.userId,
                handle: profile.username
            )
            let devicePubBase64 = Data(noiseService.getSigningPublicKeyData()).base64EncodedString()
            let coseCredData = try await APIClient.issueCoseCredential(idToken: idToken, devicePubBase64: devicePubBase64)
            try MembershipCredentialManager.shared.setCoseCredential(coseCredData)
            NotificationCenter.default.post(name: .profileUpdated, object: nil)
        } catch {
            self.statusMessage = "Profile setup failed"
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

        if let accessToken = accessToken {
            _ = KeychainManager.shared.save(accessToken, forKey: "auth_access_token")
        }
        if let idToken = idToken {
            _ = KeychainManager.shared.save(idToken, forKey: "auth_id_token")
        }
        if let refreshToken = refreshToken {
            _ = KeychainManager.shared.save(refreshToken, forKey: "auth_refresh_token")
        }
        if let expiry = accessTokenExpiry {
            let timestamp = String(Int64(expiry.timeIntervalSince1970))
            _ = KeychainManager.shared.save(timestamp, forKey: "auth_expiry")
        }
    }

    private func loadFromKeychain() {
        if let at = KeychainManager.shared.retrieve(forKey: "auth_access_token") {
            self.accessToken = at
        }
        if let it = KeychainManager.shared.retrieve(forKey: "auth_id_token") {
            self.idToken = it
        }
        if let rt = KeychainManager.shared.retrieve(forKey: "auth_refresh_token") {
            self.refreshToken = rt
        }
        if let expStr = KeychainManager.shared.retrieve(forKey: "auth_expiry"), let ts = TimeInterval(expStr) {
            self.accessTokenExpiry = Date(timeIntervalSince1970: ts)
        }
        self.isAuthenticated = (self.accessToken != nil)
    }

    // Retry wrapper used when bootstrapping immediately after interactive sign-in
    @MainActor
    private func postSignInBootstrapWithBackoff() async {
        let delays: [UInt64] = [300, 600, 1200, 2400, 4800] // milliseconds
        for (index, delayMs) in delays.enumerated() {
            await postSignInBootstrap()
            if self.statusMessage != "Profile setup failed" { return }
            if index == delays.count - 1 { return }
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }
    }
}
 


