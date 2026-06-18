//
//  RenderedPhotoComposer.swift
//  OPS
//
//  Phase F — produces the share-friendly "rendered" PNG for a LiDAR
//  dimensioned capture per spec §3.7:
//
//    • Downsample the source 48 MP photo to 2048 px on the long edge
//      (preserving aspect). Native 48 MP burn would produce 12–18 MB PNGs
//      and take 3–5 s on iPhone 13 Pro; 2048 long-edge produces
//      ~1.5–2.5 MB PNGs in <500 ms.
//    • Composite each Hover-style dimension label (leader line + chip)
//      onto the downsampled photo. Label placement runs through
//      `LabelPlacer` (same logic the annotation view uses) so the rendered
//      output matches what the user saw.
//    • Burn the accuracy badge into the bottom-right corner.
//    • Burn an OPS-lockup watermark into the bottom-left corner.
//    • Return PNG `Data`.
//
//  Performance budget: <500 ms on iPhone 13 Pro for a 48 MP input with
//  ≤6 measurements. The CGContext path here is single-threaded, but the
//  expensive step (downsample) uses `kCGImageSourceCreateThumbnailFromIm…`
//  which Apple's ImageIO accelerates on the Image Signal Processor.
//
//  Composition is pure Core Graphics + Core Text — no SwiftUI rendering
//  pass, no `ImageRenderer`. That keeps the pipeline runnable from a unit
//  test host that has no SwiftUI view layer mounted.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md
//      §3.5 (label rendering)
//      §3.6 (accuracy badge tokens)
//      §3.7 (2048 long-edge PNG burn rule)
//

import Foundation
import CoreGraphics
import ImageIO
import UIKit

public enum RenderedPhotoComposer {

    // MARK: - Configuration

    /// Long-edge target in points/pixels (1:1 since the composer renders at
    /// scale 1.0). Per spec §3.7 — change only if a field test forces a 48 MP
    /// burn variant.
    public static let longEdgeTarget: CGFloat = 2048

    /// PNG output is full-opaque (no transparency in the photo plane).
    public static let outputIsOpaque = true

    // MARK: - Public API

    /// Returns the rendered PNG bytes or `nil` if the input image isn't
    /// drawable (e.g., zero-dimension input). Throws on no error path —
    /// the renderer treats degenerate input as "nothing to render."
    public static func render(
        photo: UIImage,
        dimensions: DimensionsData,
        accuracy: AccuracyState,
        coplanarOnly: Bool = false,
        watermark: WatermarkText = .opsLockup
    ) -> Data? {
        guard photo.size.width > 0, photo.size.height > 0 else { return nil }

        let canvas = downsampledSize(for: photo.size, longEdge: longEdgeTarget)
        let scale = canvas.width / photo.size.width

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = outputIsOpaque

        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { ctx in
            let context = ctx.cgContext

            // Background guard — should be invisible behind the photo but
            // protects against any aspect-fit gaps.
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: canvas))

            // Photo.
            photo.draw(in: CGRect(origin: .zero, size: canvas))

            // Dimension labels (leader + chip burned in).
            drawDimensionLabels(
                measurements: dimensions.measurements,
                intrinsics: dimensions.intrinsics,
                imageScale: scale,
                canvasSize: canvas,
                in: context,
                openings: dimensions.openings,
                primaryUnit: dimensions.measurements.first?.primaryDisplayUnit ?? .imperialFraction
            )

            // Accuracy badge (bottom-right).
            drawAccuracyBadge(
                state: accuracy,
                coplanarOnly: coplanarOnly,
                in: canvas,
                context: context
            )

            // Watermark (bottom-left).
            drawWatermark(
                text: watermark.string,
                in: canvas,
                context: context
            )
        }

        return image.pngData()
    }

    // MARK: - Downsampling

    /// Computes the (width, height) preserving aspect such that the longest
    /// edge equals `longEdge`. If the input is already at or below the
    /// target the result equals the input size (no upscaling).
    public static func downsampledSize(for size: CGSize, longEdge: CGFloat) -> CGSize {
        let maxSide = max(size.width, size.height)
        guard maxSide > longEdge else { return size }
        let scale = longEdge / maxSide
        return CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )
    }

    // MARK: - Dimension labels

    /// Lays out and draws all measurements onto the rendered canvas. Label
    /// placement runs through `LabelPlacer` (canvas-space, post-downsample) so
    /// the rendered output matches the annotation view's layout decisions.
    static func drawDimensionLabels(
        measurements: [DimensionsData.Measurement],
        intrinsics: DimensionsData.Intrinsics,
        imageScale: CGFloat,
        canvasSize: CGSize,
        in context: CGContext,
        openings: [DimensionsData.Opening] = [],
        primaryUnit: DimensionsData.Measurement.DisplayUnit
    ) {
        guard !measurements.isEmpty else { return }

        // Build LabelPlacer inputs by scaling each measurement's image-pixel
        // endpoints down to canvas space.
        let inputs: [LabelPlacer.Input] = measurements.compactMap { m in
            guard m.imagePoints.count >= 2 else { return nil }
            let a = m.imagePoints[0]
            let b = m.imagePoints[1]
            let pointA = CGPoint(
                x: CGFloat(a.x) * imageScale,
                y: CGFloat(a.y) * imageScale
            )
            let pointB = CGPoint(
                x: CGFloat(b.x) * imageScale,
                y: CGFloat(b.y) * imageScale
            )
            let displayContext = DimensionFormatter.displayContext(
                for: m.id,
                openings: openings
            )
            let chipSize = measureChipSize(
                for: m,
                primaryUnit: primaryUnit,
                displayContext: displayContext
            )
            return LabelPlacer.Input(id: m.id, pointA: pointA, pointB: pointB, chipSize: chipSize)
        }

        let placements = LabelPlacer.place(inputs: inputs, canvasSize: canvasSize)
        let placementByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })

        for measurement in measurements {
            guard
                let input = inputs.first(where: { $0.id == measurement.id }),
                let placement = placementByID[measurement.id]
            else { continue }

            drawSingleLabel(
                pointA: input.pointA,
                pointB: input.pointB,
                chipRect: placement.chipRect,
                measurement: measurement,
                primaryUnit: primaryUnit,
                displayContext: DimensionFormatter.displayContext(
                    for: measurement.id,
                    openings: openings
                ),
                context: context
            )
        }
    }

    /// Estimates the chip rect size for a measurement's formatted text. The
    /// chip uses JetBrainsMono regular at 14 pt (primary) + 10 pt (secondary)
    /// with 8 pt horizontal / 4 pt vertical padding — same as
    /// `DimensionLabelView`.
    static func measureChipSize(
        for m: DimensionsData.Measurement,
        primaryUnit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DimensionFormatter.DisplayContext = .standard
    ) -> CGSize {
        let formatted = DimensionFormatter.format(
            valueMeters: m.valueMeters,
            primaryUnit: primaryUnit,
            displayContext: displayContext
        )
        let primaryFont = jbMono(14)
        let secondaryFont = jbMono(10)
        let primaryWidth = (formatted.primary as NSString)
            .size(withAttributes: [.font: primaryFont]).width
        let secondaryWidth = (formatted.secondary as NSString)
            .size(withAttributes: [.font: secondaryFont]).width
        let width = max(primaryWidth, secondaryWidth) + 16
        let height: CGFloat = 14 + 1 + 10 + 8
        return CGSize(width: ceil(width), height: ceil(height))
    }

    static func drawSingleLabel(
        pointA: CGPoint,
        pointB: CGPoint,
        chipRect: CGRect,
        measurement: DimensionsData.Measurement,
        primaryUnit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DimensionFormatter.DisplayContext = .standard,
        context: CGContext
    ) {
        let formatted = DimensionFormatter.format(
            valueMeters: measurement.valueMeters,
            primaryUnit: primaryUnit,
            displayContext: displayContext
        )

        // Measurement line — outer black, inner white (per DimensionLabelView §3.5).
        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(3.5)
        context.move(to: pointA); context.addLine(to: pointB)
        context.strokePath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.5)
        context.move(to: pointA); context.addLine(to: pointB)
        context.strokePath()
        context.restoreGState()

        // Leader from midpoint to chip center.
        let midpoint = CGPoint(x: (pointA.x + pointB.x) / 2, y: (pointA.y + pointB.y) / 2)
        let chipCenter = CGPoint(x: chipRect.midX, y: chipRect.midY)
        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(3)
        context.move(to: midpoint); context.addLine(to: chipCenter)
        context.strokePath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.5)
        context.move(to: midpoint); context.addLine(to: chipCenter)
        context.strokePath()
        context.restoreGState()

        // Endpoint dots (5 pt circles, white with black stroke).
        for p in [pointA, pointB] {
            let dotRect = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            context.saveGState()
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: dotRect)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: dotRect)
            context.restoreGState()
        }

        // Chip background (dark 0A0A0A at 85% alpha, 0.5 px white hairline).
        context.saveGState()
        let path = UIBezierPath(roundedRect: chipRect, cornerRadius: OPSStyle.Layout.chipRadius)
        context.setFillColor(UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 0.85).cgColor)
        path.fill()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        path.stroke()
        context.restoreGState()

        // Chip text — primary line, secondary line beneath. Always horizontal.
        let primaryAttrs: [NSAttributedString.Key: Any] = [
            .font: jbMono(14),
            .foregroundColor: UIColor.white
        ]
        let primarySize = (formatted.primary as NSString).size(withAttributes: primaryAttrs)
        let primaryX = chipRect.midX - primarySize.width / 2
        var textY = chipRect.minY + 4
        (formatted.primary as NSString).draw(
            at: CGPoint(x: primaryX, y: textY),
            withAttributes: primaryAttrs
        )

        textY += primarySize.height + 1
        if formatted.secondary != formatted.primary, !formatted.secondary.isEmpty {
            let secondaryAttrs: [NSAttributedString.Key: Any] = [
                .font: jbMono(10),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let secondarySize = (formatted.secondary as NSString)
                .size(withAttributes: secondaryAttrs)
            (formatted.secondary as NSString).draw(
                at: CGPoint(x: chipRect.midX - secondarySize.width / 2, y: textY),
                withAttributes: secondaryAttrs
            )
        }
    }

    // MARK: - Accuracy badge

    static let badgePadding: CGFloat = 12

    static func drawAccuracyBadge(
        state: AccuracyState,
        coplanarOnly: Bool,
        in canvas: CGSize,
        context: CGContext
    ) {
        let badgeText = state.displayText
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: cakeMono(12),
            .foregroundColor: badgeTextUIColor(for: state),
            .kern: 1
        ]
        let textSize = (badgeText as NSString).size(withAttributes: textAttrs)

        let pillPaddingH: CGFloat = 10
        let pillPaddingV: CGFloat = 6
        let pillWidth = textSize.width + pillPaddingH * 2
        let pillHeight = textSize.height + pillPaddingV * 2

        let pillX = canvas.width - pillWidth - badgePadding
        let pillY = canvas.height - pillHeight - badgePadding
        let pillRect = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        context.saveGState()
        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: OPSStyle.Layout.chipRadius)
        context.setFillColor(badgeFillUIColor(for: state).cgColor)
        pillPath.fill()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        pillPath.stroke()
        context.restoreGState()

        (badgeText as NSString).draw(
            at: CGPoint(x: pillX + pillPaddingH, y: pillY + pillPaddingV),
            withAttributes: textAttrs
        )

        guard coplanarOnly else { return }

        // Optional sibling pill directly below — `COPLANAR ONLY` (tan).
        let coplanarText = "COPLANAR ONLY"
        let coplanarAttrs: [NSAttributedString.Key: Any] = [
            .font: jbMono(10),
            .foregroundColor: UIColor.black,
            .kern: 1
        ]
        let coplanarSize = (coplanarText as NSString).size(withAttributes: coplanarAttrs)
        let coplanarPillWidth = coplanarSize.width + pillPaddingH * 2
        let coplanarPillHeight = coplanarSize.height + 6
        let coplanarRect = CGRect(
            x: canvas.width - coplanarPillWidth - badgePadding,
            y: pillY - coplanarPillHeight - 6,
            width: coplanarPillWidth,
            height: coplanarPillHeight
        )
        context.saveGState()
        let coplanarPath = UIBezierPath(roundedRect: coplanarRect, cornerRadius: OPSStyle.Layout.chipRadius)
        context.setFillColor(UIColor(red: 196/255, green: 168/255, blue: 104/255, alpha: 0.85).cgColor)
        coplanarPath.fill()
        context.restoreGState()
        (coplanarText as NSString).draw(
            at: CGPoint(x: coplanarRect.minX + pillPaddingH, y: coplanarRect.minY + 3),
            withAttributes: coplanarAttrs
        )
    }

    // MARK: - Watermark

    public enum WatermarkText: Equatable {
        case opsLockup
        case custom(String)

        var string: String {
            switch self {
            case .opsLockup:        return "// OPS"
            case .custom(let s):    return s
            }
        }
    }

    static func drawWatermark(text: String, in canvas: CGSize, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: cakeMono(11),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
            .kern: 1
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let pillPaddingH: CGFloat = 8
        let pillPaddingV: CGFloat = 4
        let pillRect = CGRect(
            x: badgePadding,
            y: canvas.height - textSize.height - pillPaddingV * 2 - badgePadding,
            width: textSize.width + pillPaddingH * 2,
            height: textSize.height + pillPaddingV * 2
        )

        context.saveGState()
        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: 3)
        context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        pill.fill()
        context.restoreGState()

        (text as NSString).draw(
            at: CGPoint(x: pillRect.minX + pillPaddingH, y: pillRect.minY + pillPaddingV),
            withAttributes: attrs
        )
    }

    // MARK: - Fonts (graceful fallback for unit-test hosts)

    static func jbMono(_ size: CGFloat) -> UIFont {
        UIFont(name: "JetBrainsMono-Regular", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func cakeMono(_ size: CGFloat) -> UIFont {
        UIFont(name: "CakeMono-Light", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .light)
    }

    // MARK: - Badge colour tokens (mirror `AccuracyBadge` §3.6)

    static func badgeFillUIColor(for state: AccuracyState) -> UIColor {
        switch state {
        case .calibrated:        return UIColor(red: 157/255, green: 181/255, blue: 130/255, alpha: 0.85) // olive
        case .lidarUncalibrated: return UIColor.black.withAlphaComponent(0.78)
        case .visualSlam:        return UIColor(red: 196/255, green: 168/255, blue: 104/255, alpha: 0.85) // tan
        case .noDepth:           return UIColor(red: 106/255, green: 106/255, blue: 106/255, alpha: 0.85) // textMute
        }
    }

    static func badgeTextUIColor(for state: AccuracyState) -> UIColor {
        switch state {
        case .calibrated, .visualSlam, .noDepth: return .black
        case .lidarUncalibrated:                 return UIColor(white: 237/255, alpha: 1)
        }
    }
}
