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

        let (data, response) = try await URLSession.shared.data(for: req)
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
