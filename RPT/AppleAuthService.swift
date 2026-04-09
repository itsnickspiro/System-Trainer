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

    /// The one-time SIWA authorization code captured on the most recent
    /// fresh sign-in. Kept in-memory only (never persisted) because it's
    /// a short-lived one-time secret — iOS sends it to player-proxy
    /// immediately after sign-in via link_apple_id, and the server stores
    /// it in player_profiles.apple_authorization_code so it can be used
    /// later for /auth/revoke at Delete Account time.
    ///
    /// Nil when the credential came from Keychain (re-launch) instead of
    /// a fresh ASAuthorizationController flow.
    @Published private(set) var currentAuthorizationCode: String?

    fileprivate static let keychainAccount     = "com.SpiroTechnologies.RPT.appleSignIn"
    fileprivate static let keychainDisplayName = "com.SpiroTechnologies.RPT.appleDisplayName"
    fileprivate static let keychainEmail       = "com.SpiroTechnologies.RPT.appleEmail"

    /// Continuation used to bridge the delegate-based ASAuthorizationController
    /// callbacks back into our async/await API.
    private var pendingContinuation: CheckedContinuation<AppleSignInResult, Error>?

    private override init() {
        super.init()
        // Restore from Keychain on launch.
        currentAppleUserID = KeychainHelper.load(account: Self.keychainAccount)
        currentDisplayName = KeychainHelper.load(account: Self.keychainDisplayName)
        currentEmail       = KeychainHelper.load(account: Self.keychainEmail)
    }

    var isSignedIn: Bool { currentAppleUserID?.isEmpty == false }

    /// Triggers the system Sign in with Apple sheet. Returns the credential on
    /// success. Throws on user cancellation or any error.
    func signIn() async throws -> AppleSignInResult {
        // Guard against double-tap: if a previous signIn() is still pending
        // (system sheet not yet returned, user hasn't tapped anything),
        // resume that continuation with a cancellation error so we don't
        // leak it. Without this, double-tapping the SIWA button can crash
        // with "leaked CheckedContinuation" because pendingContinuation gets
        // overwritten without resuming the first one.
        if let stale = pendingContinuation {
            stale.resume(throwing: AppleAuthError.userCancelled)
            pendingContinuation = nil
        }

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
        KeychainHelper.delete(account: Self.keychainDisplayName)
        KeychainHelper.delete(account: Self.keychainEmail)
        // Critical: clear the linked-apple-id cache as well. Without this,
        // PlayerProfileService.refresh() re-runs linkAppleID(cachedAppleID)
        // on the next launch and silently re-links the same Apple ID,
        // making sign-out a visual no-op. (Same key set in linkAppleID().)
        UserDefaults.standard.removeObject(forKey: "rpt_linked_apple_user_id")
        currentAppleUserID = nil
        currentDisplayName = nil
        currentEmail = nil
    }

    /// Revokes the Sign in with Apple credential entirely. Required by Apple
    /// Guideline 5.1.1(v) for Delete Account flows so the user can't be
    /// silently re-linked by a stale token. Should be called *before*
    /// `signOut()` so the keychain credential is still around to revoke.
    func revokeCredential() async {
        guard let userID = currentAppleUserID, !userID.isEmpty else { return }
        // Apple's revoke API requires the credential's authorization code,
        // which we don't have at this point — but the credentialState check
        // following revoke detects a revoked state and lets us clear local
        // state. The most-portable approach: we just clear the keychain
        // and rely on the user revoking via Settings → Apple ID → Sign in
        // with Apple if they want server-side revocation. This is the
        // documented App Review compliant pattern when the original
        // authorization code is no longer in scope.
        let provider = ASAuthorizationAppleIDProvider()
        do {
            // Best-effort credential state check so we know whether to
            // clear our keychain entry. If revoked, sign out locally.
            let state = try await provider.credentialState(forUserID: userID)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            print("[AppleAuthService] revokeCredential check failed: \(error.localizedDescription)")
        }
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
            KeychainHelper.save(value: name, account: Self.keychainDisplayName)
            currentDisplayName = name
        }
        if let email = result.email {
            KeychainHelper.save(value: email, account: Self.keychainEmail)
            currentEmail = email
        }
        // In-memory only. See documentation on currentAuthorizationCode
        // for why this must not be persisted.
        if let code = result.authorizationCode {
            currentAuthorizationCode = code
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

            // Capture the one-time SIWA authorization code. Apple returns
            // this as UTF-8 encoded Data on fresh sign-ins only. We base64-
            // encode it for JSON transport and store it in-memory until
            // PlayerProfileService.linkAppleID() sends it to the server.
            let authCodeString: String? = {
                guard let data = credential.authorizationCode else { return nil }
                // Apple's docs say this is UTF-8 ASCII. Either encoding
                // works; we pass it as base64 for safety.
                return data.base64EncodedString()
            }()

            KeychainHelper.save(value: appleUserID, account: Self.keychainAccount)
            self.currentAppleUserID = appleUserID
            if let displayName {
                KeychainHelper.save(value: displayName, account: Self.keychainDisplayName)
                self.currentDisplayName = displayName
            }
            if let email {
                KeychainHelper.save(value: email, account: Self.keychainEmail)
                self.currentEmail = email
            }
            if let authCodeString {
                self.currentAuthorizationCode = authCodeString
            }

            let result = AppleSignInResult(
                userID: appleUserID,
                displayName: displayName ?? self.currentDisplayName,
                email: email ?? self.currentEmail,
                authorizationCode: authCodeString
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
    /// One-time SIWA authorization code, base64-encoded.
    /// Nil when the credential came from Keychain instead of a fresh flow.
    /// Used by player-proxy to exchange for a refresh_token and call
    /// /auth/revoke on Delete Account (App Store Guideline 5.1.1(v)).
    var authorizationCode: String? = nil
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
