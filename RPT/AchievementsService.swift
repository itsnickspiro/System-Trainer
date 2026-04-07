import Combine
import Foundation
import SwiftUI

// MARK: - AchievementsService
//
// Fetches achievement definitions from the achievements-proxy Edge Function,
// caches them to disk, and evaluates unlock conditions against current player stats.
//
// Definitions from the server are held in AchievementTemplate structs (distinct
// from the existing Achievement @Model that records unlocked keys in SwiftData).
//
// Evaluation is triggered after:
//   • Quest completion
//   • Level up
//   • Workout logged
//
// Already-unlocked achievements (stored in UserDefaults) are never re-awarded.
//
// Usage:
//   await AchievementsService.shared.refresh()
//   AchievementsService.shared.evaluate()

@MainActor
final class AchievementsService: ObservableObject {

    static let shared = AchievementsService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    /// All achievement definitions fetched from the server.
    private(set) var achievements: [AchievementTemplate] = []

    /// Key of a freshly unlocked achievement — used to drive the banner UI.
    @Published var pendingUnlockTitle: String? = nil

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/achievements-proxy"
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("achievements_cache.json")
    }()
    private static let unlockedDefaultsKey = "rpt_unlocked_achievement_keys"

    private init() {
        achievements = (try? JSONDecoder().decode([AchievementTemplate].self,
                                                  from: Data(contentsOf: Self.cacheURL))) ?? []
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let fetched = try await fetchFromSupabase()
            if !fetched.isEmpty {
                achievements = fetched
                try? JSONEncoder().encode(fetched).write(to: Self.cacheURL, options: .atomic)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Evaluation

    /// Evaluate all achievement conditions against current player state.
    /// Call after quest completion, level-up, and workout logged.
    func evaluate() {
        guard let profile = DataManager.shared.currentProfile else { return }

        let unlocked = unlockedKeys()
        // Aggregate counters incremented by DataManager on each event
        let workoutsLogged  = UserDefaults.standard.integer(forKey: "rpt_total_workouts_logged")
        let questsCompleted = UserDefaults.standard.integer(forKey: "rpt_total_quests_completed")

        for achievement in achievements where !unlocked.contains(achievement.key) {
            if conditionMet(achievement, profile: profile,
                            workoutsLogged: workoutsLogged,
                            questsCompleted: questsCompleted) {
                unlock(achievement, profile: profile)
            }
        }
    }

    // MARK: - Private Helpers

    private func conditionMet(_ a: AchievementTemplate,
                               profile: Profile,
                               workoutsLogged: Int,
                               questsCompleted: Int) -> Bool {
        let value = Double(a.conditionValue)
        switch a.conditionType {
        case "streak_days":
            return Double(profile.currentStreak) >= value
        case "best_streak":
            return Double(profile.bestStreak) >= value
        case "level_reached":
            return Double(profile.level) >= value
        case "workouts_logged":
            return Double(workoutsLogged) >= value
        case "quests_completed":
            return Double(questsCompleted) >= value
        case "xp_earned":
            return Double(profile.xp) >= value
        default:
            return false
        }
    }

    private func unlock(_ achievement: AchievementTemplate, profile: Profile) {
        // Award XP
        if achievement.xpReward > 0 {
            DataManager.shared.addXPToProfile(achievement.xpReward, source: "Achievement: \(achievement.title)")
        }

        // Award GP credits
        if achievement.creditReward > 0 {
            Task {
                await PlayerProfileService.shared.addCredits(
                    amount: achievement.creditReward,
                    type: "achievement_reward",
                    referenceKey: achievement.key
                )
            }
        }

        // Persist unlock key
        var keys = unlockedKeys()
        keys.insert(achievement.key)
        UserDefaults.standard.set(Array(keys), forKey: Self.unlockedDefaultsKey)

        // Re-evaluate avatar unlocks (achievement-gated avatars may now be available)
        Task { await AvatarService.shared.refresh() }

        // Show banner
        pendingUnlockTitle = achievement.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.pendingUnlockTitle = nil
        }
    }

    private func unlockedKeys() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.unlockedDefaultsKey) ?? []
        return Set(arr)
    }

    // MARK: - Network

    private func fetchFromSupabase() async throws -> [AchievementTemplate] {
        guard let url = URL(string: Self.proxyURL) else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

        return (try? JSONDecoder().decode([AchievementTemplate].self, from: data)) ?? []
    }
}

// MARK: - Public Models

struct AchievementTemplate: Codable, Identifiable {
    var id: String { key }

    let key:           String
    let title:         String
    let description:   String
    let iconSymbol:    String
    let conditionType: String   // "streak_days" | "level_reached" | "workouts_logged" | ...
    let conditionValue: Int
    let xpReward:      Int
    let creditReward:  Int      // GP awarded on unlock
    let isEnabled:     Bool

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case description
        case iconSymbol    = "icon_symbol"
        case conditionType  = "condition_type"
        case conditionValue = "condition_value"
        case xpReward      = "xp_reward"
        case creditReward  = "credit_reward"
        case isEnabled     = "is_enabled"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key            = try c.decode(String.self, forKey: .key)
        title          = try c.decode(String.self, forKey: .title)
        description    = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        iconSymbol     = (try? c.decodeIfPresent(String.self, forKey: .iconSymbol)) ?? "trophy.fill"
        conditionType  = (try? c.decodeIfPresent(String.self, forKey: .conditionType)) ?? ""
        conditionValue = (try? c.decodeIfPresent(Int.self, forKey: .conditionValue)) ?? 0
        xpReward       = (try? c.decodeIfPresent(Int.self, forKey: .xpReward)) ?? 0
        creditReward   = (try? c.decodeIfPresent(Int.self, forKey: .creditReward)) ?? 0
        isEnabled      = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(iconSymbol, forKey: .iconSymbol)
        try c.encode(conditionType, forKey: .conditionType)
        try c.encode(conditionValue, forKey: .conditionValue)
        try c.encode(xpReward, forKey: .xpReward)
        try c.encode(creditReward, forKey: .creditReward)
        try c.encode(isEnabled, forKey: .isEnabled)
    }
}

// MARK: - Service Achievement Banner View

/// Slide-in banner driven by AchievementsService.shared.pendingUnlockTitle.
/// Drop into HomeView with `.overlay(alignment: .top)`.
struct ServiceAchievementBanner: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("Achievement Unlocked")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
