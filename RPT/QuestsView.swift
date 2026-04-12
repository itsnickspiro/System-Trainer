import SwiftUI
import SwiftData

// Rolling 14-day window for bounded @Query predicate in QuestsView.
private let questsViewCutoff: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast

struct QuestsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Quest> { q in
        q.dateTag >= questsViewCutoff
    }, sort: \Quest.createdAt, order: .reverse) private var quests: [Quest]
    @ObservedObject private var dataManager = DataManager.shared
    @State private var selectedDay = Date()
    @State private var impossibleWarnings: [ImpossibleDayDetector.ImpossibleWarning] = []

    /// True when the selected day is not today — quests are view-only, no XP awarded.
    private var isDayLocked: Bool {
        !Calendar.current.isDateInToday(selectedDay)
    }
    
    private var todaysQuests: [Quest] {
        quests.filter { Calendar.current.isDate($0.dateTag, inSameDayAs: selectedDay) }
    }
    
    private var activeQuests: [Quest] {
        todaysQuests.filter { !$0.isCompleted }
    }

    private var completedQuests: [Quest] {
        todaysQuests.filter { $0.isCompleted }
    }

    // MARK: - Quest section helpers

    private enum QuestSection: String {
        case weekly = "WEEKLY"
        case daily = "DAILY"
        case special = "SPECIAL"

        var icon: String {
            switch self {
            case .weekly:  return "calendar.badge.clock"
            case .daily:   return "sun.max.fill"
            case .special: return "star.fill"
            }
        }

        var color: Color {
            switch self {
            case .weekly:  return .purple
            case .daily:   return .cyan
            case .special: return .yellow
            }
        }

        var subtitle: String {
            switch self {
            case .weekly:  return "Punishment if incomplete"
            case .daily:   return "No punishment"
            case .special: return "Bonus"
            }
        }
    }

    private func section(for quest: Quest) -> QuestSection {
        if quest.type == .weekly { return .weekly }
        if quest.type == .oneTime { return .special }
        return .daily
    }

    /// Weekly quests span the whole week — show them on every day's view.
    private var weeklyQuests: [Quest] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDay)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: selectedDay))!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        return quests.filter { $0.type == .weekly && $0.dateTag >= monday && $0.dateTag < nextMonday }
    }

    private func quests(in section: QuestSection) -> [Quest] {
        switch section {
        case .weekly:  return weeklyQuests
        case .daily:   return todaysQuests.filter { $0.type != .weekly && $0.type != .oneTime }
        case .special: return todaysQuests.filter { $0.type == .oneTime }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned header
                HStack {
                    Text("Quests")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    if isDayLocked {
                        Button("Today") {
                            selectedDay = Date()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .stroke(Color.cyan, lineWidth: 1.5)
                        )
                        .shadow(color: .cyan.opacity(0.45), radius: 8, x: 0, y: 0)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Week scroller pinned below title
                WeekScroller(selectedDay: $selectedDay)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        // Locked day banner
                        if isDayLocked {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
                                Text(Calendar.current.isDateInFuture(selectedDay)
                                     ? "Future day — quests unlock when it arrives"
                                     : "Past day — read-only. Complete quests on today's date to earn XP.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemFill))
                            )
                            .padding(.horizontal)
                        }

                        // Real-World Data at the top to correlate with quests
                        RealWorldDataSummary()

                        // Impossible-day warnings — flag quests that exceed physiological limits
                        if !impossibleWarnings.isEmpty {
                            ImpossibleDayBanner(warnings: impossibleWarnings)
                                .padding(.horizontal)
                        }
                        
                        if todaysQuests.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "target")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cyan.opacity(0.5))

                                Text("No missions for this day")
                                    .font(.title3.bold())
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Text("Quests will appear here at midnight.")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 60)
                        } else {
                            // Progress summary
                            let allQuests = todaysQuests + weeklyQuests.filter { q in !todaysQuests.contains { $0.id == q.id } }
                            let total = allQuests.count
                            let done = allQuests.filter(\.isCompleted).count
                            HStack(spacing: 12) {
                                ProgressView(value: Double(done), total: Double(max(1, total)))
                                    .tint(.cyan)
                                Text("\(done)/\(total)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            .padding(.horizontal)

                            // Sections: Weekly → Daily → Special
                            ForEach([QuestSection.weekly, .daily, .special], id: \.rawValue) { section in
                                let sectionQuests = quests(in: section)
                                if !sectionQuests.isEmpty {
                                    questSection(section,
                                                 active: sectionQuests.filter { !$0.isCompleted },
                                                 completed: sectionQuests.filter(\.isCompleted))
                                }
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .background(colorScheme == .dark ? .black.opacity(0.95) : .white)
            .onAppear {
                impossibleWarnings = ImpossibleDayDetector.detect(in: todaysQuests)
            }
            .onChange(of: todaysQuests.count) {
                impossibleWarnings = ImpossibleDayDetector.detect(in: todaysQuests)
            }
        }
    }
    
    @ViewBuilder
    private func questSection(_ section: QuestSection, active: [Quest], completed: [Quest]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(section.color)
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(section.color.opacity(0.9))
                Text(section.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemFill)))
                Spacer()
                let sectionTotal = active.count + completed.count
                let sectionDone = completed.count
                Text("\(sectionDone)/\(sectionTotal)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(sectionDone == sectionTotal ? .green : .secondary)
            }
            .padding(.horizontal)

            LazyVStack(spacing: 8) {
                ForEach(active) { quest in
                    QuestRow(quest: quest, isLocked: isDayLocked)
                }
                ForEach(completed) { quest in
                    QuestRow(quest: quest, isLocked: isDayLocked)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Quest Category (drives form fields + XP calculation)

enum QuestCategory: String, CaseIterable, Identifiable {
    case steps       = "steps"
    case workout     = "workout"
    case calories    = "calories"
    case sleep       = "sleep"
    case manual      = "manual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps:    return "Steps"
        case .workout:  return "Workout"
        case .calories: return "Active Calories"
        case .sleep:    return "Sleep"
        case .manual:   return "Custom / Manual"
        }
    }

    var icon: String {
        switch self {
        case .steps:    return "figure.walk"
        case .workout:  return "dumbbell.fill"
        case .calories: return "flame.fill"
        case .sleep:    return "bed.double.fill"
        case .manual:   return "checkmark.seal.fill"
        }
    }

    /// The stat that improves when this quest is completed.
    var statTarget: String {
        switch self {
        case .steps:    return "endurance"
        case .workout:  return "strength"
        case .calories: return "endurance"
        case .sleep:    return "energy"
        case .manual:   return "discipline"
        }
    }

    /// Description of how completion is verified.
    var verificationNote: String {
        switch self {
        case .steps:    return "Verified automatically via HealthKit step count"
        case .workout:  return "Verified automatically when a matching workout is logged"
        case .calories: return "Verified automatically via HealthKit active calories"
        case .sleep:    return "Verified automatically via HealthKit sleep data"
        case .manual:   return "You confirm completion manually by tapping the quest"
        }
    }
}

// MARK: - Impossible Day Banner

/// Collapsible banner shown when one or more quests have targets that exceed
/// physiological daily limits. Warns the player without blocking progress.
struct ImpossibleDayBanner: View {
    let warnings: [ImpossibleDayDetector.ImpossibleWarning]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.subheadline)
                    Text(warnings.count == 1
                         ? "1 quest has an extreme target"
                         : "\(warnings.count) quests have extreme targets")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail rows
            if isExpanded {
                Divider().opacity(0.3)
                ForEach(warnings) { warning in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(warning.questTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(warning.reason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Suggestion: \(warning.suggestion)")
                            .font(.caption2)
                            .foregroundColor(.cyan.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if warning.id != warnings.last?.id {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

enum QuestDifficulty: String, CaseIterable, Identifiable {
    case easy   = "easy"
    case medium = "medium"
    case hard   = "hard"

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }

    /// Base XP for this difficulty.
    var baseXP: Int {
        switch self {
        case .easy:   return 25
        case .medium: return 50
        case .hard:   return 100
        }
    }
}



#Preview {
    QuestsView()
        .modelContainer(for: [Quest.self, Profile.self], inMemory: true)
}

struct RealWorldDataSummary: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [Profile]
    private var profile: Profile { profiles.first ?? Profile() }
    @State private var showSleepLog = false
    @State private var sleepHoursInput: Double = 7.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REAL-WORLD DATA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                Spacer()
                Text("+\(xpToday)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                miniMetric(title: "Steps", value: "\(profile.dailySteps)", goal: profile.dailyStepsGoal, icon: "figure.walk", color: .blue)
                miniMetric(title: "Active Cal", value: "\(profile.dailyActiveCalories)", goal: profile.dailyActiveCaloriesGoal, icon: "flame.fill", color: .orange)
                Button { showSleepLog = true } label: {
                    miniMetric(title: "Sleep", value: "\(Int(profile.sleepHours))h", goal: 8, icon: "bed.double.fill", color: .purple)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.green.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .sheet(isPresented: $showSleepLog) {
            SleepLogSheet(hours: $sleepHoursInput) { hours in
                DataManager.shared.recordHealthAction(.recordSleep(hours: hours))
            }
        }
    }

    private var xpToday: Int {
        // simple heuristic: award XP based on steps and calories ratios
        let stepsXP = Int(Double(profile.dailySteps) / Double(max(1, profile.dailyStepsGoal)) * 30)
        let calXP = Int(Double(profile.dailyActiveCalories) / Double(max(1, profile.dailyActiveCaloriesGoal)) * 20)
        let sleepXP = Int(min(1.0, profile.sleepHours / 8.0) * 10)
        return max(0, stepsXP + calXP + sleepXP)
    }

    @ViewBuilder
    private func miniMetric(title: String, value: String, goal: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.8))
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .tint(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func progress(for title: String) -> Double {
        switch title {
        case "Steps":
            return min(1.0, Double(profile.dailySteps) / Double(max(1, profile.dailyStepsGoal)))
        case "Active Cal":
            return min(1.0, Double(profile.dailyActiveCalories) / Double(max(1, profile.dailyActiveCaloriesGoal)))
        case "Sleep":
            return min(1.0, profile.sleepHours / 8.0)
        default:
            return 0
        }
    }
}
