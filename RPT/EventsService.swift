import Combine
import Foundation
import SwiftUI

// MARK: - EventsService
//
// Fetches special events and player participation records via the events-proxy
// Edge Function.
//
// Active events with an xp_multiplier are combined with StoreService's
// activeXPMultiplier in DataManager.
//
// Progress is updated after every workout logged and quest completed by calling
// updateAllEventProgress().
//
// Events are cached to disk and refreshed on launch.
//
// Usage:
//   await EventsService.shared.refresh()
//   EventsService.shared.activeEvents           // events to show in UI
//   EventsService.shared.activeXPMultiplier     // combined event XP boost

@MainActor
final class EventsService: ObservableObject {

    static let shared = EventsService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    @Published private(set) var activeEvents: [GameEvent] = []
    @Published private(set) var participations: [EventParticipation] = []

    /// Combined XP multiplier from any joined events (1.0 = none).
    @Published private(set) var activeXPMultiplier: Double = 1.0

    /// Combined GP credit multiplier from any joined events (1.0 = none).
    @Published private(set) var activeCreditMultiplier: Double = 1.0

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/events-proxy"
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("events_cache.json")
    }()

    private init() {
        activeEvents = (try? JSONDecoder().decode([GameEvent].self,
                                                   from: Data(contentsOf: Self.cacheURL))) ?? []
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        do {
            let payload = try await fetchEvents(cloudKitUserID: cloudKitID)

            if !payload.events.isEmpty {
                activeEvents = payload.events
                try? JSONEncoder().encode(payload.events).write(to: Self.cacheURL, options: .atomic)
            }

            participations = payload.participations
            recomputeMultiplier()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Join Event

    func joinEvent(key: String) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }
        do {
            let body: [String: Any] = [
                "action": "join_event",
                "cloudkit_user_id": cloudKitID,
                "event_key": key
            ]
            try await postToProxy(body: body)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Update Progress

    /// Update progress for a single event.
    func updateProgress(key: String, progress: Double) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }
        do {
            let body: [String: Any] = [
                "action": "update_progress",
                "cloudkit_user_id": cloudKitID,
                "event_key": key,
                "progress": progress
            ]
            try await postToProxy(body: body)
            // Refresh participation record for this event only (lightweight)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Notify all joined events that activity happened.
    /// Called after every workout logged and quest completed from DataManager.
    func updateAllEventProgress() async {
        let joinedKeys = participations.map { $0.eventKey }
        guard !joinedKeys.isEmpty else { return }

        // Increment progress by 1 unit per activity for all joined events
        for key in joinedKeys {
            let current = participations.first(where: { $0.eventKey == key })?.progress ?? 0
            await updateProgress(key: key, progress: current + 1)
        }
    }

    // MARK: - Claim Reward

    func claimReward(event: GameEvent) async {
        guard let rewardItemKey = event.rewardItemKey else { return }
        // Delegate to StoreService to "purchase" the reward item at 0 cost
        _ = await StoreService.shared.purchase(itemKey: rewardItemKey)
    }

    // MARK: - Private Helpers

    private func recomputeMultiplier() {
        var xpMult = 1.0
        var creditMult = 1.0
        for p in participations {
            guard let event = activeEvents.first(where: { $0.key == p.eventKey }) else { continue }
            if let m = event.xpMultiplier      { xpMult     *= m }
            if let m = event.creditMultiplier  { creditMult *= m }
        }
        activeXPMultiplier     = xpMult
        activeCreditMultiplier = creditMult
    }

    // MARK: - Network

    private func fetchEvents(cloudKitUserID: String) async throws -> EventsPayload {
        let body: [String: Any] = [
            "action": "get_events",
            "cloudkit_user_id": cloudKitUserID
        ]
        let data = try await postToProxy(body: body)
        return (try? JSONDecoder().decode(EventsPayload.self, from: data))
            ?? EventsPayload(events: [], participations: [])
    }

    @discardableResult
    private func postToProxy(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.proxyURL) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Public Models

struct GameEvent: Codable, Identifiable {
    var id: String { key }

    let key:          String
    let title:        String
    let description:  String
    let iconSymbol:   String
    let goalType:     String?  // "workouts" | "quests" | "steps" | "xp"
    let goalTarget:   Double?
    let xpMultiplier:     Double?
    let creditMultiplier: Double?
    let rewardItemKey:    String?
    let endsAt:           Date?
    let isEnabled:        Bool

    enum CodingKeys: String, CodingKey {
        case key, title, description, rarity
        case iconSymbol      = "icon_symbol"
        case goalType        = "individual_goal_type"
        case goalTarget      = "individual_goal_value"
        case xpMultiplier    = "xp_multiplier"
        case creditMultiplier = "credit_multiplier"
        case rewardItemKey   = "reward_item_key"
        case endsAt          = "ends_at"
        case isEnabled       = "is_enabled"
    }

    // Initialise endsAt from an ISO-8601 string
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key              = try c.decode(String.self, forKey: .key)
        title            = try c.decode(String.self, forKey: .title)
        description      = try c.decode(String.self, forKey: .description)
        iconSymbol       = try c.decode(String.self, forKey: .iconSymbol)
        goalType         = try c.decodeIfPresent(String.self, forKey: .goalType)
        goalTarget       = try c.decodeIfPresent(Double.self, forKey: .goalTarget)
        xpMultiplier     = try c.decodeIfPresent(Double.self, forKey: .xpMultiplier)
        creditMultiplier = try c.decodeIfPresent(Double.self, forKey: .creditMultiplier)
        rewardItemKey    = try c.decodeIfPresent(String.self, forKey: .rewardItemKey)
        isEnabled        = try c.decode(Bool.self, forKey: .isEnabled)

        if let dateStr = try c.decodeIfPresent(String.self, forKey: .endsAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            endsAt = iso.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr)
        } else {
            endsAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key,          forKey: .key)
        try c.encode(title,        forKey: .title)
        try c.encode(description,  forKey: .description)
        try c.encode(iconSymbol,   forKey: .iconSymbol)
        try c.encodeIfPresent(goalType,     forKey: .goalType)
        try c.encodeIfPresent(goalTarget,   forKey: .goalTarget)
        try c.encodeIfPresent(xpMultiplier,     forKey: .xpMultiplier)
        try c.encodeIfPresent(creditMultiplier, forKey: .creditMultiplier)
        try c.encodeIfPresent(rewardItemKey,    forKey: .rewardItemKey)
        try c.encode(isEnabled,    forKey: .isEnabled)
        if let d = endsAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(iso.string(from: d), forKey: .endsAt)
        }
    }
}

struct EventParticipation: Codable, Identifiable {
    var id: String { eventKey }

    let eventKey:  String
    var progress:  Double
    let isCompleted: Bool
    let rewardClaimed: Bool

    enum CodingKeys: String, CodingKey {
        case eventKey      = "event_key"
        case progress      = "current_progress"
        case isCompleted   = "goal_completed"
        case rewardClaimed = "reward_claimed"
    }
}

// MARK: - Wire Models (private)

private struct EventsPayload: Decodable {
    let events:         [GameEvent]
    let participations: [EventParticipation]
}

// MARK: - Active Event Card View

/// A card shown on HomeView for each active event the player has joined or can join.
struct ActiveEventCard: View {
    let event: GameEvent
    let participation: EventParticipation?
    let onJoin: () -> Void
    let onClaimReward: () -> Void

    @State private var timeRemaining = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var isJoined: Bool { participation != nil }
    var progress: Double { participation?.progress ?? 0 }
    var fraction: Double { min(1.0, progress / max(1, event.goalTarget ?? 1)) }
    var isCompleted: Bool { participation?.isCompleted == true }
    var rewardClaimed: Bool { participation?.rewardClaimed == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: event.iconSymbol)
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline.weight(.bold))
                    if !timeRemaining.isEmpty {
                        Text("Ends in \(timeRemaining)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                if let mult = event.xpMultiplier {
                    Text("×\(String(format: "%.1f", mult)) XP")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.15), in: Capsule())
                }
            }

            Text(event.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Progress
            if isJoined {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int(progress)) / \(Int(event.goalTarget ?? 0)) \(event.goalType ?? "")")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: fraction)
                        .tint(.orange)
                }
            }

            // CTA
            HStack {
                Spacer()
                if !isJoined {
                    Button("Join Event", action: onJoin)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .font(.subheadline.weight(.semibold))
                } else if isCompleted && !rewardClaimed {
                    Button("Claim Reward", action: onClaimReward)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .font(.subheadline.weight(.semibold))
                } else if isCompleted {
                    Label("Reward Claimed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .onReceive(timer) { _ in updateCountdown() }
        .onAppear { updateCountdown() }
    }

    private func updateCountdown() {
        guard let end = event.endsAt else { timeRemaining = ""; return }
        let diff = end.timeIntervalSinceNow
        guard diff > 0 else { timeRemaining = "Ended"; return }

        let days  = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600
        let mins  = (Int(diff) % 3600) / 60
        let secs  = Int(diff) % 60

        if days > 0 {
            timeRemaining = "\(days)d \(hours)h"
        } else if hours > 0 {
            timeRemaining = "\(hours)h \(mins)m"
        } else {
            timeRemaining = "\(mins)m \(secs)s"
        }
    }
}
