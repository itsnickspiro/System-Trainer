import SwiftUI
import SwiftData

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var showingPermissions = false
    @Binding var isOnboardingComplete: Bool
    
    let pages = OnboardingPage.allPages
    
    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [.black, .gray.opacity(0.8), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated particles
            ForEach(0..<20, id: \.self) { index in
                Circle()
                    .fill(.cyan.opacity(0.1))
                    .frame(width: .random(in: 2...6), height: .random(in: 2...6))
                    .offset(
                        x: .random(in: -200...200),
                        y: .random(in: -400...400)
                    )
                    .animation(
                        .linear(duration: .random(in: 3...8))
                        .repeatForever(autoreverses: false),
                        value: currentPage
                    )
            }
            
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            VStack {
                Spacer()
                
                // Custom page indicator
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? .cyan : .gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .scaleEffect(index == currentPage ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 30)
                
                // Action buttons
                HStack(spacing: 20) {
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut) {
                                currentPage -= 1
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    if currentPage < pages.count - 1 {
                        Button("Next") {
                            withAnimation(.easeInOut) {
                                currentPage += 1
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Get Started") {
                            showingPermissions = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingPermissions) {
            PermissionRequestView(isOnboardingComplete: $isOnboardingComplete)
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon with animation
            ZStack {
                Circle()
                    .fill(page.accentColor.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(animateIcon ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)
                
                Image(systemName: page.icon)
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(page.accentColor)
                    .scaleEffect(animateIcon ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)
            }
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .padding(.horizontal, 30)
            
            // Feature highlights
            if !page.features.isEmpty {
                VStack(spacing: 12) {
                    ForEach(page.features, id: \.self) { feature in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(page.accentColor)
                            Text(feature)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 30)
            }
            
            Spacer()
            Spacer()
        }
        .onAppear {
            animateIcon = true
        }
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let icon: String
    let accentColor: Color
    let features: [String]
    
    static let allPages = [
        OnboardingPage(
            title: "Welcome to RPT",
            description: "Transform your daily life into an epic adventure. Complete real-world quests, level up, and become the hero of your own story.",
            icon: "star.fill",
            accentColor: .yellow,
            features: [
                "Turn habits into quests",
                "Level up with real progress",
                "Track your epic journey"
            ]
        ),
        
        OnboardingPage(
            title: "Complete Daily Quests",
            description: "Every day brings new challenges. From workouts to healthy meals, turn your goals into exciting missions.",
            icon: "target",
            accentColor: .orange,
            features: [
                "Personalized daily challenges",
                "Streak-based rewards",
                "Custom quest creation"
            ]
        ),
        
        OnboardingPage(
            title: "Level Up Your Stats",
            description: "Your real-world activities boost your RPG stats. Exercise increases Strength, meditation improves Focus.",
            icon: "chart.bar.fill",
            accentColor: .blue,
            features: [
                "6 core attributes to develop",
                "Real health data integration",
                "Visible progress tracking"
            ]
        ),
        
        OnboardingPage(
            title: "Health Integration",
            description: "Connect with Apple Health to automatically track your progress and earn XP for healthy activities.",
            icon: "heart.fill",
            accentColor: .red,
            features: [
                "Automatic step tracking",
                "Sleep quality monitoring",
                "Heart rate analysis"
            ]
        ),
        
        OnboardingPage(
            title: "Stay Motivated",
            description: "Your AI coach provides guidance, celebrates victories, and helps you stay on track with your goals.",
            icon: "brain.head.profile",
            accentColor: .purple,
            features: [
                "Personalized coaching",
                "Smart notifications",
                "Progress celebrations"
            ]
        ),
        
        OnboardingPage(
            title: "Begin Your Journey",
            description: "Ready to transform your life into an adventure? Let's set up your profile and start your epic quest.",
            icon: "figure.walk",
            accentColor: .green,
            features: []
        )
    ]
}

struct PermissionRequestView: View {
    @Binding var isOnboardingComplete: Bool
    @Environment(\.modelContext) private var modelContext
    @StateObject private var healthManager = HealthManager()
    @StateObject private var notificationManager = NotificationManager()
    @State private var currentStep = 0
    @State private var profileName = ""
    @State private var selectedGoal: FitnessGoal = .generalHealth
    @State private var selectedGender: PlayerGender = .male
    @State private var selectedGym: GymEnvironment = .fullGym
    @State private var ageText: String = "25"
    @State private var heightText: String = "170"
    @State private var weightText: String = "70"
    @State private var activityLevelIndex: Int = 1

    let steps = PermissionStep.allSteps
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Progress indicator
                ProgressView(value: Double(currentStep + 1), total: Double(steps.count))
                    .tint(.cyan)
                    .padding(.horizontal)
                
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Current step content
                PermissionStepView(
                    step: steps[currentStep],
                    healthManager: healthManager,
                    notificationManager: notificationManager,
                    profileName: $profileName,
                    selectedGoal: $selectedGoal,
                    selectedGender: $selectedGender,
                    selectedGym: $selectedGym,
                    ageText: $ageText,
                    heightText: $heightText,
                    weightText: $weightText,
                    activityLevelIndex: $activityLevelIndex
                )
                
                Spacer()
                
                // Navigation buttons
                HStack(spacing: 20) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut) {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    if currentStep < steps.count - 1 {
                        Button(steps[currentStep].buttonTitle) {
                            handleStepAction()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Complete Setup") {
                            completeOnboarding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        isOnboardingComplete = true
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func handleStepAction() {
        switch steps[currentStep].type {
        case .profile, .goal, .demographics, .gymEnvironment:
            // Input steps are handled by their UI controls; nothing to do here
            break
        case .health:
            Task {
                await healthManager.requestAuthorization()
            }
        case .notifications:
            Task {
                await notificationManager.requestAuthorization()
            }
        case .complete:
            break
        }
        
        withAnimation(.easeInOut) {
            currentStep += 1
        }
    }
    
    private func completeOnboarding() {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = Int(ageText) ?? 25
        let height = Double(heightText) ?? 170.0
        let weight = Double(weightText) ?? 70.0

        // Write the profile into SwiftData so every view that reads Profile fields
        // shows the player's real info instead of defaults.
        // Fetch any existing profile first to avoid creating duplicates on re-runs.
        let existing = try? modelContext.fetch(FetchDescriptor<Profile>())
        let profile: Profile
        if let existing = existing?.first {
            profile = existing
        } else {
            profile = Profile()
            modelContext.insert(profile)
        }
        if !trimmedName.isEmpty { profile.name = trimmedName }
        profile.fitnessGoal        = selectedGoal
        profile.gender             = selectedGender
        profile.gymEnvironment     = selectedGym
        profile.age                = age
        profile.height             = height
        profile.weight             = weight
        profile.activityLevelIndex = activityLevelIndex
        try? modelContext.save()

        // Keep UserDefaults in sync for any legacy reads
        if !trimmedName.isEmpty {
            UserDefaults.standard.set(trimmedName, forKey: "userProfileName")
        }

        // Configure notifications if authorized
        if notificationManager.isAuthorized {
            notificationManager.configureRecurringNotifications()
            notificationManager.setupNotificationCategories()
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboardingComplete = true
    }
}

struct PermissionStepView: View {
    let step: PermissionStep
    @ObservedObject var healthManager: HealthManager
    @ObservedObject var notificationManager: NotificationManager
    @Binding var profileName: String
    @Binding var selectedGoal: FitnessGoal
    @Binding var selectedGender: PlayerGender
    @Binding var selectedGym: GymEnvironment
    @Binding var ageText: String
    @Binding var heightText: String
    @Binding var weightText: String
    @Binding var activityLevelIndex: Int

    private let activityLabels = ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active"]

    /// Live TDEE estimate shown in the demographics step
    private var estimatedCalories: Int {
        let age = Double(Int(ageText) ?? 25)
        let h = Double(Double(heightText) ?? 170)
        let w = Double(Double(weightText) ?? 70)
        let bmr: Double
        switch selectedGender {
        case .male:   bmr = 10 * w + 6.25 * h - 5 * age + 5
        case .female: bmr = 10 * w + 6.25 * h - 5 * age - 161
        default:      bmr = 10 * w + 6.25 * h - 5 * age - 78
        }
        let multipliers = [1.2, 1.375, 1.55, 1.725, 1.9]
        let tdee = bmr * multipliers[max(0, min(multipliers.count - 1, activityLevelIndex))]
        switch selectedGoal {
        case .loseFat:     return Int((tdee - 500).rounded())
        case .buildMuscle: return Int((tdee + 300).rounded())
        default:           return Int(tdee.rounded())
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: step.icon)
                .font(.system(size: 60, weight: .light))
                .foregroundColor(step.color)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .padding(.horizontal, 20)
            
            // Step-specific content
            switch step.type {
            case .profile:
                VStack(spacing: 16) {
                    TextField("Enter your name", text: $profileName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 250)
                    Text("We'll use this to personalize your experience")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .goal:
                VStack(spacing: 12) {
                    ForEach(FitnessGoal.allCases, id: \.self) { goal in
                        Button {
                            selectedGoal = goal
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: goal.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedGoal == goal ? .black : step.color)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.displayName)
                                        .font(.headline)
                                        .foregroundColor(selectedGoal == goal ? .black : .white)
                                    Text(goal.description)
                                        .font(.caption)
                                        .foregroundColor(selectedGoal == goal ? .black.opacity(0.7) : .gray)
                                }
                                Spacer()
                                if selectedGoal == goal {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedGoal == goal ? step.color : Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }

            case .demographics:
                VStack(spacing: 14) {
                    // Gender picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gender")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Picker("Gender", selection: $selectedGender) {
                            ForEach(PlayerGender.allCases, id: \.self) { g in
                                Text(g.displayName).tag(g)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    // Age / Height / Weight fields
                    HStack(spacing: 12) {
                        DemographicField(label: "Age", placeholder: "25", unit: "yrs", text: $ageText)
                        DemographicField(label: "Height", placeholder: "170", unit: "cm", text: $heightText)
                        DemographicField(label: "Weight", placeholder: "70", unit: "kg", text: $weightText)
                    }
                    .padding(.horizontal)

                    // Activity level picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Activity Level")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Picker("Activity Level", selection: $activityLevelIndex) {
                            ForEach(activityLabels.indices, id: \.self) { i in
                                Text(activityLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal)
                        .tint(.cyan)
                    }

                    // Live calorie goal preview
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("Daily calorie goal: \(estimatedCalories) kcal")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

            case .gymEnvironment:
                VStack(spacing: 10) {
                    ForEach(GymEnvironment.allCases, id: \.self) { env in
                        Button {
                            selectedGym = env
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: env.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedGym == env ? .black : step.color)
                                    .frame(width: 28)
                                Text(env.displayName)
                                    .font(.headline)
                                    .foregroundColor(selectedGym == env ? .black : .white)
                                Spacer()
                                if selectedGym == env {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedGym == env ? step.color : Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                
            case .health:
                VStack(spacing: 14) {
                    if healthManager.isAuthorized {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Synced to the Training Grid!")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                        Text("Your biometrics are now feeding live data into your quest engine. Steps, sleep, and active calories will auto-complete matching quests.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if !healthManager.healthDataAvailable {
                        VStack(spacing: 8) {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("Training Grid Offline")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("Apple Health isn't available on this device. You can still log workouts and nutrition manually — your progress counts either way.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                Text("Unlock passive XP gains")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(.cyan)
                                Text("Auto-complete step & sleep quests")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("Real calorie burn drives real rewards")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Text("Your data stays private — RPT only reads, never writes to Apple Health.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                
            case .notifications:
                VStack(spacing: 12) {
                    if notificationManager.isAuthorized {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Notifications enabled!")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text("Get reminded about quests and celebrate your achievements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
            case .complete:
                VStack(spacing: 16) {
                    Text("🎉")
                        .font(.system(size: 50))
                    
                    Text("You're all set! Your adventure begins now.")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

struct PermissionStep {
    enum StepType {
        case profile, goal, demographics, gymEnvironment, health, notifications, complete
    }
    
    let type: StepType
    let title: String
    let description: String
    let icon: String
    let color: Color
    let buttonTitle: String
    
    static let allSteps = [
        PermissionStep(
            type: .profile,
            title: "Create Your Profile",
            description: "Let's personalize your RPG experience with your name.",
            icon: "person.circle.fill",
            color: .blue,
            buttonTitle: "Continue"
        ),
        PermissionStep(
            type: .goal,
            title: "What's Your Goal?",
            description: "We'll tailor your quests and program to match your fitness mission.",
            icon: "target",
            color: .orange,
            buttonTitle: "Continue"
        ),
        PermissionStep(
            type: .demographics,
            title: "Your Body Stats",
            description: "Used to personalise quest intensity, calorie targets and strength benchmarks.",
            icon: "person.text.rectangle.fill",
            color: .cyan,
            buttonTitle: "Continue"
        ),
        PermissionStep(
            type: .gymEnvironment,
            title: "Where Do You Train?",
            description: "Your training environment shapes which exercises and programs are right for you.",
            icon: "building.2.fill",
            color: .purple,
            buttonTitle: "Continue"
        ),
        PermissionStep(
            type: .health,
            title: "Connect to the Training Grid",
            description: "Sync Apple Health so every step, rep, and hour of sleep earns real XP. Quests auto-complete when your body does the work.",
            icon: "sensor.tag.radiowaves.forward.fill",
            color: .red,
            buttonTitle: "Sync the Grid"
        ),
        PermissionStep(
            type: .notifications,
            title: "Enable Notifications",
            description: "Stay motivated with quest reminders and achievement celebrations.",
            icon: "bell.circle.fill",
            color: .orange,
            buttonTitle: "Enable Notifications"
        ),
        PermissionStep(
            type: .complete,
            title: "Ready to Begin!",
            description: "Your RPG life transformation starts now. Complete your first quest to earn XP!",
            icon: "flag.checkered.circle.fill",
            color: .green,
            buttonTitle: "Start Adventure"
        )
    ]
}

// MARK: - Custom Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.black)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.cyan)
                    .shadow(color: .cyan.opacity(0.5), radius: 10, x: 0, y: 5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .stroke(.gray, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Demographic input field helper
private struct DemographicField: View {
    let label: String
    let placeholder: String
    let unit: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}