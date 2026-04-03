import SwiftUI
import SwiftData
import UIKit

struct DietView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var foodEntries: [FoodEntry]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var workoutSessions: [WorkoutSession]
    @State private var selectedDate = Date()
    @State private var showingNutritionGoals = false
    @State private var macrosExpanded = false
    @State private var isPlanBannerExpanded = false

    private var profile: Profile {
        profiles.first ?? Profile(name: "Default User")
    }

    private var todaysFoodEntries: [FoodEntry] {
        let calendar = Calendar.current
        return foodEntries.filter { entry in
            calendar.isDate(entry.dateConsumed, inSameDayAs: selectedDate)
        }
    }

    private var actualConsumedCalories: Int {
        Int(todaysFoodEntries.reduce(0) { $0 + $1.totalCalories })
    }

    private var todaysCarbs: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalCarbs }
    }

    private var todaysProtein: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalProtein }
    }

    private var todaysFat: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalFat }
    }

    private var todaysFiber: Double {
        todaysFoodEntries.reduce(0) { $0 + $1.totalFiber }
    }

    private var todaysNetCarbs: Double {
        max(0, todaysCarbs - todaysFiber)
    }

    /// A workout session started today that has not been completed yet.
    private var activeWorkoutSession: WorkoutSession? {
        let cal = Calendar.current
        return workoutSessions.first {
            cal.isDateInToday($0.startedAt) && !$0.isComplete
        }
    }

    /// Calories burned from logged workouts today (MET × weight × hours).
    /// Falls back to HealthKit active calories if no workouts were logged.
    private var exerciseBurnCalories: Int {
        let cal = Calendar.current
        let todaySessions = workoutSessions.filter {
            cal.isDate($0.startedAt, inSameDayAs: selectedDate) && $0.isComplete
        }
        if !todaySessions.isEmpty {
            // MET estimate: strength=5, cardio=8, flexibility=3, mixed=6
            let totalBurn = todaySessions.reduce(0.0) { sum, s in
                // Conservative estimate: 5 kcal/min average across all workout types
                return sum + (Double(s.durationMinutes) * 5.0)
            }
            return Int(totalBurn)
        }
        // Fall back to HealthKit active calories when date is today
        if cal.isDateInToday(selectedDate) {
            return profile.dailyActiveCalories
        }
        return 0
    }

    /// Net remaining calories: goal + burn - consumed
    private var remainingCalories: Int {
        dailyCalorieGoal + exerciseBurnCalories - actualConsumedCalories
    }

    // Add food sheet
    @State private var showingAddFood = false
    @State private var selectedMealForAdding: MealType = .breakfast
    @State private var showingCopyConfirm = false
    @State private var showingMealPlanner = false
    @State private var showingRecipeCalculator = false
    // Entry editing / nutrition detail
    @State private var entryToEdit: FoodEntry? = nil
    @State private var entryForNutrition: FoodEntry? = nil

    /// True when the selected date is not today — diary and quests are read-only.
    private var isDateLocked: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }

    private var waterGlasses: Int { profile.waterIntake }

    // Active plan (anime or custom) — nil = generic mode
    private var activePlan: AnimeWorkoutPlan? {
        guard !profile.activePlanID.isEmpty else { return nil }
        if let anime = AnimeWorkoutPlanService.shared.plan(id: profile.activePlanID) { return anime }
        // Fall back to user-created custom plan
        let id = profile.activePlanID
        let descriptor = FetchDescriptor<CustomWorkoutPlan>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first?.asAnimeWorkoutPlan()
    }

    // Goals — plan overrides custom goals; custom goals override TDEE defaults
    private var dailyCalorieGoal: Int {
        activePlan?.nutrition.dailyCalories ?? profile.effectiveCalorieGoal
    }
    private var waterGoal: Int { activePlan?.nutrition.waterGlasses ?? 8 }
    private var proteinGoal: Int {
        activePlan?.nutrition.proteinGrams ?? profile.effectiveProteinGoal
    }
    private var carbGoal: Int {
        activePlan?.nutrition.carbGrams ?? profile.effectiveCarbGoal
    }
    private var fatGoal: Int {
        activePlan?.nutrition.fatGrams ?? profile.effectiveFatGoal
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned header
                HStack {
                    Text("RATION LOG")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Menu {
                        Button {
                            showingNutritionGoals = true
                        } label: {
                            Label("Nutrition Goals", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            showingCopyConfirm = true
                        } label: {
                            Label("Copy Yesterday's Meals", systemImage: "doc.on.doc")
                        }
                        .disabled(isDateLocked)
                        Button {
                            showingMealPlanner = true
                        } label: {
                            Label("Meal Planner", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            showingRecipeCalculator = true
                        } label: {
                            Label("Recipe Calculator", systemImage: "function")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Date selector pinned below header — does not scroll
                dateSelectorView
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 20) {
                    // Locked day banner
                    if isDateLocked {
                        HStack(spacing: 8) {
                            Image(systemName: Calendar.current.isDateInFuture(selectedDate) ? "lock.fill" : "lock.fill")
                                .foregroundColor(Calendar.current.isDateInFuture(selectedDate) ? .blue : .secondary)
                            Text(Calendar.current.isDateInFuture(selectedDate)
                                 ? "Future day — log opens when it arrives"
                                 : "Past day — read-only. Log on today's date to earn XP.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemFill))
                        )
                    }

                    // Active Plan Nutrition Banner (shown when a plan is selected)
                    if let plan = activePlan {
                        planNutritionBanner(plan: plan)
                    }

                    // Active workout banner — shown above calories ring when a session is in progress
                    if let session = activeWorkoutSession {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                            Text(session.routineName.isEmpty ? "Workout in progress" : session.routineName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                            Spacer()
                            Text("Active")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }

                    // Daily Calorie Summary
                    dailyCalorieSummaryView

                    // Macro Breakdown
                    macroBreakdownView

                    // Micronutrient Breakdown
                    micronutrientBreakdownView

                    // Meals Section
                    mealsSection

                    Spacer(minLength: 100)
                }
                    .padding(.horizontal)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .alert("Copy Yesterday's Meals?", isPresented: $showingCopyConfirm) {
                Button("Copy", role: .none) { copyYesterdaysMeals() }
                Button("Cancel", role: .cancel) {}
            } message: {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                Text("This will copy all food entries from \(yesterday.formatted(date: .abbreviated, time: .omitted)) to \(selectedDate.formatted(date: .abbreviated, time: .omitted)).")
            }
            .sheet(isPresented: $showingAddFood) {
                if !isDateLocked {
                    AddFoodView(selectedMeal: $selectedMealForAdding, selectedDate: selectedDate)
                }
            }
            .sheet(isPresented: $showingNutritionGoals) {
                NutritionGoalsView()
            }
            .sheet(isPresented: $showingMealPlanner) {
                MealPlanCalendarView()
            }
            .sheet(isPresented: $showingRecipeCalculator) {
                RecipeNutritionCalculatorView()
            }
            .sheet(item: $entryToEdit) { entry in
                FoodEntryEditSheet(entry: entry)
            }
            .sheet(item: $entryForNutrition) { entry in
                FoodNutritionSheet(entry: entry, fitnessGoal: profile.fitnessGoal)
            }
        }
    }

    // MARK: - Date Selector
    private var dateSelectorView: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.blue)
            }

            Spacer()

            // Tap to open meal planner for this date
            Button {
                showingMealPlanner = true
            } label: {
                VStack(spacing: 2) {
                    Text(selectedDate, style: .date)
                        .font(.headline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("tap to plan meals")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Plan Nutrition Banner

    private func planNutritionBanner(plan: AnimeWorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row — always visible, toggles expansion
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isPlanBannerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: plan.iconSymbol)
                        .font(.headline)
                        .foregroundColor(plan.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(plan.character) Protocol Active")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                        Text("Nutrition targets adjusted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(plan.difficulty.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(plan.accentColor.opacity(0.15))
                        .foregroundColor(plan.accentColor)
                        .clipShape(Capsule())
                    Image(systemName: isPlanBannerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPlanBannerExpanded {
                // Macro targets in a compact grid
                HStack(spacing: 0) {
                    nutritionTargetPill(label: "Calories", value: "\(plan.nutrition.dailyCalories)", unit: "kcal", color: .orange)
                    Divider().frame(height: 30)
                    nutritionTargetPill(label: "Protein", value: "\(plan.nutrition.proteinGrams)", unit: "g", color: .green)
                    Divider().frame(height: 30)
                    nutritionTargetPill(label: "Carbs", value: "\(plan.nutrition.carbGrams)", unit: "g", color: .blue)
                    Divider().frame(height: 30)
                    nutritionTargetPill(label: "Fat", value: "\(plan.nutrition.fatGrams)", unit: "g", color: .red)
                    Divider().frame(height: 30)
                    nutritionTargetPill(label: "Water", value: "\(plan.nutrition.waterGlasses)", unit: "gl", color: .cyan)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))

                if !plan.nutrition.mealPrepTips.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meal Prep")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        ForEach(plan.nutrition.mealPrepTips.prefix(3), id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !plan.nutrition.avoidList.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avoid")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(plan.nutrition.avoidList.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(plan.accentColor.opacity(0.06))
                .stroke(plan.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func nutritionTargetPill(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Daily Calorie Summary
    private var dailyCalorieSummaryView: some View {
        VStack(spacing: 16) {
            // Ring row: water − | calorie ring | water +
            HStack(spacing: 0) {
                // Water minus
                Button {
                    guard waterGlasses > 0 else { return }
                    profile.waterIntake = waterGlasses - 1
                    context.safeSave()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(waterGlasses > 0 ? .blue : .gray.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(waterGlasses == 0)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Remove water glass")
                .accessibilityValue("\(waterGlasses) glasses")

                // Calorie ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 120, height: 120)

                    let netGoal = dailyCalorieGoal + exerciseBurnCalories
                    Circle()
                        .trim(from: 0, to: min(Double(actualConsumedCalories) / Double(max(1, netGoal)), 1.0))
                        .stroke(
                            remainingCalories < 0 ? Color.red : Color.blue,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(abs(remainingCalories))")
                            .font(.title.weight(.bold))
                            .foregroundColor(remainingCalories < 0 ? .red : .primary)
                        Text(remainingCalories < 0 ? "over" : "remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Water plus
                Button {
                    profile.recordWaterIntake()
                    context.safeSave()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add water glass")
                .accessibilityValue("\(waterGlasses) glasses")
                .frame(maxWidth: .infinity)
            }

            // Calorie breakdown: Goal + Exercise − Food = Left
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(dailyCalorieGoal)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.green)
                    Text("Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Text("+")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    Text("\(exerciseBurnCalories)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Text("−")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    Text("\(actualConsumedCalories)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text("Food")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Text("=")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    Text("\(remainingCalories)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(remainingCalories < 0 ? .red : .primary)
                    Text("Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 28).padding(.horizontal, 6)

                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 9))
                            .foregroundColor(waterGlasses >= waterGoal ? .cyan : .blue)
                        Text("\(waterGlasses)/\(waterGoal)")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(waterGlasses >= waterGoal ? .cyan : .blue)
                    }
                    Text("Water")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
        .onAppear {
            profile.updateNutritionFromFoodEntries(todaysFoodEntries)
        }
        .onChange(of: todaysFoodEntries.count) { _, _ in
            profile.updateNutritionFromFoodEntries(todaysFoodEntries)
            context.safeSave()
        }
    }

    // MARK: - Macro Breakdown
    private var macroBreakdownView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    macrosExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Macronutrients")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Image(systemName: macrosExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if macrosExpanded {
                VStack(spacing: 14) {
                    macroRow(name: "Protein", consumed: Int(todaysProtein), goal: proteinGoal, color: .green)
                    macroRow(name: "Carbs", consumed: Int(todaysCarbs), goal: carbGoal, color: .blue)
                    // Net carbs sub-row (indented, no progress bar)
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Net Carbs")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("\(Int(todaysNetCarbs))g")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue.opacity(0.7))
                        Text("(\(Int(todaysFiber))g fiber deducted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)

                    macroRow(name: "Fat", consumed: Int(todaysFat), goal: fatGoal, color: .red)

                    // Fiber row — no goal line, informational
                    HStack {
                        let fiberGoal: Double = profile.gender == .male ? 38.0 : 25.0
                        Text("Fiber")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 60, alignment: .leading)
                        ProgressView(value: min(1.0, todaysFiber / fiberGoal))
                            .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                        Text("\(Int(todaysFiber))g / \(Int(fiberGoal))g")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    private func macroRow(name: String, consumed: Int, goal: Int, color: Color) -> some View {
        HStack {
            Text(name)
                .font(.subheadline.weight(.medium))
                .frame(width: 60, alignment: .leading)

            ProgressView(value: Double(consumed) / Double(max(1, goal)))
                .progressViewStyle(LinearProgressViewStyle(tint: color))

            Text("\(consumed)g / \(goal)g")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: - Micronutrient Breakdown

    // Computed daily micronutrient totals from today's food entries
    private var todaysPotassium: Double  { todaysFoodEntries.reduce(0) { $0 + $1.totalPotassium } }
    private var todaysCalcium: Double    { todaysFoodEntries.reduce(0) { $0 + $1.totalCalcium } }
    private var todaysIron: Double       { todaysFoodEntries.reduce(0) { $0 + $1.totalIron } }
    private var todaysMagnesium: Double  { todaysFoodEntries.reduce(0) { $0 + $1.totalMagnesium } }
    private var todaysZinc: Double       { todaysFoodEntries.reduce(0) { $0 + $1.totalZinc } }
    private var todaysVitaminC: Double   { todaysFoodEntries.reduce(0) { $0 + $1.totalVitaminC } }
    private var todaysVitaminB12: Double { todaysFoodEntries.reduce(0) { $0 + $1.totalVitaminB12 } }
    private var todaysVitaminD: Double   { todaysFoodEntries.reduce(0) { $0 + $1.totalVitaminD } }
    private var todaysCholesterol: Double { todaysFoodEntries.reduce(0) { $0 + $1.totalCholesterol } }
    private var todaysSaturatedFat: Double { todaysFoodEntries.reduce(0) { $0 + $1.totalSaturatedFat } }

    /// True only when at least one tracked food has micronutrient data
    @ViewBuilder
    private func goalAlignedSection(food: FoodItem, goal: FitnessGoal) -> some View {
        let score = food.goalAlignedScore(for: goal)
        let grade = food.goalAlignedGrade(for: goal)
        let gradeCol: Color = {
            switch grade {
            case "A": return .green
            case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
            case "C": return .yellow
            case "D": return .orange
            default: return .red
            }
        }()

        VStack(alignment: .leading, spacing: 10) {
            Label("GOAL-ALIGNED SCORE", systemImage: "target")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Grade badge
                ZStack {
                    Circle()
                        .fill(gradeCol.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(grade)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(gradeCol)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("For \(goal.rawValue.capitalized)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    // Score bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            Capsule().fill(gradeCol)
                                .frame(width: geo.size.width * CGFloat(score) / 100, height: 8)
                        }
                    }
                    .frame(height: 8)
                    Text("\(score)/100")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                // NOVA badge if available
                if food.novaGroup > 0 {
                    VStack(spacing: 2) {
                        Text("NOVA")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(food.novaGroup)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(food.novaGroup == 4 ? .red : food.novaGroup == 3 ? .orange : .green)
                        Text(["", "Unprocessed", "Culinary", "Processed", "Ultra"][min(max(food.novaGroup, 0), 4)])
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 58)
                    .padding(6)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var hasMicroData: Bool {
        todaysPotassium + todaysCalcium + todaysIron + todaysMagnesium +
        todaysVitaminC + todaysVitaminB12 + todaysVitaminD > 0
    }

    @ViewBuilder
    private var micronutrientBreakdownView: some View {
        if hasMicroData {
            VStack(alignment: .leading, spacing: 12) {
                Text("Micronutrients")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    // Minerals
                    Group {
                        microRow(name: "Potassium",   value: todaysPotassium,  goal: 3500, unit: "mg", color: .yellow)
                        microRow(name: "Calcium",     value: todaysCalcium,    goal: 1000, unit: "mg", color: .mint)
                        microRow(name: "Magnesium",   value: todaysMagnesium,  goal: 400,  unit: "mg", color: .teal)
                        microRow(name: "Iron",        value: todaysIron,       goal: 18,   unit: "mg", color: .red)
                        microRow(name: "Zinc",        value: todaysZinc,       goal: 11,   unit: "mg", color: .blue)
                    }
                    // Vitamins
                    Group {
                        microRow(name: "Vitamin C",  value: todaysVitaminC,   goal: 90,   unit: "mg",  color: .orange)
                        microRow(name: "Vitamin B12",value: todaysVitaminB12, goal: 2.4,  unit: "mcg", color: .purple)
                        microRow(name: "Vitamin D",  value: todaysVitaminD,   goal: 15,   unit: "mcg", color: .yellow)
                    }
                    // Other
                    Group {
                        microRow(name: "Saturated Fat", value: todaysSaturatedFat, goal: 20, unit: "g", color: .red)
                        if todaysCholesterol > 0 {
                            microRow(name: "Cholesterol", value: todaysCholesterol, goal: 300, unit: "mg", color: .orange)
                        }
                    }
                }
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? .black : .white)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
    }

    private func microRow(name: String, value: Double, goal: Double, unit: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption.weight(.medium))
                .frame(width: 90, alignment: .leading)
                .foregroundColor(.primary)

            ProgressView(value: min(1.0, value / max(1, goal)))
                .progressViewStyle(LinearProgressViewStyle(tint: color))

            Text(value < 1 ? String(format: "%.1f\(unit)", value) : "\(Int(value))\(unit)")
                .font(.caption.weight(.semibold))
                .foregroundColor(value >= goal ? color : .secondary)
                .frame(width: 60, alignment: .trailing)
                .lineLimit(1)
        }
    }

    // MARK: - Meals Section
    private var mealsSection: some View {
        VStack(spacing: 12) {
            mealSection(title: "Breakfast", mealType: .breakfast, color: .orange)
            mealSection(title: "Lunch", mealType: .lunch, color: .blue)
            mealSection(title: "Dinner", mealType: .dinner, color: .purple)
            mealSection(title: "Snacks", mealType: .snacks, color: .green)
        }
    }

    private func mealSection(title: String, mealType: MealType, color: Color) -> some View {
        let mealEntries = todaysFoodEntries.filter { $0.meal == mealType }
        let calories = Int(mealEntries.reduce(0) { $0 + $1.totalCalories })

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)

                Spacer()

                if calories > 0 {
                    Text("\(calories) cal")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            if !mealEntries.isEmpty {
                // List is required for .swipeActions to work
                List {
                    ForEach(mealEntries, id: \.id) { entry in
                        foodEntryRow(entry: entry)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                entryForNutrition = entry
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isDateLocked {
                                    Button(role: .destructive) {
                                        deleteFoodEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        entryToEdit = entry
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(mealEntries.count) * 62)

                if !isDateLocked {
                    Button("Log Rations") {
                        selectedMealForAdding = mealType
                        showingAddFood = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
            } else if !isDateLocked {
                Button("Log Rations") {
                    selectedMealForAdding = mealType
                    showingAddFood = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.1))
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
            } else {
                Text("No meals logged")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .black : .white)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    private func foodEntryRow(entry: FoodEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.foodItem?.name ?? "Unknown")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    foodMacroChip(label: "P", value: entry.totalProtein, color: .blue)
                    foodMacroChip(label: "C", value: entry.totalCarbs, color: .orange)
                    foodMacroChip(label: "F", value: entry.totalFat, color: .yellow)
                    if entry.quantity != 1 {
                        Text("\(Int(entry.quantity))\(entry.unit == .grams ? "g" : "×")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(entry.totalCalories))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("kcal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func foodMacroChip(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
            Text("\(Int(value))g")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }



    // MARK: - Copy Yesterday's Meals
    private func deleteFoodEntry(_ entry: FoodEntry) {
        context.delete(entry)
        context.safeSave()
    }

    private func copyYesterdaysMeals() {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: selectedDate) else { return }

        let yesterdayEntries = foodEntries.filter { cal.isDate($0.dateConsumed, inSameDayAs: yesterday) }
        guard !yesterdayEntries.isEmpty else { return }

        for entry in yesterdayEntries {
            guard let food = entry.foodItem else { continue }
            let copy = FoodEntry(
                foodItem: food,
                quantity: entry.quantity,
                unit: entry.unit,
                meal: entry.meal,
                dateConsumed: selectedDate
            )
            context.insert(copy)
        }
        context.safeSave()
    }
}

// FoodEntryEditSheet, ReplaceEntryPicker, FoodNutritionSheet, NutritionCell,
// NutritionGoalsView, AddFoodView, FoodSourceBadge, NutritionGradeBadge,
// IngredientSafetyFlags, FoodItemRow, FoodCreatorView, QuickAddView, and
// FoodDetailsView have been extracted to DietViewComponents.swift.

#Preview {
    DietView()
        .modelContainer(for: [Profile.self, FoodItem.self, FoodEntry.self, CustomMeal.self], inMemory: true)
}

// MARK: - Custom Meal Row

struct CustomMealRow: View {
    let meal: CustomMeal
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)

                    if let description = meal.details {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        Text("\(Int(meal.totalCalories)) cal")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)

                        Text("\(meal.foodItems?.count ?? 0) items")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if meal.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Spacer()

                Button {
                    onAdd()
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.green)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Meal Creator View

struct MealCreatorView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("🍳")
                    .font(.system(size: 60))

                Text("Meal Creator")
                    .font(.largeTitle.weight(.bold))

                Text("Create custom meals with AI assistance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Coming Soon!")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Planned Features:")
                        .font(.headline.weight(.semibold))

                    Text("• AI-powered recipe suggestions")
                    Text("• Automatic nutrition calculation")
                    Text("• Ingredient substitutions")
                    Text("• Meal planning assistance")
                    Text("• Save favorite combinations")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )

                Spacer()
            }
            .padding()
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension FoodUnit: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension MealType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

// MARK: - Barcode Scanner Wrapper

struct BarcodeScannerWrapper: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let scanner = BarcodeScannerViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, BarcodeScannerDelegate {
        let parent: BarcodeScannerWrapper

        init(_ parent: BarcodeScannerWrapper) {
            self.parent = parent
        }

        func didCancel() {
            parent.onDismiss()
        }

        func didEncounterError(_ error: Error) {
            print("Barcode scanner error: \(error)")
            parent.onDismiss()
        }

        func didScanBarcode(_ code: String) {
            parent.onBarcodeScanned(code)
        }
    }
}
