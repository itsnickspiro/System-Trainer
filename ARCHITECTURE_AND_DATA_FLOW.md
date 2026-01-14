# RPT Application - Complete Architecture & Data Flow Guide

## 🗂️ PROJECT STRUCTURE (Consolidated & Organized)

### ✅ CORE FILES (Keep - Single Source of Truth)

#### **Models.swift** - ALL Data Models
**What's stored here:**
- `Profile` - User profile, XP, level, RPG stats, HealthKit data
- `Quest` - Daily/Weekly/Punishment quests
- `FoodItem` - Food database entries
- `FoodEntry` - User's logged meals
- `CustomMeal` - User-created meal templates
- `Recipe` - Recipe data from API
- `FoodCategory` - Food categorization enum
- `FoodUnit` - Measurement units enum
- `QuestType` - Quest categorization enum
- `StatInfluence` - RPG stat influences enum

**Storage:** SwiftData (local SQLite database)
**Sync:** Firebase Firestore (cloud backup)

---

#### **Components.swift** - ALL UI Components
**What's defined here:**
- `XPBar` - Experience progress bar
- `StreakBadge` - Daily streak indicator
- `HardcoreTimer` - Deadline countdown
- `GlassCard` - Glassmorphism card style
- `CurvedStatRing` - Circular stat indicator (ONLY DEFINITION)
- `RPGStatsBar` - Main stats display (ONLY DEFINITION)
- `StatDetailView` - Individual stat detail (ONLY DEFINITION)
- `QuestRow` - Quest list item (ONLY DEFINITION)
- `StatRow` - Simple stat row
- `WeekScroller` - Week navigation component

**Note:** This is the ONLY place these components should be defined!

---

#### **FirebaseManager.swift** - Cloud Sync Service
**Responsibility:**
- User authentication (anonymous/email)
- Profile synchronization to Firestore
- Quest synchronization
- Analytics logging
- Real-time sync state management

**What goes to Firebase:**
```
profiles/{userId}/
  ├── id, name, xp, level
  ├── currentStreak, bestStreak
  ├── health, energy, strength, endurance, focus, discipline
  ├── waterIntake, sleepHours
  └── HealthKit metrics

quests/{questId}/
  ├── userId, title, details, type
  ├── xpReward, isCompleted, completedAt
  └── dateTag, createdAt

analytics/{eventId}/
  ├── userId, eventName
  ├── timestamp
  └── parameters
```

**Configuration:**
- Requires Firebase iOS SDK
- GoogleService-Info.plist must be added to project
- Initialize in RPTApp.swift with `FirebaseApp.configure()`

---

### 📡 API SERVICE FILES (Keep - External Data)

#### **ExercisesAPI.swift**
**Purpose:** Fetch exercise database from API Ninjas
**Endpoint:** `https://api.api-ninjas.com/v1/exercises`
**API Key:** `API_NINJAS_KEY` in Info.plist
**Returns:** `Exercise` struct with name, type, muscle, equipment, difficulty, instructions
**Used in:** WorkoutView, APITestView

---

#### **NutritionAPI.swift**
**Purpose:** Look up nutrition facts by food name
**Endpoint:** `https://api.api-ninjas.com/v1/nutrition`
**API Key:** `API_NINJAS_KEY` in Info.plist
**Returns:** `NutritionItem` with calories, macros, servings
**Used in:** DietView, food logging

---

#### **RecipeAPI.swift**
**Purpose:** Search for recipes
**Endpoint:** `https://api.api-ninjas.com/v1/recipe`
**API Key:** `API_NINJAS_KEY` in Info.plist
**Returns:** `Recipe` struct (defined in Models.swift)
**Used in:** DietView meal planning

---

#### **FoodDatabaseService.swift**
**Purpose:** Barcode scanning and food lookup
**Status:** 🟡 Currently uses MOCK data
**To Replace With:** Open Food Facts API
**Endpoint:** `https://world.openfoodfacts.org/api/v0/product/{barcode}.json`
**API Key:** None required (free)
**Returns:** `FoodItem` (SwiftData model)
**Used in:** DietView barcode scanner

**Current Implementation:**
```swift
// Lines 16-46: Mock data generation
// Replace with:
func searchFoodByBarcode(_ barcode: String) async throws -> FoodItem? {
    let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json")!
    let (data, _) = try await URLSession.shared.data(from: url)
    // Parse Open Food Facts response
    // Convert to FoodItem
}
```

---

#### **AIClient.swift**
**Purpose:** ChatGPT integration for AI coach
**Endpoint:** `https://api.openai.com/v1/chat/completions`
**API Key:** `AIAPIKey` in Info.plist
**Returns:** `ChatResponse` with AI-generated advice
**Used in:** CoachView

---

#### **Secrets.swift**
**Purpose:** Centralized API key access
**Reads from:** Info.plist
**Properties:**
- `aiAPIKey` - OpenAI API key
- `apiNinjasKey` - API Ninjas key

---

### 🗑️ FILES TO DELETE (Duplicates - Cause Build Errors)

**DELETE THESE FROM XCODE PROJECT:**

1. ❌ **FirebaseManager 2.swift**
   - Duplicate of FirebaseManager.swift
   - Also contains duplicate Recipe, RecipeAPI definitions

2. ❌ **APITestView 2.swift**
   - Duplicate of APITestView.swift

3. ❌ **BarcodeScannerViewController.swift**
   - Conflicts with BarcodeScannerView.swift

4. ❌ **StatDetailView.swift** (standalone file)
   - Duplicate - keep definition in Components.swift only

5. ❌ **QuestRow.swift** (standalone file)
   - Duplicate - keep definition in Components.swift only

**How to delete:**
```
Right-click in Xcode → Delete → "Move to Trash" (not just Remove Reference)
```

---

## 💾 DATA FLOW & STORAGE

### LOCAL STORAGE (SwiftData)
**Location:** Device's local SQLite database
**Managed by:** `@Environment(\.modelContext)`

**What's stored locally:**
```
Profile (Single instance per user)
  ├── User stats, XP, level
  ├── RPG attributes
  ├── HealthKit metrics
  └── Preferences

Quests (Multiple instances)
  ├── Daily/Weekly/Punishment quests
  ├── Completion status
  └── Associated dateTag

FoodItems (Database)
  ├── Food entries from API
  ├── Custom user-created foods
  └── Barcode mappings

FoodEntries (User log)
  ├── Date, time, quantity
  ├── Reference to FoodItem
  └── Meal type (breakfast/lunch/dinner)

CustomMeals (User templates)
  ├── Meal name
  └── Array of FoodEntries
```

**Access Pattern:**
```swift
@Environment(\.modelContext) private var modelContext

// Query
let descriptor = FetchDescriptor<Profile>()
let profiles = try modelContext.fetch(descriptor)

// Insert
let newQuest = Quest(title: "Morning Run", type: .daily)
modelContext.insert(newQuest)

// Save
try modelContext.save()
```

---

### CLOUD STORAGE (Firebase Firestore)
**Location:** Google Cloud Firebase
**Managed by:** `FirebaseManager.shared`

**What syncs to cloud:**
- Profile data (for cross-device sync)
- Quest completion history
- Analytics events
- User preferences

**What DOESN'T sync:**
- FoodItems (too large, use local cache)
- FoodEntries (unless explicitly synced)
- API responses (cache locally)

**Sync Pattern:**
```swift
// Sync profile to cloud
try await FirebaseManager.shared.syncProfile(profile)

// Fetch from cloud
let cloudData = try await FirebaseManager.shared.fetchProfile()

// Delete from cloud
try await FirebaseManager.shared.deleteQuest(questId: quest.id.uuidString)
```

---

### API DATA (Ephemeral)
**Storage:** Memory only (or short-term cache)
**Source:** External APIs

**Exercises:**
- Fetched on-demand
- Cache in memory for session
- Don't persist to SwiftData

**Nutrition:**
- Look up as needed
- Convert to FoodItem for logging
- FoodItem is persisted

**Recipes:**
- Search results cached temporarily
- User can "save" recipe (TODO: implement in FoodItem or CustomMeal)

---

## 🔑 CONFIGURATION REQUIREMENTS

### Info.plist Keys
Add these to your **Info.plist** file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing keys... -->
    
    <!-- API Ninjas Key (Required) -->
    <key>API_NINJAS_KEY</key>
    <string>YOUR_API_NINJAS_KEY_HERE</string>
    
    <!-- OpenAI Key (Optional - for AI Coach) -->
    <key>AIAPIKey</key>
    <string>YOUR_OPENAI_KEY_HERE</string>
</dict>
</plist>
```

**Get API Keys:**
- API Ninjas: https://api-ninjas.com (Free tier: 50,000 requests/month)
- OpenAI: https://platform.openai.com/api-keys (Paid, ~$0.002 per request)

---

### Firebase Configuration
**Required files:**
1. `GoogleService-Info.plist` - Download from Firebase Console
2. Firebase iOS SDK - Added via Swift Package Manager

**Setup steps:**
1. Create project at https://console.firebase.google.com
2. Add iOS app to Firebase project
3. Download `GoogleService-Info.plist`
4. Drag into Xcode project (add to target)
5. Initialize in `RPTApp.swift`:

```swift
import Firebase

@main
struct RPTApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(...)
        }
    }
}
```

---

## 📊 DATA OWNERSHIP & PRIVACY

### User Data Location

**Completely Private (Never leaves device):**
- HealthKit data (Apple's privacy requirement)
- Raw sensor data
- Biometric information

**Local with Optional Cloud Sync:**
- Profile stats (XP, level, streaks)
- Quest history
- RPG attribute values
- Food logging history

**Always from External APIs:**
- Exercise database
- Nutrition facts
- Recipe database

**User Control:**
- Can disable cloud sync (data stays local only)
- Can clear local data
- Can export data
- Can delete cloud data

---

## 🏗️ ARCHITECTURE SUMMARY

```
┌─────────────────────────────────────────────────┐
│                   ContentView                    │
│  (Main app shell with TabView & navigation)     │
└─────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┬───────────────┐
        │               │               │               │
   HomeView        QuestsView      DietView      WorkoutView
        │               │               │               │
        ├─ Profile      ├─ Quest list  ├─ Food log    ├─ Exercise list
        ├─ Stats        ├─ Add/Edit    ├─ Barcode     ├─ Workout plans
        └─ HealthKit    └─ Complete    └─ Nutrition   └─ Progress

                        │
        ┌───────────────┼───────────────┐
        │               │               │
   DataManager   FirebaseManager   API Services
        │               │               │
   SwiftData      Firestore      ExercisesAPI
   (Local DB)   (Cloud Sync)   NutritionAPI
                               RecipeAPI
                               AIClient
```

---

## ✅ FINAL CHECKLIST

**Before building:**
- [ ] Delete 5 duplicate files from Xcode
- [ ] Add API keys to Info.plist
- [ ] Add GoogleService-Info.plist to project
- [ ] Clean build folder (⌘+Shift+K)
- [ ] Build project (⌘+B)

**After successful build:**
- [ ] Test API connections in Debug build (long press for APITestView)
- [ ] Verify Firebase sync
- [ ] Test barcode scanning
- [ ] Check HealthKit permissions

**Future improvements:**
- [ ] Replace FoodDatabaseService mock with Open Food Facts
- [ ] Add offline caching for API responses
- [ ] Implement recipe saving to CustomMeal
- [ ] Add image upload for custom foods

---

## 📝 KEY LOCATIONS FOR CUSTOMIZATION

**Want to change XP rewards?**
→ `Quest.init()` in Models.swift (line ~580)

**Want to modify RPG stat calculations?**
→ `Profile.calculateOverallHealthScore()` in Models.swift

**Want to adjust UI colors/theme?**
→ `Components.swift` color definitions
→ `ContentView.setupTabBarAppearance()` for tab bar

**Want to change API endpoints?**
→ Individual API files (ExercisesAPI.swift, etc.)

**Want to add new quest types?**
→ `QuestType` enum in Models.swift
→ Update `QuestRow` in Components.swift

---

This is your complete, consolidated architecture. Everything has its place, and duplicates are marked for deletion!
