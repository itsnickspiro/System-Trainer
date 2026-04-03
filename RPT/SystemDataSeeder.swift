import SwiftData
import Foundation

/// Seeds the System Shop's canonical item archetypes into SwiftData on the app's first launch.
/// Guarded by a UserDefaults flag so it only runs once per installation.
struct SystemDataSeeder {

    private static let seededKey = "systemDataSeeded"

    /// Call this at app launch (after the ModelContext is ready).
    /// Does nothing if the seed has already been applied.
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        seed(context: context)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Unconditionally inserts one `InventoryItem` record (quantity 0) for every
    /// `InventoryItemType` case so that the System Shop always has a full catalogue.
    static func seed(context: ModelContext) {
        for itemType in InventoryItemType.allCases {
            // Avoid duplicates in case this is called manually more than once.
            let descriptor = FetchDescriptor<InventoryItem>(
                predicate: #Predicate { $0.itemType == itemType }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            guard existing.isEmpty else { continue }

            // Shop catalogue entries start at quantity 0 — the player does not
            // own any items until they spend XP to purchase them.
            let catalogueEntry = InventoryItem(itemType: itemType, quantity: 0)
            context.insert(catalogueEntry)
        }

        context.safeSave()
    }
}
