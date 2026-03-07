import SwiftUI
import AVFoundation
import SwiftData
import HealthKit

// MARK: - ItemScannerView

struct ItemScannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var scannedBarcode: String? = nil
    @State private var scannerState: ScannerState = .scanning
    @State private var analyzedItem: FoodItem? = nil
    @State private var aiVerdict: FoodItemFlavorText? = nil
    @State private var showResultSheet = false
    @State private var errorMessage: String? = nil
    @State private var torchOn = false
    @State private var pulseAnimation = false

    enum ScannerState {
        case scanning
        case decrypting
        case ready
        case error(String)
    }

    var body: some View {
        ZStack {
            // Camera feed
            ScannerCameraView(
                torchOn: $torchOn,
                onBarcodeDetected: handleBarcode
            )
            .ignoresSafeArea()

            // Dark vignette overlay
            RadialGradient(
                colors: [.clear, .black.opacity(0.6)],
                center: .center,
                startRadius: 160,
                endRadius: 340
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Reticle + status
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    Text("ITEM SCANNER")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .tracking(3)

                    Spacer()

                    Button(action: { torchOn.toggle() }) {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(torchOn ? .yellow : .white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Reticle
                ReticleView(state: $scannerState, pulseAnimation: $pulseAnimation)
                    .frame(width: 260, height: 180)

                Spacer()

                // Status label
                statusLabel
                    .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showResultSheet, onDismiss: resetScanner) {
            if let item = analyzedItem {
                ItemResultSheet(
                    foodItem: item,
                    verdict: aiVerdict,
                    barcode: scannedBarcode ?? ""
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    // MARK: - Status Label

    @ViewBuilder
    private var statusLabel: some View {
        switch scannerState {
        case .scanning:
            Text("Align barcode within the reticle")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(1)

        case .decrypting:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(0.8)
                Text("Decrypting Consumable...")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .tracking(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

        case .error(let msg):
            VStack(spacing: 6) {
                Text("SCAN FAILED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
                    .tracking(3)
                Text(msg)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

        case .ready:
            EmptyView()
        }
    }

    // MARK: - Barcode Handling

    private func handleBarcode(_ barcode: String) {
        guard case .scanning = scannerState else { return }

        // Heavy haptic on lock
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        scannedBarcode = barcode
        scannerState = .decrypting

        Task {
            do {
                // 1. Fetch product data from existing FoodDatabaseService (returns FoodItem directly)
                guard let foodItem = try await FoodDatabaseService.shared.searchFoodByBarcode(barcode) else {
                    await MainActor.run {
                        scannerState = .error("Product not found in database.")
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await MainActor.run { resetScanner() }
                        }
                    }
                    return
                }

                // 2. Request AI analysis
                let verdict = try? await AIManager.shared.analyzeFood(foodItem)

                await MainActor.run {
                    analyzedItem = foodItem
                    aiVerdict = verdict
                    scannerState = .ready
                    showResultSheet = true
                }
            } catch {
                await MainActor.run {
                    scannerState = .error(error.localizedDescription)
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run { resetScanner() }
                    }
                }
            }
        }
    }

    private func resetScanner() {
        scannerState = .scanning
        scannedBarcode = nil
        analyzedItem = nil
        aiVerdict = nil
    }
}

// MARK: - Reticle View

private struct ReticleView: View {
    @Binding var state: ItemScannerView.ScannerState
    @Binding var pulseAnimation: Bool

    private var isDecrypting: Bool {
        if case .decrypting = state { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Background tint
            RoundedRectangle(cornerRadius: 16)
                .fill(.cyan.opacity(isDecrypting ? 0.08 : 0.04))

            // Corner brackets
            CornerBracketsShape()
                .stroke(
                    isDecrypting ? Color.cyan : Color.cyan.opacity(0.8),
                    lineWidth: 2.5
                )

            // Glow ring when decrypting
            if isDecrypting {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.cyan.opacity(pulseAnimation ? 0.6 : 0.2), lineWidth: 1)
                    .scaleEffect(pulseAnimation ? 1.02 : 0.98)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
            }

            // Scan line
            ScanLineView(animating: !isDecrypting)
        }
    }
}

// MARK: - Corner Brackets Shape

private struct CornerBracketsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 24
        let radius: CGFloat = 12
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // Top-left
            (CGPoint(x: rect.minX + length, y: rect.minY + radius),
             CGPoint(x: rect.minX + radius, y: rect.minY + radius),
             CGPoint(x: rect.minX + radius, y: rect.minY + length)),
            // Top-right
            (CGPoint(x: rect.maxX - length, y: rect.minY + radius),
             CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
             CGPoint(x: rect.maxX - radius, y: rect.minY + length)),
            // Bottom-left
            (CGPoint(x: rect.minX + length, y: rect.maxY - radius),
             CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
             CGPoint(x: rect.minX + radius, y: rect.maxY - length)),
            // Bottom-right
            (CGPoint(x: rect.maxX - length, y: rect.maxY - radius),
             CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
             CGPoint(x: rect.maxX - radius, y: rect.maxY - length))
        ]
        for (start, corner, end) in corners {
            path.move(to: start)
            path.addQuadCurve(to: end, control: corner)
        }
        return path
    }
}

// MARK: - Scan Line

private struct ScanLineView: View {
    let animating: Bool
    @State private var offset: CGFloat = -80

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .cyan.opacity(0.8), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                guard animating else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                    offset = 80
                }
            }
            .onChange(of: animating) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                        offset = 80
                    }
                } else {
                    offset = 0
                }
            }
    }
}

// MARK: - Camera View (UIViewControllerRepresentable)

struct ScannerCameraView: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    let onBarcodeDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeDetected: onBarcodeDetected)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.setTorch(on: torchOn)
    }
}

// MARK: - Scanner View Controller

final class ScannerViewController: UIViewController {
    var coordinator: ScannerCameraView.Coordinator?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = currentVideoRotationAngle()
        }
    }

    private func setupSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else { return }
        session.addOutput(metadataOutput)

        // Only supported barcode types
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        let supportedTypes: [AVMetadataObject.ObjectType] = [
            .ean13, .ean8, .upce, .code128, .qr
        ]
        metadataOutput.metadataObjectTypes = supportedTypes.filter {
            metadataOutput.availableMetadataObjectTypes.contains($0)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func resumeScanning() {
        isProcessing = false
    }

    private func currentVideoRotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .landscapeLeft:   return 0
        case .landscapeRight:  return 180
        case .portraitUpsideDown: return 270
        default:               return 90
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjects Delegate

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing else { return }
        guard let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = metadata.stringValue,
              !barcode.isEmpty else { return }

        isProcessing = true
        coordinator?.onBarcodeDetected(barcode)
    }
}

// MARK: - Coordinator

extension ScannerCameraView {
    final class Coordinator {
        let onBarcodeDetected: (String) -> Void

        init(onBarcodeDetected: @escaping (String) -> Void) {
            self.onBarcodeDetected = onBarcodeDetected
        }
    }
}

// MARK: - Item Result Sheet

struct ItemResultSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let foodItem: FoodItem
    let verdict: FoodItemFlavorText?
    let barcode: String

    @State private var servingSize: Double = 100.0
    @State private var selectedMeal: MealType = .snacks
    @State private var saveSuccess = false

    private let healthStore = HKHealthStore()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header pill
                    HStack {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(width: 40, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                    // Product name + rarity badge
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verdict?.itemName ?? foodItem.name)
                                    .font(.system(size: 22, weight: .bold, design: .default))
                                    .foregroundStyle(.white)

                                if let brand = foodItem.brand {
                                    Text(brand.uppercased())
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .tracking(2)
                                }
                            }
                            Spacer()
                            if let rarity = verdict?.rarity {
                                RarityBadge(rarity: rarity)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Divider
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)

                    // Macro breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NUTRITIONAL DATA / 100G")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                            .tracking(3)
                            .padding(.horizontal, 24)

                        MacroGrid(foodItem: foodItem)
                            .padding(.horizontal, 24)
                    }

                    // AI System Verdict
                    if let verdict = verdict {
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle()
                                .fill(.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.vertical, 20)
                                .padding(.horizontal, 24)

                            Text("SYSTEM VERDICT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.7))
                                .tracking(3)
                                .padding(.horizontal, 24)

                            Text("\"\(verdict.analysis)\"")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundStyle(.white.opacity(0.85))
                                .italic()
                                .padding(.horizontal, 24)

                            if !verdict.statEffect.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.cyan)
                                    Text(verdict.statEffect)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.cyan.opacity(0.8))
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 2)
                            }
                        }
                    }

                    // Consume controls
                    VStack(spacing: 16) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.vertical, 20)

                        // Serving size stepper
                        HStack {
                            Text("SERVING (G)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(2)
                            Spacer()
                            HStack(spacing: 16) {
                                Button(action: { servingSize = max(10, servingSize - 10) }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.cyan)
                                }
                                Text("\(Int(servingSize))g")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 52)
                                Button(action: { servingSize = min(2000, servingSize + 10) }) {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Meal picker
                        HStack {
                            Text("MEAL")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(2)
                            Spacer()
                            Picker("Meal", selection: $selectedMeal) {
                                ForEach(MealType.allCases, id: \.self) { meal in
                                    Text(meal.rawValue.capitalized).tag(meal)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                        }
                        .padding(.horizontal, 24)

                        // Calories preview
                        let estimatedCalories = (foodItem.caloriesPer100g * servingSize) / 100.0
                        Text("≈ \(Int(estimatedCalories)) kcal for \(Int(servingSize))g serving")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)

                        // Consume button
                        Button(action: consumeItem) {
                            HStack(spacing: 10) {
                                if saveSuccess {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("CONSUMED")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .tracking(3)
                                } else {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("CONSUME ITEM")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .tracking(3)
                                }
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(saveSuccess ? Color.green : Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(saveSuccess)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            servingSize = foodItem.servingSize > 0 ? foodItem.servingSize : 100.0
        }
    }

    // MARK: - Consume Item

    private func consumeItem() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Persist FoodItem if not already in the store (check by barcode)
        var persistedItem: FoodItem
        if let existing = existingFoodItem(barcode: barcode) {
            persistedItem = existing
        } else {
            context.insert(foodItem)
            persistedItem = foodItem
        }

        // Create FoodEntry
        let entry = FoodEntry(
            foodItem: persistedItem,
            quantity: servingSize,
            unit: .grams,
            meal: selectedMeal,
            dateConsumed: Date(),
            notes: nil
        )
        context.insert(entry)
        try? context.save()

        // Write to HealthKit
        writeToHealthKit(servingGrams: servingSize)

        saveSuccess = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Auto-dismiss after brief success flash
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { dismiss() }
        }
    }

    private func existingFoodItem(barcode: String) -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.barcode == barcode }
        )
        return try? context.fetch(descriptor).first
    }

    private func writeToHealthKit(servingGrams: Double) {
        let factor = servingGrams / 100.0
        let now = Date()

        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal)
        ]

        healthStore.requestAuthorization(toShare: writeTypes, read: nil) { granted, _ in
            guard granted else { return }

            var samples: [HKQuantitySample] = []

            let cal = foodItem.caloriesPer100g * factor
            if cal > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.dietaryEnergyConsumed),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: cal),
                    start: now, end: now
                ))
            }

            let pro = foodItem.protein * factor
            if pro > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.dietaryProtein),
                    quantity: HKQuantity(unit: .gram(), doubleValue: pro),
                    start: now, end: now
                ))
            }

            let carb = foodItem.carbohydrates * factor
            if carb > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.dietaryCarbohydrates),
                    quantity: HKQuantity(unit: .gram(), doubleValue: carb),
                    start: now, end: now
                ))
            }

            let fat = foodItem.fat * factor
            if fat > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.dietaryFatTotal),
                    quantity: HKQuantity(unit: .gram(), doubleValue: fat),
                    start: now, end: now
                ))
            }

            guard !samples.isEmpty else { return }
            healthStore.save(samples) { _, _ in }
        }
    }
}

// MARK: - Macro Grid

private struct MacroGrid: View {
    let foodItem: FoodItem

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 10) {
            MacroCell(label: "KCAL", value: foodItem.caloriesPer100g, unit: "", color: .orange)
            MacroCell(label: "PROTEIN", value: foodItem.protein, unit: "g", color: .cyan)
            MacroCell(label: "CARBS", value: foodItem.carbohydrates, unit: "g", color: .yellow)
            MacroCell(label: "FAT", value: foodItem.fat, unit: "g", color: .purple)
            MacroCell(label: "FIBER", value: foodItem.fiber, unit: "g", color: .green)
            MacroCell(label: "SUGAR", value: foodItem.sugar, unit: "g", color: .red.opacity(0.8))
            MacroCell(label: "SODIUM", value: foodItem.sodium * 1000, unit: "mg", color: .white.opacity(0.6))
        }
    }
}

private struct MacroCell: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
            Text(value > 0 ? (unit.isEmpty ? "\(Int(value))" : String(format: "%.1f\(unit)", value)) : "—")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Rarity Badge

private struct RarityBadge: View {
    let rarity: String

    private var color: Color {
        switch rarity.lowercased() {
        case "legendary": return .yellow
        case "epic":      return .purple
        case "rare":      return .cyan
        case "uncommon":  return .green
        default:          return .white.opacity(0.5)
        }
    }

    var body: some View {
        Text(rarity.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Flow Layout (simple horizontal wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
