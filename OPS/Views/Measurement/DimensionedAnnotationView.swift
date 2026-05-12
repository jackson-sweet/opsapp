//
//  DimensionedAnnotationView.swift
//  OPS
//
//  Phase E of the LiDAR Dimensioned Photo Capture initiative
//  (spec 2026-05-10, §5.2). Full-screen photo viewer with measurement
//  tooling that lets the operator place, refine, and export dimensions
//  on a single capture.
//
//  Public surface:
//    init(assets:                  // Phase B capture descriptor
//         preloadedPhoto:          // pre-decoded UIImage (optional)
//         preloadedDepthMap:       // pre-loaded depth (optional)
//         anchors:                 // fine-grained mesh snapshot (optional)
//         detectedOpenings:        // auto-detected openings (empty → AUTO hidden)
//         initialCalibration:      // baseline calibration (drives accuracy badge)
//         capability:              // capture capability (gates CALIBRATE)
//         coplanarOnly:            // true → COPLANAR ONLY chip below badge
//         existingDimensions:      // re-open path
//         onRequestCalibrate:      // returns to §5.1 in calibration mode
//         onSaveToProject:         // persists DimensionsData via PhotoAnnotation
//         onDismiss:               // close
//    )
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.3 §3.5 §3.6 §5.2 §5.3
//

import SwiftUI
import UIKit
import PencilKit

public struct DimensionedAnnotationView: View {

    // MARK: - Inputs

    public let assets: CapturedAssets
    public let preloadedPhoto: UIImage?
    public let preloadedDepthMap: DepthMap?
    public let anchors: AnchorSnapshot?
    public let detectedOpenings: [DetectedOpening]
    public let initialCalibration: DimensionsData.Calibration
    public let capability: CaptureCapability
    public let coplanarOnly: Bool
    public let existingDimensions: DimensionsData?

    public var onRequestCalibrate: () -> Void
    public var onSaveToProject: (DimensionsData) -> Void
    public var onDismiss: () -> Void

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loadedPhoto: UIImage?
    @State private var loadedDepth: DepthMap?
    @State private var loadFailed = false

    @State private var measurements: [DimensionsData.Measurement] = []
    @State private var undoStack: [[DimensionsData.Measurement]] = []
    @State private var redoStack: [[DimensionsData.Measurement]] = []
    @State private var hasUnsavedChanges = false

    @State private var activeTool: MeasurementTool = .measure
    @State private var primaryUnit: DimensionsData.Measurement.DisplayUnit = .imperialFraction
    @State private var saveUnitAsDefault = false

    @State private var inProgressPointA: CGPoint?  // photo-pixel
    @State private var activeTouchScreen: CGPoint?
    @State private var calibration: DimensionsData.Calibration
    @State private var pulseBadge = false

    // Trace animation state per measurement id (for auto-measure §5.3 row 5).
    @State private var traceProgress: [UUID: CGFloat] = [:]
    @State private var labelOpacity: [UUID: Double] = [:]

    @State private var showingCloseConfirmation = false
    @State private var showingCalibrateConfirmation = false
    @State private var showingExport = false
    @State private var sillUnavailableReason: SillUnavailableReason?

    @State private var pencilDrawing = PKDrawing()

    // MARK: - Init helper

    public init(
        assets: CapturedAssets,
        preloadedPhoto: UIImage? = nil,
        preloadedDepthMap: DepthMap? = nil,
        anchors: AnchorSnapshot? = nil,
        detectedOpenings: [DetectedOpening] = [],
        initialCalibration: DimensionsData.Calibration,
        capability: CaptureCapability,
        coplanarOnly: Bool = false,
        existingDimensions: DimensionsData? = nil,
        onRequestCalibrate: @escaping () -> Void = {},
        onSaveToProject: @escaping (DimensionsData) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {},
        // Initial-state convenience for re-open and tests:
        startingMeasurements: [DimensionsData.Measurement] = []
    ) {
        self.assets = assets
        self.preloadedPhoto = preloadedPhoto
        self.preloadedDepthMap = preloadedDepthMap
        self.anchors = anchors
        self.detectedOpenings = detectedOpenings
        self.initialCalibration = initialCalibration
        self.capability = capability
        self.coplanarOnly = coplanarOnly
        self.existingDimensions = existingDimensions
        self.onRequestCalibrate = onRequestCalibrate
        self.onSaveToProject = onSaveToProject
        self.onDismiss = onDismiss
        self._calibration = State(initialValue: initialCalibration)
        if let existing = existingDimensions {
            self._measurements = State(initialValue: existing.measurements)
        } else {
            self._measurements = State(initialValue: startingMeasurements)
        }
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                photoArea
                MeasurementToolbar(
                    activeTool: $activeTool,
                    config: toolbarConfig,
                    onSelect: handleToolSelect,
                    onUndo: performUndo,
                    onRedo: performRedo
                )
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadAssetsIfNeeded()
        }
        .sheet(isPresented: $showingCloseConfirmation) {
            CloseConfirmationSheet(
                measurementCount: measurements.count,
                onDiscard: {
                    showingCloseConfirmation = false
                    onDismiss()
                },
                onKeepEditing: { showingCloseConfirmation = false }
            )
        }
        .sheet(isPresented: $showingCalibrateConfirmation) {
            calibrateConfirmationSheet
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(
                onSaveToProject: {
                    showingExport = false
                    persistAndSave()
                },
                onExportPDF: {
                    showingExport = false
                    Task { await exportPDF() }
                },
                onCancel: { showingExport = false }
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("MEASURE")
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(2)
                .foregroundColor(OPSStyle.Colors.text)
            Spacer()
            Button(action: handleCloseTap) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    // MARK: - Photo area

    private var photoArea: some View {
        GeometryReader { geo in
            let fit = PhotoFit(photoSize: photoPixelSize, containerSize: geo.size)
            ZStack(alignment: .topTrailing) {
                Color.black

                if let photo = loadedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if loadFailed {
                    failedPhotoState
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.opsAccent))
                }

                // PencilKit MARK layer (z-order 4, below dimensions)
                if activeTool == .mark, let photo = loadedPhoto {
                    PencilKitCanvas(drawing: $pencilDrawing,
                                    backgroundSize: photo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(true)
                }

                // Dimension labels + leaders + endpoints (z-order 2 & 3)
                ForEach(measurements) { m in
                    measurementOverlay(m, fit: fit)
                }

                // In-progress first point (z-order 1)
                if let p = inProgressPointA {
                    let screen = fit.screenPoint(fromPhoto: p)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .position(screen)
                }

                // Loupe (z-order 1)
                if let touch = activeTouchScreen,
                   let photoPx = fit.photoPixel(fromScreen: touch),
                   let photo = loadedPhoto {
                    MeasureLoupe(
                        photo: photo,
                        touchPhotoPixel: photoPx,
                        touchScreenPoint: touch,
                        canvasBounds: CGRect(origin: .zero, size: geo.size)
                    )
                }

                // Unit chip (top-right)
                UnitCycleChip(
                    unit: $primaryUnit,
                    saveAsDefault: $saveUnitAsDefault
                )
                .padding(.top, 8)
                .padding(.trailing, 12)

                // Accuracy badge stack (bottom-right)
                VStack(alignment: .trailing, spacing: 6) {
                    AccuracyBadge(state: accuracyState, pulseTrigger: pulseBadge)
                    if coplanarOnly && calibration.method == .referenceObject {
                        CoplanarOnlyChip()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
            .gesture(measurementGesture(fit: fit))
        }
    }

    @ViewBuilder
    private func measurementOverlay(_ m: DimensionsData.Measurement,
                                    fit: PhotoFit) -> some View {
        let a = fit.screenPoint(fromPhoto: cg(m.imagePoints.first))
        let b = fit.screenPoint(fromPhoto: cg(m.imagePoints.last))
        let formatted = DimensionFormatter.format(
            valueMeters: m.valueMeters,
            primaryUnit: primaryUnit
        )
        let trace = traceProgress[m.id] ?? 1.0
        let opacity = labelOpacity[m.id] ?? 1.0
        let placement = computePlacement(for: m, in: fit)
        DimensionLabelView(
            pointA: a,
            pointB: b,
            chipRect: placement,
            primaryText: formatted.primary,
            secondaryText: formatted.secondary,
            inlineHint: inlineHint(for: m),
            traceProgress: trace,
            labelOpacity: opacity
        )
    }

    private func computePlacement(for m: DimensionsData.Measurement,
                                  in fit: PhotoFit) -> CGRect {
        // Use the stored side + leader as a starting hint; defer full collision
        // avoidance to the LabelPlacer when committing layout.
        let a = fit.screenPoint(fromPhoto: cg(m.imagePoints.first))
        let b = fit.screenPoint(fromPhoto: cg(m.imagePoints.last))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let chipSize = CGSize(width: 110, height: 36)
        return LabelPlacer.chipRect(
            midpoint: mid,
            chipSize: chipSize,
            side: m.labelPlacement.side,
            leader: CGFloat(m.labelPlacement.leaderLengthPx)
        )
    }

    private var failedPhotoState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(OPSStyle.Colors.text3)
            Text("// PHOTO UNAVAILABLE")
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text2)
        }
    }

    // MARK: - Gestures

    private func measurementGesture(fit: PhotoFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard activeTool == .measure else { return }
                activeTouchScreen = value.location
            }
            .onEnded { value in
                activeTouchScreen = nil
                guard activeTool == .measure else { return }
                guard let photoPx = fit.photoPixel(fromScreen: value.location) else { return }
                handleMeasureTap(photoPixel: photoPx)
            }
    }

    private func handleMeasureTap(photoPixel: CGPoint) {
        if let firstPoint = inProgressPointA {
            // Second tap — commit.
            commitManualMeasurement(from: firstPoint, to: photoPixel)
            inProgressPointA = nil
        } else {
            inProgressPointA = photoPixel
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Manual measurement commit

    private func commitManualMeasurement(from a: CGPoint, to b: CGPoint) {
        guard let depth = currentDepthMap() else {
            // Without a depth map we cannot raycast — surface the failure
            // path; spec §5.2 will toast `// ERROR — NO DEPTH AT POINT …`.
            // For Phase E the parent owns the toast surface; we just drop.
            return
        }
        let raycaster = DepthRaycaster(
            intrinsics: assets.intrinsics,
            depth: depth,
            photoSize: photoPixelSize
        )
        guard let m = raycaster.linearMeasurement(
            from: a, to: b,
            label: "Manual",
            primaryDisplayUnit: primaryUnit,
            source: .manual
        ) else {
            return
        }
        pushUndo()
        var m2 = m
        m2.primaryDisplayUnit = primaryUnit
        measurements.append(m2)
        hasUnsavedChanges = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Auto measure

    private func runAutoMeasure() {
        guard let anchors = anchors,
              let firstOpening = detectedOpenings.first else { return }
        let result = AutoMeasurer.measure(
            opening: firstOpening,
            anchors: anchors,
            photoSize: photoPixelSize
        )
        pushUndo()
        let toAdd = result.allMeasurements.map { m in
            var m2 = m
            m2.primaryDisplayUnit = primaryUnit
            return m2
        }
        sillUnavailableReason = result.sillUnavailableReason

        if reduceMotion {
            measurements.append(contentsOf: toAdd)
            for m in toAdd {
                traceProgress[m.id] = 1.0
                labelOpacity[m.id] = 0
                withAnimation(.linear(duration: 0.2)) {
                    labelOpacity[m.id] = 1.0
                }
            }
            hasUnsavedChanges = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        // Spec §5.3 row 5 — stagger 50ms between lines, 180ms each line.
        for (idx, m) in toAdd.enumerated() {
            traceProgress[m.id] = 0
            labelOpacity[m.id] = 0
            measurements.append(m)
            let delay = Double(idx) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                    traceProgress[m.id] = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)) {
                        labelOpacity[m.id] = 1.0
                    }
                }
            }
        }
        // Single success haptic at end of staggered traces.
        let totalDuration = Double(toAdd.count - 1) * 0.05 + 0.18 + 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        hasUnsavedChanges = true
    }

    private func inlineHint(for m: DimensionsData.Measurement) -> String? {
        // The sill-fallback hint attaches to the bottom-of-window
        // measurement; we surface it once via the first measurement when
        // sill is unavailable. For Phase E we render the hint inline next
        // to the height measurement (label == "Height") since that's the
        // edge where the sill would have anchored.
        guard sillUnavailableReason == .noFloorMeshNearby,
              m.label == "Height" else { return nil }
        return "// SILL — NO FLOOR REFERENCE"
    }

    // MARK: - Tool selection

    private func handleToolSelect(_ tool: MeasurementTool) {
        switch tool {
        case .measure: break  // active tool flag is sufficient
        case .auto:    runAutoMeasure()
        case .calibrate:
            showingCalibrateConfirmation = true
        case .mark:    break
        case .note:    break
        case .export:
            guard !measurements.isEmpty else { return }
            showingExport = true
        }
    }

    // MARK: - Undo / redo

    private func pushUndo() {
        undoStack.append(measurements)
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(measurements)
        measurements = prev
        hasUnsavedChanges = !measurements.isEmpty
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(measurements)
        measurements = next
        hasUnsavedChanges = true
    }

    // MARK: - Calibration

    private var calibrateConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("// CALIBRATE")
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text)
            Text("PLACE A CREDIT CARD OR OPS MARKER IN FRAME AND RECAPTURE.\nACCURACY UPGRADES TO ±5 MM.")
                .font(.custom("JetBrainsMono-Regular", size: 12))
                .foregroundColor(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    showingCalibrateConfirmation = false
                } label: {
                    Text("CANCEL")
                        .font(.custom("CakeMono-Light", size: 14))
                        .tracking(1)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(OPSStyle.Colors.surfaceActive)
                        )
                }
                Button {
                    showingCalibrateConfirmation = false
                    onRequestCalibrate()
                } label: {
                    Text("CONTINUE")
                        .font(.custom("CakeMono-Light", size: 14))
                        .tracking(1)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(OPSStyle.Colors.opsAccent)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .presentationDetents([.height(240)])
    }

    // MARK: - Export

    private func persistAndSave() {
        let payload = currentDimensionsData()
        hasUnsavedChanges = false
        onSaveToProject(payload)
    }

    private func exportPDF() async {
        let data = PDFExporter.render(
            photo: loadedPhoto,
            dimensions: currentDimensionsData(),
            metadata: .init(
                projectName: "MEASURE",
                capturedAt: assets.captureFinishedAt,
                capturedByName: nil
            ),
            accuracy: .init(
                text: accuracyState.displayText,
                coplanarOnly: coplanarOnly
            )
        )
        await MainActor.run {
            let activity = UIActivityViewController(
                activityItems: [data],
                applicationActivities: nil
            )
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(activity, animated: true)
            }
        }
    }

    // MARK: - Close

    private func handleCloseTap() {
        if hasUnsavedChanges {
            showingCloseConfirmation = true
        } else {
            onDismiss()
        }
    }

    // MARK: - Derived state

    private var toolbarConfig: MeasurementToolbarConfig {
        MeasurementToolbarConfig(
            hasAuto: !detectedOpenings.isEmpty && anchors != nil,
            hasCalibrate: capability != .noDepth,
            canExport: !measurements.isEmpty,
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty
        )
    }

    private var accuracyState: AccuracyState {
        if calibration.method == .referenceObject {
            return .calibrated
        }
        switch capability {
        case .lidar:   return .lidarUncalibrated
        case .visual:  return .visualSlam
        case .noDepth: return .noDepth
        }
    }

    private var photoPixelSize: CGSize {
        CGSize(
            width: CGFloat(assets.intrinsics.imageWidth),
            height: CGFloat(assets.intrinsics.imageHeight)
        )
    }

    private func currentDimensionsData() -> DimensionsData {
        DimensionsData(
            captureMode: captureMode(),
            calibration: calibration,
            intrinsics: assets.intrinsics,
            depthAssetUrl: assets.depthURL.absoluteString,
            sidecarMetadataUrl: assets.sidecarURL.absoluteString,
            measurements: measurements,
            openings: detectedOpenings.map { opening in
                DimensionsData.Opening(
                    id: opening.id,
                    type: opening.type,
                    boundingPolygon: opening.boundingPolygon,
                    classificationConfidence: opening.classificationConfidence,
                    measurementIds: []
                )
            }
        )
    }

    private func captureMode() -> DimensionsData.CaptureMode {
        switch capability {
        case .lidar:   return .lidar
        case .visual:  return .visual
        case .noDepth: return .manualScale
        }
    }

    private func currentDepthMap() -> DepthMap? {
        return loadedDepth ?? preloadedDepthMap
    }

    private func cg(_ pt: DimensionsData.Point2?) -> CGPoint {
        guard let pt = pt else { return .zero }
        return CGPoint(x: pt.x, y: pt.y)
    }

    // MARK: - Asset loading

    private func loadAssetsIfNeeded() async {
        if loadedPhoto == nil {
            if let photo = preloadedPhoto {
                loadedPhoto = photo
            } else if let data = try? Data(contentsOf: assets.heicURL),
                      let img = UIImage(data: data) {
                loadedPhoto = img
            } else {
                loadFailed = true
            }
        }
        if loadedDepth == nil, preloadedDepthMap == nil {
            loadedDepth = loadDepthFromDisk()
        }
    }

    private func loadDepthFromDisk() -> DepthMap? {
        guard let data = try? Data(contentsOf: assets.depthURL) else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        let width = 768
        guard count % width == 0 else { return nil }
        let height = count / width
        let values = data.withUnsafeBytes { raw -> [Float] in
            let p = raw.bindMemory(to: Float.self)
            return Array(p)
        }
        return DepthMap(width: width, height: height, values: values)
    }
}

// MARK: - PhotoFit

/// Maps between photo-pixel coordinates (4032×3024) and screen-canvas
/// coordinates (the fitted rect inside `containerSize`, with letterbox).
public struct PhotoFit {
    public let photoSize: CGSize
    public let containerSize: CGSize

    public var fittedFrame: CGRect {
        guard photoSize.width > 0, photoSize.height > 0 else { return .zero }
        let scale = min(
            containerSize.width / photoSize.width,
            containerSize.height / photoSize.height
        )
        let size = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    public func screenPoint(fromPhoto photoPixel: CGPoint) -> CGPoint {
        let f = fittedFrame
        guard photoSize.width > 0 else { return .zero }
        let scale = f.width / photoSize.width
        return CGPoint(
            x: f.minX + photoPixel.x * scale,
            y: f.minY + photoPixel.y * scale
        )
    }

    public func photoPixel(fromScreen screenPoint: CGPoint) -> CGPoint? {
        let f = fittedFrame
        guard f.contains(screenPoint), photoSize.width > 0 else { return nil }
        let scale = f.width / photoSize.width
        return CGPoint(
            x: (screenPoint.x - f.minX) / scale,
            y: (screenPoint.y - f.minY) / scale
        )
    }
}

// MARK: - PencilKit canvas

private struct PencilKitCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let backgroundSize: CGSize

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawing = drawing
        v.tool = PKInkingTool(.pen, color: .systemYellow, width: 4)
        v.backgroundColor = .clear
        v.isOpaque = false
        v.delegate = context.coordinator
        v.drawingPolicy = .anyInput
        return v
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitCanvas
        init(parent: PencilKitCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

// MARK: - UIWindowScene helper

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
