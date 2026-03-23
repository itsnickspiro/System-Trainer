import Foundation
import SwiftData
import SwiftUI
import Combine

/// Evaluates profile state and unlocks achievements that haven't been earned yet.
/// Call `checkAll(profile:context:)` after any state-changing action.
@MainActor
final class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    /// Published so the UI can react and show a celebration banner.
    @Published var recentlyUnlocked: AchievementID? = nil

    private init() {}

    /// Check every achievement condition and unlock anything newly earned.
    /// Returns a list of newly unlocked IDs (may be empty).
    @discardableResult
    func checkAll(profile: Profile, context: ModelContext) -> [AchievementID] {
        // Load already-unlocked IDs
        let descriptor = FetchDescriptor<Achievement>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let unlockedIDs = Set(existing.compactMap { $0.achievementID })

        var newlyUnlocked: [AchievementID] = []

        func check(_ id: AchievementID, condition: Bool) {
            guard condition, !unlockedIDs.contains(id) else { return }
            let achievement = Achievement(id: id)
            context.insert(achievement)
            newlyUnlocked.append(id)
        }

        // --- Streaks ---
        check(.streak3,   condition: profile.currentStreak >= 3)
        check(.streak7,   condition: profile.currentStreak >= 7)
        check(.streak30,  condition: profile.currentStreak >= 30)
        check(.streak100, condition: profile.currentStreak >= 100)

        // --- Workouts (tracked via WorkoutSession count) ---
        let sessionDescriptor = FetchDescriptor<WorkoutSession>()
        let sessionCount = (try? context.fetch(sessionDescriptor))?.count ?? 0
        check(.firstWorkout,  condition: sessionCount >= 1)
        check(.workouts10,    condition: sessionCount >= 10)
        check(.workouts50,    condition: sessionCount >= 50)
        check(.workouts100,   condition: sessionCount >= 100)

        // --- Levels ---
        check(.level5,  condition: profile.level >= 5)
        check(.level10, condition: profile.level >= 10)
        check(.level25, condition: profile.level >= 25)
        check(.level50, condition: profile.level >= 50)

        // --- Rank ups ---
        let tierRanks = QuestManager.TierRank.allCases
        let currentRank = QuestManager.tier(for: profile.level).rank
        func rankIndex(_ r: QuestManager.TierRank) -> Int { tierRanks.firstIndex(of: r) ?? 0 }
        let ci = rankIndex(currentRank)
        check(.rankD, condition: ci >= rankIndex(.d))
        check(.rankC, condition: ci >= rankIndex(.c))
        check(.rankB, condition: ci >= rankIndex(.b))
        check(.rankA, condition: ci >= rankIndex(.a))
        check(.rankS, condition: currentRank == .s)

        // --- Time-based ---
        if let lastWorkout = profile.lastWorkoutTime {
            let hour = Calendar.current.component(.hour, from: lastWorkout)
            check(.earlyBird, condition: hour < 7)
            check(.nightOwl,  condition: hour >= 21)
        }

        if !newlyUnlocked.isEmpty {
            try? context.save()
            // Broadcast the most recently unlocked (last in list = most recent)
            recentlyUnlocked = newlyUnlocked.last
            // Clear after a brief delay so the UI resets
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { self.recentlyUnlocked = nil }
            }
        }

        return newlyUnlocked
    }
}

// MARK: - Achievements Display View

struct AchievementsView: View {
    @Environment(\.modelContext) private var context
    @Query private var achievements: [Achievement]

    private let allIDs = AchievementID.allCases

    private var unlockedIDs: Set<AchievementID> {
        Set(achievements.compactMap { $0.achievementID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(allIDs, id: \.self) { id in
                        AchievementCard(id: id, unlocked: unlockedIDs.contains(id))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct AchievementCard: View {
    let id: AchievementID
    let unlocked: Bool

    private var accentColor: Color {
        Color(hex: id.color) ?? .cyan
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(unlocked ? accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: id.icon)
                    .font(.system(size: 26))
                    .foregroundColor(unlocked ? accentColor : .gray.opacity(0.4))
                    .symbolEffect(.bounce, value: unlocked)
            }
            Text(id.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if unlocked {
                Text("Unlocked")
                    .font(.caption2)
                    .foregroundColor(accentColor)
            } else {
                Text(id.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(unlocked ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        )
        .opacity(unlocked ? 1.0 : 0.6)
    }
}

// MARK: - Achievement Unlock Banner (shown in HomeView overlay)

struct AchievementUnlockBanner: View {
    let id: AchievementID
    @State private var visible = false

    private var accentColor: Color {
        Color(hex: id.color) ?? .cyan
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 46, height: 46)
                Image(systemName: id.icon)
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.caption)
                    .foregroundColor(accentColor)
                    .fontWeight(.semibold)
                Text(id.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(id.description)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .offset(y: visible ? 0 : -120)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: visible)
        .onAppear { visible = true }
    }
}
