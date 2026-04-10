import SwiftUI

/// Quick workout logger from the Watch. Pick a type and confirm.
struct WorkoutLogView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var showingConfirmation = false
    @State private var selectedType: WorkoutCategory = .strength

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("LOG WORKOUT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(2)

                ForEach(WorkoutCategory.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                        showingConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.system(size: 14))
                                .foregroundColor(type.color)
                                .frame(width: 24)

                            Text(type.displayName)
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(type.color.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Workout")
        .alert("Log \(selectedType.displayName)?", isPresented: $showingConfirmation) {
            Button("Log It") {
                session.completeWorkout(type: selectedType.rawValue)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will auto-complete matching quests on your iPhone.")
        }
    }
}

enum WorkoutCategory: String, CaseIterable {
    case strength
    case cardio
    case flexibility
    case mixed

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .flexibility: return "Flexibility"
        case .mixed: return "Mixed"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .flexibility: return "figure.flexibility"
        case .mixed: return "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .strength: return .red
        case .cardio: return .orange
        case .flexibility: return .green
        case .mixed: return .purple
        }
    }
}
