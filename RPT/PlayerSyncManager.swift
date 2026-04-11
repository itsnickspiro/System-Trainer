import Combine
import Foundation
import SwiftUI

// MARK: - PlayerSyncManager
//
// Thin wrapper over PlayerProfileService.upsertProfile() and
// LeaderboardService.upsertEntry(), adding:
//
//   1. Trailing 3-second debounce so rapid successive state changes
//      (quest complete → XP gain → stat change) collapse into one write.
//   2. `markDirty(_:)` API so callers don't need to reason about timing —
//      they just signal intent and the manager decides when to flush.
//   3. Parallel flush of profile + leaderboard writes via `async let`.
//   4. Scene-phase hook (`syncOnBackground`) that fires an immediate flush
//      within the background budget.
//   5. Launch-time stale-sync gate — if the last successful sync is older
//      than 1 hour, force a flush on app launch. Previously the gate was
//      once-per-day, which meant a sync failure during onboarding couldn't
//      retry until the next calendar day.
//
// Why this exists: the F8 investigation found that `player_profiles` had
// stale data for users whose first-launch sync was blocked on CloudKit ID
// resolution. The old once-per-day gate meant the retry window was 24h.
// This manager ships with a 1-hour window and a clear failure signal
// (via `PlayerProfileService.lastError`) so the same class of bug is
// visible, retried fast, and never silently swallowed again.

@MainActor
final class PlayerSyncManager: ObservableObject {

    static let shared = PlayerSyncManager()

    enum DirtyField: Hashable {
        case xp              // XP gain
        case level           // level up (implies stats, xp)
        case streak          // streak change
        case stats           // 6 character stats updated
        case gp              // gold pieces balance changed
        case avatar          // avatar selection changed
        case identity        // display name or demographic info edited
        case quest           // quest complete (implies xp, stats)
        case workout         // workout logged (implies xp, stats)
    }

    private static let debounceKey = "player_sync_debounce_seconds"
    private static let launchStaleKey = "player_sync_launch_stale_hours"
    private static let enabledKey = "player_sync_enabled"
    private static let lastSyncKey = "rpt_last_profile_sync_at"

    private var pendingFields: Set<DirtyField> = []
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Signal that a field is dirty and should be synced on the next
    /// debounce window. Multiple markDirty() calls in quick succession
    /// collapse into a single flush.
    func markDirty(_ field: DirtyField) {
        markDirty([field])
    }

    /// Signal that multiple fields are dirty at once. Useful for level-up
    /// which changes stats + xp + level together.
    func markDirty(_ fields: Set<DirtyField>) {
        guard isEnabled else { return }
        pendingFields.formUnion(fields)
        scheduleDebouncedFlush()
    }

    /// Immediate flush. Used by the app backgrounding hook — there's no
    /// time to debounce when the scene is about to suspend.
    func syncOnBackground() {
        guard isEnabled else { return }
        debounceTask?.cancel()
        let fields = pendingFields
        pendingFields.removeAll()
        Task { await performFlush(fields: fields, reason: "background") }
    }

    /// Launch-time stale sync gate. If the last successful sync is older
    /// than `hours` (default 1), fires an immediate flush. Called from the
    /// RPTApp .task chain after PlayerProfileService.refresh() completes.
    func syncOnLaunchIfStale(hours: Int? = nil) async {
        guard isEnabled else { return }
        let threshold = TimeInterval((hours ?? launchStaleHours) * 3600)
        let lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        let age = Date().timeIntervalSince(lastSync ?? .distantPast)
        guard age > threshold else {
            print("[PlayerSyncManager] launch sync skipped — last sync \(Int(age))s ago, threshold \(Int(threshold))s")
            return
        }
        print("[PlayerSyncManager] launch sync firing — last sync \(Int(age))s ago (>= \(Int(threshold))s threshold)")
        // Flush all fields just to be safe — at launch we don't know
        // which local fields have drifted from the server.
        await performFlush(fields: [.xp, .level, .stats, .streak, .identity], reason: "launch_stale")
    }

    /// Force-flush on demand (e.g. after an explicit user action like
    /// "Sync Now" in a debug menu). Bypasses the debounce.
    func forceFlush() async {
        debounceTask?.cancel()
        let fields = pendingFields
        pendingFields.removeAll()
        await performFlush(fields: fields, reason: "force")
    }

    // MARK: - Internals

    private func scheduleDebouncedFlush() {
        debounceTask?.cancel()
        let seconds = debounceSeconds
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushFromDebounce()
        }
    }

    private func flushFromDebounce() async {
        let fields = pendingFields
        pendingFields.removeAll()
        await performFlush(fields: fields, reason: "debounce")
    }

    /// The real work: fires profile upsert + leaderboard upsert in parallel.
    /// Callers pass `fields` for logging context, not for payload selection
    /// — the upsert is always a full profile snapshot because SwiftData is
    /// source of truth and partial-field diffing adds complexity without
    /// meaningful savings given our 60/min rate limit.
    private func performFlush(fields: Set<DirtyField>, reason: String) async {
        let fieldList = fields.map(\.description).sorted().joined(separator: ",")
        print("[PlayerSyncManager] flush reason=\(reason) fields=[\(fieldList)]")

        async let profileTask: Void = PlayerProfileService.shared.upsertProfile()
        async let leaderboardTask: Void = LeaderboardService.shared.upsertEntry()
        _ = await (profileTask, leaderboardTask)
    }

    // MARK: - Remote config reads (with fallbacks)

    private var isEnabled: Bool {
        RemoteConfigService.shared.bool(Self.enabledKey, default: true)
    }

    private var debounceSeconds: Int {
        max(1, RemoteConfigService.shared.int(Self.debounceKey, default: 3))
    }

    private var launchStaleHours: Int {
        max(1, RemoteConfigService.shared.int(Self.launchStaleKey, default: 1))
    }
}

private extension PlayerSyncManager.DirtyField {
    var description: String {
        switch self {
        case .xp:       return "xp"
        case .level:    return "level"
        case .streak:   return "streak"
        case .stats:    return "stats"
        case .gp:       return "gp"
        case .avatar:   return "avatar"
        case .identity: return "identity"
        case .quest:    return "quest"
        case .workout:  return "workout"
        }
    }
}
