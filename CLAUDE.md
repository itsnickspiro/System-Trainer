# CLAUDE.md

Guidance for Claude Code working in this repository.

## What This Is

System Trainer (RPT) is a gamified iOS fitness app — SwiftUI + SwiftData + CloudKit + a Supabase backend. Workouts, nutrition, and daily habits become an RPG progression system: quests, XP, levels, streaks, achievements, leaderboards, store, inventory, anime-themed workout plans.

- Bundle ID: `SpiroTechnologies.RPT`
- iCloud container: `iCloud.com.SpiroTechnologies.RPT`
- Team ID: `WRVY4Q5HA5`
- Current version: 2.8.19 (build 1) — see `RPT.xcodeproj/project.pbxproj` for the source of truth

## Quick Start

```bash
# Build for simulator
xcodebuild -project RPT.xcodeproj -scheme RPT -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Open in Xcode
open RPT.xcodeproj
```

No CocoaPods, no SPM. Everything compiles from the .xcodeproj as-is.

## Required Build Settings

Two user-defined build settings flow into `Secrets.xcconfig` → Info.plist → `Secrets.swift` at runtime:

- `SUPABASE_ANON_KEY` — from Supabase dashboard → Settings → API → anon public
- `APP_SECRET` — must match `RPT_APP_SECRET` in Supabase Vault (validates the `x-app-secret` header on every Edge Function call)

In Xcode Cloud these are set as Secret Environment Variables on the workflow; `ci_scripts/ci_post_clone.sh` writes them into `Secrets.xcconfig` before the build runs.

## Claude's sandbox on the Mac Mini

Nick has explicitly granted broad access so Claude can develop, test, and ship iOS builds autonomously from this Mac Mini. The granted capabilities are:

- **Computer-use MCP** (`mcp__computer-use__*`) — Claude can screenshot, click, type, scroll, and drive any macOS app after a one-call `request_access`. Simulator is tier "full" (can drive it completely); Xcode and Terminal are tier "click" (visible + clickable, but typing goes through the Bash/Edit tools instead). Used primarily for visual verification of onboarding UI changes on the simulator before committing.
- **Xcode CLI** — `xcodebuild`, `xcrun simctl`, `xcrun devicectl`, `xcrun altool`, `codesign`, `security` are all callable via Bash. Signing identity `Apple Development: Nicholas Spiro (UL35EW4SQG)` is installed in the keychain.
- **Tethered iPhone** (when connected) — `xcrun devicectl` installs Debug builds to the real device for testing anything the simulator can't reproduce (SIWA with real Apple ID, HealthKit permission sheet, CloudKit sync, real-device gesture/hit-test differences).
- **App Store Connect API** — P8 key at `~/.appstoreconnect/private_keys/AuthKey_2Y773SS5ZG.p8` (mode 600). Scope: "App Manager" — enough to list and expire TestFlight builds, not enough to touch users or billing. Helper script at `tools/appstoreconnect.js`.

Destructive/shared actions (git push, App Store Connect uploads, TestFlight build expiration, touching developer.apple.com, running new `brew install` / `npm i`) still require Nick's explicit confirmation every time. The permissions grant broad capability, not unlimited authority.

## Visual verification on the simulator (required before every UI commit)

The Mac Mini is set up so Claude can drive the Simulator directly via computer-use and verify UI changes before committing. This is the **default workflow for any UI change** — don't ship onboarding/layout/animation fixes without running them on the simulator first.

```bash
# Build + install + launch in one pass
xcodebuild -project RPT.xcodeproj -scheme RPT -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=FF3C9C19-B01C-4ADD-A9DF-735D7FC2D7D2' \
  -configuration Debug build
APP="/Users/nickspiro/Library/Developer/Xcode/DerivedData/RPT-aurjojbqmomvovezermqipqlcugz/Build/Products/Debug-iphonesimulator/RPT.app"
xcrun simctl uninstall booted SpiroTechnologies.RPT
xcrun simctl install booted "$APP"
xcrun simctl launch booted SpiroTechnologies.RPT
```

Then grant `Simulator` via `mcp__computer-use__request_access` and use click/type/screenshot to drive the app. The "Skip SIWA (DEBUG)" button in `BootStepView` (stripped from Release via `#if DEBUG`) bypasses the Apple ID gate that would otherwise block automated testing on the simulator. Optional launch argument `-onboardingDebugAutofill 1` pre-fills name/age/height/weight/class.

Accessibility identifiers to find UI elements:
- `siwa_button` / `debug_skip_siwa` — welcome screen entry
- `onboarding_back_button` / `onboarding_continue_button` / `onboarding_skip_button` — nav chrome
- `onboarding_step_counter` — "N/11" progress text
- `name_text_field` — step 1 name input

**Simulator limitations — test on the tethered iPhone for these:** SIWA with real Apple ID, HealthKit permissions, CloudKit sync, and subtle gesture/hit-test differences between simulator and device.

## Version policy

Every bug fix bumps the marketing version by one patch AND resets `CURRENT_PROJECT_VERSION` to 1. Example: 2.8.11 build 36 → 2.8.12 build 1 → 2.8.13 build 1. Avoid "same version, build N+1" stacking — it clutters App Store Connect history.

```bash
# Bumping 2.8.12 → 2.8.13 (and resetting build to 1):
sed -i '' 's/MARKETING_VERSION = 2\.8\.12;/MARKETING_VERSION = 2.8.13;/g; \
          s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = 1;/g' \
  RPT.xcodeproj/project.pbxproj
```

Infrastructure-only changes (testing hooks, docs, CLAUDE.md) can skip the marketing bump and just increment the build number.

## Release Pipeline (manual CLI)

Used for hot-fix builds when bypassing Xcode Cloud. Bump versions in `RPT.xcodeproj/project.pbxproj` first (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` — there are 6 occurrences of each, sed-replace them all).

```bash
rm -rf build/RPT.xcarchive build/export
xcodebuild -project RPT.xcodeproj -scheme RPT -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/RPT.xcarchive clean archive
xcodebuild -exportArchive -archivePath build/RPT.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export

# Auto-expire intermediate duplicates of the SAME marketing version.
# Safe to call immediately after upload — it only touches builds of
# the version you pass in and always keeps the newest one. Replace
# 2.8.12 with whatever MARKETING_VERSION you just bumped to.
node tools/appstoreconnect.js expire-intermediates 2.8.12
```

`ExportOptions.plist` is configured for App Store Connect upload (`destination = upload`), so the export step both packages and uploads in one pass. Builds usually finish processing in TestFlight within 5–15 minutes.

The `expire-intermediates` step is **required** on every release, not optional. Xcode Cloud auto-builds on every push to `main` (including docs-only commits), so every git push creates a shadow duplicate TestFlight build of whatever marketing version is current. The auto-cleanup step hides those duplicates from testers. The upstream fix is narrowing Xcode Cloud's trigger in Product → Xcode Cloud → Manage Workflows → Start Conditions → File/Folder Changes to something like `RPT/**/*.swift`, `RPT.xcodeproj/**`, but that's a GUI-only change Claude can't make from the CLI.

## Verifying a Signed Archive

The ground-truth check for whether HealthKit / CloudKit / SIWA / push entitlements actually shipped with the binary — much faster than reading `RPT/RPT.entitlements`:

```bash
codesign -d --entitlements - build/RPT.xcarchive/Products/Applications/RPT.app
security cms -D -i build/RPT.xcarchive/Products/Applications/RPT.app/embedded.mobileprovision
```

When debugging "permission denied" / "feature not working in TestFlight" reports, verify entitlements before assuming a code bug.

## Architecture

### Data layer
- **SwiftData with CloudKit sync.** All `@Model` properties must have defaults (CloudKit requirement). Models live in `RPT/Models.swift`.
- **`DataManager.swift`** — `DataManager.shared` singleton owning the `ModelContext`. Manages quest generation, XP/level math, streak tracking, and the Midnight Reset.
- The model schema is declared in `RPTApp.swift` inside `sharedModelContainer`. **Anything declared `@Model` but missing from this `Schema([...])` array silently fails to persist.** Always update both places together.

### Service singletons
All `ObservableObject`, all `@MainActor`, all `.shared`. Refreshed in a fixed sequence at launch (defined in `RPTApp.swift` `.task` modifier on `RootContainerView`):

1. `DataManager.configure(with:)` — must run before any service that touches Profile data, including the SIWA recovery flow
2. `LeaderboardService.resolveCloudKitUserIDIfNeeded()` (10s timeout, non-fatal)
3. (Notification permission, only if onboarding complete)
4. `RemoteConfigService.refresh()`
5. `PlayerProfileService.refresh()`
6. `QuestTemplateService` → `AchievementsService` → `AnnouncementsService` → `StoreService` → `EventsService` → `AnimeWorkoutPlanService`
7. `LeaderboardService.refresh()` (rankings)
8. `AvatarService.refresh()`

**Order matters.** Anything that needs the CloudKit user ID must run after step 2.

### API layer
Swift API files NEVER call third-party APIs directly. Everything goes through Supabase Edge Function proxies. Each proxy validates the `x-app-secret` header, fetches the real third-party key from Supabase Vault, and returns the result. See `RPT/ExercisesAPI.swift`, `NutritionAPI.swift`, `RecipeAPI.swift`, `WeatherstackAPI.swift`, `FoodDatabaseService.swift`.

### Navigation
`RPT/ContentView.swift` — `TabView` with Home / Quests / Diet / Training / Leaderboard (the leaderboard tab is feature-flagged via `RemoteConfigService`). Deep links via the `rpt://` and `systemtrainer://` URL schemes; handlers live in `RPTApp.swift handleDeepLink(_:)`.

### Onboarding
`RPT/OnboardingView.swift` — single file, ~2200 lines, all step views inlined. Driven by an `Int currentStep` state. The full flow:

| Step | View | Notes |
|---|---|---|
| 0 | `BootStepView` | SIWA welcome — only path into the app for new installs |
| 1 | `NameStepView` | |
| 2 | `GenderStepView` | |
| 3 | `BodyStatsStepView` | Age / height / weight. Gates Continue. |
| 4 | `GoalStepView` | |
| 5 | `ClassSelectionStepView` | Must pick non-`.unselected`. Gates Continue. |
| 6 | `DietPreferenceStepView` | `.none` is a valid answer ("no restrictions") |
| 7 | `WorkoutPlanStepView` | Pick a pre-built anime plan. **No custom-plan option** — see "Removed in 2.8.11" |
| 8 | *(retired)* | Permanently skipped by `advanceFrom`/`previousStep` |
| 9 | `AvatarPickerStepView` | Filtered by player gender via key suffix `_m`/`_f` |
| 10 | `HealthStepView` | **Skippable** — HealthKit can fail for reasons the app can't fix |
| 11 | `NotificationsStepView` | Skippable |
| 12 | `ReadyStepView` | |

`displayedStep` remaps `currentStep` for the progress bar so it fills smoothly across the retired position 8.

### Backend (Supabase)
Edge Functions in `supabase/functions/` (deployed via `supabase functions deploy <name>`):

- **Proxies** (third-party API gateways): `exercises-proxy`, `nutrition-proxy`, `foods-proxy`, `recipe-proxy`, `weather-proxy`, `anime-plans-proxy`, `quest-templates-proxy`, `remote-config-proxy`, `usda-proxy`
- **App services**: `player-proxy` (profile / SIWA / delete-account / revoke), `avatars-proxy`, `leaderboard-proxy`, `notifications-proxy`
- **Auth (2.9.0 in progress)**: `_shared/auth.ts`, App Attest verification, JWT minting

Database scripts in `supabase/scripts/` (Python) seed exercises, foods, anime plans. See `supabase/DEPLOY.md`.

## Supabase ad-hoc SQL workflow

`supabase db push` does **NOT** work in this repo — the remote DB has 50+ migrations created via the dashboard before migration tracking existed, and the CLI refuses to push until the local history matches. For one-off seeds, schema inspection, or manual migrations, use `db query` instead:

```bash
brew install supabase/tap/supabase     # do NOT use npm -g, Supabase blocks it
export SUPABASE_ACCESS_TOKEN=sbp_xxx   # personal access token from dashboard
supabase db query --linked -f supabase/migrations/<file>.sql
supabase db query --linked "SELECT key, name FROM avatars WHERE key LIKE 'avatar_%' ORDER BY sort_order"
```

Project ref: `erghbsnxtsbnmfuycnyb` (System-Trainer). The CLI is already linked in `supabase/config.toml`.

## Conventions & gotchas

### SwiftData + CloudKit rules
- Every `@Model` property must have a default value or be optional. CloudKit requires this.
- **Never `@Attribute(.unique)`** on a CloudKit-synced model. CloudKit enforces uniqueness via record names and rejects unique constraints. The store load throws `NSCocoaError 134060` and the app fatals at the `try!` in `RPTApp.swift` (`sharedModelContainer`). This crashed launch in 2.8.10.
- The 3-tier `ModelContainer` fallback (CloudKit → local → in-memory) only catches **environment** failures — every tier shares the same `Schema`, so a schema-illegal model fails all three tiers identically. If you see all three fall through, the bug is in the schema, not the environment.

### Xcode project structure
- `RPT/` is a `PBXFileSystemSynchronizedRootGroup` — Xcode auto-discovers and compiles every file in the folder for all targets. **Never add manual PBXBuildFile / PBXFileReference entries** for files inside `RPT/`; doing so creates duplicates and triggers "Multiple commands produce .stringsdata" build errors.
- `import Combine` is required in any file that uses `@Published`. Without it `ObservableObject` conformance fails with a misleading "does not conform" error. Do NOT switch to `@Observable` — the rest of the codebase is Combine-based and mixing frameworks causes cascading import errors.

### File-backed JSON managers
- `ActivityLogManager` and `NotificationInboxManager` use a lightweight JSON-file pattern: singleton, `@Published` array, read/write to `Documents/`, capped entry count, no SwiftData/CloudKit. Use this pattern for local-only data that doesn't need sync.

### Service patterns
- Singleton pattern with a `shared` static property. All services are `@MainActor`.
- Services use `do/catch` around their network calls and set `lastError` / `lastErrorMessage` published properties. **Catch blocks should populate user-visible state**, not just `print()` — TestFlight users can't read console logs. The HealthManager catch was print-only for months and silently masked a real bug.

### Avatars are two-part
Adding an avatar requires BOTH:
1. Bundling the PNG in `RPT/Assets.xcassets/Avatars/{Male,Female}/<key>.imageset/` with a `Contents.json` that names it
2. Inserting a row in the Supabase `avatars` table with the matching `key`

`AvatarPickerView` loads via `UIImage(named: avatar.key)` with no integrity check — reusing an existing key silently swaps the artwork on the existing row. Always run `SELECT key FROM avatars WHERE key IN (...)` before bundling new images.

The `category` column has a CHECK constraint:
`default | warrior | mage | rogue | tank | anime | seasonal | premium | event` — `free` is NOT a category, it's an `unlock_type`.

The `Avatars/`, `Avatars/Male/`, and `Avatars/Female/` folders each have a `Contents.json` with `provides-namespace: false` so the imageset name is the bare lookup key (verified via `xcrun --sdk iphonesimulator assetutil --info <Assets.car>`).

### Username uniqueness
- Case-insensitive unique index on `player_profiles.display_name` — enforced at the DB level.
- `leaderboard-proxy` has a `check_username` action for debounced availability checks during onboarding.
- Username changes tracked client-side via `Profile.usernameChangesUsed` (SwiftData) — 1 free, then 5,000 GP per change.

### File location quirks
- `AvatarPickerView.swift` and `AvatarService.swift` are at the **repo root**, not under `RPT/`. They compile fine but sit outside the expected directory.

### Notification permission timing
- In RPTApp.swift `.task`, capture `wasOnboardingCompleteAtLaunch` from UserDefaults BEFORE any `await`. The .task chain takes 10+ seconds; if onboarding completes mid-chain, reading `hasCompletedOnboarding` after an await would fire the notification dialog over the Home screen on first install.

### Secrets
- All secrets go through Supabase Edge Function proxies, never in client code.
- `.entitlements` and `Info.plist` are checked in. `Secrets.xcconfig` is generated at build time and gitignored.

### UI defaults
- Dark mode is the default (`@AppStorage("colorScheme")` defaults to `"dark"`).
- `@AppStorage` for user preferences (notifications, gameplay toggles, color scheme).
- The onboarding flow uses `Color.black` backgrounds with cyan accent everywhere — match this when adding new onboarding steps.

## Removed in 2.8.11 — do not revive without context

- The "Build my own plan" custom workout plan path and the entire `GoalSurveyView` were removed in 2.8.11 after three failed attempts to fix a black-screen render bug in the survey's `fullScreenCover`. The fix was deletion, not patching.
- Profile fields like `goalSurveyCompleted`, `goalSurveyDaysPerWeek`, `goalSurveySplit` etc. remain in the SwiftData model for CloudKit backward compatibility but are unreferenced from onboarding.
- If you reintroduce this feature, do NOT use `fullScreenCover` for the survey — wrap it in a `NavigationStack` with an explicit close `ToolbarItem` so it has a guaranteed rendering shell and a guaranteed dismiss path.

## Memory systems & state

- `@AppStorage("hasCompletedOnboarding")` — gates whether the user sees onboarding or `ContentView`. Settings → Delete Account flips this back to `false` and the SwiftUI hierarchy automatically routes the user back to `OnboardingView`.
- `@AppStorage("rpt_linked_apple_user_id")` — persists the SIWA user ID so future launches can re-link without a fresh credential flow.
- `KeychainHelper` (in `AppleAuthService.swift`) — stores the Apple user ID under account `com.SpiroTechnologies.RPT.appleSignIn`. Survives app deletion.
- App Group: `group.com.SpiroTechnologies.RPT` — shared with the widget extension.

## Testing

There is no test target. The project has had `RPTTests` and `RPTUITests` schemes since project init but no tests have been written. When adding a new feature, **add a manual test plan in the PR description** rather than writing test code that nobody runs.

## When stuck

- If a SwiftUI view "doesn't render" — prefer a structural container that *guarantees* rendering (`NavigationStack`, explicit `ZStack { Color.black }` base, GeometryReader) over patching modifier-by-modifier.
- If a TestFlight user reports a permission/entitlement bug, **verify the signed archive entitlements before assuming code** (see "Verifying a Signed Archive" above).
- If `supabase db push` errors with "Remote migration versions not found", do NOT run the `repair` command it suggests — use `supabase db query --linked -f` instead (see "Supabase ad-hoc SQL workflow").
- If a service decode silently produces empty results, check whether the proxy's JSON shape matches the Swift `Decodable` (camelCase vs snake_case, wrapper objects vs bare arrays). The avatar picker was broken for months because of exactly this mismatch.
