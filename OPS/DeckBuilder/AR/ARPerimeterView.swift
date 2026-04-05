// OPS/OPS/DeckBuilder/AR/ARPerimeterView.swift

import SwiftUI
import SwiftData
import ARKit
import RealityKit
import AVFoundation
import CoreLocation
import simd

struct ARPerimeterView: View {
    @StateObject private var viewModel = ARPerimeterViewModel()
    @State private var showingDoneConfirmation = false
    @State private var arAvailability: ARAvailabilityStatus = .checking
    @Environment(\.dismiss) private var dismiss

    let onComplete: (DeckDrawingData) -> Void

    var body: some View {
        ZStack {
            switch arAvailability {
            case .checking:
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)

            case .available:
                ARViewContainer(viewModel: viewModel)
                    .ignoresSafeArea()

                VStack {
                    topBar
                    Spacer()
                    crosshairAndDimension
                    Spacer()
                    bottomControls
                }

                if viewModel.showVertexPopover, let idx = viewModel.popoverVertexIndex {
                    vertexPopover(index: idx)
                }

            case .unsupported:
                arUnavailableOverlay(message: "AR is not available on this device.")

            case .cameradenied:
                arUnavailableOverlay(message: "Camera access required for AR. Enable in Settings.")
            }
        }
        .statusBarHidden(true)
        .task { await checkARAvailability() }
        .alert("Different Address Detected",
               isPresented: $viewModel.showAddressPrompt) {
            Button("Keep Current", role: .cancel) {}
            Button("Use Detected") {
                // Pass detected address to the onComplete handler via drawingData metadata
                // The parent view can update the project address
            }
        } message: {
            if let addr = viewModel.detectedAddress {
                Text("AR detected: \(addr)\n\nUpdate the project address?")
            }
        }
    }

    private func checkARAvailability() async {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("[DeckBuilder] AR perimeter: ARWorldTrackingConfiguration not supported")
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
            print("[DeckBuilder] AR perimeter: camera permission denied (\(status.rawValue))")
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
                Button {
                    onComplete(DeckDrawingData())
                } label: {
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
            closeButton
            Spacer()
            vertexCountBadge
            Spacer()
            snapToggle
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
    }

    private var closeButton: some View {
        Button {
            if viewModel.arVertices.isEmpty {
                onComplete(DeckDrawingData())
            } else {
                showingDoneConfirmation = true
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .confirmationDialog("Exit AR Walk?", isPresented: $showingDoneConfirmation) {
            if viewModel.isClosed || viewModel.arVertices.count >= 3 {
                Button("Save & Exit") {
                    let data = viewModel.toDrawingData()
                    onComplete(data)
                }
            }
            Button("Discard", role: .destructive) {
                onComplete(DeckDrawingData())
            }
            Button("Continue Walking", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var vertexCountBadge: some View {
        if !viewModel.arVertices.isEmpty {
            Text("\(viewModel.arVertices.count) corners")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var snapToggle: some View {
        Button {
            viewModel.angleSnappingEnabled.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "angle")
                    .font(.system(size: 14, weight: .medium))
                Text(viewModel.angleSnappingEnabled ? "ON" : "OFF")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(viewModel.angleSnappingEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Crosshair & Live Dimension

    // MARK: - Tactical HUD Overlay

    private var crosshairAndDimension: some View {
        ZStack {
            tacticalCornerBrackets

            VStack(spacing: 12) {
                // Dimension readout
                if !viewModel.liveDimensionLabel.isEmpty {
                    Text(viewModel.liveDimensionLabel)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 3, y: 1)
                }

                // Tactical crosshair
                tacticalCrosshair

                // Status
                if !viewModel.isPlaneDetected {
                    HStack(spacing: 6) {
                        ProgressView().tint(OPSStyle.Colors.warningStatus).scaleEffect(0.7)
                        Text("SCANNING")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                } else {
                    Text("\(viewModel.arVertices.count) PTS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
        }
    }

    private var tacticalCrosshair: some View {
        Canvas { context, size in
            let cx = size.width / 2, cy = size.height / 2
            let gap: CGFloat = 6, arm: CGFloat = 16
            var path = Path()
            path.move(to: CGPoint(x: cx, y: cy - gap - arm))
            path.addLine(to: CGPoint(x: cx, y: cy - gap))
            path.move(to: CGPoint(x: cx, y: cy + gap))
            path.addLine(to: CGPoint(x: cx, y: cy + gap + arm))
            path.move(to: CGPoint(x: cx - gap - arm, y: cy))
            path.addLine(to: CGPoint(x: cx - gap, y: cy))
            path.move(to: CGPoint(x: cx + gap, y: cy))
            path.addLine(to: CGPoint(x: cx + gap + arm, y: cy))
            context.stroke(path, with: .color(Color.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            let r: CGFloat = 2
            context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(Color.white))
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    private var tacticalCornerBrackets: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                let w = geo.size.width, h = geo.size.height
                let arm: CGFloat = 24, inset: CGFloat = 20
                var path = Path()
                path.move(to: CGPoint(x: inset, y: inset + arm))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset + arm, y: inset))
                path.move(to: CGPoint(x: w - inset - arm, y: inset))
                path.addLine(to: CGPoint(x: w - inset, y: inset))
                path.addLine(to: CGPoint(x: w - inset, y: inset + arm))
                path.move(to: CGPoint(x: inset, y: h - inset - arm))
                path.addLine(to: CGPoint(x: inset, y: h - inset))
                path.addLine(to: CGPoint(x: inset + arm, y: h - inset))
                path.move(to: CGPoint(x: w - inset - arm, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset, y: h - inset - arm))
                context.stroke(path, with: .color(Color.white.opacity(0.2)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Floating label above trigger — current mode/assignment
            Text(triggerLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
                .padding(.bottom, 10)

            HStack(alignment: .bottom) {
                rightControls

                Spacer()

                // Camera-style circular trigger with integrated wheel
                ARTriggerButton(viewModel: viewModel) {
                    if viewModel.isNearFirstVertex {
                        viewModel.closeLoop()
                    } else if viewModel.isSplittingEdge, let edgeIdx = viewModel.splittingEdgeIndex,
                              let pos = viewModel.currentCrosshairPosition {
                        viewModel.splitEdge(edgeIndex: edgeIdx, at: pos)
                    } else if viewModel.isEditingVertex, let vertexIdx = viewModel.editingVertexIndex,
                              let pos = viewModel.currentCrosshairPosition {
                        viewModel.repositionVertex(index: vertexIdx, to: pos)
                    } else if let pos = viewModel.currentCrosshairPosition {
                        viewModel.recordVertex(worldPosition: pos)
                    }
                }
                .disabled(!viewModel.isPlaneDetected || viewModel.isClosed)
                .opacity(viewModel.isClosed ? 0.4 : 1.0)

                Spacer()

                // Undo button (symmetry with right controls)
                if !viewModel.arVertices.isEmpty && !viewModel.isClosed {
                    Button {
                        viewModel.undoLastVertex()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                } else {
                    Color.clear.frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing5)
    }

    private var triggerLabel: String {
        if !viewModel.isPlaneDetected { return "scanning" }
        if viewModel.isClosed { return "loop closed" }
        if viewModel.isNearFirstVertex { return "close loop" }
        if let label = viewModel.currentAssignmentLabel { return label }
        return "vertex"
    }

    private var rightControls: some View {
        VStack(spacing: 8) {
            if viewModel.isClosed {
                Button {
                    let data = viewModel.toDrawingData()
                    onComplete(data)
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }

            undoButton
        }
    }

    private var undoButton: some View {
        let isDisabled = viewModel.arVertices.isEmpty || viewModel.isClosed
        return Button {
            viewModel.undoLastVertex()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    // MARK: - Vertex Popover

    private func vertexPopover(index: Int) -> some View {
        VStack(spacing: 0) {
            Button {
                viewModel.showVertexPopover = false
                viewModel.isEditingVertex = true
                viewModel.editingVertexIndex = index
            } label: {
                HStack {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    Text("Reposition")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Divider().background(OPSStyle.Colors.tertiaryText)

            Button(role: .destructive) {
                viewModel.deleteVertex(index: index)
                viewModel.showVertexPopover = false
                viewModel.popoverVertexIndex = nil
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 200)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

// MARK: - AR Assignment Wheel (Extracted View)

/// Camera-style circular trigger with integrated assignment wheel.
/// Tap = fire action. Long-press = expand radial wheel. Drag to select, release to confirm.
private struct ARTriggerButton: View {
    @ObservedObject var viewModel: ARPerimeterViewModel
    @Query(filter: #Predicate<Product> { $0.isActive }, sort: \Product.name) private var products: [Product]
    @State private var wheelExpanded = false
    @State private var wheelHighlight: Int?
    let action: () -> Void

    private static let builtInItems: [(String, String)] = [
        ("House", "house"),
        ("Deck", "rectangle"),
        ("Glass", "rectangle.split.3x1"),
        ("Picket", "line.3.horizontal"),
        ("Cable", "cable.connector.horizontal"),
        ("No Rail", "xmark"),
    ]

    private var items: [(String, String)] {
        var all = Self.builtInItems
        let linearProducts = products.filter { product in
            guard let unit = product.unit?.lowercased() else { return false }
            return unit.contains("linear") || unit.contains("lf") || unit.contains("foot") || unit.contains("meter")
        }
        for product in linearProducts.prefix(2) {
            all.append((String(product.name.prefix(8)), "shippingbox"))
        }
        return all
    }

    private var dynamicProducts: [Product] {
        products.filter { product in
            guard let unit = product.unit?.lowercased() else { return false }
            return unit.contains("linear") || unit.contains("lf") || unit.contains("foot") || unit.contains("meter")
        }
    }

    private let triggerSize: CGFloat = 72
    private let wheelRadius: CGFloat = 90

    var body: some View {
        ZStack {
            // Radial wheel slots (visible when expanded)
            if wheelExpanded {
                ForEach(0..<items.count, id: \.self) { index in
                    wheelSlot(index: index)
                }
            }

            // Outer ring — camera trigger aesthetic
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                .frame(width: triggerSize, height: triggerSize)

            // Inner fill — pulses on tap
            Circle()
                .fill(Color.white.opacity(wheelExpanded ? 0.15 : 0.1))
                .frame(width: triggerSize - 8, height: triggerSize - 8)

            // Center dot
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .frame(width: triggerSize, height: triggerSize)
        .contentShape(Circle())
        .onTapGesture {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .gesture(wheelDragGesture)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: wheelExpanded)
    }

    private func wheelSlot(index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / Double(items.count)) - .pi / 2
        let isHighlighted = wheelHighlight == index
        let item = items[index]

        return VStack(spacing: 2) {
            Image(systemName: item.1)
                .font(.system(size: isHighlighted ? 16 : 12, weight: .semibold))
                .foregroundColor(isHighlighted ? Color.white : Color.white.opacity(0.7))
            Text(item.0.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(isHighlighted ? Color.white : Color.white.opacity(0.5))
        }
        .frame(width: 48, height: 48)
        .background(Circle().fill(isHighlighted ? Color.white.opacity(0.2) : Color.black.opacity(0.6)))
        .overlay(Circle().stroke(isHighlighted ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1))
        .offset(x: cos(angle) * wheelRadius, y: sin(angle) * wheelRadius)
    }

    private var wheelDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if !wheelExpanded {
                        wheelExpanded = true
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }
                    if let drag = drag {
                        let oldHighlight = wheelHighlight
                        updateHighlight(drag: drag)
                        if wheelHighlight != oldHighlight && wheelHighlight != nil {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
            }
            .onEnded { _ in
                if let idx = wheelHighlight, idx < items.count {
                    executeAction(idx)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    wheelExpanded = false
                    wheelHighlight = nil
                }
            }
    }

    private func updateHighlight(drag: DragGesture.Value) {
        let center = triggerSize / 2
        let dx = Double(drag.location.x - center)
        let dy = Double(drag.location.y - center)
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 25 else { wheelHighlight = nil; return }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        if angle > 2 * .pi { angle -= 2 * .pi }
        let step = (2 * .pi) / Double(items.count)
        wheelHighlight = Int((angle + step / 2) / step) % items.count
    }

    private func executeAction(_ index: Int) {
        let builtInCount = Self.builtInItems.count
        if index < builtInCount {
            switch index {
            case 0: viewModel.activeEdgeType = .houseEdge
            case 1: viewModel.activeEdgeType = .deckEdge
            case 2: viewModel.activeRailingConfig = RailingConfig(railingType: .glass, maxPostSpacing: RailingType.glass.defaultMaxPostSpacing)
            case 3: viewModel.activeRailingConfig = RailingConfig(railingType: .picket, maxPostSpacing: RailingType.picket.defaultMaxPostSpacing)
            case 4: viewModel.activeRailingConfig = RailingConfig(railingType: .cable, maxPostSpacing: RailingType.cable.defaultMaxPostSpacing)
            case 5: viewModel.activeRailingConfig = nil
            default: break
            }
        } else {
            let productIndex = index - builtInCount
            let linears = Array(dynamicProducts.prefix(2))
            guard productIndex < linears.count else { return }
            let product = linears[productIndex]
            viewModel.activeAssignment = AssignedItem(
                productId: product.id, name: product.name,
                unitType: .linearFoot, unitPrice: product.defaultPrice
            )
        }
    }
}

// MARK: - ARView UIViewRepresentable

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARPerimeterViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isAutoFocusEnabled = true
        config.worldAlignment = .gravity

        arView.session.run(config)
        arView.session.delegate = context.coordinator

        let renderer = ARLineRenderer()
        arView.scene.addAnchor(renderer.rootAnchor)
        context.coordinator.renderer = renderer
        context.coordinator.arView = arView

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var viewModel: ARPerimeterViewModel
        var renderer: ARLineRenderer?
        weak var arView: ARView?

        private var renderedVertexCount = 0
        private var renderedEdgeCount = 0
        private var renderedClosed = false
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?
        private let locationManager = CLLocationManager()
        private var hasTriggeredGeocode = false

        init(viewModel: ARPerimeterViewModel) {
            self.viewModel = viewModel
            super.init()
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()

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
                arView.session.run(config)
            }
        }

        deinit {
            if let obs = backgroundObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = foregroundObserver { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let cameraTransform = frame.camera.transform
            let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)

            if let position = performRaycast(session: session, arView: arView, center: center, target: .existingPlaneGeometry) {
                handleHit(position: position, cameraPosition: cameraPosition)
                return
            }

            if let position = performRaycast(session: session, arView: arView, center: center, target: .estimatedPlane) {
                handleHit(position: position, cameraPosition: cameraPosition)
                return
            }

            Task { @MainActor in
                self.viewModel.isPlaneDetected = false
            }
        }

        private func performRaycast(session: ARSession, arView: ARView, center: CGPoint, target: ARRaycastQuery.Target) -> SIMD3<Float>? {
            guard let query = arView.makeRaycastQuery(from: center, allowing: target, alignment: .horizontal) else { return nil }
            guard let hit = session.raycast(query).first else { return nil }
            return SIMD3<Float>(
                hit.worldTransform.columns.3.x,
                hit.worldTransform.columns.3.y,
                hit.worldTransform.columns.3.z
            )
        }

        private func handleHit(position: SIMD3<Float>, cameraPosition: SIMD3<Float>) {
            let renderer = self.renderer
            Task { @MainActor in
                self.viewModel.isPlaneDetected = true
                self.viewModel.updateCrosshairPosition(position)
                self.updateRendering(crosshairPosition: position, cameraPosition: cameraPosition, renderer: renderer)

                // Trigger reverse geocode once when plane first detected
                if !self.hasTriggeredGeocode, let loc = self.locationManager.location {
                    self.hasTriggeredGeocode = true
                    self.viewModel.detectAddress(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                }
            }
        }

        // MARK: - Rendering Update (MainActor)

        @MainActor
        private func updateRendering(crosshairPosition: SIMD3<Float>, cameraPosition: SIMD3<Float>, renderer: ARLineRenderer?) {
            guard let renderer = renderer else { return }

            let vCount = viewModel.arVertices.count
            let eCount = viewModel.arEdges.count
            let closed = viewModel.isClosed

            if vCount != renderedVertexCount {
                for name in viewModel.vertexEntityNames {
                    renderer.removeVertex(named: name)
                }
                viewModel.vertexEntityNames.removeAll()

                for (i, v) in viewModel.arVertices.enumerated() {
                    let pos = SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
                    let name = renderer.addVertex(at: pos, isFirst: i == 0)
                    viewModel.vertexEntityNames.append(name)
                }
                renderedVertexCount = vCount
            }

            if eCount != renderedEdgeCount {
                for name in viewModel.edgeEntityNames {
                    renderer.removeEdge(named: name)
                }
                viewModel.edgeEntityNames.removeAll()

                for edge in viewModel.arEdges {
                    guard let startV = viewModel.arVertices.first(where: { $0.id == edge.startVertexId }),
                          let endV = viewModel.arVertices.first(where: { $0.id == edge.endVertexId }) else { continue }
                    let from = SIMD3<Float>(Float(startV.x), Float(startV.y), Float(startV.z))
                    let to = SIMD3<Float>(Float(endV.x), Float(endV.y), Float(endV.z))
                    let dimInches = edge.distanceMeters * 39.3701
                    let dimLabel = "~" + DimensionEngine.formatImperial(dimInches)
                    let accLabel = AccuracyModel.formatAccuracy(dimensionInches: dimInches, accuracyPercent: edge.accuracyPercent)
                    let name = renderer.addLockedEdge(from: from, to: to, label: "\(dimLabel) \(accLabel)")
                    viewModel.edgeEntityNames.append(name)
                }
                renderedEdgeCount = eCount
            }

            if !closed, let lastV = viewModel.arVertices.last {
                let lastPos = SIMD3<Float>(Float(lastV.x), Float(lastV.y), Float(lastV.z))
                renderer.updateLiveLine(from: lastPos, to: crosshairPosition, label: viewModel.liveDimensionLabel)
            } else {
                renderer.removeLiveLine()
            }

            if closed && !renderedClosed {
                let positions = viewModel.arVertices.map {
                    SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
                }
                renderer.showFootprintFill(vertices: positions)
                renderedClosed = true
            }

            // Billboard all labels to face the camera every frame
            renderer.updateLabelOrientations(cameraPosition: cameraPosition)
        }

        // MARK: - Tap Handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            let tapLocation = gesture.location(in: arView)
            guard let query = arView.makeRaycastQuery(from: tapLocation, allowing: .existingPlaneGeometry, alignment: .horizontal),
                  let hit = arView.session.raycast(query).first else { return }

            let hitPosition = SIMD3<Float>(
                hit.worldTransform.columns.3.x,
                hit.worldTransform.columns.3.y,
                hit.worldTransform.columns.3.z
            )

            Task { @MainActor in
                self.processTap(hitPosition: hitPosition)
            }
        }

        @MainActor
        private func processTap(hitPosition: SIMD3<Float>) {
            guard !viewModel.arVertices.isEmpty else { return }

            let vertexHitRadius: Float = 0.3
            for (index, vertex) in viewModel.arVertices.enumerated() {
                let vPos = SIMD3<Float>(Float(vertex.x), Float(vertex.y), Float(vertex.z))
                if simd_distance(hitPosition, vPos) < vertexHitRadius {
                    if viewModel.isEditingVertex, let editIdx = viewModel.editingVertexIndex {
                        // Already in reposition mode — record the new position
                        if let crosshair = viewModel.currentCrosshairPosition {
                            viewModel.repositionVertex(index: editIdx, to: crosshair)
                        }
                    } else {
                        // Show vertex popover with Reposition / Delete options
                        viewModel.popoverVertexIndex = index
                        viewModel.showVertexPopover = true
                    }
                    return
                }
            }

            let edgeHitRadius: Float = 0.3
            for (index, edge) in viewModel.arEdges.enumerated() {
                guard let startV = viewModel.arVertices.first(where: { $0.id == edge.startVertexId }),
                      let endV = viewModel.arVertices.first(where: { $0.id == edge.endVertexId }) else { continue }
                let a = SIMD3<Float>(Float(startV.x), Float(startV.y), Float(startV.z))
                let b = SIMD3<Float>(Float(endV.x), Float(endV.y), Float(endV.z))
                let dist = pointToSegmentDistance(hitPosition, a: a, b: b)
                if dist < edgeHitRadius {
                    viewModel.isSplittingEdge = true
                    viewModel.splittingEdgeIndex = index
                    return
                }
            }
        }

        private func pointToSegmentDistance(_ p: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> Float {
            let ab = b - a
            let ap = p - a
            let dot = simd_dot(ab, ab)
            guard dot > 0 else { return simd_distance(p, a) }
            let t = max(0, min(1, simd_dot(ap, ab) / dot))
            let closest = a + t * ab
            return simd_distance(p, closest)
        }
    }
}
