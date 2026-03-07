import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorScheme") private var savedColorScheme = "dark"

    @State private var selectedTab = 0
    @StateObject private var dataManager = DataManager.shared
    @State private var now = Date()
    private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Daily Reset Countdown Timer
            countdownTimerView
                .padding(.top, 6)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .background(
                    (colorScheme == .dark ? Color.black.opacity(0.9) : Color.white)
                        .ignoresSafeArea(edges: .top)
                )

            // Main Tabs
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                QuestsView()
                    .tabItem { Label("Quests", systemImage: "target") }
                    .tag(1)

                DietView()
                    .tabItem { Label("Diet", systemImage: "fork.knife") }
                    .tag(2)

                WorkoutView()
                    .tabItem { Label("Training", systemImage: "figure.strengthtraining.traditional") }
                    .tag(3)

                LeaderboardView()
                    .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
                    .tag(4)

                InventoryAndShopView()
                    .tabItem { Label("Inventory", systemImage: "bag.fill") }
                    .tag(5)

                CoachView()
                    .tabItem { Label("System", systemImage: "waveform.badge.magnifyingglass") }
                    .tag(6)
            }
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
            )
        }
        .preferredColorScheme(savedColorScheme == "auto" ? nil : (savedColorScheme == "dark" ? .dark : .light))
        .background(colorScheme == .dark ? Color.black : Color.white)

        .onAppear {
            // Configure DataManager with SwiftData context
            dataManager.configure(with: modelContext)
            
            // Add back the futuristic tab bar styling once everything is working
            setupTabBarAppearance(for: colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            setupTabBarAppearance(for: newScheme)
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Countdown Timer View
    private var countdownTimerView: some View {
        HStack {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.cyan)
            Text(timeToMidnightString())
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.cyan)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func timeToMidnightString() -> String {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let comps = calendar.dateComponents([.hour, .minute, .second], from: now, to: startOfTomorrow)
        let h = comps.hour ?? 0, m = comps.minute ?? 0, s = comps.second ?? 0
        return String(format: "Reset in %02d:%02d:%02d", h, m, s)
    }

    private func setupTabBarAppearance(for scheme: ColorScheme) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = (scheme == .dark)
            ? UIColor.black.withAlphaComponent(0.8)
            : UIColor.white

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.gray,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        // Selected state (use dynamic cyan that looks good in both modes)
        let accent = UIColor.systemCyan
        appearance.stackedLayoutAppearance.selected.iconColor = accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: accent,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Quest.self, Profile.self, FoodItem.self, FoodEntry.self, CustomMeal.self], inMemory: true)
}
