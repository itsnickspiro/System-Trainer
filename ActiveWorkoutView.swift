import SwiftUI
import SwiftData
import ActivityKit

// MARK: - ActiveWorkoutView
//
// Hevy replacement — an interactive live logging view driven by an ActiveRoutine.
// Each exercise in the routine gets a card with:
//   • An AsyncImage header fetching the wger exercise GIF/image
//   • Interactive set rows: weight TextField, reps TextField, complete toggle
//
// On "Complete Quest", the view calculates total volume, finalises the
// WorkoutSession in SwiftData, awards XP, and dismisses.

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]

    let routine: ActiveRoutine
    let session: WorkoutSession

    // Local mutable state for each exercise's sets
    @State private var setStates: [Int: [WorkoutEditableSet]] = [:]
    @State private var showCompletionBanner = false
    @State private var isCompleting = false
    @State private var elapsedSeconds = 0
    @State private var showResumeAlert = false
    @State private var pendingAutosave: WorkoutAutosaveState? = nil

    private var profile: Profile? { profiles.first }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        // ── Session timer header ────────────────────────────
                        ActiveSessionHeader(
                            routineName: routine.name,
                            elapsed: elapsedSeconds
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // ── Exercise cards ─────────────────────────────────
                        ForEach(routine.exerciseWgerIDs, id: \.self) { wgerID in
                            ActiveExerciseCard(
                                wgerID: wgerID,
                                sets: Binding(
                                    get: { setStates[wgerID] ?? [] },
                                    set: { setStates[wgerID] = $0 }
                                )
                            )
                            .padding(.horizontal, 16)
                        }

                        Spacer().frame(height: 120)
                    }
                }
                .background(Color.black.ignoresSafeArea())

                // ── Complete Quest button ───────────────────────────────
                VStack(spacing: 0) {
                    if showCompletionBanner {
                        WorkoutCompleteBanner()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Button(action: completeQuest) {
                        HStack(spacing: 10) {
                            if isCompleting {
                                ProgressView().tint(.black).scaleEffect(0.85)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title3)
                            }
                            Text(isCompleting ? "SEALING SESSION..." : "COMPLETE QUEST")
                                .font(.system(.headline, design: .monospaced).weight(.black))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            Capsule().fill(completedSetsCount > 0 ? Color.cyan : Color.gray.opacity(0.4))
                        )
                    }
                    .disabled(isCompleting || completedSetsCount == 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0), .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
            }
            .navigationTitle("ACTIVE QUEST")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abandon") {
                        WorkoutAutosaveManager.shared.clearSave()
                        WorkoutActivityManager.shared.end(totalVolumeKg: 0, xpAwarded: 0)
                        dismiss()
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: buildInitialSets)
        .alert("Resume Workout?", isPresented: $showResumeAlert, presenting: pendingAutosave) { save in
            Button("Resume") { restoreAutosave(save) }
            Button("Start Fresh", role: .destructive) {
                WorkoutAutosaveManager.shared.clearSave()
                pendingAutosave = nil
            }
        } message: { save in
            let elapsed = save.elapsedSeconds / 60
            let completed = save.sets.values.flatMap { $0 }.filter(\.isComplete).count
            Text("Found a session from \(elapsed) min ago with \(completed) sets logged. Continue where you left off?")
        }
        .onChange(of: completedSetsCount) { _, newCount in
            // Update Live Activity when a set is marked complete
            let totalSets = setStates.values.flatMap { $0 }.count
            let currentExercise = currentExerciseName
            WorkoutActivityManager.shared.update(
                currentExercise: currentExercise,
                setsCompleted: newCount,
                totalSets: max(1, totalSets),
                totalVolumeKg: currentTotalVolume
            )
        }
        .task {
            // Elapsed timer + autosave — pure async loop
            var secondsSinceLastSave = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
                secondsSinceLastSave += 1
                // Autosave every 30 seconds
                if secondsSinceLastSave >= 30 {
                    secondsSinceLastSave = 0
                    WorkoutAutosaveManager.shared.save(
                        routineName: routine.name,
                        elapsedSeconds: elapsedSeconds,
                        setStates: setStates
                    )
                }
            }
        }
    }

    // MARK: - Computed

    private var completedSetsCount: Int {
        setStates.values.flatMap { $0 }.filter(\.isComplete).count
    }

    /// The exercise currently being logged (first incomplete exercise, or last if all done).
    private var currentExerciseName: String {
        for wgerID in routine.exerciseWgerIDs {
            guard let sets = setStates[wgerID] else { continue }
            if sets.contains(where: { !$0.isComplete }) {
                return sets.first?.exerciseName.isEmpty == false
                    ? (sets.first?.exerciseName ?? "Exercise")
                    : "Exercise \(wgerID)"
            }
        }
        return routine.name
    }

    private var currentTotalVolume: Double {
        setStates.values.flatMap { $0 }
            .filter(\.isComplete)
            .reduce(0) { $0 + $1.weightKgValue * Double($1.repsValue) }
    }

    // MARK: - Setup

    private func buildInitialSets() {
        // Check for an autosave first
        if let saved = WorkoutAutosaveManager.shared.loadSave(for: routine.name) {
            pendingAutosave = saved
            showResumeAlert = true
        }

        // Build default sets (may be overridden by restoreAutosave)
        for wgerID in routine.exerciseWgerIDs {
            guard setStates[wgerID] == nil else { continue }
            setStates[wgerID] = (1...3).map { WorkoutEditableSet(setNumber: $0, wgerID: wgerID) }
        }

        // Start Live Activity now that we know the total sets
        let totalSets = routine.exerciseWgerIDs.count * 3
        WorkoutActivityManager.shared.start(
            routineName: routine.name,
            totalSets: totalSets
        )
    }

    private func restoreAutosave(_ save: WorkoutAutosaveState) {
        let restored = WorkoutAutosaveManager.shared.restoreSetStates(from: save)
        // Merge: use restored sets where available, fallback to defaults
        for wgerID in routine.exerciseWgerIDs {
            if let restoredSets = restored[wgerID], !restoredSets.isEmpty {
                setStates[wgerID] = restoredSets
            }
        }
        elapsedSeconds = save.elapsedSeconds
        WorkoutAutosaveManager.shared.clearSave()
        pendingAutosave = nil
    }

    // MARK: - Complete Quest

    private func completeQuest() {
        isCompleting = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        for wgerID in routine.exerciseWgerIDs {
            guard let sets = setStates[wgerID] else { continue }
            for editSet in sets where editSet.isComplete {
                let record = ExerciseSet(
                    exerciseName: editSet.exerciseName,
                    exerciseWgerID: wgerID,
                    setNumber: editSet.setNumber,
                    weightKg: editSet.weightKgValue,
                    reps: editSet.repsValue,
                    isWarmUp: false,
                    rpe: 7.0
                )
                context.insert(record)
                if session.sets == nil { session.sets = [] }
                session.sets?.append(record)
            }
        }

        session.finish()
        context.insert(session)

        if let profile {
            let doubleXPMultiplier = profile.hasDoubleXP ? 2 : 1
            DataManager.shared.addXPToProfile(session.xpAwarded * doubleXPMultiplier, source: "Workout")
            profile.lastWorkoutTime = Date()
        }

        context.safeSave()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Clear autosave since the workout is finished
        WorkoutAutosaveManager.shared.clearSave()

        // Sync workout to Supabase activity log
        let completedSets = setStates.values.flatMap { $0 }.filter { $0.isComplete }
        let exerciseCount = setStates.keys.count
        let workoutsToday = UserDefaults.standard.integer(forKey: "rpt_workouts_today") + 1
        UserDefaults.standard.set(workoutsToday, forKey: "rpt_workouts_today")
        Task {
            await ActivitySyncService.shared.logWorkout(
                type: "strength",
                durationMinutes: session.durationMinutes,
                exercisesCount: exerciseCount,
                setsCount: completedSets.count,
                volumeKg: session.totalVolumeKg
            )
            await ActivitySyncService.shared.logStreakDay(
                activityTypes: ["workout"],
                questCount: UserDefaults.standard.integer(forKey: "rpt_quests_today"),
                workoutCount: workoutsToday,
                steps: DataManager.shared.currentProfile?.dailySteps ?? 0
            )
            await LeaderboardService.shared.upsertEntry()
        }

        // End the Live Activity
        WorkoutActivityManager.shared.end(
            totalVolumeKg: session.totalVolumeKg,
            xpAwarded: session.xpAwarded
        )

        withAnimation(.spring(duration: 0.4)) {
            showCompletionBanner = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            dismiss()
        }
    }
}

// MARK: - WorkoutEditableSet (local value-type view model)
// A class so it can be mutated through the Binding<[WorkoutEditableSet]> array.
// Uses @Observable to avoid Combine.

@Observable
final class WorkoutEditableSet: Identifiable {
    let id = UUID()
    let setNumber: Int
    let wgerID: Int
    var exerciseName: String = ""
    var weightText: String = ""
    var repsText: String = ""
    var isComplete: Bool = false

    init(setNumber: Int, wgerID: Int) {
        self.setNumber = setNumber
        self.wgerID = wgerID
    }

    var weightKgValue: Double { Double(weightText) ?? 0 }
    var repsValue: Int { Int(repsText) ?? 0 }
    var hasData: Bool { !weightText.isEmpty && !repsText.isEmpty }
}

// MARK: - ActiveSessionHeader

private struct ActiveSessionHeader: View {
    let routineName: String
    let elapsed: Int

    private var timeString: String {
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("QUEST IN PROGRESS")
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(.cyan)
                Text(routineName)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("ELAPSED")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.gray)
                Text(timeString)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - ActiveExerciseCard

private struct ActiveExerciseCard: View {
    let wgerID: Int
    @Binding var sets: [WorkoutEditableSet]

    @State private var exerciseName: String = ""
    @State private var imageURL: URL?
    @State private var isFetchingMeta = true

    private var wgerImageAPIURL: URL? {
        URL(string: "https://wger.de/api/v2/exerciseimage/?format=json&exercise_base=\(wgerID)")
    }
    private var wgerExerciseInfoURL: URL? {
        URL(string: "https://wger.de/api/v2/exerciseinfo/\(wgerID)/?format=json")
    }

    var body: some View {
        VStack(spacing: 0) {
            exerciseHeader

            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                // Column headers
                HStack {
                    Text("SET").frame(width: 32, alignment: .center)
                    Spacer()
                    Text("KG").frame(width: 72, alignment: .center)
                    Text("REPS").frame(width: 60, alignment: .center)
                    Text("✓").frame(width: 40, alignment: .center)
                }
                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(sets) { editSet in
                    ActiveSetRow(editSet: editSet)
                    if editSet.id != sets.last?.id {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }

                // Add set
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        sets.append(WorkoutEditableSet(setNumber: sets.count + 1, wgerID: wgerID))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.caption)
                        Text("ADD SET")
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    }
                    .foregroundStyle(.cyan.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .task { await fetchExerciseMeta() }
    }

    // ── Exercise image header ──────────────────────────────────────────────

    @ViewBuilder
    private var exerciseHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        decryptingPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.8)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            )
                    case .failure:
                        decryptingPlaceholder
                    @unknown default:
                        decryptingPlaceholder
                    }
                }
            } else {
                decryptingPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName.isEmpty ? "Exercise #\(wgerID)" : exerciseName)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                Text("wger #\(wgerID)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(height: (imageURL != nil && !isFetchingMeta) ? 160 : 80)
        .clipped()
    }

    private var decryptingPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            VStack(spacing: 4) {
                if isFetchingMeta {
                    ProgressView().tint(.cyan)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(.cyan.opacity(0.4))
                }
                Text("Decrypting Combat Data...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.gray)
            }
        }
    }

    // MARK: - wger API fetch

    private func fetchExerciseMeta() async {
        defer { isFetchingMeta = false }

        // Fetch exercise name from exerciseinfo endpoint
        if let infoURL = wgerExerciseInfoURL,
           let (data, _) = try? await URLSession.shared.data(from: infoURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let translations = json["translations"] as? [[String: Any]],
           let english = translations.first(where: { ($0["language"] as? Int) == 2 }),
           let name = english["name"] as? String,
           !name.isEmpty {
            exerciseName = name
        }

        // Fetch first available image
        if let imgListURL = wgerImageAPIURL,
           let (data, _) = try? await URLSession.shared.data(from: imgListURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let first = results.first,
           let imageStr = first["image"] as? String,
           let url = URL(string: imageStr) {
            imageURL = url
        }
    }
}

// MARK: - ActiveSetRow

private struct ActiveSetRow: View {
    @Bindable var editSet: WorkoutEditableSet
    @FocusState private var focusedField: RowField?

    enum RowField { case weight, reps }

    var body: some View {
        HStack(spacing: 8) {
            // Set number badge
            ZStack {
                Circle()
                    .fill(editSet.isComplete ? Color.cyan.opacity(0.2) : Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                Text("\(editSet.setNumber)")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(editSet.isComplete ? .cyan : .gray)
            }

            Spacer()

            // Weight field
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(editSet.isComplete ? 0.03 : 0.07))
                    .frame(width: 72, height: 38)
                TextField("0.0", text: $editSet.weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(editSet.isComplete ? Color.gray : Color.white)
                    .frame(width: 64)
                    .focused($focusedField, equals: .weight)
                    .disabled(editSet.isComplete)
            }

            // Reps field
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(editSet.isComplete ? 0.03 : 0.07))
                    .frame(width: 56, height: 38)
                TextField("0", text: $editSet.repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(editSet.isComplete ? Color.gray : Color.white)
                    .frame(width: 48)
                    .focused($focusedField, equals: .reps)
                    .disabled(editSet.isComplete)
            }

            // Complete toggle
            Button {
                guard editSet.hasData || editSet.isComplete else { return }
                withAnimation(.spring(duration: 0.25)) {
                    editSet.isComplete.toggle()
                }
                if editSet.isComplete {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    focusedField = nil
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(editSet.isComplete ? Color.cyan : Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: editSet.isComplete ? "checkmark" : "circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(editSet.isComplete ? Color.black : Color.gray)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(editSet.isComplete ? Color.cyan.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: editSet.isComplete)
    }
}

// MARK: - WorkoutCompleteBanner

private struct WorkoutCompleteBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.cyan)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Notice: Quest Complete.")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                Text("Volume logged. XP awarded. Directive: Rest.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1)
                )
        )
    }
}
