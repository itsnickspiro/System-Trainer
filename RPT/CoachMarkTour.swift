//
//  CoachMarkTour.swift
//  RPT
//
//  First-run coach-mark tour overlay. Walks new users through the 5 key
//  app surfaces with a dimmed scrim + captioned bubble. Dismissible and
//  only shows once per install (tracked via UserDefaults).
//

import SwiftUI
import Combine

// MARK: - Step Model

/// A single step in the coach-mark tour. Each step is a full-screen
/// caption card with an SF Symbol hero, title, body, and accent color.
struct CoachMarkStep: Identifiable {
    let id = UUID()
    let title: String           // e.g. "Your Stats"
    let body: String            // 1-2 sentence explanation
    let icon: String            // SF Symbol name
    let accentColor: Color
}

// MARK: - Tour Manager

/// Singleton that owns tour state. Call `startIfNeeded()` from HomeView's
/// onAppear; it will no-op if the user has already seen the tour.
@MainActor
final class CoachMarkTourManager: ObservableObject {
    static let shared = CoachMarkTourManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentStepIndex: Int = 0
    private(set) var steps: [CoachMarkStep] = []

    private static let completedKey = "rpt_coach_mark_tour_completed_v1"

    private init() {
        self.steps = Self.defaultSteps()
    }

    /// True if the user has already completed or dismissed the tour on this install.
    var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Start the tour if it hasn't been shown yet. Safe to call on every Home appear.
    func startIfNeeded() {
        guard !hasBeenShown else { return }
        currentStepIndex = 0
        isActive = true
    }

    /// Advance to the next step, or finish the tour if on the last step.
    func next() {
        if currentStepIndex + 1 < steps.count {
            currentStepIndex += 1
        } else {
            finish()
        }
    }

    /// Mark the tour complete and dismiss the overlay.
    func finish() {
        isActive = false
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    /// For testing: allow the user to retrigger the tour from Settings.
    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
    }

    // The 5 default steps. Copy leans into the System/isekai voice the app cultivates.
    private static func defaultSteps() -> [CoachMarkStep] {
        [
            CoachMarkStep(
                title: "【System Online】",
                body: "Welcome, Traveler. Your Stats update in real time as you complete quests, log meals, and train. Keep them above 50 to maintain peak condition.",
                icon: "bolt.heart.fill",
                accentColor: .cyan
            ),
            CoachMarkStep(
                title: "Daily Quests",
                body: "Every day the System hands you a rotating quest list — workouts, nutrition goals, discipline checks. Completing them is how you gain XP, level up, and earn Gold Pieces.",
                icon: "scroll.fill",
                accentColor: .purple
            ),
            CoachMarkStep(
                title: "Rations & Diet",
                body: "Scan a barcode or search to log meals. Your diet preference flags food that doesn't match your plan. Foods are graded A–F based on your fitness goal.",
                icon: "fork.knife",
                accentColor: .green
            ),
            CoachMarkStep(
                title: "Training",
                body: "Build custom routines or follow a pre-made plan. Every logged workout feeds Strength, Endurance, and Discipline. Your class gives you a +10% XP bonus on matching quests.",
                icon: "figure.strengthtraining.traditional",
                accentColor: .orange
            ),
            CoachMarkStep(
                title: "Begin the Journey",
                body: "You have been chosen. The System will guide you — but only you can put in the work. Start with today's first quest.",
                icon: "sparkles",
                accentColor: .yellow
            )
        ]
    }
}

// MARK: - Overlay View

/// Full-screen overlay that renders the current coach-mark step on top
/// of whatever Home content is underneath. Attach as an `.overlay` on
/// HomeView's root; it draws nothing when the tour is inactive.
struct CoachMarkOverlay: View {
    @ObservedObject private var manager = CoachMarkTourManager.shared

    var body: some View {
        if manager.isActive, manager.currentStepIndex < manager.steps.count {
            let step = manager.steps[manager.currentStepIndex]
            ZStack {
                // Dimmed scrim — blocks interaction with content beneath
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 24) {
                    Spacer()

                    // Icon hero — glowing circle badge
                    ZStack {
                        Circle()
                            .fill(step.accentColor.opacity(0.18))
                            .frame(width: 120, height: 120)
                        Circle()
                            .stroke(step.accentColor, lineWidth: 2)
                            .frame(width: 120, height: 120)
                        Image(systemName: step.icon)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundColor(step.accentColor)
                    }
                    .shadow(color: step.accentColor.opacity(0.4), radius: 24)

                    // Title
                    Text(step.title)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(step.accentColor)
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Body copy
                    Text(step.body)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // Progress dots
                    HStack(spacing: 8) {
                        ForEach(0..<manager.steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == manager.currentStepIndex ? step.accentColor : .white.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }

                    // Action buttons — Skip (if not last) + Next/Begin
                    HStack(spacing: 12) {
                        if manager.currentStepIndex < manager.steps.count - 1 {
                            Button { manager.finish() } label: {
                                Text("Skip")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .tracking(1)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        Button { manager.next() } label: {
                            HStack(spacing: 8) {
                                Text(manager.currentStepIndex == manager.steps.count - 1 ? "Begin" : "Next")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .tracking(2)
                                Image(systemName: manager.currentStepIndex == manager.steps.count - 1 ? "sparkles" : "arrow.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(step.accentColor)
                                    .shadow(color: step.accentColor.opacity(0.5), radius: 12, y: 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
                .animation(.easeInOut(duration: 0.3), value: manager.currentStepIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .zIndex(9999)
        }
    }
}
