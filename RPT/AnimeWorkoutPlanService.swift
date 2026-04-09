import Combine
import Foundation
import SwiftUI

// MARK: - AnimeWorkoutPlanService
//
// Fetches anime workout plans from the Supabase anime-plans-proxy Edge Function.
// Falls back to the bundled AnimeWorkoutPlans data if the network is unavailable.
//
// Plans are cached to disk (JSON) so the last-known remote set is available
// immediately on next launch even before the network fetch completes.
//
// Usage:
//   await AnimeWorkoutPlanService.shared.refresh()   // call on app launch
//   let plans = AnimeWorkoutPlanService.shared.all    // synchronous after refresh

@MainActor
final class AnimeWorkoutPlanService: ObservableObject {

    static let shared = AnimeWorkoutPlanService()

    // Published so views can observe loading state
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    // Internal storage — starts with bundled data, replaced on successful fetch
    private var remotePlans: [AnimeWorkoutPlan]? = nil

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/anime-plans-proxy"
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("anime_workout_plans_cache.json")
    }()

    /// Per-plan cache directory — `Library/Caches/anime_plans/{planID}.json`.
    /// Used so the active plan still loads at the gym with no internet, even
    /// independent of the full-list cache.
    private static let perPlanCacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("anime_plans", isDirectory: true)
    }()

    private init() {
        // Start empty (falls back to bundled plans via `all`);
        // load disk cache off-main to keep init() fast on cold launch.
        remotePlans = nil
        Task.detached(priority: .utility) { [weak self] in
            let url = Self.cacheURL
            guard let data = try? Data(contentsOf: url),
                  let rows = try? JSONDecoder().decode([AnimePlanRow].self, from: data) else { return }
            let plans = rows.compactMap { $0.toAnimeWorkoutPlan() }
            guard !plans.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.remotePlans = plans
            }
        }
    }

    // MARK: - Public API

    /// All plans: remote if available, otherwise bundled fallback.
    var all: [AnimeWorkoutPlan] {
        remotePlans ?? AnimeWorkoutPlans.all
    }

    /// Look up a plan by its stable string key.
    /// Falls back to the per-plan disk cache when offline / before the network
    /// fetch has populated `remotePlans`, so the active plan keeps working at
    /// the gym with no internet.
    func plan(id: String) -> AnimeWorkoutPlan? {
        if let hit = all.first(where: { $0.id == id }) {
            // Refresh the per-plan cache opportunistically so the active plan
            // is always on disk after the user has loaded it once.
            savePerPlanCache(hit)
            return hit
        }
        return loadPerPlanCache(id: id)
    }

    /// Fetch fresh plans from Supabase. Safe to call on every app launch.
    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let fetched = try await fetchFromSupabase()
            if !fetched.isEmpty {
                remotePlans = fetched
                saveDiskCache(fetched)
                // Also write each plan to its own file so the active plan can
                // be recovered even if the list cache is wiped or corrupted.
                for plan in fetched { savePerPlanCache(plan) }
            }
        } catch {
            lastError = error.localizedDescription
            // Keep using whatever we have (cache or bundled)
        }
    }

    // MARK: - Network

    private func fetchFromSupabase() async throws -> [AnimeWorkoutPlan] {
        guard let url = URL(string: Self.proxyURL) else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 15

        let (data, response) = try await PinnedURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        let rows = try JSONDecoder().decode([AnimePlanRow].self, from: data)
        return rows.compactMap { $0.toAnimeWorkoutPlan() }
    }

    // MARK: - Disk Cache

    private func loadDiskCache() -> [AnimeWorkoutPlan]? {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return nil }
        guard let rows = try? JSONDecoder().decode([AnimePlanRow].self, from: data) else { return nil }
        let plans = rows.compactMap { $0.toAnimeWorkoutPlan() }
        return plans.isEmpty ? nil : plans
    }

    private func saveDiskCache(_ plans: [AnimeWorkoutPlan]) {
        // Re-encode as AnimePlanRows for the cache
        guard let rows = try? JSONEncoder().encode(plans.map { AnimePlanRow(from: $0) }),
              let _ = try? rows.write(to: Self.cacheURL, options: .atomic) else { return }
    }

    // MARK: Per-plan cache (for offline active-plan playback)

    private func savePerPlanCache(_ plan: AnimeWorkoutPlan) {
        let dir = Self.perPlanCacheDir
        // Ensure the directory exists; ignore failures (cache is best-effort).
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(plan.id).json")
        guard let data = try? JSONEncoder().encode(AnimePlanRow(from: plan)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadPerPlanCache(id: String) -> AnimeWorkoutPlan? {
        let url = Self.perPlanCacheDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              let row  = try? JSONDecoder().decode(AnimePlanRow.self, from: data) else {
            return nil
        }
        return row.toAnimeWorkoutPlan()
    }
}

// MARK: - Wire Model

/// JSON shape returned by the anime-plans-proxy Edge Function.
private struct AnimePlanRow: Codable {

    let planKey:        String
    let characterName:  String
    let anime:          String
    let tagline:        String
    let description:    String
    let difficulty:     String
    let accentColor:    String
    let iconSymbol:     String
    let targetGender:   String?
    let weeklySchedule: [DayRow]
    let dailyCalories:  Int
    let proteinGrams:   Int
    let carbGrams:      Int
    let fatGrams:       Int
    let waterGlasses:   Int
    let mealPrepTips:   [String]
    let avoidList:      [String]

    // MARK: Nested rows

    struct DayRow: Codable {
        let dayName:      String
        let focus:        String
        let isRest:       Bool
        let exercises:    [ExRow]
        let questTitle:   String
        let questDetails: String
        let xpReward:     Int
    }

    struct ExRow: Codable {
        let name:        String
        let sets:        Int
        let reps:        String
        let restSeconds: Int
        let notes:       String
    }

    // MARK: Init from AnimeWorkoutPlan (for cache encoding)

    init(from plan: AnimeWorkoutPlan) {
        planKey       = plan.id
        characterName = plan.character
        anime         = plan.anime
        tagline       = plan.tagline
        description   = plan.description
        difficulty    = plan.difficulty.rawValue.lowercased()
        accentColor   = plan.accentColor.colorName
        iconSymbol    = plan.iconSymbol
        targetGender  = plan.targetGender?.rawValue.lowercased()
        dailyCalories = plan.nutrition.dailyCalories
        proteinGrams  = plan.nutrition.proteinGrams
        carbGrams     = plan.nutrition.carbGrams
        fatGrams      = plan.nutrition.fatGrams
        waterGlasses  = plan.nutrition.waterGlasses
        mealPrepTips  = plan.nutrition.mealPrepTips
        avoidList     = plan.nutrition.avoidList
        weeklySchedule = plan.weeklySchedule.map { d in
            DayRow(
                dayName:      d.dayName,
                focus:        d.focus,
                isRest:       d.isRest,
                exercises:    d.exercises.map { e in
                    ExRow(name: e.name, sets: e.sets, reps: e.reps,
                          restSeconds: e.restSeconds, notes: e.notes)
                },
                questTitle:   d.questTitle,
                questDetails: d.questDetails,
                xpReward:     d.xpReward
            )
        }
    }

    // MARK: Convert → AnimeWorkoutPlan

    func toAnimeWorkoutPlan() -> AnimeWorkoutPlan? {
        let diff = AnimeWorkoutPlan.PlanDifficulty(rawValue: difficulty.capitalized)
               ?? AnimeWorkoutPlan.PlanDifficulty(rawValue: difficulty)
               ?? .intermediate

        let gender: PlayerGender? = targetGender.flatMap {
            switch $0.lowercased() {
            case "male":   return .male
            case "female": return .female
            default:       return nil
            }
        }

        let days = weeklySchedule.map { d in
            AnimeWorkoutPlan.DayPlan(
                dayName:      d.dayName,
                focus:        d.focus,
                isRest:       d.isRest,
                exercises:    d.exercises.map { e in
                    AnimeWorkoutPlan.PlannedExercise(
                        name: e.name, sets: e.sets, reps: e.reps,
                        restSeconds: e.restSeconds, notes: e.notes)
                },
                questTitle:   d.questTitle,
                questDetails: d.questDetails,
                xpReward:     d.xpReward
            )
        }

        return AnimeWorkoutPlan(
            id:             planKey,
            character:      characterName,
            anime:          anime,
            tagline:        tagline,
            description:    description,
            difficulty:     diff,
            accentColor:    Color(named: accentColor),
            iconSymbol:     iconSymbol,
            weeklySchedule: days,
            nutrition:      AnimeWorkoutPlan.PlanNutrition(
                dailyCalories: dailyCalories,
                proteinGrams:  proteinGrams,
                carbGrams:     carbGrams,
                fatGrams:      fatGrams,
                waterGlasses:  waterGlasses,
                mealPrepTips:  mealPrepTips,
                avoidList:     avoidList
            ),
            targetGender: gender
        )
    }
}

// MARK: - Color helpers

private extension Color {
    /// Return a stable string name for round-trip encoding.
    var colorName: String {
        // SwiftUI Colors don't expose a name, so we map known accent colours
        // used by the plans. The mapping is only needed for cache encoding.
        switch self {
        case .red:     return "red"
        case .orange:  return "orange"
        case .yellow:  return "yellow"
        case .green:   return "green"
        case .blue:    return "blue"
        case .purple:  return "purple"
        case .pink:    return "pink"
        case .gray:    return "gray"
        case .cyan:    return "cyan"
        case .mint:    return "mint"
        case .indigo:  return "indigo"
        default:       return "blue"
        }
    }

    /// Resolve a color name string to a SwiftUI Color.
    init(named name: String) {
        switch name.lowercased() {
        case "red":    self = .red
        case "orange": self = .orange
        case "yellow": self = .yellow
        case "green":  self = .green
        case "blue":   self = .blue
        case "purple": self = .purple
        case "pink":   self = .pink
        case "gray":   self = .gray
        case "cyan":   self = .cyan
        case "mint":   self = .mint
        case "indigo": self = .indigo
        default:       self = .blue
        }
    }
}
