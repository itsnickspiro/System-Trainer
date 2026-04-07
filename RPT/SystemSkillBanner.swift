import SwiftUI
import Combine
import AudioToolbox
import UIKit

// MARK: - Model

struct SystemSkillNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String          // e.g. "Unique Skill Acquired"
    let skillName: String      // e.g. "IRON DISCIPLINE"
    let description: String    // e.g. "+5% XP on all Discipline quests"
    let rarity: SkillRarity
    let icon: String           // SF Symbol
    let sound: Bool            // whether to play a system sound

    static func == (lhs: SystemSkillNotification, rhs: SystemSkillNotification) -> Bool {
        lhs.id == rhs.id
    }
}

enum SkillRarity: String {
    case common    = "COMMON"
    case rare      = "RARE"
    case epic      = "EPIC"
    case legendary = "LEGENDARY"
    case mythic    = "MYTHIC"

    var color: Color {
        switch self {
        case .common:    return .white
        case .rare:      return .cyan
        case .epic:      return .purple
        case .legendary: return .yellow
        case .mythic:    return Color(red: 1.0, green: 0.3, blue: 0.5)
        }
    }

    var glowColor: Color { color.opacity(0.6) }
}

// MARK: - Manager

@MainActor
final class SystemNotificationManager: ObservableObject {
    static let shared = SystemNotificationManager()

    @Published private(set) var currentNotification: SystemSkillNotification? = nil
    @Published private(set) var queue: [SystemSkillNotification] = []

    private init() {}

    /// Present a notification. If one is already showing, queue it.
    func present(_ notification: SystemSkillNotification) {
        if currentNotification == nil {
            showImmediately(notification)
        } else {
            queue.append(notification)
        }
    }

    /// Called when the user dismisses the current notification.
    func dismissCurrent() {
        withAnimation(.easeOut(duration: 0.3)) {
            currentNotification = nil
        }
        // Present the next queued notification after a beat
        if let next = queue.first {
            queue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showImmediately(next)
            }
        }
    }

    private func showImmediately(_ notification: SystemSkillNotification) {
        currentNotification = notification
        if notification.sound {
            // System sound 1057 is a pleasant "level up" chime on iOS
            AudioServicesPlaySystemSound(1057)
        }
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    // MARK: - Convenience factories

    /// Trigger on first quest completion ever.
    static var firstQuestComplete: SystemSkillNotification {
        SystemSkillNotification(
            title: "Title Unlocked",
            skillName: "NOVICE ADVENTURER",
            description: "Your first quest is complete. The System recognizes your resolve.",
            rarity: .common,
            icon: "scroll.fill",
            sound: true
        )
    }

    /// Trigger on first workout ever.
    static var firstWorkoutLogged: SystemSkillNotification {
        SystemSkillNotification(
            title: "Skill Acquired",
            skillName: "TRAINED BODY",
            description: "You have begun forging your physical form. All stats now progress naturally.",
            rarity: .common,
            icon: "figure.strengthtraining.traditional",
            sound: true
        )
    }

    /// Trigger when the player crosses level 5.
    static var level5: SystemSkillNotification {
        SystemSkillNotification(
            title: "Rank Promotion",
            skillName: "APPRENTICE OF THE SYSTEM",
            description: "Level 5 achieved. The Guild has taken notice of your dedication.",
            rarity: .rare,
            icon: "star.fill",
            sound: true
        )
    }

    /// Trigger when the player crosses level 10.
    static var level10: SystemSkillNotification {
        SystemSkillNotification(
            title: "Class Specialization Available",
            skillName: "TRUE PATH UNLOCKED",
            description: "Level 10 reached. Your class now grants full bonuses. Check your stats.",
            rarity: .rare,
            icon: "bolt.horizontal.fill",
            sound: true
        )
    }

    /// Trigger when the player crosses level 25.
    static var level25: SystemSkillNotification {
        SystemSkillNotification(
            title: "Awakening Imminent",
            skillName: "ASCENDANT",
            description: "Level 25 reached. Your power level now exceeds most of this world. Keep climbing.",
            rarity: .epic,
            icon: "sparkles",
            sound: true
        )
    }

    /// Trigger when the player completes their first 7-day streak.
    static var firstSevenDayStreak: SystemSkillNotification {
        SystemSkillNotification(
            title: "Passive Skill Acquired",
            skillName: "IRON DISCIPLINE",
            description: "7 consecutive days of consistency. +5% XP on all Discipline quests going forward.",
            rarity: .rare,
            icon: "flame.fill",
            sound: true
        )
    }

    /// Trigger on first 30-day streak.
    static var firstThirtyDayStreak: SystemSkillNotification {
        SystemSkillNotification(
            title: "Legendary Trait Unlocked",
            skillName: "UNBREAKABLE",
            description: "30 consecutive days. Few mortals reach this state. You have been chosen.",
            rarity: .legendary,
            icon: "crown.fill",
            sound: true
        )
    }

    /// Trigger when first PR is set in the workout log.
    static var firstPersonalRecord: SystemSkillNotification {
        SystemSkillNotification(
            title: "Record Shattered",
            skillName: "GROWTH UNLEASHED",
            description: "Your first Personal Record. The System adjusts. Power level recalculated.",
            rarity: .rare,
            icon: "bolt.fill",
            sound: true
        )
    }
}

// MARK: - View

struct SystemSkillBannerView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    @State private var appeared: Bool = false

    var body: some View {
        if let notification = manager.currentNotification {
            ZStack {
                // Dim scrim
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture {
                        manager.dismissCurrent()
                        appeared = false
                    }

                VStack(spacing: 20) {
                    Spacer()

                    // System header
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text("【")
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundColor(notification.rarity.color)
                            Text("SYSTEM")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(notification.rarity.color)
                                .tracking(4)
                            Text("】")
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundColor(notification.rarity.color)
                        }
                        Text(notification.title.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(3)
                    }

                    // Icon hero
                    ZStack {
                        Circle()
                            .fill(notification.rarity.color.opacity(0.15))
                            .frame(width: 140, height: 140)
                        Circle()
                            .stroke(notification.rarity.color, lineWidth: 3)
                            .frame(width: 140, height: 140)
                        Circle()
                            .stroke(notification.rarity.glowColor, lineWidth: 1)
                            .frame(width: 156, height: 156)
                            .blur(radius: 4)
                        Image(systemName: notification.icon)
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundColor(notification.rarity.color)
                    }
                    .shadow(color: notification.rarity.glowColor, radius: 32)
                    .scaleEffect(appeared ? 1.0 : 0.8)

                    // Skill name
                    VStack(spacing: 4) {
                        Text("⸺")
                            .font(.system(size: 24, weight: .ultraLight))
                            .foregroundColor(notification.rarity.color)
                        Text(notification.skillName)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .tracking(2)
                            .padding(.horizontal, 24)
                        Text("⸺")
                            .font(.system(size: 24, weight: .ultraLight))
                            .foregroundColor(notification.rarity.color)
                    }

                    // Rarity badge
                    Text("Rarity: \(notification.rarity.rawValue)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(notification.rarity.color)
                        .tracking(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(notification.rarity.color.opacity(0.18))
                                .overlay(
                                    Capsule().stroke(notification.rarity.color.opacity(0.6), lineWidth: 1)
                                )
                        )

                    // Description
                    Text(notification.description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // Dismiss hint
                    Text("tap anywhere to continue")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                        .padding(.bottom, 40)
                }
                .opacity(appeared ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.4), value: appeared)
            }
            .zIndex(10000)
            .transition(.opacity)
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
        }
    }
}
