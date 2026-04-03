import SwiftUI
import SwiftData

// MARK: - Exercise Card

struct ExerciseCard: View {
    let exercise: Exercise
    let typeColor: Color
    var onAdd: ((Exercise) -> Void)? = nil
    @State private var showingDetail = false
    @State private var justAdded = false

    var body: some View {
        HStack(spacing: 0) {
            // Add button on the left
            if let onAdd {
                Button(action: {
                    onAdd(exercise)
                    withAnimation(.spring(response: 0.3)) { justAdded = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { justAdded = false }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(justAdded ? Color.green.opacity(0.18) : typeColor.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: justAdded ? "checkmark" : "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(justAdded ? .green : typeColor)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, 4)
            }

            // Main tappable area -> detail sheet
            Button(action: { showingDetail = true }) {
                HStack(spacing: 14) {
                    // Only show icon when no add button
                    if onAdd == nil {
                        ZStack {
                            Circle()
                                .fill(typeColor.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: exercise.muscleIcon)
                                .font(.system(size: 20))
                                .foregroundColor(typeColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let muscle = exercise.muscle {
                                Tag(text: muscle.capitalized, color: .blue)
                            }
                            if let difficulty = exercise.difficulty {
                                Tag(text: difficulty.capitalized, color: exercise.difficultyColor)
                            }
                            if let eq = exercise.equipment {
                                Tag(text: eq.capitalized, color: .gray)
                            }
                        }

                        if let instructions = exercise.instructions, !instructions.isEmpty {
                            Text(instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .padding(.leading, onAdd != nil ? 0 : 0)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(justAdded ? Color.green.opacity(0.4) : typeColor.opacity(0.15), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingDetail) {
            ExerciseDetailView(exercise: exercise, accentColor: typeColor, onAdd: onAdd)
        }
    }
}

// MARK: - Exercise Detail View

struct ExerciseDetailView: View {
    let exercise: Exercise
    let accentColor: Color
    var onAdd: ((Exercise) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var justAdded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero header
                    heroSection

                    VStack(spacing: 20) {
                        // Muscle groups
                        muscleSection

                        // Step-by-step instructions
                        if !exercise.instructionSteps.isEmpty {
                            instructionsSection
                        }

                        // Tips card
                        tipsSection

                        // YouTube demo link
                        videoDemoSection
                    }
                    .padding()
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onAdd {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            onAdd(exercise)
                            withAnimation(.spring(response: 0.3)) { justAdded = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                        }) {
                            Label(
                                justAdded ? "Added!" : "Add to Workout",
                                systemImage: justAdded ? "checkmark.circle.fill" : "plus.circle.fill"
                            )
                            .foregroundColor(justAdded ? .green : accentColor)
                            .fontWeight(.semibold)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [accentColor.opacity(0.3), accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                // Hero image from Supabase Storage, or fallback SF Symbol
                if let imageURL = exercise.previewImageUrl {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 24)
                        case .failure, .empty:
                            fallbackIcon
                        @unknown default:
                            fallbackIcon
                        }
                    }
                    .padding(.top, 20)
                } else {
                    fallbackIcon
                        .padding(.top, 28)
                }

                // Tags row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let cat = exercise.category ?? exercise.type
                        if let cat {
                            DetailBadge(text: cat.capitalized, icon: "figure.strengthtraining.traditional", color: accentColor)
                        }
                        let lvl = exercise.level ?? exercise.difficulty
                        if let lvl {
                            DetailBadge(text: lvl.capitalized, icon: difficultyIcon, color: exercise.difficultyColor)
                        }
                        if let eq = exercise.equipment {
                            DetailBadge(text: eq.capitalized, icon: equipmentIcon(eq), color: .secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 90, height: 90)
            Image(systemName: exercise.muscleIcon)
                .font(.system(size: 42))
                .foregroundColor(accentColor)
        }
    }

    // MARK: Muscles

    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "MUSCLES WORKED", icon: "figure.arms.open")

            // Use full arrays when available, fall back to single-value legacy fields
            let primaries   = exercise.primaryMuscles.isEmpty
                              ? (exercise.muscle.map { [$0] } ?? [])
                              : exercise.primaryMuscles
            let secondaries = exercise.secondaryMuscles.isEmpty
                              ? (exercise.secondaryMuscle.map { [$0] } ?? [])
                              : exercise.secondaryMuscles

            VStack(alignment: .leading, spacing: 8) {
                if !primaries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(primaries, id: \.self) { muscle in
                                MuscleGroupCard(label: "Primary", muscle: muscle.capitalized, color: accentColor)
                            }
                        }
                    }
                }
                if !secondaries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(secondaries, id: \.self) { muscle in
                                MuscleGroupCard(label: "Secondary", muscle: muscle.capitalized, color: .secondary)
                            }
                        }
                    }
                }
            }

            // Mechanic + force chips
            if exercise.mechanic != nil || exercise.force != nil {
                HStack(spacing: 8) {
                    if let mechanic = exercise.mechanic {
                        Tag(text: mechanic.capitalized, color: .purple)
                    }
                    if let force = exercise.force {
                        Tag(text: force.capitalized, color: .teal)
                    }
                }
            }
        }
    }

    // MARK: Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "HOW TO PERFORM", icon: "list.number")

            VStack(spacing: 10) {
                ForEach(Array(exercise.instructionSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        // Step number bubble
                        ZStack {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text(step)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                }
            }
        }
    }

    // MARK: Tips

    private var tipsSection: some View {
        // Prefer the DB-supplied tips paragraph; fall back to generated tips
        let tipsList: [String] = {
            if let dbTips = exercise.tips, !dbTips.isEmpty {
                return [dbTips]
            }
            return proTips(for: exercise)
        }()

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "PRO TIPS", icon: "lightbulb.fill")

            VStack(spacing: 8) {
                ForEach(tipsList, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(accentColor)
                            .font(.system(size: 16))
                        Text(tip)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accentColor.opacity(0.06))
                    )
                }
            }
        }
    }

    // MARK: Video Demo

    private var videoDemoSection: some View {
        // Prefer server-generated URL, fall back to client-side construction
        let ytURL: URL? = exercise.youtubeURL ?? {
            guard let encoded = exercise.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return URL(string: "https://www.youtube.com/results?search_query=\(encoded)+proper+form+tutorial")
        }()

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "VIDEO DEMONSTRATION", icon: "play.rectangle.fill")

            if let url = ytURL {
                Link(destination: url) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.red)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Watch \(exercise.name) Tutorial")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Opens YouTube — proper form & technique")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 30)
    }

    // MARK: - Helpers

    private var difficultyIcon: String {
        switch exercise.difficulty?.lowercased() {
        case "beginner":     return "1.circle"
        case "intermediate": return "2.circle"
        case "expert":       return "3.circle"
        default:             return "star"
        }
    }

    private func equipmentIcon(_ eq: String) -> String {
        switch eq.lowercased() {
        case "barbell":               return "dumbbell.fill"
        case "dumbbell", "dumbbells": return "dumbbell"
        case "machine":               return "gear"
        case "cable":                 return "cable.coaxial"
        case "bodyweight", "none":    return "figure.strengthtraining.functional"
        case "bands", "resistance band": return "waveform.path"
        case "kettlebell":            return "circle.hexagongrid"
        default:                      return "wrench.and.screwdriver"
        }
    }

    /// Returns a handful of generic form-cue tips based on exercise type/muscle.
    private func proTips(for exercise: Exercise) -> [String] {
        var tips: [String] = []

        switch exercise.muscle?.lowercased() {
        case "chest":
            tips = ["Keep your shoulder blades retracted and depressed throughout the movement.",
                    "Control the eccentric (lowering) phase for 2-3 seconds.",
                    "Don't flare your elbows past 45° to protect your rotator cuff."]
        case "back", "lats", "traps":
            tips = ["Initiate every pull by depressing your shoulder blades first.",
                    "Think about pulling your elbows to your hips, not your hands to your chest.",
                    "Avoid shrugging your shoulders at the top of the movement."]
        case "shoulders", "deltoids":
            tips = ["Keep your core braced to prevent lower-back arch.",
                    "Stop just short of lockout at the top to maintain tension.",
                    "Use a full range of motion — don't cut the movement short."]
        case "biceps", "triceps", "forearms":
            tips = ["Keep your upper arms stationary — isolation is key.",
                    "Fully extend at the bottom to stretch the muscle under load.",
                    "Squeeze hard at peak contraction for a count of one."]
        case "legs", "quadriceps", "hamstrings", "glutes":
            tips = ["Keep your chest up and knees tracking over your toes.",
                    "Drive through your heels to engage the posterior chain.",
                    "Break parallel on every rep for full glute activation."]
        case "abdominals", "abs", "core":
            tips = ["Exhale sharply at peak contraction to maximally recruit the abs.",
                    "Never pull on your neck — keep your chin slightly tucked.",
                    "Slow down the eccentric phase to increase time under tension."]
        default:
            tips = ["Warm up the target joints before adding heavy load.",
                    "Focus on mind-muscle connection — feel the target muscle working.",
                    "Log your reps and weight each session to track progressive overload."]
        }

        switch exercise.type?.lowercased() {
        case "cardio":
            tips = ["Maintain conversational pace for aerobic base work.",
                    "Keep your heart rate in Zone 2 (60-70% max HR) for fat adaptation.",
                    "Finish with 5 minutes of easy movement to bring HR down gradually."]
        case "stretching":
            tips = ["Never stretch a cold muscle — do a light warm-up first.",
                    "Hold each stretch for at least 30 seconds to see lasting change.",
                    "Breathe into the stretch; don't hold your breath."]
        default:
            break
        }

        return tips
    }
}

// MARK: - Supporting sub-views for ExerciseDetailView

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

private struct DetailBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
        )
    }
}

private struct MuscleGroupCard: View {
    let label: String
    let muscle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(muscle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Logged Exercise Entry

/// A single exercise logged during a workout session.
struct LoggedExerciseEntry: Identifiable {
    var id = UUID()
    var name: String = ""
    // Strength fields
    var sets: Int = 3
    var reps: Int = 10
    var weightKg: Double = 0.0
    // Superset / circuit
    var isSuperset: Bool = false
    var supersetGroupID: String = ""   // exercises sharing the same ID are paired
    // Cardio / timed fields
    var minutes: Int = 10
    var distanceKm: Double = 0.0
    var paceMinPerKm: Double = 0.0     // 0 = not tracked
    var heartRateZone: Int = 0         // 1-5, 0 = not tracked

    /// Total lifted volume for this entry (kg). Zero for non-strength exercises.
    var volume: Double { weightKg * Double(sets) * Double(reps) }
}

// MARK: - Workout Logger View

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var dataManager = DataManager.shared
    @Query private var personalRecords: [PersonalRecord]
    @Query private var profiles: [Profile]
    let workoutType: WorkoutType
    @Binding var duration: Int
    /// Optional exercises pre-populated from a program's day plan
    var preloadedExercises: [LoggedExerciseEntry] = []
    /// Optional routine name override (e.g. from a plan day)
    var routineName: String = ""

    init(workoutType: WorkoutType, duration: Binding<Int>, preloadedExercises: [LoggedExerciseEntry] = [], routineName: String = "") {
        self.workoutType = workoutType
        self._duration = duration
        self.preloadedExercises = preloadedExercises
        self.routineName = routineName
        // Seed exercises at init time so they're ready before onAppear fires,
        // avoiding a SwiftUI sheet timing bug where preloadedExercises arrives stale.
        self._exercises = State(initialValue: preloadedExercises)
    }

    private var useMetric: Bool { profiles.first?.useMetric ?? true }

    /// Convert a kg value to display string respecting unit preference
    private func weightDisplay(_ kg: Double) -> String {
        if useMetric {
            return kg == 0 ? "BW" : String(format: "%.1f kg", kg)
        } else {
            let lbs = kg * 2.20462
            return kg == 0 ? "BW" : String(format: "%.0f lbs", lbs)
        }
    }

    /// Convert a kg volume total to display string
    private func volumeDisplay(_ kg: Double) -> String {
        if useMetric {
            return String(format: "%.0f kg", kg)
        } else {
            return String(format: "%.0f lbs", kg * 2.20462)
        }
    }

    @State private var exercises: [LoggedExerciseEntry] = []
    @State private var notes = ""
    // Rest timer state
    @State private var restTimerActive = false
    @State private var restSecondsRemaining: Int = 90
    @State private var restTimerDuration: Int = 90
    @State private var restTimer: Timer? = nil
    // Template state
    @State private var showingSaveTemplate = false
    @State private var showingLoadTemplate = false

    /// Whether exercises are timed (cardio/flex) or sets×reps (strength/mixed).
    private var isTimed: Bool {
        workoutType == .cardio || workoutType == .flexibility
    }

    private var totalDuration: Int {
        if isTimed {
            let total = exercises.reduce(0) { $0 + $1.minutes }
            return max(duration, total)
        }
        return duration
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Header ──────────────────────────────────────────────────
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: workoutType.filledIcon)
                            .font(.title2)
                            .foregroundColor(workoutType.uiColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workoutType.displayName + " Workout")
                                .font(.headline)
                            Text(isTimed ? "Log exercises by time" : "Log sets, reps & weight")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if !isTimed {
                        // Overall duration for strength — can override
                        Stepper("Total Duration: \(duration) min", value: $duration, in: 5...180, step: 5)
                    }
                }

                // ── Exercise Log ─────────────────────────────────────────────
                if !exercises.isEmpty {
                    Section(isTimed ? "Exercises Performed" : "Sets Logged") {
                        ForEach($exercises) { $entry in
                            if isTimed {
                                TimedExerciseRow(entry: $entry, accentColor: workoutType.uiColor)
                            } else {
                                let pr = personalRecords.first {
                                    !entry.name.isEmpty &&
                                    $0.exerciseName.localizedCaseInsensitiveContains(entry.name)
                                }
                                StrengthExerciseRow(entry: $entry, accentColor: workoutType.uiColor, lastPR: pr, useMetric: useMetric)
                            }
                        }
                        .onDelete { exercises.remove(atOffsets: $0) }
                    }
                }

                // ── Add Exercise ─────────────────────────────────────────────
                Section {
                    Button {
                        withAnimation { exercises.append(LoggedExerciseEntry()) }
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .foregroundColor(workoutType.uiColor)
                    }
                }

                // ── Summary ──────────────────────────────────────────────────
                if !exercises.isEmpty {
                    Section("Session Summary") {
                        if !isTimed {
                            let totalVolume = exercises.reduce(0.0) { $0 + $1.volume }
                            if totalVolume > 0 {
                                LabeledContent("Total Volume") {
                                    Text(volumeDisplay(totalVolume))
                                        .fontWeight(.semibold)
                                        .foregroundColor(workoutType.uiColor)
                                }
                            }
                            LabeledContent("Exercises") {
                                Text("\(exercises.count)")
                                    .fontWeight(.semibold)
                            }
                        } else {
                            LabeledContent("Total Time") {
                                Text("\(exercises.reduce(0) { $0 + $1.minutes }) min")
                                    .fontWeight(.semibold)
                                    .foregroundColor(workoutType.uiColor)
                            }
                        }
                    }
                }

                // ── Notes ────────────────────────────────────────────────────
                Section("Notes (Optional)") {
                    TextField("How did it feel? Any PRs?", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                // ── Complete ─────────────────────────────────────────────────
                Section {
                    Button(action: logWorkout) {
                        HStack {
                            Spacer()
                            Label("Complete Workout", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(workoutType.uiColor)
                }
            }
            .navigationTitle(routineName.isEmpty ? "Log Workout" : routineName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if exercises.isEmpty && !preloadedExercises.isEmpty {
                    exercises = preloadedExercises
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Load template button
                    Button {
                        showingLoadTemplate = true
                    } label: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .foregroundColor(.secondary)

                    // Save as template button (only when exercises are present)
                    if !exercises.isEmpty {
                        Button {
                            showingSaveTemplate = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                        }
                        .foregroundColor(workoutType.uiColor)
                    }

                    // Rest timer button (strength/mixed only)
                    if !isTimed {
                        Button {
                            startRestTimer(seconds: restTimerDuration)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: restTimerActive ? "timer.circle.fill" : "timer")
                                Text(restTimerActive ? formatRestTime(restSecondsRemaining) : "Rest")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(restTimerActive ? .orange : .secondary)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if restTimerActive {
                    RestTimerBanner(
                        secondsRemaining: restSecondsRemaining,
                        totalSeconds: restTimerDuration,
                        onDurationChange: { newDur in
                            restTimerDuration = newDur
                            restSecondsRemaining = min(restSecondsRemaining, newDur)
                        },
                        onCancel: { stopRestTimer() }
                    )
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4), value: restTimerActive)
            .sheet(isPresented: $showingSaveTemplate) {
                SaveTemplateSheet(workoutType: workoutType, exercises: exercises) { templateName in
                    saveTemplate(name: templateName)
                }
            }
            .sheet(isPresented: $showingLoadTemplate) {
                WorkoutTemplatePicker(workoutType: workoutType) { loaded in
                    exercises = loaded
                }
            }
        }
    }

    // MARK: - Template helpers

    /// Encode exercises to JSON and save as an ActiveRoutine.
    private func saveTemplate(name: String) {
        let exerciseData = exercises.map { ["name": $0.name, "sets": "\($0.sets)", "reps": "\($0.reps)", "weightKg": "\($0.weightKg)", "minutes": "\($0.minutes)"] }
        guard let json = try? JSONSerialization.data(withJSONObject: exerciseData),
              let jsonString = String(data: json, encoding: .utf8) else { return }
        let routine = ActiveRoutine(name: name, notes: jsonString, gymEnvironment: .fullGym)
        context.insert(routine)
        context.safeSave()
    }

    private func startRestTimer(seconds: Int) {
        stopRestTimer()
        restSecondsRemaining = seconds
        restTimerActive = true
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if restSecondsRemaining > 0 {
                    restSecondsRemaining -= 1
                } else {
                    stopRestTimer()
                    // Haptic feedback when done
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restTimerActive = false
    }

    private func formatRestTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func logWorkout() {
        let effectiveDuration = isTimed
            ? exercises.reduce(0) { $0 + $1.minutes }
            : duration
        let resolvedDuration = max(5, effectiveDuration)
        let workoutStart = Date().addingTimeInterval(-Double(resolvedDuration) * 60)

        // ── 1. Create and persist WorkoutSession ─────────────────────────────
        let sessionName = routineName.isEmpty ? workoutType.displayName + " Workout" : routineName
        let session = WorkoutSession(routineName: sessionName)
        session.startedAt = workoutStart
        session.notes = notes
        // Insert session FIRST so relationship assignments have a persisted parent
        context.insert(session)
        session.sets = []

        // ── 2. Create ExerciseSets and update Personal Records ───────────────
        var globalSetNumber = 1
        for entry in exercises where !entry.name.isEmpty {
            if isTimed {
                // Cardio/flexibility: one record per exercise with duration in minutes
                let s = ExerciseSet(
                    exerciseName: entry.name,
                    exerciseWgerID: 0,
                    setNumber: globalSetNumber,
                    weightKg: entry.distanceKm > 0 ? entry.distanceKm : 0,
                    reps: entry.minutes
                )
                s.paceMinPerKm = entry.paceMinPerKm
                s.heartRateZone = entry.heartRateZone
                // Insert BEFORE assigning session relationship
                context.insert(s)
                session.sets?.append(s)
                globalSetNumber += 1
            } else {
                // Strength: one ExerciseSet per actual set (not aggregated)
                let perSetReps = entry.reps
                let perSetWeight = entry.weightKg
                for _ in 0..<max(1, entry.sets) {
                    let s = ExerciseSet(
                        exerciseName: entry.name,
                        exerciseWgerID: 0,
                        setNumber: globalSetNumber,
                        weightKg: perSetWeight,
                        reps: perSetReps
                    )
                    s.isSuperset = entry.isSuperset
                    s.supersetGroupID = entry.supersetGroupID
                    // Insert BEFORE assigning session relationship
                    context.insert(s)
                    session.sets?.append(s)
                    globalSetNumber += 1
                }

                // Update personal record using best set (highest Epley 1RM)
                if perSetWeight > 0 && perSetReps > 0 {
                    let epley1RM = perSetWeight * (1.0 + Double(perSetReps) / 30.0)
                    let existingPR = personalRecords.first {
                        $0.exerciseName.localizedCaseInsensitiveCompare(entry.name) == .orderedSame
                    }
                    if let pr = existingPR {
                        if epley1RM > pr.oneRepMaxKg {
                            pr.bestWeightKg = perSetWeight
                            pr.bestReps = perSetReps
                            pr.oneRepMaxKg = epley1RM
                            pr.achievedAt = Date()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } else {
                        let newPR = PersonalRecord(
                            exerciseWgerID: 0,
                            exerciseName: entry.name,
                            weightKg: perSetWeight,
                            reps: perSetReps
                        )
                        context.insert(newPR)
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }
                }
            }
        }

        // ── 3. Finalise session (sets XP, volume, finishedAt) ────────────────
        session.finishedAt = Date()
        session.durationMinutes = resolvedDuration
        let totalVol = exercises.reduce(0.0) { $0 + $1.volume }
        session.totalVolumeKg = totalVol
        session.xpAwarded = min(500, Int(totalVol / 10))

        context.safeSave()

        // Haptic feedback for completing a workout
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // ── 4. Update profile stats and quests ───────────────────────────────
        dataManager.updateProfile { profile in
            profile.recordWorkout(type: workoutType, duration: resolvedDuration)
        }
        dataManager.autoCompleteWorkoutQuests(for: workoutType)

        // ── 5. Write workout to Apple Health in the background ───────────────
        Task {
            await dataManager.healthManager.saveWorkout(
                type: workoutType,
                start: workoutStart,
                durationMinutes: resolvedDuration
            )
        }

        dismiss()
    }
}

// MARK: - Rest Timer Banner

private struct RestTimerBanner: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let onDurationChange: (Int) -> Void
    let onCancel: () -> Void

    private let presets = [30, 60, 90, 120, 180]

    var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        return Double(totalSeconds - secondsRemaining) / Double(totalSeconds)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest Timer")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(secondsRemaining <= 10 ? .red : .orange)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(secondsRemaining <= 10 ? Color.red : Color.orange)
                        .frame(width: geo.size.width * (1 - progress))
                        .animation(.linear(duration: 1), value: secondsRemaining)
                }
            }
            .frame(height: 6)
            // Duration presets
            HStack(spacing: 8) {
                Text("Set:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(presets, id: \.self) { p in
                    Button("\(p)s") {
                        onDurationChange(p)
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(totalSeconds == p ? Color.orange.opacity(0.3) : Color.gray.opacity(0.15)))
                    .foregroundColor(totalSeconds == p ? .orange : .secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 8, y: -2)
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Strength Exercise Row

private struct StrengthExerciseRow: View {
    @Binding var entry: LoggedExerciseEntry
    let accentColor: Color
    var lastPR: PersonalRecord? = nil
    var useMetric: Bool = true

    /// Suggest ~2.5% more than last best weight (progressive overload)
    private var suggestedWeight: Double? {
        guard let pr = lastPR, pr.bestWeightKg > 0 else { return nil }
        return (pr.bestWeightKg * 1.025 / 2.5).rounded() * 2.5
    }

    private func fmt(_ kg: Double) -> String {
        if useMetric { return String(format: "%.1f kg", kg) }
        return String(format: "%.0f lbs", kg * 2.20462)
    }

    private func fmt1RM(_ kg: Double) -> String {
        if useMetric { return String(format: "%.1f kg", kg) }
        return String(format: "%.0f lbs", kg * 2.20462)
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Exercise name (e.g. Bench Press)", text: $entry.name)
                .font(.subheadline.weight(.semibold))

            // Progressive overload hint + 1RM badges
            if let pr = lastPR, let suggested = suggestedWeight {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Last: \(fmt(pr.bestWeightKg)) × \(pr.bestReps)  →  Target: \(fmt(suggested))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    // Stored 1RM badge
                    HStack(spacing: 2) {
                        Text("1RM")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(fmt1RM(pr.oneRepMaxKg))
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.purple)
                    .cornerRadius(5)

                    Button("Use") {
                        entry.weightKg = suggested
                        entry.reps = pr.bestReps
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accentColor)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            }

            // Live estimated 1RM from current input (Epley formula)
            if entry.weightKg > 0 && entry.reps > 0 {
                let liveEpley = entry.weightKg * (1.0 + Double(entry.reps) / 30.0)
                let liveBrzycki = entry.reps < 37 ? entry.weightKg * 36.0 / (37.0 - Double(entry.reps)) : 0
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text("Est. 1RM:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Epley \(fmt1RM(liveEpley))")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.purple)
                    if liveBrzycki > 0 {
                        Text("· Brzycki \(fmt1RM(liveBrzycki))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(6)
            }

            HStack(spacing: 0) {
                // Sets
                VStack(spacing: 2) {
                    Text("SETS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Stepper("\(entry.sets)", value: $entry.sets, in: 1...20)
                        .labelsHidden()
                    Text("\(entry.sets)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44)

                // Reps
                VStack(spacing: 2) {
                    Text("REPS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Stepper("\(entry.reps)", value: $entry.reps, in: 1...100)
                        .labelsHidden()
                    Text("\(entry.reps)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44)

                // Weight — stepper always in kg internally; display label uses preference
                VStack(spacing: 2) {
                    Text(useMetric ? "KG" : "LBS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Stepper("", value: $entry.weightKg, in: 0...500, step: useMetric ? 2.5 : 1.0 / 2.20462)
                        .labelsHidden()
                    // Display in the preferred unit
                    Group {
                        if entry.weightKg == 0 {
                            Text("BW")
                        } else if useMetric {
                            Text(String(format: "%.1f", entry.weightKg))
                        } else {
                            Text(String(format: "%.0f", entry.weightKg * 2.20462))
                        }
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(entry.weightKg == 0 ? .secondary : accentColor)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                if entry.weightKg > 0 {
                    let vol = entry.volume
                    Text("Volume: \(useMetric ? String(format: "%.0f kg", vol) : String(format: "%.0f lbs", vol * 2.20462)) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Superset toggle
                Button {
                    entry.isSuperset.toggle()
                    if entry.isSuperset && entry.supersetGroupID.isEmpty {
                        entry.supersetGroupID = UUID().uuidString
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isSuperset ? "link.circle.fill" : "link.circle")
                            .font(.caption)
                        Text("Superset")
                            .font(.caption)
                    }
                    .foregroundColor(entry.isSuperset ? accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Timed Exercise Row

private struct TimedExerciseRow: View {
    @Binding var entry: LoggedExerciseEntry
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Exercise (e.g. Cycling)", text: $entry.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(entry.minutes) min")
                        .font(.caption)
                        .foregroundColor(accentColor)
                }
                Spacer()
                Stepper("", value: $entry.minutes, in: 1...120, step: 5)
                    .labelsHidden()
                Text("\(entry.minutes)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .frame(width: 36, alignment: .trailing)
            }

            // Cardio extras (collapsible row)
            HStack(spacing: 8) {
                // Distance
                VStack(spacing: 2) {
                    Text("KM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Stepper("", value: $entry.distanceKm, in: 0...100, step: 0.5)
                        .labelsHidden()
                    Text(entry.distanceKm > 0 ? String(format: "%.1f", entry.distanceKm) : "–")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(entry.distanceKm > 0 ? accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Pace
                VStack(spacing: 2) {
                    Text("PACE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Stepper("", value: $entry.paceMinPerKm, in: 0...20, step: 0.1)
                        .labelsHidden()
                    Text(entry.paceMinPerKm > 0 ? String(format: "%.1f'/km", entry.paceMinPerKm) : "–")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(entry.paceMinPerKm > 0 ? accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // HR Zone
                VStack(spacing: 2) {
                    Text("HR ZONE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Picker("", selection: $entry.heartRateZone) {
                        Text("–").tag(0)
                        ForEach(1...5, id: \.self) { z in Text("Z\(z)").tag(z) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Text(entry.heartRateZone > 0 ? "Zone \(entry.heartRateZone)" : "–")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(hrZoneColor(entry.heartRateZone))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func hrZoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }
}

// MARK: - Anime Plan Picker

struct AnimePlanPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Binding var activePlanID: String
    /// The player's biological sex — used to filter anime programs to gender-appropriate ones only.
    let playerGender: PlayerGender
    /// Called when the user confirms a switch — passes the new plan ID (empty = no plan).
    /// Caller is responsible for performing the level-1 reset on the profile.
    var onConfirmSwitch: (String) -> Void

    @Query private var customPlans: [CustomWorkoutPlan]

    @State private var pendingPlanID: String? = nil // nil = no pending confirmation
    @State private var showingCustomBuilder = false

    private var currentPlan: AnimeWorkoutPlan? {
        AnimeWorkoutPlanService.shared.plan(id: activePlanID)
    }

    /// Plans intended for the player's gender (or unisex).
    private var myPlans: [AnimeWorkoutPlan] {
        AnimeWorkoutPlanService.shared.all.filter { plan in
            plan.targetGender == nil || plan.targetGender == playerGender
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    // Lock-in warning banner (shown whenever a plan is active)
                    if !activePlanID.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Plan Lock-In Active")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.orange)
                                Text("Switching or abandoning your program resets you to Level 1.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.orange.opacity(0.08))
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // "No Plan" option
                    Button(action: {
                        if activePlanID.isEmpty {
                            // Already no plan — nothing to do
                            dismiss()
                        } else {
                            pendingPlanID = ""
                        }
                    }) {
                        HStack(spacing: 14) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No Program")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Use the adaptive quest algorithm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if activePlanID.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
                    .buttonStyle(.plain)

                    // Anime Plans section — filtered to gender-appropriate programs
                    sectionHeader(playerGender == .female ? "Female Programs" : "Male Programs")
                    ForEach(myPlans) { plan in
                        AnimePlanCard(plan: plan, isActive: activePlanID == plan.id) {
                            selectPlan(id: plan.id)
                        }
                    }

                    // Custom Plans section
                    sectionHeader("My Custom Programs")
                    if customPlans.isEmpty {
                        Text("No custom programs yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(customPlans) { cp in
                            let plan = cp.asAnimeWorkoutPlan()
                            AnimePlanCard(plan: plan, isActive: activePlanID == cp.id) {
                                selectPlan(id: cp.id)
                            }
                        }
                    }

                    // Create Custom Plan button
                    Button(action: { showingCustomBuilder = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Custom Program")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("AI-guided wizard or manual builder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.indigo.opacity(0.06))
                                .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Choose Program")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomBuilder) {
                CustomPlanBuilderView { newPlan in
                    // Auto-activate the new plan (first-time selection, no reset needed)
                    activePlanID = newPlan.id
                    onConfirmSwitch(newPlan.id)
                }
            }
            .alert("Lock-In Warning", isPresented: Binding(
                get: { pendingPlanID != nil },
                set: { if !$0 { pendingPlanID = nil } }
            )) {
                Button("Cancel", role: .cancel) { pendingPlanID = nil }
                Button("Switch & Reset", role: .destructive) {
                    if let newID = pendingPlanID {
                        onConfirmSwitch(newID)
                        activePlanID = newID
                        pendingPlanID = nil
                        dismiss()
                    }
                }
            } message: {
                let targetName: String = {
                    guard let id = pendingPlanID, !id.isEmpty else { return "no program" }
                    if let plan = AnimeWorkoutPlanService.shared.plan(id: id) {
                        return "the \(plan.character) program"
                    }
                    if let cp = customPlans.first(where: { $0.id == id }) {
                        return "'\(cp.name)'"
                    }
                    return "this program"
                }()
                Text("Switching to \(targetName) will reset your level, XP, and streak back to zero. This cannot be undone. Are you committed?")
            }
        }
    }

    // MARK: Helpers

    private func selectPlan(id: String) {
        if activePlanID == id {
            dismiss()
        } else if activePlanID.isEmpty {
            onConfirmSwitch(id)
            activePlanID = id
            dismiss()
        } else {
            pendingPlanID = id
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct AnimePlanCard: View {
    let plan: AnimeWorkoutPlan
    let isActive: Bool
    let onSelect: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main tappable row
            Button(action: { withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(plan.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: plan.iconSymbol)
                            .font(.title3)
                            .foregroundColor(plan.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(plan.character)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.primary)
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(plan.anime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(plan.tagline)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                        // Gender indicator
                        if let gender = plan.targetGender {
                            Text(gender == .male ? "♂" : "♀")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(gender == .male ? .blue : .pink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((gender == .male ? Color.blue : Color.pink).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text(plan.difficulty.rawValue.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(plan.accentColor.opacity(0.15))
                            .foregroundColor(plan.accentColor)
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    Text(plan.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Weekly schedule summary dots
                    HStack(spacing: 6) {
                        ForEach(Array(plan.weeklySchedule.enumerated()), id: \.offset) { idx, day in
                            VStack(spacing: 3) {
                                Text(["M","T","W","T","F","S","S"][idx])
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                Circle()
                                    .fill(day.isRest ? Color(.systemGray5) : plan.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(plan.nutrition.dailyCalories) kcal/day")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(plan.accentColor)
                            Text("\(plan.nutrition.proteinGrams)g protein")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: onSelect) {
                        Text(isActive ? "Currently Active" : "Start This Program")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(isActive ? .secondary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isActive ? Color(.systemGray5) : plan.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActive)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isActive ? plan.accentColor.opacity(0.15) : Color(.systemGray4).opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Save Template Sheet

private struct SaveTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workoutType: WorkoutType
    let exercises: [LoggedExerciseEntry]
    let onSave: (String) -> Void

    @State private var templateName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Template Name")) {
                    TextField("e.g. Push Day, Leg Day A…", text: $templateName)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Exercises to Save")) {
                    ForEach(exercises) { entry in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(workoutType.uiColor)
                                .font(.caption)
                            Text(entry.name.isEmpty ? "Unnamed Exercise" : entry.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(entry.sets)×\(entry.reps)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = templateName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        onSave(name)
                        dismiss()
                    }
                    .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Workout Template Picker

struct WorkoutTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ActiveRoutine.lastUsedAt, order: .reverse) private var routines: [ActiveRoutine]
    let workoutType: WorkoutType
    let onLoad: ([LoggedExerciseEntry]) -> Void

    @State private var routineToDelete: ActiveRoutine? = nil
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "bookmark",
                        description: Text("Save a workout as a template to reuse it later.")
                    )
                } else {
                    List {
                        ForEach(routines) { routine in
                            Button {
                                loadTemplate(routine)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(routine.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if let lastUsed = routine.lastUsedAt {
                                            Text(lastUsed, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    let entries = decodeExercises(from: routine.notes)
                                    if !entries.isEmpty {
                                        Text(entries.map { $0.name.isEmpty ? "Exercise" : $0.name }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(routine)
                                    context.safeSave()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func loadTemplate(_ routine: ActiveRoutine) {
        let entries = decodeExercises(from: routine.notes)
        routine.lastUsedAt = Date()
        context.safeSave()
        onLoad(entries)
        dismiss()
    }

    /// Decode exercise data from JSON stored in routine.notes
    private func decodeExercises(from json: String) -> [LoggedExerciseEntry] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return array.map { dict in
            var entry = LoggedExerciseEntry()
            entry.name = dict["name"] ?? ""
            entry.sets = Int(dict["sets"] ?? "3") ?? 3
            entry.reps = Int(dict["reps"] ?? "10") ?? 10
            entry.weightKg = Double(dict["weightKg"] ?? "0") ?? 0
            entry.minutes = Int(dict["minutes"] ?? "10") ?? 10
            return entry
        }
    }
}

// MARK: - Weekly Schedule View

struct WeeklyScheduleView: View {
    let plan: AnimeWorkoutPlan
    @Environment(\.dismiss) private var dismiss

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Index of today in the weekly schedule (0 = Monday)
    private var todayIndex: Int {
        let calWeekday = Calendar.current.component(.weekday, from: Date())
        return (calWeekday + 5) % 7
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Plan header
                    ZStack {
                        LinearGradient(
                            colors: [plan.accentColor.opacity(0.25), plan.accentColor.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        VStack(spacing: 8) {
                            Image(systemName: plan.iconSymbol)
                                .font(.system(size: 40))
                                .foregroundColor(plan.accentColor)
                                .padding(.top, 24)
                            Text("\(plan.character) — \(plan.anime)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(plan.tagline)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(Array(plan.weeklySchedule.enumerated()), id: \.offset) { index, dayPlan in
                            DayScheduleCard(
                                dayName: dayNames[index],
                                dayPlan: dayPlan,
                                accentColor: plan.accentColor,
                                isToday: index == todayIndex
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle("7-Day Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DayScheduleCard: View {
    let dayName: String
    let dayPlan: AnimeWorkoutPlan.DayPlan
    let accentColor: Color
    let isToday: Bool

    @State private var isExpanded = false

    private var cardColor: Color { isToday ? accentColor : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Day indicator circle
                    ZStack {
                        Circle()
                            .fill(cardColor.opacity(isToday ? 0.2 : 0.08))
                            .frame(width: 42, height: 42)
                        if dayPlan.isRest {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 16))
                                .foregroundColor(cardColor)
                        } else {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 16))
                                .foregroundColor(cardColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(dayName.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(isToday ? accentColor : .primary)
                            if isToday {
                                Text("TODAY")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(accentColor))
                            }
                        }
                        Text(dayPlan.isRest ? "Rest & Recovery" : dayPlan.focus)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    if !dayPlan.isRest {
                        Text("\(dayPlan.exercises.count) exercises")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded exercise list
            if isExpanded {
                Divider().padding(.horizontal)

                if dayPlan.isRest {
                    HStack(spacing: 10) {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.secondary)
                        Text("Active recovery: stretch, mobility, walk. Let adaptations compound.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(dayPlan.exercises, id: \.name) { ex in
                            HStack(spacing: 12) {
                                Text("•")
                                    .foregroundColor(accentColor)
                                    .font(.system(size: 16, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    HStack(spacing: 6) {
                                        Text("\(ex.sets)×\(ex.reps)")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(accentColor)
                                        if !ex.notes.isEmpty {
                                            Text("· \(ex.notes)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }

                        if !dayPlan.questTitle.isEmpty {
                            Divider()
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.cyan)
                                Text("Quest: \(dayPlan.questTitle)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.cyan)
                                Spacer()
                                Text("+\(dayPlan.xpReward) XP")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isToday ? accentColor.opacity(0.06) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isToday ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        )
        .onAppear {
            // Auto-expand today's card
            if isToday { isExpanded = true }
        }
    }
}

// MARK: - Planned Exercise Detail

struct PlannedExerciseDetail: Identifiable {
    let id = UUID()
    let exercise: AnimeWorkoutPlan.PlannedExercise
    let accentColor: Color
}

struct PlannedExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: PlannedExerciseDetail
    let accentColor: Color

    private var ex: AnimeWorkoutPlan.PlannedExercise { detail.exercise }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ex.name)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)
                        if !ex.notes.isEmpty {
                            Text(ex.notes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Stats chips
                    HStack(spacing: 12) {
                        statChip(icon: "repeat", label: "Sets", value: "\(ex.sets)")
                        statChip(icon: "flame.fill", label: "Reps", value: ex.reps)
                        if ex.restSeconds > 0 {
                            statChip(icon: "timer", label: "Rest", value: "\(ex.restSeconds)s")
                        }
                    }
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // How to perform
                    VStack(alignment: .leading, spacing: 10) {
                        Label("How to Perform", systemImage: "list.number")
                            .font(.headline)
                            .foregroundColor(accentColor)
                            .padding(.horizontal)

                        let steps = exerciseSteps(for: ex.name)
                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(accentColor)
                                    .frame(width: 22, alignment: .center)
                                    .padding(.top, 1)
                                Text(step)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                        }
                    }

                    if ex.restSeconds > 0 {
                        Divider().padding(.horizontal)
                        HStack(spacing: 10) {
                            Image(systemName: "timer")
                                .foregroundColor(.orange)
                            Text("Rest \(ex.restSeconds) seconds between sets to allow proper recovery.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(ex.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statChip(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(accentColor)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    /// Generic step-by-step instructions based on common exercise names.
    private func exerciseSteps(for name: String) -> [String] {
        let lower = name.lowercased()
        if lower.contains("squat") {
            return [
                "Stand with feet shoulder-width apart, toes slightly out.",
                "Brace your core and keep your chest tall.",
                "Lower by pushing your hips back and bending your knees.",
                "Descend until thighs are parallel to the floor (or deeper if mobility allows).",
                "Drive through your heels to return to standing.",
                "Lock out hips and knees fully at the top."
            ]
        } else if lower.contains("deadlift") {
            return [
                "Stand with the bar over your mid-foot, feet hip-width apart.",
                "Hinge at the hips and grip the bar just outside your legs.",
                "Flatten your back, brace your core, and take a deep breath.",
                "Drive your feet into the floor while pulling the bar close to your body.",
                "Lock out hips and knees simultaneously at the top.",
                "Lower the bar under control by hinging at the hips first."
            ]
        } else if lower.contains("bench") || lower.contains("press") && lower.contains("chest") {
            return [
                "Lie on the bench with eyes under the bar, feet flat on the floor.",
                "Grip the bar slightly wider than shoulder-width.",
                "Unrack, position the bar over your lower chest.",
                "Lower to the chest with elbows at roughly 45–75° from your torso.",
                "Press the bar back up to the starting position.",
                "Lock out elbows fully at the top."
            ]
        } else if lower.contains("pull-up") || lower.contains("pullup") || lower.contains("chin-up") {
            return [
                "Hang from the bar with arms fully extended, hands slightly wider than shoulders.",
                "Engage your shoulder blades by pulling them down and back.",
                "Drive your elbows toward your hips as you pull your chest to the bar.",
                "Pause briefly at the top with your chin over the bar.",
                "Lower yourself under control until arms are fully extended."
            ]
        } else if lower.contains("push-up") || lower.contains("pushup") {
            return [
                "Start in a high plank with hands just outside shoulder-width.",
                "Keep your body in a straight line from head to heels.",
                "Lower your chest to just above the floor, elbows at ~45°.",
                "Press back up to full arm extension.",
                "Squeeze your chest and triceps at the top."
            ]
        } else if lower.contains("row") {
            return [
                "Hinge forward at the hips to roughly 45°, keeping your back flat.",
                "Hold the weight with an overhand or underhand grip.",
                "Pull the weight toward your lower chest or navel.",
                "Squeeze your shoulder blades together at the top.",
                "Lower under control until arms are fully extended."
            ]
        } else if lower.contains("run") || lower.contains("jog") {
            return [
                "Warm up with a 5-minute brisk walk.",
                "Maintain an upright posture with a slight forward lean.",
                "Land with your foot under your hips, not out in front.",
                "Keep a steady breathing rhythm — aim for conversational pace.",
                "Cool down with a 5-minute walk and stretch."
            ]
        } else if lower.contains("plank") {
            return [
                "Start in a forearm plank — elbows under shoulders, body flat.",
                "Engage your glutes, quads, and core simultaneously.",
                "Keep your hips level — don't let them sag or pike up.",
                "Breathe steadily throughout the hold.",
                "Stop when form breaks down."
            ]
        } else {
            // Generic fallback
            return [
                "Set up in the correct starting position as described by your trainer or program.",
                "Brace your core and maintain proper posture throughout the movement.",
                "Perform the movement through its full range of motion.",
                "Control the weight on both the way up and the way down.",
                "Complete all prescribed sets and reps before resting."
            ]
        }
    }
}

// MARK: - Workout Session Edit View

struct WorkoutSessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    let session: WorkoutSession
    private var useMetric: Bool { profiles.first?.useMetric ?? true }

    @State private var routineName: String = ""
    @State private var notes: String = ""
    @State private var durationMinutes: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Session Details") {
                    TextField("Workout name", text: $routineName)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 0...600, step: 5)
                }
                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let sets = session.sets, !sets.isEmpty {
                    Section("Sets Logged (\(sets.count))") {
                        ForEach(sets.sorted { $0.setNumber < $1.setNumber }) { set in
                            HStack {
                                Text(set.exerciseName)
                                    .font(.subheadline)
                                Spacer()
                                Text("Set \(set.setNumber)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                if set.weightKg > 0 {
                                    let wt = useMetric
                                        ? String(format: "%.0f kg", set.weightKg)
                                        : String(format: "%.0f lbs", set.weightKg * 2.20462)
                                    Text("\(wt) × \(set.reps)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                routineName = session.routineName
                notes = session.notes
                durationMinutes = session.durationMinutes
            }
        }
    }

    private func saveChanges() {
        session.routineName = routineName
        session.notes = notes
        session.durationMinutes = durationMinutes
        context.safeSave()
        dismiss()
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: [Profile.self], inMemory: true)
}
