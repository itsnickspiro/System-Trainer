import Combine
import Foundation

// MARK: - ActivitySyncService
//
// Syncs workout sessions and daily streak activity to Supabase via the
// activity-proxy Edge Function.
//
// Usage:
//   await ActivitySyncService.shared.logWorkout(session: session)
//   await ActivitySyncService.shared.logStreakDay(activityTypes:questCount:workoutCount:steps:)
//   await ActivitySyncService.shared.getWorkoutHistory()   → [WorkoutSummary]
//   await ActivitySyncService.shared.reconstructStreak()   → [StreakDay]

@MainActor
final class ActivitySyncService: ObservableObject {

    static let shared = ActivitySyncService()

    @Published private(set) var lastError: String? = nil
    @Published private(set) var workoutHistory: [WorkoutSummary] = []
    @Published private(set) var streakHistory:  [StreakDay] = []

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/activity-proxy"

    private init() {}

    // MARK: - Log Workout

    /// Logs a completed workout session to Supabase.
    /// - Parameters:
    ///   - type: Workout type label, e.g. "strength", "cardio", "mobility"
    ///   - durationMinutes: Total duration of the session in minutes
    ///   - caloriesBurned: Estimated calories burned (0 if unknown)
    ///   - exercisesCount: Number of distinct exercises performed
    ///   - setsCount: Total number of sets completed
    ///   - volumeKg: Total lifting volume in kg (weight × reps, 0 for cardio)
    func logWorkout(
        type: String,
        durationMinutes: Int,
        caloriesBurned: Int = 0,
        exercisesCount: Int = 0,
        setsCount: Int = 0,
        volumeKg: Double = 0
    ) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        let body: [String: Any] = [
            "action":            "log_workout",
            "cloudkit_user_id":  cloudKitID,
            "workout_type":      type,
            "duration_minutes":  durationMinutes,
            "calories_burned":   caloriesBurned,
            "exercises_count":   exercisesCount,
            "sets_count":        setsCount,
            "volume_kg":         volumeKg,
            "logged_at":         ISO8601DateFormatter().string(from: Date())
        ]

        do {
            try await postToProxy(body: body)
        } catch {
            lastError = error.localizedDescription
            print("[ActivitySyncService] logWorkout failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Log Streak Day

    /// Records today's activity summary for streak history tracking.
    /// Call once per day (e.g. when a quest is completed or day ends).
    /// - Parameters:
    ///   - activityTypes: Types of activity completed today (e.g. ["strength", "quest"])
    ///   - questCount: Number of quests completed today
    ///   - workoutCount: Number of workout sessions completed today
    ///   - steps: Step count from HealthKit (0 if unavailable)
    func logStreakDay(
        activityTypes: [String] = [],
        questCount: Int = 0,
        workoutCount: Int = 0,
        steps: Int = 0
    ) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        let body: [String: Any] = [
            "action":           "log_streak_day",
            "cloudkit_user_id": cloudKitID,
            "activity_types":   activityTypes,
            "quest_count":      questCount,
            "workout_count":    workoutCount,
            "steps":            steps,
            "logged_date":      iso8601DateOnly(Date())
        ]

        do {
            try await postToProxy(body: body)
        } catch {
            lastError = error.localizedDescription
            print("[ActivitySyncService] logStreakDay failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Workout History

    /// Fetches the player's recent workout summaries from Supabase.
    @discardableResult
    func getWorkoutHistory() async -> [WorkoutSummary] {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return [] }

        let body: [String: Any] = [
            "action":           "get_workouts",
            "cloudkit_user_id": cloudKitID
        ]

        do {
            let data = try await postToProxy(body: body)
            let payload = try JSONDecoder().decode(WorkoutHistoryPayload.self, from: data)
            workoutHistory = payload.workouts
            return payload.workouts
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Reconstruct Streak

    /// Fetches the player's streak day history from Supabase for offline reconstruction.
    @discardableResult
    func reconstructStreak() async -> [StreakDay] {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return [] }

        let body: [String: Any] = [
            "action":           "get_streak_history",
            "cloudkit_user_id": cloudKitID
        ]

        do {
            let data = try await postToProxy(body: body)
            let payload = try JSONDecoder().decode(StreakHistoryPayload.self, from: data)
            streakHistory = payload.days
            return payload.days
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Helpers

    private func iso8601DateOnly(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    // MARK: - Network

    @discardableResult
    private func postToProxy(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.proxyURL) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Public Models

struct WorkoutSummary: Codable, Identifiable {
    var id: String { UUID().uuidString } // server doesn't return a stable ID we need for list

    let workoutType:     String
    let durationMinutes: Int
    let caloriesBurned:  Int
    let exercisesCount:  Int
    let setsCount:       Int
    let volumeKg:        Double
    let loggedAt:        String

    enum CodingKeys: String, CodingKey {
        case workoutType     = "workout_type"
        case durationMinutes = "duration_minutes"
        case caloriesBurned  = "calories_burned"
        case exercisesCount  = "exercises_count"
        case setsCount       = "sets_count"
        case volumeKg        = "volume_kg"
        case loggedAt        = "logged_at"
    }
}

struct StreakDay: Codable, Identifiable {
    var id: String { loggedDate }

    let loggedDate:    String
    let questCount:    Int
    let workoutCount:  Int
    let steps:         Int
    let activityTypes: [String]

    enum CodingKeys: String, CodingKey {
        case loggedDate    = "logged_date"
        case questCount    = "quest_count"
        case workoutCount  = "workout_count"
        case steps
        case activityTypes = "activity_types"
    }
}

// MARK: - Wire Payloads (private)

private struct WorkoutHistoryPayload: Decodable {
    let workouts: [WorkoutSummary]
}

private struct StreakHistoryPayload: Decodable {
    let days: [StreakDay]
}
