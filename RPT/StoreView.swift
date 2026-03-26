import SwiftUI

// MARK: - StoreView
//
// Displays the item store with sections: Featured, Daily, Weekly, Permanent.
// Each item card shows name, icon, rarity color, stat bonuses, and dual prices (XP + GP).
// A payment toggle on each card lets the player choose XP or Gold Pieces.
// Sale badge appears when a sale is active.

struct StoreView: View {
    @StateObject private var store = StoreService.shared
    @ObservedObject private var dataManager = DataManager.shared

    @State private var selectedSection = "featured"
    @State private var purchaseInProgress: String? = nil
    @State private var showPurchaseError = false

    private let sections = [
        ("featured", "Featured", "star.fill"),
        ("daily",    "Daily",    "sun.max.fill"),
        ("weekly",   "Weekly",   "calendar"),
        ("permanent","Permanent","infinity")
    ]

    var playerXP: Int { dataManager.currentProfile?.xp ?? 0 }
    var playerGP: Int { store.playerCredits }

    var filteredItems: [StoreItem] {
        store.storeItems.filter { $0.storeSection == selectedSection && $0.isEnabled }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Balance header (XP + GP)
                balanceHeader

                // Sale banner when active
                if store.saleActive && store.salePct > 0 {
                    saleBanner
                }

                // Section picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sections, id: \.0) { key, label, icon in
                            sectionPill(key: key, label: label, icon: icon)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Item grid
                if store.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredItems.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bag")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No items in this section")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(filteredItems) { item in
                                StoreItemCard(
                                    item: item,
                                    playerXP: playerXP,
                                    playerGP: playerGP,
                                    store: store,
                                    inventory: store.inventory,
                                    isPurchasing: purchaseInProgress == item.key
                                ) { method in
                                    Task { await buy(item, method: method) }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Purchase Failed", isPresented: $showPurchaseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "An error occurred.")
            }
        }
        .task { await store.refresh() }
    }

    // MARK: - Subviews

    private var balanceHeader: some View {
        HStack(spacing: 16) {
            // XP pill
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("\(playerXP.formatted()) XP")
                    .font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.12), in: Capsule())

            // GP pill
            HStack(spacing: 4) {
                Image(systemName: store.currencyIcon)
                    .foregroundColor(.orange)
                Text("\(playerGP.formatted()) \(store.currencySymbol)")
                    .font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var saleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .foregroundColor(.white)
            Text("SALE — \(store.salePct)% off all items!")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red)
    }

    private func sectionPill(key: String, label: String, icon: String) -> some View {
        Button {
            selectedSection = key
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selectedSection == key ? Color.accentColor : Color.secondary.opacity(0.15),
                        in: Capsule())
            .foregroundColor(selectedSection == key ? .white : .primary)
        }
    }

    // MARK: - Actions

    private func buy(_ item: StoreItem, method: PaymentMethod) async {
        purchaseInProgress = item.key
        let success = await store.purchase(itemKey: item.key, method: method)
        purchaseInProgress = nil
        if !success { showPurchaseError = true }
    }
}

// MARK: - Store Item Card

private struct StoreItemCard: View {
    let item: StoreItem
    let playerXP: Int
    let playerGP: Int
    let store: StoreService
    let inventory: [InventoryEntry]
    let isPurchasing: Bool
    let onBuy: (PaymentMethod) -> Void

    @State private var selectedMethod: PaymentMethod = .xp

    var isOwned: Bool    { inventory.contains(where: { $0.key == item.key }) }
    var isEquipped: Bool { inventory.first(where: { $0.key == item.key })?.isEquipped == true }
    var canAffordXP: Bool { playerXP >= item.finalPriceXP }
    var canAffordGP: Bool { playerGP >= item.finalPriceCredits && item.finalPriceCredits > 0 }

    var canAffordSelected: Bool {
        switch selectedMethod {
        case .xp:         return canAffordXP
        case .goldPieces: return canAffordGP
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon + badge row
            HStack {
                Image(systemName: item.iconSymbol)
                    .font(.title2)
                    .foregroundColor(item.rarityColor)
                Spacer()
                badgeView
            }

            // Sale discount badge
            if item.effectiveDiscountPct > 0 {
                Text("-\(item.effectiveDiscountPct)%")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(item.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Stat bonuses
            statBonusRow

            Spacer()

            if isOwned {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Spacer()
                }
            } else {
                // Payment method toggle (shown only when item has GP price)
                if item.hasCreditPrice {
                    paymentToggle
                }

                // Price + buy button
                buyButton
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(item.rarityColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Sub-components

    @ViewBuilder
    private var badgeView: some View {
        if isEquipped {
            Text("Equipped")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green, in: Capsule())
        } else if isOwned {
            Text("Owned")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.blue, in: Capsule())
        } else {
            Text(item.rarity.capitalized)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(item.rarityColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.rarityColor.opacity(0.15), in: Capsule())
        }
    }

    @ViewBuilder
    private var paymentToggle: some View {
        HStack(spacing: 0) {
            // XP option
            Button {
                selectedMethod = .xp
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text("XP")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(selectedMethod == .xp ? Color.yellow.opacity(0.3) : Color.clear)
                .foregroundColor(selectedMethod == .xp ? .yellow : .secondary)
            }

            Divider().frame(height: 16)

            // GP option
            Button {
                selectedMethod = .goldPieces
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: store.currencyIcon)
                        .font(.system(size: 9))
                    Text(store.currencySymbol)
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(selectedMethod == .goldPieces ? Color.orange.opacity(0.3) : Color.clear)
                .foregroundColor(selectedMethod == .goldPieces ? .orange : .secondary)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var buyButton: some View {
        Button {
            onBuy(selectedMethod)
        } label: {
            HStack(spacing: 4) {
                if isPurchasing {
                    ProgressView().scaleEffect(0.7)
                } else {
                    priceLabel
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                canAffordSelected ? buttonColor : Color.secondary.opacity(0.3),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundColor(canAffordSelected ? .white : .secondary)
        }
        .disabled(!canAffordSelected || isPurchasing)
    }

    @ViewBuilder
    private var priceLabel: some View {
        switch selectedMethod {
        case .xp:
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill").font(.caption)
                if item.effectiveDiscountPct > 0 {
                    Text("\(item.price.formatted())")
                        .strikethrough()
                        .font(.system(size: 10))
                        .opacity(0.6)
                }
                Text("\(item.finalPriceXP.formatted()) XP")
                    .font(.caption.weight(.bold))
            }
        case .goldPieces:
            HStack(spacing: 3) {
                Image(systemName: store.currencyIcon).font(.caption)
                if item.effectiveDiscountPct > 0 {
                    Text("\((item.creditPrice ?? 0).formatted())")
                        .strikethrough()
                        .font(.system(size: 10))
                        .opacity(0.6)
                }
                Text("\(item.finalPriceCredits.formatted()) \(store.currencySymbol)")
                    .font(.caption.weight(.bold))
            }
        }
    }

    private var buttonColor: Color {
        selectedMethod == .goldPieces ? .orange : .accentColor
    }

    @ViewBuilder
    private var statBonusRow: some View {
        let bonuses: [(String, Double?)] = [
            ("STR", item.bonusStrength),
            ("END", item.bonusEndurance),
            ("ENE", item.bonusEnergy),
            ("FOC", item.bonusFocus),
            ("HP",  item.bonusHealth)
        ]
        let nonNilBonuses = bonuses.compactMap { label, val in val.map { (label, $0) } }

        if !nonNilBonuses.isEmpty {
            HStack(spacing: 6) {
                ForEach(nonNilBonuses, id: \.0) { label, val in
                    Text("+\(Int(val))\(label)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
        } else if let mult = item.xpMultiplier {
            Text("×\(String(format: "%.1f", mult)) XP")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.yellow)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    StoreView()
}
