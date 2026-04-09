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
    @State private var selectedPlanID: String?         = nil
    @State private var useMetric: Bool = (Locale.current.measurementSystem == .metric)
    // The "Build my own plan" custom-plan path and its Goal Survey gate
    // were removed in 2.8.11 — they were a source of repeated render
    // bugs (the survey fullScreenCover never rendered correctly) and
    // user confusion. Onboarding is now strictly: pick a pre-built
    // anime plan or skip the workout-plan selection entirely.

    /// True while a permission-fetching Task is in flight on the current step.
    /// Used to disable the Continue button so a fast double-tap can't spawn
    /// two concurrent permission requests / step advances.
    @State private var isAdvancing: Bool = false

    /// Direction of the most recent step transition. Drives the slide
    /// animation so the back button visually moves backward (new step
    /// enters from the leading edge) instead of looking like a forward
    /// advance. Must be set BEFORE mutating currentStep inside the same
    /// withAnimation block so SwiftUI captures the correct edges when it
    /// computes the transition.
    @State private var navigatingBackward: Bool = false

    /// True when the app was launched with the `-onboardingDebugAutofill 1`
    /// argument. Used by my (Claude's) screenshot pipeline to walk through
    /// every step of onboarding without needing real input — values are
    /// pre-filled and the back/Continue buttons remain interactive so I
    /// can also test them via computer-use MCP. Compiled out of Release.
    private var debugAutofillEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "onboardingDebugAutofill")
        #else
        return false
        #endif
    }

    /// Driven by UIResponder.keyboardWillShow/Hide notifications. When true,
    /// a custom Done overlay is rendered via safeAreaInset(.bottom) so we
    /// have full layout control over the dismiss button — bypassing the
    /// system .toolbar(.keyboard) accessory bar which has been ignoring
    /// padding modifiers across three different attempts in builds 32-34.
    @State private var isKeyboardVisible: Bool = false

    // ── Services ──────────────────────────────────────────────────────────────
    @StateObject private var healthManager       = HealthManager()
    @StateObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var avatarService    = AvatarService.shared

    // ── Step configuration ────────────────────────────────────────────────────
    // 11 logical steps shown to the user (1 Name, 2 Gender, 3 Body Stats,
    // 4 Goal, 5 Class, 6 Diet, 7 Workout Plan, 9 Avatar, 10 Health,
    // 11 Notifications, 12 Ready). Step 8 — the Goal Survey Gate — is
    // intentionally retired in 2.8.11 along with the custom-plan path,
    // and the step number is permanently skipped by advanceFrom and
    // previousStep so the user never lands on it.
    private let totalProgressSteps = 11
    // HealthKit (10) and Notifications (11) are both skippable — neither
    // is allowed to block the user from completing onboarding. HealthKit
    // in particular has been a sticking point because Apple's system
    // sheet is one-shot per install: if the user denies once, they can
    // never re-trigger it from inside the app. The skip path lets them
    // proceed and re-grant later from Settings → Privacy → Health.
    private let skippableSteps: Set<Int> = [10, 11]
    private let noProgressBarSteps: Set<Int> = [0, 12]

    /// Dismisses the keyboard. Used by the tap-anywhere gesture and the
    /// keyboard accessory Done button. Wrapped here so both call sites
    /// invoke the exact same UIKit responder path.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    var body: some View {
        ZStack {
            // Background — no tap gesture here. The previous build attached
            // .onTapGesture for keyboard dismiss directly to Color.black
            // and it was racing/winning over the back chevron Button (which
            // has only a 16pt SF-symbol hit area), preventing back navigation
            // entirely. Tap-to-dismiss is now a simultaneousGesture on the
            // inner VStack so Buttons inside it always win first.
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (hidden on boot and ready screens)
                if !noProgressBarSteps.contains(currentStep) {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                // Step content. The slide direction flips based on
                // navigatingBackward so the back button feels like going
                // backward (new content enters from the left) and Continue
                // feels like going forward (new content enters from the right).
                // Uses an interpolating spring for a smoother, less abrupt
                // page transition than easeInOut.
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: navigatingBackward ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: navigatingBackward ? .trailing : .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentStep)

                // Navigation buttons (hidden on boot and ready screens)
                if !noProgressBarSteps.contains(currentStep) {
                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
            // No tap-anywhere-to-dismiss-keyboard gesture here. Two prior
            // attempts (Color.black.onTapGesture in build 34, then
            // simultaneousGesture on this VStack in build 35) both raced
            // and won over the back chevron Button despite SwiftUI docs
            // saying child Buttons should win. The Done button in the
            // safeAreaInset overlay below handles keyboard dismissal
            // completely, so tap-anywhere is no longer needed.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        // Universal keyboard dismiss affordance for any text-input step
        // (Name, Body Stats, etc). The system places this in the keyboard
        // accessory bar, so it's only visible while a TextField is focused
        // and disappears the moment the keyboard goes down.
        // Custom keyboard accessory: full SwiftUI control of layout via
        // safeAreaInset, instead of fighting the system .toolbar(.keyboard)
        // bar which has been ignoring padding/styling modifiers across
        // three previous build attempts. The view appears whenever any
        // TextField in onboarding becomes first responder (driven by
        // UIResponder keyboard notifications below) and disappears
        // synchronously with the keyboard. We control the spacing,
        // padding, capsule styling, and trailing margin completely.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardVisible {
                HStack {
                    Spacer()
                    Button(action: dismissKeyboard) {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Color.cyan)
                                    .shadow(color: .cyan.opacity(0.5), radius: 10)
                            )
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.85))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Back chevron. Hit area is expanded to the 44×44 pt HIG
                // minimum via .frame + .contentShape(Rectangle()) — without
                // those, the SF symbol's 16pt glyph hit area was so small
                // that taps near the chevron fell through to whatever
                // gesture was watching the parent (most recently the
                // .onTapGesture on Color.black, which broke back navigation
                // entirely in build 34). buttonStyle(.plain) prevents the
                // system from inserting its own padding around the label.
                Button {
                    // Flag MUST be set inside the same withAnimation block
                    // (and before currentStep mutates) so SwiftUI captures
                    // the reversed transition edges for this animation.
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        navigatingBackward = true
                        currentStep = previousStep(from: currentStep)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentStep <= 1 ? .clear : .white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentStep <= 1)
                .accessibilityIdentifier("onboarding_back_button")

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

                Text("\(displayedStep)/\(totalProgressSteps)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 36, alignment: .trailing)
                    .accessibilityIdentifier("onboarding_step_counter")
            }
            .frame(height: 32)
        }
    }

    /// Maps the raw currentStep (which can include the retired Goal Survey
    /// Gate position 8) to a 1..totalProgressSteps display number, so the
    /// progress bar fills smoothly without a missing-tooth gap at the
    /// position where step 8 used to live.
    private var displayedStep: Int {
        currentStep > 8 ? currentStep - 1 : currentStep
    }

    private var progressFraction: CGFloat {
        guard currentStep > 0 else { return 0 }
        return CGFloat(displayedStep) / CGFloat(totalProgressSteps)
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
                         // Debug-only autofill so the visual test pipeline
                         // can walk through every step without real input.
                         #if DEBUG
                         if debugAutofillEnabled {
                             if profileName.isEmpty { profileName = "TestUser" }
                             if ageText.isEmpty { ageText = "30" }
                             if heightText.isEmpty { heightText = "175" }
                             if weightText.isEmpty { weightText = "75" }
                             if selectedClass == .unselected { selectedClass = .warrior }
                         }
                         #endif
                         withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                             navigatingBackward = false
                             currentStep = 1
                         }
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
                    playerGender: selectedGender,
                    playerGoal: selectedGoal
                 )
        // Step 8 (Goal Survey Gate) was removed in 2.8.11. The advanceFrom
        // and previousStep functions skip this step number unconditionally.
        case 9:  AvatarPickerStepView(
                    selectedAvatarKey: $selectedAvatarKey,
                    playerGender: selectedGender
                 )
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
            .accessibilityIdentifier("onboarding_continue_button")

            // Skip button (optional steps only)
            if skippableSteps.contains(currentStep) {
                Button("Skip for now") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        advanceFrom(currentStep)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .accessibilityIdentifier("onboarding_skip_button")
            }
        }
    }

    // MARK: - Advance Logic

    private var canAdvance: Bool {
        switch currentStep {
        case 1: // Name
            return !profileName.trimmingCharacters(in: .whitespaces).isEmpty
        case 3: // Body stats — all three numeric fields must parse to > 0
            let age    = Int(ageText) ?? 0
            let height = Double(heightText) ?? 0
            let weight = Double(weightText) ?? 0
            return age > 0 && height > 0 && weight > 0
        case 5: // Class — must explicitly pick a non-unselected class
            return selectedClass != .unselected
        case 6: // Diet — .none is a legitimate answer ("no restrictions"),
                // so the default selection counts as a valid response.
            return true
        case 7: // Workout plan — must pick a preset
            return selectedPlanID != nil
        case 9: // Avatar
            return selectedAvatarKey != nil
        default:
            return true
        }
    }

    /// Advances from `step`. Step 8 (the retired Goal Survey Gate) is
    /// always skipped — its slot is permanently empty post-2.8.11.
    private func advanceFrom(_ step: Int) {
        var next = step + 1
        if next == 8 { next = 9 }
        // Reset the back-flag so the slide animation runs forward.
        navigatingBackward = false
        currentStep = next
    }

    /// Inverse of `advanceFrom` for the back button. Mirrors the same
    /// step-skipping rule so we never land on the retired step 8.
    private func previousStep(from step: Int) -> Int {
        var prev = step - 1
        if prev == 8 { prev = 7 }
        return max(1, prev)
    }

    private func handleAdvance() {
        // Guard against double-tap on permission steps. Without this, a fast
        // double-tap on Continue can spawn two concurrent permission Tasks
        // and double-advance currentStep.
        guard !isAdvancing else { return }

        if currentStep == 0 {
            // Boot → Name
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                navigatingBackward = false
                currentStep = 1
            }
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
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { advanceFrom(9) }
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
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { advanceFrom(10) }
            }
            return
        case 11:
            isAdvancing = true
            Task { @MainActor in
                if notificationManager.authorizationStatus == .notDetermined {
                    await notificationManager.requestAuthorization()
                }
                isAdvancing = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { advanceFrom(11) }
            }
            return
        default:
            break
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
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

        // Persist the username to UserDefaults FIRST so that any code path
        // that calls DataManager.ensureProfileExists() (which reads
        // "userProfileName") will pick up the real name instead of the
        // default "Player". This must happen before the SwiftData fetch
        // below, because ensureProfileExists can be triggered from
        // PlayerProfileService.refresh() running concurrently in the
        // RPTApp .task chain.
        if !trimmedName.isEmpty {
            UserDefaults.standard.set(trimmedName, forKey: "userProfileName")
        }

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
        if let planID = selectedPlanID, !planID.isEmpty {
            profile.activePlanID = planID
        } else {
            profile.activePlanID = ""
        }
        try? modelContext.save()

        // Keep DataManager.shared.currentProfile in sync. If it already
        // points to a Profile (same SwiftData context — same managed
        // object), the name update above is already visible. If it hasn't
        // been materialised yet, ensureProfileExists will create/fetch it
        // using the UserDefaults name we wrote above, so it picks up the
        // correct username. Force-ensure it exists now so HomeView sees
        // the profile immediately.
        if DataManager.shared.currentProfile == nil {
            DataManager.shared.ensureProfileExists()
        } else if let dmProfile = DataManager.shared.currentProfile,
                  !trimmedName.isEmpty {
            // Same context means same managed object, but be defensive:
            // if the name somehow didn't propagate, set it directly.
            dmProfile.name = trimmedName
            try? modelContext.save()
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

        // Push local profile to the cloud. Use syncProfile() (upsert-only)
        // instead of refresh() — refresh() fetches the remote profile and
        // applies it locally, which can overwrite the name the user just
        // typed with a stale "Player" default that was upserted earlier in
        // the RPTApp .task chain before onboarding finished.
        Task { await PlayerProfileService.shared.syncProfile() }

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
                        .accessibilityIdentifier("siwa_button")
                    }

                    // DEBUG-only: bypass SIWA so XCUITest smoke tests can
                    // walk through the onboarding flow without needing a
                    // real Apple ID. The button is stripped at compile
                    // time from Release builds and never ships to
                    // TestFlight or the App Store. The accessibilityIdentifier
                    // is what the UI test uses to find and tap it.
                    #if DEBUG
                    Button {
                        onNewUserSignedIn()
                    } label: {
                        Text("Skip SIWA (DEBUG)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .accessibilityIdentifier("debug_skip_siwa")
                    .padding(.top, 4)
                    #endif

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

        // Three possible outcomes from the SIWA link attempt. Onboarding
        // navigation MUST be driven by this server-side signal, never by
        // probing the local SwiftData Profile — that model has CloudKit-
        // required defaults (age=25, height=170, weight=70) which make
        // every fresh local profile look "complete" to a > 0 check, so
        // any local heuristic causes new users to skip onboarding and
        // land directly on the home page. The server's onboarding_completed
        // flag is the only authoritative answer.
        let outcome = await PlayerProfileService.shared.linkAppleID(
            appleUserID: result.userID,
            displayName: result.displayName,
            authorizationCode: result.authorizationCode
        )

        // Brief settle so applyRemoteProfile() finishes its writes before
        // the next view reads from DataManager.
        try? await Task.sleep(for: .seconds(0.5))

        switch outcome {
        case .recoveredCompleted:
            // Server says this player has completed onboarding before.
            // BUT — we deliberately do NOT auto-skip onboarding on a
            // fresh install. AppStorage's hasCompletedOnboarding flag
            // does not survive reinstalls, and the user testing the
            // app on a fresh install (or after Delete Account) expects
            // to walk through the steps again. The recovery from the
            // server still happened (applyRemoteProfile pre-filled the
            // local Profile), so they'll see all their data already
            // populated and can tap Continue through quickly. The only
            // case the auto-skip would matter for is true cross-device
            // recovery, which is rare enough that asking the user to
            // tap through pre-filled steps is a small cost compared
            // to the much-more-common "user reinstalled and wants to
            // re-onboard" case that build 27→34 kept stranding on
            // the home page with no onboarding.
            onNewUserSignedIn()

        case .linkedNewOrIncomplete:
            // Brand new player OR an existing player whose cloud row is
            // empty / partially filled. Run the full onboarding flow,
            // pre-filling whatever the server did return.
            onNewUserSignedIn()

        case .failed:
            // The server link failed (CloudKit id not resolved yet, no
            // iCloud account, transient network blip). The SIWA credential
            // itself is valid and persisted in Keychain by
            // SignInWithAppleButtonView, so the user IS authenticated
            // locally. We treat them as a new player here — they'll fill
            // out onboarding, and PlayerProfileService.refresh() retries
            // the link on every launch and quietly heals it on the next
            // session that has CloudKit. Previously this path stranded
            // the user on the welcome screen with "Couldn't sign in with
            // Apple", presenting as "onboarding doesn't trigger after SIWA".
            print("[Onboarding] linkAppleID failed; proceeding as new user — refresh() will retry the link on next launch")
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
            title: "Pick a username",
            subtitle: "Your identity across the system.\nOther players will see this."
        ) {
            VStack(spacing: 8) {
                TextField("Enter a username", text: $profileName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .accessibilityIdentifier("name_text_field")
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
                    Text("Username required to continue")
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
                    Text("Pick a class to continue — you'll get a 10% XP bonus on matching quests.")
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
                    // Imperial: split into two rows so 4 fields don't try
                    // to fit in one HStack (overflows on iPhone SE 375pt
                    // wide). Age gets its own row, Height (FT/IN) and
                    // Weight share the second row.
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            StatField(label: "AGE", placeholder: "25", unit: "yrs", text: $ageText)
                        }
                        HStack(spacing: 10) {
                            StatField(label: "FT", placeholder: "5", unit: "ft", text: $ftText)
                                .onChange(of: ftText) { _, _ in commitImperialToMetric() }
                            StatField(label: "IN", placeholder: "7", unit: "in", text: $inText)
                                .onChange(of: inText) { _, _ in commitImperialToMetric() }
                            StatField(label: "WEIGHT", placeholder: "154", unit: "lbs", text: $lbsText)
                                .onChange(of: lbsText) { _, _ in commitImperialToMetric() }
                        }
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
                .padding(.bottom, 20)  // breathing room above the nav buttons on iPhone SE
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
    let playerGender: PlayerGender
    @ObservedObject private var avatarService = AvatarService.shared

    /// Filtered catalog: same-gender only, and only avatars whose image
    /// is actually bundled in Assets.xcassets. The image filter eliminates
    /// blank/SF-symbol cells the user was seeing — any avatar whose
    /// UIImage(named: key) returns nil is silently skipped instead of
    /// rendering a placeholder.
    private var avatars: [AvatarTemplate] {
        let suffix: String
        switch playerGender {
        case .female: suffix = "_f"
        default:      suffix = "_m"
        }
        return avatarService.catalog.filter { tmpl in
            tmpl.key.hasSuffix(suffix) && UIImage(named: tmpl.key) != nil
        }
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
                                .frame(height: 88)
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
                                .frame(height: 88)
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
    /// Player's biological sex — used to filter anime programs to gender-appropriate ones.
    let playerGender: PlayerGender
    /// Player's fitness goal — used (best-effort) to filter plans by recommended goal.
    let playerGoal: FitnessGoal
    @ObservedObject private var planService = AnimeWorkoutPlanService.shared

    @State private var showingAnimePicker = false

    /// Plans whose target gender matches the player (or that are gender-neutral).
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
            subtitle: "Pick a proven plan to start with — you can swap any time from the Training tab.",
            isSkippable: false
        ) {
            VStack(spacing: 14) {
                // Anime Plan card. Title/subtitle reflect the actual chosen
                // plan once one is picked, so the user can see at a glance
                // what they selected. Tapping the card after selection
                // re-opens the picker so they can swap plans.
                // The "Build my own plan" path was removed in 2.8.11.
                let chosenAnimePlan: AnimeWorkoutPlan? = {
                    if let id = selectedPlanID,
                       let plan = planService.plan(id: id) {
                        return plan
                    }
                    return nil
                }()
                PlanOptionCard(
                    icon: chosenAnimePlan?.iconSymbol ?? "sparkles",
                    title: chosenAnimePlan?.character ?? "Choose your plan",
                    subtitle: chosenAnimePlan.map { "\($0.anime) — tap to change" }
                        ?? "Browse the full catalog of anime training programs",
                    color: .orange,
                    isSelected: chosenAnimePlan != nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingAnimePicker = true
                    }
                }

                // Loading state when the AnimeWorkoutPlanService catalog
                // hasn't fetched yet — without this, the user sees only
                // a single "Choose your plan" card with no popular-plan
                // strip and no indication that more plans are loading.
                if planService.all.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.orange)
                        Text("Loading workout plans…")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(1)
                    }
                    .padding(.top, 6)
                }

                // Mini anime plan preview strip — quick picks of the
                // most popular plans without opening the full picker.
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
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAnimePicker) {
            AnimePlanPickerSheet(
                plans: visiblePlans,
                selectedPlanID: $selectedPlanID
            )
        }
        .onAppear {
            // Trigger a refresh if the launch chain hasn't finished
            // hydrating the plan catalog yet (mirrors AvatarPickerStepView).
            if planService.all.isEmpty {
                Task { await planService.refresh() }
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
            isSkippable: true
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

                    if showDeniedHint || healthManager.lastErrorMessage != nil {
                        VStack(spacing: 10) {
                            // Surface the actual error from HealthManager
                            // when present (entitlement issue, denial,
                            // device unsupported), otherwise fall back
                            // to the generic denied message.
                            Text(healthManager.lastErrorMessage
                                 ?? "Permission denied — you can grant access later from iOS Settings → Privacy & Security → Health.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                Button("Open Health Settings") {
                                    // Direct deep link into the Health
                                    // app's Sources screen for this app.
                                    // Falls back to general Settings if
                                    // the URL scheme isn't available.
                                    if let url = URL(string: "x-apple-health://") {
                                        UIApplication.shared.open(url) { ok in
                                            if !ok, let s = URL(string: UIApplication.openSettingsURLString) {
                                                UIApplication.shared.open(s)
                                            }
                                        }
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.cyan)
                            }

                            Text("Tap Skip below to continue without Apple Health — you can connect it later from the Settings tab.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        )
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
// (GoalSurveyGateStepView removed in 2.8.11 along with the custom-plan path.
// GoalSurveyView is no longer reachable from onboarding; it can be re-used
// later from a Settings screen if needed.)

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
