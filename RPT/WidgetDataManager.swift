import Foundation
import SwiftData

// MARK: - Widget Data Manager
//
// Writes a lightweight snapshot of app state to App Group UserDefaults
// so WidgetKit extensions can read it without direct SwiftData access.
//
// Call `WidgetDataManager.shared.update(profile:quests:nutritionEntries:)` after
// any significant state change (quest completion, nutrition log, profile update).
//
// App Group: group.com.SpiroTechnologies.RPT
// (Must be enabled in the main app target's entitlements AND the widget extension's entitlements)

final class WidgetDataManager {

    static let shared = WidgetDataManager()

    static let appGroupID = "group.com.SpiroTechnologies.RPT"
    static let snapshotKey = "RPTWidgetSnapshot"

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID)
    }

    // MARK: - Write

    /// Refresh widget data from current app state. Call after any mutation.
    func update(profile: Profile?, quests: [Quest], nutritionEntries: [FoodEntry]) {
        let snapshot = buildSnapshot(profile: profile, quests: quests, nutritionEntries: nutritionEntries)
        if let encoded = try? JSONEncoder().encode(snapshot) {
            defaults?.set(encoded, forKey: Self.snapshotKey)
            defaults?.synchronize()
            // Notify so RPTApp can call WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .rptWidgetDataDidChange, object: nil)
        }
    }

    // MARK: - Read (called from widget extension)

    static func loadSnapshot() -> RPTWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey)
        else { return nil }
        return try? JSONDecoder().decode(RPTWidgetSnapshot.self, from: data)
    }

    // MARK: - Private

    private func buildSnapshot(profile: Profile?, quests: [Quest], nutritionEntries: [FoodEntry]) -> RPTWidgetSnapshot {
        let calendar = Calendar.current

        // Profile snapshot
        let profileSnap: RPTWidgetSnapshot.ProfileData?
        if let p = profile {
            profileSnap = RPTWidgetSnapshot.ProfileData(
                name: p.name,
                level: p.level,
                xp: p.xp,
                xpForNextLevel: p.levelXPThreshold(level: p.level),
                health: p.health,
                energy: p.energy,
                discipline: p.discipline,
                currentStreak: p.currentStreak,
                fitnessGoal: p.fitnessGoal.rawValue,
                avatarSystemName: avatarSymbol(for: p.fitnessGoal),
                isInRecovery: p.isInRecovery,
                recoveryDaysRemaining: p.recoveryDaysRemaining
            )
        } else {
            profileSnap = nil
        }

        // Today's quests (top 5 for widget, incomplete first)
        let todayQuests = quests
            .filter { calendar.isDateInToday($0.dateTag) }
            .sorted { !$0.isCompleted && $1.isCompleted }
            .prefix(5)
            .map { q in
                RPTWidgetSnapshot.QuestData(
                    id: q.id.hashValue,
                    title: q.title,
                    xpReward: q.xpReward,
                    isCompleted: q.isCompleted,
                    questType: q.type.rawValue
                )
            }

        // Today's nutrition
        let todayEntries = nutritionEntries.filter { calendar.isDateInToday($0.dateConsumed) }
        let totalCalories = Int(todayEntries.reduce(0) { $0 + $1.totalCalories })
        let totalProtein = todayEntries.reduce(0) { $0 + $1.totalProtein }
        let totalCarbs = todayEntries.reduce(0) { $0 + $1.totalCarbs }
        let totalFat = todayEntries.reduce(0) { $0 + $1.totalFat }

        let calorieGoal = profile?.effectiveCalorieGoal ?? 2000
        let proteinGoal = Double(profile?.effectiveProteinGoal ?? 150)
        let carbGoal = Double(profile?.effectiveCarbGoal ?? 200)

        let nutrition = RPTWidgetSnapshot.NutritionData(
            caloriesConsumed: totalCalories,
            calorieGoal: calorieGoal,
            proteinConsumed: totalProtein,
            proteinGoal: proteinGoal,
            carbsConsumed: totalCarbs,
            carbGoal: carbGoal,
            fatConsumed: totalFat
        )

        return RPTWidgetSnapshot(
            updatedAt: Date(),
            profile: profileSnap,
            todayQuests: Array(todayQuests),
            nutrition: nutrition
        )
    }

    private func avatarSymbol(for goal: FitnessGoal) -> String {
        switch goal {
        case .buildMuscle:   return "figure.strengthtraining.traditional"
        case .loseFat:       return "figure.run"
        case .endurance:     return "figure.outdoor.cycle"
        case .generalHealth: return "figure.mind.and.body"
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let rptWidgetDataDidChange = Notification.Name("RPTWidgetDataDidChange")
}

// MARK: - Shared Data Models (Codable, no SwiftData dependency)
//
// These plain Codable structs are safe to share across the app/extension boundary.
// The widget extension imports only this file (or a shared framework target in future).

struct RPTWidgetSnapshot: Codable {
    let updatedAt: Date
    let profile: ProfileData?
    let todayQuests: [QuestData]
    let nutrition: NutritionData

    struct ProfileData: Codable {
        let name: String
        let level: Int
        let xp: Int
        let xpForNextLevel: Int
        let health: Double      // 0–100
        let energy: Double      // 0–100
        let discipline: Double  // 0–100
        let currentStreak: Int
        let fitnessGoal: String
        let avatarSystemName: String
        let isInRecovery: Bool
        let recoveryDaysRemaining: Int

        var xpProgress: Double {
            guard xpForNextLevel > 0 else { return 0 }
            return min(1.0, Double(xp) / Double(xpForNextLevel))
        }
    }

    struct QuestData: Codable, Identifiable {
        let id: Int
        let title: String
        let xpReward: Int
        let isCompleted: Bool
        let questType: String
    }

    struct NutritionData: Codable {
        let caloriesConsumed: Int
        let calorieGoal: Int
        let proteinConsumed: Double
        let proteinGoal: Double
        let carbsConsumed: Double
        let carbGoal: Double
        let fatConsumed: Double

        var calorieProgress: Double { calorieGoal > 0 ? min(1.0, Double(caloriesConsumed) / Double(calorieGoal)) : 0 }
        var proteinProgress: Double { proteinGoal > 0 ? min(1.0, proteinConsumed / proteinGoal) : 0 }
        var carbProgress: Double { carbGoal > 0 ? min(1.0, carbsConsumed / carbGoal) : 0 }
    }
}
