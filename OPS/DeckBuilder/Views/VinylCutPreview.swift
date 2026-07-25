// OPS/OPS/DeckBuilder/Views/VinylCutPreview.swift
//
// Roll-layout visualization for a VinylCutPlan. Extracted verbatim from
// VinylOrderSheet so the bulk order wizard pages can render the same
// preview the single-project sheet shows. Layout constants stay in
// VinylOrderLayout (VinylOrderSheet.swift) — single source for both.

import CoreGraphics
import SwiftUI
import UIKit

struct VinylOrderViewportState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4

    var scale: CGFloat = minimumScale
    var offset: CGSize = .zero

    mutating func applyZoom(multiplier: CGFloat, viewportSize: CGSize) {
        scale = min(
            Self.maximumScale,
            max(Self.minimumScale, scale * multiplier)
        )

        if scale == Self.minimumScale {
            offset = .zero
        } else {
            offset = clampedOffset(offset, viewportSize: viewportSize)
        }
    }

    mutating func applyPan(translation: CGSize, viewportSize: CGSize) {
        guard scale > Self.minimumScale else {
            offset = .zero
            return
        }

        offset = clampedOffset(
            CGSize(
                width: offset.width + translation.width,
                height: offset.height + translation.height
            ),
            viewportSize: viewportSize
        )
    }

    mutating func fit() {
        self = Self()
    }

    private func clampedOffset(_ proposedOffset: CGSize, viewportSize: CGSize) -> CGSize {
        let horizontalLimit = max(0, viewportSize.width * (scale - 1) / 2)
        let verticalLimit = max(0, viewportSize.height * (scale - 1) / 2)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, proposedOffset.width)),
            height: min(verticalLimit, max(-verticalLimit, proposedOffset.height))
        )
    }
}

struct VinylOrderFullscreenGeometry: Equatable {
    static var headerHeight: CGFloat {
        OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing4
    }

    static var controlRailWidth: CGFloat {
        OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing3
    }

    static var fitBarHeight: CGFloat {
        OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing3
    }

    let containerSize: CGSize

    var drawingSize: CGSize {
        CGSize(
            width: max(1, containerSize.width - Self.controlRailWidth),
            height: max(
                1,
                containerSize.height - Self.headerHeight - Self.fitBarHeight
            )
        )
    }

    var headerCenter: CGPoint {
        CGPoint(
            x: containerSize.width / 2,
            y: Self.headerHeight / 2
        )
    }

    var drawingCenter: CGPoint {
        CGPoint(
            x: drawingSize.width / 2,
            y: Self.headerHeight + (drawingSize.height / 2)
        )
    }

    var controlRailCenter: CGPoint {
        CGPoint(
            x: drawingSize.width + (Self.controlRailWidth / 2),
            y: Self.headerHeight
                + ((containerSize.height - Self.headerHeight) / 2)
        )
    }

    var fitBarCenter: CGPoint {
        CGPoint(
            x: drawingSize.width / 2,
            y: containerSize.height - (Self.fitBarHeight / 2)
        )
    }
}

struct VinylCutPreview: View {
    let plan: VinylCutPlan

    var body: some View {
        Canvas { context, size in
            guard let bounds = sourceBounds, bounds.width > 0, bounds.height > 0 else {
                drawEmpty(in: &context, size: size)
                return
            }

            let target = CGRect(
                x: VinylOrderLayout.previewInset,
                y: VinylOrderLayout.previewInset,
                width: max(1, size.width - (VinylOrderLayout.previewInset * 2)),
                height: max(1, size.height - (VinylOrderLayout.previewInset * 2))
            )
            let scale = min(target.width / bounds.width, target.height / bounds.height)
            let fitted = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let origin = CGPoint(
                x: target.midX - fitted.width / 2,
                y: target.midY - fitted.height / 2
            )

            for surface in plan.surfaces {
                drawSurface(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vinyl cut preview")
    }

    private var sourceBounds: CGRect? {
        let points = plan.surfaces.flatMap(\.positions)
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let reserve = plan.surfaces
            .map { max(CGFloat(plan.settings.edgeWrapInches * surfaceScale($0) * 4), CGFloat(OPSStyle.Layout.spacing4)) }
            .max() ?? CGFloat(OPSStyle.Layout.spacing4)
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
            .insetBy(dx: -reserve, dy: -reserve)
    }

    private func drawSurface(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard let path = surfacePath(for: surface.positions, bounds: bounds, origin: origin, scale: scale) else { return }

        drawOverlapBands(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.fill(path, with: .color(OPSStyle.Colors.surfaceActive.opacity(0.42)))
        drawCuts(surface, clippedTo: path, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawDirectionTransitions(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.stroke(path, with: .color(OPSStyle.Colors.secondaryText), lineWidth: OPSStyle.Layout.Border.standard)
        drawHouseEdgeLabels(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawOverlapLeaders(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
    }

    private func drawOverlapBands(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        let annotationPlan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: plan.settings,
            viewportScale: scale
        )

        for band in annotationPlan.bands {
            let bandPath = path(for: band.polygon, bounds: bounds, origin: origin, scale: scale)
            context.fill(bandPath, with: .color(overlapFill(for: band.tone)))
            context.stroke(
                bandPath,
                with: .color(overlapStroke(for: band.tone)),
                style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [4, 3])
            )

            for hatch in band.hatchLines {
                var hatchPath = Path()
                hatchPath.move(to: map(hatch.start, bounds: bounds, origin: origin, scale: scale))
                hatchPath.addLine(to: map(hatch.end, bounds: bounds, origin: origin, scale: scale))
                context.stroke(
                    hatchPath,
                    with: .color(OPSStyle.Colors.textMute.opacity(0.58)),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
            }
        }
    }

    private func drawHouseEdgeLabels(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        let annotationPlan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: plan.settings,
            viewportScale: scale
        )
        for label in annotationPlan.houseLabels {
            context.draw(
                Text(label.text)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(annotationColor(for: label.tone)),
                at: map(label.point, bounds: bounds, origin: origin, scale: scale),
                anchor: .center
            )
        }
    }

    private func drawOverlapLeaders(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        let annotationPlan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: plan.settings,
            viewportScale: scale
        )

        for leader in annotationPlan.leaders {
            let color = annotationColor(for: leader.tone)
            var line = Path()
            line.move(to: map(leader.lineStart, bounds: bounds, origin: origin, scale: scale))
            line.addLine(to: map(leader.lineEnd, bounds: bounds, origin: origin, scale: scale))
            context.stroke(line, with: .color(color.opacity(0.82)), lineWidth: OPSStyle.Layout.Border.standard)

            context.draw(
                Text(leader.label)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(color),
                at: map(leader.labelPoint, bounds: bounds, origin: origin, scale: scale),
                anchor: .center
            )
        }
    }

    private func drawHouseEdgeBandHatching(
        _ layout: VinylPreviewEdgeLayout,
        wrapCanvas: CGFloat,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard wrapCanvas > 0, layout.length > 0 else { return }

        let dx = layout.edge.end.x - layout.edge.start.x
        let dy = layout.edge.end.y - layout.edge.start.y
        let tangent = CGVector(dx: dx / layout.length, dy: dy / layout.length)
        let stride = max(6 / max(scale, 0.001), wrapCanvas * 0.9)
        let count = max(2, Int(ceil(layout.length / stride)))

        var hatch = Path()
        for index in 0...count {
            let t = CGFloat(index) / CGFloat(count)
            let edgePoint = CGPoint(
                x: layout.edge.start.x + (dx * t),
                y: layout.edge.start.y + (dy * t)
            )
            let start = offset(edgePoint, normal: layout.outwardNormal, distance: wrapCanvas * 0.18)
            let outer = offset(edgePoint, normal: layout.outwardNormal, distance: wrapCanvas * 0.82)
            let end = offset(outer, normal: tangent, distance: stride * 0.42)

            hatch.move(to: map(start, bounds: bounds, origin: origin, scale: scale))
            hatch.addLine(to: map(end, bounds: bounds, origin: origin, scale: scale))
        }

        context.stroke(
            hatch,
            with: .color(OPSStyle.Colors.secondaryText.opacity(0.32)),
            lineWidth: 0.8
        )
    }

    private func drawCuts(
        _ surface: VinylSurfaceCutPlan,
        clippedTo clipPath: Path,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard !surface.cuts.isEmpty else { return }

        for (index, cut) in surface.cuts.enumerated() {
            guard let cutPath = cutPath(for: cut, surface: surface, bounds: bounds, origin: origin, scale: scale) else {
                continue
            }

            var clipped = context
            clipped.clip(to: clipPath)
            let regionPolygon = VinylPreviewAnnotationPlanner.regionPolygon(for: cut, in: surface)
            if let regionPath = surfacePath(
                for: regionPolygon,
                bounds: bounds,
                origin: origin,
                scale: scale
            ) {
                clipped.clip(to: regionPath)
            }

            let fill = cutFillColor(cut: cut, index: index)
            let stroke = cut.isPurchased ? OPSStyle.Colors.primaryAccent.opacity(0.78) : OPSStyle.Colors.tan
            clipped.fill(cutPath, with: .color(fill))
            clipped.stroke(cutPath, with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: cut.isPurchased ? [] : [5, 4]))

            let label = Text(vinylFormatFeetAndInches(cut.lengthInches))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(cut.isPurchased ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tan)
            clipped.draw(label, at: labelPoint(for: cut, surface: surface, bounds: bounds, origin: origin, scale: scale), anchor: .center)
        }
    }

    private func drawDirectionTransitions(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        let annotationPlan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: plan.settings,
            viewportScale: scale
        )
        for transition in annotationPlan.transitions {
            var line = Path()
            line.move(to: map(transition.start, bounds: bounds, origin: origin, scale: scale))
            line.addLine(to: map(transition.end, bounds: bounds, origin: origin, scale: scale))
            context.stroke(
                line,
                with: .color(OPSStyle.Colors.primaryText),
                lineWidth: OPSStyle.Layout.Border.standard
            )
        }
    }

    private func cutFillColor(cut: VinylCutPiece, index: Int) -> Color {
        if cut.isPurchased {
            return OPSStyle.Colors.primaryAccent.opacity(index.isMultiple(of: 2) ? 0.18 : 0.10)
        }
        return OPSStyle.Colors.tanSoft.opacity(index.isMultiple(of: 2) ? 0.95 : 0.72)
    }

    private func cutPath(
        for cut: VinylCutPiece,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> Path? {
        guard cut.runEndInches > cut.runStartInches,
              cut.bandEndInches > cut.bandStartInches else { return nil }

        let corners = [
            previewPoint(run: cut.runStartInches, cross: cut.bandStartInches, angleDegrees: cut.runAngleDegrees, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runEndInches, cross: cut.bandStartInches, angleDegrees: cut.runAngleDegrees, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runEndInches, cross: cut.bandEndInches, angleDegrees: cut.runAngleDegrees, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runStartInches, cross: cut.bandEndInches, angleDegrees: cut.runAngleDegrees, surface: surface, bounds: bounds, origin: origin, scale: scale)
        ]

        var path = Path()
        path.move(to: corners[0])
        for point in corners.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func labelPoint(
        for cut: VinylCutPiece,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        previewPoint(
            run: (cut.runStartInches + cut.runEndInches) / 2,
            cross: (cut.bandStartInches + cut.bandEndInches) / 2,
            angleDegrees: cut.runAngleDegrees,
            surface: surface,
            bounds: bounds,
            origin: origin,
            scale: scale
        )
    }

    private func previewPoint(
        run: Double,
        cross: Double,
        angleDegrees: Double,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let scaleFactor = surfaceScale(surface)
        let point = CGPoint(
            x: ((run * cosValue) - (cross * sinValue)) * scaleFactor,
            y: ((run * sinValue) + (cross * cosValue)) * scaleFactor
        )
        return map(point, bounds: bounds, origin: origin, scale: scale)
    }

    private func surfaceScale(_ surface: VinylSurfaceCutPlan) -> Double {
        guard let faceBounds = rawSurfaceBounds(for: surface.positions), surface.boundingWidthInches > 0 else {
            return 1
        }
        return Double(faceBounds.width) / surface.boundingWidthInches
    }

    private func surfacePath(
        for points: [CGPoint],
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> Path? {
        guard let first = points.first else { return nil }
        var path = Path()
        path.move(to: map(first, bounds: bounds, origin: origin, scale: scale))
        for point in points.dropFirst() {
            path.addLine(to: map(point, bounds: bounds, origin: origin, scale: scale))
        }
        path.closeSubpath()
        return path
    }

    private func edgeLayouts(for surface: VinylSurfaceCutPlan) -> [VinylPreviewEdgeLayout] {
        previewEdges(for: surface).compactMap { edge in
            let dx = edge.end.x - edge.start.x
            let dy = edge.end.y - edge.start.y
            let length = CGFloat(sqrt(Double((dx * dx) + (dy * dy))))
            guard length > 0 else { return nil }
            return VinylPreviewEdgeLayout(
                surface: surface,
                edge: edge,
                outwardNormal: outwardNormal(for: edge, surface: surface),
                length: length
            )
        }
    }

    private func previewEdges(for surface: VinylSurfaceCutPlan) -> [VinylOrderSurfaceEdge] {
        if !surface.edges.isEmpty { return surface.edges }
        guard surface.positions.count >= 2 else { return [] }
        return surface.positions.indices.map { index in
            let nextIndex = (index + 1) % surface.positions.count
            return VinylOrderSurfaceEdge(
                id: "\(surface.id)-edge-\(index)",
                start: surface.positions[index],
                end: surface.positions[nextIndex],
                edgeType: .deckEdge,
                label: nil
            )
        }
    }

    private func outwardNormal(for edge: VinylOrderSurfaceEdge, surface: VinylSurfaceCutPlan) -> CGVector {
        let dx = edge.end.x - edge.start.x
        let dy = edge.end.y - edge.start.y
        let length = CGFloat(sqrt(Double((dx * dx) + (dy * dy))))
        guard length > 0 else { return .zero }

        let normalA = CGVector(dx: dy / length, dy: -dx / length)
        let normalB = CGVector(dx: -normalA.dx, dy: -normalA.dy)
        let mid = midpoint(edge.start, edge.end)
        let probeDistance = CGFloat(OPSStyle.Layout.spacing2)
        let probeA = offset(mid, normal: normalA, distance: probeDistance)

        return PolygonMath.pointInPolygon(probeA, vertices: surface.positions) ? normalB : normalA
    }

    private func representativeLayout(
        in layouts: [VinylPreviewEdgeLayout],
        type: EdgeType
    ) -> VinylPreviewEdgeLayout? {
        layouts
            .filter { $0.edge.edgeType == type }
            .max { $0.length < $1.length }
    }

    private func path(
        for points: [CGPoint],
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: map(first, bounds: bounds, origin: origin, scale: scale))
        for point in points.dropFirst() {
            path.addLine(to: map(point, bounds: bounds, origin: origin, scale: scale))
        }
        path.closeSubpath()
        return path
    }

    private func overlapFill(for tone: VinylPreviewAnnotationTone) -> Color {
        switch tone {
        case .neutral:
            return OPSStyle.Colors.fillNeutralDim.opacity(0.86)
        case .deck:
            return OPSStyle.Colors.surfaceActive.opacity(0.72)
        }
    }

    private func overlapStroke(for tone: VinylPreviewAnnotationTone) -> Color {
        switch tone {
        case .neutral:
            return OPSStyle.Colors.textMute.opacity(0.70)
        case .deck:
            return OPSStyle.Colors.secondaryText.opacity(0.64)
        }
    }

    private func annotationColor(for tone: VinylPreviewAnnotationTone) -> Color {
        switch tone {
        case .neutral:
            return OPSStyle.Colors.text2
        case .deck:
            return OPSStyle.Colors.secondaryText
        }
    }

    private func midpoint(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private func offset(_ point: CGPoint, normal: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + (normal.dx * distance), y: point.y + (normal.dy * distance))
    }

    private func formatOverlapInches(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", rounded)
    }

    private func drawEmpty(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(
            x: VinylOrderLayout.previewInset,
            y: VinylOrderLayout.previewInset,
            width: max(1, size.width - (VinylOrderLayout.previewInset * 2)),
            height: max(1, size.height - (VinylOrderLayout.previewInset * 2))
        )
        let path = Path(roundedRect: rect, cornerRadius: OPSStyle.Layout.cornerRadius)
        context.stroke(path, with: .color(OPSStyle.Colors.cardBorder), lineWidth: 1)
    }

    private func rawSurfaceBounds(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func map(
        _ point: CGPoint,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: origin.x + ((point.x - bounds.minX) * scale),
            y: origin.y + ((point.y - bounds.minY) * scale)
        )
    }
}

struct VinylPreviewEdgeLayout {
    let surface: VinylSurfaceCutPlan
    let edge: VinylOrderSurfaceEdge
    let outwardNormal: CGVector
    let length: CGFloat
}

// MARK: - Shared Order Layout Window

struct VinylOrderLayoutWindow: View {
    let plan: VinylCutPlan
    let projectTitle: String
    let subtitle: String?

    @State private var isShowingFullscreen = false
    @State private var viewport = VinylOrderViewportState()

    init(
        plan: VinylCutPlan,
        projectTitle: String,
        subtitle: String? = nil
    ) {
        self.plan = plan
        self.projectTitle = projectTitle
        self.subtitle = subtitle
    }

    var body: some View {
        Button(action: presentFullscreen) {
            VStack(spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// ORDER LAYOUT")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.text2)

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    Text("FULL SCREEN")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)

                    Image(systemName: OPSStyle.Icons.expand)
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.md,
                            weight: .semibold
                        ))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                }
                .padding(.leading, OPSStyle.Layout.spacing3)
                .padding(.trailing, OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)

                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: OPSStyle.Layout.Border.standard)

                VinylCutPreview(plan: plan)
                    .frame(height: VinylOrderLayout.previewHeight)
                    .background(OPSStyle.Colors.background)
            }
            .glassSurface(cornerRadius: OPSStyle.Layout.panelRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Order layout")
        .accessibilityHint("Opens full screen")
        .fullScreenCover(isPresented: $isShowingFullscreen, onDismiss: resetViewport) {
            VinylOrderFullscreenLayout(
                plan: plan,
                projectTitle: displayProjectTitle,
                subtitle: displaySubtitle,
                viewport: $viewport,
                onClose: dismissFullscreen
            )
        }
    }

    private var displayProjectTitle: String {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "PROJECT" : trimmed
    }

    private var displaySubtitle: String? {
        guard let subtitle else { return nil }
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func presentFullscreen() {
        viewport.fit()
        VinylOrderInteractionFeedback.fire()
        isShowingFullscreen = true
    }

    private func dismissFullscreen() {
        VinylOrderInteractionFeedback.fire()
        isShowingFullscreen = false
    }

    private func resetViewport() {
        viewport.fit()
    }
}

private struct VinylOrderFullscreenLayout: View {
    let plan: VinylCutPlan
    let projectTitle: String
    let subtitle: String?
    @Binding var viewport: VinylOrderViewportState
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastMagnification: CGFloat = 1
    @State private var lastDragTranslation: CGSize = .zero

    private static let zoomStep: CGFloat = 1.25

    var body: some View {
        GeometryReader { geometry in
            let layout = VinylOrderFullscreenGeometry(
                containerSize: geometry.size
            )

            ZStack(alignment: .topLeading) {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                drawingViewport(size: layout.drawingSize)
                    .position(layout.drawingCenter)

                fullscreenHeader
                    .frame(
                        width: geometry.size.width,
                        height: VinylOrderFullscreenGeometry.headerHeight
                    )
                    .position(layout.headerCenter)

                zoomControlRail(viewportSize: layout.drawingSize)
                    .frame(
                        width: VinylOrderFullscreenGeometry.controlRailWidth,
                        height: max(
                            1,
                            geometry.size.height
                                - VinylOrderFullscreenGeometry.headerHeight
                        )
                    )
                    .position(layout.controlRailCenter)

                fitControlBar
                    .frame(
                        width: layout.drawingSize.width,
                        height: VinylOrderFullscreenGeometry.fitBarHeight
                    )
                    .position(layout.fitBarCenter)
            }
            .clipped()
        }
        .hidesGlobalTabBar()
        .accessibilityAddTraits(.isModal)
        .onDisappear {
            lastMagnification = 1
            lastDragTranslation = .zero
        }
    }

    private func drawingViewport(size: CGSize) -> some View {
        VinylCutPreview(plan: plan)
            .frame(width: size.width, height: size.height)
            .scaleEffect(viewport.scale)
            .offset(viewport.offset)
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(magnificationGesture(viewportSize: size))
            .simultaneousGesture(panGesture(viewportSize: size))
    }

    private var fullscreenHeader: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(projectTitle)
                    .font(OPSStyle.Typography.screenTitle(for: projectTitle))
                    .foregroundColor(OPSStyle.Colors.text)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(contextLine)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            layoutControl(
                icon: OPSStyle.Icons.close,
                label: "Close order layout"
            ) {
                onClose()
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(
            OPSStyle.Colors.background.opacity(OPSStyle.Layout.Opacity.heavy)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    private func zoomControlRail(viewportSize: CGSize) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                layoutControl(
                    icon: OPSStyle.Icons.plus,
                    label: "Zoom in",
                    isDisabled: viewport.scale >= VinylOrderViewportState.maximumScale
                ) {
                    adjustZoom(
                        by: Self.zoomStep,
                        viewportSize: viewportSize
                    )
                }

                layoutControl(
                    icon: OPSStyle.Icons.minus,
                    label: "Zoom out",
                    isDisabled: viewport.scale <= VinylOrderViewportState.minimumScale
                ) {
                    adjustZoom(
                        by: 1 / Self.zoomStep,
                        viewportSize: viewportSize
                    )
                }
            }
            .padding(OPSStyle.Layout.spacing1)
            .glassDense(cornerRadius: OPSStyle.Layout.panelRadius)

            Spacer(minLength: OPSStyle.Layout.spacing3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private var fitControlBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: OPSStyle.Layout.spacing3)

            Button(action: fitLayout) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.fit)
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.md,
                            weight: .semibold
                        ))

                    Text("FIT LAYOUT")
                        .font(OPSStyle.Typography.button)
                }
                .foregroundColor(
                    viewport == VinylOrderViewportState()
                        ? OPSStyle.Colors.textMute
                        : OPSStyle.Colors.text
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .glassDense(cornerRadius: OPSStyle.Layout.panelRadius)
            }
            .buttonStyle(.plain)
            .disabled(viewport == VinylOrderViewportState())
            .accessibilityLabel("Fit layout")

            Spacer(minLength: OPSStyle.Layout.spacing3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private var contextLine: String {
        guard let subtitle else { return "// ORDER LAYOUT" }
        return "// ORDER LAYOUT · \(subtitle)"
    }

    private func layoutControl(
        icon: String,
        label: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(
                    size: OPSStyle.Layout.IconSize.md,
                    weight: .semibold
                ))
        }
        .opsIconButtonStyle(
            backgroundColor: OPSStyle.Colors.surfaceActive,
            foregroundColor: isDisabled ? OPSStyle.Colors.textMute : OPSStyle.Colors.text
        )
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private func magnificationGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let multiplier = value / lastMagnification
                viewport.applyZoom(
                    multiplier: multiplier,
                    viewportSize: viewportSize
                )
                lastMagnification = value
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }

    private func panGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                viewport.applyPan(
                    translation: translation,
                    viewportSize: viewportSize
                )
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    private func adjustZoom(by multiplier: CGFloat, viewportSize: CGSize) {
        updateViewport(animation: OPSStyle.Animation.hover) {
            viewport.applyZoom(
                multiplier: multiplier,
                viewportSize: viewportSize
            )
        }
        VinylOrderInteractionFeedback.fire()
    }

    private func fitLayout() {
        updateViewport(animation: OPSStyle.Animation.page) {
            viewport.fit()
        }
        VinylOrderInteractionFeedback.fire()
    }

    private func updateViewport(
        animation: Animation,
        _ changes: () -> Void
    ) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                changes()
            }
        } else {
            withAnimation(animation) {
                changes()
            }
        }
    }
}

// MARK: - Roll Utilization

struct VinylRollUtilizationView: View {
    let plan: VinylRollPackingPlan

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if plan.rolls.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing3)
                    .nestedCard(cornerRadius: OPSStyle.Layout.cardRadius)
            } else {
                ForEach(Array(plan.rolls.enumerated()), id: \.offset) { index, roll in
                    rollCard(roll, index: index)
                }
            }
        }
    }

    private func rollCard(_ roll: VinylPackedRoll, index: Int) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("ROLL \(String(format: "%02d", index + 1))")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.text2)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("CUTS")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)

                Text(cutSummary(for: roll))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)

            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing3) {
                utilizationMetric(label: "USED", value: feetText(roll.usedFeet))
                Spacer(minLength: OPSStyle.Layout.spacing2)
                utilizationMetric(label: "LEFT", value: feetText(roll.leftoverFeet))
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .nestedCard(cornerRadius: OPSStyle.Layout.cardRadius)
        .accessibilityElement(children: .combine)
    }

    private func utilizationMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)

            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
        }
    }

    private func cutSummary(for roll: VinylPackedRoll) -> String {
        let cuts = roll.stripLengthsFeet.map(feetText)
        return cuts.isEmpty ? "—" : cuts.joined(separator: " + ")
    }

    private func feetText(_ value: Double) -> String {
        vinylFormatFeetAndInches(value * 12)
    }
}

private enum VinylOrderInteractionFeedback {
    static func fire() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
