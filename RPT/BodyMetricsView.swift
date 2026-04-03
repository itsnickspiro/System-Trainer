import SwiftUI
import SwiftData

struct BodyMetricsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query private var profiles: [Profile]
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    @State private var showingAddEntry = false

    private var profile: Profile? { profiles.first }
    private var useMetric: Bool { profile?.useMetric ?? true }

    var body: some View {
        NavigationStack {
            List {
                // Latest snapshot card
                if let latest = measurements.first {
                    Section("Latest") {
                        LatestMetricsCard(measurement: latest, useMetric: useMetric)
                    }
                }

                // History
                if !measurements.isEmpty {
                    Section("History") {
                        ForEach(measurements) { m in
                            MeasurementRow(measurement: m, useMetric: useMetric)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "scalemass.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text("NO BIOMETRIC DATA ON FILE")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Log your physical parameters to begin tracking.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
            .navigationTitle("Body Metrics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddBodyMeasurementView(useMetric: useMetric)
            }
        }
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
    }

    private func deleteEntries(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(measurements[idx])
        }
        context.safeSave()
    }
}

// MARK: - Latest Metrics Card

private struct LatestMetricsCard: View {
    let measurement: BodyMeasurement
    let useMetric: Bool

    private var weightDisplay: String {
        if useMetric {
            return String(format: "%.1f kg", measurement.weightKg)
        } else {
            return String(format: "%.1f lbs", measurement.weightKg * 2.20462)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(weightDisplay)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                Spacer()
                Text(measurement.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if measurement.chestCm != nil || measurement.waistCm != nil || measurement.hipsCm != nil || measurement.bodyFatPercent != nil {
                Divider()
                HStack(spacing: 20) {
                    if let chest = measurement.chestCm {
                        metricChip(label: "Chest", value: useMetric ? "\(Int(chest)) cm" : "\(Int(chest / 2.54))\"")
                    }
                    if let waist = measurement.waistCm {
                        metricChip(label: "Waist", value: useMetric ? "\(Int(waist)) cm" : "\(Int(waist / 2.54))\"")
                    }
                    if let hips = measurement.hipsCm {
                        metricChip(label: "Hips", value: useMetric ? "\(Int(hips)) cm" : "\(Int(hips / 2.54))\"")
                    }
                    if let bf = measurement.bodyFatPercent {
                        metricChip(label: "Body Fat", value: String(format: "%.1f%%", bf))
                    }
                }
            }

            if !measurement.note.isEmpty {
                Text(measurement.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricChip(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Measurement Row

private struct MeasurementRow: View {
    let measurement: BodyMeasurement
    let useMetric: Bool

    private var weightDisplay: String {
        if useMetric {
            return String(format: "%.1f kg", measurement.weightKg)
        } else {
            return String(format: "%.1f lbs", measurement.weightKg * 2.20462)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(weightDisplay)
                    .font(.subheadline.weight(.semibold))
                if let bf = measurement.bodyFatPercent {
                    Text(String(format: "%.1f%% body fat", bf))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !measurement.note.isEmpty {
                    Text(measurement.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(measurement.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Entry Sheet

struct AddBodyMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let useMetric: Bool

    @State private var weightInput: String = ""
    @State private var chestInput: String = ""
    @State private var waistInput: String = ""
    @State private var hipsInput: String = ""
    @State private var bodyFatInput: String = ""
    @State private var note: String = ""
    @State private var date = Date()
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField(useMetric ? "kg" : "lbs", text: $weightInput)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "kg" : "lbs")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Measurements (optional)") {
                    HStack {
                        Text("Chest")
                            .frame(width: 70, alignment: .leading)
                        TextField(useMetric ? "cm" : "inches", text: $chestInput)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "cm" : "in")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Waist")
                            .frame(width: 70, alignment: .leading)
                        TextField(useMetric ? "cm" : "inches", text: $waistInput)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "cm" : "in")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Hips")
                            .frame(width: 70, alignment: .leading)
                        TextField(useMetric ? "cm" : "inches", text: $hipsInput)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "cm" : "in")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Body Fat")
                            .frame(width: 70, alignment: .leading)
                        TextField("%", text: $bodyFatInput)
                            .keyboardType(.decimalPad)
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                Section("Note (optional)") {
                    TextField("e.g. Morning, fasted", text: $note)
                }
            }
            .navigationTitle("Log Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(weightInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
    }

    private func save() {
        guard let rawWeight = Double(weightInput.replacingOccurrences(of: ",", with: ".")) else { return }
        // Convert to kg for storage
        let weightKg = useMetric ? rawWeight : rawWeight / 2.20462

        // Convert optional measurements to cm for storage
        func toCm(_ s: String) -> Double? {
            guard let v = Double(s.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return useMetric ? v : v * 2.54
        }

        let m = BodyMeasurement(
            date: date,
            weightKg: weightKg,
            chestCm: toCm(chestInput),
            waistCm: toCm(waistInput),
            hipsCm: toCm(hipsInput),
            bodyFatPercent: Double(bodyFatInput.replacingOccurrences(of: ",", with: ".")),
            note: note.trimmingCharacters(in: .whitespaces)
        )
        context.insert(m)
        context.safeSave()
        dismiss()
    }
}

#Preview {
    BodyMetricsView()
        .modelContainer(for: [BodyMeasurement.self, Profile.self], inMemory: true)
}
