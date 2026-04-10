import SwiftUI

@main
struct RPTWatchApp: App {
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                StatsView()
                QuestsListView()
                WorkoutLogView()
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                session.activate()
            }
        }
    }
}
