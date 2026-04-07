import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var service = GroceryListService.shared

    @Query private var allItems: [GroceryListItem]

    @State private var showingAddManual = false
    @State private var manualName: String = ""
    @State private var manualQuantity: String = "1"
    @State private var showingClearConfirm = false

    private var weekStart: Date { GroceryListService.currentWeekStart() }

    private var weekItems: [GroceryListItem] {
        allItems.filter { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }
    }

    private var groupedByCategory: [(category: String, items: [GroceryListItem])] {
        let grouped = Dictionary(grouping: weekItems) { $0.category }
        return grouped
            .map { (category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryHeader

                    Button {
                        service.regenerateForCurrentWeek(context: context)
                    } label: {
                        Label("Refresh from Meal Plan", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)

                    if weekItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedByCategory, id: \.category) { group in
                            categorySection(group.category, items: group.items)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAddManual = true } label: {
                            Label("Add item", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label("Clear checked", systemImage: "xmark.bin")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Clear checked items?", isPresented: $showingClearConfirm) {
                Button("Clear", role: .destructive) {
                    service.clearChecked(context: context)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingAddManual) {
                addManualSheet
            }
            .task {
                if weekItems.isEmpty {
                    service.regenerateForCurrentWeek(context: context)
                }
            }
        }
    }

    private var summaryHeader: some View {
        let total = weekItems.count
        let checked = weekItems.filter { $0.isChecked }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Text(weekStart.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(checked) / \(total)")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("checked")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(1)
                }
            }
            ProgressView(value: total > 0 ? Double(checked) / Double(total) : 0)
                .tint(.cyan)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
            Text("Your list is empty")
                .font(.headline)
            Text("Plan some meals on the Diet calendar, or tap + to add an item manually.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func categorySection(_ category: String, items: [GroceryListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.uppercased())
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            ForEach(items) { item in
                groceryRow(item)
            }
        }
        .padding(.top, 4)
    }

    private func groceryRow(_ item: GroceryListItem) -> some View {
        Button {
            service.toggleChecked(item, context: context)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(item.isChecked ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(item.isChecked)
                        .foregroundColor(item.isChecked ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text("\(item.quantity, specifier: "%g") \(item.unit)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if item.isManual {
                            Text("MANUAL")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.purple.opacity(0.15), in: Capsule())
                        }
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var addManualSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $manualName)
                    TextField("Quantity", text: $manualQuantity)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddManual = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let qty = Double(manualQuantity) ?? 1
                        service.addManualItem(name: manualName, quantity: qty, unit: "item", context: context)
                        manualName = ""
                        manualQuantity = "1"
                        showingAddManual = false
                    }
                    .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
