import SwiftUI
import AuthenticationServices

/// Standard Sign in with Apple button that bridges into AppleAuthService.
/// Shows the system-recommended button styling. The owner of this button
/// passes an `onComplete` closure that receives the AppleSignInResult on
/// success or nil on user cancellation.
struct SignInWithAppleButtonView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var auth = AppleAuthService.shared

    let label: SignInWithAppleButton.Label
    let onComplete: (AppleSignInResult?) -> Void

    init(label: SignInWithAppleButton.Label = .signIn,
         onComplete: @escaping (AppleSignInResult?) -> Void) {
        self.label = label
        self.onComplete = onComplete
    }

    var body: some View {
        SignInWithAppleButton(label) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                handleSuccess(auth)
            case .failure(let error):
                if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                    onComplete(nil)
                } else {
                    print("[SignInWithAppleButtonView] failure: \(error.localizedDescription)")
                    onComplete(nil)
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .accessibilityLabel("Sign in with Apple")
    }

    private func handleSuccess(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onComplete(nil)
            return
        }
        // Mirror the AppleAuthService persistence so calling code can read
        // currentAppleUserID immediately afterward.
        Task { @MainActor in
            let firstName = credential.fullName?.givenName ?? ""
            let familyName = credential.fullName?.familyName ?? ""
            let composedName = [firstName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let displayName: String? = composedName.isEmpty ? nil : composedName

            // Capture the one-time SIWA authorization code for server-side
            // revocation. Nil on re-sign-ins where the credential comes
            // from Keychain instead of a fresh flow.
            let authCodeString: String? = credential.authorizationCode?.base64EncodedString()

            let result = AppleSignInResult(
                userID: credential.user,
                displayName: displayName,
                email: credential.email,
                authorizationCode: authCodeString
            )
            await auth.persistFromButtonResult(result)
            onComplete(result)
        }
    }
}
