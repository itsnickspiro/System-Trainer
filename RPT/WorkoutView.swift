import SwiftUI
import SwiftData

// MARK: - WorkoutType view extensions (top-level WorkoutType from Models.swift)
extension WorkoutType {
    /// SF Symbol icon with fill variant for workout type cards
    var filledIcon: String {
        switch self {
        case .strength:   return "dumbbell.fill"
        case .cardio:     return "heart.circle.fill"
        case .flexibility: return "figure.yoga"
        case .mixed:      return "figure.mixed.cardio"
        }
    }

    /// Accent color used in the Training tab UI
    var uiColor: Color {
        switch self {
        case .strength:   return .orange
        case .cardio:     return .red
        case .flexibility: return .purple
        case .mixed:      return .cyan
        }
    }

    /// API query string for the exercises endpoint
    var apiType: String {
        switch self {
        case .strength:   return "strength"
        case .cardio:     return "cardio"
        case .flexibility: return "stretching"
        case .mixed:      return ""
        }
    }
}

/// Data bundle passed to the plan workout sheet via `.sheet(item:)`.
/// Using an Identifiable item forces SwiftUI to create a fresh view each presentation.
struct PlanSessionData: Identifiable {
    let id = UUID()
    let routineName: String
    let exercises: [LoggedExerciseEntry]
}

struct WorkoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var planService = AnimeWorkoutPlanService.shared
    @Query private var profiles: [Profile]
    @State private var selectedWorkoutType: WorkoutType = .strength
    @State private var searchQuery = ""
    @State private var exercises: [Exercise] = []
    @State private var isSearching = false
    @State private var searchError: String? = nil
    @State private var showingWorkoutLogger = false
    @State private var workoutDuration = 30 // minutes
    @State private var showingPlanPicker = false
    @State private var showingProgress = false
    @State private var showingWeeklySchedule = false
    @State private var selectedDay = Date()
    @State private var sessionToEdit: WorkoutSession? = nil
    @State private var selectedPlannedExercise: PlannedExerciseDetail? = nil
    @State private var planSession: PlanSessionData? = nil
    @State private var planLoggerDuration = 45
    /// Exercises queued from the database to add to a new workout
    @State private var pendingExercises: [LoggedExerciseEntry] = []
    @State private var showingDatabaseLogger = false
    /// Debounce task so we don't fire a network call on every keystroke
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var isProgramExpanded = false
    @State private var showingDatePicker = false

    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    private var profile: Profile? { profiles.first }
    private var useMetric: Bool { profile?.useMetric ?? true }

    /// Format a kg weight value per user preference
    private func weightDisplay(_ kg: Double) -> String {
        useMetric ? String(format: "%.0f kg", kg) : String(format: "%.0f lbs", kg * 2.20462)
    }

    /// True when the selected day is not today — sessions are view-only
    private var isDayLocked: Bool {
        !Calendar.current.isDateInToday(selectedDay)
    }

    /// Sessions that started on the selected day
    private var sessionsForSelectedDay: [WorkoutSession] {
        allSessions.filter {
            Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDay)
        }
    }

    /// The plan day index for the selected day (0 = Monday)
    private var planDayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: selectedDay)
        return (weekday + 5) % 7
    }

    private var activePlan: AnimeWorkoutPlan? {
        guard let id = profile?.activePlanID, !id.isEmpty else { return nil }
        return AnimeWorkoutPlanService.shared.plan(id: id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned header: title row + week day selector
                VStack(spacing: 0) {
                    HStack {
                        Text("Training")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            showingProgress = true
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Date selector — same style as Ration Log
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        Button {
                            showingDatePicker = true
                        } label: {
                            VStack(spacing: 2) {
                                Text(Calendar.current.isDateInToday(selectedDay) ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.primary)
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(isDayLocked
                                         ? (Calendar.current.isDateInFuture(selectedDay) ? "Future" : "Past")
                                         : "Tap to jump")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.black : Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)

                ScrollView {
                    VStack(spacing: 20) {
                        let isPastDay = isDayLocked && !Calendar.current.isDateInFuture(selectedDay)

                        if isPastDay {
                            // Past date: show what they actually logged
                            sessionsSection
                        } else {
                            // Today or future: show active plan card
                            activeProgramSection

                            if activePlan == nil && !Calendar.current.isDateInFuture(selectedDay) {
                                quickStartSection
                            }

                            // Today only: also show logged sessions below the plan
                            if !isDayLocked {
                                sessionsSection
                            }

                            // Exercise search (browse exercises / add on to plan)
                            exerciseSearchSection

                            // Exercise Results
                            if isSearching {
                                ProgressView("Loading exercises...")
                                    .padding(.vertical, 40)
                            } else if let error = searchError {
                                exerciseErrorView(message: error)
                            } else if exercises.isEmpty {
                                exerciseEmptyState
                            } else {
                                exerciseResults
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .onAppear {
                if exercises.isEmpty {
                    searchExercises(type: selectedWorkoutType.apiType)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker("Jump to Date", selection: $selectedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Jump to Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingDatePicker = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingProgress) {
                ProgressChartsView()
            }
            .sheet(isPresented: $showingWorkoutLogger) {
                WorkoutLoggerView(
                    workoutType: selectedWorkoutType,
                    duration: $workoutDuration
                )
            }
            .sheet(isPresented: $showingPlanPicker) {
                AnimePlanPickerView(
                    activePlanID: Binding(
                        get: { profile?.activePlanID ?? "" },
                        set: { newID in
                            profile?.activePlanID = newID
                            context.safeSave()
                        }
                    ),
                    playerGender: profile?.gender ?? .male,
                    onConfirmSwitch: { newID in
                        guard let p = profile else { return }
                        // Lock-in penalty: reset progress but preserve all-time best streak
                        p.xp = 0
                        p.level = 1
                        p.currentStreak = 0
                        // bestStreak is intentionally preserved — it's a historical record
                        p.lastCompletionDate = nil
                        p.activePlanID = newID
                        context.safeSave()
                    }
                )
            }
            .onAppear {
                // Auto-load exercises for the selected workout type on first open
                if exercises.isEmpty && !isSearching {
                    searchExercises(type: selectedWorkoutType.apiType)
                }
            }
            .onChange(of: selectedWorkoutType) { _, newType in
                // Reload exercises when the user switches workout type
                searchQuery = ""
                searchExercises(type: newType.apiType)
            }
            .sheet(isPresented: $showingWeeklySchedule) {
                if let plan = activePlan {
                    WeeklyScheduleView(plan: plan)
                }
            }
            .sheet(item: $sessionToEdit) { session in
                WorkoutSessionEditView(session: session)
            }
            .sheet(item: $selectedPlannedExercise) { detail in
                PlannedExerciseDetailSheet(detail: detail, accentColor: detail.accentColor)
            }
            .sheet(isPresented: $showingDatabaseLogger, onDismiss: { pendingExercises = [] }) {
                WorkoutLoggerView(
                    workoutType: selectedWorkoutType,
                    duration: $workoutDuration,
                    preloadedExercises: pendingExercises,
                    routineName: ""
                )
            }
            .sheet(item: $planSession) { session in
                WorkoutLoggerView(
                    workoutType: .strength,
                    duration: $planLoggerDuration,
                    preloadedExercises: session.exercises,
                    routineName: session.routineName
                )
            }
        }
    }

    // MARK: - Active Program Section

    @ViewBuilder
    private var activeProgramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVE PROGRAM")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if activePlan == nil {
                    Button("Choose Plan") {
                        showingPlanPicker = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                }
            }

            if let plan = activePlan {
                if isProgramExpanded {
                    activePlanCard(plan: plan)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    activePlanCardCollapsed(plan: plan)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                // Empty state — prompt to pick a plan
                Button(action: { showingPlanPicker = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.martial.arts")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Program Active")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("Follow an anime character's training regimen")
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
                            .fill(Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Compact single-row card shown when the program section is collapsed.
    private func activePlanCardCollapsed(plan: AnimeWorkoutPlan) -> some View {
        let dayPlan = plan.weeklySchedule[planDayIndex]
        let dayLabel = Calendar.current.isDateInToday(selectedDay)
            ? "Today"
            : selectedDay.formatted(.dateTime.weekday(.wide))

        return HStack(spacing: 0) {
            // Left zone: tap anywhere here to expand the card
            Button {
                withAnimation(.spring(duration: 0.3)) { isProgramExpanded = true }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: plan.iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(plan.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.character)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(dayPlan.isRest ? "\(dayLabel): Rest Day" : "\(dayLabel): \(dayPlan.focus)")
                            .font(.caption)
                            .foregroundColor(dayPlan.isRest ? .secondary : plan.accentColor)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Start Session button on collapsed card (non-rest, today only)
            if !dayPlan.isRest && !isDayLocked {
                Button(action: { startSessionForDay(plan: plan, dayPlan: dayPlan) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Start")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(plan.accentColor))
                }
                .buttonStyle(.plain)
            }

            // Expand chevron
            Button {
                withAnimation(.spring(duration: 0.3)) { isProgramExpanded = true }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(plan.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func activePlanCard(plan: AnimeWorkoutPlan) -> some View {
        // Use selected day so the card tracks the week scroller
        let dayPlan = plan.weeklySchedule[planDayIndex]
        let dayLabel = Calendar.current.isDateInToday(selectedDay)
            ? "TODAY"
            : selectedDay.formatted(.dateTime.weekday(.wide)).uppercased()

        return VStack(alignment: .leading, spacing: 12) {
            // Header: icon, name, tagline, difficulty — tap to collapse
            HStack(spacing: 10) {
                Image(systemName: plan.iconSymbol)
                    .font(.title2)
                    .foregroundColor(plan.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(plan.character) — \(plan.anime)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text(plan.tagline)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(plan.difficulty.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(plan.accentColor.opacity(0.15))
                    .foregroundColor(plan.accentColor)
                    .clipShape(Capsule())
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) { isProgramExpanded = false }
            }

            Divider()

            // Day + focus label
            HStack {
                Text("\(dayLabel) — \(dayPlan.focus.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(dayPlan.isRest ? .secondary : plan.accentColor)
                Spacer()
                if dayPlan.isRest {
                    Label("Rest Day", systemImage: "moon.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if dayPlan.isRest {
                Text("Active recovery: stretch, mobility, walk. Let the adaptations compound.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Exercise list — tap row for details, play icon to start individually
                VStack(spacing: 0) {
                    ForEach(Array(dayPlan.exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(plan.accentColor)
                                .frame(width: 20, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(isDayLocked ? .secondary : .primary)
                                HStack(spacing: 6) {
                                    Text("\(ex.sets) sets × \(ex.reps)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if ex.restSeconds > 0 {
                                        Text("· \(ex.restSeconds)s rest")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Tap to view exercise details
                            Button {
                                selectedPlannedExercise = PlannedExerciseDetail(
                                    exercise: ex, accentColor: plan.accentColor
                                )
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(plan.accentColor.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPlannedExercise = PlannedExerciseDetail(
                                exercise: ex, accentColor: plan.accentColor
                            )
                        }

                        if idx < dayPlan.exercises.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.5))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isDayLocked {
                    Label(
                        Calendar.current.isDateInFuture(selectedDay)
                            ? "Future day — unlocks when it arrives"
                            : "Past day — read-only. Log workouts on today's date to earn XP.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }

            Divider()

            HStack(spacing: 10) {
                if !dayPlan.isRest && !isDayLocked {
                    Button(action: { startSessionForDay(plan: plan, dayPlan: dayPlan) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                            Text("Start Session")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(plan.accentColor))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: { showingWeeklySchedule = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13))
                        Text("Schedule")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(plan.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(plan.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func startSessionForDay(plan: AnimeWorkoutPlan, dayPlan: AnimeWorkoutPlan.DayPlan) {
        planLoggerDuration = 45
        let exercises = dayPlan.exercises.map { ex in
            var entry = LoggedExerciseEntry()
            entry.name = ex.name
            entry.sets = ex.sets
            // Parse reps string: "10", "10-12", "Max" → use first number or default to 10
            entry.reps = Int(ex.reps.components(separatedBy: CharacterSet(charactersIn: "-–")).first ?? "10") ?? 10
            return entry
        }
        planSession = PlanSessionData(routineName: dayPlan.focus, exercises: exercises)
    }

    private func workoutTypeChip(_ type: WorkoutType) -> some View {
        let isSelected = selectedWorkoutType == type
        return Button(action: {
            selectedWorkoutType = type
            searchQuery = ""
            searchExercises(type: type.apiType)
        }) {
            HStack(spacing: 6) {
                Image(systemName: type.filledIcon)
                    .font(.system(size: 15, weight: .semibold))
                Text(type.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : type.uiColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? type.uiColor : type.uiColor.opacity(0.12))
                    .overlay(Capsule().stroke(type.uiColor.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK START")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: {
                showingWorkoutLogger = true
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log \(selectedWorkoutType.displayName) Workout")
                            .font(.headline)
                        Text("Track your session and earn XP")
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
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedWorkoutType.uiColor, lineWidth: 2)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sessions for Selected Day

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                let dayLabel = Calendar.current.isDateInToday(selectedDay)
                    ? "TODAY'S SESSIONS"
                    : selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
                Text(dayLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                if isDayLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if sessionsForSelectedDay.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(isDayLocked ? "No sessions logged on this day" : "No sessions yet — start one above!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            } else {
                List {
                    ForEach(sessionsForSelectedDay) { session in
                        sessionRow(session)
                            .listRowBackground(Color(.systemGray6))
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparatorTint(Color.gray.opacity(0.3))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isDayLocked {
                                    Button(role: .destructive) {
                                        deleteSession(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !isDayLocked {
                                    Button {
                                        sessionToEdit = session
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(sessionsForSelectedDay.count) * 70)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.routineName.isEmpty ? "Workout" : session.routineName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Label(session.durationDisplay, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if session.totalVolumeKg > 0 {
                        Label(weightDisplay(session.totalVolumeKg), systemImage: "scalemass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if session.xpAwarded > 0 {
                    Text("+\(session.xpAwarded) XP")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                }
                if !session.isComplete {
                    Text("In Progress")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(height: 70)
    }

    private func deleteSession(_ session: WorkoutSession) {
        context.delete(session)
        context.safeSave()
    }

    // MARK: - Day Plan from Active Program

    private func dayPlanSection(plan: AnimeWorkoutPlan) -> some View {
        let dayPlan = plan.weeklySchedule[planDayIndex]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                let dayLabel = Calendar.current.isDateInToday(selectedDay)
                    ? "TODAY'S PLAN"
                    : "\(selectedDay.formatted(.dateTime.weekday(.wide)).uppercased())'S PLAN"
                Text(dayLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(dayPlan.focus.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(plan.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(plan.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            if dayPlan.isRest {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest Day")
                            .font(.subheadline.weight(.semibold))
                        Text("Active recovery: stretch, walk, and let adaptations compound.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayPlan.exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(plan.accentColor)
                                .frame(width: 20, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(isDayLocked ? .secondary : .primary)
                                HStack(spacing: 6) {
                                    Text("\(ex.sets) sets × \(ex.reps)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if ex.restSeconds > 0 {
                                        Text("· \(ex.restSeconds)s rest")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            // Info button — tap to see exercise details without starting workout
                            Button(action: {
                                selectedPlannedExercise = PlannedExerciseDetail(
                                    exercise: ex,
                                    accentColor: plan.accentColor
                                )
                            }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(plan.accentColor.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            if isDayLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if idx < dayPlan.exercises.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(plan.accentColor.opacity(0.15), lineWidth: 1)
                        )
                )

                if isDayLocked {
                    Label(
                        Calendar.current.isDateInFuture(selectedDay)
                            ? "Future day — this plan unlocks when it arrives"
                            : "Past day — read-only. Log workouts on today's date to earn XP.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var exerciseSearchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXERCISE DATABASE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search exercises...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        searchExercises(query: searchQuery)
                    }
                    .onChange(of: searchQuery) { _, newValue in
                        searchDebounceTask?.cancel()
                        guard !newValue.isEmpty else {
                            exercises = []
                            isSearching = false
                            return
                        }
                        searchDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else { return }
                            searchExercises(query: newValue)
                        }
                    }

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        exercises = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WorkoutType.allCases, id: \.self) { type in
                        workoutTypeChip(type)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var exerciseResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pending exercises banner — tap to open the logger
            if !pendingExercises.isEmpty {
                Button(action: { showingDatabaseLogger = true }) {
                    HStack {
                        Image(systemName: "dumbbell.fill")
                        Text("\(pendingExercises.count) exercise\(pendingExercises.count == 1 ? "" : "s") added — Start Workout")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(selectedWorkoutType.uiColor, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Text("\(exercises.count) EXERCISES FOUND")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            ForEach(exercises) { exercise in
                ExerciseCard(
                    exercise: exercise,
                    typeColor: selectedWorkoutType.uiColor,
                    onAdd: { ex in
                        var entry = LoggedExerciseEntry()
                        entry.name = ex.name
                        pendingExercises.append(entry)
                    }
                )
            }
        }
    }

    private func searchExercises(type: String = "", query: String = "") {
        isSearching = true
        searchError = nil
        exercises = []

        Task {
            do {
                let results = try await ExercisesAPI.shared.fetchExercises(
                    type: type.isEmpty ? nil : type,
                    name: query.isEmpty ? nil : query,
                    limit: 40
                )
                await MainActor.run {
                    if query.isEmpty {
                        exercises = results
                    } else {
                        exercises = FuzzySearch.sort(
                            query: query,
                            items: results,
                            string: { $0.name },
                            additionalStrings: { ex in
                                [ex.muscle, ex.secondaryMuscle, ex.type].compactMap { $0 }
                            }
                        )
                    }
                    // If API returned nothing, fall back to built-in database
                    if exercises.isEmpty {
                        exercises = BuiltInExercises.search(type: type, query: query)
                    }
                    isSearching = false
                }
            } catch {
                // API unavailable — use built-in offline database silently
                await MainActor.run {
                    exercises = BuiltInExercises.search(type: type, query: query)
                    isSearching = false
                }
            }
        }
    }

    private func exerciseErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Couldn't reach exercise database")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                searchExercises(type: selectedWorkoutType.apiType, query: searchQuery)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
    }

    private var exerciseEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No exercises found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Try a different type or search term")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: [Profile.self], inMemory: true)
}
