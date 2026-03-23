import SwiftUI
import SwiftData

struct QuestsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Quest.createdAt, order: .reverse) private var quests: [Quest]
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedDay = Date()
    @State private var showingCreateQuest = false
    
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
                // Week scroller
                WeekScroller(selectedDay: $selectedDay)
                    .padding(.vertical)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Real-World Data at the top to correlate with quests
                        RealWorldDataSummary()
                        
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
                                
                                Button("Create Quest") {
                                    showingCreateQuest = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 60)
                        } else {
                            // Active missions section
                            if !activeQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("ACTIVE MISSIONS")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.cyan.opacity(0.8))
                                        Spacer()
                                        Text("\(activeQuests.count) remaining")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    ForEach(activeQuests) { quest in
                                        QuestRow(quest: quest) {
                                            toggleQuestCompletion(quest)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Completed missions section  
                            if !completedQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("COMPLETED")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.green.opacity(0.8))
                                        Spacer()
                                        Text("\(completedQuests.count) done")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    
                                    ForEach(completedQuests) { quest in
                                        QuestRow(quest: quest) {
                                            toggleQuestCompletion(quest)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.large)
            .background(colorScheme == .dark ? .black.opacity(0.95) : .white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        showingCreateQuest = true
                    }
                    .foregroundColor(.cyan)
                }
            }
            .sheet(isPresented: $showingCreateQuest) {
                CreateQuestView(selectedDay: selectedDay)
            }
        }
    }
    
    private func toggleQuestCompletion(_ quest: Quest) {
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

struct CreateQuestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    let selectedDay: Date

    // Quest info
    @State private var title = ""
    @State private var details = ""
    @State private var questType: QuestType = .daily

    // Category + difficulty — XP is derived, not typed
    @State private var category: QuestCategory = .workout
    @State private var difficulty: QuestDifficulty = .medium

    // Category-specific targets
    @State private var stepTarget: Int = 10_000
    @State private var calTarget: Int = 400
    @State private var sleepTarget: Double = 8.0
    @State private var workoutType: WorkoutType = .strength  // for workout category

    private let stepOptions  = [5_000, 7_500, 10_000, 12_500, 15_000, 20_000]
    private let calOptions   = [200, 300, 400, 500, 600, 800]
    private let sleepOptions: [Double] = [6, 7, 7.5, 8, 9]

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

                // ── Quest Type (Daily / Weekly / Custom) ────────────────────
                Section("Frequency") {
                    Picker("Quest Type", selection: $questType) {
                        ForEach(QuestType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
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

                // ── Difficulty ──────────────────────────────────────────────
                Section("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(QuestDifficulty.allCases) { d in
                            Text(d.displayName).foregroundColor(d.color).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ── XP Preview (read-only) ───────────────────────────────────
                Section {
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
                    Text("XP is calculated automatically based on category and difficulty. It cannot be set manually.")
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

        let quest = Quest(
            title: trimmedTitle,
            details: details.trimmingCharacters(in: .whitespaces),
            type: questType,
            xpReward: calculatedXP,
            statTarget: category.statTarget,
            completionCondition: completionCondition,
            dateTag: selectedDay
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
