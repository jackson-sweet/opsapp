// OPS/OPS/DeckBuilder/Views/SketchCaptureView.swift

import SwiftUI
import VisionKit
import UIKit
import PhotosUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

// MARK: - DocumentScannerView (VisionKit Wrapper)

/// Wraps Apple's `VNDocumentCameraViewController` for capturing a hand-drawn sketch.
/// Provides auto-crop and perspective correction via the document scanner.
/// Returns the first scanned page only — deck sketches are single-page.
struct SketchDocumentScannerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = ManualSketchCaptureVC()
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        vc.onError = onError
        let nav = UINavigationController(rootViewController: vc)
        nav.isNavigationBarHidden = true
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - Manual Capture Camera (AVCaptureSession + shutter button)

private class ManualSketchCaptureVC: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var shutterButton: UIButton?
    private weak var shutterInnerCircle: UIView?
    private weak var statusLabel: UILabel?
    private var isCapturing = false  // guards against rapid multi-tap firing multiple captures

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onError?(NSError(domain: "SketchCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera not available"]))
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    private func setupUI() {
        let label = UILabel()
        label.text = "FRAME YOUR SKETCH  ·  TAP SHUTTER WHEN READY"
        label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        statusLabel = label

        let shutter = UIButton(type: .system)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        let outerSize: CGFloat = 72
        let innerSize: CGFloat = 58
        shutter.backgroundColor = .clear
        shutter.layer.cornerRadius = outerSize / 2
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.cgColor

        let innerCircle = UIView()
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = innerSize / 2
        innerCircle.isUserInteractionEnabled = false
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        shutter.addSubview(innerCircle)

        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutter)
        shutterButton = shutter
        shutterInnerCircle = innerCircle

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cancel.setTitleColor(.white, for: .normal)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            shutter.widthAnchor.constraint(equalToConstant: outerSize),
            shutter.heightAnchor.constraint(equalToConstant: outerSize),

            innerCircle.centerXAnchor.constraint(equalTo: shutter.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: innerSize),
            innerCircle.heightAnchor.constraint(equalToConstant: innerSize),

            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancel.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
        ])
    }

    @objc private func shutterTapped() {
        // Root cause of Jackson's "takes multiple scans much too quickly": rapid taps
        // fired multiple capturePhoto calls in flight. Guard with isCapturing flag.
        guard !isCapturing else { return }
        isCapturing = true
        shutterButton?.isEnabled = false
        shutterInnerCircle?.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        statusLabel?.text = "CAPTURING…"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.resetShutter()
                self.onError?(error)
            }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.resetShutter()
                self.onError?(NSError(domain: "SketchCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not process photo"]))
            }
            return
        }

        Task { @MainActor in
            self.statusLabel?.text = "PROCESSING…"
            let corrected = await SketchPerspectiveCorrector.perspectiveCorrect(image: image)
            self.onCapture?(corrected)
            // Shutter stays disabled — view is dismissing to review screen
        }
    }

    @MainActor
    private func resetShutter() {
        isCapturing = false
        shutterButton?.isEnabled = true
        shutterInnerCircle?.backgroundColor = .white
        statusLabel?.text = "FRAME YOUR SKETCH  ·  TAP SHUTTER WHEN READY"
    }
}

// MARK: - PhotoLibraryPicker (PHPicker Wrapper)

/// Wraps `PHPickerViewController` for selecting an existing photo of a hand-drawn sketch.
/// Configured for single image selection only.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onCancel()
                return
            }

            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onCancel()
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self?.parent.onPick(image)
                    } else {
                        self?.parent.onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Perspective Correction

/// Runs Vision document segmentation on a photo-library image to auto-crop and
/// perspective-correct the sketch, matching the quality of VNDocumentCamera output.
private enum SketchPerspectiveCorrector {

    /// Detects a document in the image and applies perspective correction.
    /// If no document is detected or processing fails, returns the original image unchanged.
    static func perspectiveCorrect(image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return image
        }

        guard let observation = request.results?.first as? VNRectangleObservation else {
            return image
        }

        // Convert Vision normalized coordinates to CIImage pixel coordinates
        let ciImage = CIImage(cgImage: cgImage)
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height

        let topLeft = CGPoint(
            x: observation.topLeft.x * imageWidth,
            y: observation.topLeft.y * imageHeight
        )
        let topRight = CGPoint(
            x: observation.topRight.x * imageWidth,
            y: observation.topRight.y * imageHeight
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * imageWidth,
            y: observation.bottomLeft.y * imageHeight
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * imageWidth,
            y: observation.bottomRight.y * imageHeight
        )

        // Calculate the output dimensions from the detected quad
        let outputWidth = max(
            hypot(topRight.x - topLeft.x, topRight.y - topLeft.y),
            hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y)
        )
        let outputHeight = max(
            hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y),
            hypot(topRight.x - bottomRight.x, topRight.y - bottomRight.y)
        )

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return image
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let outputCIImage = filter.outputImage else {
            return image
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else {
            return image
        }

        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - ScanProgressBar

/// Custom progress bar matching OPS design system.
/// Background: cardBackground. Fill: primaryAccent. Animates width based on progress.
private struct ScanProgressBar: View {
    let progress: Double

    private let barHeight: CGFloat = 6
    private let barCornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .frame(height: barHeight)

                // Fill
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(
                        width: max(0, geometry.size.width * CGFloat(min(max(progress, 0), 1))),
                        height: barHeight
                    )
                    .animation(OPSStyle.Animation.standard, value: progress)
            }
        }
        .frame(height: barHeight)
    }
}

// MARK: - SketchCaptureView

/// The main capture view for the scan-paper-sketch feature.
/// Presented as `.fullScreenCover` from the creation picker.
///
/// Flow:
/// 1. Shows a choice screen: "Scan with Camera" or "Choose from Library"
/// 2. Camera path: opens VisionKit document scanner (auto-crop + perspective correction)
/// 3. Library path: opens PHPicker, then runs Vision document segmentation for perspective correction
/// 4. On capture, runs `SketchScanPipeline` and shows processing progress
/// 5. On success, presents `SketchCleanupView` for edge cleanup and dimension review
/// 6. On failure, shows retry/cancel options
struct SketchCaptureView: View {
    // MARK: - Properties

    let projectId: String?
    let companyId: String
    let userId: String?
    let onComplete: (SketchScanResult) -> Void

    // MARK: - State

    @StateObject private var pipeline = SketchScanPipeline()
    @State private var capturedImage: UIImage?
    @State private var showingDocumentScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingCleanup = false
    @State private var scannerError: String?
    @State private var isProcessingLibraryImage = false
    @State private var hasUserConfirmedCapture = false   // gate: pipeline runs only after explicit "Use this"
    @Environment(\.dismiss) private var dismiss

    // MARK: - Haptic Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let errorNotification = UINotificationFeedbackGenerator()

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            if capturedImage == nil && !isProcessingLibraryImage {
                choiceScreen
            } else if isProcessingLibraryImage {
                processingLibraryLayer
            } else if capturedImage != nil && !hasUserConfirmedCapture && pipeline.stage == .idle {
                // Review-before-process gate: user sees what was captured and confirms
                reviewScreen
            } else if capturedImage != nil && hasUserConfirmedCapture && pipeline.stage != .complete && pipeline.stage != .failed {
                processingLayer
            } else if pipeline.stage == .failed {
                errorLayer
            } else if pipeline.stage == .complete && pipeline.result != nil {
                Color.clear
            }
        }
        .onChange(of: capturedImage) { _, image in
            // Capture no longer auto-starts the pipeline. User must tap "Use This Scan" on the
            // review screen. Prevents pipeline from firing on blurry/wrong frames.
            guard image != nil else { return }
            hasUserConfirmedCapture = false
        }
        .onChange(of: pipeline.stage) { oldValue, newValue in
            handleStageChange(from: oldValue, to: newValue)
        }
        .fullScreenCover(isPresented: $showingDocumentScanner) {
            SketchDocumentScannerView(
                onCapture: { image in
                    showingDocumentScanner = false
                    capturedImage = image
                },
                onCancel: {
                    showingDocumentScanner = false
                },
                onError: { error in
                    showingDocumentScanner = false
                    scannerError = error.localizedDescription
                    self.pipeline.error = error.localizedDescription
                    self.pipeline.stage = .failed
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoLibraryPicker(
                onPick: { image in
                    showingPhotoPicker = false
                    isProcessingLibraryImage = true
                    Task {
                        let corrected = await SketchPerspectiveCorrector.perspectiveCorrect(image: image)
                        await MainActor.run {
                            isProcessingLibraryImage = false
                            capturedImage = corrected
                        }
                    }
                },
                onCancel: {
                    showingPhotoPicker = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingCleanup) {
            if let scanResult = pipeline.result {
                SketchCleanupView(
                    scanResult: scanResult,
                    projectId: projectId,
                    companyId: companyId,
                    userId: userId
                ) { finalResult in
                    showingCleanup = false
                    onComplete(finalResult)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Choice Screen

    /// Two large buttons: "Scan with Camera" and "Choose from Library", plus a Cancel text button.
    private var choiceScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            Text("Scan Paper Sketch")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.bottom, OPSStyle.Layout.spacing5)

            // Buttons
            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Scan with Camera
                Button {
                    lightImpact.impactOccurred()
                    showingDocumentScanner = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                        Text("Scan with Camera")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .fill(OPSStyle.Colors.primaryAccent)
                    )
                }

                // Choose from Library
                Button {
                    lightImpact.impactOccurred()
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                        Text("Choose from Library")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)

            Spacer()

            // Cancel
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
            }
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    // MARK: - Review Screen (preview → confirm)

    /// Shown after capture (camera or library). User sees the perspective-corrected image
    /// and must explicitly tap "Use This Scan" before we run the pipeline. A "Retake"
    /// option sends them back to the scanner. This is the fix for Jackson's "takes multiple
    /// scans much too quickly" — capture is now a two-step confirmed action, never automatic.
    @ViewBuilder
    private var reviewScreen: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review Scan")
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.top, OPSStyle.Layout.spacing4)

            // Image preview
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OPSStyle.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(OPSStyle.Layout.spacing4)
            }

            // Guidance
            Text("Make sure the sketch is clear, flat, and fully in frame. If anything is blurry or cut off, retake.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Actions
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Button {
                    lightImpact.impactOccurred()
                    hasUserConfirmedCapture = true
                    guard let image = capturedImage else { return }
                    Task { await pipeline.process(image: image) }
                } label: {
                    Text("Use This Scan")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }

                Button {
                    lightImpact.impactOccurred()
                    capturedImage = nil
                    hasUserConfirmedCapture = false
                    showingDocumentScanner = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("Retake")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    // MARK: - Processing Library Image Layer

    /// Shown while the photo-library image is being perspective-corrected via Vision.
    private var processingLibraryLayer: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)

            Text("Preparing image...")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Detecting and correcting sketch perspective")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing5)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        )
    }

    // MARK: - Processing Layer

    /// Shows a thumbnail of the captured sketch at reduced opacity with a centered progress card.
    private var processingLayer: some View {
        ZStack {
            // Captured image thumbnail at 30% opacity as background context
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.3)
                    .ignoresSafeArea()
            }

            // Dark overlay for readability
            OPSStyle.Colors.background.opacity(0.6)
                .ignoresSafeArea()

            // Progress card
            VStack(spacing: OPSStyle.Layout.spacing4) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(1.5)

                Text(pipeline.stage.rawValue)
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .animation(.none, value: pipeline.stage)

                ScanProgressBar(progress: pipeline.progress)
                    .frame(maxWidth: 240)

                Text("\(Int(pipeline.progress * 100))%")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            )
        }
    }

    // MARK: - Error Layer

    /// Shows the error message with retry and cancel buttons.
    private var errorLayer: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            // Error icon
            Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                .font(.system(size: 40))
                .foregroundColor(OPSStyle.Colors.errorStatus)

            // Error title
            Text("Scan Failed")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Error detail
            Text(pipeline.error ?? scannerError ?? "An unknown error occurred.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing5)

            Spacer()

            // Action buttons
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Try Again
                Button {
                    resetForRetry()
                } label: {
                    Text("Try Again")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }

                // Cancel
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    // MARK: - Stage Change Handling

    /// Fires haptic feedback on each pipeline stage transition.
    /// Light impact for intermediate stages, medium impact for completion, error notification for failure.
    private func handleStageChange(from oldValue: SketchScanPipeline.ScanStage, to newValue: SketchScanPipeline.ScanStage) {
        switch newValue {
        case .complete:
            mediumImpact.impactOccurred()
            // Auto-present cleanup view on successful completion
            if pipeline.result != nil {
                showingCleanup = true
            }
        case .failed:
            errorNotification.notificationOccurred(.error)
        case .idle:
            break
        default:
            // Light impact on each intermediate stage change
            if oldValue != newValue {
                lightImpact.impactOccurred()
            }
        }
    }

    // MARK: - Reset

    /// Resets all state to re-enter the choice screen.
    private func resetForRetry() {
        capturedImage = nil
        scannerError = nil
        pipeline.stage = .idle
        pipeline.progress = 0.0
        pipeline.result = nil
        pipeline.error = nil
        showingDocumentScanner = false
        showingPhotoPicker = false
        showingCleanup = false
        isProcessingLibraryImage = false
        hasUserConfirmedCapture = false
    }
}
