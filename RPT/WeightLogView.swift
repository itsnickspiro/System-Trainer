import SwiftUI
import SwiftData

/// Compact weight logging card for HomeView + detail sheet for history/trend.
struct WeightLogCard: View {
    @Environment(\.modelContext) private var context
    let profile: Profile

    @State private var showLogSheet = false

    private var displayWeight: String {
        if profile.useMetric {
            return String(format: "%.1f kg", profile.weight)
        } else {
            return String(format: "%.1f lbs", profile.weight * 2.20462)
        }
    }

    var body: some View {
        Button {
            showLogSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BODY WEIGHT")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Text(displayWeight)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }

                Spacer()

                Text("Log")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.cyan, in: Capsule())
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLogSheet) {
            WeightLogSheet(profile: profile)
        }
    }
}

// MARK: - Weight Log Sheet

struct WeightLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let profile: Profile

    @State private var weightValue: Double = 0
    @State private var note: String = ""
    @State private var showingSuccess = false

    @Query(sort: \BodyMeasurement.date, order: .reverse)
    private var measurements: [BodyMeasurement]

    private var isMetric: Bool { profile.useMetric }
    private var recentMeasurements: [BodyMeasurement] {
        Array(measurements.prefix(30))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Weight input
                    weightInputSection

                    // Note
                    TextField("Note (optional)", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    // Log button
                    Button {
                        logWeight()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log Weight")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.black)
                    }
                    .padding(.horizontal)

                    // Trend
                    if !recentMeasurements.isEmpty {
                        trendSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                weightValue = isMetric ? profile.weight : profile.weight * 2.20462
            }
            .alert("Weight Logged!", isPresented: $showingSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your weight has been recorded.")
            }
        }
    }

    // MARK: - Weight Input

    private var weightInputSection: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.1f", weightValue))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.cyan)

            Text(isMetric ? "kg" : "lbs")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                Button { weightValue = max(0, weightValue - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }

                Button { weightValue = max(0, weightValue - 0.1) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }

                Button { weightValue += 0.1 } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }

                Button { weightValue += 1 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Trend Section

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT TREND")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
                .padding(.horizontal)

            ForEach(recentMeasurements.prefix(10)) { measurement in
                HStack {
                    Text(measurement.date, style: .date)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    if isMetric {
                        Text(String(format: "%.1f kg", measurement.weightKg))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    } else {
                        Text(String(format: "%.1f lbs", measurement.weightKg * 2.20462))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func logWeight() {
        let weightKg = isMetric ? weightValue : weightValue / 2.20462

        // Update profile
        profile.weight = weightKg

        // Create measurement entry
        let measurement = BodyMeasurement(
            date: Date(),
            weightKg: weightKg,
            note: note
        )
        context.insert(measurement)
        context.safeSave()

        // Post notification for quest auto-completion
        NotificationCenter.default.post(name: .weightLogged, object: nil)

        showingSuccess = true
    }
}

extension Notification.Name {
    static let weightLogged = Notification.Name("weightLogged")
}
