import Foundation
import SwiftData
import Combine

/// Aggregates upcoming PlannedMeal entries into a deduped grocery checklist.
///
/// NOTE: The existing PlannedMeal model is title-based (no FoodItem relationship
/// and no quantity field). It uses `plannedDate`, `mealSlot`, `title`, and
/// `estimatedCalories`. We aggregate by lowercased title and count how many
/// times each title appears across the week as the "quantity".
@MainActor
final class GroceryListService: ObservableObject {
    static let shared = GroceryListService()

    private init() {}

    /// Returns the Monday 00:00 of the current week.
    static func currentWeekStart() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Calendar.current.startOfDay(for: Date())
    }

    /// Regenerate the auto items for the current week from PlannedMeal entries.
    /// Preserves any items where isManual == true.
    func regenerateForCurrentWeek(context: ModelContext) {
        let weekStart = Self.currentWeekStart()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86400)

        // Delete existing auto items for this week
        let autoFetch = FetchDescriptor<GroceryListItem>(
            predicate: #Predicate<GroceryListItem> {
                $0.weekStartDate == weekStart && $0.isManual == false
            }
        )
        if let existing = try? context.fetch(autoFetch) {
            for item in existing {
                context.delete(item)
            }
        }

        // Aggregate planned meals for the next 7 days
        let plannedFetch = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> {
                $0.plannedDate >= weekStart && $0.plannedDate < weekEnd
            }
        )
        let planned = (try? context.fetch(plannedFetch)) ?? []

        // Aggregate by title (count occurrences as the "quantity")
        var aggregated: [String: (title: String, quantity: Double)] = [:]
        for meal in planned {
            let trimmed = meal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if let existing = aggregated[key] {
                aggregated[key] = (existing.title, existing.quantity + 1)
            } else {
                aggregated[key] = (trimmed, 1)
            }
        }

        // Insert deduped GroceryListItems
        for (_, entry) in aggregated {
            let item = GroceryListItem(
                name: entry.title,
                quantity: entry.quantity,
                unit: "serving",
                category: "other",
                isManual: false,
                foodItemID: nil,
                weekStartDate: weekStart
            )
            context.insert(item)
        }

        try? context.save()
    }

    /// Add a manual item (not from PlannedMeal).
    func addManualItem(name: String, quantity: Double, unit: String, context: ModelContext) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = GroceryListItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            unit: unit,
            category: "other",
            isManual: true,
            weekStartDate: Self.currentWeekStart()
        )
        context.insert(item)
        try? context.save()
    }

    func toggleChecked(_ item: GroceryListItem, context: ModelContext) {
        item.isChecked.toggle()
        item.lastModified = Date()
        try? context.save()
    }

    func clearChecked(context: ModelContext) {
        let weekStart = Self.currentWeekStart()
        let descriptor = FetchDescriptor<GroceryListItem>(
            predicate: #Predicate<GroceryListItem> {
                $0.weekStartDate == weekStart && $0.isChecked == true
            }
        )
        if let checked = try? context.fetch(descriptor) {
            for item in checked {
                context.delete(item)
            }
            try? context.save()
        }
    }
}
