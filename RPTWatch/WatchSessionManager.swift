import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity manager. Receives stats from iPhone
/// and sends workout completion messages back.
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    // MARK: - Published stats (updated from iPhone)

    @Published var playerName: String = "Player"
    @Published var level: Int = 1
    @Published var xp: Int = 0
    @Published var xpToNextLevel: Int = 100
    @Published var currentStreak: Int = 0
    @Published var bestStreak: Int = 0
    @Published var activeQuestCount: Int = 0
    @Published var activeQuests: [[String: Any]] = []
    @Published var isConnected: Bool = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send a workout completion message to the iPhone.
    func completeWorkout(type: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "complete_workout", "workout_type": type],
            replyHandler: nil
        )
    }

    /// Send a quest completion message to the iPhone.
    func completeQuest(id: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "complete_quest", "quest_id": id],
            replyHandler: nil
        )
    }

    /// Request a stats refresh from the iPhone.
    func requestRefresh() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "request_refresh"],
            replyHandler: nil
        )
    }

    private func applyStats(_ stats: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let name = stats["player_name"] as? String { self.playerName = name }
            if let lvl = stats["level"] as? Int { self.level = lvl }
            if let x = stats["xp"] as? Int { self.xp = x }
            if let xtn = stats["xp_to_next_level"] as? Int { self.xpToNextLevel = xtn }
            if let streak = stats["current_streak"] as? Int { self.currentStreak = streak }
            if let best = stats["best_streak"] as? Int { self.bestStreak = best }
            if let count = stats["active_quest_count"] as? Int { self.activeQuestCount = count }
            if let quests = stats["active_quests"] as? [[String: Any]] { self.activeQuests = quests }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = activationState == .activated
        }
        if activationState == .activated {
            applyStats(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyStats(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyStats(message)
    }
}
