import SwiftUI
import Foundation

extension Color {
    static let primaryred = Color(red: 237/255, green: 27/255, blue: 47/255)
}

struct AuthView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.colorScheme) var colorScheme

    private enum Step { case signIn, signUp, confirm }
    @State private var step: Step = .signIn

    @State private var email: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var otpCode: String = ""
    @State private var isWorking: Bool = false
    @State private var status: String = ""
    @State private var currentUsernameForConfirmation: String = ""

    private var backgroundColor: Color { colorScheme == .dark ? Color.black : Color.white }
    private var textColor: Color { Color.primaryred }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(maxHeight: 45)

            ZStack(alignment: .bottom) {
                Image("chatM")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 360, height: 160)
                Text("Mesh Live Chat")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.8))
            }
            .padding(.bottom, 40)

            HStack(spacing: 12) {
                ModeButton(title: "SIGN IN", active: step == .signIn) { step = .signIn; status = "" }
                ModeButton(title: "SIGN UP", active: step == .signUp) { step = .signUp; status = "" }
            }
            .frame(maxWidth: 320)
            
            if step == .signUp {
                Text("*Only M(G!11 domains will be authorized")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.primaryred)
                    .frame(maxWidth: 320, alignment: .leading)
            }

            VStack(spacing: 16) {
                if step == .signIn {
                    VStack(spacing: 12) {
                        InputField(title: "EMAIL", text: $email, keyboard: .emailAddress)
                        SecureInputField(title: "PASSWORD", text: $password)
                    }
                    .frame(maxWidth: 320)
                    
                    PrimaryButton(title: isWorking ? "AUTHENTICATING" : "AUTHENTICATE", disabled: isWorking || email.isEmpty || password.isEmpty) {
                        Task { await handleSignIn() }
                    }
                    .frame(maxWidth: 280)
                    .padding(.top, 8)
                } else if step == .signUp {
                    VStack(spacing: 12) {
                        InputField(title: "EMAIL", text: $email, keyboard: .emailAddress)
                        InputField(title: "USERNAME", text: $username, keyboard: .default)
                        SecureInputField(title: "PASSWORD", text: $password)
                        SecureInputField(title: "CONFIRM PASSWORD", text: $confirmPassword)
                    }
                    .frame(maxWidth: 320)
                    
                    PrimaryButton(title: isWorking ? "INITIALIZING" : "INITIALIZE", disabled: isWorking || email.isEmpty || username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
                        Task { await handleSignUp() }
                    }
                    .frame(maxWidth: 280)
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 12) {
                        OTPField(code: $otpCode)
                            .frame(maxWidth: 280)
                    }
                    
                    PrimaryButton(title: isWorking ? "VERIFYING" : "VERIFY CODE", disabled: isWorking || otpCode.count != 6) {
                        Task { await handleConfirm() }
                    }
                    .frame(maxWidth: 280)
                    .padding(.top, 8)
                }

                if !status.isEmpty {
                    Text(status.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primaryred.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primaryred.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .frame(maxWidth: 280)
                }
            }

            Spacer()
        }
        .padding()
        .background(backgroundColor)
    }

    // MARK: - Actions
    private func handleSignIn() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isWorking = true; status = ""
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            // Ensure clean state before attempting sign in
            await AuthService.ensureSignedOut()
            try await AuthService.signIn(username: normalizedEmail, password: password)
        } catch {
            await MainActor.run { status = "SIGN IN FAILED" }
            isWorking = false
            return
        }

        do {
            let idt = try await AuthService.idToken()
            // Navigate immediately for better UX; bootstrap in background
            await MainActor.run { auth.isAuthenticated = true }
            Task { try? await bootstrapWithBackoff(idToken: idt) }
        } catch {
            await MainActor.run { status = "TOKEN FETCH FAILED" }
        }
        isWorking = false
    }

    private func handleSignUp() async {
        guard !email.isEmpty, !username.isEmpty, !password.isEmpty, !confirmPassword.isEmpty else { return }
        guard password == confirmPassword else { status = "PASSWORDS DO NOT MATCH"; return }
        isWorking = true; status = ""
        do {
            // Sign up with generated internal username, keep user's handle in preferred_username
            let internalUsername = try await AuthService.signUp(email: email, password: password, username: username)
            await MainActor.run {
                currentUsernameForConfirmation = internalUsername
                step = .confirm 
            }
        } catch {
            await MainActor.run { status = "SIGN UP FAILED" }
        }
        isWorking = false
    }

    private func handleConfirm() async {
        guard otpCode.count == 6 else { return }
        isWorking = true; status = ""
        do {
            // 1) Confirm using handle (Cognito username)
            try await AuthService.confirm(username: currentUsernameForConfirmation, code: otpCode)
        } catch {
            await MainActor.run { status = "VERIFICATION FAILED" }
            isWorking = false
            return
        }

        do {
            // 2) Sign in with email alias
            await AuthService.ensureSignedOut()
            try await AuthService.signIn(username: email, password: password)
        } catch {
            await MainActor.run { status = "SIGN IN FAILED" }
            isWorking = false
            return
        }

        do {
            // 3) Fetch token and navigate immediately; bootstrap in background with backoff
            let idt = try await AuthService.idToken()
            await MainActor.run { auth.isAuthenticated = true }
            Task { try? await bootstrapWithBackoff(idToken: idt) }
        } catch {
            await MainActor.run { status = "TOKEN FETCH FAILED" }
        }
        isWorking = false
    }

    private func bootstrapWithBackoff(idToken: String) async throws {
        let delaysMs: [UInt64] = [300, 600, 1200, 2400, 4800]
        for (index, delayMs) in delaysMs.enumerated() {
            do {
                try await bootstrap(idToken: idToken)
                return
            } catch {
                if index == delaysMs.count - 1 { throw error }
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }

    private func bootstrap(idToken: String) async throws {
        let profile = try await APIClient.me(idToken: idToken)
        MembershipCredentialManager.shared.setProfile(profile)
        if let keyData = try? await fetchDevicePublicKeyBase64() {
            let credData = try await APIClient.issue(idToken: idToken, devicePubBase64: keyData)
            if let credential = try? JSONDecoder().decode(MembershipCredential.self, from: credData) {
                MembershipCredentialManager.shared.setCredential(credential)
            }
        }
    }
}

// MARK: - Subviews
private struct ModeButton: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .white : Color.primaryred)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.primaryred : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primaryred, lineWidth: 1)
                                .opacity(active ? 0 : 0.5)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

private struct InputField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred.opacity(0.5), lineWidth: 1)
                    )
            )
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .accentColor(Color.primaryred)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SecureInputField: View {
    let title: String
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        SecureField(title, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred.opacity(0.5), lineWidth: 1)
                    )
            )
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .accentColor(Color.primaryred)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(disabled ? Color.primaryred.opacity(0.5) : Color.primaryred)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primaryred, lineWidth: disabled ? 0 : 1)
                        .opacity(disabled ? 0 : 0.8)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .scaleEffect(disabled ? 1.0 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: disabled)
    }
}

private struct OTPField: View {
    @Binding var code: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TextField("ENTER 6-DIGIT CODE", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primaryred.opacity(0.5), lineWidth: 1)
                    )
            )
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .accentColor(Color.primaryred)
            .onChange(of: code) { newValue in
                if newValue.count > 6 { code = String(newValue.prefix(6)) }
            }
    }
}

// MARK: - Device key bridge for issuance
private func fetchDevicePublicKeyBase64() async throws -> String {
    let noiseService = NoiseEncryptionService()
    let pub = noiseService.getStaticPublicKeyData()
    return Data(pub).base64EncodedString()
}

#Preview {
    AuthView(auth: AuthManager())
}
