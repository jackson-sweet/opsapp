import CoreGraphics
import CoreText
import Foundation
import OPSDesignKit
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias DraftingPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias DraftingPlatformColor = NSColor
#endif

public struct DrawingScale: Codable, Equatable {
    public var inchesPerFoot: Double

    public init(inchesPerFoot: Double) {
        self.inchesPerFoot = inchesPerFoot
    }

    var pagePointsPerModelInch: CGFloat {
        CGFloat(max(inchesPerFoot, 0)) * 72 / 12
    }

    func pagePoints(forModelInches inches: CGFloat) -> CGFloat {
        inches * pagePointsPerModelInch
    }
}

struct DraftingCanvas {
    let scale: DrawingScale
    let pageRect: CGRect
    let tokens: DraftingCanvasTokens
    private let palette = DraftingCanvasPalette()

    init(
        scale: DrawingScale,
        pageRect: CGRect,
        tokens: DraftingCanvasTokens = .permitSheet
    ) {
        self.scale = scale
        self.pageRect = pageRect
        self.tokens = tokens
    }

    func modelToPage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: pageRect.minX + scale.pagePoints(forModelInches: point.x),
            y: pageRect.minY + scale.pagePoints(forModelInches: point.y)
        )
    }

    func drawDimension(
        from start: CGPoint,
        to end: CGPoint,
        in context: CGContext,
        label: String
    ) {
        let startPage = modelToPage(start)
        let endPage = modelToPage(end)
        let vector = CGVector(dx: endPage.x - startPage.x, dy: endPage.y - startPage.y)
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return }

        let unit = CGVector(dx: vector.dx / length, dy: vector.dy / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let offset = tokens.dimensionOffset
        let tick = tokens.dimensionTickLength
        let dimensionStart = startPage.offset(by: normal, distance: offset)
        let dimensionEnd = endPage.offset(by: normal, distance: offset)

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.setLineCap(.butt)

        context.move(to: startPage)
        context.addLine(to: startPage.offset(by: normal, distance: offset + tick))
        context.move(to: endPage)
        context.addLine(to: endPage.offset(by: normal, distance: offset + tick))
        context.move(to: dimensionStart)
        context.addLine(to: dimensionEnd)
        context.move(to: dimensionStart.offset(by: normal, distance: -tick / 2))
        context.addLine(to: dimensionStart.offset(by: normal, distance: tick / 2))
        context.move(to: dimensionEnd.offset(by: normal, distance: -tick / 2))
        context.addLine(to: dimensionEnd.offset(by: normal, distance: tick / 2))
        context.strokePath()
        context.restoreGState()

        let midpoint = CGPoint(
            x: (dimensionStart.x + dimensionEnd.x) / 2,
            y: (dimensionStart.y + dimensionEnd.y) / 2
        ).offset(by: normal, distance: tokens.dimensionLabelOffset)
        drawText(
            label,
            centeredAt: midpoint,
            size: CGSize(width: max(length, tokens.dimensionLabelMinWidth), height: tokens.dimensionLabelHeight),
            fontName: tokens.dimensionFontName,
            fontSize: tokens.dimensionFontSize,
            color: palette.secondaryText.cgColor,
            in: context
        )
    }

    func drawLeaderCallout(at point: CGPoint, text: String, in context: CGContext) {
        let anchor = modelToPage(point)
        let leaderEnd = CGPoint(
            x: anchor.x + tokens.calloutLeaderLength,
            y: anchor.y - tokens.calloutLeaderLength
        )
        let badgeRect = CGRect(
            x: leaderEnd.x,
            y: leaderEnd.y - tokens.calloutDiameter / 2,
            width: tokens.calloutDiameter,
            height: tokens.calloutDiameter
        )

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: anchor)
        context.addLine(to: CGPoint(x: badgeRect.minX, y: badgeRect.midY))
        context.strokePath()

        context.setFillColor(palette.calloutFill.cgColor)
        context.fillEllipse(in: badgeRect)
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.strokeEllipse(in: badgeRect)
        context.restoreGState()

        drawText(
            text,
            centeredAt: CGPoint(x: badgeRect.midX, y: badgeRect.midY),
            size: badgeRect.size,
            fontName: tokens.calloutFontName,
            fontSize: tokens.calloutFontSize,
            color: palette.primaryText.cgColor,
            in: context
        )
    }

    func drawScaleBar(in context: CGContext) {
        let origin = CGPoint(
            x: pageRect.minX + tokens.sheetInset,
            y: pageRect.maxY - tokens.sheetInset
        )
        let length = scale.pagePoints(forModelInches: tokens.scaleBarLengthFeet * 12)
        let end = CGPoint(x: origin.x + length, y: origin.y)

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.emphasisLineWidth)
        context.move(to: origin)
        context.addLine(to: end)
        context.strokePath()

        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: CGPoint(x: origin.x, y: origin.y - tokens.dimensionTickLength / 2))
        context.addLine(to: CGPoint(x: origin.x, y: origin.y + tokens.dimensionTickLength / 2))
        context.move(to: CGPoint(x: end.x, y: end.y - tokens.dimensionTickLength / 2))
        context.addLine(to: CGPoint(x: end.x, y: end.y + tokens.dimensionTickLength / 2))
        context.strokePath()
        context.restoreGState()

        drawText(
            DimensionEngine.formatImperial(Double(tokens.scaleBarLengthFeet * 12)),
            centeredAt: CGPoint(x: origin.x + length / 2, y: origin.y - tokens.scaleBarLabelOffset),
            size: CGSize(width: max(length, tokens.dimensionLabelMinWidth), height: tokens.dimensionLabelHeight),
            fontName: tokens.dimensionFontName,
            fontSize: tokens.dimensionFontSize,
            color: palette.secondaryText.cgColor,
            in: context
        )
    }

    func drawNorthArrow(in context: CGContext) {
        let tip = CGPoint(
            x: pageRect.maxX - tokens.sheetInset - tokens.northArrowSize / 2,
            y: pageRect.minY + tokens.sheetInset
        )
        let baseY = tip.y + tokens.northArrowSize
        let halfWidth = tokens.northArrowSize / 3

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setFillColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: tip)
        context.addLine(to: CGPoint(x: tip.x - halfWidth, y: baseY))
        context.addLine(to: CGPoint(x: tip.x, y: baseY - tokens.northArrowSize / 4))
        context.addLine(to: CGPoint(x: tip.x + halfWidth, y: baseY))
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.restoreGState()

        drawText(
            "N",
            centeredAt: CGPoint(x: tip.x, y: baseY + tokens.northArrowLabelOffset),
            size: CGSize(width: tokens.northArrowSize, height: tokens.dimensionLabelHeight),
            fontName: tokens.calloutFontName,
            fontSize: tokens.calloutFontSize,
            color: palette.primaryText.cgColor,
            in: context
        )
    }

    func hatch(_ polygon: [CGPoint], pattern: HatchPattern, in context: CGContext) {
        let pagePolygon = polygon.map(modelToPage)
        guard pagePolygon.count >= 3 else { return }

        let bounds = pagePolygon.reduce(CGRect.null) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }

        context.saveGState()
        context.beginPath()
        context.move(to: pagePolygon[0])
        for point in pagePolygon.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
        context.clip()

        context.setStrokeColor(palette.hatchStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        drawHatchLines(in: bounds, direction: .forward, context: context)
        if pattern == .crosshatch {
            drawHatchLines(in: bounds, direction: .backward, context: context)
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawHatchLines(
        in bounds: CGRect,
        direction: HatchDirection,
        context: CGContext
    ) {
        let span = bounds.width + bounds.height
        var offset = -bounds.height
        while offset <= bounds.width {
            let start: CGPoint
            let end: CGPoint
            switch direction {
            case .forward:
                start = CGPoint(x: bounds.minX + offset, y: bounds.minY)
                end = CGPoint(x: bounds.minX + offset + bounds.height, y: bounds.maxY)
            case .backward:
                start = CGPoint(x: bounds.minX + offset, y: bounds.maxY)
                end = CGPoint(x: bounds.minX + offset + bounds.height, y: bounds.minY)
            }
            context.move(to: start)
            context.addLine(to: end)
            offset += max(tokens.hatchSpacing, span / 1000)
        }
    }

    private func drawText(
        _ text: String,
        centeredAt center: CGPoint,
        size: CGSize,
        fontName: String,
        fontSize: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        drawText(
            text,
            in: rect,
            fontName: fontName,
            fontSize: fontSize,
            color: color,
            context: context
        )
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        fontName: String,
        fontSize: CGFloat,
        color: CGColor,
        context: CGContext
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)

        context.saveGState()
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

struct DraftingCanvasTokens: Equatable {
    var hairlineWidth: CGFloat
    var emphasisLineWidth: CGFloat
    var sheetInset: CGFloat
    var dimensionOffset: CGFloat
    var dimensionLabelOffset: CGFloat
    var dimensionTickLength: CGFloat
    var dimensionLabelMinWidth: CGFloat
    var dimensionLabelHeight: CGFloat
    var dimensionFontName: String
    var dimensionFontSize: CGFloat
    var calloutDiameter: CGFloat
    var calloutLeaderLength: CGFloat
    var calloutFontName: String
    var calloutFontSize: CGFloat
    var scaleBarLengthFeet: CGFloat
    var scaleBarLabelOffset: CGFloat
    var northArrowSize: CGFloat
    var northArrowLabelOffset: CGFloat
    var hatchSpacing: CGFloat

    static let permitSheet = DraftingCanvasTokens(
        hairlineWidth: OPSStyle.Layout.Border.standard,
        emphasisLineWidth: OPSStyle.Layout.Border.thick,
        sheetInset: OPSStyle.Layout.spacing4,
        dimensionOffset: OPSStyle.Layout.spacing3,
        dimensionLabelOffset: OPSStyle.Layout.spacing2,
        dimensionTickLength: OPSStyle.Layout.spacing2,
        dimensionLabelMinWidth: OPSStyle.Layout.touchTargetStandard,
        dimensionLabelHeight: OPSStyle.Layout.spacing4,
        dimensionFontName: "JetBrainsMono-Regular",
        dimensionFontSize: OPSStyle.Layout.spacing2_5,
        calloutDiameter: OPSStyle.Layout.IconSize.lg,
        calloutLeaderLength: OPSStyle.Layout.spacing3,
        calloutFontName: "JetBrainsMono-Medium",
        calloutFontSize: OPSStyle.Layout.spacing2_5,
        scaleBarLengthFeet: 4,
        scaleBarLabelOffset: OPSStyle.Layout.spacing3,
        northArrowSize: OPSStyle.Layout.IconSize.xl,
        northArrowLabelOffset: OPSStyle.Layout.spacing2,
        hatchSpacing: OPSStyle.Layout.spacing2
    )
}

enum HatchPattern: String, Codable, Equatable {
    case diagonal45
    case crosshatch
}

private enum HatchDirection {
    case forward
    case backward
}

private struct DraftingCanvasPalette {
    let primaryStroke: DraftingPlatformColor
    let hatchStroke: DraftingPlatformColor
    let primaryText: DraftingPlatformColor
    let secondaryText: DraftingPlatformColor
    let calloutFill: DraftingPlatformColor

    init() {
        self.primaryStroke = Self.platformColor(from: OPSStyle.Colors.text)
        self.hatchStroke = Self.platformColor(from: OPSStyle.Colors.line)
        self.primaryText = Self.platformColor(from: OPSStyle.Colors.text)
        self.secondaryText = Self.platformColor(from: OPSStyle.Colors.text2)
        self.calloutFill = Self.platformColor(from: OPSStyle.Colors.glassDenseApprox)
    }

    private static func platformColor(from color: Color) -> DraftingPlatformColor {
        DraftingPlatformColor(color)
    }
}

private extension CGPoint {
    func offset(by vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: x + vector.dx * distance, y: y + vector.dy * distance)
    }
}
