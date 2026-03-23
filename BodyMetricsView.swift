import SwiftUI
import SwiftData
import Charts
import HealthKit

// MARK: - Body Metrics View

struct BodyMetricsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var profiles: [Profile]

    @State private var showingAddEntry = false
    @State private var selectedRange: ChartRange = .threeMonths

    private var profile: Profile? { profiles.first }

    enum ChartRange: String, CaseIterable {
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"

        var days: Int? {
            switch self {
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .all: return nil
            }
        }
    }

    private var filteredMeasurements: [BodyMeasurement] {
        guard let days = selectedRange.days else { return measurements }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return measurements.filter { $0.date >= cutoff }
    }

    private var latestWeight: Double? { measurements.last?.weightKg }
    private var startingWeight: Double? { filteredMeasurements.first?.weightKg }

    private var weightChange: Double? {
        guard let latest = latestWeight, let start = startingWeight, latest != start else { return nil }
        return latest - start
    }

    private var bmi: Double? {
        guard let w = latestWeight, let h = profile?.height, h > 0 else { return nil }
        return w / pow(h / 100, 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary cards
                    summaryCards

                    // Chart
                    weightChartSection

                    // Measurements history
                    measurementsHistorySection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body Metrics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddBodyMeasurementView()
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "Current Weight",
                value: latestWeight.map { String(format: "%.1f kg", $0) } ?? "--",
                icon: "scalemass.fill",
                color: .blue
            )
            MetricCard(
                title: "Change (\(selectedRange.rawValue))",
                value: weightChange.map { String(format: "%+.1f kg", $0) } ?? "--",
                icon: weightChange.map { $0 < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill" } ?? "minus.circle.fill",
                color: weightChange.map { $0 < 0 ? .green : .orange } ?? .secondary
            )
            MetricCard(
                title: "BMI",
                value: bmi.map { String(format: "%.1f", $0) } ?? "--",
                icon: "figure.stand",
                color: bmiColor
            )
            MetricCard(
                title: "Entries",
                value: "\(measurements.count)",
                icon: "calendar.badge.checkmark",
                color: .purple
            )
        }
    }

    private var bmiColor: Color {
        guard let b = bmi else { return .secondary }
        if b < 18.5 { return .blue }
        if b < 25 { return .green }
        if b < 30 { return .orange }
        return .red
    }

    // MARK: - Weight Chart

    private var weightChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight Trend")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $selectedRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if filteredMeasurements.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Log at least 2 measurements to see your trend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Chart {
                    ForEach(filteredMeasurements, id: \.id) { m in
                        LineMark(
                            x: .value("Date", m.date),
                            y: .value("Weight", m.weightKg)
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", m.date),
                            y: .value("Weight", m.weightKg)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", m.date),
                            y: .value("Weight", m.weightKg)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(30)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: strideCount)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(String(format: "%.0f", v)) } }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
        )
    }

    private var strideCount: Int {
        switch selectedRange {
        case .oneMonth: return 7
        case .threeMonths: return 14
        case .sixMonths: return 30
        case .oneYear, .all: return 60
        }
    }

    // MARK: - History

    private var measurementsHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            if measurements.isEmpty {
                Text("No measurements logged yet. Tap + to add your first entry.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(measurements.reversed(), id: \.id) { m in
                        MeasurementRow(measurement: m)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(m)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
        )
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.subheadline)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Measurement Row

private struct MeasurementRow: View {
    let measurement: BodyMeasurement

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.date, style: .date)
                    .font(.subheadline.weight(.medium))
                if !measurement.note.isEmpty {
                    Text(measurement.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f kg", measurement.weightKg))
                    .font(.subheadline.weight(.semibold))
                if let bf = measurement.bodyFatPercent {
                    Text(String(format: "%.1f%% BF", bf))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground).opacity(0.01))
    }
}

// MARK: - Add Body Measurement View

struct AddBodyMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @StateObject private var dataManager = DataManager.shared

    @State private var weightKg: String = ""
    @State private var chestCm: String = ""
    @State private var waistCm: String = ""
    @State private var hipsCm: String = ""
    @State private var bodyFat: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var showingMeasurements = false

    private var profile: Profile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Weight") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("70.0", text: $weightKg)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section {
                    DisclosureGroup("Body Measurements (optional)", isExpanded: $showingMeasurements) {
                        HStack {
                            Text("Chest (cm)")
                            Spacer()
                            TextField("--", text: $chestCm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Waist (cm)")
                            Spacer()
                            TextField("--", text: $waistCm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Hips (cm)")
                            Spacer()
                            TextField("--", text: $hipsCm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Body Fat %")
                            Spacer()
                            TextField("--", text: $bodyFat)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional note (e.g. morning, fasted)", text: $note)
                }
            }
            .navigationTitle("Log Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(Double(weightKg) == nil)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Pre-fill from profile
                if let w = profile?.weight { weightKg = String(format: "%.1f", w) }
            }
        }
    }

    private func save() {
        guard let kg = Double(weightKg) else { return }
        let m = BodyMeasurement(
            date: date,
            weightKg: kg,
            chestCm: Double(chestCm),
            waistCm: Double(waistCm),
            hipsCm: Double(hipsCm),
            bodyFatPercent: Double(bodyFat),
            note: note
        )
        context.insert(m)
        // Also update profile weight
        if let p = profile { p.weight = kg }
        try? context.save()
        // Write to Apple Health
        Task { await dataManager.healthManager.saveBodyWeight(kg, date: date) }
        dismiss()
    }
}
