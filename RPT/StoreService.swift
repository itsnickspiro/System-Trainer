import Combine
import Foundation
import SwiftUI

// MARK: - StoreService
//
// Manages the item store and player inventory via the store-proxy Edge Function.
//
// On launch: fetches store catalog (items for sale) and the player's inventory.
// Catalog is disk-cached. Inventory is refreshed on every launch.
//
// Equipped equipment items sum all bonus_* stat fields into equippedBonuses,
// which DataManager adds to displayed player stats.
//
// Active XP boost consumables expose activeXPMultiplier, which DataManager
// multiplies all XP awards by.
//
// Usage:
//   await StoreService.shared.refresh()
//   StoreService.shared.storeItems        // items for sale
//   StoreService.shared.inventory         // items the player owns
//   StoreService.shared.equippedBonuses   // stat bonuses to add to base stats
//   StoreService.shared.activeXPMultiplier // multiply all XP by this value

@MainActor
final class StoreService: ObservableObject {

    static let shared = StoreService()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = nil

    @Published private(set) var storeItems: [StoreItem] = []
    @Published private(set) var inventory: [InventoryEntry] = []

    /// Sum of all bonus_* fields from equipped equipment items.
    @Published private(set) var equippedBonuses = StatBonuses()

    /// Multiplier from active XP-boost consumables (1.0 = no boost).
    @Published private(set) var activeXPMultiplier: Double = 1.0

    private static let proxyURL = "\(Secrets.supabaseURL)/functions/v1/store-proxy"
    private static let catalogCacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("store_catalog_cache.json")
    }()

    private init() {
        // Load cached catalog so the store tab can display immediately
        storeItems = (try? JSONDecoder().decode([StoreItem].self,
                                                from: Data(contentsOf: Self.catalogCacheURL))) ?? []
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard let cloudKitID = CloudKitLeaderboardManager.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        do {
            let payload = try await fetchStore(cloudKitUserID: cloudKitID)

            if !payload.store.isEmpty {
                storeItems = payload.store
                try? JSONEncoder().encode(payload.store).write(to: Self.catalogCacheURL, options: .atomic)
            }

            inventory = payload.inventory
            recomputeBonuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchase(itemKey: String) async -> Bool {
        guard let cloudKitID = CloudKitLeaderboardManager.shared.currentUserID,
              !cloudKitID.isEmpty else { return false }

        guard let item = storeItems.first(where: { $0.key == itemKey }) else { return false }

        // Optimistic XP deduction
        DataManager.shared.addXPToProfile(-item.price, source: "Store: \(item.name)")

        do {
            let body: [String: Any] = [
                "action": "purchase",
                "cloudkit_user_id": cloudKitID,
                "item_key": itemKey
            ]
            try await postToProxy(body: body)
            await refresh()
            return true
        } catch {
            // Revert optimistic deduction
            DataManager.shared.addXPToProfile(item.price, source: "Store refund: \(item.name)")
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Equip / Unequip

    func equip(itemKey: String, equip: Bool) async {
        guard let cloudKitID = CloudKitLeaderboardManager.shared.currentUserID,
              !cloudKitID.isEmpty else { return }
        do {
            let body: [String: Any] = [
                "action": "equip",
                "cloudkit_user_id": cloudKitID,
                "item_key": itemKey,
                "equip": equip
            ]
            try await postToProxy(body: body)
            // Update local state optimistically
            if let idx = inventory.firstIndex(where: { $0.key == itemKey }) {
                inventory[idx].isEquipped = equip
            }
            recomputeBonuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Bonus Computation

    private func recomputeBonuses() {
        var bonuses = StatBonuses()
        var xpMult = 1.0

        for entry in inventory where entry.isEquipped {
            guard let item = storeItems.first(where: { $0.key == entry.key }) else { continue }

            switch item.itemType {
            case "equipment":
                bonuses.strength  += item.bonusStrength  ?? 0
                bonuses.endurance += item.bonusEndurance ?? 0
                bonuses.energy    += item.bonusEnergy    ?? 0
                bonuses.focus     += item.bonusFocus     ?? 0
                bonuses.health    += item.bonusHealth    ?? 0
            case "consumable":
                if let mult = item.xpMultiplier, entry.isActive {
                    xpMult *= mult
                }
            default:
                break
            }
        }

        equippedBonuses  = bonuses
        activeXPMultiplier = xpMult
    }

    // MARK: - Network

    private func fetchStore(cloudKitUserID: String) async throws -> StorePayload {
        let body: [String: Any] = [
            "action": "get_store",
            "cloudkit_user_id": cloudKitUserID
        ]
        let data = try await postToProxy(body: body)
        return (try? JSONDecoder().decode(StorePayload.self, from: data)) ?? StorePayload(store: [], inventory: [])
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
            return Data()
        }
        return data
    }
}

// MARK: - Public Models

struct StoreItem: Codable, Identifiable {
    var id: String { key }

    let key:           String
    let name:          String
    let description:   String
    let iconSymbol:    String
    let itemType:      String   // "equipment" | "consumable" | "cosmetic"
    let rarity:        String   // "common" | "rare" | "epic" | "legendary"
    let price:         Int      // XP cost
    let storeSection:  String   // "featured" | "daily" | "weekly" | "permanent"
    let isEnabled:     Bool

    // Stat bonuses (equipment only)
    let bonusStrength:  Double?
    let bonusEndurance: Double?
    let bonusEnergy:    Double?
    let bonusFocus:     Double?
    let bonusHealth:    Double?

    // Consumable XP boost multiplier
    let xpMultiplier:   Double?

    enum CodingKeys: String, CodingKey {
        case key, name, description, rarity, price
        case iconSymbol    = "icon_symbol"
        case itemType      = "item_type"
        case storeSection  = "store_section"
        case isEnabled     = "is_enabled"
        case bonusStrength  = "bonus_strength"
        case bonusEndurance = "bonus_endurance"
        case bonusEnergy   = "bonus_energy"
        case bonusFocus    = "bonus_focus"
        case bonusHealth   = "bonus_health"
        case xpMultiplier  = "xp_multiplier"
    }

    var rarityColor: Color {
        switch rarity {
        case "legendary": return .orange
        case "epic":      return .purple
        case "rare":      return .blue
        default:          return .gray
        }
    }
}

struct InventoryEntry: Codable, Identifiable {
    var id: String { key }

    let key:      String
    let quantity: Int
    var isEquipped: Bool
    var isActive:   Bool   // for consumables: currently consuming XP boost

    enum CodingKeys: String, CodingKey {
        case key, quantity
        case isEquipped = "is_equipped"
        case isActive   = "is_active"
    }
}

struct StatBonuses {
    var strength:  Double = 0
    var endurance: Double = 0
    var energy:    Double = 0
    var focus:     Double = 0
    var health:    Double = 0
}

// MARK: - Wire Model (private)

private struct StorePayload: Decodable {
    let store:     [StoreItem]
    let inventory: [InventoryEntry]
}
