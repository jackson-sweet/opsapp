// OPS/OPS/DeckBuilder/AR/ARVisualizationView.swift

import SwiftUI
import ARKit
import SceneKit
import AVFoundation

// MARK: - Main View

struct ARVisualizationView: View {
    @StateObject private var viewModel: ARVisualizationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var arAvailability: ARAvailabilityStatus = .checking

    init(drawingData: DeckDrawingData) {
        self._viewModel = StateObject(wrappedValue: ARVisualizationViewModel(drawingData: drawingData))
    }

    var body: some View {
        ZStack {
            switch arAvailability {
            case .checking:
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)

            case .available:
                ARSceneContainer(viewModel: viewModel)
                    .ignoresSafeArea()

                VStack {
                    topBar
                    Spacer()
                    bottomStatus
                }

            case .unsupported:
                arUnavailableOverlay(message: "AR is not available on this device.")

            case .cameradenied:
                arUnavailableOverlay(message: "Camera access required for AR. Enable in Settings.")
            }
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let image = viewModel.screenshotImage {
                ActivityView(items: [image])
            }
        }
        .statusBarHidden(true)
        .task { await checkARAvailability() }
    }

    private func checkARAvailability() async {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("[DeckBuilder] AR visualization: ARWorldTrackingConfiguration not supported")
            arAvailability = .unsupported
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            arAvailability = .available
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            arAvailability = granted ? .available : .cameradenied
        default:
            print("[DeckBuilder] AR visualization: camera permission denied (\(status.rawValue))")
            arAvailability = .cameradenied
        }
    }

    private func arUnavailableOverlay(message: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arkit")
                    .font(.system(size: 48))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(message)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if arAvailability == .cameradenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                Button { dismiss() } label: {
                    Text("Dismiss")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Spacer()

            // Screenshot
            Button {
                NotificationCenter.default.post(name: .arVizCaptureScreenshot, object: nil)
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .disabled(viewModel.placementState != .placed)
            .opacity(viewModel.placementState == .placed ? 1 : 0.4)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
    }

    // MARK: - Bottom Status

    private var bottomStatus: some View {
        VStack(spacing: 8) {
            if !viewModel.statusMessage.isEmpty {
                HStack(spacing: 10) {
                    if viewModel.placementState == .scanning {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }

                    Text(viewModel.statusMessage)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            if viewModel.showDragHint {
                Text("Drag to reposition \u{2022} Two fingers to rotate")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 40)
        .animation(.easeInOut(duration: 0.3), value: viewModel.statusMessage)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showDragHint)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let arVizCaptureScreenshot = Notification.Name("arVizCaptureScreenshot")
}

// MARK: - ARSCNView Container

struct ARSceneContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARVisualizationViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        arView.rendersCameraGrain = true
        arView.autoenablesDefaultLighting = false

        // AR session configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true

        // People occlusion on supported devices (iPhone 12+)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        arView.session.run(config)

        // Gesture recognizers
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(pan)

        let rotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        arView.addGestureRecognizer(rotation)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.8
        arView.addGestureRecognizer(longPress)

        // Allow simultaneous pan + rotation
        pan.delegate = context.coordinator
        rotation.delegate = context.coordinator

        context.coordinator.arView = arView

        // Listen for screenshot requests
        context.coordinator.screenshotObserver = NotificationCenter.default.addObserver(
            forName: .arVizCaptureScreenshot,
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.captureScreenshot()
        }

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // No dynamic updates needed — state is managed by coordinator
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
        if let observer = coordinator.screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate {
        let viewModel: ARVisualizationViewModel
        weak var arView: ARSCNView?
        var previewNode: SCNNode?
        var screenshotObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?
        private var planeDetected = false
        private var dragStarted = false
        private var rotationStarted = false

        init(viewModel: ARVisualizationViewModel) {
            self.viewModel = viewModel
            super.init()

            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.arView?.session.pause()
            }
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let arView = self?.arView else { return }
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal]
                config.environmentTexturing = .automatic
                config.isLightEstimationEnabled = true
                arView.session.run(config)
            }
        }

        deinit {
            if let obs = backgroundObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = foregroundObserver { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if anchor is ARPlaneAnchor, !planeDetected {
                    planeDetected = true
                    setupPreviewNode()
                    Task { @MainActor in viewModel.onPlaneDetected() }
                }
            }
        }

        // MARK: - ARSCNViewDelegate

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor.name == "deckPlacement" else { return nil }
            let deckNode = DeckSceneBuilder.buildARNode(from: viewModel.drawingData)
            Task { @MainActor in viewModel.deckNode = deckNode }
            return deckNode
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard viewModel.placementState == .previewing,
                  let arView = arView,
                  let previewNode = previewNode else { return }

            // Raycast from center of screen to ground plane
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            if let query = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal),
               let result = arView.session.raycast(query).first {
                previewNode.simdWorldPosition = simd_float3(
                    result.worldTransform.columns.3.x,
                    result.worldTransform.columns.3.y,
                    result.worldTransform.columns.3.z
                )
                previewNode.isHidden = false
            }
        }

        // MARK: - Gesture Handlers

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard viewModel.placementState == .previewing, let arView = arView else { return }

            let location = gesture.location(in: arView)
            if let query = arView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal),
               let result = arView.session.raycast(query).first {

                // Remove preview
                previewNode?.removeFromParentNode()
                previewNode = nil

                // Place anchor — delegate's renderer(_:nodeFor:) will attach the deck
                let anchor = ARAnchor(name: "deckPlacement", transform: result.worldTransform)
                arView.session.add(anchor: anchor)
                Task { @MainActor in
                    viewModel.deckAnchor = anchor
                    viewModel.onTapToPlace(transform: result.worldTransform)
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard viewModel.placementState == .placed,
                  let arView = arView,
                  let deckNode = viewModel.deckNode else { return }

            if gesture.state == .began {
                dragStarted = false
            }

            let location = gesture.location(in: arView)
            if let query = arView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal),
               let result = arView.session.raycast(query).first {

                if !dragStarted {
                    dragStarted = true
                    Task { @MainActor in viewModel.onDragStart() }
                }

                // Slide along ground plane — update XZ, keep current Y and rotation
                let parentNode = deckNode.parent ?? deckNode
                parentNode.simdWorldPosition = simd_float3(
                    result.worldTransform.columns.3.x,
                    parentNode.simdWorldPosition.y,
                    result.worldTransform.columns.3.z
                )
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard viewModel.placementState == .placed,
                  let deckNode = viewModel.deckNode else { return }

            if gesture.state == .began {
                rotationStarted = false
            }

            if !rotationStarted {
                rotationStarted = true
                Task { @MainActor in viewModel.onRotateStart() }
            }

            let parentNode = deckNode.parent ?? deckNode
            parentNode.eulerAngles.y -= Float(gesture.rotation)
            gesture.rotation = 0
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, viewModel.placementState == .placed else { return }

            // Remove placed deck and anchor
            viewModel.deckNode?.parent?.removeFromParentNode()
            if let anchor = viewModel.deckAnchor {
                arView?.session.remove(anchor: anchor)
            }

            // Re-enter preview mode
            setupPreviewNode()
            Task { @MainActor in viewModel.onResetPosition() }
        }

        // MARK: - Preview Node

        func setupPreviewNode() {
            guard previewNode == nil else { return }

            let node = DeckSceneBuilder.buildARNode(from: viewModel.drawingData)
            node.name = "deckPreview"

            // Set all materials to 50% opacity for ghost effect
            node.enumerateChildNodes { child, _ in
                child.geometry?.materials.forEach { material in
                    material.transparency = 0.5
                }
            }

            // Pulsing animation to indicate "tap to place"
            let pulse = SCNAction.sequence([
                SCNAction.fadeOpacity(to: 0.3, duration: 0.8),
                SCNAction.fadeOpacity(to: 0.6, duration: 0.8)
            ])
            node.runAction(SCNAction.repeatForever(pulse))

            node.isHidden = true // hidden until first raycast positions it
            arView?.scene.rootNode.addChildNode(node)
            previewNode = node
        }

        // MARK: - Screenshot

        func captureScreenshot() {
            guard let arView = arView else { return }
            let rawSnapshot = arView.snapshot()
            let watermarked = addWatermark(to: rawSnapshot)
            Task { @MainActor in viewModel.onScreenshotCaptured(watermarked) }
        }

        private func addWatermark(to image: UIImage) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { ctx in
                image.draw(at: .zero)

                let text = "Powered by OPS"
                let font = UIFont.systemFont(ofSize: 12, weight: .medium)
                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
                shadow.shadowOffset = CGSize(width: 0, height: 1)
                shadow.shadowBlurRadius = 2

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                    .shadow: shadow
                ]

                let textSize = (text as NSString).size(withAttributes: attributes)
                let margin: CGFloat = 12
                let origin = CGPoint(
                    x: image.size.width - textSize.width - margin,
                    y: image.size.height - textSize.height - margin
                )
                (text as NSString).draw(at: origin, withAttributes: attributes)
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow pan + rotation simultaneously
            let isPan = gestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer
            let isRotation = gestureRecognizer is UIRotationGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer
            return isPan && isRotation
        }
    }
}
