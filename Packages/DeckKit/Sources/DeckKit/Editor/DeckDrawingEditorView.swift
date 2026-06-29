import CoreGraphics
import OPSDesignKit
import SwiftUI

private enum DeckDrawingEditorCopy {
    static let drawMode = String(localized: "DRAW")
    static let frameMode = String(localized: "FRAME")
    static let codeMode = String(localized: "CODE")
    static let codeAlert = String(localized: "CODE")
    static let codeOff = String(localized: "OFF")
    static let openEndsPrefix = String(localized: "OPEN ENDS")
    static let areaPrefix = String(localized: "AREA")
    static let emptyArea = String(localized: "—")
}

public struct DeckDrawingEditorView: View {
    @StateObject private var model: DeckDrawingEditorModel
    @State private var layerVisibility: FramingLayer = .all
    @State private var isDraggingLine = false

    public init(
        drawingData: DeckDrawingData,
        runtime: DeckRuntime,
        onPersist: @escaping (DeckDrawingData) -> Void
    ) {
        _model = StateObject(
            wrappedValue: DeckDrawingEditorModel(
                drawingData: drawingData,
                capabilities: DeckCapabilities.forSurface(runtime.context.appSurface),
                codeProfile: runtime.codeProfile,
                onPersist: onPersist
            )
        )
    }

    public var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            statusBar

            GeometryReader { geometry in
                drawingCanvas(size: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OPSStyle.Colors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                            .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
                    .gesture(drawGesture)
            }

            if model.capabilities.contains(.plausibleFrame) || model.capabilities.contains(.groundCover) {
                FramingControlsView(
                    framing: model.drawingData.framing,
                    loadPreset: model.selectedLoadPreset,
                    selectedGroundCover: model.drawingData.terrain?.groundCover.first?.cover ?? .grass,
                    framingNeedsRegeneration: false,
                    canGenerateFrame: model.capabilities.contains(.plausibleFrame),
                    canPickGround: model.capabilities.contains(.groundCover),
                    layerVisibility: $layerVisibility,
                    onGenerateFrame: {
                        if model.drawingData.framing == nil {
                            _ = model.generateFraming()
                        } else {
                            _ = model.regenerateFramingPreservingEdits()
                        }
                    },
                    onLoadPresetChange: model.setLoadPreset,
                    onGroundCoverChange: model.setGroundCover
                )
            }
        }
    }

    private var statusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                modePill(DeckDrawingEditorCopy.drawMode, isActive: true)

                if model.capabilities.contains(.plausibleFrame) {
                    modePill(DeckDrawingEditorCopy.frameMode, isActive: model.drawingData.framing != nil)
                }

                if model.canRunCodeChecks {
                    codeTogglePill
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                metricPill(
                    label: DeckDrawingEditorCopy.openEndsPrefix,
                    value: "\(model.drawingData.openEndpointCount)"
                )
                metricPill(
                    label: DeckDrawingEditorCopy.areaPrefix,
                    value: areaLabel
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    private var areaLabel: String {
        guard model.drawingData.hasAnyClosedSurface else {
            return DeckDrawingEditorCopy.emptyArea
        }
        let area = model.drawingData.totalRealWorldArea(scaleFactor: model.drawingData.effectiveScaleFactor)
        return DimensionEngine.formatArea(area, system: model.drawingData.config.measurementSystem)
    }

    private func modePill(_ label: String, isActive: Bool) -> some View {
        Text(label)
            .font(OPSStyle.Typography.badgeCake)
            .foregroundStyle(isActive ? OPSStyle.Colors.invertedText : OPSStyle.Colors.text2)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(isActive ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.glassApprox)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(isActive ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundStyle(OPSStyle.Colors.text3)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundStyle(OPSStyle.Colors.text)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }

    private var codeTogglePill: some View {
        Button {
            model.setCodeChecksEnabled(model.codeCheckSettings == .disabled)
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(DeckDrawingEditorCopy.codeMode)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundStyle(OPSStyle.Colors.text3)
                Text(codeStatusValue)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundStyle(codeStatusColor)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(codeStatusFill)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(codeStatusLine, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DeckDrawingEditorCopy.codeMode)
        .accessibilityValue(codeStatusValue)
    }

    private var codeStatusValue: String {
        guard model.codeCheckSettings == .enabled else {
            return DeckDrawingEditorCopy.codeOff
        }
        return "\(model.visibleCodeFindings.count)"
    }

    private var codeStatusColor: Color {
        guard model.codeCheckSettings == .enabled else {
            return OPSStyle.Colors.text3
        }
        return model.visibleCodeFindings.isEmpty ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.roseTextM
    }

    private var codeStatusFill: Color {
        guard model.codeCheckSettings == .enabled else {
            return OPSStyle.Colors.fillNeutralDim
        }
        return model.visibleCodeFindings.isEmpty ? OPSStyle.Colors.oliveFillM : OPSStyle.Colors.roseFillM
    }

    private var codeStatusLine: Color {
        guard model.codeCheckSettings == .enabled else {
            return OPSStyle.Colors.nestedBorder
        }
        return model.visibleCodeFindings.isEmpty ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.roseLineM
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingLine {
                    isDraggingLine = true
                    model.beginLine(at: value.startLocation)
                }
                model.updateLine(to: value.location)
            }
            .onEnded { value in
                model.endLine(at: value.location)
                isDraggingLine = false
            }
    }

    private func drawingCanvas(size: CGSize) -> some View {
        Canvas { context, _ in
            drawGrid(context: context, size: size)
            drawSurfaces(context: context)
            drawFraming(context: context)
            drawCodeFindings(context: context)
            drawEdges(context: context)
            drawActiveLine(context: context)
            drawVertices(context: context)
            drawGuides(context: context)
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard model.drawingData.config.gridVisible else { return }
        let spacing = max(
            OPSStyle.Layout.spacing4,
            CGFloat(model.drawingData.config.lengthSnapIncrement * model.drawingData.effectiveScaleFactor)
        )
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(
            path,
            with: .color(OPSStyle.Colors.line.opacity(OPSStyle.Layout.Opacity.subtle)),
            lineWidth: OPSStyle.Layout.Border.standard
        )
    }

    private func drawSurfaces(context: GraphicsContext) {
        let surfaces = model.drawingData.detectedSurfaces
        for surface in surfaces {
            guard surface.positions.count >= 3 else { continue }
            var path = Path()
            path.move(to: surface.positions[0])
            for point in surface.positions.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            context.fill(path, with: .color(OPSStyle.Colors.opsAccent.opacity(OPSStyle.Layout.Opacity.subtle)))
        }
    }

    private func drawFraming(context: GraphicsContext) {
        guard let framing = model.drawingData.framing else { return }
        for member in framing.members.flatMap(\.members) where layerVisibility.contains(layer(for: member.role)) {
            var path = Path()
            path.move(to: member.start)
            path.addLine(to: member.end)
            context.stroke(path, with: .color(color(for: member.role)), lineWidth: lineWidth(for: member.role))

            if member.role == .post {
                let rect = CGRect(
                    x: member.start.x - OPSStyle.Layout.Indicator.dotMD,
                    y: member.start.y - OPSStyle.Layout.Indicator.dotMD,
                    width: OPSStyle.Layout.Indicator.dotMD * 2,
                    height: OPSStyle.Layout.Indicator.dotMD * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.opsAccent))
            }
        }
    }

    private func drawCodeFindings(context: GraphicsContext) {
        for finding in model.visibleCodeFindings {
            guard let anchor = finding.lineAnchor else { continue }
            var path = Path()
            path.move(to: anchor.start)
            path.addLine(to: anchor.end)

            let color = codeColor(for: finding.severity)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: OPSStyle.Layout.Border.thick,
                    dash: [OPSStyle.Layout.spacing2, OPSStyle.Layout.spacing1]
                )
            )

            context.draw(
                Text(DeckDrawingEditorCopy.codeAlert)
                    .font(OPSStyle.Typography.badgeCake)
                    .foregroundStyle(color),
                at: codeLabelPoint(for: anchor)
            )
        }
    }

    private func drawEdges(context: GraphicsContext) {
        for edge in model.drawingData.edges {
            guard let start = model.drawingData.vertex(byId: edge.startVertexId),
                  let end = model.drawingData.vertex(byId: edge.endVertexId) else { continue }
            var path = Path()
            path.move(to: start.position)
            path.addLine(to: end.position)
            context.stroke(path, with: .color(OPSStyle.Colors.text), lineWidth: OPSStyle.Layout.Border.thick)

            if let dimension = edge.dimension {
                let midpoint = CGPoint(
                    x: (start.position.x + end.position.x) / 2,
                    y: (start.position.y + end.position.y) / 2
                )
                context.draw(
                    Text(DimensionEngine.format(dimension, system: model.drawingData.config.measurementSystem))
                        .font(OPSStyle.Typography.caption)
                        .foregroundStyle(OPSStyle.Colors.text2),
                    at: CGPoint(x: midpoint.x, y: midpoint.y - OPSStyle.Layout.spacing3)
                )
            }
        }
    }

    private func drawActiveLine(context: GraphicsContext) {
        guard let activeLine = model.activeLine else { return }
        var path = Path()
        path.move(to: activeLine.start)
        path.addLine(to: activeLine.end)
        context.stroke(path, with: .color(OPSStyle.Colors.opsAccent), lineWidth: OPSStyle.Layout.Border.thick)
        context.draw(
            Text(activeLine.dimensionLabel)
                .font(OPSStyle.Typography.caption)
                .foregroundStyle(OPSStyle.Colors.opsAccent),
            at: activeLine.end
        )
    }

    private func drawVertices(context: GraphicsContext) {
        for vertex in model.drawingData.vertices {
            let rect = CGRect(
                x: vertex.position.x - OPSStyle.Layout.Indicator.dotMD,
                y: vertex.position.y - OPSStyle.Layout.Indicator.dotMD,
                width: OPSStyle.Layout.Indicator.dotMD * 2,
                height: OPSStyle.Layout.Indicator.dotMD * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.background))
            context.stroke(Path(ellipseIn: rect), with: .color(OPSStyle.Colors.opsAccent), lineWidth: OPSStyle.Layout.Border.standard)
        }
    }

    private func drawGuides(context: GraphicsContext) {
        for guide in model.alignmentGuides {
            var path = Path()
            path.move(to: guide.from)
            path.addLine(to: guide.to)
            context.stroke(
                path,
                with: .color(OPSStyle.Colors.opsAccent.opacity(OPSStyle.Layout.Opacity.medium)),
                style: StrokeStyle(
                    lineWidth: OPSStyle.Layout.Border.standard,
                    dash: [OPSStyle.Layout.spacing1, OPSStyle.Layout.spacing1]
                )
            )
        }
    }

    private func color(for role: FramingRole) -> Color {
        switch role {
        case .ledger:
            return OPSStyle.Colors.opsAccent
        case .rimBand:
            return OPSStyle.Colors.text2
        case .beam:
            return OPSStyle.Colors.tanTextM
        case .joist:
            return OPSStyle.Colors.text3
        case .post:
            return OPSStyle.Colors.opsAccent
        case .blocking:
            return OPSStyle.Colors.glassBorder
        case .bridging, .cantilever:
            return OPSStyle.Colors.textMute
        }
    }

    private func codeColor(for severity: DeckCodeSeverity) -> Color {
        switch severity {
        case .advisory:
            return OPSStyle.Colors.text3
        case .warning:
            return OPSStyle.Colors.tanTextM
        case .violation:
            return OPSStyle.Colors.roseTextM
        }
    }

    private func codeLabelPoint(for anchor: DeckCodeLineAnchor) -> CGPoint {
        CGPoint(
            x: (anchor.start.x + anchor.end.x) / 2,
            y: (anchor.start.y + anchor.end.y) / 2 - OPSStyle.Layout.spacing3
        )
    }

    private func lineWidth(for role: FramingRole) -> CGFloat {
        switch role {
        case .beam, .ledger:
            return OPSStyle.Layout.Border.thick
        case .rimBand, .joist, .blocking, .post, .bridging, .cantilever:
            return OPSStyle.Layout.Border.standard
        }
    }

    private func layer(for role: FramingRole) -> FramingLayer {
        switch role {
        case .ledger, .rimBand:
            return .rim
        case .beam:
            return .beams
        case .joist:
            return .joists
        case .post:
            return .posts
        case .blocking:
            return .blocking
        case .bridging, .cantilever:
            return .joists
        }
    }
}
