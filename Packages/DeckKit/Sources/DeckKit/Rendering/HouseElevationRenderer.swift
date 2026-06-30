import CoreGraphics
import Foundation
import OPSDesignKit
import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias ElevationPlatformColor = UIColor
private typealias ElevationPlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias ElevationPlatformColor = NSColor
private typealias ElevationPlatformFont = NSFont
#endif

public struct HouseElevationRenderTokens: Equatable {
    public var margin: CGFloat
    public var hairlineWidth: CGFloat
    public var emphasisLineWidth: CGFloat
    public var hatchSpacing: CGFloat
    public var hatchLength: CGFloat
    public var openingGlyphInset: CGFloat
    public var calloutDiameter: CGFloat
    public var calloutLeaderLength: CGFloat
    public var calloutTextFontName: String
    public var dimensionFontName: String
    public var labelFontSize: CGFloat
    public var dimensionFontSize: CGFloat

    public init(
        margin: CGFloat,
        hairlineWidth: CGFloat,
        emphasisLineWidth: CGFloat,
        hatchSpacing: CGFloat,
        hatchLength: CGFloat,
        openingGlyphInset: CGFloat,
        calloutDiameter: CGFloat,
        calloutLeaderLength: CGFloat,
        calloutTextFontName: String,
        dimensionFontName: String,
        labelFontSize: CGFloat,
        dimensionFontSize: CGFloat
    ) {
        self.margin = margin
        self.hairlineWidth = hairlineWidth
        self.emphasisLineWidth = emphasisLineWidth
        self.hatchSpacing = hatchSpacing
        self.hatchLength = hatchLength
        self.openingGlyphInset = openingGlyphInset
        self.calloutDiameter = calloutDiameter
        self.calloutLeaderLength = calloutLeaderLength
        self.calloutTextFontName = calloutTextFontName
        self.dimensionFontName = dimensionFontName
        self.labelFontSize = labelFontSize
        self.dimensionFontSize = dimensionFontSize
    }

    public static let elevationSheet = HouseElevationRenderTokens(
        margin: OPSStyle.Layout.spacing5,
        hairlineWidth: OPSStyle.Layout.Border.standard,
        emphasisLineWidth: OPSStyle.Layout.Border.thick,
        hatchSpacing: OPSStyle.Layout.spacing2,
        hatchLength: OPSStyle.Layout.spacing2,
        openingGlyphInset: OPSStyle.Layout.spacing1,
        calloutDiameter: OPSStyle.Layout.IconSize.lg,
        calloutLeaderLength: OPSStyle.Layout.spacing3,
        calloutTextFontName: "JetBrainsMono-Medium",
        dimensionFontName: "JetBrainsMono-Regular",
        labelFontSize: OPSStyle.Layout.spacing2_5,
        dimensionFontSize: OPSStyle.Layout.spacing2_5
    )
}

public enum HouseElevationRenderer {
    public struct ElevationLayout: Equatable {
        public var canvasSize: CGSize
        public var contentRect: CGRect
        public var wallRect: CGRect
        public var gradeLineY: CGFloat
        public var deckSurfaceY: CGFloat
        public var storyLineYs: [CGFloat]
        public var openings: [OpeningLayout]
        public var callouts: [CalloutLayout]
        public var scale: CGFloat

        public init(
            canvasSize: CGSize,
            contentRect: CGRect,
            wallRect: CGRect,
            gradeLineY: CGFloat,
            deckSurfaceY: CGFloat,
            storyLineYs: [CGFloat],
            openings: [OpeningLayout],
            callouts: [CalloutLayout],
            scale: CGFloat
        ) {
            self.canvasSize = canvasSize
            self.contentRect = contentRect
            self.wallRect = wallRect
            self.gradeLineY = gradeLineY
            self.deckSurfaceY = deckSurfaceY
            self.storyLineYs = storyLineYs
            self.openings = openings
            self.callouts = callouts
            self.scale = scale
        }
    }

    public struct OpeningLayout: Equatable, Identifiable {
        public var id: String
        public var kind: OpeningKind
        public var rect: CGRect
        public var calloutTag: String

        public init(
            id: String,
            kind: OpeningKind,
            rect: CGRect,
            calloutTag: String
        ) {
            self.id = id
            self.kind = kind
            self.rect = rect
            self.calloutTag = calloutTag
        }
    }

    public struct CalloutLayout: Equatable, Identifiable {
        public var id: String
        public var tag: String
        public var anchor: CGPoint
        public var leaderEnd: CGPoint
        public var badgeRect: CGRect

        public init(
            id: String,
            tag: String,
            anchor: CGPoint,
            leaderEnd: CGPoint,
            badgeRect: CGRect
        ) {
            self.id = id
            self.tag = tag
            self.anchor = anchor
            self.leaderEnd = leaderEnd
            self.badgeRect = badgeRect
        }
    }

    public static func layout(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize,
        tokens: HouseElevationRenderTokens = .elevationSheet
    ) -> ElevationLayout {
        let canvas = CGRect(origin: .zero, size: size)
        let contentRect = contentRect(in: canvas, margin: tokens.margin)
        let sourceBounds = sourceBounds(for: elevation)
        let sourceWidth = max(elevation.wallLengthInches, 1)
        let sourceHeight = max(sourceBounds.maxY - sourceBounds.minY, 1)
        let scale = min(
            contentRect.width / CGFloat(sourceWidth),
            contentRect.height / CGFloat(sourceHeight)
        )
        let resolvedScale = scale.isFinite && scale > 0 ? scale : 1
        let scaledSize = CGSize(
            width: CGFloat(sourceWidth) * resolvedScale,
            height: CGFloat(sourceHeight) * resolvedScale
        )
        let drawingRect = CGRect(
            x: contentRect.midX - scaledSize.width / 2,
            y: contentRect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        func point(x: Double, y: Double) -> CGPoint {
            CGPoint(
                x: drawingRect.minX + CGFloat(x) * resolvedScale,
                y: drawingRect.maxY - CGFloat(y - sourceBounds.minY) * resolvedScale
            )
        }

        func rect(from sourceRect: CGRect) -> CGRect {
            let topLeft = point(
                x: Double(sourceRect.minX),
                y: Double(sourceRect.maxY)
            )
            let bottomRight = point(
                x: Double(sourceRect.maxX),
                y: Double(sourceRect.minY)
            )
            return CGRect(
                x: min(topLeft.x, bottomRight.x),
                y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            )
        }

        let wallMinY = min(elevation.deckSurfaceYInches, elevation.wallTopYInches)
        let wallMaxY = max(elevation.deckSurfaceYInches, elevation.wallTopYInches)
        let wallRect = rect(
            from: CGRect(
                x: 0,
                y: wallMinY,
                width: elevation.wallLengthInches,
                height: max(wallMaxY - wallMinY, 1)
            )
        )
        let openingLayouts = elevation.openings.map { opening in
            OpeningLayout(
                id: opening.id,
                kind: opening.kind,
                rect: rect(from: opening.rect),
                calloutTag: opening.calloutTag
            )
        }
        let callouts = openingLayouts.map { opening in
            calloutLayout(for: opening, contentRect: contentRect, tokens: tokens)
        }

        return ElevationLayout(
            canvasSize: size,
            contentRect: contentRect,
            wallRect: wallRect,
            gradeLineY: point(x: 0, y: elevation.gradeYInches).y,
            deckSurfaceY: point(x: 0, y: elevation.deckSurfaceYInches).y,
            storyLineYs: elevation.storyLines.map { point(x: 0, y: $0).y },
            openings: openingLayouts,
            callouts: callouts,
            scale: resolvedScale
        )
    }

    #if canImport(UIKit)
    public static func render(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            draw(
                elevation,
                size: size,
                context: context.cgContext,
                tokens: .elevationSheet
            )
        }
    }
    #elseif canImport(AppKit)
    public static func render(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        if let context = NSGraphicsContext.current?.cgContext {
            draw(
                elevation,
                size: size,
                context: context,
                tokens: .elevationSheet
            )
        }
        image.unlockFocus()
        return image
    }
    #endif

    private static func draw(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize,
        context: CGContext,
        tokens: HouseElevationRenderTokens
    ) {
        let layout = layout(elevation, size: size, tokens: tokens)
        let palette = HouseElevationRenderPalette()
        let canvas = CGRect(origin: .zero, size: size)

        context.setFillColor(palette.background.cgColor)
        context.fill(canvas)

        drawGradeLine(layout, context: context, tokens: tokens, palette: palette)
        drawWallFace(layout, context: context, tokens: tokens, palette: palette)
        drawStoryLines(layout, context: context, tokens: tokens, palette: palette)
        drawDeckSurfaceLine(layout, context: context, tokens: tokens, palette: palette)
        drawOpenings(layout.openings, context: context, tokens: tokens, palette: palette)
        drawDimensions(elevation, layout: layout, context: context, tokens: tokens, palette: palette)
        drawCallouts(layout.callouts, context: context, tokens: tokens, palette: palette)
    }

    private static func drawGradeLine(
        _ layout: ElevationLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        context.saveGState()
        context.setStrokeColor(palette.grade.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: CGPoint(x: layout.contentRect.minX, y: layout.gradeLineY))
        context.addLine(to: CGPoint(x: layout.contentRect.maxX, y: layout.gradeLineY))
        context.strokePath()

        var x = layout.contentRect.minX
        while x <= layout.contentRect.maxX {
            context.move(to: CGPoint(x: x, y: layout.gradeLineY))
            context.addLine(
                to: CGPoint(
                    x: x + tokens.hatchLength,
                    y: layout.gradeLineY + tokens.hatchLength
                )
            )
            x += tokens.hatchSpacing
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawWallFace(
        _ layout: ElevationLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        context.setFillColor(palette.wallFill.cgColor)
        context.fill(layout.wallRect)
        context.setStrokeColor(palette.wallStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.stroke(layout.wallRect)
    }

    private static func drawStoryLines(
        _ layout: ElevationLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        context.saveGState()
        context.setStrokeColor(palette.storyLine.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.setLineDash(
            phase: 0,
            lengths: [tokens.hatchLength, tokens.hatchSpacing]
        )
        for y in layout.storyLineYs where y > layout.wallRect.minY && y < layout.wallRect.maxY {
            context.move(to: CGPoint(x: layout.wallRect.minX, y: y))
            context.addLine(to: CGPoint(x: layout.wallRect.maxX, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawDeckSurfaceLine(
        _ layout: ElevationLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        context.setStrokeColor(palette.deckSurface.cgColor)
        context.setLineWidth(tokens.emphasisLineWidth)
        context.move(
            to: CGPoint(x: layout.wallRect.minX, y: layout.deckSurfaceY)
        )
        context.addLine(
            to: CGPoint(x: layout.wallRect.maxX, y: layout.deckSurfaceY)
        )
        context.strokePath()
    }

    private static func drawOpenings(
        _ openings: [OpeningLayout],
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        for opening in openings {
            context.setFillColor(palette.openingFill.cgColor)
            context.fill(opening.rect)
            context.setStrokeColor(palette.openingStroke.cgColor)
            context.setLineWidth(tokens.hairlineWidth)
            context.stroke(opening.rect)
            drawOpeningGlyph(opening, context: context, tokens: tokens, palette: palette)
        }
    }

    private static func drawOpeningGlyph(
        _ opening: OpeningLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        let rect = opening.rect.insetBy(
            dx: min(tokens.openingGlyphInset, opening.rect.width / 3),
            dy: min(tokens.openingGlyphInset, opening.rect.height / 3)
        )
        context.setStrokeColor(palette.openingGlyph.cgColor)
        context.setLineWidth(tokens.hairlineWidth)

        switch opening.kind {
        case .patioDoor, .frenchDoor, .sliderDoor:
            context.move(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        case .window:
            context.move(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        context.strokePath()
    }

    private static func drawDimensions(
        _ elevation: HouseElevationProjector.Elevation,
        layout: ElevationLayout,
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        let widthLabel = formatInches(elevation.wallLengthInches)
        drawText(
            widthLabel,
            in: CGRect(
                x: layout.wallRect.minX,
                y: min(
                    layout.deckSurfaceY + tokens.hatchSpacing,
                    layout.contentRect.maxY - tokens.dimensionFontSize
                ),
                width: layout.wallRect.width,
                height: tokens.dimensionFontSize + tokens.hatchSpacing
            ),
            fontName: tokens.dimensionFontName,
            fontSize: tokens.dimensionFontSize,
            color: palette.dimensionText,
            alignment: .center
        )

        let heightLabel = formatInches(
            elevation.wallTopYInches - elevation.deckSurfaceYInches
        )
        drawText(
            heightLabel,
            in: CGRect(
                x: layout.wallRect.maxX + tokens.hatchSpacing,
                y: layout.wallRect.minY,
                width: max(layout.contentRect.maxX - layout.wallRect.maxX - tokens.hatchSpacing, 0),
                height: tokens.dimensionFontSize + tokens.hatchSpacing
            ),
            fontName: tokens.dimensionFontName,
            fontSize: tokens.dimensionFontSize,
            color: palette.dimensionText,
            alignment: .left
        )
    }

    private static func drawCallouts(
        _ callouts: [CalloutLayout],
        context: CGContext,
        tokens: HouseElevationRenderTokens,
        palette: HouseElevationRenderPalette
    ) {
        for callout in callouts {
            context.setStrokeColor(palette.calloutStroke.cgColor)
            context.setLineWidth(tokens.hairlineWidth)
            context.move(to: callout.anchor)
            context.addLine(to: callout.leaderEnd)
            context.strokePath()

            context.setFillColor(palette.calloutFill.cgColor)
            context.fillEllipse(in: callout.badgeRect)
            context.setStrokeColor(palette.calloutStroke.cgColor)
            context.strokeEllipse(in: callout.badgeRect)
            drawText(
                callout.tag,
                in: callout.badgeRect,
                fontName: tokens.calloutTextFontName,
                fontSize: tokens.labelFontSize,
                color: palette.calloutText,
                alignment: .center
            )
        }
    }

    private static func calloutLayout(
        for opening: OpeningLayout,
        contentRect: CGRect,
        tokens: HouseElevationRenderTokens
    ) -> CalloutLayout {
        let diameter = tokens.calloutDiameter
        let anchor = CGPoint(x: opening.rect.midX, y: opening.rect.minY)
        let preferredCenter = CGPoint(
            x: anchor.x,
            y: anchor.y - tokens.calloutLeaderLength - diameter / 2
        )
        let center = CGPoint(
            x: clamp(
                preferredCenter.x,
                min: contentRect.minX + diameter / 2,
                max: contentRect.maxX - diameter / 2
            ),
            y: clamp(
                preferredCenter.y,
                min: contentRect.minY + diameter / 2,
                max: contentRect.maxY - diameter / 2
            )
        )
        let badgeRect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        return CalloutLayout(
            id: opening.id,
            tag: opening.calloutTag,
            anchor: anchor,
            leaderEnd: CGPoint(x: center.x, y: badgeRect.maxY),
            badgeRect: badgeRect
        )
    }

    private static func contentRect(in canvas: CGRect, margin: CGFloat) -> CGRect {
        let insetX = min(max(margin, 0), max(canvas.width / 4, 0))
        let insetY = min(max(margin, 0), max(canvas.height / 4, 0))
        return canvas.insetBy(dx: insetX, dy: insetY)
    }

    private static func sourceBounds(
        for elevation: HouseElevationProjector.Elevation
    ) -> (minY: Double, maxY: Double) {
        var minY = min(
            0,
            elevation.gradeYInches,
            elevation.deckSurfaceYInches,
            elevation.wallTopYInches
        )
        var maxY = max(
            elevation.gradeYInches,
            elevation.deckSurfaceYInches,
            elevation.wallTopYInches
        )

        for opening in elevation.openings {
            minY = min(minY, Double(opening.rect.minY))
            maxY = max(maxY, Double(opening.rect.maxY))
        }

        for line in elevation.storyLines {
            minY = min(minY, line)
            maxY = max(maxY, line)
        }

        if maxY <= minY {
            maxY = minY + 1
        }

        return (minY, maxY)
    }

    private static func formatInches(_ rawInches: Double) -> String {
        let totalInches = Int(rawInches.rounded())
        let feet = totalInches / 12
        let inches = abs(totalInches % 12)

        if feet == 0 {
            return "\(inches)″"
        }

        return "\(feet)′-\(inches)″"
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else { return minValue }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        fontName: String,
        fontSize: CGFloat,
        color: ElevationPlatformColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let font = ElevationPlatformFont(name: fontName, size: fontSize)
            ?? fallbackFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]

        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private static func fallbackFont(size: CGFloat) -> ElevationPlatformFont {
        #if canImport(UIKit)
        return ElevationPlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #elseif canImport(AppKit)
        return ElevationPlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
    }
}

private struct HouseElevationRenderPalette {
    let background: ElevationPlatformColor
    let wallFill: ElevationPlatformColor
    let wallStroke: ElevationPlatformColor
    let openingFill: ElevationPlatformColor
    let openingStroke: ElevationPlatformColor
    let openingGlyph: ElevationPlatformColor
    let grade: ElevationPlatformColor
    let deckSurface: ElevationPlatformColor
    let storyLine: ElevationPlatformColor
    let dimensionText: ElevationPlatformColor
    let calloutFill: ElevationPlatformColor
    let calloutStroke: ElevationPlatformColor
    let calloutText: ElevationPlatformColor

    init() {
        self.background = Self.platformColor(from: OPSStyle.Colors.background)
        self.wallFill = Self.platformColor(from: OPSStyle.Colors.glassApprox)
        self.wallStroke = Self.platformColor(from: OPSStyle.Colors.glassBorder)
        self.openingFill = Self.platformColor(from: OPSStyle.Colors.background)
        self.openingStroke = Self.platformColor(from: OPSStyle.Colors.text2)
        self.openingGlyph = Self.platformColor(from: OPSStyle.Colors.text3)
        self.grade = Self.platformColor(from: OPSStyle.Colors.textMute)
        self.deckSurface = Self.platformColor(from: OPSStyle.Colors.text)
        self.storyLine = Self.platformColor(from: OPSStyle.Colors.lineSoft)
        self.dimensionText = Self.platformColor(from: OPSStyle.Colors.text2)
        self.calloutFill = Self.platformColor(from: OPSStyle.Colors.glassDenseApprox)
        self.calloutStroke = Self.platformColor(from: OPSStyle.Colors.text2)
        self.calloutText = Self.platformColor(from: OPSStyle.Colors.text)
    }

    private static func platformColor(from color: Color) -> ElevationPlatformColor {
        ElevationPlatformColor(color)
    }
}
