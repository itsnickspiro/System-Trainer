import SwiftUI
import SwiftData

// MARK: - Helpers

/// Converts an accentColor string from the model to a SwiftUI Color.
func itemAccentColor(_ name: String) -> Color {
    switch name {
    case "cyan":   return .cyan
    case "purple": return .purple
    case "green":  return .green
    case "yellow": return .yellow
    case "orange": return .orange
    case "red":    return .red
    default:       return .white
    }
}

// MARK: - Root View

struct InventoryAndShopView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var items: [InventoryItem]

    @State private var selectedTab: InventoryTab = .myInventory

    private var profile: Profile? { profiles.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Tab Picker ────────────────────────────────────────────
                Picker("Tab", selection: $selectedTab) {
                    ForEach(InventoryTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // ── Content ───────────────────────────────────────────────
                Group {
                    switch selectedTab {
                    case .myInventory:
                        MyInventoryTabView(items: ownedItems, profile: profile)
                    case .systemShop:
                        StoreContentView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("INVENTORY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // Items the player actually owns (quantity > 0)
    private var ownedItems: [InventoryItem] {
        items.filter { $0.quantity > 0 }
    }
}

// MARK: - Tab enum

enum InventoryTab: String, CaseIterable, Identifiable {
    case myInventory = "My Inventory"
    case systemShop  = "Item Shop"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - My Inventory Tab

private struct MyInventoryTabView: View {
    let items: [InventoryItem]
    let profile: Profile?

    @State private var selectedItem: InventoryItem?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            InventoryItemCard(item: item)
                                .onTapGesture { selectedItem = item }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            if let profile {
                ConsumeConfirmationSheet(item: item, profile: profile) {
                    selectedItem = nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.5))
            Text("INVENTORY EMPTY")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.gray)
            Text("Visit the Item Shop to acquire items.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System Shop Tab

private struct SystemShopTabView: View {
    let items: [InventoryItem]
    let profile: Profile?

    @State private var selectedItem: InventoryItem?

    // All 5 shop archetypes ordered by cost (cheapest first)
    private var shopItems: [InventoryItem] {
        InventoryItemType.allCases.compactMap { type in
            items.first { $0.itemType == type }
        }
        .sorted { $0.itemType.shopXPCost < $1.itemType.shopXPCost }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let profile {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                        Text("\(profile.xp.formatted()) XP available")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.yellow)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                ForEach(shopItems) { item in
                    ShopItemRow(item: item, profile: profile) {
                        selectedItem = item
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .sheet(item: $selectedItem) { item in
            if let profile {
                PurchaseConfirmationSheet(item: item, profile: profile) {
                    selectedItem = nil
                }
            }
        }
    }
}

// MARK: - Item Cards & Rows

private struct InventoryItemCard: View {
    let item: InventoryItem

    var body: some View {
        let accent = itemAccentColor(item.itemType.accentColor)
        let badgeAccent = itemAccentColor(item.itemType.category.badgeColor)

        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: item.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(accent)
            }

            Text(item.displayName)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Category badge
            Text(item.itemType.category.displayName.uppercased())
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .foregroundStyle(badgeAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(badgeAccent.opacity(0.15)))

            // Quantity
            Text("×\(item.quantity)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct ShopItemRow: View {
    let item: InventoryItem
    let profile: Profile?
    let onBuy: () -> Void

    private var canAfford: Bool {
        guard let profile else { return false }
        return profile.xp >= item.itemType.shopXPCost
    }

    var body: some View {
        let accent = itemAccentColor(item.itemType.accentColor)
        let badgeAccent = itemAccentColor(item.itemType.category.badgeColor)

        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accent.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                Text(item.itemType.category.displayName.uppercased())
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(badgeAccent)
            }

            Spacer()

            // Cost + Buy button
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(canAfford ? Color.yellow : Color.gray)
                    Text("\(item.itemType.shopXPCost.formatted())")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(canAfford ? Color.yellow : Color.gray)
                }
                Button(action: onBuy) {
                    Text("BUY")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(canAfford ? Color.black : Color.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(canAfford ? Color.yellow : Color.white.opacity(0.08))
                        )
                }
                .disabled(!canAfford)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Consume Confirmation Sheet

private struct ConsumeConfirmationSheet: View {
    @Environment(\.modelContext) private var context
    let item: InventoryItem
    let profile: Profile
    let onDismiss: () -> Void

    @State private var showResult = false
    @State private var resultMessage = ""

    var body: some View {
        let accent = itemAccentColor(item.itemType.accentColor)

        NavigationStack {
            VStack(spacing: 28) {
                // Item art
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: item.icon)
                        .font(.system(size: 42))
                        .foregroundStyle(accent)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(item.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // System prompt
                VStack(spacing: 4) {
                    Text("Notice:")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.yellow)
                    Text("Consume \"\(item.displayName)\"?")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Owned: ×\(item.quantity)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .padding(.horizontal, 24)

                if showResult {
                    Text(resultMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 10) {
                    Button(action: consume) {
                        Text("CONSUME")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(accent))
                    }
                    Button(action: onDismiss) {
                        Text("CANCEL")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("USE ITEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func consume() {
        guard item.quantity > 0 else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        applyEffect()

        item.quantity -= 1
        try? context.save()

        withAnimation {
            resultMessage = effectMessage()
            showResult = true
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onDismiss()
        }
    }

    private func applyEffect() {
        switch item.itemType {
        case .hermitMiracleSeed, .gateEscapeFragment:
            profile.activateExemption(durationHours: 24)

        case .demonLordPanacea:
            profile.doubleXPActiveUntil = Calendar.current.date(
                byAdding: .hour, value: 24, to: Date()
            )
            profile.health     = min(profile.health + 50, 100)
            profile.energy     = min(profile.energy + 30, 100)
            profile.discipline = min(profile.discipline + 20, 100)

        case .pocketGuardianCandy:
            profile.xp += item.itemType.xpBonus

        case .equivalentExchangeChalk:
            // Quest reroll is handled by QuestManager on next generation
            break
        }
    }

    private func effectMessage() -> String {
        switch item.itemType {
        case .hermitMiracleSeed:
            return "Analysis: Level reset blocked for 24 hours. Directive: Maintain compliance."
        case .gateEscapeFragment:
            return "Analysis: Escape vector activated. One quest absolved. Directive: Resume operations."
        case .demonLordPanacea:
            return "Analysis: Recovery protocol online. Health +50, Energy +30. Double XP active 24h."
        case .pocketGuardianCandy:
            return "Analysis: XP transfer complete. +\(item.itemType.xpBonus.formatted()) XP deposited."
        case .equivalentExchangeChalk:
            return "Analysis: Quest substitution queued. Next generation will apply exchange."
        }
    }
}

// MARK: - Purchase Confirmation Sheet

private struct PurchaseConfirmationSheet: View {
    @Environment(\.modelContext) private var context
    let item: InventoryItem
    let profile: Profile
    let onDismiss: () -> Void

    @State private var showInsufficient = false

    private var canAfford: Bool { profile.xp >= item.itemType.shopXPCost }

    var body: some View {
        let accent = itemAccentColor(item.itemType.accentColor)

        NavigationStack {
            VStack(spacing: 28) {
                // Item art
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: item.icon)
                        .font(.system(size: 42))
                        .foregroundStyle(accent)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(item.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Cost summary
                HStack(spacing: 8) {
                    Label {
                        Text("\(item.itemType.shopXPCost.formatted()) XP")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(canAfford ? Color.yellow : Color.red)
                    } icon: {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(canAfford ? Color.yellow : Color.red)
                    }
                    Text("→")
                        .foregroundStyle(.gray)
                    Label {
                        Text("×1 \(item.displayName)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(accent)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .padding(.horizontal, 24)

                if showInsufficient {
                    Text("Notice: Insufficient XP. Acquire more XP to proceed.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                Text("Balance: \(profile.xp.formatted()) XP")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.gray)

                Spacer()

                // Action buttons
                VStack(spacing: 10) {
                    Button(action: purchase) {
                        Text("CONFIRM PURCHASE")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().fill(canAfford ? Color.yellow : Color.gray.opacity(0.4))
                            )
                    }
                    Button(action: onDismiss) {
                        Text("CANCEL")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("ITEM SHOP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func purchase() {
        guard canAfford else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation { showInsufficient = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showInsufficient = false }
            }
            return
        }

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        profile.xp -= item.itemType.shopXPCost
        item.quantity += 1
        try? context.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}
