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
// Gold Pieces (GP) are a secondary currency. Items may have a credit_price in
// addition to the XP price. Use PaymentMethod to select which currency to use
// when calling purchase().
//
// Usage:
//   await StoreService.shared.refresh()
//   StoreService.shared.storeItems         // items for sale
//   StoreService.shared.inventory          // items the player owns
//   StoreService.shared.equippedBonuses    // stat bonuses to add to base stats
//   StoreService.shared.activeXPMultiplier // multiply all XP by this value
//   StoreService.shared.playerCredits      // player's current GP balance
//   StoreService.shared.currencyName       // "Gold Pieces"
//   StoreService.shared.saleActive         // true when a sale is running

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

    /// Player's current Gold Pieces balance (mirrors PlayerProfileService.shared.systemCredits).
    @Published private(set) var playerCredits: Int = 0

    // MARK: - Currency Metadata
    @Published private(set) var currencyName:   String = "Gold Pieces"
    @Published private(set) var currencySymbol: String = "GP"
    @Published private(set) var currencyIcon:   String = "centsign.circle.fill"

    // MARK: - Sale Info
    @Published private(set) var saleActive: Bool   = false
    @Published private(set) var salePct:    Int    = 0   // e.g. 20 for 20% off

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

        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return }

        do {
            let payload = try await fetchStore(cloudKitUserID: cloudKitID)

            if !payload.store.isEmpty {
                storeItems = payload.store
                try? JSONEncoder().encode(payload.store).write(to: Self.catalogCacheURL, options: .atomic)
            }

            inventory = payload.inventory

            // Apply currency metadata from server
            if let currency = payload.currency {
                currencyName   = currency.name
                currencySymbol = currency.symbol
                currencyIcon   = currency.icon
            }

            // Apply sale info
            if let sale = payload.sale {
                saleActive = sale.active
                salePct    = sale.pct
            } else {
                saleActive = false
                salePct    = 0
            }

            // Mirror GP balance from server (server is authoritative)
            if let serverCredits = payload.playerCredits {
                playerCredits = serverCredits
            } else {
                playerCredits = PlayerProfileService.shared.systemCredits
            }

            recomputeBonuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchase(itemKey: String, method: PaymentMethod = .xp) async -> Bool {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
              !cloudKitID.isEmpty else { return false }

        guard let item = storeItems.first(where: { $0.key == itemKey }) else { return false }

        // Optimistic deduction based on payment method
        switch method {
        case .xp:
            DataManager.shared.addXPToProfile(-item.finalPriceXP, source: "Store: \(item.name)")
        case .goldPieces:
            playerCredits = max(0, playerCredits - item.finalPriceCredits)
        }

        do {
            var body: [String: Any] = [
                "action": "purchase",
                "cloudkit_user_id": cloudKitID,
                "item_key": itemKey
            ]
            if method == .goldPieces {
                body["pay_with"] = "credits"
            }
            try await postToProxy(body: body)
            await refresh()
            return true
        } catch {
            // Revert optimistic deduction
            switch method {
            case .xp:
                DataManager.shared.addXPToProfile(item.finalPriceXP, source: "Store refund: \(item.name)")
            case .goldPieces:
                playerCredits = PlayerProfileService.shared.systemCredits
            }
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Equip / Unequip

    func equip(itemKey: String, equip: Bool) async {
        guard let cloudKitID = LeaderboardService.shared.currentUserID,
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
            case "consumable" where entry.isActive,
                 "boost" where entry.isActive:
                // XP multiplier
                if let mult = item.xpMultiplier {
                    xpMult *= mult
                }
                // Stat bonuses from active consumables/boosts
                bonuses.strength  += item.bonusStrength  ?? 0
                bonuses.endurance += item.bonusEndurance ?? 0
                bonuses.energy    += item.bonusEnergy    ?? 0
                bonuses.focus     += item.bonusFocus     ?? 0
                bonuses.health    += item.bonusHealth    ?? 0
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
        return (try? JSONDecoder().decode(StorePayload.self, from: data))
            ?? StorePayload(store: [], inventory: [], currency: nil, sale: nil, playerCredits: nil)
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

struct StoreItem: Codable, Identifiable {
    var id: String { key }

    let key:           String
    let name:          String
    let description:   String
    let iconSymbol:    String
    let itemType:      String   // "equipment" | "consumable" | "cosmetic"
    let rarity:        String   // "common" | "rare" | "epic" | "legendary"
    let price:         Int      // Base XP cost
    let creditPrice:   Int?     // Base GP cost (nil if XP-only item)
    let storeSection:  String   // "featured" | "daily" | "weekly" | "permanent"
    let isEnabled:     Bool

    // Server-computed sale prices (present when a sale is active)
    let finalPriceXP:         Int     // price after any active discount
    let finalPriceCredits:    Int     // creditPrice after any active discount (0 if XP-only)
    let effectiveDiscountPct: Int     // 0–100; 0 when no sale

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
        case creditPrice          = "credit_price"
        case iconSymbol           = "icon_symbol"
        case itemType             = "item_type"
        case storeSection         = "store_section"
        case isEnabled            = "is_enabled"
        case finalPriceXP         = "final_price_xp"
        case finalPriceCredits    = "final_price_credits"
        case effectiveDiscountPct = "effective_discount_pct"
        case bonusStrength        = "bonus_strength"
        case bonusEndurance       = "bonus_endurance"
        case bonusEnergy          = "bonus_energy"
        case bonusFocus           = "bonus_focus"
        case bonusHealth          = "bonus_health"
        case xpMultiplier         = "xp_multiplier"
    }

    /// Custom init so we can fall back to `price` when server omits final_price_xp.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key          = try c.decode(String.self, forKey: .key)
        name         = try c.decode(String.self, forKey: .name)
        description  = try c.decode(String.self, forKey: .description)
        iconSymbol   = try c.decode(String.self, forKey: .iconSymbol)
        itemType     = try c.decode(String.self, forKey: .itemType)
        rarity       = try c.decode(String.self, forKey: .rarity)
        price        = try c.decode(Int.self, forKey: .price)
        creditPrice  = try c.decodeIfPresent(Int.self, forKey: .creditPrice)
        storeSection = try c.decode(String.self, forKey: .storeSection)
        isEnabled    = try c.decode(Bool.self, forKey: .isEnabled)
        finalPriceXP         = (try? c.decode(Int.self, forKey: .finalPriceXP))         ?? price
        finalPriceCredits    = (try? c.decode(Int.self, forKey: .finalPriceCredits))    ?? (creditPrice ?? 0)
        effectiveDiscountPct = (try? c.decode(Int.self, forKey: .effectiveDiscountPct)) ?? 0
        bonusStrength  = try c.decodeIfPresent(Double.self, forKey: .bonusStrength)
        bonusEndurance = try c.decodeIfPresent(Double.self, forKey: .bonusEndurance)
        bonusEnergy    = try c.decodeIfPresent(Double.self, forKey: .bonusEnergy)
        bonusFocus     = try c.decodeIfPresent(Double.self, forKey: .bonusFocus)
        bonusHealth    = try c.decodeIfPresent(Double.self, forKey: .bonusHealth)
        xpMultiplier   = try c.decodeIfPresent(Double.self, forKey: .xpMultiplier)
    }

    var rarityColor: Color {
        switch rarity {
        case "legendary": return .orange
        case "epic":      return .purple
        case "rare":      return .blue
        default:          return .gray
        }
    }

    /// True when this item has a GP price and GP purchases are possible.
    var hasCreditPrice: Bool { (creditPrice ?? 0) > 0 }
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

// MARK: - Payment Method

/// Selects which currency to use when purchasing a store item.
enum PaymentMethod: Equatable {
    case xp
    case goldPieces
}

// MARK: - Wire Models (private)

private struct StorePayload: Decodable {
    let store:          [StoreItem]
    let inventory:      [InventoryEntry]
    let currency:       StoreCurrencyInfo?
    let sale:           StoreSaleInfo?
    let playerCredits:  Int?

    enum CodingKeys: String, CodingKey {
        case store, inventory, currency, sale
        case playerCredits = "player_credits"
    }
}

private struct StoreCurrencyInfo: Decodable {
    let name:   String
    let symbol: String
    let icon:   String
}

private struct StoreSaleInfo: Decodable {
    let active: Bool
    let pct:    Int
}
