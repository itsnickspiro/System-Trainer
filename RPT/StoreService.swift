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
        // Start empty; load cached catalog off-main so init() returns instantly on cold launch.
        storeItems = []
        Task.detached(priority: .utility) { [weak self] in
            let url = await Self.catalogCacheURL
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([StoreItem].self, from: data),
                  !decoded.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.storeItems = decoded
            }
        }
    }

    /// Timestamp of the last successful refresh. Used by the 5-minute staleness gate.
    private var lastSuccessfulRefreshAt: Date = .distantPast

    // MARK: - Refresh

    func refresh(force: Bool = false) async {
        // Catalog + inventory changes infrequently; skip the network round-trip
        // if we refreshed successfully within the last 5 minutes.
        if !force, Date().timeIntervalSince(lastSuccessfulRefreshAt) < 300 {
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Use CloudKit ID if available; fall back to "anonymous" so the
        // catalog still loads even when CloudKit resolution hasn't finished.
        // The server returns an empty inventory for unknown IDs, which is fine.
        let cloudKitID = LeaderboardService.shared.currentUserID ?? ""
        let effectiveID = cloudKitID.isEmpty ? "anonymous" : cloudKitID

        do {
            let payload = try await fetchStore(cloudKitUserID: effectiveID)

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
            lastSuccessfulRefreshAt = Date()

            // Run the store item effect audit in DEBUG builds only.
            // Surfaces mismatches between StoreItemEffectSpec.knownSpecs
            // and the live catalog — silently-broken items caused the
            // pre-F7 audit that uncovered Discipline Crown +4 doing
            // nothing, 14 equipment items with zero effect, etc.
            // Runs at catalog refresh time so issues show up in the
            // console the first time after a bad row lands.
            #if DEBUG
            StoreItemEffectAudit.auditAndLog()
            #endif
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
            await refresh(force: true)
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

        // Store audit fixes (pre-F7):
        //   1. Discipline was silently dropped — 3 equipment items advertised
        //      bonuses that never applied (Discipline Crown +4, System Armor +5,
        //      Warrior's Mantle +2). The StoreItem decoder now reads
        //      bonus_discipline from the server, and this loop aggregates it.
        //   2. Equipment XP multiplier was never applied — the `consumable`
        //      branch was the only site that read `xpMultiplier`, so equipment
        //      with bonus_xp_multiplier > 1 (e.g. System Armor 1.1x) did
        //      nothing. Moved xpMult aggregation out of the switch so it
        //      applies to all equipped/active items regardless of type.
        for entry in inventory {
            let isActiveConsumable = (entry.isActive && (entry.isEquipped == false))
            let shouldApply = entry.isEquipped || isActiveConsumable || entry.isActive
            guard shouldApply else { continue }
            guard let item = storeItems.first(where: { $0.key == entry.key }) else { continue }

            switch item.itemType {
            case "equipment":
                guard entry.isEquipped else { continue }
                bonuses.strength   += item.bonusStrength   ?? 0
                bonuses.endurance  += item.bonusEndurance  ?? 0
                bonuses.discipline += item.bonusDiscipline ?? 0
                bonuses.energy     += item.bonusEnergy     ?? 0
                bonuses.focus      += item.bonusFocus      ?? 0
                bonuses.health     += item.bonusHealth     ?? 0
                if let mult = item.xpMultiplier, mult > 1 {
                    xpMult *= mult
                }
            case "consumable", "boost":
                guard entry.isActive else { continue }
                if let mult = item.xpMultiplier, mult > 1 {
                    xpMult *= mult
                }
                bonuses.strength   += item.bonusStrength   ?? 0
                bonuses.endurance  += item.bonusEndurance  ?? 0
                bonuses.discipline += item.bonusDiscipline ?? 0
                bonuses.energy     += item.bonusEnergy     ?? 0
                bonuses.focus      += item.bonusFocus      ?? 0
                bonuses.health     += item.bonusHealth     ?? 0
            default:
                // avatar_frame, badge, cosmetic, title — no numeric effect to aggregate here.
                // Their effect is visual and applied elsewhere (avatar picker,
                // leaderboard row rendering, etc.).
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

        // Session 2 bug fix: the previous version used `try?` here which
        // silently swallowed any decode failure and returned an empty
        // StorePayload. That's exactly what made "items aren't in the item
        // shop" impossible to diagnose — the store appeared empty with no
        // error signal. Now we throw the decode error upward so refresh()'s
        // catch block populates `lastError` and logs the real reason.
        do {
            return try JSONDecoder().decode(StorePayload.self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<non-utf8>"
            print("[StoreService] DECODE FAILURE: \(error)\nraw response preview (first 500 chars):\n\(preview)")
            #endif
            throw error
        }
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
    let bonusStrength:   Double?
    let bonusEndurance:  Double?
    let bonusDiscipline: Double?   // Store audit fix — was silently dropped
    let bonusEnergy:     Double?
    let bonusFocus:      Double?
    let bonusHealth:     Double?

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
        case bonusDiscipline      = "bonus_discipline"
        case bonusEnergy          = "bonus_energy"
        case bonusFocus           = "bonus_focus"
        case bonusHealth          = "bonus_health"
        case xpMultiplier         = "xp_multiplier"
    }

    /// Custom init. Session 2 bug fix: every string/number field now uses
    /// `try?` with a sensible fallback so a single missing/null field can't
    /// blow up the whole array decode. Previously any item row with a null
    /// `description` or `icon_symbol` in the DB would silently break the
    /// entire store catalog and the user would see "No items in this
    /// section" with no signal of the underlying cause.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `key` is the unique identifier — still throw if it's genuinely
        // missing, so a malformed row doesn't become a ghost entry.
        key          = try c.decode(String.self, forKey: .key)
        name         = (try? c.decode(String.self, forKey: .name))          ?? key
        description  = (try? c.decode(String.self, forKey: .description))   ?? ""
        iconSymbol   = (try? c.decode(String.self, forKey: .iconSymbol))    ?? "questionmark.square"
        itemType     = (try? c.decode(String.self, forKey: .itemType))      ?? "cosmetic"
        rarity       = (try? c.decode(String.self, forKey: .rarity))        ?? "common"
        price        = (try? c.decode(Int.self,    forKey: .price))         ?? 0
        creditPrice  = try? c.decodeIfPresent(Int.self, forKey: .creditPrice) ?? nil
        storeSection = (try? c.decode(String.self, forKey: .storeSection))  ?? "permanent"
        isEnabled    = (try? c.decode(Bool.self,   forKey: .isEnabled))     ?? true
        finalPriceXP         = (try? c.decode(Int.self, forKey: .finalPriceXP))         ?? price
        finalPriceCredits    = (try? c.decode(Int.self, forKey: .finalPriceCredits))    ?? (creditPrice ?? 0)
        effectiveDiscountPct = (try? c.decode(Int.self, forKey: .effectiveDiscountPct)) ?? 0
        bonusStrength   = try? c.decodeIfPresent(Double.self, forKey: .bonusStrength)   ?? nil
        bonusEndurance  = try? c.decodeIfPresent(Double.self, forKey: .bonusEndurance)  ?? nil
        bonusDiscipline = try? c.decodeIfPresent(Double.self, forKey: .bonusDiscipline) ?? nil
        bonusEnergy     = try? c.decodeIfPresent(Double.self, forKey: .bonusEnergy)     ?? nil
        bonusFocus      = try? c.decodeIfPresent(Double.self, forKey: .bonusFocus)      ?? nil
        bonusHealth     = try? c.decodeIfPresent(Double.self, forKey: .bonusHealth)     ?? nil
        xpMultiplier    = try? c.decodeIfPresent(Double.self, forKey: .xpMultiplier)    ?? nil
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
    var strength:   Double = 0
    var endurance:  Double = 0
    var discipline: Double = 0   // Store audit fix — was missing entirely
    var energy:     Double = 0
    var focus:      Double = 0
    var health:     Double = 0
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
