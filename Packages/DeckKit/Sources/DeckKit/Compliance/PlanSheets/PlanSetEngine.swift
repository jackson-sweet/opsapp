import CoreGraphics
import Foundation

public enum PlanSetEngine {
    public static func renderPermitSet(
        _ data: DeckDrawingData,
        compliance: ComplianceReport,
        sheets: [PlanSheetKind],
        titleBlock: TitleBlock,
        package: CodePackage
    ) -> Data {
        let orderedSheets = canonicalSheets(sheets)
        return PDFRenderer.render(pageRect: PlanSetTokens.letterPageRect) { context, pageRect in
            for sheet in orderedSheets {
                context.beginPDFPage(nil)
                PlanSheetRenderer.render(
                    sheet,
                    data: data,
                    titleBlock: titleBlock,
                    scale: PlanSetTokens.defaultScale,
                    pageRect: pageRect,
                    in: context
                )
                stampDisclaimer(titleBlock.disclaimer, pageRect: pageRect, context: context)
                context.endPDFPage()
            }

            context.beginPDFPage(nil)
            renderComplianceSummary(
                compliance,
                titleBlock: titleBlock,
                package: package,
                pageRect: pageRect,
                context: context
            )
            stampDisclaimer(titleBlock.disclaimer, pageRect: pageRect, context: context)
            context.endPDFPage()
        }
    }

    public static func renderSheet(
        _ kind: PlanSheetKind,
        data: DeckDrawingData,
        scale: DrawingScale,
        titleBlock: TitleBlock
    ) -> Data {
        PDFRenderer.render(pageRect: PlanSetTokens.letterPageRect) { context, pageRect in
            context.beginPDFPage(nil)
            PlanSheetRenderer.render(
                kind,
                data: data,
                titleBlock: titleBlock,
                scale: scale,
                pageRect: pageRect,
                in: context
            )
            stampDisclaimer(titleBlock.disclaimer, pageRect: pageRect, context: context)
            context.endPDFPage()
        }
    }

    public static func renderCalcReport(
        _ framing: FramingPlan,
        footings: FootingPlan,
        package: CodePackage
    ) -> Data {
        PDFRenderer.render(pageRect: PlanSetTokens.letterPageRect) { context, pageRect in
            context.beginPDFPage(nil)
            renderCalcReportPage(
                framing,
                footings: footings,
                package: package,
                pageRect: pageRect,
                context: context
            )
            context.endPDFPage()
        }
    }

    private static func canonicalSheets(_ sheets: [PlanSheetKind]) -> [PlanSheetKind] {
        let requested = Set(sheets)
        return PlanSheetKind.allCases.filter { requested.contains($0) }
    }

    private static func renderComplianceSummary(
        _ report: ComplianceReport,
        titleBlock: TitleBlock,
        package: CodePackage,
        pageRect: CGRect,
        context: CGContext
    ) {
        let tokens = PlanSheetTokens.permitSheet
        let palette = PlanSheetPalette()
        let layout = PlanSetPageLayout(pageRect: pageRect, tokens: tokens)

        context.setFillColor(palette.background.cgColor)
        context.fill(pageRect)
        context.setStrokeColor(palette.primaryStroke.cgColor)
        context.setLineWidth(tokens.hairlineWidth)
        context.stroke(pageRect.insetBy(dx: tokens.sheetInset, dy: tokens.sheetInset))

        _ = TitleBlockRenderer.draw(
            titleBlock,
            sheetTitle: "COMPLIANCE SUMMARY",
            in: layout.titleBlockRect,
            context: context,
            tokens: tokens,
            palette: palette
        )

        var lines = [
            "COMPLIANCE SUMMARY",
            report.summaryStatement,
            "PACKAGE \(report.packageEdition)",
            "CODE DATA CURRENT TO \(PlanSheetDateFormatter.string(from: package.publishedDate))",
            report.disclaimer
        ]
        if report.findings.isEmpty {
            lines.append(ComplianceStrings.noFailures)
        } else {
            lines.append(contentsOf: report.findings.flatMap(findingLines))
        }

        drawLines(lines, in: layout.contentRect, context: context, tokens: tokens, palette: palette)
    }

    private static func renderCalcReportPage(
        _ framing: FramingPlan,
        footings: FootingPlan,
        package: CodePackage,
        pageRect: CGRect,
        context: CGContext
    ) {
        let tokens = PlanSheetTokens.permitSheet
        let palette = PlanSheetPalette()
        let contentRect = pageRect.insetBy(dx: tokens.sheetInset + tokens.drawingInset, dy: tokens.sheetInset + tokens.drawingInset)
        let assumptions = framing.loadPreset ?? LoadPreset()
        var lines = [
            "STRUCTURAL CALC REPORT",
            "PACKAGE \(package.edition ?? package.jurisdictionId)",
            "CODE DATA CURRENT TO \(PlanSheetDateFormatter.string(from: package.publishedDate))",
            "LIVE LOAD \(formatNumber(assumptions.liveLoadPSF)) PSF",
            "DEAD LOAD \(formatNumber(assumptions.deadLoadPSF)) PSF",
            "SPECIES \(assumptions.species.rawValue.uppercased())",
            "GRADE \(assumptions.grade.rawValue.uppercased())",
            "SOIL \(formatNumber(footings.soil?.bearingCapacityPSF ?? 0)) PSF",
            "MEMBER TABLE"
        ]

        for member in framing.members.flatMap(\.members) {
            lines.append(memberCalcLine(member))
        }
        lines.append("FOOTING TABLE")
        for footing in footings.footings {
            lines.append(footingCalcLine(footing))
        }
        lines.append(ComplianceStrings.disclaimer)

        context.setFillColor(palette.background.cgColor)
        context.fill(pageRect)
        drawLines(lines, in: contentRect, context: context, tokens: tokens, palette: palette)
    }

    private static func findingLines(_ finding: ComplianceFinding) -> [String] {
        [
            "\(finding.severity.rawValue.uppercased()) · \(finding.item.uppercased())",
            "CURRENT \(finding.currentValue ?? "—") · TARGET \(finding.targetValue ?? "—")",
            "SECTION \(finding.codeSection)",
            finding.fix.map { "FIX \($0)" } ?? "FIX —"
        ]
    }

    private static func memberCalcLine(_ member: FramingMember) -> String {
        var parts = [
            member.role.rawValue.uppercased(),
            member.nominalSize?.rawValue ?? "—",
            "SPAN \(DimensionEngine.formatImperial(Double(PolygonMath.edgeLength(from: member.start, to: member.end))))"
        ]
        if let sizing = member.sizing {
            switch sizing.outcome {
            case let .ok(value, citation, _):
                parts.append("ALLOW \(formatNumber(value.allowableSpanFeet)) FT")
                parts.append("UTILIZATION \(formatNumber(value.utilization * 100))%")
                parts.append(citation.limitingCheck.uppercased())
                parts.append(citation.codeSection)
            case let .outOfEnvelope(reason, citation):
                parts.append("OUT OF ENVELOPE")
                parts.append(reason)
                parts.append(citation.codeSection)
            }
        } else {
            parts.append("NOT ENGINEERED")
        }
        return parts.joined(separator: " · ")
    }

    private static func footingCalcLine(_ footing: Footing) -> String {
        var parts = [
            "FOOTING",
            footing.type.rawValue.uppercased(),
            "DIA \(footing.diameterInches.map(DimensionEngine.formatImperial) ?? "—")",
            "DEPTH \(footing.depthInches.map(DimensionEngine.formatImperial) ?? "—")"
        ]
        if let hardware = footing.connection?.hardwareModel, !hardware.isEmpty {
            parts.append(hardware)
        }
        if footing.connection?.upliftRated == true {
            parts.append("UPLIFT RATED")
        }
        return parts.joined(separator: " · ")
    }

    private static func drawLines(
        _ lines: [String],
        in rect: CGRect,
        context: CGContext,
        tokens: PlanSheetTokens,
        palette: PlanSheetPalette
    ) {
        var y = rect.minY
        for (index, line) in lines.enumerated() {
            let fontName = index == 0 ? tokens.headingFontName : tokens.labelFontName
            let fontSize = index == 0 ? tokens.headingFontSize : tokens.labelFontSize
            let rowHeight = index == 0 ? tokens.titleBlockRowHeight * 2 : tokens.titleBlockRowHeight
            let rowRect = CGRect(
                x: rect.minX,
                y: y,
                width: rect.width,
                height: rowHeight
            )
            PlanSheetText.draw(
                line,
                in: rowRect,
                context: context,
                fontName: fontName,
                fontSize: fontSize,
                color: palette.primaryText.cgColor,
                alignment: .left
            )
            y += rowHeight
            if y > rect.maxY { break }
        }
    }

    private static func stampDisclaimer(
        _ disclaimer: String,
        pageRect: CGRect,
        context: CGContext
    ) {
        let tokens = PlanSheetTokens.permitSheet
        let palette = PlanSheetPalette()
        let rect = CGRect(
            x: pageRect.minX + tokens.sheetInset + tokens.drawingInset,
            y: pageRect.maxY - tokens.sheetInset - tokens.titleBlockRowHeight * 3,
            width: pageRect.width - tokens.sheetInset * 2 - tokens.drawingInset * 2,
            height: tokens.titleBlockRowHeight * 3
        )
        PlanSheetText.draw(
            disclaimer,
            in: rect,
            context: context,
            fontName: tokens.labelFontName,
            fontSize: tokens.labelFontSize,
            color: palette.secondaryText.cgColor,
            alignment: .left
        )
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private enum PDFRenderer {
    static func render(
        pageRect: CGRect,
        body: (CGContext, CGRect) -> Void
    ) -> Data {
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        body(context, pageRect)
        context.closePDF()
        return data as Data
    }
}

private struct PlanSetPageLayout {
    var contentRect: CGRect
    var titleBlockRect: CGRect

    init(pageRect: CGRect, tokens: PlanSheetTokens) {
        let sheetRect = pageRect.insetBy(dx: tokens.sheetInset, dy: tokens.sheetInset)
        self.titleBlockRect = CGRect(
            x: sheetRect.maxX - tokens.titleBlockWidth,
            y: sheetRect.minY,
            width: tokens.titleBlockWidth,
            height: sheetRect.height
        )
        self.contentRect = CGRect(
            x: sheetRect.minX + tokens.drawingInset,
            y: sheetRect.minY + tokens.drawingInset,
            width: sheetRect.width - tokens.titleBlockWidth - tokens.drawingInset * 3,
            height: sheetRect.height - tokens.drawingInset * 2
        )
    }
}

private enum PlanSetTokens {
    static let letterPageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let defaultScale = DrawingScale(inchesPerFoot: 0.25)
}
