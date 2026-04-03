import Combine
import Foundation
import SwiftUI

// MARK: - AvatarService
//
// Manages the player's avatar selection via the avatars-proxy Edge Function.
//
// On launch: fetches the full avatar catalog (name, rarity, unlock requirements)
// and the player's current equipped avatar. Catalog is disk-cached.
//
// Usage:
//   await AvatarService.shared.refresh()
//   AvatarService.shared.catalog      // all AvatarTemplate items
//   AvatarService.shared.current      // currently equipped AvatarTemplate (or nil)
//   await AvatarService.shared.setAvatar(key: "avatar_warrior_m")

@MainActor
final class AvatarService: ObservableObject {

    static let shared = AvatarService()

    @Published private(set) var isLoading    = false
    @Published private(set) var lastError: String? = nil

    /// Full catalog — all available avatars, including locked ones.
    @Published private(set) var catalog: [AvatarTemplate] = []

    /// The currently equipped avatar (nil until first refresh).
    @Published private(set) var current: AvatarTemplate? = nil

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/avatars-proxy"
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("avatar_catalog_cache.json")
    }()

    private init() {
        catalog = (try? JSONDecoder().decode([AvatarTemplate].self,
                                             from: Data(contentsOf: Self.cacheURL))) ?? []
        current = catalog.first { $0.isEquipped }
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        let body: [String: Any] = [
            "action":           "get_catalog",
            "cloudkit_user_id": cloudKitID
        ]

        do {
            let data = try await postToProxy(body: body)
            guard !data.isEmpty else { return }
            let templates = try JSONDecoder().decode([AvatarTemplate].self, from: data)
            catalog = templates
            current = templates.first { $0.isEquipped }
            try? JSONEncoder().encode(templates).write(to: Self.cacheURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Set Avatar

    /// Equips the avatar with the given key. Updates the local state optimistically,
    /// then syncs to Supabase and refreshes the leaderboard display name entry.
    func setAvatar(key: String) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        // Optimistic local update
        catalog = catalog.map { t in
            var copy = t
            copy.isEquipped = (t.key == key)
            return copy
        }
        current = catalog.first { $0.isEquipped }

        let body: [String: Any] = [
            "action":           "set_avatar",
            "cloudkit_user_id": cloudKitID,
            "avatar_key":       key
        ]

        do {
            try await postToProxy(body: body)
            // Re-fetch to confirm server state
            await refresh()
            // Update leaderboard entry so the new avatar_key propagates
            await LeaderboardService.shared.upsertEntry()
        } catch {
            lastError = error.localizedDescription
            // Revert on failure
            await refresh()
        }
    }

    // MARK: - GP Purchase

    /// Purchases a GP-priced avatar then equips it.
    func purchaseAndEquip(key: String) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return false }

        let body: [String: Any] = [
            "action":           "purchase_avatar",
            "cloudkit_user_id": cloudKitID,
            "avatar_key":       key
        ]

        do {
            try await postToProxy(body: body)
            await refresh()
            await LeaderboardService.shared.upsertEntry()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Network

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

// MARK: - AvatarTemplate

struct AvatarTemplate: Codable, Identifiable {
    var id: String { key }

    let key:                    String
    let name:                   String
    let description:            String
    let category:               String   // "free" | "warrior" | "mage" | "rogue" | "tank" | "anime" | "event"
    let rarity:                 String   // "common" | "rare" | "epic" | "legendary"
    let unlockType:             String   // "free" | "level" | "achievement" | "gp" | "event"
    let unlockLevel:            Int?     // required player level (unlockType == "level")
    let unlockAchievementKey:   String?  // achievement key required (unlockType == "achievement")
    let gpPrice:                Int?     // GP cost (unlockType == "gp")
    let accentColor:            String   // hex string e.g. "#00FFFF"
    var isUnlocked:             Bool
    var isEquipped:             Bool

    enum CodingKeys: String, CodingKey {
        case key, name, description, category, rarity
        case unlockType             = "unlock_type"
        case unlockLevel            = "unlock_level"
        case unlockAchievementKey   = "unlock_achievement_key"
        case gpPrice                = "gp_price"
        case accentColor            = "accent_color"
        case isUnlocked             = "is_unlocked"
        case isEquipped             = "is_equipped"
    }

    /// SwiftUI Color parsed from the hex accent_color string.
    var color: Color {
        Color(hex: accentColor) ?? .cyan
    }

    var rarityColor: Color {
        switch rarity {
        case "legendary": return .orange
        case "epic":      return .purple
        case "rare":      return .blue
        default:          return .gray
        }
    }

    /// Human-readable unlock requirement string shown on locked cells.
    var unlockRequirement: String {
        switch unlockType {
        case "level":
            return "Level \(unlockLevel ?? 0)"
        case "achievement":
            if let key = unlockAchievementKey {
                return key.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return "Achievement"
        case "gp":
            return "\(gpPrice ?? 0) GP"
        case "event":
            return "Event Exclusive"
        default:
            return "Free"
        }
    }
}


