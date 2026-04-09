import Foundation
import SwiftData
import Combine
import Network
import HealthKit
import UIKit

/// Centralized data manager that coordinates between local SwiftData and APIs
@MainActor
final class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // MARK: - Core Managers
    @Published private(set) var healthManager = HealthManager()
    @Published private(set) var recipeAPI = RecipeAPI.shared
    
    // MARK: - Local Data Context
    private var modelContext: ModelContext?
    
    // MARK: - Cached Data
    @Published private(set) var currentProfile: Profile?
    @Published private(set) var todaysQuests: [Quest] = []
    @Published private(set) var cachedRecipes: [Recipe] = []
    @Published private(set) var lastSyncDate: Date?
    
    // MARK: - State
    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var syncError: Error?
    /// Set when a SwiftData context save fails so the UI can surface the problem.
    @Published var lastSaveError: String? = nil
    
    // MARK: - HealthKit background delivery
    /// Active observer queries, keyed by sample type identifier.
    /// Keeping strong references prevents queries from being deallocated.
    private var observerQueries: [String: HKObserverQuery] = [:]
    /// Last time handleHealthDataUpdate() actually performed work. Used to debounce
    /// the 5+ observer callbacks HealthKit fires in rapid succession after a sync.
    private var lastHealthFetchAt: Date = .distantPast
    /// Reuse HealthManager's HKHealthStore to avoid duplicate instances.
    private var hkStore: HKHealthStore { healthManager.healthStore }

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
        startPeriodicSync()
    }
    
    // MARK: - Destructive
    /// Wipes every SwiftData model instance the app knows about. Used by the
    /// "Delete Account" flow in Settings. Cloud (Supabase) deletion is handled
    /// separately by the player-proxy `delete_account` action; CloudKit data
    /// will replicate the local deletes through the private database sync.
    @MainActor
    func deleteEverything() {
        guard let context = modelContext else { return }
        let typesToDelete: [any PersistentModel.Type] = [
            Profile.self,
            Quest.self,
            FoodItem.self,
            FoodEntry.self,
            CustomMeal.self,
            CustomMealItem.self,
            ExerciseItem.self,
            WorkoutSession.self,
            ExerciseSet.self,
            ActiveRoutine.self,
            PersonalRecord.self,
            PatrolRoute.self,
            InventoryItem.self,
            CustomWorkoutPlan.self,
            Achievement.self,
            BodyMeasurement.self,
            PlannedMeal.self,
            WeeklyBoss.self,
            GroceryListItem.self
        ]
        for type in typesToDelete {
            do {
                try context.delete(model: type)
            } catch {
                print("[DataManager] Failed to delete all \(type): \(error.localizedDescription)")
            }
        }
        do {
            try context.save()
        } catch {
            print("[DataManager] Failed to save after deleteEverything: \(error.localizedDescription)")
        }
        currentProfile = nil
        todaysQuests = []
    }

    // MARK: - Setup
    func configure(with context: ModelContext) {
        self.modelContext = context
        loadLocalData()
    }
    
    private func setupObservers() {
        // Monitor network connectivity
        NetworkMonitor.shared.$isConnected
            .assign(to: &$isOnline)

        // When HealthKit authorization is granted, register background observers.
        healthManager.$isAuthorized
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                self?.startHealthKitBackgroundDelivery()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Profile Helpers

    /// Ensures a local Profile row exists in SwiftData. Used by
    /// PlayerProfileService to hydrate a cross-device cloud profile onto a
    /// fresh install where currentProfile is still nil.
    @MainActor
    func ensureProfileExists() {
        guard currentProfile == nil, let context = modelContext else { return }
        let descriptor = FetchDescriptor<Profile>()
        if let existing = (try? context.fetch(descriptor))?.first {
            currentProfile = existing
            return
        }
        let savedName = UserDefaults.standard.string(forKey: "userProfileName") ?? "Player"
        let newProfile = Profile(name: savedName)
        context.insert(newProfile)
        try? context.save()
        currentProfile = newProfile
    }

    /// Saves the SwiftData context if available. Throws if the save fails.
    @MainActor
    func saveContext() throws {
        try modelContext?.save()
    }

    // MARK: - Data Loading
    private func loadLocalData() {
        guard let context = modelContext else { return }
        
        // Load current profile
        let profileDescriptor = FetchDescriptor<Profile>()
        do {
            let profiles = try context.fetch(profileDescriptor)
            if let profile = profiles.first {
                currentProfile = profile
            } else {
                // Create default profile with saved name from onboarding
                let savedName = UserDefaults.standard.string(forKey: "userProfileName") ?? "Player"
                let newProfile = Profile(name: savedName)
                context.insert(newProfile)
                try context.save()
                currentProfile = newProfile
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
        
        // One-time cleanup: remove duplicate quests created by date manipulation
        deduplicateQuests()

        // Load today's quests
        refreshTodaysQuests()

        // Generate default daily quests if they don't exist
        generateDefaultDailyQuests()

        // Check for hardcore reset penalty (missed quests) at launch
        currentProfile?.applyHardcoreResetIfNeeded()

        // Award daily login GP bonus (once per day)
        Task { await checkDailyLoginBonus() }

        // Wire the boss raid service to this same SwiftData context so it can
        // spawn / load this week's WeeklyBoss row.
        if let context = modelContext {
            BossRaidService.shared.setContext(context)
        }

        // Sync the player's guild membership + active guild raid from the
        // backend on launch. The cached Profile.guildID / guildName fields
        // get repopulated automatically.
        Task { await GuildService.shared.refresh() }
    }

    /// Remove duplicate quests: for each calendar day, keep only one quest per title.
    /// Prefers keeping completed quests over incomplete ones.
    private func deduplicateQuests() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Quest>(
            sortBy: [SortDescriptor(\.dateTag, order: .forward)]
        )
        guard let allQuests = try? context.fetch(descriptor) else { return }

        // Group by (startOfDay, title)
        var seen: [String: Quest] = [:]
        var toDelete: [Quest] = []

        for quest in allQuests {
            let dayKey = Calendar.current.startOfDay(for: quest.dateTag)
            let key = "\(dayKey.timeIntervalSince1970)|\(quest.title)"

            if let existing = seen[key] {
                // Keep the completed one; if both same status, keep the earlier one
                if quest.isCompleted && !existing.isCompleted {
                    toDelete.append(existing)
                    seen[key] = quest
                } else {
                    toDelete.append(quest)
                }
            } else {
                seen[key] = quest
            }
        }

        guard !toDelete.isEmpty else { return }
        print("[DataManager] Removing \(toDelete.count) duplicate quest(s)")
        for quest in toDelete {
            context.delete(quest)
        }
        saveLocalChanges()
    }


    private func refreshTodaysQuests() {
        guard let context = modelContext else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let questDescriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { quest in
                quest.dateTag >= today && quest.dateTag < tomorrow
            },
            sortBy: [SortDescriptor(\Quest.createdAt, order: .reverse)]
        )
        
        do {
            todaysQuests = try context.fetch(questDescriptor)
            refreshWidgetData(context: context)
        } catch {
            print("Failed to load today's quests: \(error)")
        }
    }

    /// Push a fresh snapshot to App Group UserDefaults so widgets can update.
    private func refreshWidgetData(context: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let entryDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.dateConsumed >= todayStart
            }
        )
        let todayEntries = (try? context.fetch(entryDescriptor)) ?? []
        WidgetDataManager.shared.update(
            profile: currentProfile,
            quests: todaysQuests,
            nutritionEntries: todayEntries
        )
    }

    // MARK: - Profile Management
    func updateProfile(_ updates: (Profile) -> Void) {
        guard let profile = currentProfile else { return }
        
        updates(profile)
        saveLocalChanges()
    }
    
    func addXPToProfile(_ xp: Int, source: String = "General", statTarget: String? = nil) {
        guard let profile = currentProfile else { return }

        // Apply active XP multipliers from equipped items and events
        let storeMultiplier = StoreService.shared.activeXPMultiplier
        let eventMultiplier = EventsService.shared.activeXPMultiplier

        // Class / archetype bonus: +10% XP on quests whose statTarget matches
        // the player's chosen class. Warriors get a bonus on strength quests,
        // Rangers on endurance, Monks on discipline, Sages on focus.
        // Only applies to positive XP gains (penalties use no bonus).
        let classBonus: Double
        if xp > 0,
           let target = statTarget,
           !target.isEmpty,
           profile.playerClass != .unselected,
           profile.playerClass.bonusStatTarget == target.lowercased() {
            classBonus = 1.10
        } else {
            classBonus = 1.0
        }

        let scaledXP = xp > 0
            ? Int(Double(xp) * storeMultiplier * eventMultiplier * classBonus)
            : xp

        let oldLevel = profile.level
        profile.addXP(scaledXP)

        // Log XP gain
        if scaledXP != 0 {
            ActivityLogManager.shared.log(.xp, "\(scaledXP > 0 ? "+" : "")\(scaledXP) XP from \(source)", detail: scaledXP != xp ? "Base \(xp) × multipliers → \(scaledXP)" : nil)
        }

        // Check for level up
        if profile.level > oldLevel {
            handleLevelUp(from: oldLevel, to: profile.level)
        }

        // Damage the active weekly raid boss (only fires for the Forsaken
        // Dragon archetype — XP-driven boss). Other archetypes ignore this.
        if scaledXP > 0 {
            BossRaidService.shared.applyDamage(source: .xpEarned, amount: scaledXP)
        }

        saveLocalChanges()
    }

    private func handleLevelUp(from oldLevel: Int, to newLevel: Int) {
        print("Level up! \(oldLevel) -> \(newLevel)")
        ActivityLogManager.shared.log(.levelUp, "Level \(oldLevel) → \(newLevel)")
        NotificationInboxManager.shared.add(title: "Level Up!", body: "You reached level \(newLevel)!", category: "levelUp")

        // Isekai-style milestone notifications at key levels. The manager
        // queues them if multiple fire at once, so crossing levels 5 → 10 in
        // one batch shows both in sequence.
        if oldLevel < 5 && newLevel >= 5 {
            SystemNotificationManager.shared.present(SystemNotificationManager.level5)
        }
        if oldLevel < 10 && newLevel >= 10 {
            SystemNotificationManager.shared.present(SystemNotificationManager.level10)
        }
        if oldLevel < 25 && newLevel >= 25 {
            SystemNotificationManager.shared.present(SystemNotificationManager.level25)
        }

        // Local push notification for the new level. Honors the
        // levelUpNotifications user preference (default true).
        if UserDefaults.standard.bool(forKey: "levelUpNotifications") {
            NotificationManager.shared.scheduleLevelUpNotification(newLevel: newLevel)
        }

        // Sync progress to cloud, award level-up GP, evaluate achievements, and update leaderboard
        Task {
            await PlayerProfileService.shared.syncProfile()
            await PlayerProfileService.shared.syncIfStreakMilestone(
                currentProfile?.currentStreak ?? 0
            )
            AchievementsService.shared.evaluate()

            // Award GP for EVERY level gained, not just one. Previously a
            // multi-level skip (e.g. completing a long quest that pushes
            // level 5 → 8) only awarded a single level-up bonus, robbing
            // the player of two levels' worth of GP. Award once per level
            // with a unique reference_key so the credit history shows each
            // level individually and idempotency is preserved per-level.
            let rc = RemoteConfigService.shared
            let levelUpBonus = rc.int("credits_per_level_up", default: 50)
            if levelUpBonus > 0 {
                for level in (oldLevel + 1)...newLevel {
                    await PlayerProfileService.shared.addCredits(
                        amount: levelUpBonus,
                        type: "level_up_bonus",
                        referenceKey: "level_\(level)"
                    )
                }
            }

            // Update leaderboard with new level/XP
            await LeaderboardService.shared.upsertEntry()
        }
    }
    // MARK: - GP Bonus Helpers

    /// Awards daily login GP bonus once per calendar day.
    private func checkDailyLoginBonus() async {
        let key = "rpt_last_daily_login_credit_date"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) { return }

        let rc = RemoteConfigService.shared
        let bonus = rc.int("credits_daily_login_bonus", default: 5)
        if bonus > 0 {
            await PlayerProfileService.shared.addCredits(amount: bonus, type: "daily_login")
        }
        UserDefaults.standard.set(today, forKey: key)
    }

    /// Awards GP for streak milestones (7-day and 30-day). Called after streak changes.
    private func checkStreakMilestoneBonus(streak: Int) {
        let rc = RemoteConfigService.shared
        let milestones: [(threshold: Int, key: String, configKey: String)] = [
            (7,  "rpt_streak_credit_7",  "credits_streak_bonus_7day"),
            (30, "rpt_streak_credit_30", "credits_streak_bonus_30day"),
        ]
        for m in milestones {
            guard streak == m.threshold else { continue }
            let awarded = UserDefaults.standard.bool(forKey: "\(m.key)_\(streak)")
            guard !awarded else { continue }
            let bonus = rc.int(m.configKey, default: m.threshold == 7 ? 25 : 100)
            if bonus > 0 {
                ActivityLogManager.shared.log(.streak, "\(m.threshold)-day streak milestone!", detail: "+\(bonus) GP bonus")
                NotificationInboxManager.shared.add(title: "Streak Milestone!", body: "You hit a \(m.threshold)-day streak and earned \(bonus) GP!", category: "streak")
                Task {
                    await PlayerProfileService.shared.addCredits(
                        amount: bonus,
                        type: "streak_bonus",
                        referenceKey: "\(m.threshold)_day_streak"
                    )
                }
                UserDefaults.standard.set(true, forKey: "\(m.key)_\(streak)")
            }

            // Isekai-style system notification at streak milestones
            if m.threshold == 7 {
                SystemNotificationManager.shared.present(SystemNotificationManager.firstSevenDayStreak)
            } else if m.threshold == 30 {
                SystemNotificationManager.shared.present(SystemNotificationManager.firstThirtyDayStreak)
            }
        }
    }

    // MARK: - Quest Management
    func addQuest(_ quest: Quest) {
        guard let context = modelContext else { return }

        // Prevent duplicate quests: skip if a quest with the same title
        // already exists for the same day (guards against clock manipulation)
        let questDate = quest.dateTag
        let questTitle = quest.title
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: questDate)) ?? questDate.addingTimeInterval(86400)
        let startOfDay = Calendar.current.startOfDay(for: questDate)
        let descriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { q in
                q.title == questTitle && q.dateTag >= startOfDay && q.dateTag < nextDay
            }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return // duplicate — skip
        }

        context.insert(quest)
        saveLocalChanges()
        refreshTodaysQuests()
    }
    
    func completeQuest(_ quest: Quest) {
        // Idempotency: prevent double-completion from concurrent code paths
        guard !quest.isCompleted else { return }
        // Date guard: only allow completing quests dated today
        guard Calendar.current.isDateInToday(quest.dateTag) else { return }

        quest.isCompleted = true
        quest.completedAt = Date()

        ActivityLogManager.shared.log(.quest, "Completed: \(quest.title)", detail: "+\(quest.xpReward) XP reward")

        // Award XP (through multipliers) and register completion
        if let profile = currentProfile {
            let prevPassCount = profile.exemptionPassCount
            addXPToProfile(quest.xpReward, source: "Quest", statTarget: quest.statTarget)
            profile.registerCompletion()

            // If registerCompletion awarded a streak pass, mirror it to InventoryItem
            if profile.exemptionPassCount > prevPassCount {
                syncExemptionPassToInventory(profile: profile)
            }

            // Check streak milestone GP bonuses
            checkStreakMilestoneBonus(streak: profile.currentStreak)
        }

        // Haptic feedback for quest completion
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Increment the aggregate quests-completed counter for achievement evaluation
        let prevQuestCount = UserDefaults.standard.integer(forKey: "rpt_total_quests_completed")
        let questCount = prevQuestCount + 1
        UserDefaults.standard.set(questCount, forKey: "rpt_total_quests_completed")

        // First quest ever — fire an isekai-style system notification
        if prevQuestCount == 0 {
            SystemNotificationManager.shared.present(SystemNotificationManager.firstQuestComplete)
        }

        // Damage the weekly raid boss (only the Iron Sleeper consumes this).
        BossRaidService.shared.applyDamage(source: .questComplete, amount: 1)

        saveLocalChanges()
        refreshTodaysQuests()

        // Evaluate achievements and report progress to events
        AchievementsService.shared.evaluate()
        Task { await EventsService.shared.updateAllEventProgress() }

        // Check if completing this quest satisfies discipline check conditions
        autoCompleteDisciplineQuests()

        // Award GP for quest completion and sync to activity/leaderboard backends
        Task {
            let rc = RemoteConfigService.shared
            let baseCreditsPerQuest = rc.int("credits_quest_completion", default: 10)
            let baseMultiplier = rc.float("credits_multiplier_base", default: 1.0)
            let eventMultiplier = EventsService.shared.activeCreditMultiplier
            let scaledAmount = Int(Double(baseCreditsPerQuest) * Double(baseMultiplier) * eventMultiplier)
            // Add quest-specific bonus GP (from creditReward field)
            let totalGP = scaledAmount + quest.creditReward
            if totalGP > 0 {
                await PlayerProfileService.shared.addCredits(
                    amount: totalGP,
                    type: quest.creditReward > 0 ? "quest_bonus_gp" : "quest_reward",
                    referenceKey: quest.title
                )
            }

            // Log streak day activity to Supabase
            let totalQuests = UserDefaults.standard.integer(forKey: "rpt_quests_today") + 1
            UserDefaults.standard.set(totalQuests, forKey: "rpt_quests_today")
            await ActivitySyncService.shared.logStreakDay(
                activityTypes: ["quest"],
                questCount: totalQuests,
                workoutCount: UserDefaults.standard.integer(forKey: "rpt_workouts_today"),
                steps: currentProfile?.dailySteps ?? 0
            )

            // Update leaderboard with latest XP
            await LeaderboardService.shared.upsertEntry()
        }
    }

    /// Ensures the InventoryItem for hermitMiracleSeed matches profile.exemptionPassCount.
    private func syncExemptionPassToInventory(profile: Profile) {
        guard let context = modelContext else { return }
        // Scope the fetch to the one item type we care about via a predicate
        // so we don't pull the entire inventory table on every quest completion.
        let targetType = InventoryItemType.hermitMiracleSeed
        var descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.itemType == targetType }
        )
        descriptor.fetchLimit = 1
        let allItems = (try? context.fetch(descriptor)) ?? []
        if let existing = allItems.first {
            existing.quantity = profile.exemptionPassCount
        } else {
            let newItem = InventoryItem(itemType: .hermitMiracleSeed, quantity: profile.exemptionPassCount)
            context.insert(newItem)
        }
    }

    func uncompleteQuest(_ quest: Quest) {
        // Only allow un-completing quests from today — past days are locked.
        guard Calendar.current.isDateInToday(quest.dateTag ?? Date()) else { return }

        quest.isCompleted = false
        quest.completedAt = nil

        // Refund XP — the player didn't actually earn it
        if let profile = currentProfile {
            profile.subtractXP(quest.xpReward)
        }

        saveLocalChanges()
        refreshTodaysQuests()
    }
    
    func deleteQuest(_ quest: Quest) {
        guard let context = modelContext else { return }

        do {
            context.delete(quest)
            try context.save()
            refreshTodaysQuests()
        } catch {
            print("Failed to delete quest: \(error)")
        }
    }

    /// Delete a user-created quest, reversing XP/GP awards if it was already completed.
    func deleteUserCreatedQuest(_ quest: Quest) {
        guard quest.isUserCreated else { return }
        if quest.isCompleted {
            // Reverse XP
            if let profile = currentProfile {
                profile.subtractXP(quest.xpReward)
            }
            // Reverse GP (credits) via PlayerProfileService (negative amount = debit)
            if quest.creditReward > 0 {
                Task { @MainActor in
                    await PlayerProfileService.shared.addCredits(
                        amount: -quest.creditReward,
                        type: "quest_deletion_reversal",
                        referenceKey: quest.id.uuidString
                    )
                }
            }
        }
        deleteQuest(quest)
    }

    // MARK: - Workout Quest Auto-Complete

    /// Called immediately after a user logs a workout. Finds today's incomplete quests
    /// that match the workout type and marks them complete, awarding XP.
    ///
    /// Matching logic (system quests keyed on statTarget):
    ///   - strength    → statTarget "strength"
    ///   - cardio      → statTarget "endurance"
    ///   - flexibility → statTarget "energy"
    ///   - mixed       → statTarget "strength" OR "endurance"
    ///   - Any type    → plan training quest (title starts with "[")
    ///
    /// Custom quests are matched via completionCondition "workout:<type>" or "workout:any".
    @discardableResult
    func autoCompleteWorkoutQuests(for workoutType: WorkoutType) -> Int {
        let matchingTargets: Set<String>
        switch workoutType {
        case .strength:    matchingTargets = ["strength"]
        case .cardio:      matchingTargets = ["endurance"]
        case .flexibility: matchingTargets = ["energy"]
        case .mixed:       matchingTargets = ["strength", "endurance"]
        }

        var completed = 0
        for quest in todaysQuests where !quest.isCompleted {
            // Custom quests: check completionCondition
            if let condition = quest.completionCondition, condition.hasPrefix("workout:") {
                let required = String(condition.dropFirst("workout:".count))
                if required == "any" || required == workoutType.rawValue {
                    completeQuest(quest)
                    completed += 1
                }
                continue
            }

            // System quests: match by statTarget
            let targetMatches = quest.statTarget.map { matchingTargets.contains($0) } ?? false
            // Plan training quests (no completionCondition, title starts with "[")
            let isPlanTrainingQuest = quest.completionCondition == nil
                && quest.title.hasPrefix("[")
                && !quest.title.contains("Rest")
            if targetMatches || isPlanTrainingQuest {
                completeQuest(quest)
                completed += 1
            }
        }

        if completed > 0 {
            NotificationInboxManager.shared.add(
                title: "Quest\(completed > 1 ? "s" : "") Auto-Completed!",
                body: "\(completed) workout quest\(completed > 1 ? "s" : "") completed automatically.",
                category: "quest"
            )
            // Increment workout counters for achievement + weekly goal evaluation
            let workoutCount = UserDefaults.standard.integer(forKey: "rpt_total_workouts_logged") + 1
            UserDefaults.standard.set(workoutCount, forKey: "rpt_total_workouts_logged")
            let weeklyCount = UserDefaults.standard.integer(forKey: "rpt_weekly_workouts") + 1
            UserDefaults.standard.set(weeklyCount, forKey: "rpt_weekly_workouts")
            // Check weekly quest completion
            autoCompleteWeeklyQuests()
            // Evaluate achievements and report to events after workout
            AchievementsService.shared.evaluate()
            Task { await EventsService.shared.updateAllEventProgress() }
        }

        return completed
    }

    // MARK: - Health Quest Auto-Complete

    /// Checks all of today's incomplete quests that have a HealthKit-backed
    /// completionCondition and auto-completes them when the threshold is met.
    /// Called from handleHealthDataUpdate() every time new health data arrives.
    @discardableResult
    func autoCompleteHealthQuests() -> Int {
        guard let profile = currentProfile else { return 0 }
        var completed = 0

        for quest in todaysQuests where !quest.isCompleted {
            guard let condition = quest.completionCondition else { continue }
            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let target = Double(parts[1]) else { continue }
            let kind = String(parts[0])

            let met: Bool
            switch kind {
            case "steps":
                met = Double(profile.dailySteps) >= target
            case "calories":
                met = Double(profile.dailyActiveCalories) >= target
            case "sleep":
                met = profile.sleepHours >= target
            case "water":
                met = Double(profile.waterIntake) >= target
            case "meditation":
                met = Double(profile.mindfulnessMinutesToday) >= target
            default:
                continue  // "workout", "meals", "discipline_check", "manual" handled elsewhere
            }

            if met {
                completeQuest(quest)
                completed += 1
            }
        }
        if completed > 0 {
            NotificationInboxManager.shared.add(
                title: "Health Quest\(completed > 1 ? "s" : "") Complete!",
                body: "\(completed) health quest\(completed > 1 ? "s" : "") auto-completed from HealthKit data.",
                category: "quest"
            )
        }
        return completed
    }

    // MARK: - Nutrition Quest Auto-Complete

    /// Counts today's food entries and auto-completes any quest with a
    /// "meals:<count>" completionCondition when the threshold is met.
    /// Called after a food entry is saved.
    @discardableResult
    func autoCompleteNutritionQuests() -> Int {
        guard let context = modelContext else { return 0 }

        let todayStart = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.dateConsumed >= todayStart
            }
        )
        let todayMealCount = (try? context.fetch(descriptor))?.count ?? 0

        var completed = 0
        for quest in todaysQuests where !quest.isCompleted {
            guard let condition = quest.completionCondition,
                  condition.hasPrefix("meals:") else { continue }
            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let target = Int(parts[1]) else { continue }

            if todayMealCount >= target {
                completeQuest(quest)
                completed += 1
            }
        }
        return completed
    }

    // MARK: - Discipline Check Auto-Complete

    /// Auto-completes "discipline_check" quests when at least one meal is logged
    /// AND at least one other quest has been completed today.
    /// Called after any quest completion and after meal logging.
    @discardableResult
    func autoCompleteDisciplineQuests() -> Int {
        guard let context = modelContext else { return 0 }

        let todayStart = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { entry in
                entry.dateConsumed >= todayStart
            }
        )
        let hasMeals = ((try? context.fetch(descriptor))?.count ?? 0) > 0
        let hasCompletedQuest = todaysQuests.contains { quest in
            quest.isCompleted && quest.completionCondition != "discipline_check"
        }

        guard hasMeals && hasCompletedQuest else { return 0 }

        var completed = 0
        for quest in todaysQuests where !quest.isCompleted {
            guard quest.completionCondition == "discipline_check" else { continue }
            completeQuest(quest)
            completed += 1
        }
        return completed
    }

    // MARK: - Daily Quest Generation

    /// Generates today's quests from HealthKit data if they haven't been generated yet.
    /// Called once on app launch; keyed to today's date so it only runs once per day.
    func generateDefaultDailyQuests() {
        let today = Calendar.current.startOfDay(for: Date())
        let key = "questsGeneratedDate"
        let lastGenerated = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast

        // Already generated today — skip
        guard !Calendar.current.isDate(lastGenerated, inSameDayAs: today) else { return }

        // Reset daily activity counters for the new day
        UserDefaults.standard.set(0, forKey: "rpt_quests_today")
        UserDefaults.standard.set(0, forKey: "rpt_workouts_today")

        guard let context = modelContext, let profile = currentProfile else { return }

        // Keep incomplete quests from previous days visible (read-only)
        // so the player can see what they missed. QuestsView locks
        // interaction for any day that isn't today.

        // ── Check if last week's WEEKLY quests were all completed ─────────────
        // Only weekly quests trigger punishment. Daily quests reward XP but
        // missing them has no penalty — keeps the system encouraging, not punishing.
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let isMonday = weekday == 2
        if isMonday {
            // Look back at last week's quests (Monday to Sunday)
            let lastMonday = calendar.date(byAdding: .day, value: -7, to: today)!
            let weeklyDescriptor = FetchDescriptor<Quest>(
                predicate: #Predicate<Quest> { q in q.dateTag >= lastMonday && q.dateTag < today }
            )
            if let lastWeekQuests = try? context.fetch(weeklyDescriptor) {
                let weeklyOnly = lastWeekQuests.filter { $0.type == .weekly }
                let anyIncomplete = weeklyOnly.contains { !$0.isCompleted }
                if anyIncomplete && !weeklyOnly.isEmpty && profile.hardcoreResetDeadline == nil {
                    let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
                    profile.hardcoreResetDeadline = endOfToday
                }
            }
        }

        // Active plan override: use plan quests instead of generic health-driven ones
        let activePlanID = profile.activePlanID
        if !activePlanID.isEmpty {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
            // Anime plan branch — structured workout data, build full plan quests
            if let plan = AnimeWorkoutPlanService.shared.plan(id: activePlanID) {
                let planQuests = QuestManager.shared.buildPlanQuests(
                    plan: plan, profile: profile, date: today, dueDate: tomorrow
                )
                planQuests.forEach { addQuest($0) }
                UserDefaults.standard.set(today, forKey: key)
                return
            }
            // Custom plan branch — derive training quests from the goal survey.
            if let _ = (try? context.fetch(FetchDescriptor<CustomWorkoutPlan>(predicate: #Predicate { $0.id == activePlanID })))?.first {
                let quests = buildCustomPlanQuests(for: profile, on: today, dueDate: tomorrow)
                quests.forEach { addQuest($0) }
                UserDefaults.standard.set(today, forKey: key)
                return
            }
        }

        // Recovery Mode override: use lighter rehabilitation quests
        if profile.isInRecovery {
            let quests = buildRecoveryQuests(for: profile, on: today)
            quests.forEach { addQuest($0) }
            UserDefaults.standard.set(today, forKey: key)
            return
        }

        // Build quest list driven by the player's health data gaps
        let quests = buildHealthDrivenQuests(for: profile, on: today)
        quests.forEach { addQuest($0) }

        // Generate weekly quests on Mondays (or first launch of the week)
        generateWeeklyQuestsIfNeeded(for: profile, on: today)

        UserDefaults.standard.set(today, forKey: key)
    }

    // MARK: - Weekly Quest Generation

    /// Generates weekly quests once per week (Monday). Weekly quests are the ONLY
    /// quests that trigger punishment for non-completion.
    private func generateWeeklyQuestsIfNeeded(for profile: Profile, on date: Date) {
        let weekKey = "weeklyQuestsGeneratedWeek"
        let calendar = Calendar.current

        // Compute this week's Monday
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2 // Sun=6, Mon=0, Tue=1...
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: date))!

        // Skip if already generated for this week
        let lastWeekGenerated = UserDefaults.standard.object(forKey: weekKey) as? Date ?? .distantPast
        guard !calendar.isDate(lastWeekGenerated, inSameDayAs: thisMonday) else { return }

        // Reset weekly workout counter
        UserDefaults.standard.set(0, forKey: "rpt_weekly_workouts")

        // Due date: next Monday at midnight
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday)!

        let rc = RemoteConfigService.shared
        let workoutGoal = rc.int("weekly_workout_goal", default: 4)
        let weeklyXP = rc.int("xp_weekly_workout_goal", default: 200)

        addQuest(Quest(
            title: "Weekly Training Goal",
            details: "Complete \(workoutGoal) workouts this week. Any type counts — strength, cardio, flexibility, or mixed. Log each workout to track progress.",
            type: .weekly,
            createdAt: Date(),
            dueDate: nextMonday,
            xpReward: weeklyXP,
            creditReward: 50,
            statTarget: "discipline",
            completionCondition: "weekly_workouts:\(workoutGoal)",
            dateTag: thisMonday
        ))

        UserDefaults.standard.set(thisMonday, forKey: weekKey)
    }

    /// Checks weekly quests and auto-completes them when targets are met.
    /// Called after each workout is logged.
    @discardableResult
    func autoCompleteWeeklyQuests() -> Int {
        guard let context = modelContext else { return 0 }

        // Find incomplete weekly quests
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: Date()))!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday)!

        let descriptor = FetchDescriptor<Quest>(
            predicate: #Predicate<Quest> { q in
                q.dateTag >= thisMonday && q.dateTag < nextMonday && !q.isCompleted
            }
        )
        guard let weeklyQuests = try? context.fetch(descriptor) else { return 0 }

        let weeklyWorkouts = UserDefaults.standard.integer(forKey: "rpt_weekly_workouts")
        var completed = 0

        for quest in weeklyQuests {
            guard quest.type == .weekly,
                  let condition = quest.completionCondition else { continue }

            if condition.hasPrefix("weekly_workouts:") {
                let target = Int(condition.dropFirst("weekly_workouts:".count)) ?? 4
                if weeklyWorkouts >= target {
                    completeQuest(quest)
                    completed += 1
                    NotificationInboxManager.shared.add(
                        title: "Weekly Goal Complete!",
                        body: "You hit your weekly workout target of \(target). Great discipline!",
                        category: "quest"
                    )
                }
            }
        }
        return completed
    }

    /// Rehabilitation Arc quests — 50% XP, gentler targets, 3 days post-reset.
    private func buildRecoveryQuests(for profile: Profile, on date: Date) -> [Quest] {
        var quests: [Quest] = []
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)
        let dayNum = 4 - max(0, profile.recoveryDaysRemaining) // Day 1, 2, or 3

        // ── Recovery Arc Header Quest (auto-completed — it's an info banner, not a task) ──
        let header = Quest(
            title: "[REHABILITATION ARC] Day \(dayNum) of 3",
            details: "System detected a critical failure. Reduced difficulty protocols active. Complete all quests to rebuild your foundation. 50% XP penalty lifted after 3 days.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 25, statTarget: "discipline", dateTag: date
        )
        header.isCompleted = true
        header.completedAt = Date()
        quests.append(header)

        // ── Light Movement — 5,000 steps (half of normal) ────────────────────
        quests.append(Quest(
            title: "Light Movement Protocol",
            details: "Walk 5,000 steps today. No intense training required — focus on re-establishing a daily routine.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 40, statTarget: "endurance",
            completionCondition: "steps:5000", dateTag: date
        ))

        // ── Sleep Recovery ────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Sleep Recalibration",
            details: "Achieve 7+ hours of sleep tonight. Your body is recovering from a critical stress event.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 50, statTarget: "energy",
            completionCondition: "sleep:7", dateTag: date
        ))

        // ── Gentle Workout ────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Rehabilitation Training",
            details: "Complete any 15-minute workout — stretching, mobility, or light cardio counts. No heavy lifting required.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 40, statTarget: "health",
            completionCondition: "workout:any", dateTag: date
        ))

        // ── Hydration ─────────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Hydration Protocol",
            details: "Drink 6 glasses of water today. Hydration accelerates recovery and stat restoration.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 25, statTarget: "health",
            completionCondition: "water:6", dateTag: date
        ))

        // ── Nutrition Log ─────────────────────────────────────────────────────
        quests.append(Quest(
            title: "Nutrition Log",
            details: "Log at least 2 meals today in the Diary tab. Rebuilding nutritional awareness is key to recovery.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: 30, statTarget: "discipline",
            completionCondition: "meals:2", dateTag: date
        ))

        applyRandomGPBonuses(to: &quests)
        return quests
    }

    /// Randomly assigns a GP bonus to ~20% of quests. Keeps the economy scarce
    /// so Gold Pieces feel rewarding when they appear.
    private func applyRandomGPBonuses(to quests: inout [Quest]) {
        let rc = RemoteConfigService.shared
        let chance = rc.float("gp_bonus_chance", default: 0.2)  // 20% of quests
        let minGP = rc.int("gp_bonus_min", default: 5)
        let maxGP = rc.int("gp_bonus_max", default: 25)
        guard maxGP > 0 else { return }

        // Ensure min <= max so the closed range doesn't crash at runtime.
        let safeMin = min(minGP, maxGP)
        let safeMax = max(minGP, maxGP)

        for quest in quests {
            if Double.random(in: 0..<1) < Double(chance) {
                quest.creditReward = Int.random(in: safeMin...safeMax)
            }
        }
    }

    /// Builds the standard "Daily Discipline Check" quest. Shared between the
    /// health-driven and custom-plan branches.
    private func makeDisciplineCheckQuest(for profile: Profile, on date: Date, dueDate: Date?) -> Quest {
        let rc = RemoteConfigService.shared
        return Quest(
            title: "Daily Discipline Check",
            details: "Current streak: \(profile.currentStreak) days. Log at least one meal and complete one quest before midnight.",
            type: .daily, createdAt: Date(), dueDate: dueDate,
            xpReward: rc.int("xp_discipline_check", default: 50), statTarget: "discipline",
            completionCondition: "discipline_check", dateTag: date
        )
    }

    /// Builds the standard "Nutrition Log" quest. Shared between the
    /// health-driven and custom-plan branches.
    private func makeNutritionLogQuest(for profile: Profile, on date: Date, dueDate: Date?, tier: QuestManager.PlayerTier? = nil) -> Quest {
        let rc = RemoteConfigService.shared
        let resolvedTier = tier ?? QuestManager.tier(for: profile.level)
        let nutritionBaseXP = rc.int("xp_nutrition_log_base", default: 50)
        return Quest(
            title: "Nutrition Log",
            details: "Log all meals for today in the Diary tab. Hitting your calorie and protein goals awards full XP.",
            type: .daily, createdAt: Date(), dueDate: dueDate,
            xpReward: Int(Double(nutritionBaseXP) * resolvedTier.xpMultiplier), statTarget: "discipline",
            completionCondition: "meals:1", dateTag: date
        )
    }

    /// Analyses the player's current health stats and returns a tailored set of quests.
    private func buildHealthDrivenQuests(for profile: Profile, on date: Date) -> [Quest] {
        var quests: [Quest] = []
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)
        let rc = RemoteConfigService.shared

        // ── Steps ──────────────────────────────────────────────────────────────
        let stepGoal = rc.int("daily_step_goal", default: 10_000)
        let stepGap = stepGoal - profile.dailySteps
        if stepGap > 5_000 {
            quests.append(Quest(
                title: "Step Count Protocol",
                details: "Reach \(stepGoal.formatted()) steps today. Current: \(profile.dailySteps.formatted()). Endurance stat will increase.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_steps_urgent", default: 75), statTarget: "endurance",
                completionCondition: "steps:\(stepGoal)", dateTag: date
            ))
        } else {
            quests.append(Quest(
                title: "Maintain Pace",
                details: "Hit \(stepGoal.formatted()) steps. You're on track — keep moving.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_steps_normal", default: 50), statTarget: "endurance",
                completionCondition: "steps:\(stepGoal)", dateTag: date
            ))
        }

        // ── Sleep ──────────────────────────────────────────────────────────────
        if profile.sleepHours < 6.5 {
            quests.append(Quest(
                title: "Sleep Debt Recovery",
                details: "Last night: \(String(format: "%.1f", profile.sleepHours))h. Sleep deficit detected. Achieve 8h tonight to restore Energy and Focus stats.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_sleep_debt", default: 100), statTarget: "energy",
                completionCondition: "sleep:8", dateTag: date
            ))
        } else if profile.sleepHours < 7.5 {
            quests.append(Quest(
                title: "Rest Optimization",
                details: "Sleep logged: \(String(format: "%.1f", profile.sleepHours))h. Target 8h for maximum stat recovery.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_sleep_normal", default: 60), statTarget: "energy",
                completionCondition: "sleep:8", dateTag: date
            ))
        }

        // ── Active Calories ────────────────────────────────────────────────────
        let calGoal = rc.int("daily_active_calories_goal", default: 400)
        if profile.dailyActiveCalories < calGoal / 2 {
            quests.append(Quest(
                title: "Burn Protocol — URGENT",
                details: "Active calories today: \(profile.dailyActiveCalories) kcal. Target: \(calGoal) kcal. Complete any 30-min workout.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_calories_urgent", default: 120), statTarget: "strength",
                completionCondition: "calories:\(calGoal)", dateTag: date
            ))
        } else if profile.dailyActiveCalories < calGoal {
            quests.append(Quest(
                title: "Burn Target",
                details: "Active calories: \(profile.dailyActiveCalories)/\(calGoal) kcal. Close the gap with a workout session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_calories_normal", default: 80), statTarget: "strength",
                completionCondition: "calories:\(calGoal)", dateTag: date
            ))
        }

        // ── Resting Heart Rate ────────────────────────────────────────────────
        let hrThreshold = rc.int("resting_hr_threshold", default: 75)
        if profile.restingHeartRate > hrThreshold {
            quests.append(Quest(
                title: "Cardiovascular Conditioning",
                details: "Resting HR: \(profile.restingHeartRate) bpm — above optimal (>\(hrThreshold) bpm). 20 minutes of zone-2 cardio will improve Health stat.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_cardio_conditioning", default: 90), statTarget: "health",
                completionCondition: "workout:cardio", dateTag: date
            ))
        }

        // ── Discipline (streak guard) ─────────────────────────────────────────
        quests.append(makeDisciplineCheckQuest(for: profile, on: date, dueDate: tomorrow))

        // ── Low stat — Focus ──────────────────────────────────────────────────
        let focusThreshold = rc.int("focus_low_threshold", default: 40)
        if profile.focus < Double(focusThreshold) {
            quests.append(Quest(
                title: "Cognitive Training",
                details: "Focus stat is low (\(Int(profile.focus))/100). Meditate for 10 minutes or complete a focused deep-work session.",
                type: .daily, createdAt: Date(), dueDate: tomorrow,
                xpReward: rc.int("xp_cognitive_training", default: 70), statTarget: "focus",
                completionCondition: "meditation:10", dateTag: date
            ))
        }

        // ── Guaranteed: Daily Training — always present so there is always a workout quest ──
        let tier = QuestManager.tier(for: profile.level)
        let weekday = Calendar.current.component(.weekday, from: date)
        let trainingFocus: String
        let trainingDetails: String
        switch weekday {
        case 2, 5: // Mon, Thu — Push
            trainingFocus = "Push Day"
            trainingDetails = "Upper body push — chest, shoulders, triceps. Complete at least 3 working sets of any push movement."
        case 3, 6: // Tue, Fri — Pull
            trainingFocus = "Pull Day"
            trainingDetails = "Upper body pull — back, biceps, rear delts. Complete at least 3 working sets of any pull movement."
        case 4, 7: // Wed, Sat — Legs
            trainingFocus = "Leg Day"
            trainingDetails = "Lower body — quads, hamstrings, glutes. Complete at least 3 working sets of any leg movement."
        default:   // Sun — Active Recovery
            trainingFocus = "Active Recovery"
            trainingDetails = "Light movement day — stretching, mobility, yoga, or a slow walk. Let your body recover and adapt."
        }
        let trainingBaseXP = rc.int("xp_daily_training_base", default: 100)
        quests.append(Quest(
            title: "Daily Training: \(trainingFocus)",
            details: "\(tier.rank.displayName) Protocol — \(trainingDetails)\nComplete any logged workout to auto-check this quest.",
            type: .daily, createdAt: Date(), dueDate: tomorrow,
            xpReward: Int(Double(trainingBaseXP) * tier.xpMultiplier), statTarget: "strength",
            completionCondition: "workout:any", dateTag: date
        ))

        // ── Guaranteed: Nutrition Log — always present ─────────────────────────
        quests.append(makeNutritionLogQuest(for: profile, on: date, dueDate: tomorrow, tier: tier))

        applyRandomGPBonuses(to: &quests)

        // ── Cap to max_daily_quests if configured ─────────────────────────────
        let maxQuests = rc.int("max_daily_quests", default: 0)
        if maxQuests > 0 && quests.count > maxQuests {
            return Array(quests.prefix(maxQuests))
        }
        return quests
    }
    
    // MARK: - Recipe Management
    func searchRecipes(query: String? = nil, limit: Int = 10) async throws -> [Recipe] {
        // Try to fetch from API
        do {
            let recipes = try await recipeAPI.fetchRecipes(query: query, limit: limit)
            
            // Cache the results
            if query == nil || query?.isEmpty == true {
                // Only cache general searches to avoid cluttering
                cachedRecipes = recipes
            }
            
            return recipes
        } catch {
            // Fallback to cached recipes if available
            if !cachedRecipes.isEmpty {
                return cachedRecipes.prefix(limit).map { $0 }
            }
            throw error
        }
    }
    
    func saveRecipeToProfile(_ recipe: Recipe) {
        // Record meal (affects health stats, but no XP - only quests give XP)
        updateProfile { profile in
            profile.recordMeal(healthiness: .healthy) // Default to healthy
        }

    }
    
    // MARK: - Health Data Integration

    /// Called whenever HealthKit delivers new data (via observer query) or the
    /// health manager publishes an objectWillChange notification.
    private func handleHealthDataUpdate() async {
        // Multiple HealthKit observer queries can fire in rapid succession after a
        // workout sync (steps + active calories + workouts + HR + sleep all at once).
        // Debounce to one fetch per minute to prevent battery drain and write storms.
        if Date().timeIntervalSince(lastHealthFetchAt) < 60 {
            return
        }
        lastHealthFetchAt = Date()

        guard let profile = currentProfile else { return }

        // Fetch latest health data
        await healthManager.fetchTodaysHealthData(for: profile)

        // Update daily stats (this handles XP internally once per day)
        profile.updateDailyStats()

        saveLocalChanges()

        // Reload quests so we have the latest state before checking conditions
        refreshTodaysQuests()

        // Auto-complete any custom quests whose HealthKit threshold is now met
        autoCompleteHealthQuests()
    }

    // MARK: - HealthKit Background Observer Setup

    /// Registers HKObserverQuery + enableBackgroundDelivery for the four core
    /// metrics: steps, active calories, workouts, and resting heart rate.
    ///
    /// When HealthKit wakes the app via silent push (background delivery), the
    /// observer fires, we refetch and update the profile in SwiftData.
    /// This replaces any polling timer and is iOS-recommended for battery health.
    private func startHealthKitBackgroundDelivery() {
        guard hkStore.authorizationStatus(for: HKQuantityType(.stepCount)) != .notDetermined else {
            // HealthKit not yet authorised — do nothing; observers will be
            // registered after the user grants permission via requestAuthorization.
            return
        }

        let trackedTypes: [(HKSampleType, HKUpdateFrequency)] = [
            (HKQuantityType(.stepCount),          .hourly),
            (HKQuantityType(.activeEnergyBurned), .hourly),
            (HKQuantityType(.restingHeartRate),   .daily),
            (HKCategoryType(.sleepAnalysis),      .daily),
            (HKObjectType.workoutType(),          .immediate),
        ]

        for (sampleType, frequency) in trackedTypes {
            let typeID = sampleType.identifier

            // Skip if an observer is already registered for this type.
            guard observerQueries[typeID] == nil else { continue }

            // Register background delivery so HealthKit wakes the app via silent push.
            hkStore.enableBackgroundDelivery(for: sampleType, frequency: frequency) { _, error in
                if let error { print("[HealthKit] Background delivery failed for \(typeID): \(error)") }
            }

            // Observer query fires when new samples arrive (foreground or background).
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    print("[HealthKit] Observer error for \(typeID): \(error)")
                    completionHandler()
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.handleHealthDataUpdate()
                    completionHandler() // Must be called to signal HealthKit the delivery was handled.
                }
            }

            observerQueries[typeID] = query
            hkStore.execute(query)
        }
    }

    /// Call this after HealthKit authorization is granted so observers are
    /// registered immediately without waiting for the next app launch.
    func registerHealthKitObserversAfterAuthorization() {
        startHealthKitBackgroundDelivery()
    }

    /// Call when app returns to foreground to ensure health data is fresh.
    func refreshHealthOnForeground() {
        Task { await handleHealthDataUpdate() }
        // Re-run daily quest generation in case the day rolled over while the app was open
        generateDefaultDailyQuests()
        refreshTodaysQuests()
        // Check for hardcore reset penalty (missed quests) on every foreground,
        // not just from the HomeView timer
        currentProfile?.applyHardcoreResetIfNeeded()
    }
    
    func recordHealthAction(_ action: HealthAction) {
        guard let profile = currentProfile else { return }
        
        switch action {
        case .drinkWater:
            profile.recordWaterIntake()
            ActivityLogManager.shared.log(.health, "Drank water (+1 cup)", detail: "Total: \(profile.waterIntake) cups today")
        case .recordMeal(let healthiness):
            profile.recordMeal(healthiness: healthiness)
            ActivityLogManager.shared.log(.health, "Logged meal (\(healthiness))")
        case .recordWorkout(let type, let duration):
            profile.recordWorkout(type: type, duration: duration)
            ActivityLogManager.shared.log(.health, "Logged \(type.displayName) workout", detail: "\(duration) minutes")
        case .recordSleep(let hours):
            profile.recordSleep(hours: hours)
            ActivityLogManager.shared.log(.health, "Logged \(String(format: "%.1f", hours))h sleep")
        case .recordMeditation(let minutes):
            profile.recordMeditation(minutes: minutes)
            ActivityLogManager.shared.log(.health, "Meditation session", detail: "\(minutes) minutes")
        }

        saveLocalChanges()

        // Damage the active weekly raid boss based on the action
        switch action {
        case .drinkWater:
            BossRaidService.shared.applyDamage(source: .waterCup, amount: 1)
        case .recordWorkout(_, let duration):
            BossRaidService.shared.applyDamage(source: .workoutMinutes, amount: duration)
        default:
            break
        }

        // Check quest auto-completion for water/meditation actions
        switch action {
        case .drinkWater, .recordMeditation:
            autoCompleteHealthQuests()
        default:
            break
        }
    }
    
    // MARK: - Local Storage
    func saveLocalChanges() {
        guard let context = modelContext else { return }
        
        do {
            try context.save()
            lastSaveError = nil
        } catch {
            print("Failed to save local changes: \(error)")
            lastSaveError = error.localizedDescription
        }
    }
    
    // MARK: - Sync
    private func startPeriodicSync() {
        // No-op: sync is driven by HKObserverQuery background delivery.
    }

    func forceSyncNow() async {
        await handleHealthDataUpdate()
    }

    // MARK: - CloudKit Conflict Reconciliation

    /// Called after a CloudKit import completes. Ensures progression fields
    /// reflect the highest values across all devices (prevents last-write-wins
    /// from silently regressing XP, level, or bestStreak).
    func reconcileAfterCloudSync() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Profile>()
        guard let profiles = try? context.fetch(descriptor) else { return }

        for profile in profiles {
            // Derive the correct level from totalXPEarned to detect sync regression
            var derivedLevel = 1
            var derivedXP = profile.totalXPEarned
            while derivedXP >= profile.levelXPThreshold(level: derivedLevel) {
                derivedXP -= profile.levelXPThreshold(level: derivedLevel)
                derivedLevel += 1
            }

            // If the synced profile has a lower level than what totalXPEarned implies,
            // the remote wrote a stale level — restore the derived values.
            if profile.level < derivedLevel {
                profile.level = derivedLevel
                profile.xp = derivedXP
                print("[CloudKit] Reconciled: level \(profile.level), xp \(profile.xp) from totalXPEarned \(profile.totalXPEarned)")
            }

            // bestStreak should never decrease — take the max
            // (already protected by code, but CloudKit sync could overwrite)
            if profile.currentStreak > profile.bestStreak {
                profile.bestStreak = profile.currentStreak
            }
        }

        saveLocalChanges()
    }

    // MARK: - Custom Plan Quest Builder

    private func buildCustomPlanQuests(for profile: Profile, on date: Date, dueDate: Date?) -> [Quest] {
        // If the user hasn't completed the goal survey yet, fall back to the
        // existing placeholder set so quests are never empty.
        guard profile.goalSurveyCompleted else {
            var quests: [Quest] = []
            quests.append(Quest(
                title: "[CUSTOM PLAN] Goal Survey Required",
                details: "Open the goal survey from Settings to unlock training quests for your custom plan.",
                type: .daily, createdAt: Date(), dueDate: dueDate,
                xpReward: 0, statTarget: "discipline",
                completionCondition: "", dateTag: date
            ))
            quests.append(makeDisciplineCheckQuest(for: profile, on: date, dueDate: dueDate))
            quests.append(makeNutritionLogQuest(for: profile, on: date, dueDate: dueDate))
            applyRandomGPBonuses(to: &quests)
            return quests
        }

        var quests: [Quest] = []

        // Compute today's training day from the survey schedule.
        let weekday = Calendar.current.component(.weekday, from: date) // 1=Sun … 7=Sat
        let day = trainingDay(
            for: weekday,
            daysPerWeek: profile.goalSurveyDaysPerWeek,
            split: profile.goalSurveySplit ?? .fullBody
        )

        let intensity = profile.goalSurveyIntensity ?? .moderate
        let sessionMinutes = profile.goalSurveySessionMinutes > 0 ? profile.goalSurveySessionMinutes : 60
        let baseXP = 80
        let scaledXP = Int(Double(baseXP) * intensity.xpMultiplier)

        switch day {
        case .rest:
            // Rest day — just nutrition + recovery + discipline
            quests.append(Quest(
                title: "Rest Day Recovery",
                details: "Hit your sleep and water targets today. Rest is when growth happens — protect it.",
                type: .daily, createdAt: Date(), dueDate: dueDate,
                xpReward: 30, statTarget: "energy",
                completionCondition: "water:8", dateTag: date
            ))

        case .training(let focus):
            let bodyParts = focus.bodyParts.joined(separator: ", ")
            let intensityNote: String
            switch intensity {
            case .easy:     intensityNote = "Keep RPE 6-7. Focus on form."
            case .moderate: intensityNote = "RPE 7-8. Steady working weight."
            case .intense:  intensityNote = "RPE 8-9. Push the last reps."
            }
            quests.append(Quest(
                title: "Daily Training: \(focus.title)",
                details: "Today is \(focus.title) day. Hit \(bodyParts). 3 working sets of any qualifying movement. Target \(sessionMinutes) min. \(intensityNote)",
                type: .daily, createdAt: Date(), dueDate: dueDate,
                xpReward: scaledXP, statTarget: "strength",
                completionCondition: "workout:any", dateTag: date
            ))

            // Bonus quest if today's focus matches one of the user's chosen focus areas
            let userFocusAreas = profile.goalSurveyFocusAreas.map { $0.rawValue.lowercased() }
            if focus.bodyParts.contains(where: { userFocusAreas.contains($0.lowercased()) }) {
                quests.append(Quest(
                    title: "Bonus Focus: \(focus.title)",
                    details: "You marked this body part as a priority. Hit at least 2 dedicated isolation sets after the main lifts.",
                    type: .daily, createdAt: Date(), dueDate: dueDate,
                    xpReward: 25, statTarget: "discipline",
                    completionCondition: "", dateTag: date
                ))
            }
        }

        // Cardio quest a few days a week based on cardio preference
        let cardio = profile.goalSurveyCardio ?? .none
        if cardio.sessionsPerWeek > 0 {
            // Map sessions per week to deterministic weekdays so the quest doesn't appear randomly.
            // 2 sessions: Tue, Fri. 3 sessions: Mon, Wed, Fri. 4 sessions: Mon, Tue, Thu, Fri.
            let cardioDays: Set<Int>
            switch cardio.sessionsPerWeek {
            case 2: cardioDays = [3, 6]
            case 3: cardioDays = [2, 4, 6]
            case 4: cardioDays = [2, 3, 5, 6]
            default: cardioDays = []
            }
            if cardioDays.contains(weekday) {
                let cardioMinutes: Int
                let cardioDescription: String
                switch cardio {
                case .light:    cardioMinutes = 20; cardioDescription = "20 min walk or easy bike"
                case .moderate: cardioMinutes = 30; cardioDescription = "30 min jog or steady cycling"
                case .high:     cardioMinutes = 25; cardioDescription = "25 min HIIT or sprint intervals"
                default: cardioMinutes = 0; cardioDescription = ""
                }
                if cardioMinutes > 0 {
                    quests.append(Quest(
                        title: "Cardio Session",
                        details: "\(cardioDescription). Track via the Patrol map or log a workout.",
                        type: .daily, createdAt: Date(), dueDate: dueDate,
                        xpReward: 50, statTarget: "endurance",
                        completionCondition: "workout:cardio", dateTag: date
                    ))
                }
            }
        }

        // Always include the standard daily anchors
        quests.append(makeDisciplineCheckQuest(for: profile, on: date, dueDate: dueDate))
        quests.append(makeNutritionLogQuest(for: profile, on: date, dueDate: dueDate))

        applyRandomGPBonuses(to: &quests)
        return quests
    }

    // MARK: - Custom Plan Schedule

    private enum CustomTrainingDay {
        case rest
        case training(focus: TrainingFocus)
    }

    private struct TrainingFocus {
        let title: String       // "Push", "Pull", "Legs", "Full Body", "Upper", "Lower", "Chest", etc.
        let bodyParts: [String] // matched against profile.goalSurveyFocusAreas
    }

    private func trainingDay(for weekday: Int, daysPerWeek: Int, split: GoalSurveySplit) -> CustomTrainingDay {
        // weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        let schedule: [CustomTrainingDay] = scheduleFor(daysPerWeek: max(2, min(daysPerWeek, 7)), split: split)
        // schedule index 0 = Monday by convention; remap weekday (1=Sun..7=Sat) accordingly
        let mondayBasedIndex = (weekday + 5) % 7  // Sun=6, Mon=0, Tue=1, ... Sat=5
        return schedule[mondayBasedIndex]
    }

    private func scheduleFor(daysPerWeek: Int, split: GoalSurveySplit) -> [CustomTrainingDay] {
        let push  = TrainingFocus(title: "Push",      bodyParts: ["chest","shoulders","arms"])
        let pull  = TrainingFocus(title: "Pull",      bodyParts: ["back","arms"])
        let legs  = TrainingFocus(title: "Legs",      bodyParts: ["legs","glutes"])
        let upper = TrainingFocus(title: "Upper",     bodyParts: ["chest","back","shoulders","arms"])
        let lower = TrainingFocus(title: "Lower",     bodyParts: ["legs","glutes","core"])
        let full  = TrainingFocus(title: "Full Body", bodyParts: ["chest","back","legs","shoulders","arms","glutes","core"])
        let chest = TrainingFocus(title: "Chest",     bodyParts: ["chest"])
        let back  = TrainingFocus(title: "Back",      bodyParts: ["back"])
        let legs2 = TrainingFocus(title: "Legs",      bodyParts: ["legs","glutes"])
        let shldr = TrainingFocus(title: "Shoulders", bodyParts: ["shoulders"])
        let arms  = TrainingFocus(title: "Arms",      bodyParts: ["arms"])

        let rest: CustomTrainingDay = .rest

        // Indices: [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
        switch split {
        case .fullBody:
            switch daysPerWeek {
            case 2: return [.training(focus: full), rest, rest, .training(focus: full), rest, rest, rest]
            case 3: return [.training(focus: full), rest, .training(focus: full), rest, .training(focus: full), rest, rest]
            case 4: return [.training(focus: full), .training(focus: full), rest, .training(focus: full), .training(focus: full), rest, rest]
            default: return [.training(focus: full), .training(focus: full), .training(focus: full), .training(focus: full), .training(focus: full), rest, rest]
            }
        case .upperLower:
            switch daysPerWeek {
            case 2: return [.training(focus: upper), rest, rest, .training(focus: lower), rest, rest, rest]
            case 3: return [.training(focus: upper), rest, .training(focus: lower), rest, .training(focus: upper), rest, rest]
            case 4: return [.training(focus: upper), .training(focus: lower), rest, .training(focus: upper), .training(focus: lower), rest, rest]
            case 5: return [.training(focus: upper), .training(focus: lower), .training(focus: upper), rest, .training(focus: lower), .training(focus: upper), rest]
            default: return [.training(focus: upper), .training(focus: lower), .training(focus: upper), .training(focus: lower), .training(focus: upper), .training(focus: lower), rest]
            }
        case .pushPullLegs:
            switch daysPerWeek {
            case 3: return [.training(focus: push), rest, .training(focus: pull), rest, .training(focus: legs), rest, rest]
            case 4: return [.training(focus: push), .training(focus: pull), rest, .training(focus: legs), .training(focus: push), rest, rest]
            case 5: return [.training(focus: push), .training(focus: pull), .training(focus: legs), rest, .training(focus: push), .training(focus: pull), rest]
            default: return [.training(focus: push), .training(focus: pull), .training(focus: legs), .training(focus: push), .training(focus: pull), .training(focus: legs), rest]
            }
        case .broSplit:
            switch daysPerWeek {
            case 4: return [.training(focus: chest), .training(focus: back), rest, .training(focus: legs2), .training(focus: arms), rest, rest]
            default: return [.training(focus: chest), .training(focus: back), .training(focus: shldr), .training(focus: legs2), .training(focus: arms), rest, rest]
            }
        case .custom:
            // For "custom" the survey doesn't impose a schedule. Treat every requested day as a generic full-body day so the user has SOMETHING to log.
            var sched: [CustomTrainingDay] = Array(repeating: .rest, count: 7)
            let trainingIndices: [Int]
            switch daysPerWeek {
            case 2: trainingIndices = [0, 3]
            case 3: trainingIndices = [0, 2, 4]
            case 4: trainingIndices = [0, 1, 3, 4]
            case 5: trainingIndices = [0, 1, 3, 4, 5]
            case 6: trainingIndices = [0, 1, 2, 3, 4, 5]
            default: trainingIndices = [0, 1, 2, 3, 4, 5, 6]
            }
            for i in trainingIndices { sched[i] = .training(focus: full) }
            return sched
        }
    }

    // MARK: - Cleanup
    deinit {
        // DataManager is a singleton — deinit is effectively dead code.
        // Observer queries are cleaned up implicitly when the process exits.
        cancellables.removeAll()
    }
}

// MARK: - Health Actions
enum HealthAction {
    case drinkWater
    case recordMeal(MealHealthiness)
    case recordWorkout(WorkoutType, duration: Int)
    case recordSleep(hours: Double)
    case recordMeditation(minutes: Int)
}

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rpt.networkMonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
