import SwiftUI

// MARK: - Notification name for activity logging

extension Notification.Name {
    static let activityLogged = Notification.Name("activityLogged")
}

// MARK: - Activity Logger View

/// A sheet-presented multi-step flow for logging real-world activities.
/// Maps free-text descriptions to workout types and awards XP.
struct ActivityLoggerView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var step = 1
    @State private var activityDescription = ""
    @State private var mapping: ActivityMapping = ActivityMapper.map("")
    @State private var durationMinutes = 30
    @State private var selectedIntensity: ActivityIntensity = .moderate
    @State private var distanceMiles = ""

    // Quick-pick options shown on step 1
    private let quickPicks = [
        ("Walk", "figure.walk"),
        ("Run", "figure.run"),
        ("Bike", "bicycle"),
        ("Yard Work", "leaf.fill"),
        ("Cleaning", "sparkles"),
        ("Sports", "sportscourt.fill"),
    ]

    // Computed XP based on current duration and intensity
    private var xpEarned: Int {
        ActivityMapper.calculateXP(durationMinutes: durationMinutes, intensity: selectedIntensity)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Step indicator
                    stepIndicator
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    // Step content
                    switch step {
                    case 1:
                        step1View
                    case 2:
                        step2View
                    case 3:
                        step3View
                    default:
                        EmptyView()
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step > 1 {
                        Button {
                            withAnimation { step -= 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.cyan)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.cyan : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Step 1: What did you do?

    private var step1View: some View {
        VStack(spacing: 24) {
            Text("LOG ACTIVITY")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundColor(.white)

            Text("What did you do?")
                .font(.headline)
                .foregroundColor(.gray)

            // Text field for activity description
            TextField("e.g. Walked the dog", text: $activityDescription)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .foregroundColor(.white)
                .autocorrectionDisabled(false)

            // Quick-pick buttons
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Pick")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    ForEach(quickPicks, id: \.0) { name, icon in
                        Button {
                            activityDescription = name
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: icon)
                                    .font(.title3)
                                Text(name)
                                    .font(.caption)
                            }
                            .foregroundColor(activityDescription == name ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                activityDescription == name
                                    ? Color.cyan
                                    : Color.white.opacity(0.08)
                            )
                            .cornerRadius(12)
                        }
                    }
                }
            }

            Spacer()

            // Continue button
            Button {
                // Map the description and advance
                mapping = ActivityMapper.map(activityDescription)
                selectedIntensity = mapping.suggestedIntensity
                withAnimation { step = 2 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(activityDescription.isEmpty ? Color.gray : Color.cyan)
                    .cornerRadius(14)
            }
            .disabled(activityDescription.isEmpty)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 2: Details

    private var step2View: some View {
        VStack(spacing: 24) {
            Text("DETAILS")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundColor(.white)

            // Mapped activity card
            HStack(spacing: 12) {
                Image(systemName: mapping.workoutType.icon)
                    .font(.title)
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.label)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(mapping.workoutType.displayName)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)

            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                HStack {
                    Text("\(durationMinutes) min")
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Stepper("", value: $durationMinutes, in: 5...120, step: 5)
                        .labelsHidden()
                        .tint(.cyan)
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }

            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                Text("Intensity")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                Picker("Intensity", selection: $selectedIntensity) {
                    ForEach(ActivityIntensity.allCases, id: \.self) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Distance (only for cardio)
            if mapping.workoutType == .cardio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Distance (optional)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .textCase(.uppercase)

                    HStack {
                        TextField("0.0", text: $distanceMiles)
                            .textFieldStyle(.plain)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.white)
                        Text("miles")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                }
            }

            Spacer()

            // Continue button
            Button {
                withAnimation { step = 3 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .cornerRadius(14)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 3: Confirmation

    private var step3View: some View {
        VStack(spacing: 24) {
            Text("CONFIRM")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundColor(.white)

            // Confirmation card
            VStack(spacing: 16) {
                // Activity name
                Text(activityDescription)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Divider().background(Color.gray.opacity(0.3))

                // Workout type row
                HStack {
                    Image(systemName: mapping.workoutType.icon)
                        .foregroundColor(.cyan)
                    Text(mapping.workoutType.displayName)
                        .foregroundColor(.white)
                    Spacer()
                }

                // Duration row
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.cyan)
                    Text("\(durationMinutes) minutes")
                        .foregroundColor(.white)
                    Spacer()
                }

                // Intensity row
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.cyan)
                    Text(selectedIntensity.displayName)
                        .foregroundColor(.white)
                    Spacer()
                }

                // Distance row (if provided)
                if mapping.workoutType == .cardio, !distanceMiles.isEmpty {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.cyan)
                        Text("\(distanceMiles) miles")
                            .foregroundColor(.white)
                        Spacer()
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                // XP earned
                HStack {
                    Text("XP Earned")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("+\(xpEarned) XP")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.06))
            .cornerRadius(16)

            Spacer()

            // Log Activity button
            Button {
                logActivity()
            } label: {
                Text("Log Activity")
                    .font(.headline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .cornerRadius(14)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Log Activity

    /// Posts a notification with the activity details and dismisses the sheet.
    private func logActivity() {
        let userInfo: [String: Any] = [
            "activityName": activityDescription,
            "workoutType": mapping.workoutType.rawValue,
            "durationMinutes": durationMinutes,
            "intensity": selectedIntensity.rawValue,
            "xpEarned": xpEarned,
        ]

        NotificationCenter.default.post(
            name: .activityLogged,
            object: nil,
            userInfo: userInfo
        )

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ActivityLoggerView()
}
