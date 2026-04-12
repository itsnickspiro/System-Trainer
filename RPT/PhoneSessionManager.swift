import Foundation
import WatchConnectivity

/// iPhone-side WatchConnectivity manager. Sends stats to the Watch
/// and handles session start requests. Quest completion is NOT
/// supported from the Watch — quests must be completed on the iPhone.
@MainActor
final class PhoneSessionManager: NSObject {

    static let shared = PhoneSessionManager()

    private override init() {
        super.init()
    }

    /// Call once during app launch (after DataManager + LeaderboardService are ready).
    nonisolated func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push the current player stats to the Watch. Call after any significant
    /// change (quest completion, level up, XP gain, streak change).
    func sendStats() {
        guard WCSession.default.activationState == .activated else { return }

        guard let profile = DataManager.shared.currentProfile else { return }

        // Gather active (incomplete, today's) quests
        let quests = DataManager.shared.todaysQuests
            .filter { !$0.isCompleted }
            .prefix(10)
            .map { quest -> [String: Any] in
                [
                    "id": quest.id.uuidString,
                    "title": quest.title,
                    "description": quest.details,
                    "xp_reward": quest.xpReward,
                    "is_completed": quest.isCompleted,
                ]
            }

        var stats: [String: Any] = [
            "player_name": profile.name,
            "level": profile.level,
            "xp": profile.xp,
            "xp_to_next_level": xpForNextLevel(profile.level),
            "current_streak": profile.currentStreak,
            "best_streak": profile.bestStreak,
            "active_quest_count": quests.count,
            "active_quests": Array(quests),
        ]

        // Health stats from profile
        stats["steps"] = profile.dailySteps
        stats["calories_burned"] = profile.dailyActiveCalories
        stats["heart_rate"] = profile.restingHeartRate
        stats["sleep_hours"] = profile.sleepHours

        try? WCSession.default.updateApplicationContext(stats)
    }

    private func xpForNextLevel(_ currentLevel: Int) -> Int {
        // Match the same XP curve used in DataManager
        return currentLevel * 100
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            Task { @MainActor in
                sendStats()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        Task { @MainActor in
            switch action {
            case "start_session":
                handleStartSession()
            case "request_refresh":
                sendStats()
            default:
                break
            }
        }
    }

    // MARK: - Handlers

    @MainActor
    private func handleStartSession() {
        // Post a notification that the training tab can listen for
        NotificationCenter.default.post(name: .watchRequestedSession, object: nil)
        sendStats()
    }
}

extension Notification.Name {
    static let watchRequestedSession = Notification.Name("watchRequestedSession")
}
