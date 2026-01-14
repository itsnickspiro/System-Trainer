import SwiftUI
import Combine
import AVFoundation

// MARK: - BarcodeScannerViewController

// Stub types to replace missing Barcode, BarcodeFormat, and VisionImage
// TODO: Replace with actual barcode detection implementation using Vision/MLKit or similar
struct Barcode {
    let rawValue: String?
    let format: BarcodeFormat
}

enum BarcodeFormat: Equatable {
    case EAN13, EAN8, UPCA, UPCE, code128, code39, code93
}

struct VisionImage {
    let buffer: CMSampleBuffer
    var orientation: UIImage.Orientation = .up
    init(buffer: CMSampleBuffer) {
        self.buffer = buffer
    }
}

// MARK: - BarcodeScannerViewController

class BarcodeScannerViewController: UIViewController {
    weak var delegate: BarcodeScannerDelegate?

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // UI Elements
    private let overlayView = UIView()
    private let scanAreaView = UIView()
    private let instructionLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)

    private var isFlashOn = false

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
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break // Already have permission
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if !granted {
                        self?.showCameraPermissionAlert()
                    }
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
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.delegate?.didCancel()
        })

        present(alert, animated: true)
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didEncounterError(BarcodeScannerError.cameraUnavailable)
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.didEncounterError(error)
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            delegate?.didEncounterError(BarcodeScannerError.cannotAddInput)
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            delegate?.didEncounterError(BarcodeScannerError.cannotAddOutput)
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    private func setupUI() {
        // Setup overlay
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        // Setup scan area
        scanAreaView.layer.borderColor = UIColor.systemBlue.cgColor
        scanAreaView.layer.borderWidth = 2
        scanAreaView.layer.cornerRadius = 8
        scanAreaView.backgroundColor = UIColor.clear
        scanAreaView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanAreaView)

        // Setup instruction label
        instructionLabel.text = "Position barcode within the frame"
        instructionLabel.textColor = UIColor.white
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        // Setup cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        cancelButton.layer.cornerRadius = 8
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Setup flash button
        let flashImage = UIImage(systemName: "flashlight.off.fill")
        flashButton.setImage(flashImage, for: .normal)
        flashButton.tintColor = UIColor.white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        flashButton.layer.cornerRadius = 8
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        view.addSubview(flashButton)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Overlay fills entire view
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Scan area centered
            scanAreaView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanAreaView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            scanAreaView.widthAnchor.constraint(equalToConstant: 280),
            scanAreaView.heightAnchor.constraint(equalToConstant: 120),

            // Instruction label above scan area
            instructionLabel.bottomAnchor.constraint(equalTo: scanAreaView.topAnchor, constant: -20),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Cancel button at bottom left
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            // Flash button at bottom right
            flashButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flashButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Create cutout in overlay for scan area
        createOverlayCutout()
    }

    private func createOverlayCutout() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let path = UIBezierPath(rect: self.overlayView.bounds)
            let cutoutPath = UIBezierPath(
                roundedRect: self.scanAreaView.frame,
                cornerRadius: 8
            )
            path.append(cutoutPath)
            path.usesEvenOddFillRule = true

            let maskLayer = CAShapeLayer()
            maskLayer.path = path.cgPath
            maskLayer.fillRule = .evenOdd
            self.overlayView.layer.mask = maskLayer
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        createOverlayCutout()
    }

    private func startScanning() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    @objc private func cancelTapped() {
        delegate?.didCancel()
    }

    @objc private func flashTapped() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()

            if isFlashOn {
                device.torchMode = .off
                flashButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
            } else {
                device.torchMode = .on
                flashButton.setImage(UIImage(systemName: "flashlight.on.fill"), for: .normal)
            }

            isFlashOn.toggle()
            device.unlockForConfiguration()
        } catch {
            print("Flash could not be used: \(error)")
        }
    }

    private func processBarcode(_ barcode: Barcode) {
        guard let rawValue = barcode.rawValue else { return }

        // Validate barcode format
        let validFormats: [BarcodeFormat] = [.EAN13, .EAN8, .UPCA, .UPCE, .code128, .code39, .code93]
        guard validFormats.contains(barcode.format) else { return }

        // Stop scanning and notify delegate
        stopScanning()

        DispatchQueue.main.async { [weak self] in
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            // Visual feedback
            self?.showScanSuccessAnimation {
                self?.delegate?.didScanBarcode(rawValue)
            }
        }
    }

    private func showScanSuccessAnimation(completion: @escaping () -> Void) {
        // Flash the scan area green briefly
        scanAreaView.layer.borderColor = UIColor.systemGreen.cgColor
        scanAreaView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.2)

        UIView.animate(withDuration: 0.3, animations: {
            self.scanAreaView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                self.scanAreaView.transform = .identity
                self.scanAreaView.backgroundColor = UIColor.clear
            }) { _ in
                completion()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension BarcodeScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // TODO: Implement barcode detection with Vision or MLKit here
        // For now, no barcode detection - skip processing

        // Example stub: simulate no barcodes detected
        // If implementing, call processBarcode(_:) on detection

        // If error occurs, call delegate?.didEncounterError(error)
    }
}

// MARK: - BarcodeScannerDelegate

protocol BarcodeScannerDelegate: AnyObject {
    func didCancel()
    func didEncounterError(_ error: Error)
    func didScanBarcode(_ code: String)
}

// MARK: - Barcode Scanner Errors

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

// MARK: - SwiftUI Integration

struct BarcodeScanner: View {
    @Binding var isPresented: Bool
    let onBarcodeScanned: (String) -> Void

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        // BarcodeScannerView removed, so show placeholder text
        Text("Barcode scanner unavailable")
            .foregroundColor(.secondary)
            .font(.headline)
            .onAppear {
                // Optionally dismiss or handle as needed
            }
    }
}

