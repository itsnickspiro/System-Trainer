import SwiftUI
import SwiftData

struct QuestsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Quest.createdAt, order: .reverse) private var quests: [Quest]
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedDay = Date()
    
    private var todaysQuests: [Quest] {
        quests.filter { Calendar.current.isDate($0.dateTag, inSameDayAs: selectedDay) }
    }
    
    private var activeQuests: [Quest] {
        todaysQuests.filter { !$0.isCompleted }
    }
    
    private var completedQuests: [Quest] {
        todaysQuests.filter { $0.isCompleted }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Week scroller
                WeekScroller(selectedDay: $selectedDay)
                    .padding(.vertical)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Real-World Data at the top to correlate with quests
                        RealWorldDataSummary()
                        
                        if activeQuests.isEmpty && completedQuests.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "target")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cyan.opacity(0.5))
                                
                                Text("No missions for this day")
                                    .font(.title3.bold())
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("Create your first quest to get started!")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Button("Create Quest") {
                                    // Create a sample quest for demonstration
                                    let quest = Quest(
                                        title: "Morning Workout",
                                        details: "Complete 30 minutes of exercise",
                                        type: .daily,
                                        xpReward: 50,
                                        dateTag: selectedDay
                                    )
                                    context.insert(quest)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 60)
                        } else {
                            // Active missions section
                            if !activeQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("ACTIVE MISSIONS")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.cyan.opacity(0.8))
                                        Spacer()
                                        Text("\(activeQuests.count) remaining")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    ForEach(activeQuests) { quest in
                                        QuestRow(quest: quest) {
                                            toggleQuestCompletion(quest)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Completed missions section  
                            if !completedQuests.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("COMPLETED")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.green.opacity(0.8))
                                        Spacer()
                                        Text("\(completedQuests.count) done")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    
                                    ForEach(completedQuests) { quest in
                                        QuestRow(quest: quest) {
                                            toggleQuestCompletion(quest)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.large)
            .background(colorScheme == .dark ? .black.opacity(0.95) : .white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        addSampleQuest()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
    }
    
    private func toggleQuestCompletion(_ quest: Quest) {
        if quest.isCompleted {
            // Un-complete: clear flag and remove completion date only
            quest.isCompleted = false
            quest.completedAt = nil
            try? context.save()
        } else {
            // Complete via DataManager so XP is awarded and Firebase is synced
            dataManager.completeQuest(quest)
        }
    }
    
    private func addSampleQuest() {
        let sampleQuests = [
            ("Hydration Check", "Drink 8 glasses of water", 25),
            ("Power Walk", "Walk 10,000 steps", 40),
            ("Mindful Moment", "Meditate for 10 minutes", 30),
            ("Strength Session", "Complete strength training", 60),
            ("Healthy Meal", "Prepare a nutritious meal", 35)
        ]
        
        let randomQuest = sampleQuests.randomElement()!
        let quest = Quest(
            title: randomQuest.0,
            details: randomQuest.1,
            type: .daily,
            xpReward: randomQuest.2,
            dateTag: selectedDay
        )
        context.insert(quest)
    }
}

#Preview {
    QuestsView()
        .modelContainer(for: [Quest.self, Profile.self], inMemory: true)
}

struct RealWorldDataSummary: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [Profile]
    private var profile: Profile { profiles.first ?? Profile() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REAL-WORLD DATA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                Spacer()
                Text("+\(xpToday)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                miniMetric(title: "Steps", value: "\(profile.dailySteps)", goal: profile.dailyStepsGoal, icon: "figure.walk", color: .blue)
                miniMetric(title: "Active Cal", value: "\(profile.dailyActiveCalories)", goal: profile.dailyActiveCaloriesGoal, icon: "flame.fill", color: .orange)
                miniMetric(title: "Sleep", value: String(format: "%.1fh", profile.sleepHours), goal: 8, icon: "bed.double.fill", color: .purple)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.green.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private var xpToday: Int {
        // simple heuristic: award XP based on steps and calories ratios
        let stepsXP = Int(Double(profile.dailySteps) / Double(max(1, profile.dailyStepsGoal)) * 30)
        let calXP = Int(Double(profile.dailyActiveCalories) / Double(max(1, profile.dailyActiveCaloriesGoal)) * 20)
        let sleepXP = Int(min(1.0, profile.sleepHours / 8.0) * 10)
        return max(0, stepsXP + calXP + sleepXP)
    }

    @ViewBuilder
    private func miniMetric(title: String, value: String, goal: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.8))
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .tint(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func progress(for title: String) -> Double {
        switch title {
        case "Steps":
            return min(1.0, Double(profile.dailySteps) / Double(max(1, profile.dailyStepsGoal)))
        case "Active Cal":
            return min(1.0, Double(profile.dailyActiveCalories) / Double(max(1, profile.dailyActiveCaloriesGoal)))
        case "Sleep":
            return min(1.0, profile.sleepHours / 8.0)
        default:
            return 0
        }
    }
}
