// OPS/OPS/DeckBuilder/Views/SketchCleanupView.swift

import SwiftUI
import SwiftData

/// Cleanup view where users review and correct detection results before importing to canvas.
/// Shows the original photo at reduced opacity with detected geometry overlaid.
struct SketchCleanupView: View {

    // MARK: - Properties

    let scanResult: SketchScanResult
    let projectId: String?
    let companyId: String
    let userId: String?
    let onComplete: (SketchScanResult) -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var vertices: [DetectedVertex]
    @State private var segments: [DetectedLineSegment]
    @State private var ocrResults: [RecognizedText]
    @State private var associations: [DimensionAssociation]
    @State private var confirmedDimensionIds: Set<String> = []
    @State private var rejectedDimensionIds: Set<String> = []
    @State private var eraserActive = false
    @State private var addVertexActive = false
    @State private var showingConflictSheet = false
    @State private var showingAIConsent = false
    @State private var isAIProcessing = false
    @State private var conflictResolution: ConflictResolution = .useAnnotations
    @State private var stairDetections: [(segmentId: String, treadCount: Int)]
    @State private var currentTransform: ImageTransform?
    @State private var scaleConfirmed = false
    @State private var customScaleEntry = false
    @State private var customScaleText = ""
    @State private var overriddenScaleResult: ScaleResult?

    // Client cross-reference
    @Environment(\.modelContext) private var modelContext
    @State private var matchedClient: Client?
    @State private var showingClientBanner = false
    @State private var clientBannerDismissed = false

    /// Stores the image-to-screen coordinate transform for the current layout
    struct ImageTransform {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        /// Convert screen-space point to image-pixel space
        func screenToImage(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - offsetX) / scaleX,
                y: (point.y - offsetY) / scaleY
            )
        }

        /// Convert image-pixel space point to screen-space
        func imageToScreen(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * scaleX + offsetX,
                y: point.y * scaleY + offsetY
            )
        }
    }

    // MARK: - Init

    init(
        scanResult: SketchScanResult,
        projectId: String?,
        companyId: String,
        userId: String?,
        onComplete: @escaping (SketchScanResult) -> Void
    ) {
        self.scanResult = scanResult
        self.projectId = projectId
        self.companyId = companyId
        self.userId = userId
        self.onComplete = onComplete
        self._vertices = State(initialValue: scanResult.contourResult.vertices)
        self._segments = State(initialValue: scanResult.contourResult.segments)
        self._ocrResults = State(initialValue: scanResult.recognizedTexts)
        self._associations = State(initialValue: scanResult.dimensionAssociations)
        self._stairDetections = State(initialValue: scanResult.stairDetections)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            // Canvas area
            ZStack {
                // Background: original photo at 40% opacity
                photoBackground

                // Overlay: detected geometry
                geometryOverlay
            }
            .gesture(eraserGesture)
            .onTapGesture { location in
                if addVertexActive {
                    addVertexAtTap(screenPoint: location)
                }
            }

            // Info banner
            scaleBanner

            // Bottom toolbar
            bottomToolbar
        }
        .background(OPSStyle.Colors.background)
        .sheet(isPresented: $showingConflictSheet) {
            ScaleConflictSheet(
                conflicts: scanResult.scaleResult?.conflicts ?? []
            ) { resolution in
                conflictResolution = resolution
                showingConflictSheet = false
            }
            .presentationDetents([.medium])
        }
        .alert("AI Assist", isPresented: $showingAIConsent) {
            Button("Proceed") {
                runAIFallback()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sketch will be sent to our AI service for analysis. Proceed?")
        }
        .onAppear {
            // Auto-show conflict sheet if there are conflicts
            if let conflicts = scanResult.scaleResult?.conflicts, !conflicts.isEmpty {
                showingConflictSheet = true
            }
            // Auto-trigger AI assist if <3 edges detected
            if segments.count < 3 {
                showingAIConsent = true
            }
            // Client name cross-reference (Fix 4)
            lookupClient()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(OPSStyle.Icons.close)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text("Review Scan")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Import as-is (skip cleanup)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                importToCanvas()
            } label: {
                Text("Import")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Photo Background

    private var photoBackground: some View {
        GeometryReader { geometry in
            let uiImage = UIImage(cgImage: scanResult.sourceImage)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .opacity(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Geometry Overlay

    private var geometryOverlay: some View {
        GeometryReader { geometry in
            let imageSize = CGSize(
                width: scanResult.sourceImage.width,
                height: scanResult.sourceImage.height
            )

            // Calculate how the image fits in the available space
            let fitSize = fitImageSize(imageSize: imageSize, containerSize: geometry.size)
            let offsetX = (geometry.size.width - fitSize.width) / 2
            let offsetY = (geometry.size.height - fitSize.height) / 2
            let scaleX = fitSize.width / imageSize.width
            let scaleY = fitSize.height / imageSize.height

            Canvas { context, size in
                // Draw line segments
                for segment in segments {
                    let start = CGPoint(
                        x: segment.startPoint.x * scaleX + offsetX,
                        y: segment.startPoint.y * scaleY + offsetY
                    )
                    let end = CGPoint(
                        x: segment.endPoint.x * scaleX + offsetX,
                        y: segment.endPoint.y * scaleY + offsetY
                    )

                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)

                    context.stroke(
                        path,
                        with: .color(OPSStyle.Colors.primaryAccent),
                        lineWidth: 2
                    )
                }

                // Draw vertex dots
                for vertex in vertices {
                    let pos = CGPoint(
                        x: vertex.position.x * scaleX + offsetX,
                        y: vertex.position.y * scaleY + offsetY
                    )
                    let dotSize: CGFloat = 8
                    let dotRect = CGRect(
                        x: pos.x - dotSize / 2,
                        y: pos.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(OPSStyle.Colors.primaryAccent)
                    )
                }

                // Draw stair patterns as hatched rectangles
                for detection in stairDetections {
                    if let segment = segments.first(where: { $0.id == detection.segmentId }) {
                        let mid = CGPoint(
                            x: (segment.startPoint.x + segment.endPoint.x) / 2 * scaleX + offsetX,
                            y: (segment.startPoint.y + segment.endPoint.y) / 2 * scaleY + offsetY
                        )
                        // Small stair indicator
                        let stairRect = CGRect(x: mid.x - 15, y: mid.y - 10, width: 30, height: 20)
                        context.stroke(Path(stairRect), with: .color(OPSStyle.Colors.warningStatus), lineWidth: 1)
                        // Hatch lines inside
                        let lineCount = min(detection.treadCount, 6)
                        let spacing = stairRect.width / CGFloat(lineCount + 1)
                        for i in 1...lineCount {
                            var line = Path()
                            let x = stairRect.origin.x + spacing * CGFloat(i)
                            line.move(to: CGPoint(x: x, y: stairRect.origin.y))
                            line.addLine(to: CGPoint(x: x, y: stairRect.maxY))
                            context.stroke(line, with: .color(OPSStyle.Colors.warningStatus), lineWidth: 0.5)
                        }
                    }
                }
            }

            // Dimension labels overlay (SwiftUI views on top of Canvas)
            ForEach(dimensionLabelsData(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)) { label in
                dimensionLabel(label)
                    .position(x: label.position.x, y: label.position.y)
            }

            // Capture transform for eraser and vertex tool
            Color.clear
                .onAppear {
                    currentTransform = ImageTransform(
                        scaleX: scaleX, scaleY: scaleY,
                        offsetX: offsetX, offsetY: offsetY
                    )
                }
                .onChange(of: geometry.size) { _, _ in
                    let newFit = fitImageSize(imageSize: imageSize, containerSize: geometry.size)
                    currentTransform = ImageTransform(
                        scaleX: newFit.width / imageSize.width,
                        scaleY: newFit.height / imageSize.height,
                        offsetX: (geometry.size.width - newFit.width) / 2,
                        offsetY: (geometry.size.height - newFit.height) / 2
                    )
                }
        }
    }

    // MARK: - Dimension Labels

    private struct DimensionLabelData: Identifiable {
        let id: String
        let textId: String
        let text: String
        let position: CGPoint
        let isConfirmed: Bool
        let isRejected: Bool
        let hasConflict: Bool
    }

    private func dimensionLabelsData(scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> [DimensionLabelData] {
        var labels: [DimensionLabelData] = []
        let conflictSegmentIds = Set((scanResult.scaleResult?.conflicts ?? []).map { $0.segmentId })

        for assoc in associations {
            guard let text = ocrResults.first(where: { $0.id == assoc.textId }) else { continue }

            let pos = CGPoint(
                x: text.boundingBox.midX * scaleX + offsetX,
                y: text.boundingBox.midY * scaleY + offsetY
            )

            let formattedDim = DimensionEngine.formatImperial(assoc.dimensionInches)
            let hasConflict = conflictSegmentIds.contains(assoc.segmentId)

            labels.append(DimensionLabelData(
                id: assoc.textId,
                textId: assoc.textId,
                text: formattedDim,
                position: pos,
                isConfirmed: confirmedDimensionIds.contains(assoc.textId),
                isRejected: rejectedDimensionIds.contains(assoc.textId),
                hasConflict: hasConflict
            ))
        }
        return labels
    }

    @ViewBuilder
    private func dimensionLabel(_ label: DimensionLabelData) -> some View {
        if !label.isRejected {
            HStack(spacing: 4) {
                Text(label.text)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(labelColor(for: label))

                // Confirm button
                if !label.isConfirmed {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        confirmedDimensionIds.insert(label.textId)
                        rejectedDimensionIds.remove(label.textId)
                    } label: {
                        Image(OPSStyle.Icons.checkmarkCircleFill)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    }
                    .frame(width: 28, height: 28)
                }

                // Reject button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    rejectedDimensionIds.insert(label.textId)
                    confirmedDimensionIds.remove(label.textId)
                    // Remove from associations
                    associations.removeAll { $0.textId == label.textId }
                } label: {
                    Image(OPSStyle.Icons.close)
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.errorStatus.opacity(0.8))
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.cardBackground.opacity(0.85))
            )
        }
    }

    private func labelColor(for label: DimensionLabelData) -> Color {
        if label.isConfirmed {
            return OPSStyle.Colors.successStatus
        } else if label.hasConflict {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }

    // MARK: - Client Banner (Fix 4)

    @ViewBuilder
    private var clientBanner: some View {
        if let clientName = scanResult.clientNameCandidate, !clientBannerDismissed {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(OPSStyle.Icons.teamMember)
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                if let client = matchedClient {
                    Text("Link to \(client.name)'s project?")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                } else {
                    Text("Create client \"\(clientName)\"?")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    clientBannerDismissed = true
                    // Client linking is handled at import time via onComplete
                } label: {
                    Text("Yes")
                        .font(OPSStyle.Typography.smallButton)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    clientBannerDismissed = true
                } label: {
                    Text("No")
                        .font(OPSStyle.Typography.smallButton)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.cardBackground)
        }
    }

    // MARK: - Scale Banner (Fix 6: Interactive)

    private var activeScaleResult: ScaleResult? {
        overriddenScaleResult ?? scanResult.scaleResult
    }

    private var scaleBanner: some View {
        VStack(spacing: 0) {
            // Client banner above scale
            clientBanner

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: scanResult.gridResult.hasGrid ? "grid" : "ruler")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                if !scaleConfirmed {
                    // Interactive: ask for confirmation
                    scaleConfirmationRow
                } else {
                    // Confirmed: show read-only
                    scaleDisplayText
                }

                Spacer()

                // Vertex/edge count
                Text("\(vertices.count) pts · \(segments.count) edges")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackground)

            // Custom scale entry row
            if customScaleEntry {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("1 square =")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("e.g. 6 inches", text: $customScaleText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .textFieldStyle(.plain)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: customScaleText) { _, newValue in
                            let sanitized = DimensionEngine.sanitizeQuotesForLiveInput(newValue)
                            if sanitized != newValue { customScaleText = sanitized }
                        }
                        .frame(width: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                                )
                        )
                        .keyboardType(.decimalPad)

                    Button {
                        applyCustomScale()
                    } label: {
                        Text("Apply")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.cardBackground)
            }
        }
    }

    @ViewBuilder
    private var scaleConfirmationRow: some View {
        if scanResult.gridResult.hasGrid {
            if case .graphPaper(_, let unitName) = activeScaleResult?.source {
                Text(unitName + " Correct?")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                scaleConfirmButtons
            } else {
                Text("Graph paper detected")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                scaleConfirmButtons
            }
        } else if activeScaleResult != nil {
            Text("Scale from dimensions. Correct?")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            scaleConfirmButtons
        } else {
            Text("No scale detected — enter dimensions on canvas")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
    }

    private var scaleConfirmButtons: some View {
        HStack(spacing: 6) {
            Button {
                scaleConfirmed = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("Yes")
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.successStatus)
            }

            Button {
                customScaleEntry = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("No")
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Button {
                customScaleEntry = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("Custom")
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }

    @ViewBuilder
    private var scaleDisplayText: some View {
        if case .graphPaper(_, let unitName) = activeScaleResult?.source {
            Text(unitName)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.successStatus)
            Image(OPSStyle.Icons.checkmarkCircleFill)
                .font(.system(size: 12))
                .foregroundColor(OPSStyle.Colors.successStatus)
        } else if activeScaleResult != nil {
            Text("Scale confirmed")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.successStatus)
            Image(OPSStyle.Icons.checkmarkCircleFill)
                .font(.system(size: 12))
                .foregroundColor(OPSStyle.Colors.successStatus)
        } else {
            Text("No scale")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
    }

    /// Apply a custom scale entered by the user (e.g., "6 inches" per grid square)
    private func applyCustomScale() {
        guard let gridSpacing = scanResult.gridResult.gridSpacingPixels, gridSpacing > 0 else {
            // No grid — parse as a direct pixels-per-inch factor from dimension input
            if let inches = DimensionEngine.parseToInches(customScaleText, system: .imperial), inches > 0 {
                overriddenScaleResult = ScaleResult(
                    scaleFactor: 1.0, // Will be recalculated
                    source: .averaged,
                    conflicts: []
                )
            }
            customScaleEntry = false
            scaleConfirmed = true
            return
        }

        // Parse custom scale: expect a dimension like "6 inches", "1 foot", "6", "12"
        if let inchesPerSquare = DimensionEngine.parseToInches(customScaleText, system: .imperial), inchesPerSquare > 0 {
            let pixelsPerInch = gridSpacing / inchesPerSquare
            let unitDesc = String(format: "1 square = %@", DimensionEngine.formatImperial(inchesPerSquare))
            overriddenScaleResult = ScaleResult(
                scaleFactor: pixelsPerInch,
                source: .graphPaper(squaresPerUnit: 12.0 / inchesPerSquare, unitName: unitDesc),
                conflicts: ScaleInference.detectConflicts(
                    associations: associations,
                    segments: segments,
                    pixelsPerInch: pixelsPerInch
                )
            )
        }

        customScaleEntry = false
        scaleConfirmed = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Bottom Toolbar

    private func toolButton(icon: String, label: String, isActive: Bool, activeColor: Color = OPSStyle.Colors.warningStatus, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isActive ? activeColor : OPSStyle.Colors.primaryAccent)
                Text(label)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(isActive ? activeColor : OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Eraser toggle
            toolButton(icon: "eraser", label: "Eraser", isActive: eraserActive) {
                eraserActive.toggle()
                if eraserActive { addVertexActive = false }
            }

            // Add vertex tool (Fix 3)
            toolButton(icon: "plus.circle", label: "Vertex", isActive: addVertexActive, activeColor: OPSStyle.Colors.primaryAccent) {
                addVertexActive.toggle()
                if addVertexActive { eraserActive = false }
            }

            // AI Assist (Fix 2)
            if !isAIProcessing {
                toolButton(icon: "sparkles", label: "AI Assist", isActive: false) {
                    showingAIConsent = true
                }
            } else {
                VStack(spacing: 2) {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryAccent)
                        .frame(width: 20, height: 20)
                    Text("AI...")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }

            // Conflicts button (if any)
            if let conflicts = activeScaleResult?.conflicts, !conflicts.isEmpty {
                toolButton(icon: "exclamationmark.triangle", label: "\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")", isActive: false, activeColor: OPSStyle.Colors.warningStatus) {
                    showingConflictSheet = true
                }
            }

            Spacer()

            // Done button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                importToCanvas()
            } label: {
                Text("Done")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .fill(OPSStyle.Colors.primaryAccent)
                    )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Eraser Gesture

    private var eraserGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard eraserActive else { return }
                eraseNear(screenPoint: value.location)
            }
    }

    /// Erase geometry near a screen-space point by transforming to image-pixel space first
    private func eraseNear(screenPoint: CGPoint) {
        guard let transform = currentTransform else { return }
        let imagePoint = transform.screenToImage(screenPoint)

        // Scale the erase radius to image space
        let screenRadius: CGFloat = 30
        let imageRadius = screenRadius / transform.scaleX

        // Remove nearest vertex within radius
        if let idx = vertices.firstIndex(where: {
            SnapEngine.distance($0.position, imagePoint) < imageRadius
        }) {
            let removedVertex = vertices[idx]
            // Remove segments connected to this vertex
            segments.removeAll { seg in
                removedVertex.connectedSegmentIds.contains(seg.id)
            }
            vertices.remove(at: idx)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        // Remove nearest segment within radius
        if let idx = segments.firstIndex(where: { seg in
            let (_, dist) = PolygonMath.closestPointOnSegment(
                point: imagePoint,
                segStart: seg.startPoint,
                segEnd: seg.endPoint
            )
            return dist < imageRadius
        }) {
            segments.remove(at: idx)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Add Vertex (Fix 3)

    /// Add a vertex at a tap location by splitting the nearest edge
    private func addVertexAtTap(screenPoint: CGPoint) {
        guard let transform = currentTransform else { return }
        let imagePoint = transform.screenToImage(screenPoint)

        // Find nearest edge to split
        var closestSegIdx: Int?
        var closestDist = Double.infinity
        var closestPointOnSeg = CGPoint.zero

        for (idx, seg) in segments.enumerated() {
            let (closest, dist) = PolygonMath.closestPointOnSegment(
                point: imagePoint,
                segStart: seg.startPoint,
                segEnd: seg.endPoint
            )
            if dist < closestDist {
                closestDist = dist
                closestSegIdx = idx
                closestPointOnSeg = closest
            }
        }

        guard let segIdx = closestSegIdx else { return }
        let splitSeg = segments[segIdx]

        // Create new vertex at the closest point on the edge
        let newVertexId = UUID().uuidString
        let newVertex = DetectedVertex(
            id: newVertexId,
            position: closestPointOnSeg,
            connectedSegmentIds: []
        )

        // Create two new segments replacing the split one
        let seg1Id = UUID().uuidString
        let seg2Id = UUID().uuidString

        let seg1 = DetectedLineSegment(
            id: seg1Id,
            startPoint: splitSeg.startPoint,
            endPoint: closestPointOnSeg
        )
        let seg2 = DetectedLineSegment(
            id: seg2Id,
            startPoint: closestPointOnSeg,
            endPoint: splitSeg.endPoint
        )

        // Update the new vertex's connections
        var updatedVertex = newVertex
        updatedVertex.connectedSegmentIds = [seg1Id, seg2Id]

        // Update existing vertices: replace old segment ID with new segment IDs
        for i in 0..<vertices.count {
            if let removeIdx = vertices[i].connectedSegmentIds.firstIndex(of: splitSeg.id) {
                vertices[i].connectedSegmentIds.remove(at: removeIdx)
                // Start vertex gets seg1, end vertex gets seg2
                if SnapEngine.distance(vertices[i].position, splitSeg.startPoint) <
                   SnapEngine.distance(vertices[i].position, splitSeg.endPoint) {
                    vertices[i].connectedSegmentIds.append(seg1Id)
                } else {
                    vertices[i].connectedSegmentIds.append(seg2Id)
                }
            }
        }

        // Apply mutations
        segments.remove(at: segIdx)
        segments.append(seg1)
        segments.append(seg2)
        vertices.append(updatedVertex)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - AI Fallback (Fix 2)

    private func runAIFallback() {
        // TODO: Store API key in Keychain or app config — for now, check UserDefaults
        guard let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key"), !apiKey.isEmpty else {
            // No API key configured — inform user
            return
        }

        isAIProcessing = true
        Task {
            do {
                let aiResult = try await SketchAIFallback.analyze(
                    image: scanResult.sourceImage,
                    apiKey: apiKey
                )
                // Replace current detection with AI results
                vertices = aiResult.contourResult.vertices
                segments = aiResult.contourResult.segments
                ocrResults = aiResult.recognizedTexts
                associations = aiResult.dimensionAssociations
                stairDetections = aiResult.stairDetections
                if let scale = aiResult.scaleResult {
                    overriddenScaleResult = scale
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("[SketchCleanupView] AI fallback failed: \(error)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isAIProcessing = false
        }
    }

    // MARK: - Client Lookup (Fix 4)

    private func lookupClient() {
        guard let clientName = scanResult.clientNameCandidate, !clientName.isEmpty else { return }

        // Query Client model by company and name similarity
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { client in
                client.companyId == companyId && client.deletedAt == nil
            }
        )

        do {
            let clients = try modelContext.fetch(descriptor)
            // Fuzzy match: case-insensitive contains
            let lowered = clientName.lowercased()
            matchedClient = clients.first { client in
                client.name.lowercased().contains(lowered) || lowered.contains(client.name.lowercased())
            }
            showingClientBanner = matchedClient != nil || !clientName.isEmpty
        } catch {
            print("[SketchCleanupView] Client lookup failed: \(error)")
        }
    }

    // MARK: - Import to Canvas

    private func importToCanvas() {
        // Re-check closure after user edits
        let isClosed = ContourExtractor.checkClosed(
            vertices: vertices,
            segments: segments
        )

        let updatedContour = ContourExtractionResult(
            vertices: vertices,
            segments: segments,
            isClosed: isClosed,
            stairPatterns: scanResult.contourResult.stairPatterns
        )

        var updatedResult = SketchScanResult(
            sourceImage: scanResult.sourceImage,
            gridResult: scanResult.gridResult,
            contourResult: updatedContour,
            recognizedTexts: ocrResults,
            dimensionAssociations: associations,
            scaleResult: activeScaleResult,
            clientNameCandidate: scanResult.clientNameCandidate,
            stairDetections: stairDetections
        )
        updatedResult.conflictResolution = conflictResolution

        onComplete(updatedResult)
    }

    // MARK: - Helpers

    private func fitImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let scaleX = containerSize.width / imageSize.width
        let scaleY = containerSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
