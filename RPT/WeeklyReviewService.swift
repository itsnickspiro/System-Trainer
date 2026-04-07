import Foundation
import SwiftData
import FoundationModels
import Combine

/// Generates and persists a short personalized weekly review of the user's
/// fitness, nutrition, and quest activity using on-device Foundation Models.
/// New review generated every Monday morning.
@MainActor
final class WeeklyReviewService: ObservableObject {
    static let shared = WeeklyReviewService()

    @Published private(set) var currentReview: WeeklyReview?
    @Published private(set) var isGenerating = false

    private static let reviewKey = "rpt_weekly_review_v1"
    private static let weekStartKey = "rpt_weekly_review_week_start_v1"
    private static let dismissedKey = "rpt_weekly_review_dismissed_week_v1"

    private init() {
        loadCachedReview()
    }

    // MARK: - Public API

    /// Check if a review is due and generate it if so. Safe to call on every
    /// app launch / foreground. Won't regenerate within the same week.
    func refreshIfNeeded(context: ModelContext) async {
        guard !isGenerating else { return }
        let now = Date()
        let thisWeekStart = startOfCurrentWeek(now)

        // If we already have a review for this week, no-op
        if let cachedWeekStart = UserDefaults.standard.object(forKey: Self.weekStartKey) as? Date,
           Calendar.current.isDate(cachedWeekStart, inSameDayAs: thisWeekStart),
           currentReview != nil {
            return
        }

        // Collect the last 7 days of stats (from one week before this week's start)
        let weekAgo = thisWeekStart.addingTimeInterval(-7 * 86400)
        let stats = gatherWeeklyStats(context: context, weekAgo: weekAgo)

        // Generate via Foundation Models
        isGenerating = true
        defer { isGenerating = false }
        do {
            let review = try await generateReview(stats: stats)
            currentReview = review
            UserDefaults.standard.set(thisWeekStart, forKey: Self.weekStartKey)
            if let data = try? JSONEncoder().encode(review) {
                UserDefaults.standard.set(data, forKey: Self.reviewKey)
            }
        } catch {
            // Model unavailable or generation failed — leave cached review untouched
            print("[WeeklyReviewService] generation failed: \(error.localizedDescription)")
        }
    }

    /// User tapped the dismiss button. Hides the current review until next Monday.
    func dismiss() {
        let thisWeekStart = startOfCurrentWeek(Date())
        UserDefaults.standard.set(thisWeekStart, forKey: Self.dismissedKey)
        currentReview = nil
    }

    /// Whether the Home tab card should currently render.
    var shouldShowCard: Bool {
        guard currentReview != nil else { return false }
        let thisWeekStart = startOfCurrentWeek(Date())
        if let dismissed = UserDefaults.standard.object(forKey: Self.dismissedKey) as? Date,
           Calendar.current.isDate(dismissed, inSameDayAs: thisWeekStart) {
            return false
        }
        return true
    }

    // MARK: - Private helpers

    private func loadCachedReview() {
        if let data = UserDefaults.standard.data(forKey: Self.reviewKey),
           let cached = try? JSONDecoder().decode(WeeklyReview.self, from: data) {
            currentReview = cached
        }
    }

    /// Returns the Monday 00:00 that begins the week containing `date`.
    private func startOfCurrentWeek(_ date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? Calendar.current.startOfDay(for: date)
    }

    private func gatherWeeklyStats(context: ModelContext, weekAgo: Date) -> WeeklyStats {
        // Workouts logged in the last 7 days
        let workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.startedAt >= weekAgo }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []
        let workoutCount = workouts.count
        let totalVolume = workouts.reduce(0.0) { $0 + $1.totalVolumeKg }
        let totalMinutes = workouts.reduce(0) { $0 + $1.durationMinutes }

        // Food entries logged in the last 7 days
        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.dateConsumed >= weekAgo }
        )
        let foodEntries = (try? context.fetch(foodDescriptor)) ?? []
        // totalCalories / totalProtein are computed properties, so sum in Swift.
        let totalCalories = foodEntries.reduce(0.0) { $0 + $1.totalCalories }
        let totalProtein = foodEntries.reduce(0.0) { $0 + $1.totalProtein }
        let foodEntryCount = foodEntries.count

        // Quests tagged to any date in the last 7 days
        let questDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { $0.dateTag >= weekAgo }
        )
        let quests = (try? context.fetch(questDescriptor)) ?? []
        let completedQuests = quests.filter { $0.isCompleted }.count
        let totalQuests = quests.count

        // Profile snapshot (level + streak)
        let profileDescriptor = FetchDescriptor<Profile>()
        let profile = (try? context.fetch(profileDescriptor))?.first
        let currentLevel = profile?.level ?? 1
        let currentStreak = profile?.currentStreak ?? 0

        return WeeklyStats(
            workoutCount: workoutCount,
            totalVolumeKg: totalVolume,
            totalWorkoutMinutes: totalMinutes,
            totalCalories: Int(totalCalories),
            totalProtein: Int(totalProtein),
            foodEntryCount: foodEntryCount,
            completedQuests: completedQuests,
            totalQuests: totalQuests,
            currentLevel: currentLevel,
            currentStreak: currentStreak
        )
    }

    private func generateReview(stats: WeeklyStats) async throws -> WeeklyReview {
        let prompt = """
        FACTUAL PLAYER DATA (use ONLY these numbers — invent nothing):
        Workouts this week: \(stats.workoutCount) (total \(stats.totalWorkoutMinutes) min, volume \(Int(stats.totalVolumeKg))kg)
        Meals logged: \(stats.foodEntryCount)
        Calories logged: \(stats.totalCalories) kcal
        Protein logged: \(stats.totalProtein)g
        Quests completed: \(stats.completedQuests) of \(stats.totalQuests)
        Current level: \(stats.currentLevel)
        Current streak: \(stats.currentStreak) days

        Task: Generate a weekly System briefing for the Traveler. Produce one short \
        observation about what went well, one about what to improve, a single directive \
        for the coming week, and a one-word mood summary. Use terse, mystical System \
        vocabulary (Traveler, System, quest, stat). Reference only the numbers above.
        """

        // Match the AIManager pattern: plain-String instructions + .respond(to:generating:)
        let session = LanguageModelSession(instructions: """
        IDENTITY: You are THE SYSTEM — an omniscient, hyper-analytical, emotionless entity \
        from an isekai LitRPG. You speak to the Traveler in terse, mystical, clinical prose. \
        Never use motivational language. Never invent numbers. Every sentence must be short.
        """)
        let response = try await session.respond(to: prompt, generating: WeeklyReview.self)
        return response.content
    }
}

// MARK: - Models

/// The structured weekly review returned by the on-device model.
/// Also persisted to UserDefaults via Codable for offline display.
@Generable
struct WeeklyReview: Codable, Sendable {
    @Guide(description: "A single sentence describing the player's strongest achievement this week. Max 15 words.")
    var wentWell: String

    @Guide(description: "A single sentence pointing at the weakest area or most missed opportunity. Max 15 words.")
    var toImprove: String

    @Guide(description: "A single directive for next week in the voice of a video game system. Max 15 words.")
    var nextWeekDirective: String

    @Guide(description: "A one-word mood summary of the week. Examples: Ascending, Stagnant, Unbreakable, Faltering, Relentless.")
    var weekMood: String
}

/// Plain aggregate of the last seven days of player activity.
struct WeeklyStats {
    let workoutCount: Int
    let totalVolumeKg: Double
    let totalWorkoutMinutes: Int
    let totalCalories: Int
    let totalProtein: Int
    let foodEntryCount: Int
    let completedQuests: Int
    let totalQuests: Int
    let currentLevel: Int
    let currentStreak: Int
}
