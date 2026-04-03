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
                    Text("My Diary")
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
                    try? context.save()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(waterGlasses > 0 ? .blue : .gray.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(waterGlasses == 0)
                .frame(maxWidth: .infinity)

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
                    try? context.save()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
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
            try? context.save()
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
                    Button("Add Food") {
                        selectedMealForAdding = mealType
                        showingAddFood = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
            } else if !isDateLocked {
                Button("Add Food") {
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
        try? context.save()
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
        try? context.save()
    }
}

// MARK: - Food Entry Edit Sheet

/// Allows the user to change quantity/unit of an existing food entry, or replace the
/// food entirely by opening the food search picker.
struct FoodEntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: FoodEntry

    @State private var quantity: String = ""
    @State private var selectedUnit: FoodUnit = .grams
    @State private var showingReplace = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    HStack {
                        Text(entry.foodItem?.name ?? "Unknown")
                            .font(.headline)
                        Spacer()
                        Button("Replace") {
                            showingReplace = true
                        }
                        .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Per \(Int(entry.quantity)) \(entry.unit.rawValue)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(entry.totalCalories)) kcal · \(String(format: "%.0f", entry.totalProtein))g P · \(String(format: "%.0f", entry.totalCarbs))g C · \(String(format: "%.0f", entry.totalFat))g F")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .opacity(entry.totalCalories > 0 ? 1 : 0.5)
                }

                Section("Amount") {
                    HStack {
                        TextField("Quantity", text: $quantity)
                            .keyboardType(.decimalPad)
                        Divider()
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(FoodUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Button("Save Changes", action: save)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) {
                        context.delete(entry)
                        try? context.save()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                quantity = String(format: "%.0f", entry.quantity)
                selectedUnit = entry.unit
            }
            .sheet(isPresented: $showingReplace) {
                ReplaceEntryPicker(entry: entry, onReplaced: { dismiss() })
            }
        }
    }

    private func save() {
        let newQty = Double(quantity) ?? entry.quantity
        entry.quantity = newQty
        entry.unit = selectedUnit
        try? context.save()
        dismiss()
    }
}

/// Opens the existing food search UI so the user can pick a replacement item.
/// On selection the original FoodEntry is updated in-place.
struct ReplaceEntryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]

    let entry: FoodEntry
    let onReplaced: () -> Void

    @State private var searchText = ""

    private var filtered: [FoodItem] {
        if searchText.isEmpty { return Array(allFoods.prefix(40)) }
        return allFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.id) { food in
                    Button {
                        entry.foodItem = food
                        try? context.save()
                        onReplaced()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text("\(Int(food.caloriesPerServing)) kcal · \(String(format: "%.0f", food.protein))g P · \(String(format: "%.0f", food.carbohydrates))g C · \(String(format: "%.0f", food.fat))g F")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search foods…")
            .navigationTitle("Replace Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Food Nutrition Sheet

struct FoodNutritionSheet: View {
    let entry: FoodEntry
    var fitnessGoal: FitnessGoal? = nil
    @Environment(\.dismiss) private var dismiss

    private var food: FoodItem? { entry.foodItem }
    private var qty: Double { entry.quantity }
    private var gradeColor: Color {
        switch food?.nutritionGrade ?? "C" {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero header
                    ZStack {
                        LinearGradient(
                            colors: [gradeColor.opacity(0.25), gradeColor.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(gradeColor.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                Text(food?.nutritionGrade ?? "?")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundColor(gradeColor)
                            }
                            .padding(.top, 16)

                            Text(food?.name ?? "Unknown Food")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)

                            if let brand = food?.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Nutrition Grade")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal)
                    }

                    VStack(spacing: 20) {
                        // Serving info
                        servingSection

                        // Macros
                        macroSection

                        // Goal-Aligned Score (if profile goal is available)
                        if let goal = fitnessGoal, let f = food {
                            goalAlignedSection(food: f, goal: goal)
                        }

                        // Micros (only if any data available)
                        if hasMicroData { microSection }
                    }
                    .padding()
                }
            }
            .navigationTitle("Nutrition Facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("SERVING", systemImage: "scalemass.fill")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                NutritionCell(label: "Amount", value: "\(Int(qty)) \(entry.unit.rawValue)", color: .blue)
                NutritionCell(label: "Calories", value: "\(Int(entry.totalCalories))", color: .orange)
                if let s = food?.servingSize, s > 0 {
                    NutritionCell(label: "Serving Size", value: "\(Int(s))g", color: .secondary)
                }
            }
        }
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MACRONUTRIENTS", systemImage: "chart.pie.fill")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NutritionCell(label: "Protein", value: "\(String(format: "%.1f", entry.totalProtein))g", color: .blue)
                NutritionCell(label: "Carbs", value: "\(String(format: "%.1f", entry.totalCarbs))g", color: .green)
                NutritionCell(label: "Fat", value: "\(String(format: "%.1f", entry.totalFat))g", color: .yellow)
                if let f = food?.fiber, f > 0 {
                    NutritionCell(label: "Fiber", value: "\(String(format: "%.1f", scaledValue(f)))g", color: .mint)
                }
                if let s = food?.sugar, s > 0 {
                    NutritionCell(label: "Sugar", value: "\(String(format: "%.1f", scaledValue(s)))g", color: .pink)
                }
                if let s = food?.saturatedFatG, s > 0 {
                    NutritionCell(label: "Sat. Fat", value: "\(String(format: "%.1f", scaledValue(s)))g", color: .red)
                }
            }
        }
    }

    private var microSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MICRONUTRIENTS", systemImage: "atom")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let v = food?.sodium, v > 0 {
                    NutritionCell(label: "Sodium", value: "\(Int(scaledValue(v)))mg", color: .orange)
                }
                if let v = food?.potassiumMg, v > 0 {
                    NutritionCell(label: "Potassium", value: "\(Int(scaledValue(v)))mg", color: .purple)
                }
                if let v = food?.calciumMg, v > 0 {
                    NutritionCell(label: "Calcium", value: "\(Int(scaledValue(v)))mg", color: .teal)
                }
                if let v = food?.ironMg, v > 0 {
                    NutritionCell(label: "Iron", value: "\(String(format: "%.1f", scaledValue(v)))mg", color: .red)
                }
                if let v = food?.magnesiumMg, v > 0 {
                    NutritionCell(label: "Magnesium", value: "\(Int(scaledValue(v)))mg", color: .green)
                }
                if let v = food?.zincMg, v > 0 {
                    NutritionCell(label: "Zinc", value: "\(String(format: "%.1f", scaledValue(v)))mg", color: .cyan)
                }
                if let v = food?.vitaminCMg, v > 0 {
                    NutritionCell(label: "Vitamin C", value: "\(Int(scaledValue(v)))mg", color: .yellow)
                }
                if let v = food?.vitaminB12Mcg, v > 0 {
                    NutritionCell(label: "B12", value: "\(String(format: "%.1f", scaledValue(v)))mcg", color: .indigo)
                }
                if let v = food?.vitaminDMcg, v > 0 {
                    NutritionCell(label: "Vitamin D", value: "\(String(format: "%.1f", scaledValue(v)))mcg", color: .orange)
                }
                if let v = food?.cholesterolMg, v > 0 {
                    NutritionCell(label: "Cholesterol", value: "\(Int(scaledValue(v)))mg", color: .red)
                }
            }
        }
    }

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
        guard let f = food else { return false }
        return f.sodium > 0 || f.potassiumMg > 0 || f.calciumMg > 0 || f.ironMg > 0 ||
               f.magnesiumMg > 0 || f.zincMg > 0 || f.vitaminCMg > 0 ||
               f.vitaminB12Mcg > 0 || f.vitaminDMcg > 0 || f.cholesterolMg > 0
    }

    /// Scale a per-100g value to the actual quantity logged.
    private func scaledValue(_ per100g: Double) -> Double {
        let grams: Double
        switch entry.unit {
        case .grams:        grams = qty
        case .servings:     grams = qty * (food?.servingSize ?? 100)
        case .cups:         grams = qty * 240
        case .tablespoons:  grams = qty * 15
        case .teaspoons:    grams = qty * 5
        case .ounces:       grams = qty * 28.35
        case .pounds:       grams = qty * 453.6
        case .milliliters:  grams = qty // water density ≈ 1g/ml
        case .liters:       grams = qty * 1000
        case .pieces:       grams = qty * (food?.servingSize ?? 100)
        }
        return per100g * grams / 100
    }
}

struct NutritionCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Nutrition Goals Editor

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    private var profile: Profile? { profiles.first }

    private let activityLabels = ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active"]
    private let activityDescriptions = [
        "Desk job, little exercise",
        "Light exercise 1–3 days/week",
        "Moderate exercise 3–5 days/week",
        "Hard exercise 6–7 days/week",
        "Physical job + hard daily training"
    ]

    // Local state mirrors profile values
    @State private var activityIndex: Int = 1
    @State private var calorieOverride: String = ""
    @State private var proteinOverride: String = ""
    @State private var carbOverride: String = ""
    @State private var fatOverride: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // ── TDEE Preview ─────────────────────────────────────────────
                if let p = profile {
                    Section(header: Text("Your Estimated TDEE")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("BMR", systemImage: "flame")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("\(Int(p.bmr)) kcal/day")
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Label("TDEE (with activity)", systemImage: "figure.run")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("\(Int(p.tdee)) kcal/day")
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Label("Goal Adjustment", systemImage: "target")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("\(p.effectiveCalorieGoal) kcal/day")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.blue)
                            }
                            Text("Based on \(p.fitnessGoal.displayName) goal (Mifflin-St Jeor)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Activity Level ───────────────────────────────────────────
                Section(header: Text("Activity Level")) {
                    Picker("Activity Level", selection: $activityIndex) {
                        ForEach(0..<activityLabels.count, id: \.self) { i in
                            VStack(alignment: .leading) {
                                Text(activityLabels[i])
                                Text(activityDescriptions[i])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(i)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // ── Custom Overrides ─────────────────────────────────────────
                Section(
                    header: Text("Custom Goals (optional)"),
                    footer: Text("Leave blank to auto-calculate from TDEE and your fitness goal.")
                ) {
                    HStack {
                        Label("Calories", systemImage: "flame.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        TextField("Auto", text: $calorieOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Protein", systemImage: "fork.knife")
                            .foregroundColor(.green)
                        Spacer()
                        TextField("Auto", text: $proteinOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Carbs", systemImage: "leaf.fill")
                            .foregroundColor(.blue)
                        Spacer()
                        TextField("Auto", text: $carbOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Label("Fat", systemImage: "drop.fill")
                            .foregroundColor(.red)
                        Spacer()
                        TextField("Auto", text: $fatOverride)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // ── Reset ────────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        calorieOverride = ""; proteinOverride = ""
                        carbOverride = ""; fatOverride = ""
                    } label: {
                        Label("Clear All Custom Goals", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Nutrition Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadFromProfile() }
        }
    }

    private func loadFromProfile() {
        guard let p = profile else { return }
        activityIndex = p.activityLevelIndex
        calorieOverride = p.customCalorieGoal > 0 ? "\(p.customCalorieGoal)" : ""
        proteinOverride = p.customProteinGoal > 0 ? "\(p.customProteinGoal)" : ""
        carbOverride = p.customCarbGoal > 0 ? "\(p.customCarbGoal)" : ""
        fatOverride = p.customFatGoal > 0 ? "\(p.customFatGoal)" : ""
    }

    private func save() {
        guard let p = profile else { dismiss(); return }
        p.activityLevelIndex = activityIndex
        p.customCalorieGoal = Int(calorieOverride) ?? 0
        p.customProteinGoal = Int(proteinOverride) ?? 0
        p.customCarbGoal = Int(carbOverride) ?? 0
        p.customFatGoal = Int(fatOverride) ?? 0
        try? context.save()
        dismiss()
    }
}

#Preview {
    DietView()
        .modelContainer(for: [Profile.self, FoodItem.self, FoodEntry.self, CustomMeal.self], inMemory: true)
}

// MARK: - Add Food View

struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]
    @Query private var customMeals: [CustomMeal]
    
    @Binding var selectedMeal: MealType
    let selectedDate: Date
    
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var showingFoodCreator = false
    @State private var showingQuickAdd = false
    @State private var showingBarcodeScanner = false
    @State private var isLoadingBarcode = false
    @State private var barcodeError: String?

    // Live remote search
    @State private var remoteSearchResults: [FoodItem] = []
    @State private var isSearchingRemote = false
    @State private var remoteSearchTask: Task<Void, Never>? = nil
    @State private var showingRemoteSection = false

    @StateObject private var foodDatabase = FoodDatabaseService.shared
    
    private var filteredFoods: [FoodItem] {
        if searchText.isEmpty {
            return allFoods.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return FuzzySearch.sort(query: searchText, items: allFoods, string: { $0.name },
                                    additionalStrings: { food in [food.brand].compactMap { $0 } })
        }
    }

    private func triggerRemoteSearch(_ query: String) {
        remoteSearchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            remoteSearchResults = []
            showingRemoteSection = false
            return
        }
        remoteSearchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            isSearchingRemote = true
            let results = (try? await foodDatabase.searchFood(query: query, limit: 20)) ?? []
            guard !Task.isCancelled else { return }
            // Deduplicate against local
            let localNames = Set(allFoods.map { $0.name.lowercased() })
            remoteSearchResults = results.filter { !localNames.contains($0.name.lowercased()) }
            isSearchingRemote = false
            showingRemoteSection = !remoteSearchResults.isEmpty
        }
    }

    private var filteredMeals: [CustomMeal] {
        if searchText.isEmpty {
            return customMeals.sorted { $0.lastUsed ?? Date.distantPast > $1.lastUsed ?? Date.distantPast }
        } else {
            return FuzzySearch.sort(query: searchText, items: customMeals, string: { $0.name })
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar with Barcode Scanner
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search foods or meals...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newVal in
                            if selectedTab == 0 { triggerRemoteSearch(newVal) }
                        }
                    
                    if isSearchingRemote {
                        ProgressView().scaleEffect(0.7)
                    } else if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
                            remoteSearchResults = []
                            showingRemoteSection = false
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    Button {
                        showingBarcodeScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)
                .padding(.top)
                
                // Loading indicator for barcode scanning
                if isLoadingBarcode {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Looking up product...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // Error message for barcode scanning
                if let error = barcodeError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                // Tab Picker
                Picker("Type", selection: $selectedTab) {
                    Text("Foods").tag(0)
                    Text("Meals").tag(1)
                    Text("Recent").tag(2)
                    Text("Favorites").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if selectedTab == 0 {
                            // Local Foods
                            ForEach(filteredFoods, id: \.id) { food in
                                FoodItemRow(food: food) { quantity, unit in
                                    addFoodEntry(food: food, quantity: quantity, unit: unit)
                                }
                            }

                            // Remote search results (USDA + Open Food Facts)
                            if showingRemoteSection {
                                HStack(spacing: 8) {
                                    let hasUSDA = remoteSearchResults.contains { $0.dataSource == "USDA" }
                                    let hasOFF  = remoteSearchResults.contains { $0.dataSource == "OpenFoodFacts" }
                                    Image(systemName: "network")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if hasUSDA && hasOFF {
                                        Text("USDA + OPEN FOOD FACTS")
                                    } else if hasUSDA {
                                        Text("USDA VERIFIED")
                                    } else {
                                        Text("OPEN FOOD FACTS")
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)

                                ForEach(remoteSearchResults, id: \.id) { food in
                                    FoodItemRow(food: food, showSourceBadge: true) { quantity, unit in
                                        // Save to local DB on first use
                                        context.insert(food)
                                        try? context.save()
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                            
                            if filteredFoods.isEmpty && remoteSearchResults.isEmpty && !isSearchingRemote && !searchText.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    
                                    Text("No foods found")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Try scanning a barcode or creating a custom food")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                                    Button("Scan Barcode") {
                                        showingBarcodeScanner = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding()
                            }
                        } else if selectedTab == 1 {
                            // Custom Meals
                            ForEach(filteredMeals, id: \.id) { meal in
                                CustomMealRow(meal: meal) {
                                    addCustomMeal(meal: meal)
                                }
                            }
                        } else if selectedTab == 2 {
                            // Recent Foods
                            let recentFoods = allFoods.filter { $0.lastUsed != nil }
                                .sorted { $0.lastUsed! > $1.lastUsed! }
                                .prefix(20)
                            if recentFoods.isEmpty {
                                Text("No recently logged foods")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            } else {
                                ForEach(Array(recentFoods), id: \.id) { food in
                                    FoodItemRow(food: food) { quantity, unit in
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                        } else {
                            // Favorites
                            let favoriteFoods = allFoods.filter { $0.isFavorite }
                                .sorted { $0.name < $1.name }
                            if favoriteFoods.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "heart.slash")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No favorite foods yet")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("Tap the heart icon on any food to add it here")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                ForEach(favoriteFoods, id: \.id) { food in
                                    FoodItemRow(food: food) { quantity, unit in
                                        addFoodEntry(food: food, quantity: quantity, unit: unit)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to \(selectedMeal.displayName)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Scan Barcode", systemImage: "barcode.viewfinder") {
                            showingBarcodeScanner = true
                        }
                        Button("Create Food", systemImage: "plus") {
                            showingFoodCreator = true
                        }
                        Button("Quick Add", systemImage: "bolt") {
                            showingQuickAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingFoodCreator) {
                FoodCreatorView()
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView(selectedMeal: selectedMeal, selectedDate: selectedDate)
            }
            .fullScreenCover(isPresented: $showingBarcodeScanner) {
                BarcodeScannerWrapper(onBarcodeScanned: { barcode in
                    showingBarcodeScanner = false
                    handleBarcodeScanned(barcode)
                }, onDismiss: {
                    showingBarcodeScanner = false
                })
            }
        }
    }
    
    private func handleBarcodeScanned(_ barcode: String) {
        isLoadingBarcode = true
        barcodeError = nil

        // AVCapture pads 12-digit UPC-A to 13-digit EAN-13 with a leading "0".
        // Strip it so Supabase lookups match stored 12-digit UPC-A codes.
        let lookupBarcode = barcode.count == 13 && barcode.hasPrefix("0")
            ? String(barcode.dropFirst())
            : barcode

        Task {
            do {
                let food = try await foodDatabase.searchFoodByBarcode(lookupBarcode)
                
                await MainActor.run {
                    isLoadingBarcode = false
                    
                    if let food = food {
                        // Add the food to the database
                        context.insert(food)
                        try? context.save()
                        
                        // Show the food in a selection view
                        showFoodForSelection(food)
                        
                        // Provide haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    } else {
                        barcodeError = "Product not found. Try creating it manually."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingBarcode = false
                    barcodeError = error.localizedDescription
                }
            }
        }
    }
    
    private func showFoodForSelection(_ food: FoodItem) {
        // Filter to show only this food
        searchText = food.name
        selectedTab = 0
    }
    
    private func addFoodEntry(food: FoodItem, quantity: Double, unit: FoodUnit) {
        let entry = FoodEntry(
            foodItem: food,
            quantity: quantity,
            unit: unit,
            meal: selectedMeal,
            dateConsumed: selectedDate
        )
        
        context.insert(entry)
        try? context.save()
        dismiss()
    }
    
    private func addCustomMeal(meal: CustomMeal) {
        for item in meal.foodItems ?? [] {
            guard let fi = item.foodItem else { continue }
            let entry = FoodEntry(
                foodItem: fi,
                quantity: item.quantity,
                unit: item.unit,
                meal: selectedMeal,
                dateConsumed: selectedDate
            )
            context.insert(entry)
        }
        
        meal.lastUsed = Date()
        try? context.save()
        dismiss()
    }
}

// MARK: - Food Item Row

// MARK: - Nutrition Grade Badge

/// Yuka-style A/B/C/D/F grade badge for a food item.
// MARK: - Food Source Badge

struct FoodSourceBadge: View {
    let source: String

    private var label: String {
        switch source {
        case "USDA":          return "USDA"
        case "OpenFoodFacts": return "OFF"
        default:              return source.prefix(4).uppercased()
        }
    }

    private var badgeColor: Color {
        source == "USDA" ? .blue : .secondary
    }

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(source == "USDA" ? "USDA FoodData Central — verified data" : "Open Food Facts — community data")
    }
}

struct NutritionGradeBadge: View {
    let grade: String
    let score: Int

    private var badgeColor: Color {
        switch grade {
        case "A": return .green
        case "B": return Color(red: 0.4, green: 0.8, blue: 0.2)
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(grade)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .help("Nutrition score: \(score)/100")
    }
}

// MARK: - Ingredient Safety Analysis

struct IngredientSafetyFlags: View {
    let food: FoodItem

    struct Flag: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let color: Color
    }

    private var flags: [Flag] {
        var result: [Flag] = []
        // Sodium per 100g > 600mg is high (WHO daily limit is 2000mg)
        if food.sodium > 600 {
            result.append(Flag(icon: "drop.triangle.fill", label: "High Sodium", color: .orange))
        }
        // Sugar per 100g > 20g is high
        if food.sugar > 20 {
            result.append(Flag(icon: "cube.fill", label: "High Sugar", color: .red))
        }
        // Saturated-style: fat per 100g > 30g is high
        if food.fat > 30 {
            result.append(Flag(icon: "exclamationmark.triangle.fill", label: "High Fat", color: .yellow))
        }
        // Very low protein for a "protein" category food
        if food.category == .protein && food.protein < 10 {
            result.append(Flag(icon: "arrow.down.circle.fill", label: "Low Protein", color: .purple))
        }
        // NOVA classification (ultra-processed food warning)
        if food.novaGroup == 4 {
            result.append(Flag(icon: "bolt.trianglebadge.exclamationmark.fill", label: "Ultra-Processed", color: .red))
        } else if food.novaGroup == 3 {
            result.append(Flag(icon: "staroflife.fill", label: "Processed", color: .orange))
        }
        // Additive risk
        switch food.additiveRiskLevel {
        case 3:
            result.append(Flag(icon: "flask.fill", label: "High Additives", color: .red))
        case 2:
            result.append(Flag(icon: "flask.fill", label: "Some Additives", color: .orange))
        case 1:
            result.append(Flag(icon: "flask.fill", label: "Few Additives", color: .yellow))
        default:
            break
        }
        return result
    }

    var body: some View {
        if !flags.isEmpty {
            HStack(spacing: 6) {
                ForEach(flags) { flag in
                    HStack(spacing: 3) {
                        Image(systemName: flag.icon)
                            .font(.system(size: 9))
                            .foregroundColor(flag.color)
                        Text(flag.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(flag.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(flag.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
    }
}

struct FoodItemRow: View {
    let food: FoodItem
    var showSourceBadge: Bool = false
    let onAdd: (Double, FoodUnit) -> Void

    @Environment(\.modelContext) private var context
    @State private var quantity: Double = 1.0
    @State private var selectedUnit: FoodUnit = FoodUnit.servings
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let brand = food.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text("\(Int(food.caloriesPerServing)) cal/serving")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Nutrition grade badge
                        NutritionGradeBadge(grade: food.nutritionGrade, score: food.nutritionScore)

                        if !food.isCustom {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        // Data source badge
                        if showSourceBadge && !food.dataSource.isEmpty {
                            FoodSourceBadge(source: food.dataSource)
                        }
                    }

                    // Safety flags
                    IngredientSafetyFlags(food: food)
                }
                
                Spacer()

                // Favorite toggle
                Button {
                    food.isFavorite.toggle()
                    try? context.save()
                } label: {
                    Image(systemName: food.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(food.isFavorite ? .red : .secondary)
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
            
            HStack(spacing: 12) {
                // Quantity Input
                HStack(spacing: 8) {
                    Button {
                        if quantity > 0.25 {
                            quantity -= 0.25
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                    .disabled(quantity <= 0.25)
                    
                    Text(String(format: "%.2f", quantity))
                        .font(.subheadline.weight(.medium))
                        .frame(minWidth: 50)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        quantity += 0.25
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                
                // Unit Picker
                Picker("Unit", selection: $selectedUnit) {
                    ForEach([FoodUnit.servings, FoodUnit.grams, FoodUnit.cups, FoodUnit.ounces], id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                
                Spacer()
                
                // Add Button
                Button {
                    onAdd(quantity, selectedUnit)
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.blue)
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
        .sheet(isPresented: $showingDetails) {
            FoodDetailsView(food: food)
        }
    }
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

// MARK: - Additional Views (Enhanced Stubs)

struct FoodCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var name = ""
    @State private var brand = ""
    @State private var calories = ""
    @State private var servingSize = "100"
    @State private var selectedCategory: FoodCategory = .other
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Food Name", text: $name)
                    TextField("Brand (Optional)", text: $brand)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(FoodCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                
                Section("Nutrition (per serving)") {
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                    TextField("Serving Size (g)", text: $servingSize)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Create Food")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveFoodItem()
                    }
                    .disabled(name.isEmpty || calories.isEmpty)
                }
            }
        }
    }
    
    private func saveFoodItem() {
        let caloriesValue = Double(calories) ?? 0
        let servingSizeValue = Double(servingSize) ?? 100
        
        let foodItem = FoodItem(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            caloriesPer100g: (caloriesValue * 100) / servingSizeValue,
            servingSize: servingSizeValue,
            category: selectedCategory
        )
        
        context.insert(foodItem)
        try? context.save()
        dismiss()
    }
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let selectedMeal: MealType
    let selectedDate: Date
    
    @State private var calories = ""
    @State private var description = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Quick Add Calories")
                    .font(.largeTitle.weight(.bold))
                
                Text("Quickly log calories when you don't have detailed food information")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    TextField("Calories", text: $calories)
                        .font(.title)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Description (Optional)", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                
                Button {
                    saveQuickAdd()
                } label: {
                    Text("Add \(calories.isEmpty ? "Calories" : "\(calories) cal") to \(selectedMeal.displayName)")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue)
                        )
                }
                .disabled(calories.isEmpty)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveQuickAdd() {
        let caloriesValue = Double(calories) ?? 0
        let foodName = description.isEmpty ? "Quick Add (\(Int(caloriesValue)) cal)" : description
        
        // Create a quick add food item — servingSize must be 100 so that
        // caloriesPerServing = caloriesPer100g (the user's entered value).
        let foodItem = FoodItem(
            name: foodName,
            caloriesPer100g: caloriesValue,
            servingSize: 100,
            category: .other
        )
        
        context.insert(foodItem)
        
        // Create the food entry
        let entry = FoodEntry(
            foodItem: foodItem,
            quantity: 1,
            unit: FoodUnit.servings,
            meal: selectedMeal,
            dateConsumed: selectedDate
        )
        
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}

struct FoodDetailsView: View {
    let food: FoodItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(food.name)
                            .font(.largeTitle.weight(.bold))
                        
                        if let brand = food.brand {
                            Text(brand)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Nutrition Facts
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nutrition Facts")
                            .font(.title2.weight(.semibold))
                        
                        VStack(spacing: 8) {
                            nutritionRow("Calories", "\(Int(food.caloriesPerServing))")
                            nutritionRow("Carbohydrates", "\(String(format: "%.1f", food.carbohydrates))g")
                            nutritionRow("Protein", "\(String(format: "%.1f", food.protein))g")
                            nutritionRow("Fat", "\(String(format: "%.1f", food.fat))g")
                            nutritionRow("Fiber", "\(String(format: "%.1f", food.fiber))g")
                            nutritionRow("Sugar", "\(String(format: "%.1f", food.sugar))g")
                            nutritionRow("Sodium", "\(String(format: "%.0f", food.sodium))mg")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    
                    // Additional Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional Information")
                            .font(.headline.weight(.semibold))
                        
                        HStack {
                            Text("Category:")
                            Text(food.category.displayName)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Source:")
                            Text(food.isCustom ? "Custom" : "Database")
                                .foregroundColor(.secondary)
                        }
                        
                        if let barcode = food.barcode {
                            HStack {
                                Text("Barcode:")
                                Text(barcode)
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Food Details")
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
    
    private func nutritionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

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
