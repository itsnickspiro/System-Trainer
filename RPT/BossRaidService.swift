import Foundation
import SwiftData
import Combine

@MainActor
final class BossRaidService: ObservableObject {
    static let shared = BossRaidService()

    @Published private(set) var currentBoss: WeeklyBoss? = nil
    @Published private(set) var currentArchetype: WeeklyBossArchetype? = nil

    private weak var modelContext: ModelContext?

    private init() {}

    /// Wire the SwiftData context. Call once from RPTApp / DataManager init.
    func setContext(_ context: ModelContext) {
        self.modelContext = context
        spawnIfNeeded()
    }

    /// Compute the Monday 00:00 of the current week.
    private func currentWeekStart() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Calendar.current.startOfDay(for: Date())
    }

    /// Pick this week's boss archetype deterministically from the week of year.
    private func archetypeForCurrentWeek() -> WeeklyBossArchetype {
        let weekOfYear = Calendar.current.component(.weekOfYear, from: Date())
        let allCases = WeeklyBossArchetype.allCases
        return allCases[weekOfYear % allCases.count]
    }

    /// Spawn this week's boss if no row exists yet for the current week.
    /// Idempotent — safe to call on every launch / foreground.
    func spawnIfNeeded() {
        guard let context = modelContext else { return }
        let weekStart = currentWeekStart()
        let descriptor = FetchDescriptor<WeeklyBoss>(
            predicate: #Predicate<WeeklyBoss> { $0.weekStartDate == weekStart }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            currentBoss = existing
            currentArchetype = WeeklyBossArchetype(rawValue: existing.bossKey)
            return
        }

        let archetype = archetypeForCurrentWeek()
        let boss = WeeklyBoss(
            bossKey: archetype.rawValue,
            weekStartDate: weekStart,
            maxHP: archetype.maxHP
        )
        context.insert(boss)
        try? context.save()
        currentBoss = boss
        currentArchetype = archetype
    }

    /// Apply damage from a specific activity source. Only damages the boss if
    /// the source matches its archetype.
    func applyDamage(source: BossDamageSource, amount: Int) {
        guard let boss = currentBoss, !boss.isDefeated else { return }
        guard let archetype = currentArchetype else { return }

        let isMatch: Bool = {
            switch (archetype, source) {
            case (.slothDemon, .steps): return true
            case (.gluttonKing, .meal): return true
            case (.hollowWarrior, .workoutMinutes): return true
            case (.ironSleeper, .questComplete): return true
            case (.witheringSpirit, .waterCup): return true
            case (.forsakenDragon, .xpEarned): return true
            default: return false
            }
        }()

        guard isMatch, amount > 0 else { return }

        boss.damageDealt += amount
        boss.currentHP = max(0, boss.maxHP - boss.damageDealt)

        if boss.currentHP <= 0 && boss.defeatedAt == nil {
            boss.defeatedAt = Date()
            // Defer reward until the user explicitly claims it via the UI button.
        }
        try? modelContext?.save()
    }

    /// User tapped Claim on a defeated boss.
    func claimReward() {
        guard let boss = currentBoss,
              boss.isDefeated,
              !boss.rewardClaimed,
              let archetype = currentArchetype else { return }

        boss.rewardClaimed = true
        try? modelContext?.save()

        // Award GP via PlayerProfileService
        Task {
            await PlayerProfileService.shared.addCredits(
                amount: archetype.defeatReward,
                type: "boss_defeat",
                referenceKey: archetype.rawValue
            )
        }

        // Fire isekai system notification
        let notification = SystemSkillNotification(
            title: "Boss Defeated",
            skillName: archetype.defeatTitle.uppercased(),
            description: "\(archetype.displayName) has fallen. \(archetype.defeatReward) GP awarded. Title 'The \(archetype.defeatTitle)' is now yours.",
            rarity: archetype == .forsakenDragon ? .legendary : .epic,
            icon: archetype.icon,
            sound: true
        )
        SystemNotificationManager.shared.present(notification)
    }
}

/// All the activity sources that can damage a boss. Each source matches
/// at most one archetype — the service decides which boss this damage
/// applies to and ignores the rest.
enum BossDamageSource {
    case steps             // amount = step delta
    case meal              // amount = 1 per meal
    case workoutMinutes    // amount = workout duration
    case questComplete     // amount = 1
    case waterCup          // amount = 1
    case xpEarned          // amount = XP gained
}
