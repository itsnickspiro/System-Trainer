import SwiftUI
import AVFoundation

// MARK: - BarcodeScannerViewController

class BarcodeScannerViewController: UIViewController {
    weak var delegate: BarcodeScannerDelegate?

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureDevice: AVCaptureDevice?

    // UI Elements
    private let overlayView = UIView()
    private let scanAreaView = UIView()
    private let instructionLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .system)

    private var isFlashOn = false
    // When true, the next detected barcode fires the delegate once then stops
    private var isCapturePending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        checkCameraPermission()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanning()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopScanning()
        turnOffFlash()
    }

    // MARK: - Camera Permission

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if !granted { self?.showCameraPermissionAlert() }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert()
        @unknown default:
            showCameraPermissionAlert()
        }
    }

    private func showCameraPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Permission Required",
            message: "Please enable camera access in Settings to scan barcodes.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.delegate?.didCancel()
        })
        present(alert, animated: true)
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            delegate?.didEncounterError(BarcodeScannerError.cameraUnavailable)
            return
        }
        captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else {
                delegate?.didEncounterError(BarcodeScannerError.cannotAddInput)
                return
            }
            captureSession.addInput(input)
        } catch {
            delegate?.didEncounterError(error)
            return
        }

        // Use AVCaptureMetadataOutput for native barcode detection (no Vision/MLKit needed)
        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            delegate?.didEncounterError(BarcodeScannerError.cannotAddOutput)
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        // Support the common barcode types used on product packaging
        metadataOutput.metadataObjectTypes = [
            .ean13, .ean8, .upce,
            .code128, .code39, .code93,
            .pdf417, .qr
        ]

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Dark overlay behind scan area
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        // Scan area frame
        scanAreaView.layer.borderColor = UIColor.systemBlue.cgColor
        scanAreaView.layer.borderWidth = 2
        scanAreaView.layer.cornerRadius = 10
        scanAreaView.backgroundColor = .clear
        scanAreaView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanAreaView)

        // Corner accent lines inside the scan frame
        addCornerAccents(to: scanAreaView)

        // Instruction label
        instructionLabel.text = "Align barcode within the frame\nor tap Capture"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        // Cancel button — bottom left
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        cancelButton.layer.cornerRadius = 10
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Flash toggle button — bottom right
        flashButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        flashButton.layer.cornerRadius = 10
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        view.addSubview(flashButton)

        // Capture button — bottom centre, prominent
        captureButton.setImage(UIImage(systemName: "barcode.viewfinder"), for: .normal)
        captureButton.tintColor = .white
        captureButton.backgroundColor = UIColor.systemBlue
        captureButton.layer.cornerRadius = 32
        captureButton.imageView?.contentMode = .scaleAspectFit
        let captureSymbolConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        captureButton.setPreferredSymbolConfiguration(captureSymbolConfig, forImageIn: .normal)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            // Overlay fills the entire view
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Scan area: centred, slightly above middle
            scanAreaView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanAreaView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            scanAreaView.widthAnchor.constraint(equalToConstant: 280),
            scanAreaView.heightAnchor.constraint(equalToConstant: 130),

            // Instruction below the scan area
            instructionLabel.topAnchor.constraint(equalTo: scanAreaView.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Cancel — bottom left
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            // Flash — bottom right
            flashButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flashButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            flashButton.widthAnchor.constraint(equalToConstant: 64),
            flashButton.heightAnchor.constraint(equalToConstant: 44),

            // Capture — bottom centre
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 64),
            captureButton.heightAnchor.constraint(equalToConstant: 64),
        ])

        createOverlayCutout()
    }

    /// Draws short corner accent lines inside the scan frame for a viewfinder look.
    private func addCornerAccents(to containerView: UIView) {
        let length: CGFloat = 22
        let thickness: CGFloat = 3
        let radius: CGFloat = 10
        let color = UIColor.systemBlue

        let positions: [(Bool, Bool)] = [
            (false, false),
            (true, false),
            (false, true),
            (true, true)
        ]

        for (flipH, flipV) in positions {
            // Horizontal arm
            let h = UIView()
            h.backgroundColor = color
            h.layer.cornerRadius = thickness / 2
            h.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(h)

            // Vertical arm
            let v = UIView()
            v.backgroundColor = color
            v.layer.cornerRadius = thickness / 2
            v.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(v)

            NSLayoutConstraint.activate([
                h.widthAnchor.constraint(equalToConstant: length),
                h.heightAnchor.constraint(equalToConstant: thickness),
                flipH ? h.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -radius)
                       : h.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: radius),
                flipV ? h.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -(radius - thickness / 2))
                       : h.topAnchor.constraint(equalTo: containerView.topAnchor, constant: radius - thickness / 2),

                v.widthAnchor.constraint(equalToConstant: thickness),
                v.heightAnchor.constraint(equalToConstant: length),
                flipH ? v.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -(radius - thickness / 2))
                       : v.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: radius - thickness / 2),
                flipV ? v.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -radius)
                       : v.topAnchor.constraint(equalTo: containerView.topAnchor, constant: radius),
            ])
        }
    }

    private func createOverlayCutout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let path = UIBezierPath(rect: self.overlayView.bounds)
            let cutout = UIBezierPath(roundedRect: self.scanAreaView.frame, cornerRadius: 10)
            path.append(cutout)
            path.usesEvenOddFillRule = true
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            mask.fillRule = .evenOdd
            self.overlayView.layer.mask = mask
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        createOverlayCutout()
    }

    // MARK: - Session Control

    private func startScanning() {
        guard !(captureSession?.isRunning ?? false) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        guard captureSession?.isRunning ?? false else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    // MARK: - Button Actions

    @objc private func cancelTapped() {
        turnOffFlash()
        delegate?.didCancel()
    }

    /// Capture button: arms a one-shot capture — the next detected barcode fires the delegate.
    @objc private func captureTapped() {
        guard !isCapturePending else { return }
        isCapturePending = true

        // Animate the button to give tactile feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.captureButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.captureButton.backgroundColor = .systemBlue.withAlphaComponent(0.6)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.captureButton.transform = .identity
                self.captureButton.backgroundColor = .systemBlue
            }
        }

        instructionLabel.text = "Ready — align barcode to capture"
    }

    @objc private func flashTapped() {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if isFlashOn {
                device.torchMode = .off
                flashButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
                flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                flashButton.setImage(UIImage(systemName: "flashlight.on.fill"), for: .normal)
                flashButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.8)
            }
            isFlashOn.toggle()
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }

    private func turnOffFlash() {
        guard let device = captureDevice, device.hasTorch, isFlashOn else { return }
        try? device.lockForConfiguration()
        device.torchMode = .off
        device.unlockForConfiguration()
        isFlashOn = false
    }

    // MARK: - Barcode Handling

    private func handleDetected(code: String) {
        stopScanning()
        turnOffFlash()

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        showScanSuccessAnimation {
            self.delegate?.didScanBarcode(code)
        }
    }

    private func showScanSuccessAnimation(completion: @escaping () -> Void) {
        scanAreaView.layer.borderColor = UIColor.systemGreen.cgColor
        scanAreaView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)

        UIView.animate(withDuration: 0.2, animations: {
            self.scanAreaView.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                self.scanAreaView.transform = .identity
                self.scanAreaView.backgroundColor = .clear
            }) { _ in
                completion()
            }
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension BarcodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let code = readableObject.stringValue else { return }

        // Auto-detect: fire immediately without needing capture button press
        // If capture mode is armed, also fire
        guard !isCapturePending else {
            isCapturePending = false
            handleDetected(code: code)
            return
        }

        // Normal continuous mode: fire on first detection
        handleDetected(code: code)
    }
}

// MARK: - BarcodeScannerDelegate

protocol BarcodeScannerDelegate: AnyObject {
    func didCancel()
    func didEncounterError(_ error: Error)
    func didScanBarcode(_ code: String)
}

// MARK: - BarcodeScannerError

enum BarcodeScannerError: LocalizedError {
    case noCameraAvailable
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case scanningFailed

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable, .cameraUnavailable:
            return "Camera is not available on this device."
        case .cannotAddInput:
            return "Cannot add camera input to capture session."
        case .cannotAddOutput:
            return "Cannot add video output to capture session."
        case .scanningFailed:
            return "Barcode scanning failed. Please try again."
        }
    }
}

// MARK: - SwiftUI Wrapper

struct BarcodeScanner: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onBarcodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}

    class Coordinator: NSObject, BarcodeScannerDelegate {
        let parent: BarcodeScanner

        init(_ parent: BarcodeScanner) {
            self.parent = parent
        }

        func didCancel() {
            DispatchQueue.main.async { self.parent.isPresented = false }
        }

        func didEncounterError(_ error: Error) {
            DispatchQueue.main.async { self.parent.isPresented = false }
        }

        func didScanBarcode(_ code: String) {
            DispatchQueue.main.async {
                self.parent.onBarcodeScanned(code)
                self.parent.isPresented = false
            }
        }
    }
}
