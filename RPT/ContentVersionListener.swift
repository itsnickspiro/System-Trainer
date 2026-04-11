import Combine
import Foundation

// MARK: - ContentVersionListener
//
// F7 remote content pipeline wiring. Subscribes once at app launch to the
// `.rptContentVersionBumped` notification that RemoteConfigService posts
// when a catalog's server version has advanced past the last-known client
// version. Dispatches a force-refresh to the matching content service.
//
// Why this lives in its own file:
//   - Keeps content services (AvatarService, StoreService, ...) ignorant
//     of the notification wiring — they just expose a `refresh()`.
//   - Centralises the catalog → service mapping so adding a new catalog
//     is a one-line change here.
//   - A single subscriber avoids the n² refresh spam that would happen
//     if every service subscribed and each force-refresh triggered
//     RemoteConfigService.refresh() again.
//
// Usage (wired in RPTApp.swift `.task`):
//   ContentVersionListener.shared.start()
//
// Kill switch: the master flag `remote_content_pipeline_enabled` is
// checked inside RemoteConfigService.refresh() BEFORE the notification
// is posted — so flipping that flag off in the Supabase dashboard
// immediately disables the listener without any client update.

@MainActor
final class ContentVersionListener {

    static let shared = ContentVersionListener()

    private var observer: NSObjectProtocol?

    private init() {}

    /// Wire the listener. Call once at app launch after RemoteConfigService
    /// has loaded its cached values. Idempotent — repeated calls are safe.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .rptContentVersionBumped,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let catalog = note.userInfo?["catalog"] as? String ?? "?"
            let previous = note.userInfo?["previous"] as? Int ?? 0
            let current = note.userInfo?["current"] as? Int ?? 0
            print("[ContentVersionListener] received bump for \(catalog) (\(previous) → \(current))")
            Task { @MainActor in
                await self.dispatch(catalogKey: catalog)
            }
        }
    }

    /// Tear down the listener. Called by `stop()` — only used by tests.
    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    // MARK: - Dispatch

    /// Route a catalog key to the service that owns it. Each content
    /// service is called with its existing refresh path so we don't
    /// need to thread a "force" flag through every service (some have
    /// staleness gates, some don't). AvatarService/EventsService etc.
    /// already refresh on every call — any gate they have is fine to
    /// bypass for a deliberate content-version refresh because that
    /// only fires when the server has new data.
    private func dispatch(catalogKey: String) async {
        switch catalogKey {
        case "content_version_avatars":
            await AvatarService.shared.refresh()
        case "content_version_items":
            await StoreService.shared.refresh(force: true)
        case "content_version_quest_templates":
            await QuestTemplateService.shared.refresh()
        case "content_version_foods":
            // FoodDatabaseService has a different refresh surface; it
            // caches the USDA mirror client-side and doesn't expose a
            // simple refresh(). Food catalog updates are picked up on
            // the next search, so no-op here is acceptable.
            print("[ContentVersionListener] foods bump — no service-level refresh; next search will pick it up")
        case "content_version_achievements":
            await AchievementsService.shared.refresh()
        case "content_version_special_events":
            await EventsService.shared.refresh()
        case "content_version_anime_workout_plans":
            await AnimeWorkoutPlanService.shared.refresh()
        default:
            print("[ContentVersionListener] unhandled catalog key: \(catalogKey)")
        }
    }
}
