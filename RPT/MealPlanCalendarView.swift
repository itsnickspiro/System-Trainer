import SwiftUI
import SwiftData

// MARK: - Meal Plan Calendar View

struct MealPlanCalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlannedMeal.plannedDate) private var allPlanned: [PlannedMeal]

    // Week navigation
    @State private var weekOffset: Int = 0
    @State private var showingAddMeal: Bool = false
    @State private var addMealDate: Date = Date()
    @State private var addMealSlot: String = "Lunch"
    @State private var editingMeal: PlannedMeal? = nil

    private let slots = ["Breakfast", "Lunch", "Dinner", "Snack"]
    private let accentColor = Color.green

    private var weekDates: [Date] {
        let cal = Calendar.current
        guard let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())),
              let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: monday) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
    }

    private func meals(for date: Date, slot: String) -> [PlannedMeal] {
        let cal = Calendar.current
        return allPlanned.filter {
            cal.isDate($0.plannedDate, inSameDayAs: date) && $0.mealSlot == slot
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Week navigator
                    weekNavigator
                        .padding()

                    // Calendar grid
                    VStack(spacing: 1) {
                        ForEach(slots, id: \.self) { slot in
                            slotRow(slot: slot)
                        }
                    }
                    .padding(.horizontal)

                    // Summary footer
                    summaryFooter
                        .padding()

                    Spacer(minLength: 80)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Meal Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addMealDate = Date()
                        addMealSlot = "Lunch"
                        showingAddMeal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMeal) {
                AddPlannedMealSheet(
                    initialDate: addMealDate,
                    initialSlot: addMealSlot,
                    slots: slots
                )
            }
            .sheet(item: $editingMeal) { meal in
                EditPlannedMealSheet(meal: meal, slots: slots)
            }
        }
    }

    // MARK: - Week Navigator

    private var weekNavigator: some View {
        HStack {
            Button {
                withAnimation { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(weekLabel)
                    .font(.headline)
                if weekOffset == 0 {
                    Text("This Week")
                        .font(.caption2)
                        .foregroundColor(accentColor)
                } else if weekOffset == 1 {
                    Text("Next Week")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if weekOffset == -1 {
                    Text("Last Week")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
        }
    }

    // MARK: - Slot Row

    private func slotRow(slot: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Slot header
            HStack {
                Image(systemName: slotIcon(slot))
                    .font(.caption)
                    .foregroundColor(slotColor(slot))
                Text(slot)
                    .font(.caption.weight(.bold))
                    .foregroundColor(slotColor(slot))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(slotColor(slot).opacity(0.08))

            // Day columns
            HStack(spacing: 1) {
                ForEach(weekDates, id: \.self) { date in
                    dayCell(date: date, slot: slot)
                }
            }

            Divider()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func dayCell(date: Date, slot: String) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let cellMeals = meals(for: date, slot: slot)

        VStack(spacing: 4) {
            // Day header
            VStack(spacing: 1) {
                Text(dayLetter(date))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isToday ? accentColor : .secondary)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 11, weight: isToday ? .black : .regular))
                    .foregroundColor(isToday ? accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isToday ? accentColor.opacity(0.08) : Color.clear)

            // Meals for this cell
            if cellMeals.isEmpty {
                Button {
                    addMealDate = date
                    addMealSlot = slot
                    showingAddMeal = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(cellMeals) { meal in
                    mealChip(meal)
                }
                Button {
                    addMealDate = date
                    addMealSlot = slot
                    showingAddMeal = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 9))
                        .foregroundColor(accentColor.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private func mealChip(_ meal: PlannedMeal) -> some View {
        Button {
            editingMeal = meal
        } label: {
            Text(meal.title.isEmpty ? "Meal" : meal.title)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(meal.isCompleted ? accentColor.opacity(0.3) : slotColor(meal.mealSlot).opacity(0.2))
                .cornerRadius(4)
                .foregroundColor(meal.isCompleted ? accentColor : .primary)
                .overlay(
                    meal.isCompleted ?
                    RoundedRectangle(cornerRadius: 4).stroke(accentColor.opacity(0.5), lineWidth: 1) :
                    nil
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Footer

    private var summaryFooter: some View {
        let weekMeals = allPlanned.filter { meal in
            guard let first = weekDates.first, let last = weekDates.last else { return false }
            return meal.plannedDate >= first && meal.plannedDate <= last
        }
        let totalCalories = weekMeals.reduce(0) { $0 + $1.estimatedCalories }
        let completed = weekMeals.filter { $0.isCompleted }.count

        return VStack(spacing: 10) {
            Divider()
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(weekMeals.count)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(accentColor)
                    Text("Meals Planned")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                VStack(spacing: 2) {
                    Text("\(completed)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.green)
                    Text("Completed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if totalCalories > 0 {
                    VStack(spacing: 2) {
                        Text("\(totalCalories)")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.orange)
                        Text("Est. Calories")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func dayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(1))
    }

    private func slotIcon(_ slot: String) -> String {
        switch slot {
        case "Breakfast": return "sun.horizon.fill"
        case "Lunch":     return "sun.max.fill"
        case "Dinner":    return "moon.fill"
        default:          return "apple.logo"
        }
    }

    private func slotColor(_ slot: String) -> Color {
        switch slot {
        case "Breakfast": return .orange
        case "Lunch":     return .yellow
        case "Dinner":    return .purple
        default:          return .mint
        }
    }
}

// MARK: - Add Planned Meal Sheet

struct AddPlannedMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var initialDate: Date
    var initialSlot: String
    var slots: [String]

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedCalories: Int = 0
    @State private var selectedDate: Date
    @State private var selectedSlot: String

    init(initialDate: Date, initialSlot: String, slots: [String]) {
        self.initialDate = initialDate
        self.initialSlot = initialSlot
        self.slots = slots
        _selectedDate = State(initialValue: initialDate)
        _selectedSlot = State(initialValue: initialSlot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Details") {
                    TextField("e.g. Grilled Chicken Salad", text: $title)
                    TextField("Notes (optional)", text: $notes)
                }

                Section("When") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    Picker("Meal", selection: $selectedSlot) {
                        ForEach(slots, id: \.self) { slot in
                            Text(slot).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calories") {
                    HStack {
                        Text("Estimated Calories")
                        Spacer()
                        TextField("0", value: $estimatedCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Planned Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let meal = PlannedMeal(
                            plannedDate: selectedDate,
                            mealSlot: selectedSlot,
                            title: title,
                            notes: notes,
                            estimatedCalories: estimatedCalories
                        )
                        context.insert(meal)
                        context.safeSave()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Planned Meal Sheet

struct EditPlannedMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var meal: PlannedMeal
    var slots: [String]

    @State private var title: String
    @State private var notes: String
    @State private var estimatedCalories: Int
    @State private var selectedDate: Date
    @State private var selectedSlot: String

    init(meal: PlannedMeal, slots: [String]) {
        self.meal = meal
        self.slots = slots
        _title = State(initialValue: meal.title)
        _notes = State(initialValue: meal.notes)
        _estimatedCalories = State(initialValue: meal.estimatedCalories)
        _selectedDate = State(initialValue: meal.plannedDate)
        _selectedSlot = State(initialValue: meal.mealSlot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Details") {
                    TextField("e.g. Grilled Chicken Salad", text: $title)
                    TextField("Notes (optional)", text: $notes)
                }

                Section("When") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    Picker("Meal", selection: $selectedSlot) {
                        ForEach(slots, id: \.self) { slot in
                            Text(slot).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calories") {
                    HStack {
                        Text("Estimated Calories")
                        Spacer()
                        TextField("0", value: $estimatedCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Toggle("Mark as Completed", isOn: Binding(
                        get: { meal.isCompleted },
                        set: { meal.isCompleted = $0; context.safeSave() }
                    ))
                }

                Section {
                    Button("Delete Meal", role: .destructive) {
                        context.delete(meal)
                        context.safeSave()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        meal.title = title
                        meal.notes = notes
                        meal.estimatedCalories = estimatedCalories
                        meal.plannedDate = selectedDate
                        meal.mealSlot = selectedSlot
                        context.safeSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MealPlanCalendarView()
        .modelContainer(for: [PlannedMeal.self], inMemory: true)
}
