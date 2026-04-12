import SwiftUI
import PhotosUI

// MARK: - Admin Views
//
// Conditionally shown UI for players with is_admin=true.
// These views are only accessible when PlayerProfileService.shared.isAdmin is true.

// MARK: - Admin Add Avatar Sheet

struct AdminAddAvatarSheet: View {
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var avatarKey = ""
    @State private var avatarName = ""
    @State private var category = "free"
    @State private var gender = "male"
    @State private var unlockType = "free"
    @State private var gpCost = ""
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var uploadSuccess = false

    private let categories = ["free", "warrior", "mage", "rogue", "tank", "anime", "event", "premium"]
    private let genders = ["male", "female", "neutral"]
    private let unlockTypes = ["free", "gp_purchase", "level", "achievement", "event"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                        Text("ADMIN — Add Avatar")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                Section("Image") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Label("Select Image", systemImage: "photo.badge.plus")
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                selectedImage = img
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Key (e.g. avatar_ninja_m) *", text: $avatarKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Display Name *", text: $avatarName)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Gender", selection: $gender) {
                        ForEach(genders, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                Section("Unlock Settings") {
                    Picker("Unlock Type", selection: $unlockType) {
                        ForEach(unlockTypes, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                    }
                    if unlockType == "gp_purchase" {
                        TextField("GP Cost", text: $gpCost)
                            .keyboardType(.numberPad)
                    }
                }

                if let error = uploadError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { upload() }
                        .disabled(avatarKey.isEmpty || avatarName.isEmpty || selectedImage == nil || isUploading)
                        .foregroundColor(.orange)
                }
            }
            .alert("Avatar Added", isPresented: $uploadSuccess) {
                Button("OK") {
                    onComplete()
                    dismiss()
                }
            } message: {
                Text("\(avatarName) is now live in the avatar catalog.")
            }
        }
    }

    private func upload() {
        guard let image = selectedImage,
              let pngData = image.pngData() else { return }
        isUploading = true
        uploadError = nil

        Task {
            do {
                let base64 = pngData.base64EncodedString()
                let body: [String: Any] = [
                    "action": "add_avatar",
                    "key": avatarKey.trimmingCharacters(in: .whitespaces),
                    "name": avatarName.trimmingCharacters(in: .whitespaces),
                    "image_base64": base64,
                    "content_type": "image/png",
                    "category": category,
                    "gender": gender,
                    "unlock_type": unlockType,
                    "gp_cost": Int(gpCost) ?? 0,
                    "sort_order": 100
                ]

                guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/avatar-upload-proxy") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.timeoutInterval = 60

                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let errBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    await MainActor.run {
                        uploadError = (errBody?["error"] as? String) ?? "Upload failed"
                        isUploading = false
                    }
                    return
                }

                await MainActor.run {
                    isUploading = false
                    uploadSuccess = true
                }
            } catch {
                await MainActor.run {
                    uploadError = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }
}

// MARK: - Admin Moderation Review View

struct AdminModerationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [AdminReport] = []
    @State private var flags: [AdminFlag] = []
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Reports (\(reports.count))").tag(0)
                    Text("Flags (\(flags.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedTab == 0 {
                    reportsList
                } else {
                    flagsList
                }
            }
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .task { await refresh() }
    }

    private var reportsList: some View {
        List {
            if reports.isEmpty {
                Text("No pending reports").foregroundColor(.secondary)
            }
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.red)
                        Spacer()
                        Text(report.status)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.orange)
                    }
                    Text("Reported: \(report.reportedCloudkitUserId.prefix(12))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let desc = report.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Button("Dismiss") {
                            Task { await actionReport(report.id, status: "dismissed") }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray)

                        Button("Ban") {
                            Task {
                                await banPlayer(report.reportedCloudkitUserId)
                                await actionReport(report.id, status: "actioned")
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var flagsList: some View {
        List {
            if flags.isEmpty {
                Text("No unreviewed flags").foregroundColor(.secondary)
            }
            ForEach(flags) { flag in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(flag.flagType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.orange)
                        Spacer()
                        if let mag = flag.magnitude {
                            Text("\(Int(mag))")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundColor(.red)
                        }
                    }
                    Text("Player: \(flag.cloudkitUserId.prefix(12))...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("False Positive") {
                            Task { await reviewFlag(flag.id, resolution: "false_positive") }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray)

                        Button("Ban") {
                            Task {
                                await banPlayer(flag.cloudkitUserId)
                                await reviewFlag(flag.id, resolution: "banned")
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func refresh() async {
        isLoading = true
        async let r = fetchReports()
        async let f = fetchFlags()
        reports = await r
        flags = await f
        isLoading = false
    }

    private func fetchReports() async -> [AdminReport] {
        guard let data = try? await adminProxyCall(body: [
            "action": "list_pending",
            "status_filter": "pending",
            "limit": 50
        ]) else { return [] }
        return (try? JSONDecoder().decode(AdminReportsResponse.self, from: data))?.reports ?? []
    }

    private func fetchFlags() async -> [AdminFlag] {
        guard let data = try? await adminProxyCall(body: [
            "action": "list_flagged",
            "unreviewed_only": true,
            "limit": 50
        ]) else { return [] }
        return (try? JSONDecoder().decode(AdminFlagsResponse.self, from: data))?.flags ?? []
    }

    private func actionReport(_ reportId: String, status: String) async {
        _ = try? await adminProxyCall(body: [
            "action": "action_report",
            "report_id": reportId,
            "new_status": status,
            "reviewer": "admin_app"
        ])
        await refresh()
    }

    private func reviewFlag(_ flagId: String, resolution: String) async {
        _ = try? await adminProxyCall(body: [
            "action": "review_flag",
            "flag_id": flagId,
            "resolution": resolution,
            "reviewer": "admin_app"
        ])
        await refresh()
    }

    private func banPlayer(_ cloudkitUserId: String) async {
        _ = try? await adminProxyCall(body: [
            "action": "ban_player",
            "target_cloudkit_user_id": cloudkitUserId,
            "reason": "admin_app_action"
        ])
    }

    private func adminProxyCall(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/moderation-proxy") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: - Admin Models

struct AdminReport: Codable, Identifiable {
    let id: String
    let reporterCloudkitUserId: String
    let reportedCloudkitUserId: String
    let reason: String
    let description: String?
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason, description, status
        case reporterCloudkitUserId = "reporter_cloudkit_user_id"
        case reportedCloudkitUserId = "reported_cloudkit_user_id"
        case createdAt = "created_at"
    }
}

struct AdminFlag: Codable, Identifiable {
    let id: String
    let cloudkitUserId: String
    let flagType: String
    let magnitude: Double?
    let autoDetectedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, magnitude
        case cloudkitUserId = "cloudkit_user_id"
        case flagType = "flag_type"
        case autoDetectedAt = "auto_detected_at"
    }
}

private struct AdminReportsResponse: Decodable {
    let reports: [AdminReport]?
}

private struct AdminFlagsResponse: Decodable {
    let flags: [AdminFlag]?
}

// MARK: - Admin Create Event Sheet

struct AdminCreateEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var eventDescription = ""
    @State private var eventType = "challenge"
    @State private var rewardGP = "500"
    @State private var rewardXP = "200"
    @State private var durationDays = "7"
    @State private var isCreating = false
    @State private var createError: String?
    @State private var createSuccess = false

    private let eventTypes = ["challenge", "community", "seasonal", "special"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                        Text("ADMIN — Create Event")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                Section("Event Details") {
                    TextField("Title *", text: $title)
                    TextField("Description", text: $eventDescription, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Type", selection: $eventType) {
                        ForEach(eventTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                Section("Duration") {
                    HStack {
                        Text("Days")
                        Spacer()
                        TextField("7", text: $durationDays)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }

                Section("Rewards") {
                    HStack {
                        Text("GP Reward")
                        Spacer()
                        TextField("0", text: $rewardGP)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("XP Reward")
                        Spacer()
                        TextField("0", text: $rewardXP)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                if let error = createError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.isEmpty || isCreating)
                        .foregroundColor(.orange)
                }
            }
            .alert("Event Created", isPresented: $createSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(title) is now live!")
            }
        }
    }

    private func create() {
        isCreating = true
        createError = nil
        let days = Int(durationDays) ?? 7

        Task {
            do {
                let body: [String: Any] = [
                    "action": "admin_create_event",
                    "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                    "title": title,
                    "description": eventDescription,
                    "event_type": eventType,
                    "reward_gp": Int(rewardGP) ?? 0,
                    "reward_xp": Int(rewardXP) ?? 0,
                    "starts_at": ISO8601DateFormatter().string(from: Date()),
                    "ends_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(days * 86400)))
                ]

                guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/events-proxy") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: req)
                let http = response as? HTTPURLResponse
                if http?.statusCode == 200 {
                    await MainActor.run {
                        isCreating = false
                        createSuccess = true
                    }
                } else {
                    let errBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    await MainActor.run {
                        createError = (errBody?["error"] as? String) ?? "Creation failed"
                        isCreating = false
                    }
                }
            } catch {
                await MainActor.run {
                    createError = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Admin Store Item Sheet

struct AdminCreateStoreItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var itemKey = ""
    @State private var itemName = ""
    @State private var itemDescription = ""
    @State private var itemType = "equipment"
    @State private var gpPrice = "100"
    @State private var storeSection = "permanent"
    @State private var bonusStat = "strength"
    @State private var bonusValue = "5"
    @State private var isCreating = false
    @State private var createError: String?
    @State private var createSuccess = false

    private let itemTypes = ["equipment", "consumable", "cosmetic"]
    private let sections = ["permanent", "featured", "daily", "weekly"]
    private let stats = ["strength", "endurance", "focus", "discipline", "vitality", "energy"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                        Text("ADMIN — Create Store Item")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                Section("Item Details") {
                    TextField("Key (e.g. sword_of_valor) *", text: $itemKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Display Name *", text: $itemName)
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Type", selection: $itemType) {
                        ForEach(itemTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                Section("Store Placement") {
                    Picker("Section", selection: $storeSection) {
                        ForEach(sections, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    HStack {
                        Text("Price (GP)")
                        Spacer()
                        TextField("100", text: $gpPrice)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                if itemType == "equipment" {
                    Section("Stat Bonus") {
                        Picker("Stat", selection: $bonusStat) {
                            ForEach(stats, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        HStack {
                            Text("Bonus Value")
                            Spacer()
                            TextField("5", text: $bonusValue)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }

                if let error = createError {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Create Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(itemKey.isEmpty || itemName.isEmpty || isCreating)
                        .foregroundColor(.orange)
                }
            }
            .alert("Item Created", isPresented: $createSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(itemName) is now in the store!")
            }
        }
    }

    private func create() {
        isCreating = true
        createError = nil

        Task {
            do {
                var body: [String: Any] = [
                    "action": "admin_create_item",
                    "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                    "key": itemKey.trimmingCharacters(in: .whitespaces),
                    "name": itemName.trimmingCharacters(in: .whitespaces),
                    "description": itemDescription,
                    "item_type": itemType,
                    "gp_price": Int(gpPrice) ?? 100,
                    "store_section": storeSection,
                    "is_enabled": true
                ]

                if itemType == "equipment" {
                    body["bonus_\(bonusStat)"] = Int(bonusValue) ?? 0
                    body["effect_type"] = "stat_bonus"
                }

                guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/store-proxy") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: req)
                let http = response as? HTTPURLResponse
                if http?.statusCode == 200 {
                    await MainActor.run {
                        isCreating = false
                        createSuccess = true
                    }
                } else {
                    let errBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    await MainActor.run {
                        createError = (errBody?["error"] as? String) ?? "Creation failed"
                        isCreating = false
                    }
                }
            } catch {
                await MainActor.run {
                    createError = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Admin Hub View
// Central admin panel accessible from Settings or HomeView for admin users.

struct AdminHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showModeration = false
    @State private var showCreateEvent = false
    @State private var showCreateStoreItem = false
    @State private var showCreateQuest = false
    @State private var showCreateTournament = false
    @State private var showPlayerManager = false
    @State private var showSeasonManager = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .foregroundColor(.orange)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Admin Panel")
                                .font(.headline)
                            Text("Manage content, players, and moderation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Content Management") {
                    Button { showCreateEvent = true } label: {
                        Label("Events", systemImage: "calendar.badge.plus")
                    }
                    Button { showCreateStoreItem = true } label: {
                        Label("Store Items", systemImage: "bag.badge.plus")
                    }
                    Button { showCreateQuest = true } label: {
                        Label("Quest Templates", systemImage: "scroll")
                    }
                    NavigationLink {
                        AdminAddAvatarSheet()
                    } label: {
                        Label("Upload Avatar", systemImage: "person.crop.circle.badge.plus")
                    }
                    NavigationLink {
                        AdminAddFoodSheet(barcode: "")
                    } label: {
                        Label("Add Food", systemImage: "fork.knife")
                    }
                }

                Section("Competitive") {
                    Button { showCreateTournament = true } label: {
                        Label("Tournaments", systemImage: "trophy")
                    }
                    Button { showSeasonManager = true } label: {
                        Label("Seasons", systemImage: "leaf")
                    }
                }

                Section("Player Management") {
                    Button { showPlayerManager = true } label: {
                        Label("Search & Edit Players", systemImage: "person.text.rectangle")
                    }
                }

                Section("Moderation") {
                    Button { showModeration = true } label: {
                        Label("Reports & Flags", systemImage: "exclamationmark.shield")
                    }
                }
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showModeration) { AdminModerationView() }
            .sheet(isPresented: $showCreateEvent) { AdminCreateEventSheet() }
            .sheet(isPresented: $showCreateStoreItem) { AdminCreateStoreItemSheet() }
            .sheet(isPresented: $showCreateQuest) { AdminCreateQuestSheet() }
            .sheet(isPresented: $showCreateTournament) { AdminTournamentManagerSheet() }
            .sheet(isPresented: $showPlayerManager) { AdminPlayerManagerView() }
            .sheet(isPresented: $showSeasonManager) { AdminSeasonManagerSheet() }
        }
    }
}

// MARK: - Admin Quest Template Creator

struct AdminCreateQuestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var questKey = ""
    @State private var title = ""
    @State private var subtitle = ""
    @State private var questType = "daily"
    @State private var conditionType = "manual"
    @State private var conditionTarget = ""
    @State private var xpReward = "50"
    @State private var creditReward = "0"
    @State private var isCreating = false
    @State private var createError: String?
    @State private var createSuccess = false

    private let questTypes = ["daily", "weekly", "special"]
    private let conditionTypes = ["manual", "steps", "calories_burned", "workout_logged", "food_logged", "water_logged", "sleep_hours", "streak_days"]

    var body: some View {
        NavigationStack {
            Form {
                adminHeader("Create Quest Template")
                Section("Quest Details") {
                    TextField("Key (e.g. quest_daily_cardio) *", text: $questKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Title *", text: $title)
                    TextField("Subtitle", text: $subtitle)
                    Picker("Type", selection: $questType) {
                        ForEach(questTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Section("Completion") {
                    Picker("Condition", selection: $conditionType) {
                        ForEach(conditionTypes, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                    }
                    if conditionType != "manual" {
                        TextField("Target (e.g. 10000 for steps)", text: $conditionTarget)
                            .keyboardType(.numberPad)
                    }
                }
                Section("Rewards") {
                    numField("XP Reward", text: $xpReward)
                    numField("GP Reward", text: $creditReward)
                }
                errorSection(createError)
            }
            .navigationTitle("Create Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(questKey.isEmpty || title.isEmpty || isCreating).foregroundColor(.orange)
                }
            }
            .alert("Quest Created", isPresented: $createSuccess) { Button("OK") { dismiss() } }
        }
    }

    private func create() {
        isCreating = true; createError = nil
        Task {
            let body: [String: Any] = [
                "action": "admin_create_quest_template",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "key": questKey, "title": title, "subtitle": subtitle,
                "quest_type": questType, "condition_type": conditionType,
                "condition_target": conditionTarget.isEmpty ? NSNull() : conditionTarget,
                "xp_reward": Int(xpReward) ?? 50, "credit_reward": Int(creditReward) ?? 0
            ]
            let result = await adminPost(proxy: "quest-templates-proxy", body: body)
            await MainActor.run {
                isCreating = false
                if result { createSuccess = true } else { createError = "Creation failed" }
            }
        }
    }
}

// MARK: - Admin Tournament Manager

struct AdminTournamentManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var tournamentDescription = ""
    @State private var bracketSize = 8
    @State private var entryGPCost = "0"
    @State private var prizePoolGP = "1000"
    @State private var minLevel = "5"
    @State private var isCreating = false
    @State private var createError: String?
    @State private var createSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                adminHeader("Tournaments")
                Section("Create Tournament") {
                    TextField("Title *", text: $title)
                    TextField("Description", text: $tournamentDescription, axis: .vertical).lineLimit(2...4)
                    Picker("Bracket Size", selection: $bracketSize) {
                        Text("8 Players").tag(8); Text("16 Players").tag(16)
                    }
                    numField("Entry Fee (GP)", text: $entryGPCost)
                    numField("Prize Pool (GP)", text: $prizePoolGP)
                    numField("Min Level", text: $minLevel)
                }
                errorSection(createError)
            }
            .navigationTitle("Tournaments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(title.isEmpty || isCreating).foregroundColor(.orange)
                }
            }
            .alert("Tournament Created", isPresented: $createSuccess) { Button("OK") { dismiss() } }
        }
    }

    private func create() {
        isCreating = true; createError = nil
        Task {
            let body: [String: Any] = [
                "action": "admin_create_tournament",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "title": title, "description": tournamentDescription,
                "bracket_size": bracketSize, "entry_gp_cost": Int(entryGPCost) ?? 0,
                "prize_pool_gp": Int(prizePoolGP) ?? 1000, "min_level": Int(minLevel) ?? 5,
                "starts_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(7 * 86400))
            ]
            let result = await adminPost(proxy: "tournament-proxy", body: body)
            await MainActor.run {
                isCreating = false
                if result { createSuccess = true } else { createError = "Creation failed" }
            }
        }
    }
}

// MARK: - Admin Season Manager

struct AdminSeasonManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var seasonService = SeasonService.shared
    @State private var isFinalizing = false
    @State private var finalizeResult: String?

    var body: some View {
        NavigationStack {
            List {
                adminHeader("Season Management")
                if let season = seasonService.activeSeason {
                    Section("Active Season") {
                        LabeledContent("Name", value: season.label)
                        LabeledContent("Season #", value: "\(season.seasonNumber)")
                        LabeledContent("Status", value: season.status)
                        LabeledContent("Remaining", value: "\(seasonService.remainingDays) days")
                    }
                    Section {
                        Button(role: .destructive) {
                            finalize(seasonId: season.id)
                        } label: {
                            Label("Finalize Season Now", systemImage: "checkmark.seal")
                        }
                        .disabled(isFinalizing)
                    }
                } else {
                    Section { Text("No active season").foregroundColor(.secondary) }
                }
                if let result = finalizeResult {
                    Section { Text(result).font(.caption).foregroundColor(.green) }
                }
            }
            .navigationTitle("Seasons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await seasonService.refresh() }
    }

    private func finalize(seasonId: String) {
        isFinalizing = true
        Task {
            let body: [String: Any] = [
                "action": "finalize_season",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "season_id": seasonId
            ]
            let ok = await adminPost(proxy: "season-proxy", body: body)
            await MainActor.run {
                isFinalizing = false
                finalizeResult = ok ? "Season finalized. Next season created." : "Finalize failed"
                Task { await seasonService.refresh() }
            }
        }
    }
}

// MARK: - Admin Player Manager

struct AdminPlayerManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var players: [AdminPlayerResult] = []
    @State private var isSearching = false
    @State private var selectedPlayer: AdminPlayerResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by username...", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .onSubmit { search() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .padding()

                if isSearching {
                    ProgressView("Searching...").padding()
                }

                List(players) { player in
                    Button {
                        selectedPlayer = player
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(player.displayName ?? "Unknown")
                                        .font(.subheadline.weight(.semibold))
                                    if player.isAdmin == true {
                                        Text("ADMIN").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(.orange).padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    }
                                    if player.isBanned == true {
                                        Text("BANNED").font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(.red).padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.red.opacity(0.2)))
                                    }
                                }
                                Text("Lv.\(player.level ?? 1) | \(player.systemCredits ?? 0) GP")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Player Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selectedPlayer) { player in
                AdminPlayerEditorSheet(player: player)
            }
        }
    }

    private func search() {
        guard searchQuery.count >= 2 else { return }
        isSearching = true
        Task {
            let body: [String: Any] = [
                "action": "admin_search_players",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "query": searchQuery
            ]
            if let data = try? await adminPostRaw(proxy: "player-proxy", body: body),
               let resp = try? JSONDecoder().decode(AdminPlayersResponse.self, from: data) {
                await MainActor.run { players = resp.players ?? [] }
            }
            await MainActor.run { isSearching = false }
        }
    }
}

// MARK: - Admin Player Editor

struct AdminPlayerEditorSheet: View {
    let player: AdminPlayerResult
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var level: String = ""
    @State private var totalXP: String = ""
    @State private var credits: String = ""
    @State private var isAdminToggle = false
    @State private var isBannedToggle = false
    @State private var isSaving = false
    @State private var saveResult: String?
    @State private var creditHistory: [AdminCreditTxn] = []
    @State private var showCreditHistory = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display Name", text: $displayName)
                    LabeledContent("CloudKit ID") {
                        Text(player.cloudkitUserId ?? "").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
                Section("Progression") {
                    numField("Level", text: $level)
                    numField("Total XP", text: $totalXP)
                    numField("GP Balance", text: $credits)
                }
                Section("Flags") {
                    Toggle("Admin", isOn: $isAdminToggle)
                    Toggle("Banned", isOn: $isBannedToggle)
                }
                Section("Credit History") {
                    Button { loadCreditHistory() } label: {
                        Label("View Credit History", systemImage: "clock.arrow.circlepath")
                    }
                    ForEach(creditHistory) { txn in
                        HStack {
                            Text(txn.transactionType ?? "unknown").font(.caption)
                            Spacer()
                            Text("\(txn.amount > 0 ? "+" : "")\(txn.amount)").font(.caption.monospacedDigit())
                                .foregroundColor(txn.amount >= 0 ? .green : .red)
                        }
                    }
                }
                if let result = saveResult {
                    Section { Text(result).font(.caption).foregroundColor(result.contains("Saved") ? .green : .red) }
                }
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving).foregroundColor(.orange)
                }
            }
        }
        .onAppear {
            displayName = player.displayName ?? ""
            level = "\(player.level ?? 1)"
            totalXP = "\(player.totalXP ?? 0)"
            credits = "\(player.systemCredits ?? 0)"
            isAdminToggle = player.isAdmin ?? false
            isBannedToggle = player.isBanned ?? false
        }
    }

    private func save() {
        isSaving = true
        Task {
            let body: [String: Any] = [
                "action": "admin_edit_player",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "target_cloudkit_user_id": player.cloudkitUserId ?? "",
                "display_name": displayName,
                "level": Int(level) ?? 1,
                "total_xp": Int(totalXP) ?? 0,
                "system_credits": Int(credits) ?? 0,
                "is_admin": isAdminToggle,
                "is_banned": isBannedToggle
            ]
            let ok = await adminPost(proxy: "player-proxy", body: body)
            await MainActor.run {
                isSaving = false
                saveResult = ok ? "Saved" : "Save failed"
            }
        }
    }

    private func loadCreditHistory() {
        Task {
            let body: [String: Any] = [
                "action": "admin_get_credit_history",
                "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
                "target_cloudkit_user_id": player.cloudkitUserId ?? ""
            ]
            if let data = try? await adminPostRaw(proxy: "player-proxy", body: body),
               let resp = try? JSONDecoder().decode(AdminCreditHistoryResponse.self, from: data) {
                await MainActor.run { creditHistory = resp.transactions ?? [] }
            }
        }
    }
}

// MARK: - Admin Helper Functions

private func adminPost(proxy: String, body: [String: Any]) async -> Bool {
    guard let data = try? await adminPostRaw(proxy: proxy, body: body) else { return false }
    let resp = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return resp?["success"] as? Bool == true
}

private func adminPostRaw(proxy: String, body: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/\(proxy)") else { throw URLError(.badURL) }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    req.timeoutInterval = 15
    let (data, _) = try await URLSession.shared.data(for: req)
    return data
}

@ViewBuilder
private func adminHeader(_ title: String) -> some View {
    Section {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill").foregroundColor(.orange)
            Text("ADMIN — \(title)")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange)
        }
    }
}

@ViewBuilder
private func numField(_ label: String, text: Binding<String>) -> some View {
    HStack {
        Text(label)
        Spacer()
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
    }
}

@ViewBuilder
private func errorSection(_ error: String?) -> some View {
    if let error = error {
        Section { Text(error).foregroundColor(.red).font(.caption) }
    }
}

// MARK: - Admin Models

struct AdminPlayerResult: Codable, Identifiable {
    let cloudkitUserId: String?
    let playerId: String?
    let displayName: String?
    let level: Int?
    let totalXP: Int?
    let isAdmin: Bool?
    let isBanned: Bool?
    let systemCredits: Int?
    let lifetimeCreditsEarned: Int?

    var id: String { cloudkitUserId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case cloudkitUserId = "cloudkit_user_id"
        case playerId = "player_id"
        case displayName = "display_name"
        case level
        case totalXP = "total_xp"
        case isAdmin = "is_admin"
        case isBanned = "is_banned"
        case systemCredits = "system_credits"
        case lifetimeCreditsEarned = "lifetime_credits_earned"
    }
}

struct AdminCreditTxn: Codable, Identifiable {
    let id: String?
    let amount: Int
    let balanceAfter: Int?
    let transactionType: String?
    let referenceKey: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, amount
        case balanceAfter = "balance_after"
        case transactionType = "transaction_type"
        case referenceKey = "reference_key"
        case createdAt = "created_at"
    }
}

private struct AdminPlayersResponse: Decodable { let players: [AdminPlayerResult]? }
private struct AdminCreditHistoryResponse: Decodable { let transactions: [AdminCreditTxn]? }
