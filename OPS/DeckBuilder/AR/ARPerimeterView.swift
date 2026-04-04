// OPS/OPS/DeckBuilder/AR/ARPerimeterView.swift

import SwiftUI
import ARKit
import RealityKit
import simd

struct ARPerimeterView: View {
    @StateObject private var viewModel = ARPerimeterViewModel()
    @State private var showingVertexPopover = false
    @State private var selectedVertexIndex: Int?
    @State private var showingDoneConfirmation = false

    let onComplete: (DeckDrawingData) -> Void

    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                crosshairAndDimension
                Spacer()
                bottomControls
            }

            if showingVertexPopover, let idx = selectedVertexIndex {
                vertexPopover(index: idx)
            }
        }
        .statusBarHidden(true)
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

    private var crosshairAndDimension: some View {
        VStack(spacing: 8) {
            liveDimensionBadge
            crosshairIcon
            scanningIndicator
        }
    }

    @ViewBuilder
    private var liveDimensionBadge: some View {
        if !viewModel.liveDimensionLabel.isEmpty {
            Text(viewModel.liveDimensionLabel)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var crosshairIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 2)
    }

    @ViewBuilder
    private var scanningIndicator: some View {
        if !viewModel.isPlaneDetected {
            Text("Scanning surface...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(alignment: .bottom) {
            ARAssignmentWheelView(viewModel: viewModel)
                .frame(width: 60, height: 60)

            Spacer()
            mainActionButton
            Spacer()
            rightControls
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing5)
    }

    private var mainActionButton: some View {
        Button {
            if viewModel.isNearFirstVertex {
                viewModel.closeLoop()
            } else if let pos = viewModel.currentCrosshairPosition {
                viewModel.recordVertex(worldPosition: pos)
            }
        } label: {
            mainActionButtonLabel
        }
        .disabled(!viewModel.isPlaneDetected || viewModel.isClosed)
        .opacity(viewModel.isClosed ? 0.4 : 1.0)
    }

    private var mainActionButtonLabel: some View {
        VStack(spacing: 4) {
            Text(buttonTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            if viewModel.arVertices.isEmpty {
                Text("Aim at first corner")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(minWidth: 180)
        .padding(.vertical, 16)
        .background(buttonColor)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    private var buttonTitle: String {
        if !viewModel.isPlaneDetected { return "Scanning..." }
        if viewModel.isClosed { return "Loop Closed" }
        if viewModel.isNearFirstVertex { return "Close Loop" }
        if viewModel.isSplittingEdge { return "Record Split" }
        if viewModel.isEditingVertex { return "Record Position" }
        return "Record Vertex"
    }

    private var buttonColor: Color {
        if !viewModel.isPlaneDetected { return OPSStyle.Colors.tertiaryText }
        if viewModel.isNearFirstVertex { return OPSStyle.Colors.successStatus }
        return OPSStyle.Colors.primaryAccent
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
                viewModel.isEditingVertex = true
                viewModel.editingVertexIndex = index
                showingVertexPopover = false
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
                showingVertexPopover = false
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

private struct ARAssignmentWheelView: View {
    @ObservedObject var viewModel: ARPerimeterViewModel
    @State private var wheelExpanded = false
    @State private var wheelHighlight: Int?

    private let items: [(String, String)] = [
        ("House", "house"),
        ("Deck", "rectangle"),
        ("Glass", "rectangle.split.3x1"),
        ("Picket", "line.3.horizontal"),
        ("Cable", "cable.connector.horizontal"),
        ("No Rail", "xmark"),
    ]

    var body: some View {
        ZStack {
            if wheelExpanded {
                wheelSlots
            }
            centerButton
        }
        .animation(OPSStyle.Animation.spring, value: wheelExpanded)
    }

    private var wheelSlots: some View {
        ForEach(0..<items.count, id: \.self) { index in
            wheelSlot(index: index)
        }
    }

    private func wheelSlot(index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / Double(items.count)) - .pi / 2
        let isHighlighted = wheelHighlight == index
        let item = items[index]

        return VStack(spacing: 2) {
            Image(systemName: item.1)
                .font(.system(size: isHighlighted ? 18 : 14, weight: .medium))
                .foregroundColor(isHighlighted ? OPSStyle.Colors.primaryAccent : .white)
            Text(item.0)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(isHighlighted ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
        }
        .frame(width: 50, height: 50)
        .background(
            Circle().fill(isHighlighted ? OPSStyle.Colors.primaryAccent.opacity(0.2) : Color.black.opacity(0.6))
        )
        .offset(x: cos(angle) * 80, y: sin(angle) * 80)
    }

    private var centerButton: some View {
        Circle()
            .fill(Color.black.opacity(0.5))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: wheelExpanded ? "xmark" : "circle.grid.2x2")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            )
            .onTapGesture {
                withAnimation(OPSStyle.Animation.spring) {
                    wheelExpanded.toggle()
                    wheelHighlight = nil
                }
            }
            .gesture(wheelDragGesture)
    }

    private var wheelDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if !wheelExpanded { wheelExpanded = true }
                    if let drag = drag {
                        updateHighlight(drag: drag)
                    }
                }
            }
            .onEnded { _ in
                if let idx = wheelHighlight, idx < items.count {
                    executeAction(idx)
                }
                withAnimation(OPSStyle.Animation.spring) {
                    wheelExpanded = false
                    wheelHighlight = nil
                }
            }
    }

    private func updateHighlight(drag: DragGesture.Value) {
        let dx = Double(drag.location.x - 25)
        let dy = Double(drag.location.y - 25)
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 20 else { wheelHighlight = nil; return }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        if angle > 2 * .pi { angle -= 2 * .pi }
        let step = (2 * .pi) / Double(items.count)
        wheelHighlight = Int((angle + step / 2) / step) % items.count
    }

    private func executeAction(_ index: Int) {
        switch index {
        case 0: viewModel.activeEdgeType = .houseEdge
        case 1: viewModel.activeEdgeType = .deckEdge
        case 2: viewModel.activeRailingConfig = RailingConfig(railingType: .glass, maxPostSpacing: RailingType.glass.defaultMaxPostSpacing)
        case 3: viewModel.activeRailingConfig = RailingConfig(railingType: .picket, maxPostSpacing: RailingType.picket.defaultMaxPostSpacing)
        case 4: viewModel.activeRailingConfig = RailingConfig(railingType: .cable, maxPostSpacing: RailingType.cable.defaultMaxPostSpacing)
        case 5: viewModel.activeRailingConfig = nil
        default: break
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

        init(viewModel: ARPerimeterViewModel) {
            self.viewModel = viewModel
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

            if let position = performRaycast(session: session, arView: arView, center: center, target: .existingPlaneGeometry) {
                handleHit(position: position)
                return
            }

            if let position = performRaycast(session: session, arView: arView, center: center, target: .estimatedPlane) {
                handleHit(position: position)
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

        private func handleHit(position: SIMD3<Float>) {
            let renderer = self.renderer
            Task { @MainActor in
                self.viewModel.isPlaneDetected = true
                self.viewModel.updateCrosshairPosition(position)
                self.updateRendering(crosshairPosition: position, renderer: renderer)
            }
        }

        // MARK: - Rendering Update (MainActor)

        @MainActor
        private func updateRendering(crosshairPosition: SIMD3<Float>, renderer: ARLineRenderer?) {
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
                        if let crosshair = viewModel.currentCrosshairPosition {
                            viewModel.repositionVertex(index: editIdx, to: crosshair)
                        }
                    } else {
                        viewModel.editingVertexIndex = index
                        viewModel.isEditingVertex = true
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
