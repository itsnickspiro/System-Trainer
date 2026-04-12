import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
import UIKit

struct PhotoMealLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var selectedImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var extractedText: String = ""
    /// Type-erased storage for `MealEstimate` (iOS 26+).
    @State private var estimate: Any? = nil
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var showingCamera = false

    // Editable fields so user can correct the AI before saving
    @State private var editName: String = ""
    @State private var editBrand: String = ""
    @State private var editCalories: Double = 0
    @State private var editProtein: Double = 0
    @State private var editCarbs: Double = 0
    @State private var editFat: Double = 0
    @State private var editFiber: Double = 0
    @State private var editSugar: Double = 0
    @State private var editSodium: Double = 0
    @State private var editServingGrams: Double = 100

    var selectedMeal: MealType = .snacks

    // Helper to extract confidence from type-erased MealEstimate (iOS 26+)
    private var estimateConfidence: Int? {
        if #available(iOS 26.0, *), let est = estimate as? MealEstimate { return est.confidence }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoArea

                    if isProcessing {
                        HStack(spacing: 10) {
                            ProgressView().tint(.cyan)
                            Text("Analyzing label…")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                                .tracking(1)
                        }
                        .padding(.vertical, 10)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }

                    if estimate != nil {
                        editableEstimateForm
                        saveButton
                    }
                }
                .padding()
            }
            .navigationTitle("Scan Nutrition Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { await loadSelectedPhoto(newItem) }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(image: $selectedImage, sourceType: .camera)
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    Task { await processImage(image) }
                }
            }
        }
    }

    private var photoArea: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.cyan.opacity(0.5), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 44, weight: .light))
                                .foregroundColor(.cyan)
                            Text("Point your camera at a nutrition label")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    )
            }

            HStack(spacing: 12) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
            .disabled(isProcessing)
        }
    }

    private var editableEstimateForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REVIEW & EDIT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .tracking(2)

            TextField("Food name", text: $editName)
                .textFieldStyle(.roundedBorder)
            TextField("Brand (optional)", text: $editBrand)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Serving size")
                Spacer()
                TextField("100", value: $editServingGrams, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .keyboardType(.decimalPad)
                Text("g").foregroundColor(.secondary)
            }

            macroField("Calories", value: $editCalories, unit: "kcal")
            macroField("Protein",  value: $editProtein, unit: "g")
            macroField("Carbs",    value: $editCarbs, unit: "g")
            macroField("Fat",      value: $editFat, unit: "g")
            macroField("Fiber",    value: $editFiber, unit: "g")
            macroField("Sugar",    value: $editSugar, unit: "g")
            macroField("Sodium",   value: $editSodium, unit: "mg")

            if let confidence = estimateConfidence, confidence < 60 {
                Label("AI confidence is low — double-check these values before saving.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
        }
    }

    private var saveButton: some View {
        Button(action: saveToLog) {
            Label("Save to Diary", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
        .disabled(editName.isEmpty || isProcessing)
    }

    // MARK: - Processing pipeline

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage = image
        }
    }

    private func processImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil
        estimate = nil

        do {
            let text = try await recognizeText(in: image)
            extractedText = text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIManagerError.generationFailed("No readable text found in the image.")
            }
            guard #available(iOS 26.0, *) else {
                throw AIManagerError.generationFailed("Nutrition label analysis requires iOS 26 or later.")
            }
            let parsed = try await AIManager.shared.parseNutritionLabel(text: text)
            estimate = parsed
            seedEditFields(from: parsed)
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    @available(iOS 26.0, *)
    private func seedEditFields(from est: MealEstimate) {
        editName = est.name
        editBrand = est.brand
        editCalories = Double(est.calories)
        editProtein = est.protein
        editCarbs = est.carbohydrates
        editFat = est.fat
        editFiber = est.fiber
        editSugar = est.sugar
        editSodium = est.sodium
        editServingGrams = est.servingGrams > 0 ? est.servingGrams : 100
    }

    private func saveToLog() {
        // Convert per-serving → per-100g by scaling.
        let grams = max(1, editServingGrams)
        let factor = 100.0 / grams
        let foodItem = FoodItem(
            name: editName.trimmingCharacters(in: .whitespaces),
            brand: editBrand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editBrand,
            barcode: nil,
            caloriesPer100g: editCalories * factor,
            servingSize: grams,
            carbohydrates: editCarbs * factor,
            protein: editProtein * factor,
            fat: editFat * factor,
            fiber: editFiber * factor,
            sugar: editSugar * factor,
            sodium: editSodium * factor,
            category: .other,
            isCustom: true
        )
        foodItem.dataSource = "ai_scan"
        context.insert(foodItem)

        let entry = FoodEntry(
            foodItem: foodItem,
            quantity: 1,
            unit: .servings,
            meal: selectedMeal,
            dateConsumed: Date()
        )
        context.insert(entry)
        try? context.save()

        DataManager.shared.updateProfile { profile in
            let goal = profile.fitnessGoal
            profile.recordMeal(healthiness: foodItem.mealHealthiness(for: goal))
        }
        _ = DataManager.shared.autoCompleteNutritionQuests()

        Task {
            await DataManager.shared.healthManager.saveMealSample(
                foodItem: foodItem,
                servingGrams: grams,
                date: Date()
            )
        }

        dismiss()
    }
}

// MARK: - UIKit camera wrapper

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .camera
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
