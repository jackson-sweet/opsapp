//
//  ARCaptureViewRepresentable.swift
//  OPS
//
//  SwiftUI wrapper around the live ARKit camera feed driven by
//  `LiDARCaptureCoordinator`. The coordinator already owns and runs the
//  ARSession; this view binds to that session for display only.
//
//  Why a custom UIView (not `ARView` / `ARSCNView`):
//    Both `ARView` and `ARSCNView` create and own their own internal
//    ARSession, which cannot be replaced — `ARView.session` is read-only.
//    Running two ARSessions simultaneously would fight for the camera.
//    Instead we poll the coordinator's running session each display frame
//    via `CADisplayLink`, pull `currentFrame.capturedImage`, and blit the
//    CVPixelBuffer through CIImage → CGImage onto a CALayer.
//
//    The faint steel-blue mesh-confidence tint from spec §5.1 ("1 px hairline
//    at rgba(111,148,176,0.08)") is rendered as an overlay color above the
//    camera layer — per-triangle mesh wireframe is a Phase E enhancement;
//    the §5.1 mesh-fade-in animation (200 ms opacity 0→1) drives this tint.
//
//  Memory: `CADisplayLink` is invalidated in `dismantleUIView`; `CIContext`
//  is reused across frames so we don't churn allocations.
//

import SwiftUI
import ARKit
import CoreImage

struct ARCaptureViewRepresentable: UIViewRepresentable {

    /// The coordinator whose `arSession` is the active source of frames.
    /// We do NOT retain a strong reference inside the UIView — the coordinator
    /// lives on the SwiftUI view, and the representable is rebuilt if it changes.
    let coordinator: LiDARCaptureCoordinator

    /// True once the AR session has emitted at least one tracked frame.
    /// Drives the mesh fade-in (§5.3 row 1). Reads but never writes.
    @Binding var meshVisible: Bool

    func makeUIView(context: Context) -> LiDARPreviewUIView {
        let view = LiDARPreviewUIView()
        view.bind(coordinator: coordinator) { hasFrame in
            // Bounce out to the next runloop so we don't fight SwiftUI's
            // update phase when the very first frame arrives.
            DispatchQueue.main.async {
                if hasFrame && !meshVisible {
                    meshVisible = true
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: LiDARPreviewUIView, context: Context) {
        // Coordinator instance is stable across updates — nothing to wire here.
    }

    static func dismantleUIView(_ uiView: LiDARPreviewUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

// MARK: - UIKit host view

final class LiDARPreviewUIView: UIView {

    private let cameraLayer = CALayer()
    private let meshTintLayer = CALayer()
    private weak var arSession: ARSession?
    private var displayLink: CADisplayLink?
    private var hasFiredFirstFrame = false
    private var onFrame: ((Bool) -> Void)?

    /// Reused across frames — `CIContext` allocation is non-trivial.
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background") ?? .black

        cameraLayer.contentsGravity = .resizeAspectFill
        cameraLayer.masksToBounds = true
        layer.addSublayer(cameraLayer)

        // Mesh-confidence tint — fades in once the session reports tracking.
        // 8% alpha steel-blue per spec §5.1.
        meshTintLayer.backgroundColor = UIColor(
            red: 111.0 / 255.0,
            green: 148.0 / 255.0,
            blue: 176.0 / 255.0,
            alpha: 0.08
        ).cgColor
        meshTintLayer.opacity = 0
        layer.addSublayer(meshTintLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported — built programmatically by SwiftUI")
    }

    func bind(coordinator: LiDARCaptureCoordinator, onFrame: @escaping (Bool) -> Void) {
        self.arSession = coordinator.arSession
        self.onFrame = onFrame
        startDisplayLink()
    }

    func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        arSession = nil
        onFrame = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cameraLayer.frame = bounds
        meshTintLayer.frame = bounds
    }

    // MARK: - Display link

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        // ProMotion-aware — system picks the best refresh rate (60 or 120 Hz).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let frame = arSession?.currentFrame else { return }

        // The CVPixelBuffer is in camera-native landscape orientation.
        // For a portrait device, rotate so the image reads upright in the
        // preview — matches what ARView/ARSCNView do internally.
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let oriented = ciImage.oriented(.right)

        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cameraLayer.contents = cgImage
        CATransaction.commit()

        if !hasFiredFirstFrame {
            hasFiredFirstFrame = true
            // 200 ms mesh tint fade-in (§5.3 row 1) — pure CALayer opacity ramp,
            // matches the OPS curve via CAMediaTimingFunction.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.20
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            meshTintLayer.add(fade, forKey: "fadeIn")
            meshTintLayer.opacity = 1

            onFrame?(true)
        }
    }
}
