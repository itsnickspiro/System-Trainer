import SwiftUI
import PhotosUI
import UIKit

/// In-app bug reporter. Captures a description, optional screenshot, and
/// device/version metadata, then POSTs to bug-reports-proxy submit_in_app.
/// The captured row is picked up every 4 hours by the auto-triage Claude
/// Code cron and either auto-fixed via PR or commented for human review.
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var description: String = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var screenshotImage: UIImage? = nil
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var submitSuccess = false

    private var canSubmit: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 && !isSubmitting && !submitSuccess
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private var deviceModel: String { UIDevice.current.model }
    private var osVersion: String { UIDevice.current.systemVersion }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero
                    headerCard

                    // Description
                    descriptionBlock

                    // Screenshot picker
                    screenshotBlock

                    // Device info preview
                    deviceInfoCard

                    if submitSuccess {
                        successCard
                    } else if let err = submitError {
                        errorCard(err)
                    }
                }
                .padding()
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await submit() } }
                            .disabled(!canSubmit)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
        }
    }

    // MARK: - Sub-views

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ant.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.cyan)
                Text("【SYSTEM REPORT】")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.cyan)
                    .tracking(2)
            }
            Text("Describe what went wrong, what you expected, and any steps to reproduce. Attaching a screenshot helps a lot.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT HAPPENED")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $description)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.gray.opacity(0.3), lineWidth: 1)
                    )
                if description.isEmpty {
                    Text("e.g. \"When I scanned a Chipotle receipt, the photo scanner crashed back to Home.\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                Text("\(description.count) / 2000")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(description.count < 10 ? .orange : .secondary)
            }
        }
    }

    private var screenshotBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCREENSHOT (OPTIONAL)")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            HStack(spacing: 12) {
                if let image = screenshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.cyan.opacity(0.5), lineWidth: 1)
                        )
                    Button(role: .destructive) {
                        screenshotImage = nil
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Add screenshot", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.cyan.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATTACHED METADATA")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            VStack(alignment: .leading, spacing: 3) {
                metaRow("App Version", "\(appVersion) (\(buildNumber))")
                metaRow("Device", deviceModel)
                metaRow("iOS", osVersion)
                metaRow("User ID", String((LeaderboardService.shared.currentUserID ?? "anonymous").prefix(12)) + "…")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key.uppercased())
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
    }

    private var successCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
            Text("The System has received your report. Closing…")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't send report")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Async actions

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run { screenshotImage = image }
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        var body: [String: Any] = [
            "action": "submit_in_app",
            "cloudkit_user_id": LeaderboardService.shared.currentUserID ?? "",
            "app_version": appVersion,
            "build_number": buildNumber,
            "device_model": deviceModel,
            "os_version": osVersion,
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        if let image = screenshotImage,
           let jpeg = image.jpegData(compressionQuality: 0.7) {
            body["screenshot_base64"] = jpeg.base64EncodedString()
        }

        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/bug-reports-proxy") else {
            submitError = "Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30 // screenshots can be slow on weak connections

        do {
            let (data, response) = try await PinnedURLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                submitError = "Server returned HTTP \(code). Try again later."
                return
            }
            // Decode as a flexible dictionary so we don't have to spell out the schema
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["success"] as? Bool == true {
                submitSuccess = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { dismiss() }
            } else {
                let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Unknown error"
                submitError = errMsg
            }
        } catch {
            submitError = error.localizedDescription
        }
    }
}
