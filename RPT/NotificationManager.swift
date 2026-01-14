import SwiftUI
import UserNotifications
import Combine

/// Production-ready notification manager
/// Handles all app notifications with proper permissions and scheduling
@MainActor
class NotificationManager: NSObject, ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            await MainActor.run {
                self.isAuthorized = granted
                if granted {
                    checkAuthorizationStatus()
                }
            }
        } catch {
            print("Notification authorization failed: \(error)")
            await MainActor.run {
                self.isAuthorized = false
            }
        }
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }
    
    // MARK: - Quest Notifications
    func scheduleDailyQuestReminder() {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Daily Quest Reminder"
        content.body = "Don't break your streak! Complete today's quests to level up."
        content.sound = .default
        content.badge = 1
        
        // Schedule for 9 AM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyQuestReminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule daily reminder: \(error)")
            }
        }
    }
    
    func scheduleStreakWarning() {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Streak Warning"
        content.body = "You have incomplete quests! Don't let your streak end."
        content.sound = .default
        content.badge = 1
        
        // Schedule for 8 PM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "streakWarning", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule streak warning: \(error)")
            }
        }
    }
    
    func scheduleLevelUpNotification(newLevel: Int) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🎉 Level Up!"
        content.body = "Congratulations! You've reached level \(newLevel)!"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "levelUp_\(newLevel)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule level up notification: \(error)")
            }
        }
    }
    
    func scheduleHealthGoalNotification(goalType: String, achieved: Bool) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        if achieved {
            content.title = "🎯 Goal Achieved!"
            content.body = "Great job! You've reached your \(goalType) goal today."
        } else {
            content.title = "💪 Almost There!"
            content.body = "You're close to your \(goalType) goal. Keep going!"
        }
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "healthGoal_\(goalType)_\(achieved ? "achieved" : "reminder")"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule health goal notification: \(error)")
            }
        }
    }
    
    // MARK: - Quest-specific notifications
    func scheduleQuestDeadlineReminder(for quest: Quest) {
        guard isAuthorized, let dueDate = quest.dueDate else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Quest Deadline"
        content.body = "'\(quest.title)' is due soon!"
        content.sound = .default
        
        // Remind 1 hour before due date
        let reminderDate = Calendar.current.date(byAdding: .hour, value: -1, to: dueDate) ?? dueDate
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate), repeats: false)
        
        let request = UNNotificationRequest(identifier: "questDeadline_\(quest.id)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule quest deadline: \(error)")
            }
        }
    }
    
    // MARK: - Management
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func cancelNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
    
    // MARK: - Badge Management
    func updateBadge(count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Failed to set badge count: \(error)")
            }
        }
    }
    
    func clearBadge() {
        updateBadge(count: 0)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .list, .badge, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        
        // Handle notification taps
        handleNotificationResponse(identifier: identifier)
        
        completionHandler()
    }
    
    private func handleNotificationResponse(identifier: String) {
        // Route user to appropriate screen based on notification type
        if identifier.contains("quest") {
            // Navigate to quests view
            NotificationCenter.default.post(name: .navigateToQuests, object: nil)
        } else if identifier.contains("streak") {
            // Navigate to home view with focus on incomplete quests
            NotificationCenter.default.post(name: .navigateToHome, object: nil)
        } else if identifier.contains("levelUp") {
            // Navigate to profile/stats view
            NotificationCenter.default.post(name: .navigateToProfile, object: nil)
        } else if identifier.contains("healthGoal") {
            // Navigate to health insights
            NotificationCenter.default.post(name: .navigateToHealth, object: nil)
        }
    }
}

// MARK: - Navigation Notifications
extension Notification.Name {
    static let navigateToQuests = Notification.Name("navigateToQuests")
    static let navigateToHome = Notification.Name("navigateToHome")
    static let navigateToProfile = Notification.Name("navigateToProfile")
    static let navigateToHealth = Notification.Name("navigateToHealth")
}

// MARK: - Production Configuration
extension NotificationManager {
    /// Configure all recurring notifications based on user preferences
    func configureRecurringNotifications() {
        guard isAuthorized else { return }
        
        // Cancel existing recurring notifications
        cancelRecurringNotifications()
        
        // Check user preferences and schedule accordingly
        if UserDefaults.standard.bool(forKey: "questReminders") {
            scheduleDailyQuestReminder()
        }
        
        if UserDefaults.standard.bool(forKey: "streakWarnings") {
            scheduleStreakWarning()
        }
    }
    
    private func cancelRecurringNotifications() {
        let recurringIdentifiers = ["dailyQuestReminder", "streakWarning"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: recurringIdentifiers)
    }
    
    /// Set up notification categories for interactive notifications
    func setupNotificationCategories() {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_QUEST",
            title: "Mark Complete",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_QUEST",
            title: "Remind Later",
            options: []
        )
        
        let questCategory = UNNotificationCategory(
            identifier: "QUEST_REMINDER",
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([questCategory])
    }
}

// MARK: - SwiftUI Integration Helper
struct NotificationPermissionView: View {
    @StateObject private var notificationManager = NotificationManager()
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: notificationManager.isAuthorized ? "bell.fill" : "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(notificationManager.isAuthorized ? .green : .orange)
            
            Text(notificationManager.isAuthorized ? "Notifications Enabled" : "Enable Notifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(notificationManager.isAuthorized ? 
                 "You'll receive reminders for quests and achievements." : 
                 "Stay motivated with timely reminders and celebrate your achievements.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if !notificationManager.isAuthorized {
                Button("Enable Notifications") {
                    Task {
                        await notificationManager.requestAuthorization()
                        if notificationManager.isAuthorized {
                            notificationManager.configureRecurringNotifications()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open Settings") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            notificationManager.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showingSettings) {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                SafariView(url: settingsUrl)
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}