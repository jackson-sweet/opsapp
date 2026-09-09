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
    /// Where a double-tap lands. 2× is the step that reads as "closer" without
    /// losing the shape of the deck — the rung a second double-tap returns from.
    static let doubleTapScale: CGFloat = 2

    var scale: CGFloat = minimumScale
    var offset: CGSize = .zero

    /// True while the drawing is showing everything at 1:1 — the state the FIT
    /// chip returns to, and therefore the state in which it has nothing to do.
    var isFitted: Bool {
        self == Self()
    }

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

    /// Double-tap: fitted → `doubleTapScale` anchored on the tapped point,
    /// anywhere else → back to fit. Replaces the `+`/`−` rail the founder
    /// called redundant (bug 317da29f) with the gesture every map and photo
    /// on the phone already uses.
    ///
    /// `point` is in the viewport's own coordinate space (origin top-left).
    /// The drawing is `scaleEffect`-ed about the viewport centre and then
    /// offset, so the content under the tap stays under the tap when the new
    /// offset walks the anchor back by the scale ratio.
    mutating func toggleFit(at point: CGPoint, viewportSize: CGSize) {
        guard scale == Self.minimumScale else {
            fit()
            return
        }

        let target = min(Self.maximumScale, Self.doubleTapScale)
        let ratio = target / max(scale, 0.0001)
        let fromCenter = CGSize(
            width: point.x - (viewportSize.width / 2),
            height: point.y - (viewportSize.height / 2)
        )
        let anchor = CGSize(
            width: fromCenter.width - offset.width,
            height: fromCenter.height - offset.height
        )

        scale = target
        offset = clampedOffset(
            CGSize(
                width: fromCenter.width - (anchor.width * ratio),
                height: fromCenter.height - (anchor.height * ratio)
            ),
            viewportSize: viewportSize
        )
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

/// Layout for the full-screen order workspace.
///
/// The drawing owns the **full container width**. The predecessor reserved a
/// 56pt zoom rail down the right side and drew the layout into what was left,
/// which read as the drawing being "cut off at about 48px in from the right
/// edge" (bug 317da29f). The rail is gone — pinch, drag and double-tap carry
/// zoom now — so only two bands take space: the header at the top and the
/// settings sheet resting at its peek detent along the bottom. The three bands
/// tile the container exactly.
struct VinylOrderWorkspaceGeometry: Equatable {
    /// Header band — a 44pt control row plus the title/context stack's room.
    /// This is the CONTENT height; `headerRect` adds the top safe-area inset on
    /// top of it, because the workspace runs under the status bar.
    static var headerHeight: CGFloat {
        OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing4
    }

    /// MOBILE.md §6.1 peek sheet — 80pt: the handle, the summary line, and a
    /// full content row that still clears the home indicator.
    static var sheetPeekHeight: CGFloat {
        OPSStyle.Layout.sheetPeekHeight
    }

    /// FIT chip — one 44pt-tall glass chip, wide enough for its icon and label.
    static var fitChipSize: CGSize {
        CGSize(
            width: OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing4,
            height: OPSStyle.Layout.touchTargetMin
        )
    }

    /// Stand-off between the chip and both the trailing bezel and the header.
    static var fitChipInset: CGFloat {
        OPSStyle.Layout.spacing3
    }

    /// The full container the workspace occupies — bezel to bezel. The
    /// workspace ignores the safe area so the drawing can run to the edges;
    /// the insets below put them back where they matter.
    let containerSize: CGSize
    /// Status bar + Dynamic Island. Padded into the header band, never into the
    /// drawing — the drawing passes beneath the header when zoomed.
    var topInset: CGFloat = 0
    /// Home indicator. Padded into the settings panel's own content so its
    /// summary line clears the indicator.
    var bottomInset: CGFloat = 0

    var headerRect: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: max(1, containerSize.width),
            height: max(0, topInset) + Self.headerHeight
        )
    }

    var drawingRect: CGRect {
        CGRect(
            x: 0,
            y: headerRect.height,
            width: max(1, containerSize.width),
            height: max(
                1,
                containerSize.height - headerRect.height - Self.sheetPeekHeight
            )
        )
    }

    var sheetPeekRect: CGRect {
        CGRect(
            x: 0,
            y: max(headerRect.height, containerSize.height - Self.sheetPeekHeight),
            width: max(1, containerSize.width),
            height: Self.sheetPeekHeight
        )
    }

    /// Tallest the settings panel may grow to — MOBILE.md §6.2 caps a half
    /// sheet at 50% of the screen. Never taller than the peek, so a degenerate
    /// container cannot invert the two.
    var sheetHalfHeight: CGFloat {
        max(Self.sheetPeekHeight, (containerSize.height / 2).rounded())
    }

    /// Top-trailing corner of the drawing band — the same corner the close `×`
    /// occupies in the header, so every "get me out of here" control lives in
    /// one place.
    var fitChipRect: CGRect {
        CGRect(
            x: drawingRect.maxX - Self.fitChipInset - Self.fitChipSize.width,
            y: drawingRect.minY + Self.fitChipInset,
            width: Self.fitChipSize.width,
            height: Self.fitChipSize.height
        )
    }

    var drawingSize: CGSize {
        drawingRect.size
    }

    var headerCenter: CGPoint {
        CGPoint(x: headerRect.midX, y: headerRect.midY)
    }

    var drawingCenter: CGPoint {
        CGPoint(x: drawingRect.midX, y: drawingRect.midY)
    }

    var fitChipCenter: CGPoint {
        CGPoint(x: fitChipRect.midX, y: fitChipRect.midY)
    }
}

struct VinylPreviewFitResult: Equatable {
    let bounds: CGRect
    let origin: CGPoint
    let scale: CGFloat
}

/// Resolves the drawing's fit inside its canvas.
///
/// The reserve and the scale are mutually dependent: the dimension ring is
/// specified in screen points — it has to stay legible whatever the deck's
/// size — while the reserve that holds it lives in source units, and the scale
/// that converts between them falls out of the reserved bounds. Two refinement
/// passes settle it: the correction is second order, so the residual is well
/// under a point. Before this the drawing fitted to the wrap band alone and a
/// long deck clipped its own dimensions off the canvas.
enum VinylPreviewFit {
    static let refinementPasses = 2

    static func resolve(
        content: CGRect,
        wrapCanvas: CGFloat,
        wrapReserve: CGFloat,
        ringReachPoints: CGFloat,
        target: CGRect
    ) -> VinylPreviewFitResult {
        var reserve = wrapReserve
        var scale = fittedScale(content: content, reserve: reserve, target: target)

        for _ in 0..<refinementPasses {
            reserve = max(wrapReserve, wrapCanvas + (ringReachPoints / max(scale, 0.0001)))
            scale = fittedScale(content: content, reserve: reserve, target: target)
        }

        let bounds = content.insetBy(dx: -reserve, dy: -reserve)
        let fitted = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return VinylPreviewFitResult(
            bounds: bounds,
            origin: CGPoint(
                x: target.midX - fitted.width / 2,
                y: target.midY - fitted.height / 2
            ),
            scale: scale
        )
    }

    private static func fittedScale(
        content: CGRect,
        reserve: CGFloat,
        target: CGRect
    ) -> CGFloat {
        let bounds = content.insetBy(dx: -reserve, dy: -reserve)
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(target.width / bounds.width, target.height / bounds.height)
    }
}

/// How much of the annotation ring a drawing carries.
enum VinylPreviewAnnotationDetail {
    /// Bands, cuts and every callout — the workspace, where the order is read.
    case full
    /// Bands and cuts only. The inline card is a short thumbnail the operator
    /// taps to OPEN the drawing; six dimension callouts and two lap labels at
    /// that size squeeze the deck down to a smudge and print over each other.
    /// A thumbnail's whole job is the shape.
    case shape
}

struct VinylCutPreview: View {
    let plan: VinylCutPlan
    /// The drawing's own imperial/metric preference, so an edge reads the same
    /// here as it does on the deck canvas.
    var measurementSystem: MeasurementSystem = .imperial
    var annotationDetail: VinylPreviewAnnotationDetail = .full

    var body: some View {
        Canvas { context, size in
            guard let fit = fit(in: size) else {
                drawEmpty(in: &context, size: size)
                return
            }

            for surface in plan.surfaces {
                drawSurface(
                    surface,
                    in: &context,
                    bounds: fit.bounds,
                    origin: fit.origin,
                    scale: fit.scale
                )
            }
        }
        // A scale drawing's callouts are part of the GRAPHIC, not body copy —
        // tripling them at accessibility sizes collides every label and destroys
        // the thing being read. The drawing keeps drafting scale and the
        // workspace carries the accessible path instead: pinch, double-tap, and
        // a VoiceOver adjustable zoom action on the drawing itself.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vinyl cut preview")
    }

    private func fit(in size: CGSize) -> VinylPreviewFitResult? {
        guard let content = contentBounds, content.width > 0, content.height > 0 else {
            return nil
        }

        return VinylPreviewFit.resolve(
            content: content,
            wrapCanvas: wrapCanvas,
            wrapReserve: wrapReserve,
            ringReachPoints: annotationDetail == .full
                ? VinylPreviewAnnotationPlanner.dimensionRingReachPoints(
                    for: plan.surfaces,
                    settings: plan.settings,
                    measurementSystem: measurementSystem
                )
                : 0,
            target: CGRect(
                x: VinylOrderLayout.previewInset,
                y: VinylOrderLayout.previewInset,
                width: max(1, size.width - (VinylOrderLayout.previewInset * 2)),
                height: max(1, size.height - (VinylOrderLayout.previewInset * 2))
            )
        )
    }

    /// Deepest wrap band across the plan's surfaces, in source units.
    private var wrapCanvas: CGFloat {
        plan.surfaces
            .map { CGFloat(plan.settings.edgeWrapInches * surfaceScale($0)) }
            .max() ?? 0
    }

    /// The legacy wrap reserve — four band depths, never under one `spacing4`.
    private var wrapReserve: CGFloat {
        plan.surfaces
            .map { max(CGFloat(plan.settings.edgeWrapInches * surfaceScale($0) * 4), CGFloat(OPSStyle.Layout.spacing4)) }
            .max() ?? CGFloat(OPSStyle.Layout.spacing4)
    }

    private var contentBounds: CGRect? {
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
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func drawSurface(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard let path = surfacePath(for: surface.positions, bounds: bounds, origin: origin, scale: scale) else { return }

        // One planner pass per surface per draw. The annotation plan used to be
        // recomputed for every callout family, which meant four full geometry
        // passes on every frame of a pinch — expensive at ProMotion rates.
        let annotationPlan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: plan.settings,
            viewportScale: scale,
            measurementSystem: measurementSystem
        )

        drawOverlapBands(annotationPlan, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.fill(path, with: .color(OPSStyle.Colors.surfaceActive.opacity(0.42)))
        drawCuts(surface, clippedTo: path, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawDirectionTransitions(annotationPlan, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.stroke(path, with: .color(OPSStyle.Colors.secondaryText), lineWidth: OPSStyle.Layout.Border.standard)

        guard annotationDetail == .full else { return }
        drawHouseEdgeLabels(annotationPlan, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawOverlapLeaders(annotationPlan, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawDimensionLabels(annotationPlan, in: &context, bounds: bounds, origin: origin, scale: scale)
    }

    /// The deck's own dimensions — the outermost ring of the drawing, outside
    /// the wrap band and the lap leaders.
    private func drawDimensionLabels(
        _ annotationPlan: VinylPreviewAnnotationPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        for label in annotationPlan.dimensionLabels {
            context.draw(
                Text(label.text)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.text2),
                at: map(label.point, bounds: bounds, origin: origin, scale: scale),
                anchor: .center
            )
        }
    }

    private func drawOverlapBands(
        _ annotationPlan: VinylPreviewAnnotationPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
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
        _ annotationPlan: VinylPreviewAnnotationPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
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
        _ annotationPlan: VinylPreviewAnnotationPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
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
        _ annotationPlan: VinylPreviewAnnotationPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
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
    /// The order's layout settings, owned by the parent. The workspace edits
    /// them in place and calls `onSettingsChanged` so the parent re-plans.
    @Binding var settings: VinylOrderSettings
    let onSettingsChanged: () -> Void
    /// The drawing's own imperial/metric preference, so an edge reads the same
    /// here as it does on the deck canvas.
    let measurementSystem: MeasurementSystem

    @State private var isShowingWorkspace = false
    @State private var viewport = VinylOrderViewportState()

    init(
        plan: VinylCutPlan,
        projectTitle: String,
        subtitle: String? = nil,
        settings: Binding<VinylOrderSettings>,
        measurementSystem: MeasurementSystem = .imperial,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.plan = plan
        self.projectTitle = projectTitle
        self.subtitle = subtitle
        self._settings = settings
        self.measurementSystem = measurementSystem
        self.onSettingsChanged = onSettingsChanged
    }

    var body: some View {
        Button(action: presentWorkspace) {
            VStack(spacing: 0) {
                // No hairline under this row (bug 1a8e48af, "the title divider
                // line doesn't need to be there"). The card's own glass edge
                // already separates the header from the drawing.
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// \(VinylOrderWorkspaceCopy.screen)")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.text2)

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    Text(VinylOrderWorkspaceCopy.fullScreenAction)
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

                VinylCutPreview(
                    plan: plan,
                    measurementSystem: measurementSystem,
                    annotationDetail: .shape
                )
                .frame(height: VinylOrderLayout.previewHeight)
                .background(OPSStyle.Colors.background)
            }
            .glassSurface(cornerRadius: OPSStyle.Layout.panelRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VinylOrderWorkspaceCopy.windowLabel)
        .accessibilityHint(VinylOrderWorkspaceCopy.windowHint)
        .fullScreenCover(isPresented: $isShowingWorkspace, onDismiss: resetViewport) {
            VinylOrderWorkspace(
                plan: plan,
                projectTitle: displayProjectTitle,
                deckTitle: displaySubtitle,
                measurementSystem: measurementSystem,
                settings: $settings,
                viewport: $viewport,
                onSettingsChanged: onSettingsChanged,
                onClose: dismissWorkspace
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

    private func presentWorkspace() {
        viewport.fit()
        VinylOrderInteractionFeedback.fire()
        isShowingWorkspace = true
    }

    private func dismissWorkspace() {
        VinylOrderInteractionFeedback.fire()
        isShowingWorkspace = false
    }

    private func resetViewport() {
        viewport.fit()
    }
}

/// The full-screen ORDER LAYOUT — the place the order is *worked*, not a
/// picture of it.
///
/// Three bands tile the screen: a header with no divider, the drawing running
/// bezel to bezel, and the settings panel resting at its peek. The zoom rail
/// the founder called "redundant" is gone — pinch, drag and double-tap carry
/// zoom, and a FIT chip appears only once there is something to return from.
/// Internal (not private) so the geometry, the viewport and the whole composed
/// screen are testable and snapshot-provable.
struct VinylOrderWorkspace: View {
    let plan: VinylCutPlan
    let projectTitle: String
    let deckTitle: String?
    let measurementSystem: MeasurementSystem
    @Binding var settings: VinylOrderSettings
    @Binding var viewport: VinylOrderViewportState
    let onSettingsChanged: () -> Void
    let onClose: () -> Void

    @State private var lastMagnification: CGFloat = 1
    @State private var lastDragTranslation: CGSize = .zero
    @State private var panelDetent: VinylOrderPanelDetent
    @State private var panelDrag: CGFloat = 0

    init(
        plan: VinylCutPlan,
        projectTitle: String,
        deckTitle: String?,
        measurementSystem: MeasurementSystem = .imperial,
        settings: Binding<VinylOrderSettings>,
        viewport: Binding<VinylOrderViewportState>,
        // Where the settings panel opens. Always `.peek` in the app — the
        // drawing is what the operator came for — and overridable so the
        // expanded screen can be rendered whole for proof.
        panelDetent: VinylOrderPanelDetent = .peek,
        onSettingsChanged: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.plan = plan
        self.projectTitle = projectTitle
        self.deckTitle = deckTitle
        self.measurementSystem = measurementSystem
        self._settings = settings
        self._viewport = viewport
        self._panelDetent = State(initialValue: panelDetent)
        self.onSettingsChanged = onSettingsChanged
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = VinylOrderWorkspaceGeometry(
                containerSize: geometry.size,
                topInset: geometry.safeAreaInsets.top,
                bottomInset: geometry.safeAreaInsets.bottom
            )
            let panelHeight = VinylOrderSettingsPanel.height(
                detent: panelDetent,
                dragOffset: panelDrag,
                peekHeight: VinylOrderWorkspaceGeometry.sheetPeekHeight,
                halfHeight: layout.sheetHalfHeight
            )

            ZStack(alignment: .topLeading) {
                OPSStyle.Colors.background

                drawingViewport(size: layout.drawingSize)
                    .position(layout.drawingCenter)

                header(layout: layout)
                    .frame(
                        width: layout.headerRect.width,
                        height: layout.headerRect.height
                    )
                    .position(layout.headerCenter)

                ZStack { fitChip }
                    .frame(
                        width: VinylOrderWorkspaceGeometry.fitChipSize.width,
                        height: VinylOrderWorkspaceGeometry.fitChipSize.height
                    )
                    .animation(OPSStyle.Animation.panel, value: viewport.isFitted)
                    .allowsHitTesting(!viewport.isFitted)
                    .position(layout.fitChipCenter)

                VinylOrderSettingsPanel(
                    plan: plan,
                    settings: $settings,
                    onSettingsChanged: onSettingsChanged,
                    peekHeight: VinylOrderWorkspaceGeometry.sheetPeekHeight,
                    halfHeight: layout.sheetHalfHeight,
                    bottomInset: layout.bottomInset,
                    detent: $panelDetent,
                    dragOffset: $panelDrag
                )
                .frame(width: layout.containerSize.width, height: panelHeight)
                .position(
                    x: layout.containerSize.width / 2,
                    y: layout.containerSize.height - (panelHeight / 2)
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .hidesGlobalTabBar()
        .accessibilityAddTraits(.isModal)
        .onDisappear {
            lastMagnification = 1
            lastDragTranslation = .zero
        }
    }

    // MARK: - Drawing

    /// The drawing owns the full width. A re-plan crossfades rather than
    /// snapping: the canvas is keyed on the settings that shape it, so a new
    /// identity swaps the layout under a 200ms opacity transition on the one
    /// OPS curve. `OPSStyle.Animation.panel` is already reduce-motion aware,
    /// and the transition is opacity either way — nothing slides or scales.
    private func drawingViewport(size: CGSize) -> some View {
        ZStack {
            VinylCutPreview(plan: plan, measurementSystem: measurementSystem)
                .frame(width: size.width, height: size.height)
                .id(planIdentity)
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .animation(OPSStyle.Animation.panel, value: planIdentity)
        .scaleEffect(viewport.scale)
        .offset(viewport.offset)
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            zoomToggle(at: location, viewportSize: size)
        }
        .gesture(magnificationGesture(viewportSize: size))
        .simultaneousGesture(panGesture(viewportSize: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VinylOrderWorkspaceCopy.drawingLabel)
        .accessibilityValue(VinylOrderWorkspaceCopy.zoomValue(scale: Double(viewport.scale)))
        .accessibilityAdjustableAction { direction in
            adjustZoom(direction, viewportSize: size)
        }
    }

    /// Changes exactly when the drawing would look different — the settings
    /// that shape the layout, plus what the engine made of them.
    private var planIdentity: String {
        [
            plan.settings.direction.rawValue,
            plan.settings.patternMode.rawValue,
            plan.settings.allowsDirectionalChanges ? "mixed" : "locked",
            "\(plan.settings.rollWidthInches)",
            "\(plan.settings.seamOverlapInches)",
            "\(plan.settings.edgeWrapInches)",
            "\(plan.totalStripCount)",
            "\(plan.surfaces.count)"
        ].joined(separator: "|")
    }

    // MARK: - Header

    /// No divider (bug 1a8e48af) — the glass wash IS the separation, and the
    /// drawing passes beneath it when the operator zooms in.
    private func header(layout: VinylOrderWorkspaceGeometry) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, layout.topInset))

            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(projectTitle)
                        .font(OPSStyle.Typography.screenTitle(for: projectTitle))
                        .foregroundColor(OPSStyle.Colors.text)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(contextLine)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .monospacedDigit()
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                Button(action: onClose) {
                    Image(systemName: OPSStyle.Icons.close)
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.md,
                            weight: .semibold
                        ))
                }
                .opsIconButtonStyle(
                    backgroundColor: OPSStyle.Colors.surfaceActive,
                    foregroundColor: OPSStyle.Colors.text
                )
                .accessibilityLabel(VinylOrderWorkspaceCopy.closeLabel)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(height: VinylOrderWorkspaceGeometry.headerHeight)
            // MOBILE.md §2.1 — the nav bar is fixed-height by design. Letting an
            // accessibility type size grow this band would eat the drawing the
            // screen exists to show; the settings panel below scrolls and does
            // scale all the way up.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { headerWash }
    }

    private var headerWash: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(
                OPSStyle.Colors.background.opacity(OPSStyle.Layout.Opacity.heavy)
            )
        }
    }

    private var contextLine: String {
        VinylOrderWorkspaceCopy.contextLine(
            plan: plan,
            deckTitle: deckTitle,
            measurementSystem: measurementSystem
        )
    }

    // MARK: - FIT chip

    /// Present only while the drawing is zoomed. At fit there is nothing to
    /// return to, so the chip does not sit there as a permanently dead control.
    @ViewBuilder
    private var fitChip: some View {
        if !viewport.isFitted {
            Button(action: fitLayout) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.fit)
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.md,
                            weight: .semibold
                        ))

                    Text(VinylOrderWorkspaceCopy.fitAction)
                        .font(OPSStyle.Typography.buttonLabel)
                }
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassDense(cornerRadius: OPSStyle.Layout.panelRadius)
            }
            .buttonStyle(.plain)
            // The chip is a fixed 44pt overlay on the drawing — same reasoning
            // as the header band. VoiceOver reaches zoom through the drawing's
            // adjustable action, so nothing is lost at the largest sizes.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityLabel(VinylOrderWorkspaceCopy.fitLabel)
            .transition(.opacity)
        }
    }

    // MARK: - Gestures

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

    /// Discovery beat: the zoom lands under the finger and the light impact
    /// fires with it, so the gesture reads as having been received.
    private func zoomToggle(at location: CGPoint, viewportSize: CGSize) {
        withAnimation(OPSStyle.Animation.page) {
            viewport.toggleFit(at: location, viewportSize: viewportSize)
        }
        VinylOrderInteractionFeedback.fire()
    }

    private func adjustZoom(
        _ direction: AccessibilityAdjustmentDirection,
        viewportSize: CGSize
    ) {
        let step: CGFloat
        switch direction {
        case .increment: step = VinylOrderViewportState.doubleTapScale
        case .decrement: step = 1 / VinylOrderViewportState.doubleTapScale
        @unknown default: return
        }
        withAnimation(OPSStyle.Animation.page) {
            viewport.applyZoom(multiplier: step, viewportSize: viewportSize)
        }
        VinylOrderInteractionFeedback.fire()
    }

    private func fitLayout() {
        withAnimation(OPSStyle.Animation.page) {
            viewport.fit()
        }
        VinylOrderInteractionFeedback.fire()
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
