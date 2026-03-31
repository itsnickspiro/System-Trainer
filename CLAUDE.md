# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

System Trainer (RPT) is a gamified iOS fitness app built with SwiftUI and SwiftData. It turns workouts, nutrition tracking, and daily habits into an RPG-style progression system with quests, XP, levels, streaks, achievements, leaderboards, and an in-app store/inventory.

## Build & Run

- **Open in Xcode:** `RPT.xcodeproj` — no CocoaPods or SPM dependencies to resolve
- **Build:** Cmd+B in Xcode, or `xcodebuild -project RPT.xcodeproj -scheme RPT -sdk iphonesimulator`
- **Required Xcode Build Settings (User-Defined):**
  - `SUPABASE_ANON_KEY` — from Supabase dashboard (Settings → API → anon public)
  - `APP_SECRET` — shared secret matching `RPT_APP_SECRET` in Supabase Vault
  - These flow into Info.plist and are read by `Secrets.swift` at runtime
- **CloudKit:** Uses private CloudKit database (`iCloud.com.SpiroTechnologies.RPT`). Falls back to local-only SwiftData store in Simulator or when entitlement is missing.
- **No test suite currently exists.**

## Supabase Backend

Edge Functions in `supabase/functions/` proxy all third-party API calls — no API keys are ever sent to the client. Each proxy function follows the same pattern: validate `x-app-secret` header, fetch the real key from Supabase Vault, call the external API, return the result.

**Proxy functions:** `exercises-proxy`, `nutrition-proxy`, `foods-proxy`, `recipe-proxy`, `weather-proxy`, `anime-plans-proxy`, `quest-templates-proxy`, `remote-config-proxy`, `usda-proxy`

**Deploy:** `supabase functions deploy` (all) or `supabase functions deploy <name>`

**Local dev:** `supabase functions serve --env-file .env.local`

**Database scripts** (`supabase/scripts/`): Python scripts for seeding exercises, foods, and anime plans. See `supabase/DEPLOY.md` for full setup instructions.

## Architecture

### Data Layer
- **SwiftData** with CloudKit sync — all `@Model` properties must be optional or have defaults
- **`Models.swift`** — all SwiftData model definitions: `Profile`, `Quest`, `FoodItem`, `FoodEntry`, `CustomMeal`, `ExerciseItem`, `WorkoutSession`, `ExerciseSet`, `ActiveRoutine`, `PersonalRecord`, `PatrolRoute`, `InventoryItem`, `CustomWorkoutPlan`, `Achievement`, `BodyMeasurement`, `PlannedMeal`
- **`DataManager.swift`** — singleton (`DataManager.shared`) that owns ModelContext reference and manages quest generation, XP/level calculations, streak tracking, and daily resets

### Service Singletons (all `ObservableObject`, refreshed in sequence at launch)
Launch order matters — defined in `RPTApp.swift`:
1. `LeaderboardService` (CloudKit user ID resolution)
2. `RemoteConfigService` (feature flags)
3. `PlayerProfileService` (cloud profile)
4. `QuestTemplateService` → `AchievementsService` → `AnnouncementsService` → `StoreService` → `EventsService` → `AnimeWorkoutPlanService` → `LeaderboardService` (rankings) → `AvatarService`

### API Layer
Swift API files call Supabase Edge Functions (never external APIs directly):
- `ExercisesAPI.swift` — exercise search
- `NutritionAPI.swift` — nutrition data lookup
- `RecipeAPI.swift` — recipe search
- `WeatherstackAPI.swift` — weather for outdoor workouts
- `FoodDatabaseService.swift` — food database queries

### Navigation
`ContentView.swift` — TabView with: Home, Quests, Diet, Training, Leaderboard (feature-flagged). Deep links via `rpt://` and `systemtrainer://` URL schemes.

### Key Patterns
- **Feature flags** via `RemoteConfigService` — gates like `feature_coach_enabled`, `feature_leaderboard_enabled`, `feature_anime_plans_enabled`
- **`@AppStorage`** for user preferences (color scheme, notification toggles, gameplay settings)
- **`HealthManager.swift`** — HealthKit integration for steps, heart rate, calories, sleep
- **`QuestManager.swift`** — procedural quest generation with progressive overload based on player demographics
- **`AchievementManager.swift`** — achievement tracking and unlock logic

## Conventions

- All secrets go through Supabase Edge Function proxies, never in client code
- SwiftData models: every property needs a default value (CloudKit requirement)
- Services use singleton pattern with `shared` static property
- UI defaults to dark mode (`@AppStorage("colorScheme")` defaults to `"dark"`)
