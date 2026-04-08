//
//  GoalSurveyView.swift
//  RPT
//
//  7-step goal survey wizard used by the "Build my own plan" onboarding path.
//  Collects answers, persists them to the Profile via DataManager, and kicks
//  off default daily quest generation. Designed to match the existing
//  dark / cyan onboarding aesthetic.
//

import SwiftUI

struct GoalSurveyView: View {
    let profile: Profile
    let onComplete: () -> Void

    // MARK: - Wizard state
    @State private var currentPage: Int = 0
    @State private var days: Int = 4
    @State private var split: GoalSurveySplit = .fullBody
    @State private var sessionLength: Int = 60
    @State private var intensity: GoalSurveyIntensity = .moderate
    @State private var focusAreas: [GoalSurveyFocusArea] = []
    @State private var gym: GymEnvironment = .fullGym
    @State private var cardio: GoalSurveyCardio = .light

    private let totalPages: Int = 7

    var body: some View {
        ZStack {
            // Dark background matches OnboardingView
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with a close affordance. Without this the user
                // is trapped inside the fullScreenCover until they finish
                // all 7 pages — there's no swipe-to-dismiss on
                // fullScreenCover, no navigation bar, no Cancel button.
                // Tapping X calls onComplete which dismisses the cover
                // without flipping profile.goalSurveyCompleted, so the
                // gate step still sees the unfinished state and the user
                // is free to either retry or back out to step 7 and
                // choose a different workout plan.
                HStack {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Close survey")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                progressDots
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // The previous implementation used TabView with
                // .tabViewStyle(.page(indexDisplayMode: .never)) which
                // collapsed to zero height once a sibling HStack (the close
                // button bar) was added above it inside the parent VStack —
                // SwiftUI's page-style TabView is greedy *only* if it has
                // an explicit infinite frame, otherwise it shrinks. The
                // result was a fully black survey with progress dots and
                // nav buttons floating against the gradient and no
                // visible question content. Switching to a direct
                // page-by-page Group + explicit .frame(maxHeight: .infinity)
                // is more reliable on every iOS version and matches the
                // pattern OnboardingView itself uses.
                Group {
                    switch currentPage {
                    case 0: daysPage
                    case 1: splitPage
                    case 2: sessionLengthPage
                    case 3: intensityPage
                    case 4: focusAreasPage
                    case 5: equipmentPage
                    case 6: cardioPage
                    default: daysPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(currentPage)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .animation(.easeInOut(duration: 0.25), value: currentPage)

                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadExistingAnswers)
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? Color.cyan : Color.white.opacity(0.18))
                    .frame(width: i == currentPage ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
            }
        }
    }

    // MARK: - Navigation buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button {
                    withAnimation { currentPage -= 1 }
                } label: {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Button {
                if currentPage == totalPages - 1 {
                    saveAndComplete()
                } else {
                    withAnimation { currentPage += 1 }
                }
            } label: {
                Text(currentPage == totalPages - 1 ? "Save & Generate Quests" : "Next")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.cyan)
                            .shadow(color: .cyan.opacity(0.5), radius: 14)
                    )
            }
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.5)
        }
    }

    private var canAdvance: Bool {
        switch currentPage {
        case 4: return !focusAreas.isEmpty
        default: return true
        }
    }

    // MARK: - Page 1 — Days per week

    private var daysPage: some View {
        QuestionContainer(
            title: "How many days per week?",
            subtitle: "Pick what you can realistically commit to."
        ) {
            VStack(spacing: 24) {
                Text("\(days)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .cyan.opacity(0.6), radius: 18)

                Text(days == 1 ? "day / week" : "days / week")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.8))

                Slider(
                    value: Binding(
                        get: { Double(days) },
                        set: { days = Int($0.rounded()) }
                    ),
                    in: 2...7,
                    step: 1
                )
                .tint(.cyan)
                .padding(.horizontal, 8)

                HStack {
                    Text("2").foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("7").foregroundColor(.white.opacity(0.5))
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Page 2 — Split

    private var splitPage: some View {
        QuestionContainer(
            title: "Which split fits your style?",
            subtitle: "We'll structure your weekly plan around this."
        ) {
            VStack(spacing: 12) {
                ForEach(GoalSurveySplit.allCases) { option in
                    SelectionCard(
                        title: option.displayName,
                        subtitle: option.blurb,
                        isSelected: split == option
                    ) {
                        split = option
                    }
                }
            }
        }
    }

    // MARK: - Page 3 — Session length

    private var sessionLengthPage: some View {
        QuestionContainer(
            title: "How long per session?",
            subtitle: "We'll tune exercise volume to fit."
        ) {
            VStack(spacing: 16) {
                Picker("Session length", selection: $sessionLength) {
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                    Text("90 min").tag(90)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)

                Text("\(sessionLength) minutes")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .cyan.opacity(0.5), radius: 14)
                    .padding(.top, 16)
            }
        }
    }

    // MARK: - Page 4 — Intensity

    private var intensityPage: some View {
        QuestionContainer(
            title: "How hard do you want to push?",
            subtitle: "This affects XP rewards and quest difficulty."
        ) {
            VStack(spacing: 12) {
                ForEach(GoalSurveyIntensity.allCases) { option in
                    SelectionCard(
                        title: option.displayName,
                        subtitle: "XP multiplier ×\(String(format: "%.1f", option.xpMultiplier))",
                        isSelected: intensity == option
                    ) {
                        intensity = option
                    }
                }
            }
        }
    }

    // MARK: - Page 5 — Focus areas (multi-select, max 3)

    private var focusAreasPage: some View {
        QuestionContainer(
            title: "What are you focusing on?",
            subtitle: "Pick up to 3 priorities."
        ) {
            VStack(spacing: 16) {
                Text("\(focusAreas.count) of 3 selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cyan.opacity(0.8))

                FlowLayout(spacing: 10) {
                    ForEach(GoalSurveyFocusArea.allCases) { area in
                        let selected = focusAreas.contains(area)
                        let atLimit = focusAreas.count >= 3 && !selected
                        FocusChip(
                            area: area,
                            isSelected: selected,
                            isDisabled: atLimit
                        ) {
                            if selected {
                                focusAreas.removeAll { $0 == area }
                            } else if focusAreas.count < 3 {
                                focusAreas.append(area)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Page 6 — Equipment (maps to Profile.gymEnvironment)

    private var equipmentPage: some View {
        QuestionContainer(
            title: "What equipment do you have?",
            subtitle: "We'll only suggest exercises you can actually do."
        ) {
            VStack(spacing: 12) {
                EquipmentCard(
                    title: "Full gym",
                    subtitle: "Barbells, dumbbells, machines, cables",
                    icon: "building.2.fill",
                    isSelected: gym == .fullGym
                ) { gym = .fullGym }

                EquipmentCard(
                    title: "Home / limited",
                    subtitle: "Dumbbells, bands, pull-up bar",
                    icon: "house.fill",
                    isSelected: gym == .homeGym
                ) { gym = .homeGym }

                EquipmentCard(
                    title: "Bodyweight only",
                    subtitle: "No equipment — just you",
                    icon: "figure.mind.and.body",
                    isSelected: gym == .bodyweightOnly
                ) { gym = .bodyweightOnly }
            }
        }
    }

    // MARK: - Page 7 — Cardio

    private var cardioPage: some View {
        QuestionContainer(
            title: "How much cardio?",
            subtitle: "Last step — then we'll build your quests."
        ) {
            VStack(spacing: 12) {
                ForEach(GoalSurveyCardio.allCases) { option in
                    SelectionCard(
                        title: option.displayName,
                        subtitle: option.sessionsPerWeek == 0
                            ? "No cardio sessions"
                            : "\(option.sessionsPerWeek) sessions / week",
                        isSelected: cardio == option
                    ) {
                        cardio = option
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadExistingAnswers() {
        if profile.goalSurveyDaysPerWeek > 0 {
            days = profile.goalSurveyDaysPerWeek
        }
        if let s = profile.goalSurveySplit { split = s }
        if profile.goalSurveySessionMinutes > 0 {
            sessionLength = profile.goalSurveySessionMinutes
        }
        if let i = profile.goalSurveyIntensity { intensity = i }
        let existingFocus = profile.goalSurveyFocusAreas
        if !existingFocus.isEmpty { focusAreas = existingFocus }
        gym = profile.gymEnvironment
        if let c = profile.goalSurveyCardio { cardio = c }
    }

    private func saveAndComplete() {
        DataManager.shared.updateProfile { p in
            p.goalSurveyDaysPerWeek = days
            p.goalSurveySplit = split
            p.goalSurveySessionMinutes = sessionLength
            p.goalSurveyIntensity = intensity
            p.goalSurveyFocusAreas = focusAreas
            p.gymEnvironment = gym
            p.goalSurveyCardio = cardio
            p.goalSurveyCompleted = true
        }
        DataManager.shared.generateDefaultDailyQuests()
        onComplete()
    }
}

// MARK: - Reusable subviews

private struct QuestionContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .cyan.opacity(0.4), radius: 12)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.top, 8)

                content

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct SelectionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.cyan : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? .cyan.opacity(0.25) : .clear,
                radius: 12
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EquipmentCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.7))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.cyan : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FocusChip: View {
    let area: GoalSurveyFocusArea
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: area.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(area.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(isDisabled ? 0.3 : 0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.cyan : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.cyan : Color.white.opacity(isDisabled ? 0.08 : 0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// Minimal flow layout for the focus chips (iOS 16+).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            y = totalHeight + rowHeight
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
