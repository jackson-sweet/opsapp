import CoreGraphics
import CoreText
import Foundation
import OPSDesignKit
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlanSheetPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlanSheetPlatformColor = NSColor
#endif

public enum PlanSheetKind: String, Codable, CaseIterable, Hashable {
    case planView
    case framingPlan
    case elevation
    case crossSection
    case sitePlan
    case detailCallout
}

public struct TitleBlock: Codable, Equatable {
    public var projectName: String
    public var address: String?
    public var packageEdition: String
    public var generatedDate: Date
    public var disclaimer: String
    public var peStamp: PEStampRequest?

    public init(
        projectName: String,
        address: String? = nil,
        packageEdition: String,
        generatedDate: Date,
        disclaimer: String,
        peStamp: PEStampRequest? = nil
    ) {
        self.projectName = projectName
        self.address = address
        self.packageEdition = packageEdition
        self.generatedDate = generatedDate
        self.disclaimer = disclaimer
        self.peStamp = peStamp
    }
}

struct PlanSheetRenderResult: Equatable {
    var kind: PlanSheetKind
    var titleBlockTexts: [String]
    var bodyCallouts: [String]
    var placeholders: [String]

    init(
        kind: PlanSheetKind,
        titleBlockTexts: [String] = [],
        bodyCallouts: [String] = [],
        placeholders: [String] = []
    ) {
        self.kind = kind
        self.titleBlockTexts = titleBlockTexts
        self.bodyCallouts = bodyCallouts
        self.placeholders = placeholders
    }
}

enum PlanSheetRenderer {
    @discardableResult
    static func render(
        _ kind: PlanSheetKind,
        data: DeckDrawingData,
        titleBlock: TitleBlock,
        scale: DrawingScale,
        pageRect: CGRect,
        in context: CGContext,
        tokens: PlanSheetTokens = .permitSheet
    ) -> PlanSheetRenderResult {
        let palette = PlanSheetPalette()
        context.setFillColor(palette.background.cgColor)
        context.fill(pageRect)

        let layout = PlanSheetLayout(pageRect: pageRect, tokens: tokens)
        drawSheetBorder(pageRect, context: context, tokens: tokens, palette: palette)

        var result = PlanSheetRenderResult(kind: kind)
        result.titleBlockTexts = TitleBlockRenderer.draw(
            titleBlock,
            kind: kind,
            in: layout.titleBlockRect,
            context: context,
            tokens: tokens,
            palette: palette
        )

        let canvas = DraftingCanvas(
            scale: scale,
            pageRect: layout.drawingRect,
            tokens: tokens.draftingTokens
        )

        switch kind {
        case .planView:
            renderPlanView(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        case .framingPlan:
            renderFramingPlan(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        case .elevation:
            renderElevation(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        case .crossSection:
            renderCrossSection(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        case .sitePlan:
            renderSitePlan(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        case .detailCallout:
            renderDetailCallout(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        }

        return result
    }

    private static func drawSheetBorder(
        _ pageRect: CGRect,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.stroke(pageRect.insetBy(dx: tokens.sheetInset, dy: tokens.sheetInset))
        context.restoreGState()
    }

    private static func renderPlanView(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        let positions = primaryFootprintPositions(data)
        guard positions.count >= 3 else {
            appendPlaceholder("DECK GEOMETRY NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }

        drawPolygon(positions, canvas: canvas, context: context, tokens: tokens, palette: palette)
        for edge in data.allEdges {
            guard let start = data.allVertices.first(where: { $0.id == edge.startVertexId }),
                  let end = data.allVertices.first(where: { $0.id == edge.endVertexId }) else { continue }
            let label = edge.dimension.map(DimensionEngine.formatImperial)
                ?? DimensionEngine.formatImperial(Double(PolygonMath.edgeLength(from: start.position, to: end.position)) / data.effectiveScaleFactor)
            canvas.drawDimension(from: start.position, to: end.position, in: context, label: label)
        }
        canvas.drawNorthArrow(in: context)
        canvas.drawScaleBar(in: context)
        result.bodyCallouts.append("PLAN VIEW")
    }

    private static func renderFramingPlan(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        if let positions = Optional(primaryFootprintPositions(data)), positions.count >= 3 {
            drawPolygon(positions, canvas: canvas, context: context, tokens: tokens, palette: palette)
        }

        guard let framing = data.framing, !framing.members.flatMap(\.members).isEmpty else {
            appendPlaceholder("FRAMING PLAN NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }

        let members = framing.members.flatMap(\.members)
        if members.contains(where: { $0.sizing == nil }) {
            result.bodyCallouts.append("NOT ENGINEERED")
            drawWatermark("NOT ENGINEERED", canvas: canvas, context: context, tokens: tokens, palette: palette)
        }

        for member in members {
            drawMember(member, canvas: canvas, context: context, tokens: tokens, palette: palette)
            let midpoint = CGPoint(x: (member.start.x + member.end.x) / 2, y: (member.start.y + member.end.y) / 2)
            canvas.drawLeaderCallout(at: midpoint, text: calloutTag(for: member), in: context)
            result.bodyCallouts.append(memberCallout(member))
        }
        canvas.drawScaleBar(in: context)
    }

    private static func renderElevation(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        guard data.house != nil else {
            appendPlaceholder("HOUSE MODEL NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }
        guard data.terrain != nil else {
            appendPlaceholder("TERRAIN MODEL NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }
        guard let elevation = HouseElevationProjector.projectAllFaces(data).first else {
            appendPlaceholder("HOUSE EDGE NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }

        let origin = canvas.pageRect.origin
        let width = min(canvas.pageRect.width, CGFloat(elevation.wallLengthInches) * tokens.elevationScale)
        let gradeY = canvas.pageRect.midY + tokens.sectionStackGap
        let deckY = gradeY - CGFloat(elevation.deckSurfaceYInches) * tokens.elevationScale
        let wallTopY = deckY - CGFloat(max(elevation.wallTopYInches - elevation.deckSurfaceYInches, 1)) * tokens.elevationScale
        let wallRect = CGRect(
            x: origin.x + tokens.drawingInset,
            y: wallTopY,
            width: width,
            height: max(deckY - wallTopY, tokens.minimumDetailHeight)
        )

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setFillColor(palette.subtleFill.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.fill(wallRect)
        context.stroke(wallRect)
        drawLine(
            from: CGPoint(x: canvas.pageRect.minX + tokens.drawingInset, y: gradeY),
            to: CGPoint(x: canvas.pageRect.maxX - tokens.drawingInset, y: gradeY),
            context: context,
            tokens: tokens,
            palette: palette
        )
        drawLine(
            from: CGPoint(x: wallRect.minX, y: deckY),
            to: CGPoint(x: wallRect.maxX, y: deckY),
            context: context,
            tokens: tokens,
            palette: palette
        )
        context.restoreGState()

        result.bodyCallouts.append("ELEVATION")
        for opening in elevation.openings {
            result.bodyCallouts.append(opening.calloutTag)
        }
    }

    private static func renderCrossSection(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        var missingPrerequisite = false
        if data.house == nil {
            appendPlaceholder("HOUSE MODEL NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            missingPrerequisite = true
        }
        if data.terrain == nil {
            appendPlaceholder("TERRAIN MODEL NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            missingPrerequisite = true
        }
        if missingPrerequisite {
            return
        }

        let centerX = canvas.pageRect.midX
        let gradeY = canvas.pageRect.maxY - tokens.drawingInset
        let footingRect = CGRect(
            x: centerX - tokens.detailFootingWidth / 2,
            y: gradeY - tokens.detailFootingHeight,
            width: tokens.detailFootingWidth,
            height: tokens.detailFootingHeight
        )
        let postRect = CGRect(
            x: centerX - tokens.detailPostWidth / 2,
            y: footingRect.minY - tokens.detailPostHeight,
            width: tokens.detailPostWidth,
            height: tokens.detailPostHeight
        )
        let beamRect = CGRect(
            x: centerX - tokens.detailBeamWidth / 2,
            y: postRect.minY - tokens.detailBeamHeight,
            width: tokens.detailBeamWidth,
            height: tokens.detailBeamHeight
        )
        let joistRect = CGRect(
            x: centerX - tokens.detailJoistWidth / 2,
            y: beamRect.minY - tokens.detailJoistHeight,
            width: tokens.detailJoistWidth,
            height: tokens.detailJoistHeight
        )

        drawDetailRects([footingRect, postRect, beamRect, joistRect], context: context, tokens: tokens, palette: palette)
        result.bodyCallouts.append(contentsOf: ["FOOTING", "POST", "BEAM", "JOIST", "DECKING", "GUARD"])
    }

    private static func renderSitePlan(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        if let setbacks = data.permitMeta?.setbacks, setbacks.propertyLines.count >= 3 {
            drawPolygon(setbacks.propertyLines, canvas: canvas, context: context, tokens: tokens, palette: palette)
            if setbacks.ahjVerified == false {
                result.bodyCallouts.append("VERIFY SETBACKS WITH AHJ")
                drawWatermark("VERIFY SETBACKS WITH AHJ", canvas: canvas, context: context, tokens: tokens, palette: palette)
            }
            if let requiredSetbackFeet = setbacks.requiredSetbackFeet {
                result.bodyCallouts.append("SETBACK \(DimensionEngine.formatImperial(requiredSetbackFeet * 12))")
            }
        } else {
            appendPlaceholder("SETBACK INPUT NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        }

        let positions = primaryFootprintPositions(data)
        if positions.count >= 3 {
            canvas.hatch(positions, pattern: .diagonal45, in: context)
        }
    }

    private static func renderDetailCallout(
        _ data: DeckDrawingData,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        guard let footing = data.footings?.footings.first else {
            appendPlaceholder("FOOTING DETAIL NOT PROVIDED", canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
            return
        }

        renderCrossSection(data, canvas: canvas, context: context, tokens: tokens, palette: palette, result: &result)
        if let hardware = footing.connection?.hardwareModel, !hardware.isEmpty {
            result.bodyCallouts.append(hardware)
            canvas.drawLeaderCallout(at: footing.position, text: hardware, in: context)
        }
        if let diameter = footing.diameterInches {
            result.bodyCallouts.append("FOOTING DIA \(DimensionEngine.formatImperial(diameter))")
        }
        if let depth = footing.depthInches {
            result.bodyCallouts.append("FOOTING DEPTH \(DimensionEngine.formatImperial(depth))")
        }
    }

    private static func primaryFootprintPositions(_ data: DeckDrawingData) -> [CGPoint] {
        if data.isMultiLevel {
            return data.levels.first?.orderedPositions ?? []
        }
        return data.orderedPositions
    }

    private static func drawPolygon(
        _ positions: [CGPoint],
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        guard let first = positions.first else { return }
        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: canvas.modelToPage(first))
        for position in positions.dropFirst() {
            context.addLine(to: canvas.modelToPage(position))
        }
        context.closePath()
        context.strokePath()
        context.restoreGState()
    }

    private static func drawMember(
        _ member: FramingMember,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        context.saveGState()
        context.setStrokeColor(member.role == .beam ? palette.attentionStroke.cgColor : palette.primaryStroke.cgColor)
        context.setLineWidth(member.role == .beam ? tokens.emphasisLineWidth : tokens.hairlineWidth)
        context.move(to: canvas.modelToPage(member.start))
        context.addLine(to: canvas.modelToPage(member.end))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawWatermark(
        _ text: String,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        PlanSheetText.draw(
            text,
            in: canvas.pageRect.insetBy(dx: tokens.drawingInset, dy: tokens.drawingInset),
            context: context,
            fontName: tokens.headingFontName,
            fontSize: tokens.headingFontSize,
            color: palette.attentionStroke.cgColor,
            alignment: .center
        )
    }

    private static func appendPlaceholder(
        _ text: String,
        canvas: DraftingCanvas,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette,
        result: inout PlanSheetRenderResult
    ) {
        result.placeholders.append(text)
        PlanSheetText.draw(
            text,
            in: canvas.pageRect.insetBy(dx: tokens.drawingInset, dy: tokens.drawingInset),
            context: context,
            fontName: tokens.labelFontName,
            fontSize: tokens.labelFontSize,
            color: palette.secondaryText.cgColor,
            alignment: .center
        )
    }

    private static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func drawDetailRects(
        _ rects: [CGRect],
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setFillColor(palette.subtleFill.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        for rect in rects {
            context.fill(rect)
            context.stroke(rect)
        }
        context.restoreGState()
    }

    private static func calloutTag(for member: FramingMember) -> String {
        switch member.role {
        case .joist: return "J"
        case .beam: return "B"
        case .post: return "P"
        case .ledger: return "L"
        case .rimBand: return "R"
        case .blocking: return "BL"
        case .bridging: return "BR"
        case .cantilever: return "C"
        }
    }

    private static func memberCallout(_ member: FramingMember) -> String {
        var parts = [member.role.rawValue.uppercased()]
        if let nominalSize = member.nominalSize {
            parts.append(nominalSize.rawValue)
        }
        if member.plyCount > 1 {
            parts.append("\(member.plyCount)-PLY")
        }
        if let spacing = member.spacingInchesOC {
            parts.append("@ \(DimensionEngine.formatImperial(spacing)) O.C.")
        }
        return parts.joined(separator: " ")
    }
}

enum TitleBlockRenderer {
    static func draw(
        _ titleBlock: TitleBlock,
        kind: PlanSheetKind,
        in rect: CGRect,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) -> [String] {
        draw(
            titleBlock,
            sheetTitle: kind.sheetTitle,
            in: rect,
            context: context,
            tokens: tokens,
            palette: palette
        )
    }

    static func draw(
        _ titleBlock: TitleBlock,
        sheetTitle: String,
        in rect: CGRect,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) -> [String] {
        let texts = titleBlockTexts(titleBlock, sheetTitle: sheetTitle)

        context.saveGState()
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.stroke(rect)

        var rowY = rect.minY + tokens.titleBlockPadding
        for text in texts {
            let rowRect = CGRect(
                x: rect.minX + tokens.titleBlockPadding,
                y: rowY,
                width: rect.width - tokens.titleBlockPadding * 2,
                height: tokens.titleBlockRowHeight
            )
            PlanSheetText.draw(
                text,
                in: rowRect,
                context: context,
                fontName: tokens.labelFontName,
                fontSize: tokens.labelFontSize,
                color: palette.primaryText.cgColor,
                alignment: .left
            )
            rowY += tokens.titleBlockRowHeight
        }

        if titleBlock.peStamp?.requested == true {
            let stampRect = CGRect(
                x: rect.minX + tokens.titleBlockPadding,
                y: rect.maxY - tokens.peStampBoxHeight - tokens.titleBlockPadding,
                width: rect.width - tokens.titleBlockPadding * 2,
                height: tokens.peStampBoxHeight
            )
            context.stroke(stampRect)
            PlanSheetText.draw(
                "PE STAMP REQUESTED",
                in: stampRect.insetBy(dx: tokens.titleBlockPadding, dy: tokens.titleBlockPadding),
                context: context,
                fontName: tokens.labelFontName,
                fontSize: tokens.labelFontSize,
                color: palette.secondaryText.cgColor,
                alignment: .center
            )
        }
        context.restoreGState()

        return texts
    }

    private static func titleBlockTexts(_ titleBlock: TitleBlock, sheetTitle: String) -> [String] {
        var texts = [
            titleBlock.projectName,
            sheetTitle,
            titleBlock.packageEdition,
            PlanSheetDateFormatter.string(from: titleBlock.generatedDate),
            titleBlock.disclaimer
        ]
        if let address = titleBlock.address, !address.isEmpty {
            texts.insert(address, at: 1)
        }
        if titleBlock.peStamp?.requested == true {
            texts.append("PE STAMP REQUESTED")
        }
        return texts
    }
}

private struct PlanSheetLayout {
    var drawingRect: CGRect
    var titleBlockRect: CGRect

    init(pageRect: CGRect, tokens: PlanSheetTokens) {
        let sheetRect = pageRect.insetBy(dx: tokens.sheetInset, dy: tokens.sheetInset)
        self.titleBlockRect = CGRect(
            x: sheetRect.maxX - tokens.titleBlockWidth,
            y: sheetRect.minY,
            width: tokens.titleBlockWidth,
            height: sheetRect.height
        )
        self.drawingRect = CGRect(
            x: sheetRect.minX + tokens.drawingInset,
            y: sheetRect.minY + tokens.drawingInset,
            width: max(sheetRect.width - tokens.titleBlockWidth - tokens.drawingInset * 3, tokens.minimumDrawingWidth),
            height: max(sheetRect.height - tokens.drawingInset * 2, tokens.minimumDrawingHeight)
        )
    }
}

struct PlanSheetTokens: Equatable {
    var sheetInset: CGFloat
    var drawingInset: CGFloat
    var titleBlockWidth: CGFloat
    var titleBlockPadding: CGFloat
    var titleBlockRowHeight: CGFloat
    var peStampBoxHeight: CGFloat
    var hairlineWidth: CGFloat
    var emphasisLineWidth: CGFloat
    var labelFontName: String
    var headingFontName: String
    var labelFontSize: CGFloat
    var headingFontSize: CGFloat
    var minimumDrawingWidth: CGFloat
    var minimumDrawingHeight: CGFloat
    var minimumDetailHeight: CGFloat
    var elevationScale: CGFloat
    var sectionStackGap: CGFloat
    var detailFootingWidth: CGFloat
    var detailFootingHeight: CGFloat
    var detailPostWidth: CGFloat
    var detailPostHeight: CGFloat
    var detailBeamWidth: CGFloat
    var detailBeamHeight: CGFloat
    var detailJoistWidth: CGFloat
    var detailJoistHeight: CGFloat
    var draftingTokens: DraftingCanvasTokens

    static let permitSheet = PlanSheetTokens(
        sheetInset: OPSStyle.Layout.spacing2,
        drawingInset: OPSStyle.Layout.spacing4,
        titleBlockWidth: OPSStyle.Layout.touchTargetStandard * 4,
        titleBlockPadding: OPSStyle.Layout.spacing1,
        titleBlockRowHeight: OPSStyle.Layout.spacing5,
        peStampBoxHeight: OPSStyle.Layout.touchTargetStandard * 2,
        hairlineWidth: OPSStyle.Layout.Border.standard,
        emphasisLineWidth: OPSStyle.Layout.Border.thick,
        labelFontName: "JetBrainsMono-Regular",
        headingFontName: "CakeMono-Light",
        labelFontSize: OPSStyle.Layout.spacing2_5,
        headingFontSize: OPSStyle.Layout.spacing5,
        minimumDrawingWidth: OPSStyle.Layout.touchTargetStandard,
        minimumDrawingHeight: OPSStyle.Layout.touchTargetStandard,
        minimumDetailHeight: OPSStyle.Layout.spacing2,
        elevationScale: OPSStyle.Layout.spacing1 / 12,
        sectionStackGap: OPSStyle.Layout.touchTargetLarge,
        detailFootingWidth: OPSStyle.Layout.touchTargetLarge,
        detailFootingHeight: OPSStyle.Layout.spacing5,
        detailPostWidth: OPSStyle.Layout.spacing2,
        detailPostHeight: OPSStyle.Layout.touchTargetLarge * 2,
        detailBeamWidth: OPSStyle.Layout.touchTargetLarge * 2,
        detailBeamHeight: OPSStyle.Layout.spacing2,
        detailJoistWidth: OPSStyle.Layout.touchTargetLarge * 3,
        detailJoistHeight: OPSStyle.Layout.spacing1,
        draftingTokens: .permitSheet
    )
}

struct PlanSheetPalette {
    let background: PlanSheetPlatformColor
    let primaryStroke: PlanSheetPlatformColor
    let attentionStroke: PlanSheetPlatformColor
    let primaryText: PlanSheetPlatformColor
    let secondaryText: PlanSheetPlatformColor
    let subtleFill: PlanSheetPlatformColor

    init() {
        self.background = Self.platformColor(from: OPSStyle.Colors.Light.background)
        self.primaryStroke = Self.platformColor(from: OPSStyle.Colors.Light.primaryText)
        self.attentionStroke = Self.platformColor(from: OPSStyle.Colors.tan)
        self.primaryText = Self.platformColor(from: OPSStyle.Colors.Light.primaryText)
        self.secondaryText = Self.platformColor(from: OPSStyle.Colors.Light.secondaryText)
        self.subtleFill = Self.platformColor(from: OPSStyle.Colors.Light.cardBackground)
    }

    private static func platformColor(from color: Color) -> PlanSheetPlatformColor {
        PlanSheetPlatformColor(color)
    }
}

enum PlanSheetText {
    static func draw(
        _ text: String,
        in rect: CGRect,
        context: CGContext,
        fontName: String,
        fontSize: CGFloat,
        color: CGColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: CTFontCreateWithName(fontName as CFString, fontSize, nil),
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

enum PlanSheetDateFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

private extension PlanSheetKind {
    var sheetTitle: String {
        switch self {
        case .planView: return "PLAN VIEW"
        case .framingPlan: return "FRAMING PLAN"
        case .elevation: return "ELEVATION"
        case .crossSection: return "CROSS SECTION"
        case .sitePlan: return "SITE PLAN"
        case .detailCallout: return "DETAIL CALLOUT"
        }
    }
}
