import Foundation
import AppTrackingTransparency

/// Small wrapper around ATT so the rest of the app doesn't have to import the
/// framework. Calling `requestIfNeeded()` is safe to call multiple times — the
/// system only shows the prompt once per install. Subsequent calls return the
/// cached status without UI.
enum AppTrackingHelper {

    /// Triggers the standard system ATT prompt if it hasn't already been
    /// answered. Returns the resulting status. Safe to ignore the return value.
    @discardableResult
    static func requestIfNeeded() async -> ATTrackingManager.AuthorizationStatus {
        return await ATTrackingManager.requestTrackingAuthorization()
    }

    static var currentStatus: ATTrackingManager.AuthorizationStatus {
        ATTrackingManager.trackingAuthorizationStatus
    }
}
