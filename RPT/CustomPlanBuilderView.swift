import SwiftUI
import SwiftData

// MARK: - Entry Point

/// Shown from the plan picker when the user taps "Create Custom Plan".
/// Lets them choose between the AI-guided wizard and the manual builder.
struct CustomPlanBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Called when a plan is saved, so the picker can immediately activate it.
    var onPlanCreated: (CustomWorkoutPlan) -> Void

    @State private var mode: BuilderMode? = nil

    enum BuilderMode { case guided, manual }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.indigo)
                    Text("Build Your Program")
                        .font(.title2.weight(.bold))
                    Text("Create a personalised training plan tailored to your goals.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 32)

                VStack(spacing: 16) {
                    // Guided / AI path
                    ModeCard(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "AI-Guided Wizard",
                        subtitle: "Answer a few questions and Apple Intelligence will build your plan on-device.",
                        badge: AIManager.shared.isAvailable ? "Apple Intelligence" : "Not Available",
                        badgeColor: AIManager.shared.isAvailable ? .purple : .secondary
                    ) {
                        mode = .guided
                    }
                    .disabled(!AIManager.shared.isAvailable)
                    .opacity(AIManager.shared.isAvailable ? 1 : 0.5)

                    // Manual path
                    ModeCard(
                        icon: "pencil.and.list.clipboard",
                        iconColor: .blue,
                        title: "Manual Builder",
                        subtitle: "Design every day yourself — sets, reps, nutrition targets, the works.",
                        badge: "Full Control",
                        badgeColor: .blue
                    ) {
                        mode = .manual
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $mode) { m in
                switch m {
                case .guided:
                    GuidedPlanWizard(onPlanCreated: { plan in
                        onPlanCreated(plan)
                        dismiss()
                    })
                case .manual:
                    ManualPlanBuilderView(onPlanCreated: { plan in
                        onPlanCreated(plan)
                        dismiss()
                    })
                }
            }
        }
    }
}

extension CustomPlanBuilderView.BuilderMode: Identifiable {
    var id: Int { self == .guided ? 0 : 1 }
}

// MARK: - Mode Selection Card

private struct ModeCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.12))
                            .foregroundColor(badgeColor)
                            .clipShape(Capsule())
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guided Wizard (AI path)

struct GuidedPlanWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var onPlanCreated: (CustomWorkoutPlan) -> Void

    // Questionnaire state
    @State private var goal: String = ""
    @State private var experience: String = ""
    @State private var daysPerWeek: String = "4"
    @State private var sessionLength: String = "60"
    @State private var equipment: String = ""
    @State private var limitations: String = ""
    @State private var bodyWeight: String = ""
    @State private var targetWeight: String = ""

    @State private var currentStep = 0
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    private let steps = ["Goal", "Experience", "Schedule", "Details"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step progress
                stepProgressBar

                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case 0: goalStep
                        case 1: experienceStep
                        case 2: scheduleStep
                        case 3: detailsStep
                        default: EmptyView()
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }

                // Bottom nav
                bottomNavigation
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Wizard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isGenerating {
                    generatingOverlay
                }
            }
            .alert("Generation Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Steps

    private var goalStep: some View {
        WizardSection(title: "What's your primary goal?", icon: "target") {
            VStack(spacing: 10) {
                ForEach(["Lose body fat", "Build muscle mass", "Improve endurance",
                         "Increase strength", "General fitness & health",
                         "Athletic performance"], id: \.self) { option in
                    SelectionPill(label: option, isSelected: goal == option) {
                        goal = option
                    }
                }
            }
        }
    }

    private var experienceStep: some View {
        WizardSection(title: "Training experience level?", icon: "chart.bar.fill") {
            VStack(spacing: 10) {
                ForEach([
                    ("Beginner", "Less than 6 months"),
                    ("Intermediate", "6 months – 2 years"),
                    ("Advanced", "2–5 years"),
                    ("Elite", "5+ years / competitive")
                ], id: \.0) { level, desc in
                    SelectionPill(label: "\(level) — \(desc)", isSelected: experience == level) {
                        experience = level
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        WizardSection(title: "Training schedule", icon: "calendar") {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Days per week: \(daysPerWeek)")
                        .font(.subheadline.weight(.medium))
                    Slider(value: Binding(
                        get: { Double(daysPerWeek) ?? 4 },
                        set: { daysPerWeek = "\(Int($0))" }
                    ), in: 2...7, step: 1)
                    .tint(.indigo)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session length: \(sessionLength) min")
                        .font(.subheadline.weight(.medium))
                    Slider(value: Binding(
                        get: { Double(sessionLength) ?? 60 },
                        set: { sessionLength = "\(Int($0))" }
                    ), in: 20...120, step: 10)
                    .tint(.indigo)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Available equipment")
                        .font(.subheadline.weight(.medium))
                    ForEach(["Full gym", "Home gym (dumbbells + pull-up bar)",
                             "Bodyweight only", "Resistance bands"], id: \.self) { option in
                        SelectionPill(label: option, isSelected: equipment == option) {
                            equipment = option
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
        }
    }

    private var detailsStep: some View {
        WizardSection(title: "A few final details", icon: "person.fill") {
            VStack(spacing: 16) {
                LabelledField(label: "Current body weight (kg)", text: $bodyWeight,
                              placeholder: "e.g. 80", keyboard: .decimalPad)
                LabelledField(label: "Target weight (kg, optional)", text: $targetWeight,
                              placeholder: "e.g. 75", keyboard: .decimalPad)
                LabelledField(label: "Injuries or limitations (optional)",
                              text: $limitations, placeholder: "e.g. bad knees, shoulder impingement")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        }
    }

    // MARK: Progress Bar

    private var stepProgressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? Color.indigo : Color(.systemGray5))
                    .frame(height: 4)
                    .animation(.spring(duration: 0.3), value: currentStep)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: Bottom Nav

    private var bottomNavigation: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if currentStep > 0 {
                    Button("Back") { withAnimation { currentStep -= 1 } }
                        .foregroundColor(.secondary)
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Next") { withAnimation { currentStep += 1 } }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(!canAdvance)
                } else {
                    Button("Generate My Plan") { generatePlan() }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(!canAdvance)
                }
            }
            .padding()
        }
        .background(.regularMaterial)
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !goal.isEmpty
        case 1: return !experience.isEmpty
        case 2: return !equipment.isEmpty
        case 3: return !bodyWeight.isEmpty
        default: return true
        }
    }

    // MARK: Generating Overlay

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("THE SYSTEM IS ANALYSING...")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("Apple Intelligence is building your program on-device.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        }
    }

    // MARK: Generation

    private func generatePlan() {
        isGenerating = true
        let answers: [String: String] = [
            "goal": goal,
            "experience": experience,
            "daysPerWeek": daysPerWeek,
            "sessionLengthMinutes": sessionLength,
            "equipment": equipment,
            "injuries_or_limitations": limitations.isEmpty ? "none" : limitations,
            "bodyWeightKg": bodyWeight,
            "targetWeightKg": targetWeight.isEmpty ? "not specified" : targetWeight
        ]

        Task {
            do {
                let suggestion = try await AIManager.shared.generatePlan(from: answers)
                let plan = buildPlan(from: suggestion, answers: answers)
                await MainActor.run {
                    context.insert(plan)
                    context.safeSave()
                    isGenerating = false
                    onPlanCreated(plan)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func buildPlan(from s: AIPlanSuggestion, answers: [String: String]) -> CustomWorkoutPlan {
        let plan = CustomWorkoutPlan(name: s.name, description: s.description)
        plan.difficultyRaw = s.difficulty
        plan.isAIGenerated = true
        plan.aiPromptSummary = "Goal: \(goal) · \(experience) · \(daysPerWeek)d/wk · \(equipment)"

        // Build 7-day schedule from focus labels
        let focuses = [s.mondayFocus, s.tuesdayFocus, s.wednesdayFocus,
                       s.thursdayFocus, s.fridayFocus, s.saturdayFocus, s.sundayFocus]
        let dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
        plan.weeklySchedule = zip(dayNames, focuses).map { name, focus in
            let isRest = focus.lowercased().contains("rest")
            if isRest {
                return CustomDayPlan.restDay(name: name)
            }
            return CustomDayPlan(
                dayName: name,
                focus: focus,
                isRest: false,
                exercises: defaultExercises(for: focus),
                questTitle: "\(focus) Session",
                questDetails: "Complete today's \(focus.lowercased()) session. Focus, execute, log.",
                xpReward: 150
            )
        }

        plan.nutrition = CustomPlanNutrition(
            dailyCalories: s.dailyCalories,
            proteinGrams: s.proteinGrams,
            carbGrams: s.carbGrams,
            fatGrams: s.fatGrams,
            waterGlasses: s.waterGlasses,
            mealPrepTips: [s.mealPrepTip1, s.mealPrepTip2, s.mealPrepTip3],
            avoidList: s.avoidFoods.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )
        return plan
    }

    /// Provides a sensible default exercise list for a given focus string.
    private func defaultExercises(for focus: String) -> [CustomPlannedExercise] {
        let f = focus.lowercased()
        if f.contains("push") || f.contains("chest") {
            return [
                CustomPlannedExercise(name: "Bench Press", sets: 4, reps: "8-10", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Overhead Press", sets: 3, reps: "10", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Tricep Dips", sets: 3, reps: "12", restSeconds: 60, notes: "")
            ]
        } else if f.contains("pull") || f.contains("back") {
            return [
                CustomPlannedExercise(name: "Pull-Ups", sets: 4, reps: "Max", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Bent-Over Row", sets: 3, reps: "10", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Face Pulls", sets: 3, reps: "15", restSeconds: 60, notes: "")
            ]
        } else if f.contains("leg") || f.contains("lower") {
            return [
                CustomPlannedExercise(name: "Squat", sets: 4, reps: "8", restSeconds: 120, notes: ""),
                CustomPlannedExercise(name: "Romanian Deadlift", sets: 3, reps: "10", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Leg Press", sets: 3, reps: "12", restSeconds: 90, notes: "")
            ]
        } else if f.contains("cardio") || f.contains("endurance") {
            return [
                CustomPlannedExercise(name: "Run / Bike", sets: 1, reps: "30 min", restSeconds: 0, notes: "Zone 2 pace")
            ]
        } else {
            return [
                CustomPlannedExercise(name: "Deadlift", sets: 4, reps: "6-8", restSeconds: 120, notes: ""),
                CustomPlannedExercise(name: "Pull-Ups", sets: 3, reps: "Max", restSeconds: 90, notes: ""),
                CustomPlannedExercise(name: "Push-Ups", sets: 3, reps: "20", restSeconds: 60, notes: "")
            ]
        }
    }
}

// MARK: - Manual Builder

struct ManualPlanBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var onPlanCreated: (CustomWorkoutPlan) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var difficultyRaw = "Intermediate"
    @State private var accentColorHex = "#5E5CE6"
    @State private var iconSymbol = "figure.strengthtraining.traditional"
    @State private var schedule: [CustomDayPlan] = ManualPlanBuilderView.defaultSchedule()
    @State private var nutrition = CustomPlanNutrition()
    @State private var editingDayIndex: Int? = nil
    @State private var showingIconPicker = false

    private static func defaultSchedule() -> [CustomDayPlan] {
        let names = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
        return names.enumerated().map { i, name in
            i == 6 ? CustomDayPlan.restDay(name: name)
                   : CustomDayPlan(dayName: name, focus: "Training", isRest: false,
                                   exercises: [], questTitle: "\(name) Workout",
                                   questDetails: "Complete today's session.", xpReward: 100)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Plan identity
                Section("Plan Details") {
                    HStack {
                        Button(action: { showingIconPicker = true }) {
                            Image(systemName: iconSymbol)
                                .font(.title2)
                                .foregroundColor(Color(hex: accentColorHex) ?? .indigo)
                                .frame(width: 44, height: 44)
                                .background((Color(hex: accentColorHex) ?? .indigo).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        TextField("Plan name", text: $name)
                            .font(.headline)
                    }
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Difficulty", selection: $difficultyRaw) {
                        ForEach(["Beginner","Intermediate","Advanced","Elite"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    ColorPicker("Accent Color", selection: Binding(
                        get: { Color(hex: accentColorHex) ?? .indigo },
                        set: { accentColorHex = $0.hexString }
                    ))
                }

                // Weekly schedule
                Section("Weekly Schedule") {
                    ForEach(schedule.indices, id: \.self) { i in
                        DayRowView(day: $schedule[i]) {
                            editingDayIndex = i
                        }
                    }
                }

                // Nutrition
                Section("Nutrition Targets") {
                    nutritionFields
                }

                // Meal prep tips
                Section("Meal Prep Tips (optional)") {
                    ForEach(0..<3, id: \.self) { i in
                        let placeholder = ["Prep protein in bulk on Sunday",
                                           "Keep healthy snacks portioned",
                                           "Track macros in the morning"][i]
                        TextField(placeholder, text: Binding(
                            get: { nutrition.mealPrepTips.indices.contains(i) ? nutrition.mealPrepTips[i] : "" },
                            set: { v in
                                var tips = nutrition.mealPrepTips
                                while tips.count <= i { tips.append("") }
                                tips[i] = v
                                nutrition.mealPrepTips = tips.filter { !$0.isEmpty }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Manual Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePlan() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $editingDayIndex) { idx in
                DayEditorView(day: $schedule[idx])
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selected: $iconSymbol)
            }
        }
    }

    @ViewBuilder
    private var nutritionFields: some View {
        NutritionStepper(label: "Daily Calories", value: $nutrition.dailyCalories, step: 50, range: 1000...6000)
        NutritionStepper(label: "Protein (g)", value: $nutrition.proteinGrams, step: 5, range: 50...400)
        NutritionStepper(label: "Carbs (g)", value: $nutrition.carbGrams, step: 5, range: 50...600)
        NutritionStepper(label: "Fat (g)", value: $nutrition.fatGrams, step: 5, range: 20...200)
        NutritionStepper(label: "Water (glasses)", value: $nutrition.waterGlasses, step: 1, range: 4...20)
    }

    private func savePlan() {
        let plan = CustomWorkoutPlan(name: name, description: description)
        plan.difficultyRaw = difficultyRaw
        plan.accentColorHex = accentColorHex
        plan.iconSymbol = iconSymbol
        plan.isAIGenerated = false
        plan.weeklySchedule = schedule
        plan.nutrition = nutrition
        context.insert(plan)
        context.safeSave()
        onPlanCreated(plan)
        dismiss()
    }
}

// MARK: - Day Row (in the Form list)

private struct DayRowView: View {
    @Binding var day: CustomDayPlan
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(day.isRest ? "Rest Day" : "\(day.focus) · \(day.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !day.isRest },
                    set: { day.isRest = !$0 }
                ))
                .labelsHidden()
                .tint(.indigo)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day Editor Sheet

struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var day: CustomDayPlan

    var body: some View {
        NavigationStack {
            Form {
                Section("Day Info") {
                    TextField("Focus (e.g. Push — Chest & Shoulders)", text: $day.focus)
                    Toggle("Rest Day", isOn: $day.isRest)
                        .tint(.indigo)
                    TextField("Quest Title", text: $day.questTitle)
                    TextField("Quest Details", text: $day.questDetails, axis: .vertical)
                        .lineLimit(2...4)
                    NutritionStepper(label: "XP Reward", value: $day.xpReward, step: 25, range: 25...1000)
                }

                if !day.isRest {
                    Section {
                        ForEach(day.exercises.indices, id: \.self) { i in
                            ExerciseEditorRow(exercise: $day.exercises[i])
                        }
                        .onDelete { day.exercises.remove(atOffsets: $0) }
                        .onMove { day.exercises.move(fromOffsets: $0, toOffset: $1) }
                        Button("Add Exercise") {
                            day.exercises.append(CustomPlannedExercise())
                        }
                    } header: {
                        Text("Exercises")
                    }
                }
            }
            .navigationTitle(day.dayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
    }
}

// MARK: - Exercise Editor Row

private struct ExerciseEditorRow: View {
    @Binding var exercise: CustomPlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Exercise name", text: $exercise.name)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                LabelledSmallField(label: "Sets", text: Binding(
                    get: { "\(exercise.sets)" },
                    set: { exercise.sets = Int($0) ?? exercise.sets }
                ))
                LabelledSmallField(label: "Reps", text: $exercise.reps)
                LabelledSmallField(label: "Rest (s)", text: Binding(
                    get: { "\(exercise.restSeconds)" },
                    set: { exercise.restSeconds = Int($0) ?? exercise.restSeconds }
                ))
            }
            TextField("Notes (optional)", text: $exercise.notes)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Icon Picker

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String

    private let icons: [String] = [
        "figure.strengthtraining.traditional",
        "figure.run", "figure.walk", "figure.martial.arts",
        "figure.boxing", "figure.yoga", "figure.cycling",
        "figure.swimming", "figure.hiking", "figure.skiing",
        "dumbbell.fill", "bolt.fill", "flame.fill",
        "heart.fill", "star.fill", "shield.fill",
        "crown.fill", "trophy.fill", "medal.fill",
        "atom", "infinity", "tornado"
    ]

    let columns = [GridItem(.adaptive(minimum: 60))]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Button(action: { selected = icon; dismiss() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected == icon ? Color.indigo : Color(.systemGray6))
                                    .frame(width: 56, height: 56)
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selected == icon ? .white : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Shared Helper Views

struct WizardSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.indigo)
                Text(title)
                    .font(.headline)
            }
            content
        }
    }
}

struct SelectionPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.indigo : Color(.systemBackground))
                    .stroke(isSelected ? Color.indigo : Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LabelledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
        }
    }
}

private struct LabelledSmallField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray6)))
                .frame(width: 60)
        }
    }
}

struct NutritionStepper: View {
    let label: String
    @Binding var value: Int
    let step: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper("\(label): \(value)", value: $value, in: range, step: step)
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
