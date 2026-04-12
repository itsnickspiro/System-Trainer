import Foundation
import Combine
import WatchConnectivity

/// Watch-side WatchConnectivity manager. Receives stats from iPhone
/// and sends session start messages back. Read-only for quests —
/// quests can only be completed on the iPhone.
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

    // MARK: - Health stats (sent from iPhone)

    @Published var steps: Int = 0
    @Published var caloriesBurned: Int = 0
    @Published var heartRate: Int = 0
    @Published var sleepHours: Double = 0

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Tell the iPhone to open the training screen / start a session.
    func startSession() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "start_session"],
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

            // Health stats
            if let s = stats["steps"] as? Int { self.steps = s }
            if let cal = stats["calories_burned"] as? Int { self.caloriesBurned = cal }
            if let hr = stats["heart_rate"] as? Int { self.heartRate = hr }
            if let sleep = stats["sleep_hours"] as? Double { self.sleepHours = sleep }
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
