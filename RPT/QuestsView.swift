import SwiftUI
import SwiftData

struct QuestsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Quest.createdAt, order: .reverse) private var quests: [Quest]
    @ObservedObject private var dataManager = DataManager.shared
    @State private var selectedDay = Date()
    @State private var showingCreateQuest = false
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
                    } else {
                        Button("Add", systemImage: "plus") {
                            showingCreateQuest = true
                        }
                        .foregroundColor(.cyan)
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
                        
                        if activeQuests.isEmpty && completedQuests.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "target")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cyan.opacity(0.5))
                                
                                Text("No missions for this day")
                                    .font(.title3.bold())
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("Create your first quest to get started!")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                if !isDayLocked {
                                    Button("Create Quest") {
                                        showingCreateQuest = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 60)
                        } else {
                            // Active missions section
                            if !activeQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("ACTIVE MISSIONS")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.cyan.opacity(0.8))
                                        Spacer()
                                        Text("\(activeQuests.count) remaining")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal)
                                    
                                    List {
                                        ForEach(activeQuests) { quest in
                                            QuestRow(quest: quest, onToggle: {
                                                toggleQuestCompletion(quest)
                                            }, isLocked: isDayLocked)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                if !isDayLocked && quest.isUserCreated {
                                                    Button(role: .destructive) {
                                                        dataManager.deleteUserCreatedQuest(quest)
                                                    } label: {
                                                        Label("Delete Quest", systemImage: "trash.fill")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .listStyle(.plain)
                                    .scrollDisabled(true)
                                    .frame(height: CGFloat(activeQuests.count) * 140)
                                }
                            }

                            // Completed missions section
                            if !completedQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("COMPLETED")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.green.opacity(0.8))
                                        Spacer()
                                        Text("\(completedQuests.count) done")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal)

                                    List {
                                        ForEach(completedQuests) { quest in
                                            QuestRow(quest: quest, onToggle: {
                                                toggleQuestCompletion(quest)
                                            }, isLocked: isDayLocked)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                if !isDayLocked && quest.isUserCreated {
                                                    Button(role: .destructive) {
                                                        dataManager.deleteUserCreatedQuest(quest)
                                                    } label: {
                                                        Label("Delete Quest", systemImage: "trash.fill")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .listStyle(.plain)
                                    .scrollDisabled(true)
                                    .frame(height: CGFloat(completedQuests.count) * 140)
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
            .sheet(isPresented: $showingCreateQuest) {
                CreateQuestView(selectedDay: selectedDay)
            }
        }
    }
    
    private func toggleQuestCompletion(_ quest: Quest) {
        // Only allow toggling on today — prevents retroactive XP farming
        guard !isDayLocked else { return }
        if quest.isCompleted {
            // Un-complete: refund XP so the player doesn't keep what they didn't earn
            dataManager.uncompleteQuest(quest)
        } else {
            // Complete via DataManager so XP is awarded
            dataManager.completeQuest(quest)
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

    /// Base XP for this difficulty. Scaled by category weight in CreateQuestView.
    var baseXP: Int {
        switch self {
        case .easy:   return 25
        case .medium: return 50
        case .hard:   return 100
        }
    }
}

// MARK: - Create Quest View

private enum CustomPreset: CaseIterable {
    case weekdays, weekends, biweekly

    var label: String {
        switch self {
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .biweekly: return "Biweekly"
        }
    }

    // iOS weekday integers: 1=Sun, 2=Mon … 7=Sat
    var repeatDays: [Int] {
        switch self {
        case .weekdays: return [2, 3, 4, 5, 6]         // Mon–Fri
        case .weekends: return [1, 7]                   // Sun + Sat
        case .biweekly: return [2, 5]                   // Mon + Thu (twice a week)
        }
    }
}

struct CreateQuestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    let selectedDay: Date

    // Quest info
    @State private var title = ""
    @State private var details = ""
    @State private var questType: QuestType = .oneTime
    @State private var customPreset: CustomPreset = .weekdays
    // Multi-day selection for weekly quests: weekday integers (1=Sun, 2=Mon, ... 7=Sat)
    @State private var selectedWeekdays: Set<Int> = []

    // Category — difficulty is auto-assigned from target value
    @State private var category: QuestCategory = .workout

    // Category-specific targets
    @State private var stepTarget: Int = 10_000
    @State private var calTarget: Int = 400
    @State private var sleepTarget: Double = 8.0
    @State private var workoutType: WorkoutType = .strength  // for workout category

    private let stepOptions  = [5_000, 7_500, 10_000, 12_500, 15_000, 20_000]
    private let calOptions   = [200, 300, 400, 500, 600, 800]
    private let sleepOptions: [Double] = [6, 7, 7.5, 8, 9]

    /// Auto-assigned difficulty based on category and target — no manual override.
    private var difficulty: QuestDifficulty {
        switch category {
        case .steps:
            if stepTarget < 7_500  { return .easy }
            if stepTarget <= 12_500 { return .medium }
            return .hard
        case .calories:
            if calTarget < 300  { return .easy }
            if calTarget <= 500 { return .medium }
            return .hard
        case .sleep:
            if sleepTarget < 7.0 { return .easy }
            if sleepTarget <= 8.0 { return .medium }
            return .hard
        case .workout:
            return .medium
        case .manual:
            return .medium
        }
    }

    // XP is calculated from category + difficulty — user cannot set it
    private var calculatedXP: Int {
        let base = difficulty.baseXP
        switch category {
        case .steps:    return Int(Double(base) * (Double(stepTarget) / 10_000.0)).clamped(to: 15...200)
        case .calories: return Int(Double(base) * (Double(calTarget) / 400.0)).clamped(to: 15...200)
        case .sleep:    return Int(Double(base) * (sleepTarget / 8.0)).clamped(to: 15...150)
        case .workout:  return base               // workout difficulty maps 1:1
        case .manual:   return base               // manual quests use flat difficulty XP
        }
    }

    private var completionCondition: String {
        switch category {
        case .steps:    return "steps:\(stepTarget)"
        case .calories: return "calories:\(calTarget)"
        case .sleep:    return "sleep:\(sleepTarget)"
        case .workout:  return "workout:\(workoutType.rawValue)"
        case .manual:   return "manual"
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Quest Info ──────────────────────────────────────────────
                Section("Quest Info") {
                    TextField("Title (e.g. Morning Run)", text: $title)
                    TextField("Details / Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...5)
                }

                // ── Quest Type ───────────────────────────────────────────────
                Section("Frequency") {
                    Picker("Frequency", selection: $questType) {
                        ForEach(QuestType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    if questType == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repeat schedule")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(CustomPreset.allCases, id: \.label) { preset in
                                    Button {
                                        customPreset = preset
                                    } label: {
                                        Text(preset.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(customPreset == preset ? Color.cyan : Color(.systemGray5))
                                            )
                                            .foregroundColor(customPreset == preset ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if questType == .weekly {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repeat on days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                ForEach([(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")], id: \.0) { num, label in
                                    let selected = selectedWeekdays.contains(num)
                                    Button {
                                        if selected { selectedWeekdays.remove(num) }
                                        else { selectedWeekdays.insert(num) }
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .frame(width: 34, height: 34)
                                            .background(
                                                Circle()
                                                    .fill(selected ? Color.cyan : Color(.systemGray5))
                                            )
                                            .foregroundColor(selected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Category ────────────────────────────────────────────────
                Section {
                    ForEach(QuestCategory.allCases) { cat in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { category = cat }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: cat.icon)
                                    .foregroundColor(category == cat ? .cyan : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.displayName)
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .font(.body)
                                    Text(cat.verificationNote)
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                Spacer()
                                if category == cat {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Category & Verification")
                } footer: {
                    Text("The selected category determines how completion is verified — no manual cheating.")
                        .font(.caption)
                }

                // ── Category-specific target ────────────────────────────────
                if category != .manual {
                    Section("Target") {
                        switch category {
                        case .steps:
                            Picker("Step Goal", selection: $stepTarget) {
                                ForEach(stepOptions, id: \.self) { n in
                                    Text(n.formatted()).tag(n)
                                }
                            }
                        case .calories:
                            Picker("Active Calories", selection: $calTarget) {
                                ForEach(calOptions, id: \.self) { n in
                                    Text("\(n) kcal").tag(n)
                                }
                            }
                        case .sleep:
                            Picker("Hours of Sleep", selection: $sleepTarget) {
                                ForEach(sleepOptions, id: \.self) { h in
                                    Text(String(format: "%.1fh", h)).tag(h)
                                }
                            }
                        case .workout:
                            Picker("Workout Type", selection: $workoutType) {
                                ForEach(WorkoutType.allCases) { type in
                                    Label(type.displayName, systemImage: type.icon).tag(type)
                                }
                            }
                        case .manual:
                            EmptyView()
                        }
                    }
                }

                // ── XP Preview (read-only) ───────────────────────────────────
                Section {
                    HStack {
                        Label("Difficulty", systemImage: "chart.bar.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(difficulty.displayName)
                            .foregroundColor(difficulty.color)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Label("Stat Boost", systemImage: "bolt.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(category.statTarget.capitalized)
                            .foregroundColor(.cyan)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Label("XP Reward", systemImage: "star.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("+\(calculatedXP) XP")
                            .foregroundColor(.yellow)
                            .fontWeight(.bold)
                    }
                    HStack {
                        Label("Verified By", systemImage: "lock.shield.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(category == .manual ? "Manual tap" : "HealthKit")
                            .foregroundColor(category == .manual ? .orange : .green)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                } header: {
                    Text("Reward Preview")
                } footer: {
                    Text("Difficulty is auto-assigned based on your target. XP scales with difficulty and cannot be set manually.")
                        .font(.caption)
                }

                // ── Create button ────────────────────────────────────────────
                Section {
                    Button(action: createQuest) {
                        HStack {
                            Spacer()
                            Label("Add Quest", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(isValid ? Color.cyan : Color.gray)
                    .disabled(!isValid)
                }
            }
            .navigationTitle("New Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createQuest() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let tag = Calendar.current.startOfDay(for: selectedDay)

        let (saveType, days): (QuestType, [Int]) = {
            switch questType {
            case .custom:  return (.weekly, customPreset.repeatDays)
            case .weekly:  return (.weekly, Array(selectedWeekdays).sorted())
            default:       return (questType, [])
            }
        }()

        let quest = Quest(
            title: trimmedTitle,
            details: details.trimmingCharacters(in: .whitespaces),
            type: saveType,
            repeatDays: days,
            xpReward: calculatedXP,
            isUserCreated: true,
            statTarget: category.statTarget,
            completionCondition: completionCondition,
            dateTag: tag
        )
        context.insert(quest)
        dismiss()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
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
                miniMetric(title: "Sleep", value: String(format: "%.1fh", profile.sleepHours), goal: 8, icon: "bed.double.fill", color: .purple)
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
