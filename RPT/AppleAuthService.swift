import Foundation
import AuthenticationServices
import Combine
import UIKit

/// Manages Sign in with Apple state and credential persistence.
///
/// Apple's opaque user identifier is stable across devices for the same Apple
/// ID. We persist it in the Keychain so the user is auto-recognized on
/// reinstall (Keychain survives app deletion). The actual cross-device
/// profile linkage happens through PlayerProfileService.linkAppleID() —
/// this service only handles the OS-level credential dance.
@MainActor
final class AppleAuthService: NSObject, ObservableObject {

    static let shared = AppleAuthService()

    @Published private(set) var currentAppleUserID: String?
    @Published private(set) var currentDisplayName: String?
    @Published private(set) var currentEmail: String?
    @Published private(set) var lastError: String?

    fileprivate static let keychainAccount = "com.SpiroTechnologies.RPT.appleSignIn"
    fileprivate static let displayNameKey = "rpt_apple_display_name"
    fileprivate static let emailKey       = "rpt_apple_email"

    /// Continuation used to bridge the delegate-based ASAuthorizationController
    /// callbacks back into our async/await API.
    private var pendingContinuation: CheckedContinuation<AppleSignInResult, Error>?

    private override init() {
        super.init()
        // Restore from Keychain on launch.
        currentAppleUserID = KeychainHelper.load(account: Self.keychainAccount)
        currentDisplayName = UserDefaults.standard.string(forKey: Self.displayNameKey)
        currentEmail       = UserDefaults.standard.string(forKey: Self.emailKey)
    }

    var isSignedIn: Bool { currentAppleUserID?.isEmpty == false }

    /// Triggers the system Sign in with Apple sheet. Returns the credential on
    /// success. Throws on user cancellation or any error.
    func signIn() async throws -> AppleSignInResult {
        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Clears local Apple credentials. Does NOT delete the player profile from
    /// the backend — the profile remains linked to the Apple ID and can be
    /// recovered by signing in again on this or any other device.
    func signOut() {
        KeychainHelper.delete(account: Self.keychainAccount)
        UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        currentAppleUserID = nil
        currentDisplayName = nil
        currentEmail = nil
    }

    /// Re-checks the credential state for the persisted Apple user ID. If the
    /// user revoked access in iOS Settings, the credential will report
    /// `.revoked` or `.notFound`, and we should sign them out locally.
    func refreshCredentialStateIfNeeded() async {
        guard let userID = currentAppleUserID, !userID.isEmpty else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userID)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            // Network or transient — don't sign out, just log.
            print("[AppleAuthService] credentialState check failed: \(error.localizedDescription)")
        }
    }

    /// Persist a successful sign-in result coming from the SwiftUI button path
    /// (which doesn't go through ASAuthorizationController.delegate). Idempotent.
    func persistFromButtonResult(_ result: AppleSignInResult) async {
        KeychainHelper.save(value: result.userID, account: Self.keychainAccount)
        currentAppleUserID = result.userID
        if let name = result.displayName {
            UserDefaults.standard.set(name, forKey: Self.displayNameKey)
            currentDisplayName = name
        }
        if let email = result.email {
            UserDefaults.standard.set(email, forKey: Self.emailKey)
            currentEmail = email
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                              didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.pendingContinuation?.resume(throwing: AppleAuthError.unsupportedCredential)
                self.pendingContinuation = nil
                return
            }

            let appleUserID = credential.user
            // .fullName / .email are ONLY returned on the very first sign-in
            // for an Apple ID + app combination. Subsequent sign-ins return nil
            // for both. Persist them the first time we see them.
            let firstName = credential.fullName?.givenName ?? ""
            let familyName = credential.fullName?.familyName ?? ""
            let composedName = [firstName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let displayName: String? = composedName.isEmpty ? nil : composedName
            let email = credential.email

            KeychainHelper.save(value: appleUserID, account: Self.keychainAccount)
            self.currentAppleUserID = appleUserID
            if let displayName {
                UserDefaults.standard.set(displayName, forKey: Self.displayNameKey)
                self.currentDisplayName = displayName
            }
            if let email {
                UserDefaults.standard.set(email, forKey: Self.emailKey)
                self.currentEmail = email
            }

            let result = AppleSignInResult(
                userID: appleUserID,
                displayName: displayName ?? self.currentDisplayName,
                email: email ?? self.currentEmail
            )
            self.pendingContinuation?.resume(returning: result)
            self.pendingContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                              didCompleteWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.pendingContinuation?.resume(throwing: error)
            self.pendingContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find the active foreground window. UIKit lookup; on iOS this is the
        // standard pattern recommended by Apple's sample code.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes.first?.windows.first { $0.isKeyWindow } ?? UIWindow()
        return window
    }
}

// MARK: - Models

struct AppleSignInResult {
    let userID: String
    let displayName: String?
    let email: String?
}

enum AppleAuthError: LocalizedError {
    case unsupportedCredential
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedCredential: return "Unsupported credential type returned from Sign in with Apple."
        case .userCancelled:         return "Sign in cancelled."
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
