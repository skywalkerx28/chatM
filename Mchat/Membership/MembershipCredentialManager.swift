import Foundation
extension Notification.Name {
    static let mchatProfileReady = Notification.Name("mchat.profileReady")
    static let mchatCoseReady = Notification.Name("mchat.coseReady")
}

final class MembershipCredentialManager {
    static let shared = MembershipCredentialManager()
    private init() {
        loadProfile()
        loadCoseCredential()
    }

    private var profile: UserProfile?
    private var coseCredentialData: Data?
    private var parsedCoseCredential: CoseCredential?

    func setProfile(_ p: UserProfile?) { 
        profile = p 
        if let p = p {
            saveProfile()
            // Notify interested components that a valid profile is ready
            NotificationCenter.default.post(name: .mchatProfileReady, object: nil, userInfo: ["campusId": p.campus_id])
        } else {
            // Clear saved profile
            UserDefaults.standard.removeObject(forKey: "mchat.userProfile")
        }
    }
    func currentProfile() -> UserProfile? { profile }
    
    private func saveProfile() {
        guard let profile = profile else { return }
        do {
            let data = try JSONEncoder().encode(profile)
            UserDefaults.standard.set(data, forKey: "mchat.userProfile")
            print("Profile saved to UserDefaults")
        } catch {
            print("Failed to save profile: \(error)")
        }
    }
    
    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: "mchat.userProfile") else {
            print("No saved profile found")
            return
        }
        do {
            profile = try JSONDecoder().decode(UserProfile.self, from: data)
            print("Profile loaded from UserDefaults: \(profile?.username ?? "unknown")")
        } catch {
            print("Failed to load profile: \(error)")
        }
    }

    // MARK: - COSE Credential Management
    
    /// Set COSE credential (raw bytes and parsed claims)
    func setCoseCredential(_ credentialData: Data) throws {
        // Verify credential before storing
        let parsed = try CoseCredentialVerifier.shared.verify(credentialData)
        
        self.coseCredentialData = credentialData
        self.parsedCoseCredential = parsed
        
        saveCoseCredential()
        
        print("COSE credential stored for campus: \(parsed.campusId), handle: \(parsed.handle)")

        // Bind canonical identity based on verified COSE credential so the app can
        // operate in decentralized/offline mode without requiring server tokens.
        bindCanonicalIdentity(from: parsed)

        // Notify listeners that COSE is verified and ready
        NotificationCenter.default.post(name: .mchatCoseReady, object: nil, userInfo: ["campusId": parsed.campusId])
    }
    
    /// Get raw COSE credential bytes for transmission
    func currentCoseCredentialData() -> Data? {
        return coseCredentialData
    }
    
    /// Get parsed COSE credential claims
    func currentCoseCredential() -> CoseCredential? {
        return parsedCoseCredential
    }
    
    /// Check if current COSE credential is valid and not expired
    func hasCoseCredential() -> Bool {
        guard let credential = parsedCoseCredential else { return false }
        return credential.isValid
    }
    
    /// Check if COSE credential needs renewal (expires within threshold)
    func coseCredentialNeedsRenewal(within seconds: TimeInterval = 600) -> Bool {
        guard let credential = parsedCoseCredential else { return true }
        return !credential.isValid || credential.expiresWithin(seconds: seconds)
    }
    
    /// Clear COSE credential
    func clearCoseCredential() {
        coseCredentialData = nil
        parsedCoseCredential = nil
        UserDefaults.standard.removeObject(forKey: "mchat.coseCredential")
    }
    
    // MARK: - COSE Credential Persistence
    
    private func saveCoseCredential() {
        guard let credentialData = coseCredentialData else { return }
        UserDefaults.standard.set(credentialData, forKey: "mchat.coseCredential")
        print("COSE credential saved to UserDefaults")
    }
    
    private func loadCoseCredential() {
        guard let data = UserDefaults.standard.data(forKey: "mchat.coseCredential") else {
            print("No saved COSE credential found")
            return
        }
        
        do {
            // Verify credential on load
            let parsed = try CoseCredentialVerifier.shared.verify(data)
            
            // Only keep if still valid
            if parsed.isValid {
                self.coseCredentialData = data
                self.parsedCoseCredential = parsed
                print("Valid COSE credential loaded: \(parsed.handle) @ \(parsed.campusId)")

                // Bind canonical identity from COSE to support offline entry
                bindCanonicalIdentity(from: parsed)

                // Announce COSE readiness for any components that depend on campus context
                NotificationCenter.default.post(name: .mchatCoseReady, object: nil, userInfo: ["campusId": parsed.campusId])
            } else {
                print("Loaded COSE credential is expired, clearing")
                UserDefaults.standard.removeObject(forKey: "mchat.coseCredential")
            }
        } catch {
            print("Failed to verify loaded COSE credential: \(error)")
            UserDefaults.standard.removeObject(forKey: "mchat.coseCredential")
        }
    }

    // MARK: - Identity binding derived from COSE
    private func bindCanonicalIdentity(from credential: CoseCredential) {
        // Compute this device's cryptographic fingerprint and bind it to the
        // campus identity present in the verified COSE credential. This enables a
        // decentralized startup path independent of server tokens.
        let noiseService = NoiseEncryptionService()
        let fingerprint = noiseService.getIdentityFingerprint()
        SecureIdentityStateManager.shared.setCanonicalIdentity(
            fingerprint: fingerprint,
            userId: credential.userId,
            handle: credential.handle
        )
    }
}


