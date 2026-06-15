//
//  CameraBatchView.swift
//  OPS
//
//  Multi-photo batch camera built on AVFoundation. The camera preview
//  stays live between captures, the user accumulates a stack in the
//  bottom-right corner, and a single Done press hands the entire batch
//  back to the host. Bug 0a07ca47.
//
//  The previous implementation wrapped UIImagePickerController and
//  re-presented it after every shot, which is slow, breaks the flow,
//  and makes "five quick photos of the same wall" essentially impossible
//  on a job site. This rewrite uses a custom AVCaptureSession-backed
//  camera so the user never leaves capture mode until they confirm.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - CameraBatchView (SwiftUI host)

/// Full-screen multi-shot camera. Hand it a closure and it gives back the
/// final batch when the user taps Done. Cancel returns nothing.
struct CameraBatchView: View {
    let onUpload: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var capturedImages: [UIImage] = []
    @State private var showingGallery = false
    @State private var galleryImages: [UIImage] = []
    @State private var showingReview = false
    /// Bumped every time a photo lands so the stack can play its
    /// "incoming" animation. We can't observe `capturedImages.count`
    /// alone because adding two photos in quick succession could share
    /// the same animation transaction.
    @State private var captureBeat: Int = 0

    var body: some View {
        ZStack {
            // Live AVFoundation preview takes the full screen.
            CameraPreviewLayer(
                onCapture: handleCapture,
                onCancel: { dismiss() }
            )
            .ignoresSafeArea()

            // Bottom HUD — stack thumbnail (left), shutter (centre),
            // gallery (right), plus Done in the top-right.
            VStack {
                topBar
                Spacer()
                bottomHUD
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingGallery) {
            GalleryPickerWrapper(images: $galleryImages) {
                if !galleryImages.isEmpty {
                    capturedImages.append(contentsOf: galleryImages)
                    galleryImages = []
                    bumpCaptureBeat()
                }
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            CapturedStackReview(
                images: $capturedImages,
                onDone: { showingReview = false },
                onClearAll: {
                    capturedImages.removeAll()
                    showingReview = false
                }
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Cancel — drops every captured image and dismisses the
            // camera. Confirms with a haptic so the user feels the
            // exit deliberate even on a glove tap.
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                    )
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            // Live count badge — always visible so the user knows
            // exactly how many photos are queued up.
            if !capturedImages.isEmpty {
                Text("\(capturedImages.count) PHOTO\(capturedImages.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                    )
            }

            Spacer()

            // Done — commits the batch. Disabled until the user has
            // captured at least one photo so the button can never
            // close the camera empty-handed.
            Button(action: commitBatch) {
                Text("DONE")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.8)
                    .foregroundColor(capturedImages.isEmpty
                        ? OPSStyle.Colors.tertiaryText
                        : OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                    )
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(capturedImages.isEmpty)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
    }

    // MARK: - Bottom HUD

    private var bottomHUD: some View {
        HStack(alignment: .center) {
            // Gallery button — left side, mirrored against the stack
            // so the layout stays balanced visually.
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingGallery = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 56, height: 56)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
            .accessibilityLabel("Add photos from library")

            Spacer()

            // The shutter belongs on the bottom centre. We render an
            // empty placeholder here so the stack and gallery icons
            // sit at equal depth from the edges; the real shutter is
            // the one inside CameraPreviewLayer (it's tied to the
            // AVCaptureSession lifecycle and easier to keep there).
            Color.clear
                .frame(width: 72, height: 72)

            Spacer()

            // Captured-photo stack — bottom-right per the spec. Hidden
            // when no photos have been captured yet so the empty state
            // doesn't draw attention to nothing.
            if let topImage = capturedImages.last {
                CapturedStackThumbnail(
                    topImage: topImage,
                    count: capturedImages.count,
                    captureBeat: captureBeat,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingReview = true
                    }
                )
            } else {
                // Reserve the slot so layout doesn't jitter when the
                // first photo lands.
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing4)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Capture Handling

    private func handleCapture(_ image: UIImage) {
        capturedImages.append(image)
        bumpCaptureBeat()
    }

    private func bumpCaptureBeat() {
        // Bumping a tracked counter makes the stack thumbnail's
        // `.onChange` fire even when two photos are appended in quick
        // succession (where the count may not be reflected yet).
        captureBeat &+= 1
    }

    private func commitBatch() {
        guard !capturedImages.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let batch = capturedImages
        // Clear before dismiss so a quick reopen of the camera doesn't
        // briefly show the previous session's stack.
        capturedImages.removeAll()
        onUpload(batch)
        dismiss()
    }
}

// MARK: - CapturedStackThumbnail

/// The bottom-right pile of captured photos. Renders the most recent
/// shot on top with a faint badge of the total count, and adopts a
/// tactical "stack" look — three offset rounded tiles behind the photo
/// when there's more than one item, so the user feels the pile growing.
private struct CapturedStackThumbnail: View {
    let topImage: UIImage
    let count: Int
    let captureBeat: Int
    let onTap: () -> Void

    /// Scale pulse animation that fires every time a new photo lands
    /// on the stack. 1.0 → 1.12 → 1.0 over 0.35s, so the user sees the
    /// stack "absorb" each new photo.
    @State private var landedScale: CGFloat = 1.0

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Stack visuals — only render the back tiles when
                // there's actually more than one photo.
                if count >= 3 {
                    stackTile(offsetX: 6, offsetY: 6, opacity: 0.4)
                }
                if count >= 2 {
                    stackTile(offsetX: 3, offsetY: 3, opacity: 0.65)
                }

                // Top photo — fully opaque, with a 1pt accent ring so it
                // reads against busy outdoor backgrounds.
                Image(uiImage: topImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.primaryText, lineWidth: 1.5)
                    )

                // Count badge — tucked into the top-right corner of the
                // top tile. Always visible so the user can confirm how
                // many photos they've actually got banked.
                if count > 0 {
                    Text("\(count)")
                        .font(OPSStyle.Typography.metadata)
                        .fontWeight(.bold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, OPSStyle.Layout.spacing1)
                        .background(
                            Capsule()
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                        .offset(x: 22, y: -22)
                }
            }
            .frame(width: 72, height: 72, alignment: .center)
            .scaleEffect(landedScale)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
        .accessibilityLabel("Review \(count) captured photo\(count == 1 ? "" : "s")")
        .onChange(of: captureBeat) { _, _ in
            // Two-stage spring so the pulse settles confidently rather
            // than bouncing. Matches OPSStyle.Animation.springFast for
            // the up-stroke and standard for the relaxation.
            withAnimation(OPSStyle.Animation.springFast) {
                landedScale = 1.12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(OPSStyle.Animation.standard) {
                    landedScale = 1.0
                }
            }
        }
    }

    private func stackTile(offsetX: CGFloat, offsetY: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .fill(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .frame(width: 56, height: 56)
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
    }
}

// MARK: - CapturedStackReview

/// Full-screen review sheet for the in-progress batch. The user can
/// remove individual photos or clear the lot. Done returns to the
/// camera so they can keep shooting.
private struct CapturedStackReview: View {
    @Binding var images: [UIImage]
    let onDone: () -> Void
    let onClearAll: () -> Void

    @State private var showingClearConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDone) {
                        Text("DONE")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

                    Spacer()

                    Text("\(images.count) PHOTO\(images.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button(action: { showingClearConfirmation = true }) {
                        Text("CLEAR ALL")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    .disabled(images.isEmpty)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                Divider()
                    .background(OPSStyle.Colors.cardBorder)

                // Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    images.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .background(
                                            Circle()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                }
                                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                }
            }
        }
        .alert("Clear All Photos?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                onClearAll()
            }
        } message: {
            Text("Removes every photo you've captured in this session.")
        }
    }
}

// MARK: - CameraPreviewLayer (AVCaptureSession + shutter)

/// Live AVCaptureSession preview with an embedded shutter button. Stays
/// running across captures so the user never sees a flash-to-black
/// transition between shots.
private struct CameraPreviewLayer: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        let vc = CameraPreviewViewController()
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {}
}

private final class CameraPreviewViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var shutterButton: UIButton?
    private weak var shutterInnerCircle: UIView?
    private weak var flashView: UIView?
    private weak var lensSelectorStack: UIStackView?
    private var lensOptions: [CameraLensOption] = []

    /// Bug 423073b4 — handle to the active capture device so the
    /// pinch-to-zoom gesture can mutate `videoZoomFactor` directly.
    /// Held weakly because AVCaptureDevice is owned by the session.
    private weak var captureDevice: AVCaptureDevice?

    /// Bug 423073b4 — last committed zoom factor; the pinch handler
    /// multiplies the current gesture scale against this baseline so
    /// each new pinch starts from the previous level instead of
    /// snapping back to 1x.
    private var baseZoomFactor: CGFloat = 1.0

    /// Multi-shot debounce. Same defence as SketchCaptureView — refuse a
    /// rapid double-tap while a capture is in flight, plus a short
    /// minimum interval so the camera can't queue 10 shots from one
    /// stuck-finger drag.
    private var isCapturing = false
    private var lastCaptureStartedAt: Date?
    private static let minCaptureInterval: TimeInterval = 0.4

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupShutter()
        setupLensSelector()
        setupFlashView()
        setupZoomGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        flashView?.frame = view.bounds
    }

    private func setupCamera() {
        session.sessionPreset = .photo

        guard let device = preferredBackCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        // Bug 423073b4 — request the camera's full sensor resolution. The
        // previous default settings on `.photo` preset still emitted JPEGs
        // at the device's reduced dimensions on some hardware. Setting
        // `maxPhotoDimensions` to the output's reported maximum opts the
        // capture into the largest available format. iOS 16 deprecated
        // `isHighResolutionCaptureEnabled`; use the dimensions API instead.
        if #available(iOS 16.0, *) {
            photoOutput.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        captureDevice = device
        baseZoomFactor = device.videoZoomFactor

        let preview = AVCaptureVideoPreviewLayer(session: session)
        // Bug 423073b4 — `.resizeAspect` (letterbox) replaces
        // `.resizeAspectFill` (centre-crop). Fill mode showed the user a
        // cropped preview that didn't match the captured frame — felt
        // like the camera had auto-zoomed when in fact the captured photo
        // was wider than what the preview displayed. Aspect mode shows
        // the EXACT frame the user is about to capture.
        preview.videoGravity = .resizeAspect
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    private func preferredBackCamera() -> AVCaptureDevice? {
        let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if #available(iOS 13.0, *) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInUltraWideCamera,
                    .builtInWideAngleCamera
                ],
                mediaType: .video,
                position: .back
            )
            return discovery.devices.first ?? fallback
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first ?? fallback
    }

    private func setupLensSelector() {
        guard let device = captureDevice, let shutterButton else { return }

        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        lensOptions = CameraLensOptionPlanner.options(
            minZoom: device.minAvailableVideoZoomFactor,
            maxZoom: min(device.activeFormat.videoMaxZoomFactor, CGFloat(8)),
            switchOverZoomFactors: switchOvers
        )
        guard lensOptions.count > 1 else { return }

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = CGFloat(OPSStyle.Layout.spacing1)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        stack.layer.cornerRadius = CGFloat(OPSStyle.Layout.buttonRadius)
        stack.layer.borderColor = UIColor(OPSStyle.Colors.line).cgColor
        stack.layer.borderWidth = OPSStyle.Layout.Border.standard
        stack.layoutMargins = UIEdgeInsets(
            top: CGFloat(OPSStyle.Layout.spacing1),
            left: CGFloat(OPSStyle.Layout.spacing1),
            bottom: CGFloat(OPSStyle.Layout.spacing1),
            right: CGFloat(OPSStyle.Layout.spacing1)
        )
        stack.isLayoutMarginsRelativeArrangement = true

        for (index, option) in lensOptions.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(option.label, for: .normal)
            button.titleLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            button.layer.cornerRadius = CGFloat(OPSStyle.Layout.buttonRadius)
            button.contentEdgeInsets = UIEdgeInsets(
                top: CGFloat(OPSStyle.Layout.spacing1),
                left: CGFloat(OPSStyle.Layout.spacing2),
                bottom: CGFloat(OPSStyle.Layout.spacing1),
                right: CGFloat(OPSStyle.Layout.spacing2)
            )
            button.addTarget(self, action: #selector(lensOptionTapped(_:)), for: .touchUpInside)
            button.accessibilityLabel = "\(option.label) camera lens"
            stack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        lensSelectorStack = stack
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -CGFloat(OPSStyle.Layout.spacing3)),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(OPSStyle.Layout.touchTargetMin))
        ])
        updateLensSelector(for: device.videoZoomFactor)
    }

    @objc private func lensOptionTapped(_ sender: UIButton) {
        guard lensOptions.indices.contains(sender.tag) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        applyZoomFactor(lensOptions[sender.tag].zoomFactor, animated: true)
    }

    /// Bug 423073b4 — pinch gesture drives `device.videoZoomFactor` so
    /// the user has the same zoom affordance as the native iOS Camera
    /// app. Clamps to the device's reported min/max, accumulates across
    /// pinches via `baseZoomFactor`, and ramps the zoom rather than
    /// snapping (matches Apple's tactile feel).
    private func setupZoomGesture() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }

        switch gesture.state {
        case .began:
            baseZoomFactor = device.videoZoomFactor
        case .changed:
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, CGFloat(8))
            let target = max(minZoom, min(baseZoomFactor * gesture.scale, maxZoom))
            applyZoomFactor(target, animated: true)
        case .ended, .cancelled:
            baseZoomFactor = device.videoZoomFactor
            updateLensSelector(for: device.videoZoomFactor)
        default:
            break
        }
    }

    private func applyZoomFactor(_ zoomFactor: CGFloat, animated: Bool) {
        guard let device = captureDevice else { return }
        let target = CameraLensOptionPlanner.clamped(
            zoomFactor,
            minZoom: device.minAvailableVideoZoomFactor,
            maxZoom: min(device.activeFormat.videoMaxZoomFactor, CGFloat(8))
        )
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: target, withRate: 4.0)
            } else {
                device.videoZoomFactor = target
            }
            device.unlockForConfiguration()
            baseZoomFactor = target
            updateLensSelector(for: target)
        } catch {
            print("[CameraBatch] Zoom lock failed: \(error)")
        }
    }

    private func updateLensSelector(for zoomFactor: CGFloat) {
        guard let stack = lensSelectorStack, !lensOptions.isEmpty else { return }
        let selectedIndex = lensOptions
            .enumerated()
            .min { lhs, rhs in
                abs(lhs.element.zoomFactor - zoomFactor) < abs(rhs.element.zoomFactor - zoomFactor)
            }?
            .offset

        for view in stack.arrangedSubviews {
            guard let button = view as? UIButton else { continue }
            let selected = button.tag == selectedIndex
            button.backgroundColor = selected
                ? UIColor(OPSStyle.Colors.surfaceActive)
                : UIColor.clear
            button.setTitleColor(
                selected ? UIColor(OPSStyle.Colors.text) : UIColor(OPSStyle.Colors.text3),
                for: .normal
            )
        }
    }

    private func setupShutter() {
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

        NSLayoutConstraint.activate([
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: outerSize),
            shutter.heightAnchor.constraint(equalToConstant: outerSize),

            innerCircle.centerXAnchor.constraint(equalTo: shutter.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: innerSize),
            innerCircle.heightAnchor.constraint(equalToConstant: innerSize),
        ])
    }

    /// White flash overlay used to confirm capture. 60ms fade so the
    /// user feels the shutter without drawing attention to a literal
    /// flash artifact.
    private func setupFlashView() {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        flash.isUserInteractionEnabled = false
        flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flash)
        flashView = flash
    }

    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        if let last = lastCaptureStartedAt, Date().timeIntervalSince(last) < Self.minCaptureInterval {
            return
        }
        isCapturing = true
        lastCaptureStartedAt = Date()
        shutterButton?.isEnabled = false
        shutterInnerCircle?.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Kick off the capture. Settings.flashMode auto so iPhones can
        // decide whether the scene needs the LED.
        // Bug 423073b4 — pin maxPhotoDimensions to the output's reported
        // maximum so the JPEG comes out at the camera's full sensor
        // resolution instead of the default lower-resolution preset.
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)

        // White-flash overlay — fades in/out over ~150ms total so the
        // user sees a confident "shot fired" cue but the preview comes
        // right back.
        UIView.animate(withDuration: 0.05, animations: {
            self.flashView?.alpha = 0.6
        }, completion: { _ in
            UIView.animate(withDuration: 0.10) {
                self.flashView?.alpha = 0
            }
        })
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            // Always re-enable the shutter even on failure so the user
            // isn't stranded with an unresponsive button mid-job.
            DispatchQueue.main.async {
                self.resetShutter()
            }
        }

        if error != nil { return }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }

        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.onCapture?(image)
        }
    }

    private func resetShutter() {
        isCapturing = false
        shutterButton?.isEnabled = true
        shutterInnerCircle?.backgroundColor = .white
    }
}

// MARK: - Gallery Picker Wrapper (PHPicker)

/// Lifted from the original CameraBatchView. Used when the user wants
/// to pull existing library photos into the same batch as the live
/// captures.
private struct GalleryPickerWrapper: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 20
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GalleryPickerWrapper
        // Bug 35c400c2 mirror — same hasFinished guard as the main
        // ImagePicker so a flaky double-fire from PHPicker can't double
        // a library import either.
        var hasFinished = false

        init(parent: GalleryPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !hasFinished else { return }
            hasFinished = true

            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            // Slot-indexed loading so order is preserved regardless of
            // which loadDataRepresentation resolves first.
            var loaded: [UIImage?] = Array(repeating: nil, count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                guard result.itemProvider.hasItemConformingToTypeIdentifier("public.image") else { continue }
                group.enter()
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    defer { group.leave() }
                    guard let data = data, let image = UIImage(data: data) else { return }
                    loaded[index] = image
                }
            }

            group.notify(queue: .main) {
                self.parent.images = loaded.compactMap { $0 }
                self.parent.onComplete()
            }
        }
    }
}
