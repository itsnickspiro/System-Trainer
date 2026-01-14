import SwiftUI

struct WorkoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedWorkoutType: WorkoutType = .strength
    @State private var searchQuery = ""
    @State private var exercises: [Exercise] = []
    @State private var isSearching = false
    @State private var showingWorkoutLogger = false
    @State private var workoutDuration = 30 // minutes

    enum WorkoutType: String, CaseIterable {
        case strength = "Strength"
        case cardio = "Cardio"
        case flexibility = "Flexibility"
        case mixed = "Mixed"

        var icon: String {
            switch self {
            case .strength: return "dumbbell.fill"
            case .cardio: return "heart.circle.fill"
            case .flexibility: return "figure.yoga"
            case .mixed: return "figure.mixed.cardio"
            }
        }

        var color: Color {
            switch self {
            case .strength: return .orange
            case .cardio: return .red
            case .flexibility: return .purple
            case .mixed: return .cyan
            }
        }

        var apiType: String {
            switch self {
            case .strength: return "strength"
            case .cardio: return "cardio"
            case .flexibility: return "stretching"
            case .mixed: return ""
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Workout Type Selector
                    workoutTypeSelector

                    // Quick Start Workout
                    quickStartSection

                    // Exercise Search
                    exerciseSearchSection

                    // Exercise Results
                    if isSearching {
                        ProgressView("Searching exercises...")
                            .padding()
                    } else if !exercises.isEmpty {
                        exerciseResults
                    }
                }
                .padding()
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white)
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingWorkoutLogger) {
                WorkoutLoggerView(
                    workoutType: selectedWorkoutType,
                    duration: $workoutDuration
                )
            }
        }
    }

    private var workoutTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WORKOUT TYPE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WorkoutType.allCases, id: \.self) { type in
                    workoutTypeCard(type)
                }
            }
        }
    }

    private func workoutTypeCard(_ type: WorkoutType) -> some View {
        Button(action: {
            selectedWorkoutType = type
            // Auto-search for this type
            searchExercises(type: type.apiType)
        }) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(selectedWorkoutType == type ? .white : type.color)

                Text(type.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedWorkoutType == type ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedWorkoutType == type ?
                          LinearGradient(colors: [type.color, type.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color(.systemGray6), Color(.systemGray6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
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
                        Text("Log \(selectedWorkoutType.rawValue) Workout")
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
                                .stroke(selectedWorkoutType.color, lineWidth: 2)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var exerciseSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISE DATABASE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search exercises...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchExercises(query: searchQuery)
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
        }
    }

    private var exerciseResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(exercises.count) EXERCISES FOUND")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            ForEach(exercises) { exercise in
                ExerciseCard(exercise: exercise, typeColor: selectedWorkoutType.color)
            }
        }
    }

    private func searchExercises(type: String = "", query: String = "") {
        isSearching = true
        exercises = []

        Task {
            do {
                let results = try await ExercisesAPI.shared.fetchExercises(
                    type: type.isEmpty ? nil : type,
                    name: query.isEmpty ? nil : query,
                    limit: 20
                )
                await MainActor.run {
                    exercises = results
                    isSearching = false
                }
            } catch {
                print("Failed to fetch exercises: \(error)")
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    let typeColor: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            if let muscle = exercise.muscle {
                                Tag(text: muscle.capitalized, color: .blue)
                            }
                            if let difficulty = exercise.difficulty {
                                Tag(text: difficulty.capitalized, color: typeColor)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let instructions = exercise.instructions, !instructions.isEmpty {
                Text(instructions)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataManager = DataManager.shared
    let workoutType: WorkoutView.WorkoutType
    @Binding var duration: Int
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Details") {
                    HStack {
                        Image(systemName: workoutType.icon)
                            .foregroundColor(workoutType.color)
                        Text(workoutType.rawValue)
                            .font(.headline)
                    }

                    Stepper("Duration: \(duration) min", value: $duration, in: 5...180, step: 5)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }

                Section {
                    Button(action: logWorkout) {
                        HStack {
                            Spacer()
                            Text("Complete Workout")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(workoutType.color)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func logWorkout() {
        // Update profile stats based on workout
        dataManager.updateProfile { profile in
            // Increase stats based on workout type
            switch workoutType {
            case .strength:
                profile.strength = min(100, profile.strength + Double(duration) / 10)
            case .cardio:
                profile.endurance = min(100, profile.endurance + Double(duration) / 10)
                profile.energy = min(100, profile.energy + Double(duration) / 15)
            case .flexibility:
                profile.health = min(100, profile.health + Double(duration) / 15)
            case .mixed:
                profile.strength = min(100, profile.strength + Double(duration) / 20)
                profile.endurance = min(100, profile.endurance + Double(duration) / 20)
            }

            // Record workout completion
            profile.updateDailyStats()
        }

        dismiss()
    }
}

#Preview {
    WorkoutView()
}
