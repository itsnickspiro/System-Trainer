import SwiftUI
import SwiftData
import AuthenticationServices

// MARK: - OnboardingView
//
// Unified onboarding flow. All collected state lives here; sub-views
// receive only the bindings they need.
//
// Steps (current — 13 logical positions, 12 user-visible):
//  0  — Boot / Welcome     (no progress bar — own SIWA button)
//  1  — Name
//  2  — Biological Sex
//  3  — Basics (age + height + weight on one screen)
//  4  — Fitness Goal
//  5  — Player Class
//  6  — Diet Preference
//  7  — Workout Plan  (anime plans filtered by gender + goal, or Build-my-own)
//  8  — Goal Survey Gate (only shown if Build-my-own was chosen)
//  9  — Avatar Picker  (required)
//  10 — HealthKit          (required)
//  11 — Notifications      (skippable)
//  12 — Ready Screen       (no progress bar — own "Enter the System" button)
//
// ATT (App Tracking Transparency) was previously at step 12 but is removed
// because the codebase doesn't use the IDFA — requesting tracking permission
// without consuming it is grounds for App Review rejection per
// Guideline 5.1.2.

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @Environment(\.modelContext) private var modelContext

    // ── Collected state ───────────────────────────────────────────────────────
    @State private var currentStep = 0

    @State private var profileName         = ""
    @State private var selectedGender: PlayerGender    = .male
    @State private var selectedGoal: FitnessGoal       = .generalHealth
    @State private var selectedDietType: DietType      = .none
    @State private var selectedClass: PlayerClass      = .unselected
    @State private var ageText             = "25"
    @State private var heightText          = "170"   // always stored in cm internally
    @State private var weightText          = "70"    // always stored in kg internally
    @State private var activityLevelIndex  = 1
    @State private var selectedAvatarKey: String?      = nil
    @State private var selectedPlanID: String?         = nil   // nil = skip / custom
    @State private var useMetric: Bool = (Locale.current.measurementSystem == .metric)
    /// Set to true when the user picks "Build my own plan" on the plan step.
    /// Controls whether step 6 (the Goal Survey gate) is shown.
    @State private var isBuildingCustomPlan: Bool = false
    /// Tracks whether the in-memory profile has had its goal survey completed.
    /// Bound against the actual Profile model so step 6 Continue can enable.
    @State private var goalSurveyCompleted: Bool = false

    /// True while a permission-fetching Task is in flight on the current step.
    /// Used to disable the Continue button so a fast double-tap can't spawn
    /// two concurrent permission requests / step advances.
    @State private var isAdvancing: Bool = false

    // ── Services ──────────────────────────────────────────────────────────────
    @StateObject private var healthManager       = HealthManager()
    @StateObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var avatarService    = AvatarService.shared

    // ── Step configuration ────────────────────────────────────────────────────
    private let totalProgressSteps = 12  // logical progress denominator (1–11 visible + Ready)
    private let skippableSteps: Set<Int> = [11]  // Only Notifications is optional; HealthKit (10) and Avatar (9) are required
    private let noProgressBarSteps: Set<Int> = [0, 12]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (hidden on boot and ready screens)
                if !noProgressBarSteps.contains(currentStep) {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                // Step content
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)

                // Navigation buttons (hidden on boot and ready screens)
                if !noProgressBarSteps.contains(currentStep) {
                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Back chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        currentStep = max(1, currentStep - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentStep <= 1 ? .clear : .white.opacity(0.7))
                }
                .disabled(currentStep <= 1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.cyan)
                            .frame(
                                width: geo.size.width * progressFraction,
                                height: 4
                            )
                            .animation(.easeInOut(duration: 0.4), value: currentStep)
                    }
                }
                .frame(height: 4)

                Text("\(currentStep)/\(totalProgressSteps)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(height: 32)
        }
    }

    private var progressFraction: CGFloat {
        guard currentStep > 0 else { return 0 }
        return CGFloat(currentStep) / CGFloat(totalProgressSteps)
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:  BootStepView(
                     // Existing user — cloud profile fully restored, skip
                     // onboarding entirely.
                     onExistingUserRecovered: {
                         UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                         isOnboardingComplete = true
                     },
                     // New user OR existing-but-incomplete — pre-fill any
                     // recovered fields and advance to step 1 so they
                     // complete the rest of onboarding normally.
                     onNewUserSignedIn: {
                         if let p = DataManager.shared.currentProfile {
                             profileName    = p.name
                             ageText        = p.age > 0 ? "\(p.age)" : ""
                             heightText     = p.height > 0 ? "\(Int(p.height))" : ""
                             weightText     = p.weight > 0 ? "\(Int(p.weight))" : ""
                             selectedGender = p.gender
                             selectedGoal   = p.fitnessGoal
                         }
                         withAnimation(.easeInOut(duration: 0.35)) { currentStep = 1 }
                     }
                 )
        case 1:  NameStepView(profileName: $profileName)
        case 2:  GenderStepView(selectedGender: $selectedGender)
        case 3:  BodyStatsStepView(
                    ageText: $ageText,
                    heightText: $heightText,
                    weightText: $weightText,
                    activityLevelIndex: $activityLevelIndex,
                    useMetric: $useMetric,
                    selectedGender: selectedGender,
                    selectedGoal: selectedGoal
                 )
        case 4:  GoalStepView(selectedGoal: $selectedGoal)
        case 5:  ClassSelectionStepView(selectedClass: $selectedClass)
        case 6:  DietPreferenceStepView(selectedDietType: $selectedDietType)
        case 7:  WorkoutPlanStepView(
                    selectedPlanID: $selectedPlanID,
                    isBuildingCustomPlan: $isBuildingCustomPlan,
                    playerGender: selectedGender,
                    playerGoal: selectedGoal
                 )
        case 8:  GoalSurveyGateStepView(
                    profileProvider: { ensureProfile() },
                    goalSurveyCompleted: $goalSurveyCompleted
                 )
        case 9:  AvatarPickerStepView(selectedAvatarKey: $selectedAvatarKey)
        case 10: HealthStepView(healthManager: healthManager)
        case 11: NotificationsStepView(notificationManager: notificationManager)
        case 12: ReadyStepView(
                    name: profileName,
                    goal: selectedGoal,
                    avatarKey: selectedAvatarKey ?? "avatar_default",
                    onContinue: { completeOnboarding() }
                 )
        default: EmptyView()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            // Continue / advance button. Notifications (step 11) is the
            // last step where the user taps Continue — the Ready screen
            // (step 12) is in noProgressBarSteps so its button is rendered
            // inline by ReadyStepView itself.
            Button(currentStep == 11 ? "Almost done" : "Continue") {
                handleAdvance()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(!canAdvance || isAdvancing)

            // Helper text when the goal survey gate blocks progression
            if currentStep == 8 && !goalSurveyCompleted {
                Text("Complete the goal survey to continue.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Skip button (optional steps only)
            if skippableSteps.contains(currentStep) {
                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        advanceFrom(currentStep)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Advance Logic

    private var canAdvance: Bool {
        switch currentStep {
        case 1: return !profileName.trimmingCharacters(in: .whitespaces).isEmpty
        case 8: return goalSurveyCompleted
        case 9: return selectedAvatarKey != nil
        default: return true
        }
    }

    /// Advances from `step`, skipping the Goal Survey Gate when the
    /// user didn't pick "Build my own plan".
    private func advanceFrom(_ step: Int) {
        var next = step + 1
        if next == 8 && !isBuildingCustomPlan {
            next = 9
        }
        currentStep = next
    }

    private func handleAdvance() {
        // Guard against double-tap on permission steps. Without this, a fast
        // double-tap on Continue can spawn two concurrent permission Tasks
        // and double-advance currentStep.
        guard !isAdvancing else { return }

        if currentStep == 0 {
            // Boot → Name
            withAnimation(.easeInOut(duration: 0.35)) { currentStep = 1 }
            return
        }

        // Permission steps: fire the system prompt before advancing so the
        // user always sees the standard iOS dialog when they tap Continue.
        // Each request is a no-op if the status has already been determined.
        switch currentStep {
        case 9:
            // Avatar picker (required). Persist selection before advancing.
            if let key = selectedAvatarKey {
                Task { await AvatarService.shared.setAvatar(key: key) }
            }
            withAnimation(.easeInOut(duration: 0.35)) { advanceFrom(9) }
            return
        case 10:
            // HealthKit (required). If the user denies, we still advance —
            // they'll see the inline "Open Settings" path on next entry.
            isAdvancing = true
            Task { @MainActor in
                if !healthManager.isAuthorized {
                    await healthManager.requestAuthorization()
                }
                isAdvancing = false
                withAnimation(.easeInOut(duration: 0.35)) { advanceFrom(10) }
            }
            return
        case 11:
            isAdvancing = true
            Task { @MainActor in
                if notificationManager.authorizationStatus == .notDetermined {
                    await notificationManager.requestAuthorization()
                }
                isAdvancing = false
                withAnimation(.easeInOut(duration: 0.35)) { advanceFrom(11) }
            }
            return
        default:
            break
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            advanceFrom(currentStep)
        }
    }

    /// Fetch-or-create the live Profile so step 6's survey sheet can mutate it.
    private func ensureProfile() -> Profile {
        let existing = try? modelContext.fetch(FetchDescriptor<Profile>())
        if let first = existing?.first { return first }
        let p = Profile()
        modelContext.insert(p)
        try? modelContext.save()
        return p
    }

    // MARK: - Complete Onboarding

    private func completeOnboarding() {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let age    = Int(ageText)    ?? 25
        let height = Double(heightText) ?? 170.0
        let weight = Double(weightText) ?? 70.0

        // Write to SwiftData Profile
        let existing = try? modelContext.fetch(FetchDescriptor<Profile>())
        let profile: Profile
        if let first = existing?.first {
            profile = first
        } else {
            profile = Profile()
            modelContext.insert(profile)
        }
        if !trimmedName.isEmpty { profile.name = trimmedName }
        profile.fitnessGoal        = selectedGoal
        profile.dietType           = selectedDietType
        profile.playerClass        = selectedClass
        profile.gender             = selectedGender
        profile.age                = age
        profile.height             = height   // stored in cm
        profile.weight             = weight   // stored in kg
        profile.useMetric          = useMetric
        profile.activityLevelIndex = activityLevelIndex
        if isBuildingCustomPlan {
            // Leave the "custom_pending" (or whatever the survey set) sentinel in place.
            if (profile.activePlanID ?? "").isEmpty {
                profile.activePlanID = "custom_pending"
            }
        } else if let planID = selectedPlanID, !planID.isEmpty {
            profile.activePlanID = planID
        } else {
            profile.activePlanID = ""
        }
        try? modelContext.save()

        // UserDefaults sync
        if !trimmedName.isEmpty {
            UserDefaults.standard.set(trimmedName, forKey: "userProfileName")
        }

        // Notifications
        if notificationManager.isAuthorized {
            notificationManager.configureRecurringNotifications()
            notificationManager.setupNotificationCategories()
        }

        // Avatar selection (async, fire-and-forget)
        if let key = selectedAvatarKey {
            Task { await AvatarService.shared.setAvatar(key: key) }
        }

        // Kick off profile sync
        Task { await PlayerProfileService.shared.refresh() }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboardingComplete = true
    }
}

// MARK: - Step 0: Boot / Welcome

private struct BootStepView: View {
    /// Called when SIWA succeeds AND the cloud profile is fully restored —
    /// the BootStepView's parent skips the rest of onboarding entirely.
    var onExistingUserRecovered: () -> Void = {}

    /// Called when SIWA succeeds but the user is brand new (no cloud profile)
    /// OR existing-but-incomplete. The parent advances to the next onboarding
    /// step, optionally pre-filled with whatever was recovered.
    var onNewUserSignedIn: () -> Void = {}

    @State private var pulse = false
    @State private var glowOpacity: Double = 0.3
    @State private var isAuthenticating = false
    @State private var authError: String? = nil

    var body: some View {
        ZStack {
            // Glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.cyan.opacity(glowOpacity - Double(i) * 0.08), lineWidth: 1)
                    .frame(width: CGFloat(180 + i * 60), height: CGFloat(180 + i * 60))
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .animation(
                        .easeInOut(duration: 2.4 + Double(i) * 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.3),
                        value: pulse
                    )
            }

            VStack(spacing: 0) {
                Spacer()

                // Title block
                VStack(spacing: 16) {
                    Text("SYSTEM TRAINER")
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .cyan.opacity(0.7), radius: 20)
                        .multilineTextAlignment(.center)

                    Text("TRAIN. LEVEL UP. ASCEND.")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                        .tracking(4)
                }

                Spacer()

                // Sign in with Apple — the ONLY way into the app right now.
                // The BEGIN button is gone. Identity protection is mandatory.
                VStack(spacing: 14) {
                    if isAuthenticating {
                        HStack(spacing: 10) {
                            ProgressView().tint(.cyan)
                            Text("Linking your account…")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                                .tracking(1)
                        }
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        SignInWithAppleButtonView(label: .signIn) { result in
                            guard let result else { return }
                            Task { await handleSignIn(result) }
                        }
                        .frame(height: 50)
                    }

                    if let err = authError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Sign in with Apple is required to begin. We use your Apple ID to keep your progress safe across devices — no email, no password.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }

    /// Handle a successful Apple credential. Two outcomes:
    ///   1. Cloud profile is fully populated (existing user, cross-device
    ///      recovery) → onExistingUserRecovered() — parent skips onboarding
    ///   2. Cloud profile is missing or incomplete (brand new user, OR
    ///      existing user whose cloud row is empty from the silent-drop
    ///      bug period) → onNewUserSignedIn() — parent pre-fills what
    ///      was recovered and advances to step 1
    @MainActor
    private func handleSignIn(_ result: AppleSignInResult) async {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        let success = await PlayerProfileService.shared.linkAppleID(
            appleUserID: result.userID,
            displayName: result.displayName
        )
        guard success else {
            authError = "Couldn't sign in with Apple. Check your connection and try again."
            return
        }

        // Give the hydration a beat to settle
        try? await Task.sleep(for: .seconds(0.5))

        if let profile = DataManager.shared.currentProfile,
           !profile.name.isEmpty,
           profile.age > 0,
           profile.height > 0,
           profile.weight > 0 {
            onExistingUserRecovered()
        } else {
            onNewUserSignedIn()
        }
    }
}

// MARK: - Step 1: Name

private struct NameStepView: View {
    @Binding var profileName: String
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingStepShell(
            icon: "person.circle.fill",
            iconColor: .cyan,
            title: "What should we\ncall you, Warrior?",
            subtitle: "Your identity in the system."
        ) {
            VStack(spacing: 8) {
                TextField("Enter your name", text: $profileName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(focused ? Color.cyan : Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .focused($focused)
                    .submitLabel(.continue)
                    .frame(maxWidth: 320)

                if profileName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Required to continue")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.7))
                }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Step 2: Biological Sex

private struct GenderStepView: View {
    @Binding var selectedGender: PlayerGender

    var body: some View {
        OnboardingStepShell(
            icon: "person.2.fill",
            iconColor: .purple,
            title: "Choose Your Fighter",
            subtitle: "Used to personalise training benchmarks and calorie targets."
        ) {
            HStack(spacing: 16) {
                GenderCard(
                    icon: "figure.stand",
                    label: "Male",
                    isSelected: selectedGender == .male,
                    color: .blue
                ) { selectedGender = .male }

                GenderCard(
                    icon: "figure.stand.dress",
                    label: "Female",
                    isSelected: selectedGender == .female,
                    color: .pink
                ) { selectedGender = .female }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct GenderCard: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(isSelected ? color : .white.opacity(0.5))
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? color.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? color : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 12)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: Fitness Goal

private struct GoalStepView: View {
    @Binding var selectedGoal: FitnessGoal

    var body: some View {
        OnboardingStepShell(
            icon: "target",
            iconColor: .orange,
            title: "Your Primary Mission",
            subtitle: "Shapes your quest difficulty and daily targets."
        ) {
            VStack(spacing: 10) {
                ForEach(FitnessGoal.allCases, id: \.self) { goal in
                    GoalCard(goal: goal, isSelected: selectedGoal == goal) {
                        selectedGoal = goal
                    }
                }
            }
        }
    }
}

private struct GoalCard: View {
    let goal: FitnessGoal
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        switch goal {
        case .loseFat:      return .orange
        case .buildMuscle:  return .blue
        case .endurance:    return .green
        case .generalHealth: return .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: goal.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.5))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(goal.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Diet Preference

private struct DietPreferenceStepView: View {
    @Binding var selectedDietType: DietType

    var body: some View {
        OnboardingStepShell(
            icon: "leaf.fill",
            iconColor: .green,
            title: "What's your eating style?",
            subtitle: "Pick the diet that fits you. We'll flag foods that don't match it."
        ) {
            VStack(spacing: 10) {
                ForEach(DietType.allCases, id: \.self) { diet in
                    DietCard(diet: diet, isSelected: selectedDietType == diet) {
                        selectedDietType = diet
                    }
                }
                Text("You can change this anytime in Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 6)
            }
        }
    }
}

private struct DietCard: View {
    let diet: DietType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: diet.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.5))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(diet.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(diet.tagline)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.cyan : Color.white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Class Selection

private struct ClassSelectionStepView: View {
    @Binding var selectedClass: PlayerClass

    private let classes: [PlayerClass] = [.warrior, .ranger, .monk, .sage]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "shield.lefthalf.filled",
            iconColor: .cyan,
            title: "Choose your path",
            subtitle: "Your class shapes how you grow. You can change it later in Settings."
        ) {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(classes) { pc in
                        ClassCard(
                            playerClass: pc,
                            isSelected: selectedClass == pc
                        ) {
                            selectedClass = (selectedClass == pc) ? .unselected : pc
                        }
                    }
                }

                if selectedClass != .unselected {
                    Text(selectedClass.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .transition(.opacity)
                } else {
                    Text("Optional — pick one for a 10% XP bonus on matching quests.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedClass)
        }
    }
}

private struct ClassCard: View {
    let playerClass: PlayerClass
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        switch playerClass.color {
        case "red":    return .red
        case "green":  return .green
        case "purple": return .purple
        case "cyan":   return .cyan
        default:       return .gray
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: playerClass.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.55))
                    .frame(height: 36)

                Text(playerClass.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Text(playerClass.tagline)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? accentColor.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? accentColor : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Body Stats

private struct BodyStatsStepView: View {
    @Binding var ageText: String
    @Binding var heightText: String   // always cm internally
    @Binding var weightText: String   // always kg internally
    @Binding var activityLevelIndex: Int
    @Binding var useMetric: Bool
    let selectedGender: PlayerGender
    let selectedGoal: FitnessGoal

    // Imperial display fields — derived from/converted to the metric bindings
    @State private var ftText: String = "5"
    @State private var inText: String = "7"
    @State private var lbsText: String = "154"

    private let activityOptions: [(label: String, icon: String, subtitle: String)] = [
        ("Sedentary",         "sofa.fill",          "Little to no exercise"),
        ("Lightly Active",    "figure.walk",         "1–3 days/week"),
        ("Moderately Active", "figure.run",          "3–5 days/week"),
        ("Very Active",       "figure.hiking",       "6–7 days/week"),
        ("Extremely Active",  "bolt.heart.fill",     "Physical job or 2× training")
    ]

    private var estimatedCalories: Int {
        let age = Double(Int(ageText) ?? 25)
        let h   = Double(Double(heightText) ?? 170)
        let w   = Double(Double(weightText) ?? 70)
        let bmr: Double
        switch selectedGender {
        case .male:   bmr = 10 * w + 6.25 * h - 5 * age + 5
        case .female: bmr = 10 * w + 6.25 * h - 5 * age - 161
        default:      bmr = 10 * w + 6.25 * h - 5 * age - 78
        }
        let multipliers = [1.2, 1.375, 1.55, 1.725, 1.9]
        let idx  = max(0, min(multipliers.count - 1, activityLevelIndex))
        let tdee = bmr * multipliers[idx]
        switch selectedGoal {
        case .loseFat:      return Int((tdee - 500).rounded())
        case .buildMuscle:  return Int((tdee + 300).rounded())
        default:            return Int(tdee.rounded())
        }
    }

    // Sync imperial fields from metric bindings when switching to imperial
    private func populateImperialFromMetric() {
        let cm = Double(heightText) ?? 170.0
        let totalInches = cm / 2.54
        ftText = "\(Int(totalInches / 12))"
        inText = "\(Int(totalInches.truncatingRemainder(dividingBy: 12)))"
        let kg = Double(weightText) ?? 70.0
        lbsText = String(format: "%.0f", kg * 2.20462)
    }

    // Write imperial fields back to metric bindings
    private func commitImperialToMetric() {
        let ft = Double(ftText) ?? 5
        let inches = Double(inText) ?? 7
        let totalCm = (ft * 12 + inches) * 2.54
        heightText = String(format: "%.0f", totalCm)
        let lbs = Double(lbsText) ?? 154
        weightText = String(format: "%.1f", lbs / 2.20462)
    }

    var body: some View {
        OnboardingStepShell(
            icon: "person.text.rectangle.fill",
            iconColor: .cyan,
            title: "Calibrate Your System",
            subtitle: "Used to calculate your calorie target and quest intensity."
        ) {
            VStack(spacing: 14) {
                // Unit toggle
                Picker("Units", selection: $useMetric) {
                    Text("Imperial").tag(false)
                    Text("Metric").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: useMetric) { _, isMetric in
                    if !isMetric {
                        populateImperialFromMetric()
                    } else {
                        commitImperialToMetric()
                    }
                }

                // Age / Height / Weight
                if useMetric {
                    HStack(spacing: 12) {
                        StatField(label: "AGE", placeholder: "25", unit: "yrs", text: $ageText)
                        StatField(label: "HEIGHT", placeholder: "170", unit: "cm", text: $heightText)
                        StatField(label: "WEIGHT", placeholder: "70", unit: "kg", text: $weightText)
                    }
                } else {
                    HStack(spacing: 12) {
                        StatField(label: "AGE", placeholder: "25", unit: "yrs", text: $ageText)
                        StatField(label: "FT", placeholder: "5", unit: "ft", text: $ftText)
                            .onChange(of: ftText) { _, _ in commitImperialToMetric() }
                        StatField(label: "IN", placeholder: "7", unit: "in", text: $inText)
                            .onChange(of: inText) { _, _ in commitImperialToMetric() }
                        StatField(label: "WEIGHT", placeholder: "154", unit: "lbs", text: $lbsText)
                            .onChange(of: lbsText) { _, _ in commitImperialToMetric() }
                    }
                }

                // Activity level cards
                VStack(alignment: .leading, spacing: 6) {
                    Text("ACTIVITY LEVEL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.leading, 2)

                    ForEach(activityOptions.indices, id: \.self) { i in
                        let opt = activityOptions[i]
                        Button { activityLevelIndex = i } label: {
                            HStack(spacing: 12) {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(activityLevelIndex == i ? .cyan : .white.opacity(0.4))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(opt.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(opt.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                                Spacer()
                                if activityLevelIndex == i {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.cyan)
                                        .font(.system(size: 16))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(activityLevelIndex == i ? Color.cyan.opacity(0.1) : Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(activityLevelIndex == i ? Color.cyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: activityLevelIndex)
                    }
                }

                // Live TDEE estimate
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Daily calorie target: \(estimatedCalories) kcal")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: estimatedCalories)
            }
        }
    }
}

private struct StatField: View {
    let label: String
    let placeholder: String
    let unit: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            VStack(spacing: 2) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.07))
                    )

                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 9: Avatar Picker (Onboarding)

private struct AvatarPickerStepView: View {
    @Binding var selectedAvatarKey: String?
    @ObservedObject private var avatarService = AvatarService.shared

    private var avatars: [AvatarTemplate] {
        avatarService.catalog
    }

    var body: some View {
        OnboardingStepShell(
            icon: "person.crop.circle.badge.checkmark",
            iconColor: .cyan,
            title: "Choose your avatar",
            subtitle: "This represents you across the app — on Home, in guilds, on the leaderboard.",
            isSkippable: false
        ) {
            VStack(spacing: 16) {
                if avatars.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 70)
                        }
                    }
                    Text("Loading avatars…")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(1)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(avatars) { avatar in
                            AvatarCell(avatar: avatar,
                                       isSelected: selectedAvatarKey == avatar.key) {
                                selectedAvatarKey = avatar.key
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill if already equipped
            if selectedAvatarKey == nil, let current = avatarService.current {
                selectedAvatarKey = current.key
            }
            if avatars.isEmpty {
                Task { await avatarService.refresh() }
            }
        }
    }
}

// MARK: - Step 5: Avatar Selection (legacy unused)

private struct AvatarStepView: View {
    @Binding var selectedAvatarKey: String?
    @ObservedObject private var avatarService = AvatarService.shared

    private var displayAvatars: [AvatarTemplate] {
        Array(avatarService.catalog.prefix(8))
    }

    var body: some View {
        OnboardingStepShell(
            icon: "person.crop.circle.badge.plus",
            iconColor: .cyan,
            title: "Choose Your Warrior",
            subtitle: "Your avatar represents you in the system.",
            isSkippable: true
        ) {
            VStack(spacing: 16) {
                if displayAvatars.isEmpty {
                    // Catalog not loaded yet — show placeholder grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 70)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(displayAvatars) { avatar in
                            AvatarCell(avatar: avatar,
                                       isSelected: selectedAvatarKey == avatar.key) {
                                selectedAvatarKey = avatar.key
                            }
                        }
                    }
                }

                Text("More avatars unlock as you level up")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

private struct AvatarCell: View {
    let avatar: AvatarTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let uiImage = UIImage(named: avatar.key) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2.5)
                        .shadow(color: isSelected ? .cyan.opacity(0.6) : .clear, radius: 6)
                )

                Text(avatar.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.cyan.opacity(0.1) : Color.clear)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 6: Workout Plan

private struct WorkoutPlanStepView: View {
    @Binding var selectedPlanID: String?
    @Binding var isBuildingCustomPlan: Bool
    /// Player's biological sex — used to filter anime programs to gender-appropriate ones.
    let playerGender: PlayerGender
    /// Player's fitness goal — used (best-effort) to filter plans by recommended goal.
    let playerGoal: FitnessGoal
    @ObservedObject private var planService = AnimeWorkoutPlanService.shared

    @State private var showingAnimePicker = false
    @State private var pickMode: PickMode = .none

    private enum PickMode { case none, anime, custom }

    /// Plans whose target gender matches the player (or that are gender-neutral).
    /// The goal filter is applied as a nice-to-have if the plan model exposes it.
    private var visiblePlans: [AnimeWorkoutPlan] {
        planService.all.filter { plan in
            plan.targetGender == nil || plan.targetGender == playerGender
        }
    }

    private var previewPlans: [AnimeWorkoutPlan] {
        Array(visiblePlans.prefix(4))
    }

    var body: some View {
        OnboardingStepShell(
            icon: "figure.strengthtraining.traditional",
            iconColor: .orange,
            title: "Training Protocol",
            subtitle: "Start with a proven plan or build your own.",
            isSkippable: true
        ) {
            VStack(spacing: 14) {
                // Anime Plan card
                PlanOptionCard(
                    icon: "sparkles",
                    title: "Anime Plan",
                    subtitle: "Train like your favourite character",
                    color: .orange,
                    isSelected: pickMode == .anime
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pickMode = .anime
                        showingAnimePicker = true
                    }
                }

                // Build my own plan card — triggers the Goal Survey gate.
                PlanOptionCard(
                    icon: "plus.circle.fill",
                    title: "Build my own plan",
                    subtitle: "Answer a short survey so we can tailor quests to you",
                    color: .blue,
                    isSelected: pickMode == .custom
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pickMode = .custom
                        selectedPlanID = "custom_pending"
                        isBuildingCustomPlan = true
                    }
                }

                // Mini anime plan preview strip
                if !previewPlans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("POPULAR PLANS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.leading, 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(previewPlans) { plan in
                                    MiniPlanChip(plan: plan,
                                                 isSelected: selectedPlanID == plan.id) {
                                        selectedPlanID = plan.id
                                        pickMode = .anime
                                        isBuildingCustomPlan = false
                                    }
                                }
                            }
                        }
                    }
                }

                // Confirmation
                if let id = selectedPlanID,
                   let plan = planService.plan(id: id) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Selected: \(plan.character)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 4)
                } else if pickMode == .custom {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Build your plan after setup in the Training tab")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showingAnimePicker) {
            AnimePlanPickerSheet(
                plans: visiblePlans,
                selectedPlanID: $selectedPlanID
            )
        }
        .onChange(of: selectedPlanID) { _, newValue in
            // Any non-sentinel real plan ID clears the "custom" intent.
            if let id = newValue, !id.isEmpty, id != "custom_pending" {
                isBuildingCustomPlan = false
            }
        }
    }
}

private struct PlanOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isSelected ? color : .white.opacity(0.4))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : Color.white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct MiniPlanChip: View {
    let plan: AnimeWorkoutPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.character)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(plan.difficulty.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(plan.difficulty.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AnimePlanPickerSheet: View {
    let plans: [AnimeWorkoutPlan]
    @Binding var selectedPlanID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(plans) { plan in
                        Button {
                            selectedPlanID = plan.id
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: plan.iconSymbol)
                                    .font(.system(size: 22))
                                    .foregroundColor(plan.accentColor)
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(plan.character)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(plan.anime)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                }

                                Spacer()

                                Text(plan.difficulty.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(plan.difficulty.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(plan.difficulty.color.opacity(0.15))
                                    )

                                if selectedPlanID == plan.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.cyan)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedPlanID == plan.id
                                          ? Color.cyan.opacity(0.08)
                                          : Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selectedPlanID == plan.id
                                                    ? Color.cyan.opacity(0.4)
                                                    : Color.white.opacity(0.08),
                                                    lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Choose Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step 7: Gold Pieces Explainer

private struct GPExplainerStepView: View {
    @State private var coinPulse = false

    private let bullets: [(icon: String, text: String)] = [
        ("target",               "Earn GP by completing quests"),
        ("storefront.fill",      "Spend GP in the item store"),
        ("bolt.fill",            "Buy gear that powers up your stats")
    ]

    private let examples: [(label: String, amount: String)] = [
        ("Daily Quest",  "+25 GP"),
        ("Weekly Quest", "+100 GP"),
        ("Level Up",     "+200 GP")
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "dollarsign.circle.fill",
            iconColor: Color(red: 1.0, green: 0.8, blue: 0.0),
            title: "Gold Pieces",
            subtitle: "The in-game currency that powers your progression."
        ) {
            VStack(spacing: 18) {
                // Bullets
                VStack(spacing: 10) {
                    ForEach(bullets, id: \.text) { bullet in
                        HStack(spacing: 12) {
                            Image(systemName: bullet.icon)
                                .font(.system(size: 16))
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                .frame(width: 24)
                            Text(bullet.text)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 4)

                Divider().background(Color.white.opacity(0.1))

                // Example amounts
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXAMPLE REWARDS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))

                    HStack(spacing: 10) {
                        ForEach(examples, id: \.label) { ex in
                            VStack(spacing: 4) {
                                Text(ex.amount)
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text(ex.label)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.45))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Step 8: HealthKit

private struct HealthStepView: View {
    @ObservedObject var healthManager: HealthManager
    @State private var showDeniedHint = false

    private let readItems: [String] = [
        "Steps",
        "Sleep",
        "Heart rate",
        "Workouts",
        "Body weight",
        "Body fat percentage",
        "Mindful sessions"
    ]

    private let writeItems: [String] = [
        "Meals you log in the app",
        "Workouts you complete in the app",
        "Water intake",
        "Body weight changes"
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "heart.text.square.fill",
            iconColor: .red,
            title: "Connect Apple Health",
            subtitle: "Required to power your stats and personalize daily quests.",
            isSkippable: false
        ) {
            VStack(spacing: 18) {
                if healthManager.isAuthorized {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health Connected")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.green)
                            Text("Your biometrics are feeding the quest engine.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    )
                } else {
                    healthSection(header: "【WHAT WE READ】", items: readItems, accent: .cyan)
                    healthSection(header: "【WHAT WE WRITE】", items: writeItems, accent: .orange)

                    Button {
                        Task { @MainActor in
                            await healthManager.requestAuthorization()
                            if !healthManager.isAuthorized {
                                showDeniedHint = true
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "heart.fill")
                            Text("Connect Apple Health")
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .padding(.top, 4)

                    if showDeniedHint {
                        VStack(spacing: 8) {
                            Text("Permission denied — open Settings to enable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.cyan)
                        }
                    }

                    Text("We never share your health data. Everything stays on your device or in your private CloudKit container.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func healthSection(header: String, items: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.8))
                .tracking(2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundColor(accent.opacity(0.7))
                        Text(item)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accent.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Step 9: Notifications

private struct NotificationsStepView: View {
    @ObservedObject var notificationManager: NotificationManager

    private let examples = [
        "⚔️ Daily quests are live — time to level up!",
        "🔥 Streak at risk! Log one quest to keep it alive.",
        "🏆 You levelled up to Rank 12. New missions await."
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "bell.badge.fill",
            iconColor: .orange,
            title: "Stay in the System",
            subtitle: "Quest reminders and achievement alerts keep you on mission.",
            isSkippable: true
        ) {
            VStack(spacing: 16) {
                if notificationManager.isAuthorized {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text("Notifications enabled!")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    )
                } else {
                    // Example previews
                    VStack(spacing: 8) {
                        Text("EXAMPLE ALERTS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(examples, id: \.self) { ex in
                            HStack {
                                Text(ex)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                    }

                    Button("Enable Notifications") {
                        Task { await notificationManager.requestAuthorization() }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .padding(.top, 4)

                    if notificationManager.authorizationStatus == .denied {
                        VStack(spacing: 8) {
                            Text("Notifications are disabled in Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.cyan)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Step 10: Ready Screen

private struct ReadyStepView: View {
    let name: String
    let goal: FitnessGoal
    let avatarKey: String
    /// Called when the user taps "Enter the System". The parent
    /// OnboardingView wires this to completeOnboarding(), which writes
    /// hasCompletedOnboarding=true and routes the user to ContentView.
    var onContinue: () -> Void

    @State private var checkmarkScale: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Checkmark
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 110, height: 110)
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: appeared)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .scaleEffect(appeared ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.2), value: appeared)
                }

                VStack(spacing: 10) {
                    Text("SYSTEM ONLINE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                        .tracking(4)

                    Text("Welcome, \(name.isEmpty ? "Warrior" : name)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .cyan.opacity(0.3), radius: 8)
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                // Avatar + goal summary
                HStack(spacing: 20) {
                    // Avatar
                    ZStack {
                        if let uiImage = UIImage(named: avatarKey) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.cyan.opacity(0.5))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(Color.cyan, lineWidth: 2))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: goal.icon)
                                .foregroundColor(.cyan)
                            Text(goal.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text("Mission objective locked in")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                )
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)

                Spacer()

                // "Enter the System" — final commit button. Lives inline
                // because the Ready step is in noProgressBarSteps so the
                // parent's nav-button row is suppressed.
                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        Text("Enter the System")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 14)
                    )
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Shell Layout

private struct OnboardingStepShell<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var isSkippable: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(iconColor)
                }
                .padding(.top, 24)

                // Title + subtitle
                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
                .padding(.horizontal, 8)

                // Step-specific content
                content
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Button Styles

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cyan)
                    .shadow(color: .cyan.opacity(0.4), radius: 10)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Re-export old styles for backwards compat with any call site still using them
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingPrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .stroke(Color.gray, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Enums still referenced outside this file
// (FitnessGoal, GymEnvironment, PlayerGender are in Models.swift — no change needed)

// MARK: - QuestDifficulty, QuestCategory (still in QuestsView.swift — no change)

// MARK: - Preview

// MARK: - Step 6: Goal Survey Gate
//
// Only shown when the user picked "Build my own plan" on step 5.
// Presents GoalSurveyView in a fullScreenCover. Continue (in the parent nav
// bar) is disabled until `profile.goalSurveyCompleted == true`.

private struct GoalSurveyGateStepView: View {
    /// Lazily fetches-or-creates the live Profile so the survey sheet has
    /// something to mutate.
    let profileProvider: () -> Profile
    @Binding var goalSurveyCompleted: Bool

    @State private var showingSurvey = false
    @State private var resolvedProfile: Profile? = nil

    var body: some View {
        OnboardingStepShell(
            icon: "list.bullet.clipboard.fill",
            iconColor: .cyan,
            title: "Goal Survey Required",
            subtitle: "To generate quests for your custom plan, complete a 7-question survey about your training preferences."
        ) {
            VStack(spacing: 16) {
                Button {
                    resolvedProfile = profileProvider()
                    showingSurvey = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: goalSurveyCompleted
                              ? "checkmark.circle.fill"
                              : "arrow.right.circle.fill")
                        Text(goalSurveyCompleted ? "Survey Complete" : "Take the Survey")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(goalSurveyCompleted ? .green : .cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill((goalSurveyCompleted ? Color.green : Color.cyan).opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke((goalSurveyCompleted ? Color.green : Color.cyan)
                                            .opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                if goalSurveyCompleted {
                    Text("Nice — tap Continue to keep going.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .fullScreenCover(isPresented: $showingSurvey) {
            if let profile = resolvedProfile {
                GoalSurveyView(profile: profile) {
                    // Sync local gate state from the profile after the survey dismisses.
                    goalSurveyCompleted = profile.goalSurveyCompleted
                    showingSurvey = false
                }
            }
        }
    }
}

// MARK: - Step 9: ATT (App Tracking Transparency) Prompt
//
// Briefly explains why we want tracking permission, then triggers the system
// prompt via AppTrackingHelper. Both buttons advance the step — the Skip link
// just advances without requesting.

// ATTPromptStepView removed in 2.8.4 — the codebase doesn't consume
// the IDFA, so requesting tracking permission was both pointless and an
// App Review hazard per Guideline 5.1.2. The NSUserTrackingUsageDescription
// key was also removed from Info.plist + project.pbxproj, and
// AppTrackingHelper.swift was deleted entirely.

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .modelContainer(for: [Profile.self, Quest.self], inMemory: true)
}
