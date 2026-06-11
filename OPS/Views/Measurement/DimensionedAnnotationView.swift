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

    public var onRequestCalibrate: (DimensionsData, Bool) -> Void
    public var onSaveToProject: (DimensionsData) async throws -> DimensionedAnnotationSaveResult
    public var onDismiss: () -> Void

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var loadedPhoto: UIImage?
    @State private var loadedDepth: DepthMap?
    @State private var loadFailed = false

    @State private var measurements: [DimensionsData.Measurement] = []
    @State private var openings: [DimensionsData.Opening] = []
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
    @State private var saveState: DimensionedAnnotationSaveState = .idle

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
        initialHasUnsavedChanges: Bool = false,
        onRequestCalibrate: @escaping (DimensionsData, Bool) -> Void = { _, _ in },
        onSaveToProject: @escaping (DimensionsData) async throws -> DimensionedAnnotationSaveResult = { _ in .synced },
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
        if let existing = existingDimensions {
            self._calibration = State(initialValue: existing.calibration)
            self._measurements = State(initialValue: existing.measurements)
            self._openings = State(initialValue: existing.openings)
        } else {
            self._calibration = State(initialValue: initialCalibration)
            self._measurements = State(initialValue: startingMeasurements)
            self._openings = State(initialValue: Self.persistedOpenings(from: detectedOpenings))
        }
        self._hasUnsavedChanges = State(initialValue: initialHasUnsavedChanges)
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

            if saveState.isVisible {
                VStack {
                    AnnotationSaveStateBanner(
                        state: saveState,
                        onRetry: {
                            Task { await saveCurrentAnnotation() }
                        }
                    )
                    .padding(.top, 56)
                    .padding(.horizontal, 12)
                    Spacer()
                }
                .transition(
                    reduceMotion
                        ? .opacity.animation(.linear(duration: 0.15))
                        : .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).animation(.opsCurve200),
                            removal: .opacity.animation(.opsCurve200)
                          )
                )
                .zIndex(11)
            }

        }
        .preferredColorScheme(.dark)
        .task {
            await loadAssetsIfNeeded()
        }
        .sheet(isPresented: $showingCloseConfirmation) {
            CloseConfirmationSheet(
                measurementCount: measurements.count,
                includesCalibrationChange: hasUnsavedCalibrationChange,
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
        .interactiveDismissDisabled(true)
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
        let displayContext = DimensionFormatter.displayContext(for: m.id, openings: openings)
        let formatted = DimensionFormatter.format(
            valueMeters: m.valueMeters,
            primaryUnit: primaryUnit,
            displayContext: displayContext
        )
        let inlineHint = inlineHint(for: m)
        let accessibilityLabel = DimensionFormatter.accessibilityLabel(
            measurementLabel: m.label,
            valueMeters: m.valueMeters,
            primaryUnit: primaryUnit,
            displayContext: displayContext,
            inlineHint: inlineHint,
            includeSecondaryUnit: !formatted.secondary.isEmpty
                && formatted.secondary != formatted.primary
                && formatted.secondary != DimensionFormatter.emptyDash
        )
        let trace = traceProgress[m.id] ?? 1.0
        let opacity = labelOpacity[m.id] ?? 1.0
        let placement = computePlacement(
            for: m,
            in: fit,
            primaryText: formatted.primary,
            secondaryText: formatted.secondary,
            inlineHint: inlineHint
        )
        DimensionLabelView(
            pointA: a,
            pointB: b,
            chipRect: placement,
            measurementLabel: m.label,
            primaryText: formatted.primary,
            secondaryText: formatted.secondary,
            inlineHint: inlineHint,
            accessibilityLabelText: accessibilityLabel,
            maximumLabelWidth: DimensionLabelMetrics.maximumLabelWidth(in: fit.containerSize),
            traceProgress: trace,
            labelOpacity: opacity
        )
    }

    private func computePlacement(for m: DimensionsData.Measurement,
                                  in fit: PhotoFit,
                                  primaryText: String,
                                  secondaryText: String,
                                  inlineHint: String?) -> CGRect {
        // Use the stored side + leader as a starting hint; defer full collision
        // avoidance to the LabelPlacer when committing layout.
        let a = fit.screenPoint(fromPhoto: cg(m.imagePoints.first))
        let b = fit.screenPoint(fromPhoto: cg(m.imagePoints.last))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        return Self.liveDimensionLabelChipRect(
            midpoint: mid,
            labelPlacement: m.labelPlacement,
            primaryText: primaryText,
            secondaryText: secondaryText,
            inlineHint: inlineHint,
            canvasSize: fit.containerSize,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    static func liveDimensionLabelChipRect(
        midpoint: CGPoint,
        labelPlacement: DimensionsData.Measurement.LabelPlacement,
        primaryText: String,
        secondaryText: String,
        inlineHint: String?,
        canvasSize: CGSize,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGRect {
        let metrics = DimensionLabelMetrics(dynamicTypeSize: dynamicTypeSize)
        let maximumWidth = DimensionLabelMetrics.maximumLabelWidth(in: canvasSize)
        let layout = metrics.layout(
            primaryText: primaryText,
            secondaryText: secondaryText,
            inlineHint: inlineHint,
            maximumWidth: maximumWidth
        )
        let rawRect = LabelPlacer.chipRect(
            midpoint: midpoint,
            chipSize: layout.chipSize,
            side: labelPlacement.side,
            leader: CGFloat(labelPlacement.leaderLengthPx)
        )
        return metrics.clampedChipRect(
            rawRect,
            inlineHint: inlineHint,
            canvasSize: canvasSize,
            maximumWidth: maximumWidth
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
            showDepthMissFeedback()
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
            showDepthMissFeedback()
            return
        }
        pushUndo()
        var m2 = m
        m2.primaryDisplayUnit = primaryUnit
        measurements.append(m2)
        hasUnsavedChanges = DimensionedAnnotationWorkflow
            .dirtyAfterMeasurementCommit(previouslyDirty: hasUnsavedChanges)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func showDepthMissFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        ToastCenter.shared.present(Toast(label: Feedback.Err.noDepth, tone: .error))
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
        assignAutoMeasurements(toAdd.map(\.id), to: result.opening)
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
            hasUnsavedChanges = DimensionedAnnotationWorkflow.dirtyAfterAutoMeasure(
                addedMeasurementCount: toAdd.count,
                previouslyDirty: hasUnsavedChanges
            )
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
        hasUnsavedChanges = DimensionedAnnotationWorkflow.dirtyAfterAutoMeasure(
            addedMeasurementCount: toAdd.count,
            previouslyDirty: hasUnsavedChanges
        )
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
                    onRequestCalibrate(currentDimensionsData(), hasUnsavedChanges)
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
        Task { await saveCurrentAnnotation() }
    }

    @MainActor
    private func saveCurrentAnnotation() async {
        if case .saving = saveState { return }

        let payload = currentDimensionsData()
        saveState = .saving(copy: DimensionedAnnotationWorkflow.savingCopy)
        do {
            let result = try await onSaveToProject(payload)
            switch result {
            case .synced:
                hasUnsavedChanges = false
                saveState = .idle
                ToastCenter.shared.present(Feedback.Measure.dimensionsSaved(view: { onDismiss() }))
            case .queuedForRetry:
                let continuity = DimensionedAnnotationWorkflow.queuedSaveState()
                hasUnsavedChanges = continuity.leavesAnnotationDirty
                saveState = continuity.saveState
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } catch {
            let continuity = DimensionedAnnotationWorkflow.saveFailureState()
            hasUnsavedChanges = continuity.leavesAnnotationDirty
            saveState = continuity.saveState
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
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
                ToastCenter.shared.present(Feedback.Measure.pdfReady)
            }
        }
    }

    // MARK: - Close

    private func handleCloseTap() {
        switch DimensionedAnnotationWorkflow.closeDecision(
            hasUnsavedChanges: hasUnsavedChanges,
            saveState: saveState
        ) {
        case .confirmDiscard:
            showingCloseConfirmation = true
        case .dismiss:
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

    private var hasUnsavedCalibrationChange: Bool {
        calibration != initialCalibration
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
            depthAssetUrl: assets.depthURL?.absoluteString,
            sidecarMetadataUrl: assets.sidecarURL.absoluteString,
            measurements: measurements,
            openings: currentOpenings()
        )
    }

    private func currentOpenings() -> [DimensionsData.Opening] {
        let currentMeasurementIDs = Set(measurements.map(\.id))
        return openings.map { opening in
            var filtered = opening
            filtered.measurementIds = filtered.measurementIds.filter {
                currentMeasurementIDs.contains($0)
            }
            return filtered
        }
    }

    private func assignAutoMeasurements(
        _ measurementIDs: [UUID],
        to detectedOpening: DetectedOpening
    ) {
        if let idx = openings.firstIndex(where: { $0.id == detectedOpening.id }) {
            for measurementID in measurementIDs where !openings[idx].measurementIds.contains(measurementID) {
                openings[idx].measurementIds.append(measurementID)
            }
        } else {
            openings.append(Self.persistedOpening(
                from: detectedOpening,
                measurementIds: measurementIDs
            ))
        }
    }

    private static func persistedOpenings(
        from detectedOpenings: [DetectedOpening]
    ) -> [DimensionsData.Opening] {
        detectedOpenings.map { persistedOpening(from: $0, measurementIds: []) }
    }

    private static func persistedOpening(
        from detectedOpening: DetectedOpening,
        measurementIds: [UUID]
    ) -> DimensionsData.Opening {
        DimensionsData.Opening(
            id: detectedOpening.id,
            type: detectedOpening.type,
            boundingPolygon: detectedOpening.boundingPolygon,
            classificationConfidence: detectedOpening.classificationConfidence,
            measurementIds: measurementIds
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
        DepthMapLoader.load(from: assets.depthURL)
    }
}

private struct AnnotationSaveStateBanner: View {
    let state: DimensionedAnnotationSaveState
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let copy = state.copy {
                Text(copy)
                    .font(.panelTitle)
                    .textCase(.uppercase)
                    .foregroundColor(foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.allowsRetry {
                Button(action: onRetry) {
                    Text("RETRY")
                        .font(.panelTitle)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.surfaceActive)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry save")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(OPSStyle.Colors.glassDenseApprox)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .strokeBorder(border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch state {
        case .idle, .saving:
            return OPSStyle.Colors.text2
        case .failed:
            return OPSStyle.Colors.rose
        case .queued:
            return OPSStyle.Colors.tan
        }
    }

    private var border: Color {
        switch state {
        case .idle, .saving:
            return OPSStyle.Colors.line
        case .failed:
            return OPSStyle.Colors.roseLine
        case .queued:
            return OPSStyle.Colors.tanLine
        }
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
