import SwiftUI
import SwiftData

// MARK: - Progress Charts View

struct ProgressChartsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt) private var workoutSessions: [WorkoutSession]
    @Query private var profiles: [Profile]
    @Query(sort: \ExerciseSet.loggedAt) private var allSets: [ExerciseSet]
    @Query(sort: \BodyMeasurement.date) private var bodyMeasurements: [BodyMeasurement]
    @Query(sort: \FoodEntry.dateConsumed) private var foodEntries: [FoodEntry]

    @State private var selectedExercise: String = ""

    private var profile: Profile? { profiles.first }

    /// All unique exercise names that have at least one logged set
    private var exerciseNames: [String] {
        let names = Set(allSets.map { $0.exerciseName }).filter { !$0.isEmpty }
        return names.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Level & XP Card
                    levelProgressCard

                    // Weekly workout bar chart
                    weeklyWorkoutChart

                    // Streak calendar heatmap
                    streakCalendar

                    // Personal Records summary
                    personalRecordsSummary

                    // Volume load history per exercise
                    volumeHistoryChart

                    // Body metrics: weight, body fat %, rate-of-change
                    bodyMetricsChart

                    // Weight trend vs calorie intake
                    weightVsCaloriesChart

                    Spacer(minLength: 80)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Level Progress Card

    private var levelProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Level Progress", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.cyan)

            if let p = profile {
                let tier = QuestManager.tier(for: p.level)
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("LVL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(p.level)")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundColor(.cyan)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 50)

                    VStack(spacing: 4) {
                        Text("RANK")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(tier.rank.displayName)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(rankColor(tier.rank))
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 50)

                    VStack(spacing: 4) {
                        Text("STREAK")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Text("\(p.currentStreak)")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // XP bar
                let threshold = p.levelXPThreshold(level: p.level)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("XP to next level")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(p.xp) / \(threshold)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.cyan)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.cyan.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * (Double(p.xp) / Double(max(1, threshold)))))
                        }
                    }
                    .frame(height: 8)
                }

                // Total workouts
                HStack {
                    Label("\(workoutSessions.count) total workouts", systemImage: "dumbbell.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Label("Best: \(p.bestStreak) days", systemImage: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Weekly Workout Bar Chart

    private var weeklyWorkoutChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workouts Per Week", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(.orange)

            let weekBuckets = buildWeekBuckets()
            if weekBuckets.isEmpty || weekBuckets.allSatisfy({ $0.count == 0 }) {
                Text("Complete your first workout to see progress here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let maxCount = max(1, weekBuckets.map { $0.count }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weekBuckets.suffix(12), id: \.label) { bucket in
                        VStack(spacing: 4) {
                            Text("\(bucket.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(bucket.count > 0 ? .orange : .clear)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bucket.count > 0 ? Color.orange : Color.gray.opacity(0.2))
                                .frame(height: max(4, 80 * CGFloat(bucket.count) / CGFloat(maxCount)))
                            Text(bucket.label)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Streak Calendar Heatmap (last 8 weeks)

    private var streakCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activity Heatmap", systemImage: "calendar")
                .font(.headline)
                .foregroundColor(.green)

            let activeDates = Set(workoutSessions.map { Calendar.current.startOfDay(for: $0.startedAt) })
            let weeks = buildCalendarWeeks()

            VStack(spacing: 4) {
                // Day headers
                HStack(spacing: 4) {
                    ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks.indices, id: \.self) { wi in
                    HStack(spacing: 4) {
                        ForEach(weeks[wi].indices, id: \.self) { di in
                            if let date = weeks[wi][di] {
                                let isActive = activeDates.contains(Calendar.current.startOfDay(for: date))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? Color.green : Color.gray.opacity(0.15))
                                    .frame(height: 20)
                                    .overlay(
                                        Text(isActive ? "" : "\(Calendar.current.component(.day, from: date))")
                                            .font(.system(size: 7))
                                            .foregroundColor(.secondary)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.clear)
                                    .frame(height: 20)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15)).frame(width: 12, height: 12)
                Text("No workout")
                RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 12, height: 12)
                Text("Worked out")
                Spacer()
                Text("\(activeDates.count) active days")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Personal Records Summary

    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var personalRecords: [PersonalRecord]

    private var personalRecordsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Records", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundColor(.yellow)

            if personalRecords.isEmpty {
                Text("Log workouts to track your personal records.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(personalRecords.prefix(5), id: \.id) { pr in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pr.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("Best: \(String(format: "%.1f", pr.bestWeightKg))kg × \(pr.bestReps) reps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 3) {
                                    Text("1RM")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text(String(format: "%.0fkg", pr.oneRepMaxKg))
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.purple)
                                .cornerRadius(5)

                                Text(pr.achievedAt.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Training zone loads
                        oneRMLoadingZones(pr.oneRepMaxKg)
                    }
                    if pr.id != personalRecords.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Volume Load History Chart

    /// Weekly tonnage buckets for the selected exercise (last 12 weeks)
    private func volumeBuckets(for exercise: String) -> [VolumeBucket] {
        let cal = Calendar.current
        let now = Date()
        return (0..<12).reversed().compactMap { weekOffset -> VolumeBucket? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: cal.startOfDay(for: now)),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
            let tonnage = allSets
                .filter { $0.exerciseName == exercise && $0.loggedAt >= weekStart && $0.loggedAt < weekEnd }
                .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return VolumeBucket(label: formatter.string(from: weekStart), tonnage: tonnage)
        }
    }

    private var volumeHistoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Volume Load History", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.purple)

            if exerciseNames.isEmpty {
                Text("Log strength workouts to track volume trends.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Exercise picker
                Picker("Exercise", selection: $selectedExercise) {
                    ForEach(exerciseNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.purple)
                .onAppear {
                    if selectedExercise.isEmpty, let first = exerciseNames.first {
                        selectedExercise = first
                    }
                }

                let buckets = volumeBuckets(for: selectedExercise)
                let maxTonnage = max(1.0, buckets.map { $0.tonnage }.max() ?? 1.0)
                let totalTonnage = buckets.reduce(0.0) { $0 + $1.tonnage }

                if totalTonnage == 0 {
                    Text("No sets logged for \(selectedExercise) in the past 12 weeks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(buckets, id: \.label) { bucket in
                            VStack(spacing: 4) {
                                if bucket.tonnage > 0 {
                                    Text("\(Int(bucket.tonnage))")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.purple)
                                } else {
                                    Text("").font(.system(size: 8))
                                }
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(bucket.tonnage > 0 ? Color.purple : Color.gray.opacity(0.2))
                                    .frame(height: max(4, 80 * CGFloat(bucket.tonnage) / CGFloat(maxTonnage)))
                                Text(bucket.label)
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 110)

                    HStack {
                        Text("Total: \(Int(totalTonnage)) kg lifted over 12 weeks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("kg × reps")
                            .font(.caption2)
                            .foregroundColor(.purple.opacity(0.7))
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Body Metrics Chart (Weight + Body Fat + Rate of Change)

    private var bodyMetricsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Body Metrics", systemImage: "figure.stand")
                .font(.headline)
                .foregroundColor(.teal)

            if bodyMeasurements.isEmpty {
                Text("Log body measurements to see trends.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let recent = Array(bodyMeasurements.suffix(20))

                // Rate-of-change indicator
                rateOfChangeRow(measurements: recent)

                // Weight trend sparkline
                weightSparkline(measurements: recent)

                // Body fat trend (if data exists)
                let withFat = recent.filter { $0.bodyFatPercent != nil }
                if !withFat.isEmpty {
                    bodyFatSparkline(measurements: withFat)
                }

                // Latest snapshot
                if let latest = bodyMeasurements.last {
                    HStack(spacing: 16) {
                        metricPill(value: String(format: "%.1f kg", latest.weightKg),
                                   label: "Weight",
                                   color: .teal)
                        if let bf = latest.bodyFatPercent {
                            metricPill(value: String(format: "%.1f%%", bf),
                                       label: "Body Fat",
                                       color: .orange)
                        }
                        Spacer()
                        Text(latest.date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func rateOfChangeRow(measurements: [BodyMeasurement]) -> some View {
        if measurements.count >= 2 {
            // Use last 4 entries (or all if fewer) to compute weekly rate
            let sample = Array(measurements.suffix(4))
            let first = sample.first!
            let last = sample.last!
            let daysDiff = max(1.0, last.date.timeIntervalSince(first.date) / 86400.0)
            let kgChange = last.weightKg - first.weightKg
            let weeklyRate = kgChange / daysDiff * 7.0

            let arrow = weeklyRate > 0.05 ? "↑" : weeklyRate < -0.05 ? "↓" : "→"
            let color: Color = weeklyRate > 0.05 ? .red : weeklyRate < -0.05 ? .green : .secondary
            let rateText = String(format: "%+.2f kg/week", weeklyRate)

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.teal)
                Text("Rate of change:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(arrow) \(rateText)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func weightSparkline(measurements: [BodyMeasurement]) -> some View {
        let weights = measurements.map { $0.weightKg }
        let minW = (weights.min() ?? 0) - 1
        let maxW = (weights.max() ?? 1) + 1
        let range = max(1.0, maxW - minW)

        VStack(alignment: .leading, spacing: 4) {
            Text("WEIGHT (kg)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            GeometryReader { geo in
                let pts = measurements.enumerated().map { i, m -> CGPoint in
                    let x = measurements.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(measurements.count - 1) : geo.size.width / 2
                    let y = geo.size.height * CGFloat(1 - (m.weightKg - minW) / range)
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    // Area fill
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts.first!.x, y: geo.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [.teal.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    }

                    // Line
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: pts[0])
                            pts.dropFirst().forEach { p.addLine(to: $0) }
                        }
                        .stroke(Color.teal, lineWidth: 2)
                    }

                    // Dots
                    ForEach(pts.indices, id: \.self) { i in
                        Circle()
                            .fill(Color.teal)
                            .frame(width: 5, height: 5)
                            .position(pts[i])
                    }
                }
            }
            .frame(height: 60)
        }
    }

    @ViewBuilder
    private func bodyFatSparkline(measurements: [BodyMeasurement]) -> some View {
        let fats = measurements.compactMap { $0.bodyFatPercent }
        let minF = (fats.min() ?? 0) - 1
        let maxF = (fats.max() ?? 1) + 1
        let range = max(1.0, maxF - minF)

        VStack(alignment: .leading, spacing: 4) {
            Text("BODY FAT (%)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            GeometryReader { geo in
                let pts = measurements.enumerated().compactMap { i, m -> CGPoint? in
                    guard let bf = m.bodyFatPercent else { return nil }
                    let x = measurements.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(measurements.count - 1) : geo.size.width / 2
                    let y = geo.size.height * CGFloat(1 - (bf - minF) / range)
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts.first!.x, y: geo.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [.orange.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))

                        Path { p in
                            p.move(to: pts[0])
                            pts.dropFirst().forEach { p.addLine(to: $0) }
                        }
                        .stroke(Color.orange, lineWidth: 2)
                    }

                    ForEach(pts.indices, id: \.self) { i in
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                            .position(pts[i])
                    }
                }
            }
            .frame(height: 60)
        }
    }

    private func metricPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Weight vs Calories Correlation Chart

    private var weightVsCaloriesChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weight vs Calories", systemImage: "flame.fill")
                .font(.headline)
                .foregroundColor(.red)

            let points = buildWeightCaloriePoints()

            if points.isEmpty {
                Text("Log both meals and body weight to see the correlation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Dual-axis line chart: calories (bars) + weight (line overlay)
                let sortedPoints = points.sorted { $0.date < $1.date }
                let maxCals = max(1.0, sortedPoints.map { $0.calories }.max() ?? 1.0)
                let weights = sortedPoints.map { $0.weight }
                let minW = (weights.min() ?? 0) - 1
                let maxW = (weights.max() ?? 1) + 1
                let weightRange = max(1.0, maxW - minW)

                ZStack(alignment: .bottom) {
                    // Calorie bars
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(sortedPoints, id: \.date) { pt in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.3))
                                .frame(height: max(4, 80 * CGFloat(pt.calories) / CGFloat(maxCals)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 80)

                    // Weight line overlay
                    GeometryReader { geo in
                        let pts = sortedPoints.enumerated().map { i, pt -> CGPoint in
                            let x = sortedPoints.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(sortedPoints.count - 1) : geo.size.width / 2
                            let y = geo.size.height * CGFloat(1 - (pt.weight - minW) / weightRange)
                            return CGPoint(x: x, y: y)
                        }
                        if pts.count > 1 {
                            Path { p in
                                p.move(to: pts[0])
                                pts.dropFirst().forEach { p.addLine(to: $0) }
                            }
                            .stroke(Color.teal, lineWidth: 2)

                            ForEach(pts.indices, id: \.self) { i in
                                Circle()
                                    .fill(Color.teal)
                                    .frame(width: 6, height: 6)
                                    .position(pts[i])
                            }
                        }
                    }
                    .frame(height: 80)
                }
                .frame(height: 80)

                // X-axis labels (every other point to avoid clutter)
                HStack {
                    ForEach(sortedPoints.indices, id: \.self) { i in
                        if i % max(1, sortedPoints.count / 4) == 0 {
                            Text(sortedPoints[i].date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                        if i < sortedPoints.count - 1 {
                            Spacer()
                        }
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.red.opacity(0.5)).frame(width: 12, height: 8)
                        Text("Calories").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.teal).frame(width: 12, height: 3)
                        Text("Weight").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// Match food entry calorie totals with body measurements on the same day or nearest day
    private func buildWeightCaloriePoints() -> [WeightCaloriePoint] {
        guard !bodyMeasurements.isEmpty && !foodEntries.isEmpty else { return [] }
        let cal = Calendar.current
        let last30 = bodyMeasurements.filter { $0.date >= Date().addingTimeInterval(-30 * 86400) }
        guard !last30.isEmpty else { return Array(bodyMeasurements.suffix(10).compactMap { m -> WeightCaloriePoint? in
            let dayStart = cal.startOfDay(for: m.date)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let cals = foodEntries
                .filter { $0.dateConsumed >= dayStart && $0.dateConsumed < dayEnd }
                .reduce(0.0) { $0 + $1.totalCalories }
            guard cals > 0 else { return nil }
            return WeightCaloriePoint(date: m.date, weight: m.weightKg, calories: cals)
        }) }

        return last30.compactMap { m -> WeightCaloriePoint? in
            let dayStart = cal.startOfDay(for: m.date)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let cals = foodEntries
                .filter { $0.dateConsumed >= dayStart && $0.dateConsumed < dayEnd }
                .reduce(0.0) { $0 + $1.totalCalories }
            guard cals > 0 else { return nil }
            return WeightCaloriePoint(date: m.date, weight: m.weightKg, calories: cals)
        }
    }

    // MARK: - Helpers

    private struct WeekBucket {
        let label: String
        let count: Int
    }

    private struct VolumeBucket {
        let label: String
        let tonnage: Double
    }

    private struct WeightCaloriePoint {
        let date: Date
        let weight: Double
        let calories: Double
    }

    private func buildWeekBuckets() -> [WeekBucket] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [WeekBucket] = []
        for weekOffset in (0..<12).reversed() {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: cal.startOfDay(for: now)),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { continue }
            let count = workoutSessions.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            buckets.append(WeekBucket(label: formatter.string(from: weekStart), count: count))
        }
        return buckets
    }

    private func buildCalendarWeeks() -> [[Date?]] {
        let cal = Calendar.current
        let now = Date()
        let todayWeekday = cal.component(.weekday, from: now) - 1 // 0=Sun
        guard let startDate = cal.date(byAdding: .day, value: -(todayWeekday + 7 * 7), to: cal.startOfDay(for: now)) else { return [] }

        var weeks: [[Date?]] = []
        var current = startDate
        while current <= now {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(current <= now ? current : nil)
                current = cal.date(byAdding: .day, value: 1, to: current) ?? current
            }
            weeks.append(week)
        }
        return weeks
    }

    /// Compact row of training zone weights (50–85% 1RM) shown under each PR.
    @ViewBuilder
    private func oneRMLoadingZones(_ oneRM: Double) -> some View {
        let zones: [(String, Double, Color)] = [
            ("50%", oneRM * 0.50, .gray),
            ("60%", oneRM * 0.60, .blue),
            ("70%", oneRM * 0.70, .teal),
            ("80%", oneRM * 0.80, .orange),
            ("85%", oneRM * 0.85, .red),
        ]
        HStack(spacing: 6) {
            ForEach(zones, id: \.0) { label, kg, color in
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                    Text(String(format: "%.0f", kg))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.primary)
                    Text("kg")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(color.opacity(0.08))
                .cornerRadius(5)
            }
        }
    }

    private func rankColor(_ rank: QuestManager.TierRank) -> Color {
        switch rank {
        case .e: return .gray
        case .d: return .green
        case .c: return .blue
        case .b: return .purple
        case .a: return .orange
        case .s: return .yellow
        }
    }
}

#Preview {
    ProgressChartsView()
        .modelContainer(for: [Profile.self, WorkoutSession.self, PersonalRecord.self, ExerciseSet.self, BodyMeasurement.self, FoodEntry.self, FoodItem.self], inMemory: true)
}
