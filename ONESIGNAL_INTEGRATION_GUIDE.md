# OneSignal Push Notifications Integration Guide

## Overview
OneSignal provides push notifications for quest reminders, streak maintenance, level-up celebrations, and more.

Your OneSignal App ID is already in Info.plist: `os_v2_app_h47lav52dnax5kwltgzeapdgqoywvs2leegupwudcrkjsrzmxvnqwygrda754svtnkgcojt7wjlv7gdt6mividsn6icnj5cudjgpn5q`

## Step 1: Add OneSignal SDK via Swift Package Manager

1. Open Xcode project
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/OneSignal/OneSignal-XCFramework`
4. Select **Dependency Rule**: Up to Next Major Version `5.0.0`
5. Click **Add Package**
6. Select both targets:
   - ✅ OneSignalFramework
   - ✅ OneSignalExtension (for rich notifications)
7. Click **Add Package**

## Step 2: Configure App Capabilities

1. Select your project in Xcode
2. Select **RPT** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add:
   - ✅ Push Notifications
   - ✅ Background Modes
     - Enable: Remote notifications
     - Enable: Background fetch

## Step 3: Update RPTApp.swift

Replace the current RPTApp.swift initialization with:

```swift
import SwiftUI
import SwiftData
import FirebaseCore
import OneSignalFramework

@main
struct RPTApp: App {
    init() {
        // Firebase Configuration
        FirebaseApp.configure()

        // OneSignal Configuration
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        OneSignal.initialize(
            Secrets.oneSignalAPIKey,
            withLaunchOptions: nil
        )

        // Request notification permissions
        OneSignal.Notifications.requestPermission({ accepted in
            print("User accepted notifications: \(accepted)")
        }, fallbackToSettings: true)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Quest.self,
            Profile.self,
            FoodItem.self,
            FoodEntry.self,
            CustomMeal.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            if let inMemoryContainer = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ) {
                return inMemoryContainer
            }
            fatalError("Could not create even an in-memory ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if Auth.auth().currentUser != nil {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
```

## Step 4: Update Info.plist

The OneSignal_API key is already added. No additional plist changes needed.

## Step 5: Uncomment NotificationManager.swift

The `NotificationManager.swift` file has been created but is currently using local notifications only. Once OneSignal SDK is installed, it will automatically use OneSignal for remote notifications.

## Step 6: Test Notifications

### Test in Simulator:
1. Run app in simulator
2. Grant notification permissions when prompted
3. Check console for OneSignal initialization logs
4. Go to OneSignal dashboard
5. Send test notification to All Users

### Test on Device:
1. Connect physical iOS device
2. Update signing team in Xcode
3. Enable Push Notifications in Signing & Capabilities
4. Run on device
5. Grant notification permissions
6. Send test notification from OneSignal dashboard

## Notification Types to Implement

### 1. Quest Reminders
- **Trigger**: Daily at 9 AM, 12 PM, 6 PM
- **Message**: "You have 3 quests remaining! Complete them to maintain your streak 🔥"
- **Deep Link**: Open QuestsView

### 2. Streak Warnings
- **Trigger**: 9 PM if no quests completed
- **Message**: "Don't lose your {streak}-day streak! Complete a quest now! 🎯"
- **Deep Link**: Open QuestsView

### 3. Level Up Celebration
- **Trigger**: When user levels up
- **Message**: "Level Up! 🎉 You reached Level {level}! Tap to see your rewards."
- **Deep Link**: Open ProfileView

### 4. Daily Reset
- **Trigger**: Midnight (00:00)
- **Message**: "New day, new quests! Your daily challenges are ready 💪"
- **Deep Link**: Open QuestsView

### 5. Leaderboard Update
- **Trigger**: Weekly on Sunday at 6 PM
- **Message**: "You're #{rank} this week! Can you climb higher? 🏆"
- **Deep Link**: Open LeaderboardView

### 6. Inactive User Re-engagement
- **Trigger**: 3 days of inactivity
- **Message**: "We miss you! Your fitness journey awaits. Come back and level up! 🌟"
- **Deep Link**: Open HomeView

## OneSignal Dashboard Configuration

### Create Segments:
1. **Active Users**: Last session < 24h
2. **At Risk**: Last session 24-72h
3. **Churned**: Last session > 7 days
4. **Streak Holders**: Users with currentStreak > 0
5. **Beginners**: Level 1-5
6. **Advanced**: Level 20+

### Set Up Automated Messages:
1. Go to **Messages → Automated**
2. Create automation for each notification type
3. Set triggers and segments
4. Configure timing and frequency caps

## Deep Linking

Add URL scheme to Info.plist (already configured):
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>rptfitness</string>
        </array>
    </dict>
</array>
```

Handle deep links in NotificationManager:
- `rptfitness://quests` → QuestsView
- `rptfitness://home` → HomeView
- `rptfitness://leaderboard` → LeaderboardView
- `rptfitness://profile` → ProfileView

## Testing Checklist

- [ ] OneSignal SDK installed via SPM
- [ ] App compiles without errors
- [ ] Push notification capability added
- [ ] Notification permissions requested on launch
- [ ] Device registered in OneSignal dashboard
- [ ] Test notification received in app
- [ ] Deep link navigation works
- [ ] Badge count updates
- [ ] Notification sound plays
- [ ] Rich notifications display correctly

## Best Practices

1. **Respect User Preferences**
   - Don't spam notifications
   - Provide in-app settings to customize frequency
   - Honor Do Not Disturb times

2. **Personalize Messages**
   - Use user's name from profile
   - Reference their current streak
   - Mention specific incomplete quests

3. **Optimize Timing**
   - Send quest reminders during workout hours
   - Avoid late-night notifications
   - Respect time zones

4. **Track Engagement**
   - Monitor open rates
   - A/B test message copy
   - Adjust timing based on data

## Cost Estimate

- **Free Tier**: 10,000 subscribers
- **Growth Plan**: $9/month for 10,000+ subscribers
- **Professional**: $99/month for advanced features

For beta testing, the free tier is more than sufficient.

## Next Steps After Integration

1. Set up first automated campaign (daily quest reminder)
2. Create user segments based on activity level
3. Test all notification types
4. Monitor open rates and adjust messaging
5. Implement in-app notification settings
