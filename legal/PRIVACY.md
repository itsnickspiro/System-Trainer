# Privacy Policy

**App:** System Trainer (internal codename: RPT)
**Bundle ID:** com.SpiroTechnologies.RPT
**Publisher:** Spiro Technologies — operated by Nick Spiro
**Location:** Orland Park, Illinois, USA
**Contact:** directr441@gmail.com
**Effective date:** April 7, 2026

---

## Table of Contents

1. [The Short Version](#1-the-short-version)
2. [Who We Are](#2-who-we-are)
3. [Data We Collect](#3-data-we-collect)
   - 3.1 [HealthKit Data (Apple Health)](#31-healthkit-data-apple-health)
   - 3.2 [Apple ID Information (Sign in with Apple)](#32-apple-id-information-sign-in-with-apple)
   - 3.3 [Camera](#33-camera)
   - 3.4 [Location](#34-location)
   - 3.5 [Motion & Fitness](#35-motion--fitness)
   - 3.6 [Photo Library](#36-photo-library)
   - 3.7 [Notifications](#37-notifications)
   - 3.8 [Device Information](#38-device-information)
   - 3.9 [Advertising Identifier (IDFA) & App Tracking Transparency](#39-advertising-identifier-idfa--app-tracking-transparency)
   - 3.10 [Player Profile Data](#310-player-profile-data)
4. [Where Your Data Is Stored](#4-where-your-data-is-stored)
5. [HealthKit-Specific Disclosure](#5-healthkit-specific-disclosure)
6. [Third-Party Services](#6-third-party-services)
7. [Sign in with Apple & Private Relay](#7-sign-in-with-apple--private-relay)
8. [Children's Privacy](#8-childrens-privacy)
9. [Your Rights & How To Exercise Them](#9-your-rights--how-to-exercise-them)
10. [Cookies & Web Tracking](#10-cookies--web-tracking)
11. [Push Notifications](#11-push-notifications)
12. [Data Retention](#12-data-retention)
13. [Security](#13-security)
14. [Changes To This Policy](#14-changes-to-this-policy)
15. [Contact Us](#15-contact-us)

---

## 1. The Short Version

If you only read one part of this document, read this.

- **Your fitness data stays on your device.** Everything System Trainer reads from Apple Health (steps, sleep, heart rate, workouts, body measurements) is processed locally on your iPhone and is **never** transmitted to our servers, sold, or shared with advertisers.
- **Your game profile syncs to our backend.** A small set of RPG-style fields — your display name, level, XP, streak, Gold Pieces balance, fitness goal, and onboarding survey answers — is stored on Supabase so your progress survives a reinstall and so the leaderboard works.
- **You are identified by an anonymous CloudKit user ID.** We don't require a username, phone number, or password. Sign in with Apple is optional and is only used to recover your account on a new device.
- **No ads, no analytics SDKs, no tracking pixels, no selling data.** System Trainer does not embed Google Analytics, Meta SDK, Firebase Analytics, AdMob, Mixpanel, Segment, or any comparable tool.
- **Delete your account at any time from inside the app.** Settings → Delete Account wipes every row on our backend that is keyed to you. Your local SwiftData and iCloud copies are removed when you uninstall the app.
- **No third-party API keys are shipped in the app.** Every external API call (exercise database, food database, weather, etc.) is routed through our Supabase Edge Functions, which hold credentials in Supabase Vault.

---

## 2. Who We Are

System Trainer is an independent iOS fitness game developed and operated by **Nick Spiro** under the banner **Spiro Technologies**, based in Orland Park, Illinois, USA. Spiro Technologies is the data controller for the limited profile data stored in our Supabase backend.

If you have any privacy question, data request, or concern, email **directr441@gmail.com**. There is no third-party customer-support portal — messages go directly to the operator.

---

## 3. Data We Collect

System Trainer only collects the specific categories listed below. We do not collect anything that is not described here.

### 3.1 HealthKit Data (Apple Health)

With your explicit permission granted through the iOS HealthKit permission sheet, System Trainer **reads** the following sample types from Apple Health:

- Step count
- Active energy burned
- Distance walking / running
- Flights climbed
- Apple Exercise Time
- Resting heart rate
- Heart rate
- Heart rate variability (SDNN)
- VO₂ Max
- Body mass (weight)
- Height
- Body fat percentage
- Body mass index
- Sleep analysis
- Respiratory rate
- Oxygen saturation

With your explicit permission, System Trainer **writes** the following sample types back to Apple Health so that data you log inside the app appears alongside data from other fitness apps:

- Workouts (HKWorkout sessions with duration and activity type)
- Body mass (weight readings)
- Dietary water, energy, protein, carbohydrates, total fat, saturated fat, fiber, sugar, sodium, cholesterol, potassium, calcium, iron, vitamin C, vitamin D
- Mindful sessions

**All HealthKit data is processed exclusively on your device.** System Trainer does not transmit any HealthKit sample, derived value, or aggregate to Supabase, to any third-party server, to any analytics pipeline, or to any advertising partner. HealthKit data is **never** sold. HealthKit data is **never** used for advertising, marketing, or retargeting. See Section 5 for the full App Store HealthKit disclosure.

You can revoke HealthKit access at any time in iOS Settings → Privacy & Security → Health → System Trainer. Revoking access does not delete data already read by the app, but it prevents further reads and writes.

### 3.2 Apple ID Information (Sign in with Apple)

Sign in with Apple is **optional**. You can use the entire app without signing in. If you choose to sign in, System Trainer requests only the `.fullName` and `.email` scopes so that we can:

- Display your name in the app and on the leaderboard.
- Link your progress to a stable identifier so you can recover your account after reinstalling the app or switching devices.

Apple only provides the full name and email address on the **first** sign-in for a given Apple ID / app combination. These values are stored locally (UserDefaults and Keychain) and are associated with your profile row in our Supabase database. If you chose "Hide My Email" at the Sign in with Apple prompt, Apple provides only a private relay address (@privaterelay.appleid.com) — we never see your real email.

The opaque Apple user ID (a long string with no personal information) is persisted in the iOS Keychain on your device so that Sign in with Apple survives app deletion and lets you recover your account by signing in again.

### 3.3 Camera

System Trainer requests camera access **only when you tap the barcode scanner** in the Diet tab. The camera is used solely to decode product barcodes so we can look up nutrition information. Camera frames are processed in memory on your device and are never saved, transmitted, or uploaded to any server.

Usage description string shown by iOS: *"System Trainer uses the camera to scan food barcodes so you can log meals instantly without typing."*

### 3.4 Location

System Trainer requests location access only for the **Patrol Routes** feature, which records the path of an outdoor cardio workout so you can see distance, pace, and your route on a map.

- **When In Use** permission is requested the first time you start a Patrol route.
- **Always** permission is only requested if you opt into background tracking so that the route continues recording while the screen is locked.

Location samples are stored **locally** in your SwiftData store as part of the `PatrolRoute` model. Routes are synced to your private iCloud database via Apple's CloudKit (see Section 4) but are **not** sent to Supabase or any third party.

Usage description strings shown by iOS:

- *"System Trainer uses your location to track outdoor cardio routes (Patrol mode) so you can see distance, pace, and the path you ran or walked."*
- *"System Trainer needs continued location access to keep recording your route while the screen is locked during outdoor cardio sessions."*

### 3.5 Motion & Fitness

System Trainer requests motion access to detect workouts and steps when Apple Health data is unavailable (for example, on a device with no Apple Watch paired). Motion data is used on-device only and is never transmitted off the device.

Usage description string shown by iOS: *"System Trainer uses motion data to detect workouts and steps when Apple Health is unavailable."*

### 3.6 Photo Library

System Trainer can read from the photo library only when you explicitly choose to pick an image (for example, to attach a screenshot to a bug report). Access is scoped to the file you pick, and the app never reads your photo library in the background or without your action.

Usage description string shown by iOS: *"This app requires access to your photo library to let users select, import, and use existing images or videos from their device."*

### 3.7 Notifications

Push notifications are **opt-in**. The iOS permission prompt is only shown after you complete onboarding. We use notifications exclusively for:

- Quest reminders
- Streak warnings
- Level-up and achievement announcements
- Daily reset notifications

We do **not** send marketing notifications, promotional campaigns, or notifications from third parties.

### 3.8 Device Information

When your profile is synced to Supabase, the following non-identifying device metadata may be included so we can diagnose crashes and support specific iPhone models:

- App version
- Device model (for example, "iPhone 15 Pro")
- iOS version

This information is also attached to any bug report you submit from Settings → Report a Bug so we can reproduce the issue. See Section 3.10 for the full list of player-profile columns.

### 3.9 Advertising Identifier (IDFA) & App Tracking Transparency

System Trainer includes the App Tracking Transparency framework and may show the standard iOS "Allow tracking?" prompt during onboarding. **System Trainer does not currently run any analytics, advertising, or attribution SDK that uses the IDFA**, and we do not transmit the IDFA to any server. The ATT prompt is included for future compatibility and to comply with App Store guidelines. Choosing "Ask App Not to Track" has no functional effect on the app today because no tracking occurs regardless of your answer.

If this changes in a future version, this policy will be updated and you will be notified in the app.

Usage description string shown by iOS: *"System Trainer uses the advertising identifier only for anonymous analytics about which features players use most. We never share or sell your data."*

### 3.10 Player Profile Data

When you use System Trainer, a limited set of fields from your in-app profile is synced to our Supabase backend so that you can recover your progress, appear on the leaderboard, and participate in server-side features like the GP economy and guilds. The **only** columns that the backend accepts are:

- **Identity:** display name, avatar key
- **Progression:** level, total XP, current streak, longest streak, leaderboard rank
- **Demographics (from the onboarding survey):** weight (kg), height (cm), date of birth (used only to compute age), biological sex, metric/imperial preference, activity level index
- **Goals & preferences:** fitness goal, diet type, player class / archetype, gym environment, active anime training plan key
- **Onboarding survey answers:** days per week, split type, session length, intensity, focus areas, cardio preference, whether onboarding is completed
- **Social:** rival's CloudKit user ID, rival display name, guild ID / name / role
- **Economy & stats:** Gold Pieces (system credits), lifetime credits earned, total workouts logged, total quests completed, total days active
- **Goal tracking:** daily calorie goal, daily protein goal, daily step goal, daily water goal (oz)
- **Diagnostics:** app version, device model

**Data we do NOT sync to Supabase:** individual workout sessions, exercise sets, personal records, specific food entries, meal history, body measurement history, patrol route GPS paths, HealthKit samples, or any Apple Health data. All of that data lives only on your device (SwiftData) and in your private iCloud CloudKit database.

Your row in Supabase is keyed by an **anonymous CloudKit user record ID** (or a locally generated UUID if you do not have an iCloud account). This identifier is not linked to your real name, Apple ID email, phone number, or any public identity unless you explicitly sign in with Apple.

**Bug reports:** if you tap "Report a Bug" in Settings and write a description, we store the text you submitted, your app version, build number, device model, iOS version, your CloudKit user ID, and an optional screenshot you choose to attach. Screenshots are stored in Supabase Storage and are only accessed by the operator (Nick Spiro) to diagnose the reported issue.

---

## 4. Where Your Data Is Stored

System Trainer data lives in exactly three places:

1. **On your iPhone (SwiftData)** — workout history, exercise sets, personal records, food entries, custom meals, body measurements, patrol route GPS paths, achievements, inventory, and anything else listed in `Models.swift`. This data is encrypted at rest by iOS as part of the standard iOS sandbox.
2. **Your private Apple iCloud CloudKit database** (`iCloud.com.SpiroTechnologies.RPT`) — SwiftData automatically syncs to this **private** CloudKit database so that your workouts and progress follow you to your other iOS devices. This is your personal iCloud space. Spiro Technologies has no visibility into it and cannot read, export, or delete records in your private database.
3. **Spiro Technologies' Supabase project (hosted in US East)** — the small set of player-profile columns listed in Section 3.10, credit transaction history, leaderboard entries, friend connections, guild memberships, and optional bug reports. This is the only place where we, the operator, can see your data.

---

## 5. HealthKit-Specific Disclosure

Apple requires apps that access HealthKit to disclose their HealthKit data practices explicitly. System Trainer complies in full:

- HealthKit data is **never** sold.
- HealthKit data is **never** shared with third parties.
- HealthKit data is **never** used for advertising, marketing, remarketing, or any similar purpose.
- HealthKit data is **never** transmitted from your device to Supabase, to any Spiro Technologies server, to any analytics service, or to any content delivery network.
- HealthKit data is **never** disclosed to data brokers or information resellers.
- HealthKit data is used only within the app itself, to power quests, stats, and on-device coaching.

If you have any concern about how HealthKit data is handled, email **directr441@gmail.com** and we will respond promptly.

---

## 6. Third-Party Services

System Trainer talks to several external services so that features like food search and weather lookup can work. **No third-party API keys are ever bundled in the iOS app binary.** Every external request is proxied through a Supabase Edge Function that validates a shared app secret and fetches the real API key from Supabase Vault.

The external services used today are:

| Service | Purpose | Data sent |
|--|--|--|
| **USDA FoodData Central** (`api.nal.usda.gov`) | Government food database lookups | Search query text only |
| **Open Food Facts** (`world.openfoodfacts.org`, `search.openfoodfacts.org`) | Crowdsourced food database and barcode lookups | Search query text or barcode only |
| **API Ninjas — Nutrition** (`api.api-ninjas.com/v1/nutrition`) | Parsed nutrition lookups for freeform food text | Search query text only |
| **API Ninjas — Recipe** (`api.api-ninjas.com/v2/recipe`) | Recipe search | Search query text only |
| **Weatherstack** (`api.weatherstack.com`) | Weather conditions for outdoor workouts | Approximate location (latitude / longitude) or city name |
| **Apple App Store Connect API** (`api.appstoreconnect.apple.com`) | Pulls TestFlight beta feedback submitted by testers (not used for general users) | TestFlight comment text, device model, OS version, app version — only if you submit feedback through TestFlight |

The exercise database, anime training plans, quest templates, announcements, remote config, store catalog, achievements, events, avatars, and leaderboard data are all served **from Spiro Technologies' own Supabase database**, not from a third party.

None of the third-party providers listed above receive your identity, Apple ID, CloudKit user ID, HealthKit data, or any other personally identifying information. They receive only the minimal query text or coordinates needed to answer the specific request.

System Trainer does **not** include:

- Google Analytics, Firebase Analytics, or any Google tracking SDK
- Meta (Facebook) SDK, Meta Pixel, or Meta Audience Network
- AdMob, AppLovin, Unity Ads, or any other ad network
- Mixpanel, Amplitude, Segment, Heap, PostHog, or any analytics SDK
- Crashlytics, Sentry, Bugsnag, or any third-party crash reporter (crashes are diagnosed through Apple's built-in crash logs and TestFlight feedback)

---

## 7. Sign in with Apple & Private Relay

Sign in with Apple is the only authentication method System Trainer offers, and it is strictly optional. If you choose to sign in:

- You can use the standard **"Hide My Email"** option so that Apple gives us only a private-relay address. We never see your real email.
- Apple's opaque user identifier is the **only** stable key we store; it is not your email, phone number, or iCloud username.
- You can revoke Sign in with Apple at any time from iOS Settings → Apple ID → Sign-In & Security → Sign in with Apple → System Trainer → Stop Using Apple ID. The next time the app checks credential state, it will sign you out locally.

Signing out inside the app does **not** automatically delete your Supabase row. To fully erase your data, use Settings → Delete Account (see Section 9).

---

## 8. Children's Privacy

System Trainer is rated **13+** on the App Store and is **not directed to children under 13**. We do not knowingly collect information from children under 13. If you are under 13, please do not use System Trainer and do not submit any information to us.

In the U.S., the Children's Online Privacy Protection Act (COPPA) applies only to services directed at children under 13. Because System Trainer targets users 13 and older, COPPA's parental-consent obligations are not triggered. If you are a parent or guardian and believe your child under 13 has used the app, email **directr441@gmail.com** and we will promptly delete any associated profile.

---

## 9. Your Rights & How To Exercise Them

### Delete your account in one tap

Open the app → Settings → **Delete Account**. This triggers the `delete_account` action on our backend, which **immediately and irreversibly** deletes your rows from every table that stores your data:

- `player_profiles`
- `leaderboard`
- `player_inventory`
- `credit_transactions`
- `player_backups`
- `event_participants`
- `guild_members`
- `guild_raid_contributions`
- `friend_connections` (both directions)

If you are signed in with Apple, we also perform a defense-in-depth delete keyed on your Apple user ID to catch any stray rows. After deletion, your data is gone from our backend and cannot be recovered. Your local on-device SwiftData and your private iCloud CloudKit records are removed by uninstalling the app and, optionally, clearing the private CloudKit database from iOS Settings → Apple ID → iCloud → Manage Storage.

### Access your data

Email **directr441@gmail.com** with the subject line "Data access request" and we will provide a JSON export of the Supabase rows keyed to your CloudKit user ID within 30 days.

### Revoke individual permissions

You can independently revoke any of the permissions System Trainer asks for at any time from iOS Settings:

- **HealthKit:** Settings → Privacy & Security → Health → System Trainer
- **Camera:** Settings → Privacy & Security → Camera → System Trainer
- **Location:** Settings → Privacy & Security → Location Services → System Trainer
- **Motion & Fitness:** Settings → Privacy & Security → Motion & Fitness → System Trainer
- **Notifications:** Settings → Notifications → System Trainer
- **Tracking (IDFA / ATT):** Settings → Privacy & Security → Tracking
- **Sign in with Apple:** Settings → Apple ID → Sign-In & Security → Sign in with Apple → System Trainer

### California residents (CCPA / CPRA)

If you are a California resident, you have the right to:

- **Know** what personal information we have collected about you (email us).
- **Delete** your personal information (use in-app Delete Account).
- **Correct** inaccurate personal information (email us).
- **Opt out** of the sale or sharing of personal information — **we never sell or share personal information for cross-context behavioral advertising, so there is nothing to opt out of.**
- **Non-discrimination** for exercising your rights. We will never treat you differently for making a request.

### European Economic Area residents (GDPR)

If you are in the EEA, UK, or Switzerland, you have the right to:

- **Access** the personal data we hold about you.
- **Rectify** inaccurate data.
- **Erase** your data ("right to be forgotten") via in-app Delete Account.
- **Restrict or object** to certain processing.
- **Data portability** — we provide exports in JSON upon request.
- **Lodge a complaint** with your local supervisory authority.

Our legal basis for processing is your **consent** (you opt in to sync your profile) and our **legitimate interest** in making the app work (for example, rendering the leaderboard). Data transfers to the United States are handled by Supabase, our infrastructure provider, under their Standard Contractual Clauses.

---

## 10. Cookies & Web Tracking

System Trainer is a native iOS application. It does not use cookies, web beacons, tracking pixels, local storage scripts, browser fingerprinting, or any other web-tracking technology. It does not render any content inside an in-app browser, and it does not load any third-party web content during normal operation.

---

## 11. Push Notifications

Push notifications are opt-in. iOS will show you the standard system prompt after you complete onboarding. Notifications are used **only** for gameplay events — quest reminders, streak warnings, level-up messages, achievement unlocks, and daily reset reminders. We do not use push notifications for marketing, promotions, or third-party content. You can disable notifications entirely in iOS Settings → Notifications → System Trainer.

---

## 12. Data Retention

- **On-device data (SwiftData):** retained until you uninstall the app or use Settings → Delete Account.
- **Private iCloud CloudKit database:** retained in your personal iCloud space until you delete the app and clear its CloudKit data from iOS Settings. Spiro Technologies cannot access or delete this data for you.
- **Supabase player profile rows:** retained until you use Settings → Delete Account, at which point the rows are deleted immediately and permanently.
- **Bug reports:** retained until the underlying issue is resolved. You can request earlier deletion by emailing directr441@gmail.com.
- **Aggregated, non-identifying operational metrics** (such as total active players on a given day): may be retained indefinitely in aggregate form only.

We do not perform automatic "inactive account" deletions. Your data persists until **you** choose to delete it.

---

## 13. Security

- **Encryption at rest on device:** Your iPhone encrypts the app's SwiftData store as part of the standard iOS sandbox using your device passcode or biometrics.
- **Encryption in transit:** All network traffic from the app to Supabase travels over HTTPS (TLS 1.2+).
- **Private CloudKit database:** Apple handles encryption, access control, and storage for your private CloudKit database. Only you can read it.
- **App secret validation:** Every request from the app to a Supabase Edge Function includes an `x-app-secret` header that is validated server-side. Requests without the correct secret are rejected with HTTP 401.
- **Supabase Vault for credentials:** All third-party API keys (USDA, Open Food Facts, API Ninjas, Weatherstack, Apple App Store Connect) are stored in Supabase Vault and are fetched server-side only. No API key is ever bundled in the client app.
- **Row-level security:** Supabase writes are gated by the service role key inside the Edge Functions; clients cannot write to the database directly.
- **Keychain storage:** Your Sign in with Apple identifier is stored in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlock` so it is protected by your device passcode.

No system is perfectly secure. If you discover a security issue, please email **directr441@gmail.com** with details and we will investigate promptly.

---

## 14. Changes To This Policy

This policy lives at [`legal/PRIVACY.md`](./PRIVACY.md) in the System Trainer GitHub repository. When we change it, we will update the **Effective date** at the top. Material changes that affect what data is collected or how it is used will also be announced inside the app (either via the Announcements feed or a first-launch notice after the update).

We encourage you to re-read this policy after any significant app update.

---

## 15. Contact Us

- **Email:** directr441@gmail.com
- **Developer:** Nick Spiro — Spiro Technologies
- **Location:** Orland Park, Illinois, USA
- **GitHub issues:** https://github.com/directr441/System-Trainer/issues

If you send a privacy-related email, please include "System Trainer privacy" in the subject line so we can respond quickly.
