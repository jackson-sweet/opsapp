// OPS/OPS/DeckBuilder/Views/SketchCleanupView.swift

import SwiftUI

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
    @State private var showingConflictSheet = false
    @State private var conflictResolution: ConflictResolution = .useAnnotations
    @State private var stairDetections: [(segmentId: String, treadCount: Int)]

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
        .onAppear {
            // Auto-show conflict sheet if there are conflicts
            if let conflicts = scanResult.scaleResult?.conflicts, !conflicts.isEmpty {
                showingConflictSheet = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
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
                        Image(systemName: "checkmark.circle.fill")
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.errorStatus.opacity(0.8))
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
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

    // MARK: - Scale Banner

    private var scaleBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: scanResult.gridResult.hasGrid ? "grid" : "ruler")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            if scanResult.gridResult.hasGrid {
                if case .graphPaper(_, let unitName) = scanResult.scaleResult?.source {
                    Text(unitName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    Text("Graph paper detected")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            } else if scanResult.scaleResult != nil {
                Text("Scale from dimensions")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            } else {
                Text("No scale detected — enter dimensions on canvas")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Spacer()

            // Client name if detected
            if let clientName = scanResult.clientNameCandidate {
                Text(clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            // Vertex/edge count
            Text("\(vertices.count) pts · \(segments.count) edges")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Eraser toggle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                eraserActive.toggle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "eraser")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(eraserActive ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent)
                    Text("Eraser")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(eraserActive ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }

            // Conflicts button (if any)
            if let conflicts = scanResult.scaleResult?.conflicts, !conflicts.isEmpty {
                Button {
                    showingConflictSheet = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                        Text("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
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
                eraseNear(point: value.location)
            }
    }

    private func eraseNear(point: CGPoint) {
        let eraseRadius: CGFloat = 30

        // Remove nearest vertex within radius
        if let idx = vertices.firstIndex(where: {
            SnapEngine.distance($0.position, point) < eraseRadius
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
                point: point,
                segStart: seg.startPoint,
                segEnd: seg.endPoint
            )
            return dist < eraseRadius
        }) {
            segments.remove(at: idx)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Import to Canvas

    private func importToCanvas() {
        // Build updated scan result with user's edits
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
            scaleResult: scanResult.scaleResult,
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
