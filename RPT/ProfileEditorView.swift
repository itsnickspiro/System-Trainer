import SwiftUI
import SwiftData

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: Profile
    
    @State private var name: String
    @State private var height: Double
    @State private var weight: Double
    @State private var dailyStepsGoal: Int
    @State private var dailyCaloriesGoal: Int
    @State private var weeklyWorkoutGoal: Int
    
    @State private var heightUnit: HeightUnit = (Locale.current.measurementSystem == .metric) ? .metric : .imperial
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 8
    @State private var heightCentimeters: Int = 170
    
    @State private var isEditingHeight = false
    @State private var isEditingWeight = false
    
    @State private var weightUnit: WeightUnit = (Locale.current.measurementSystem == .metric) ? .metric : .imperial
    @State private var weightKilograms: Int = 75
    @State private var weightPounds: Int = 165
    
    enum HeightUnit: String, CaseIterable, Identifiable {
        case metric, imperial
        var id: String { rawValue }
        var displayName: String { self == .metric ? "Metric" : "Imperial" }
    }
    
    enum WeightUnit: String, CaseIterable, Identifiable {
        case metric, imperial
        var id: String { rawValue }
        var displayName: String { self == .metric ? "Metric" : "Imperial" }
    }
    
    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _height = State(initialValue: profile.height)
        _weight = State(initialValue: profile.weight)
        _dailyStepsGoal = State(initialValue: profile.dailyStepsGoal)
        _dailyCaloriesGoal = State(initialValue: profile.dailyActiveCaloriesGoal)
        _weeklyWorkoutGoal = State(initialValue: profile.weeklyWorkoutGoal)
        
        // Initialize height pickers from cm
        let cm = Int(profile.height.rounded())
        let totalInches = Int((Double(cm) / 2.54).rounded())
        let feet = max(3, min(7, totalInches / 12))
        let inches = max(0, min(11, totalInches % 12))
        _heightCentimeters = State(initialValue: max(120, min(220, cm)))
        _heightFeet = State(initialValue: feet)
        _heightInches = State(initialValue: inches)
        
        // Initialize weight pickers from kg
        let kg = Int(profile.weight.rounded())
        let lbs = Int((profile.weight * 2.20462).rounded())
        _weightKilograms = State(initialValue: max(40, min(200, kg)))
        _weightPounds = State(initialValue: max(90, min(440, lbs)))
    }
    
    private func computedGoals(height: Double, weight: Double) -> (steps: Int, activeCalories: Int, weeklyMinutes: Int) {
        // Simple heuristic: scale with height and weight
        // Base values
        let baseSteps = 8000.0
        let baseCalories = 400.0
        let baseWeekly = 150.0 // minutes per week

        // Height factor: normalize around 170cm
        let heightFactor = max(0.8, min(1.2, height / 170.0))
        // Weight factor: normalize around 75kg
        let weightFactor = max(0.8, min(1.2, weight / 75.0))

        let steps = Int((baseSteps * heightFactor * weightFactor).rounded())
        let calories = Int((baseCalories * weightFactor).rounded())
        let weekly = Int((baseWeekly * heightFactor).rounded())

        return (max(3000, steps), max(150, calories), max(90, weekly))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    HStack {
                        Text("Name")
                        TextField("Your name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    // Height summary row
                    Button {
                        withAnimation { isEditingHeight.toggle() }
                    } label: {
                        HStack {
                            Text("Height")
                            Spacer()
                            Text(heightUnit == .metric ? "\(heightCentimeters) cm" : "\(heightFeet) ft \(heightInches) in")
                                .foregroundColor(.secondary)
                            Image(systemName: isEditingHeight ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if isEditingHeight {
                        Picker("Units", selection: $heightUnit) {
                            ForEach(HeightUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)

                        if heightUnit == .imperial {
                            HStack {
                                Picker("Feet", selection: $heightFeet) {
                                    ForEach(3...7, id: \.self) { f in
                                        Text("\(f) ft").tag(f)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                .clipped()

                                Picker("Inches", selection: $heightInches) {
                                    ForEach(0...11, id: \.self) { i in
                                        Text("\(i) in").tag(i)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            }
                            .frame(height: 120)
                            .onChange(of: heightFeet) { _, _ in
                                height = Double((heightFeet * 12 + heightInches)) * 2.54
                                heightCentimeters = Int(height.rounded())
                            }
                            .onChange(of: heightInches) { _, _ in
                                height = Double((heightFeet * 12 + heightInches)) * 2.54
                                heightCentimeters = Int(height.rounded())
                            }
                        } else {
                            Picker("Centimeters", selection: $heightCentimeters) {
                                ForEach(120...220, id: \.self) { c in
                                    Text("\(c) cm").tag(c)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .clipped()
                            .onChange(of: heightCentimeters) { _, newValue in
                                height = Double(newValue)
                                let totalInches = Int((height / 2.54).rounded())
                                heightFeet = max(3, min(7, totalInches / 12))
                                heightInches = max(0, min(11, totalInches % 12))
                            }
                        }
                    }
                    
                    // Weight summary row
                    Button {
                        withAnimation { isEditingWeight.toggle() }
                    } label: {
                        HStack {
                            Text("Weight")
                            Spacer()
                            Text(weightUnit == .metric ? "\(weightKilograms) kg" : "\(weightPounds) lb")
                                .foregroundColor(.secondary)
                            Image(systemName: isEditingWeight ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if isEditingWeight {
                        Picker("Units", selection: $weightUnit) {
                            ForEach(WeightUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)

                        if weightUnit == .imperial {
                            Picker("Pounds", selection: $weightPounds) {
                                ForEach(90...440, id: \.self) { p in
                                    Text("\(p) lb").tag(p)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .clipped()
                            .onChange(of: weightPounds) { _, newValue in
                                weight = Double(newValue) * 0.453592
                                weightKilograms = Int(weight.rounded())
                            }
                        } else {
                            Picker("Kilograms", selection: $weightKilograms) {
                                ForEach(40...200, id: \.self) { k in
                                    Text("\(k) kg").tag(k)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .clipped()
                            .onChange(of: weightKilograms) { _, newValue in
                                weight = Double(newValue)
                                weightPounds = Int((weight * 2.20462).rounded())
                            }
                        }
                    }
                }
                
                Section("Health Goals") {
                    let goals = computedGoals(height: height, weight: weight)
                    
                    HStack {
                        Text("Daily Steps")
                        Spacer()
                        Text("\(goals.steps)")
                            .foregroundColor(.secondary)
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Daily Active Calories")
                        Spacer()
                        Text("\(goals.activeCalories)")
                            .foregroundColor(.secondary)
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Weekly Workout Minutes")
                        Spacer()
                        Text("\(goals.weeklyMinutes)")
                            .foregroundColor(.secondary)
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                    }
                }
                
                Section("Current Stats") {
                    StatRow(title: "Current Level", value: "\(profile.level)")
                    StatRow(title: "Total XP", value: "\(profile.xp)")
                    StatRow(title: "Current Streak", value: "\(profile.currentStreak) days")
                    StatRow(title: "Best Streak", value: "\(profile.bestStreak) days")
                }
                
                Section("RPG Attributes") {
                    StatRow(title: "Health", value: "\(Int(profile.health))/100")
                    StatRow(title: "Energy", value: "\(Int(profile.energy))/100")
                    StatRow(title: "Strength", value: "\(Int(profile.strength))/100")
                    StatRow(title: "Endurance", value: "\(Int(profile.endurance))/100")
                    StatRow(title: "Focus", value: "\(Int(profile.focus))/100")
                    StatRow(title: "Discipline", value: "\(Int(profile.discipline))/100")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(nil)
    }
    
    private func saveProfile() {
        profile.name = name
        profile.height = height
        profile.weight = weight

        let goals = computedGoals(height: height, weight: weight)
        profile.dailyStepsGoal = goals.steps
        profile.dailyActiveCaloriesGoal = goals.activeCalories
        profile.weeklyWorkoutGoal = goals.weeklyMinutes

        do {
            try modelContext.save()
        } catch {
            print("Failed to save profile changes: \(error)")
        }

        NotificationCenter.default.post(name: .profileDidSave, object: nil)

        dismiss()
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct HealthSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthManager: HealthManager
    let profile: Profile
    
    @State private var autoSyncEnabled = true
    @State private var syncFrequency = "hourly"
    @State private var showingPermissions = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Status") {
                    HStack {
                        Image(systemName: healthManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(healthManager.isAuthorized ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text("Apple Health")
                                .font(.headline)
                            Text(healthManager.permissionStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !healthManager.isAuthorized && healthManager.healthDataAvailable {
                        Button("Request Access") {
                            Task {
                                await healthManager.requestAuthorization()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("Open Health App") {
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                
                if healthManager.isAuthorized {
                    Section("Sync Settings") {
                        Toggle("Auto-Sync Health Data", isOn: $autoSyncEnabled)
                        
                        Picker("Sync Frequency", selection: $syncFrequency) {
                            Text("Real-time").tag("realtime")
                            Text("Every Hour").tag("hourly")
                            Text("Daily").tag("daily")
                        }
                    }
                    
                    Section("Data Sources") {
                        HealthDataSourceRow(
                            title: "Steps",
                            icon: "figure.walk",
                            color: .blue,
                            status: .connected
                        )
                        
                        HealthDataSourceRow(
                            title: "Active Calories",
                            icon: "flame.fill",
                            color: .orange,
                            status: .connected
                        )
                        
                        HealthDataSourceRow(
                            title: "Sleep",
                            icon: "bed.double.fill",
                            color: .purple,
                            status: .connected
                        )
                        
                        HealthDataSourceRow(
                            title: "Heart Rate",
                            icon: "heart.fill",
                            color: .red,
                            status: .connected
                        )
                        
                        HealthDataSourceRow(
                            title: "Body Mass",
                            icon: "figure.arms.open",
                            color: .green,
                            status: .connected
                        )
                    }
                }
                
                Section("Manual Data Entry") {
                    NavigationLink("Log Weight") {
                        WeightEntryView(profile: profile)
                    }
                    
                    NavigationLink("Log Sleep") {
                        SleepEntryView(profile: profile)
                    }
                    
                    NavigationLink("Log Workout") {
                        WorkoutEntryView(profile: profile)
                    }
                }
                
                Section("Privacy") {
                    NavigationLink("Data Usage") {
                        DataUsageView()
                    }
                    
                    Button("Revoke Health Access") {
                        showingPermissions = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Health Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Revoke Health Access", isPresented: $showingPermissions) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To revoke health data access, please use the Settings app under Privacy & Security > Health.")
        }
    }
}

struct HealthDataSourceRow: View {
    let title: String
    let icon: String
    let color: Color
    let status: DataSourceStatus
    
    enum DataSourceStatus {
        case connected, limited, disconnected
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .limited: return .orange
            case .disconnected: return .red
            }
        }
        
        var text: String {
            switch self {
            case .connected: return "Connected"
            case .limited: return "Limited"
            case .disconnected: return "Not Connected"
            }
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                
                Text(status.text)
                    .font(.caption)
                    .foregroundColor(status.color)
            }
        }
    }
}

// MARK: - Manual Entry Views

struct WeightEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: Profile
    @State private var weight: Double
    @State private var date = Date()
    
    init(profile: Profile) {
        self.profile = profile
        _weight = State(initialValue: profile.weight)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Weight Entry") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("Weight", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("kg")
                    }
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveWeight()
                    }
                }
            }
        }
    }
    
    private func saveWeight() {
        profile.weight = weight
        do {
            try modelContext.save()
        } catch {
            print("Failed to save weight entry: \(error)")
        }
        NotificationCenter.default.post(name: .profileDidSave, object: nil)
        // BMI is automatically recalculated as it's a computed property
        dismiss()
    }
}

struct SleepEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: Profile
    @State private var bedtime = Date()
    @State private var wakeTime = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep Entry") {
                    DatePicker("Bedtime", selection: $bedtime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Wake Time", selection: $wakeTime, displayedComponents: [.date, .hourAndMinute])
                    
                    HStack {
                        Text("Sleep Duration")
                        Spacer()
                        Text("\(sleepDuration, specifier: "%.1f") hours")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Log Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSleep()
                    }
                }
            }
        }
    }
    
    private var sleepDuration: Double {
        let duration = wakeTime.timeIntervalSince(bedtime)
        return max(0, duration / 3600) // Convert to hours
    }
    
    private func saveSleep() {
        profile.sleepHours = sleepDuration
        do {
            try modelContext.save()
        } catch {
            print("Failed to save sleep entry: \(error)")
        }
        NotificationCenter.default.post(name: .profileDidSave, object: nil)
        dismiss()
    }
}

struct WorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: Profile
    @State private var workoutType = "Strength Training"
    @State private var duration: Int = 30
    @State private var intensity = "Moderate"
    @State private var date = Date()
    
    let workoutTypes = ["Strength Training", "Cardio", "Yoga", "Running", "Cycling", "Swimming", "Other"]
    let intensityLevels = ["Light", "Moderate", "Vigorous"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Details") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    
                    Picker("Workout Type", selection: $workoutType) {
                        ForEach(workoutTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("Minutes", value: $duration, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                    }
                    
                    Picker("Intensity", selection: $intensity) {
                        ForEach(intensityLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveWorkout()
                    }
                }
            }
        }
    }
    
    private func saveWorkout() {
        profile.lastWorkoutTime = date
        profile.weeklyWorkoutMinutes += duration

        // Apply stat bonuses based on workout type and intensity
        let baseBonus = intensity == "Light" ? 1.0 : intensity == "Moderate" ? 2.0 : 3.0

        if workoutType.contains("Strength") || workoutType.contains("Training") {
            profile.adjustStat(\.strength, by: baseBonus)
        }
        if workoutType.contains("Cardio") || workoutType.contains("Running") || workoutType.contains("Cycling") {
            profile.adjustStat(\.endurance, by: baseBonus)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save workout entry: \(error)")
        }
        NotificationCenter.default.post(name: .profileDidSave, object: nil)

        dismiss()
    }
}

struct DataUsageView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How We Use Your Health Data")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 12) {
                    DataUsageItem(
                        icon: "chart.bar.fill",
                        title: "Progress Tracking",
                        description: "We use your health data to calculate RPG stats and track your real-world progress."
                    )
                    
                    DataUsageItem(
                        icon: "target",
                        title: "Goal Achievement",
                        description: "Health metrics help determine quest completion and reward calculation."
                    )
                    
                    DataUsageItem(
                        icon: "shield.fill",
                        title: "Privacy Protection",
                        description: "All health data stays on your device. We never share or upload your personal health information."
                    )
                    
                    DataUsageItem(
                        icon: "cpu.fill",
                        title: "Local Processing",
                        description: "Health data processing happens entirely on your device for maximum privacy and security."
                    )
                }
                
                Text("Data Types We Access")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Step count and walking distance")
                    Text("• Active calories burned")
                    Text("• Sleep analysis")
                    Text("• Heart rate and HRV")
                    Text("• Body measurements (weight, height, BMI)")
                    Text("• Workout sessions")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Data Usage")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(nil)
    }
}

struct DataUsageItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

extension Notification.Name {
    static let profileDidSave = Notification.Name("ProfileDidSaveNotification")
}

#Preview {
    ProfileEditorView(profile: Profile())
}
