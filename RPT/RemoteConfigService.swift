import Combine
import Foundation

// MARK: - RemoteConfigService
//
// Fetches all rows from the `remote_config` Supabase table via the
// remote-config-proxy Edge Function.
//
// Values are cached to UserDefaults so the last-known config is available
// immediately on launch before the network call completes.
//
// Usage:
//   await RemoteConfigService.shared.refresh()   // call on app launch
//   let enabled = RemoteConfigService.shared.bool("feature_coach_enabled")
//   let maxQ    = RemoteConfigService.shared.int("max_daily_quests")

@MainActor
final class RemoteConfigService: ObservableObject {

    static let shared = RemoteConfigService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    // In-memory store — seeded from UserDefaults cache on init
    private var store: [String: String] = [:]

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/remote-config-proxy"
    private static let cacheKey = "rpt_remote_config_cache"

    private init() {
        // Load last-known config from UserDefaults so defaults are available synchronously
        if let saved = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] {
            store = saved
        }
    }

    // MARK: - Typed Accessors

    func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let raw = store[key] else { return defaultValue }
        return raw == "true" || raw == "1"
    }

    func int(_ key: String, default defaultValue: Int = 0) -> Int {
        guard let raw = store[key], let val = Int(raw) else { return defaultValue }
        return val
    }

    func float(_ key: String, default defaultValue: Double = 0) -> Double {
        guard let raw = store[key], let val = Double(raw) else { return defaultValue }
        return val
    }

    func string(_ key: String, default defaultValue: String = "") -> String {
        store[key] ?? defaultValue
    }

    // MARK: - Refresh

    /// Fetches fresh config from Supabase. Safe to call on every app launch.
    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Capture the pre-fetch known versions so we can diff post-fetch.
        let previousVersions = ContentCatalog.allCases.map { catalog in
            (catalog, knownContentVersion(for: catalog))
        }

        do {
            let fetched = try await fetchFromSupabase()
            if !fetched.isEmpty {
                store = fetched
                UserDefaults.standard.set(fetched, forKey: Self.cacheKey)
            }
        } catch {
            lastError = error.localizedDescription
            // Keep using whatever is cached
        }

        // F7 content pipeline: diff server versions vs. last-known client
        // versions. Any catalog whose server version bumped triggers a
        // post-notification; the matching content service listens and
        // force-refreshes. Gated on `remote_content_pipeline_enabled` so
        // we can kill-switch it if it ever misbehaves.
        guard bool("remote_content_pipeline_enabled", default: true) else { return }

        for (catalog, previous) in previousVersions {
            let current = contentVersion(for: catalog)
            guard current > previous else { continue }
            print("[RemoteConfigService] content version bumped for \(catalog.configKey): \(previous) → \(current) — notifying listeners")
            setKnownContentVersion(current, for: catalog)
            NotificationCenter.default.post(
                name: .rptContentVersionBumped,
                object: nil,
                userInfo: [
                    "catalog": catalog.configKey,
                    "previous": previous,
                    "current": current,
                ]
            )
        }
    }

    // MARK: - F7 Content Pipeline

    /// The set of remote-configurable content catalogs. Each one has a
    /// corresponding `content_version_*` key in `remote_config` that
    /// the DB triggers auto-increment on every INSERT/UPDATE/DELETE
    /// to the source table(s).
    enum ContentCatalog: String, CaseIterable {
        case avatars
        case items
        case questTemplates
        case foods
        case achievements
        case specialEvents
        case animeWorkoutPlans

        /// The matching `content_version_*` key in `remote_config`.
        var configKey: String {
            switch self {
            case .avatars:           return "content_version_avatars"
            case .items:             return "content_version_items"
            case .questTemplates:    return "content_version_quest_templates"
            case .foods:             return "content_version_foods"
            case .achievements:      return "content_version_achievements"
            case .specialEvents:     return "content_version_special_events"
            case .animeWorkoutPlans: return "content_version_anime_workout_plans"
            }
        }

        fileprivate var knownVersionKey: String {
            "rpt_known_content_version_\(rawValue)"
        }
    }

    /// The current server-side version for a catalog. Returns 0 if the
    /// remote config hasn't been fetched yet (first launch).
    func contentVersion(for catalog: ContentCatalog) -> Int {
        int(catalog.configKey, default: 0)
    }

    /// The last version this client knew about for a catalog. Persisted
    /// in UserDefaults so the diff survives relaunches.
    func knownContentVersion(for catalog: ContentCatalog) -> Int {
        UserDefaults.standard.integer(forKey: catalog.knownVersionKey)
    }

    private func setKnownContentVersion(_ version: Int, for catalog: ContentCatalog) {
        UserDefaults.standard.set(version, forKey: catalog.knownVersionKey)
    }

    // MARK: - Network

    private func fetchFromSupabase() async throws -> [String: String] {
        guard let url = URL(string: Self.proxyURL) else { return [:] }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 10

        let (data, response) = try await PinnedURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }

        let rows = try JSONDecoder().decode([RemoteConfigRow].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value) })
    }
}

// MARK: - Wire Model

private struct RemoteConfigRow: Decodable {
    let key: String
    let value: String
}
