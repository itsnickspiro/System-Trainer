import SwiftUI

// MARK: - InventoryView
//
// Shows all items the player owns, grouped by type: Equipment, Consumables, Cosmetics.
// Tap equipment to equip/unequip.
// Tap consumables to activate (use the XP boost).
// Equipped items show a checkmark badge.

struct InventoryView: View {
    @StateObject private var store = StoreService.shared

    /// Group inventory entries by item type
    private var grouped: [(String, String, [InventoryEntry])] {
        let types: [(String, String)] = [
            ("equipment",    "Equipment"),
            ("consumable",   "Consumables"),
            ("boost",        "Boosts"),
            ("cosmetic",     "Cosmetics"),
            ("avatar_frame", "Avatar Frames"),
            ("title",        "Titles"),
            ("badge",        "Badges")
        ]
        return types.compactMap { key, label in
            let entries = store.inventory.filter { entry in
                store.storeItems.first(where: { $0.key == entry.key })?.itemType == key
            }
            guard !entries.isEmpty else { return nil }
            return (key, label, entries)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.inventory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bag")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        Text("Your inventory is empty")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Visit the Store to get your first item.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(grouped, id: \.0) { _, label, entries in
                            Section(label) {
                                ForEach(entries) { entry in
                                    if let item = store.storeItems.first(where: { $0.key == entry.key }) {
                                        InventoryItemRow(item: item, entry: entry) {
                                            handleTap(item: item, entry: entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Item Shop")
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
        }
        .task { await store.refresh() }
    }

    private func handleTap(item: StoreItem, entry: InventoryEntry) {
        switch item.itemType {
        case "equipment":
            Task { await store.equip(itemKey: item.key, equip: !entry.isEquipped) }
        case "consumable", "boost":
            Task { await store.equip(itemKey: item.key, equip: !entry.isActive) }
        default:
            break
        }
    }
}

// MARK: - Inventory Item Row

private struct InventoryItemRow: View {
    let item: StoreItem
    let entry: InventoryEntry
    let onTap: () -> Void

    var actionLabel: String {
        switch item.itemType {
        case "equipment":        return entry.isEquipped ? "Unequip" : "Equip"
        case "consumable", "boost": return entry.isActive   ? "Active"  : "Use"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Item icon with rarity color
            ZStack {
                Circle()
                    .fill(item.rarityColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: item.iconSymbol)
                    .font(.title3)
                    .foregroundColor(item.rarityColor)
                if entry.isEquipped || entry.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .offset(x: 14, y: 14)
                }
            }

            // Name + description
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    if entry.quantity > 1 {
                        Text("×\(entry.quantity)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Stat bonuses summary
                bonusSummary
            }

            Spacer()

            // Action button (equipment/consumables only)
            if !actionLabel.isEmpty {
                Button(actionLabel, action: onTap)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(entry.isEquipped || entry.isActive ? .red : .accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var bonusSummary: some View {
        let bonuses: [(String, Double?)] = [
            ("STR", item.bonusStrength),
            ("END", item.bonusEndurance),
            ("ENE", item.bonusEnergy),
            ("FOC", item.bonusFocus),
            ("HP",  item.bonusHealth)
        ]
        let nonNil = bonuses.compactMap { label, val in val.map { (label, $0) } }

        if !nonNil.isEmpty {
            HStack(spacing: 4) {
                ForEach(nonNil, id: \.0) { label, val in
                    Text("+\(Int(val)) \(label)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            }
        } else if let mult = item.xpMultiplier {
            Text("×\(String(format: "%.1f", mult)) XP Boost")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - Preview

#Preview {
    InventoryView()
}
