// OPS/OPS/DeckBuilder/Rendering/DeckShareRenderer.swift

import UIKit
import Foundation

struct DeckShareRenderer {

    // MARK: - Brand Colors (UIKit equivalents of OPSStyle tokens)

    private static let accentColor = UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 1)    // #597794
    private static let darkText = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)
    private static let mediumText = UIColor(red: 100/255, green: 100/255, blue: 100/255, alpha: 1)
    private static let lightBorder = UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1)
    private static let fillColor = UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 0.08)
    private static let headerBg = UIColor(red: 89/255, green: 119/255, blue: 148/255, alpha: 1)

    // MARK: - Share Image (1080 x 1920 PNG)

    /// Render a branded share image with deck drawing, dimensions, and optional material summary
    static func renderShareImage(
        drawingData: DeckDrawingData,
        title: String,
        clientName: String?
    ) -> UIImage? {
        let size = CGSize(width: 1080, height: 1920)
        let renderer = UIGraphicsImageRenderer(size: size)

        let lineItems = EstimateGeneratorService.generateLineItems(from: drawingData)

        return renderer.image { ctx in
            let gc = ctx.cgContext

            // White background
            gc.setFillColor(UIColor.white.cgColor)
            gc.fill(CGRect(origin: .zero, size: size))

            // Title bar
            let titleBarHeight: CGFloat = 140
            gc.setFillColor(headerBg.cgColor)
            gc.fill(CGRect(x: 0, y: 0, width: size.width, height: titleBarHeight))

            drawText(
                title.uppercased(),
                at: CGPoint(x: 54, y: 40),
                font: .systemFont(ofSize: 36, weight: .bold),
                color: .white,
                maxWidth: size.width - 108
            )

            if let client = clientName, !client.isEmpty {
                drawText(
                    client,
                    at: CGPoint(x: 54, y: 88),
                    font: .systemFont(ofSize: 24, weight: .medium),
                    color: UIColor.white.withAlphaComponent(0.8),
                    maxWidth: size.width - 108
                )
            }

            // Deck drawing area
            let drawingTop: CGFloat = titleBarHeight + 40
            let drawingHeight: CGFloat = lineItems.isEmpty ? size.height - titleBarHeight - 200 : 900
            let drawingRect = CGRect(x: 54, y: drawingTop, width: size.width - 108, height: drawingHeight)

            renderDeckDrawing(
                drawingData: drawingData,
                in: drawingRect,
                context: gc
            )

            // Material summary table (if items exist)
            if !lineItems.isEmpty {
                let tableTop = drawingTop + drawingHeight + 30
                let tableRect = CGRect(x: 54, y: tableTop, width: size.width - 108, height: size.height - tableTop - 160)
                renderMaterialTable(lineItems: lineItems, in: tableRect, context: gc)
            }

            // Area + perimeter summary line
            let summaryY = size.height - 140
            var summaryParts: [String] = []
            let areaSqFt = EstimateGeneratorService.calculateAreaSqFt(drawingData: drawingData)
            if areaSqFt > 0 {
                summaryParts.append("\(Int(areaSqFt.rounded())) sq ft")
            }
            let perimeterFt = EstimateGeneratorService.calculatePerimeterFt(drawingData: drawingData)
            if perimeterFt > 0 {
                summaryParts.append("\(Int(perimeterFt.rounded())) lin ft perimeter")
            }
            if !summaryParts.isEmpty {
                drawText(
                    summaryParts.joined(separator: "  \u{2022}  "),
                    at: CGPoint(x: 54, y: summaryY),
                    font: .systemFont(ofSize: 22, weight: .medium),
                    color: mediumText,
                    maxWidth: size.width - 200
                )
            }

            // OPS watermark (bottom-right)
            drawText(
                "OPS",
                at: CGPoint(x: size.width - 150, y: size.height - 70),
                font: .systemFont(ofSize: 28, weight: .heavy),
                color: accentColor.withAlphaComponent(0.3),
                maxWidth: 120
            )
        }
    }

    // MARK: - PDF Export

    /// Render a multi-page PDF with dimensioned drawing and material table
    /// - Returns: PDF data, or nil if rendering fails
    static func renderPDF(
        drawingData: DeckDrawingData,
        title: String,
        clientName: String?,
        companyName: String?
    ) -> Data? {
        let letterSize = CGRect(x: 0, y: 0, width: 792, height: 612) // landscape letter
        let portraitSize = CGRect(x: 0, y: 0, width: 612, height: 792)  // portrait letter

        let lineItems = EstimateGeneratorService.generateLineItems(from: drawingData)
        let dateStr = formatDate(Date())
        let company = companyName ?? "OPS"

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: letterSize)

        let data = pdfRenderer.pdfData { pdfCtx in
            // Page 1: Landscape deck drawing
            pdfCtx.beginPage(withBounds: letterSize, pageInfo: [:])
            let gc = pdfCtx.cgContext

            // Header
            drawText(
                title.uppercased(),
                at: CGPoint(x: 36, y: 24),
                font: .systemFont(ofSize: 16, weight: .bold),
                color: darkText,
                maxWidth: letterSize.width - 200
            )
            drawText(
                "\(company)  \u{2022}  \(dateStr)",
                at: CGPoint(x: 36, y: 46),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: mediumText,
                maxWidth: letterSize.width - 200
            )
            if let client = clientName, !client.isEmpty {
                drawText(
                    "Client: \(client)",
                    at: CGPoint(x: letterSize.width - 250, y: 24),
                    font: .systemFont(ofSize: 11, weight: .medium),
                    color: mediumText,
                    maxWidth: 220
                )
            }

            // Separator
            gc.setStrokeColor(lightBorder.cgColor)
            gc.setLineWidth(0.5)
            gc.move(to: CGPoint(x: 36, y: 66))
            gc.addLine(to: CGPoint(x: letterSize.width - 36, y: 66))
            gc.strokePath()

            // Drawing area
            let drawingRect = CGRect(x: 54, y: 80, width: letterSize.width - 108, height: letterSize.height - 140)
            renderDeckDrawing(drawingData: drawingData, in: drawingRect, context: gc)

            // Footer
            drawText(
                "Generated by OPS \u{2014} \(company)",
                at: CGPoint(x: 36, y: letterSize.height - 30),
                font: .systemFont(ofSize: 8, weight: .regular),
                color: mediumText,
                maxWidth: 300
            )

            // Page 2: Material table (portrait, only if items exist)
            if !lineItems.isEmpty {
                pdfCtx.beginPage(withBounds: portraitSize, pageInfo: [:])

                // Header
                drawText(
                    "Material List",
                    at: CGPoint(x: 36, y: 24),
                    font: .systemFont(ofSize: 16, weight: .bold),
                    color: darkText,
                    maxWidth: 300
                )
                drawText(
                    "\(title)  \u{2022}  \(dateStr)",
                    at: CGPoint(x: 36, y: 46),
                    font: .systemFont(ofSize: 10, weight: .medium),
                    color: mediumText,
                    maxWidth: portraitSize.width - 72
                )

                // Separator
                let gc2 = pdfCtx.cgContext
                gc2.setStrokeColor(lightBorder.cgColor)
                gc2.setLineWidth(0.5)
                gc2.move(to: CGPoint(x: 36, y: 66))
                gc2.addLine(to: CGPoint(x: portraitSize.width - 36, y: 66))
                gc2.strokePath()

                // Table
                let tableRect = CGRect(x: 36, y: 80, width: portraitSize.width - 72, height: portraitSize.height - 140)
                renderPDFMaterialTable(lineItems: lineItems, in: tableRect, context: gc2)

                // Footer
                drawText(
                    "Generated by OPS \u{2014} \(company)",
                    at: CGPoint(x: 36, y: portraitSize.height - 30),
                    font: .systemFont(ofSize: 8, weight: .regular),
                    color: mediumText,
                    maxWidth: 300
                )
            }
        }

        return data
    }

    // MARK: - Shared Drawing Renderer

    private static func renderDeckDrawing(
        drawingData: DeckDrawingData,
        in rect: CGRect,
        context gc: CGContext
    ) {
        let positions = drawingData.orderedPositions
        guard !positions.isEmpty else { return }

        let bounds = boundingRect(for: positions)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scaleX = rect.width / bounds.width
        let scaleY = rect.height / bounds.height
        let fitScale = min(scaleX, scaleY) * 0.85 // 85% fill for breathing room

        let drawingWidth = bounds.width * fitScale
        let drawingHeight = bounds.height * fitScale
        let offsetX = rect.origin.x + (rect.width - drawingWidth) / 2 - bounds.origin.x * fitScale
        let offsetY = rect.origin.y + (rect.height - drawingHeight) / 2 - bounds.origin.y * fitScale

        func transform(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * fitScale + offsetX, y: point.y * fitScale + offsetY)
        }

        // Footprint fill
        if drawingData.isClosed && positions.count >= 3 {
            gc.setFillColor(fillColor.cgColor)
            gc.beginPath()
            gc.move(to: transform(positions[0]))
            for i in 1..<positions.count {
                gc.addLine(to: transform(positions[i]))
            }
            gc.closePath()
            gc.fillPath()
        }

        // Edges
        for edge in drawingData.edges {
            guard let start = drawingData.vertex(byId: edge.startVertexId),
                  let end = drawingData.vertex(byId: edge.endVertexId) else { continue }
            let p1 = transform(start.position)
            let p2 = transform(end.position)

            // Railing indicator (thicker colored line underneath)
            if edge.railingConfig != nil {
                gc.setStrokeColor(accentColor.withAlphaComponent(0.4).cgColor)
                gc.setLineWidth(6.0)
                gc.beginPath()
                gc.move(to: p1)
                gc.addLine(to: p2)
                gc.strokePath()
            }

            // Stair indicator (dashed line)
            if edge.stairConfig != nil {
                gc.setStrokeColor(UIColor(red: 180/255, green: 130/255, blue: 80/255, alpha: 0.5).cgColor)
                gc.setLineWidth(4.0)
                gc.setLineDash(phase: 0, lengths: [6, 4])
                gc.beginPath()
                gc.move(to: p1)
                gc.addLine(to: p2)
                gc.strokePath()
                gc.setLineDash(phase: 0, lengths: [])
            }

            // Main edge line
            gc.setStrokeColor(darkText.cgColor)
            gc.setLineWidth(2.0)
            gc.beginPath()
            gc.move(to: p1)
            gc.addLine(to: p2)
            gc.strokePath()

            // Dimension label
            if let dim = edge.dimension {
                let midX = (p1.x + p2.x) / 2
                let midY = (p1.y + p2.y) / 2
                let label = DimensionEngine.format(dim, system: drawingData.config.measurementSystem)
                let fontSize: CGFloat = rect.width > 600 ? 18 : 11
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: accentColor
                ]
                let nsLabel = label as NSString
                let labelSize = nsLabel.size(withAttributes: attrs)

                // White background pill behind label
                let pillRect = CGRect(
                    x: midX - labelSize.width / 2 - 4,
                    y: midY - labelSize.height - 6,
                    width: labelSize.width + 8,
                    height: labelSize.height + 4
                )
                gc.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                gc.fill(pillRect)

                nsLabel.draw(
                    at: CGPoint(x: midX - labelSize.width / 2, y: midY - labelSize.height - 4),
                    withAttributes: attrs
                )
            }
        }

        // Vertices
        gc.setFillColor(accentColor.cgColor)
        for vertex in drawingData.vertices {
            let p = transform(vertex.position)
            let dotSize: CGFloat = rect.width > 600 ? 10 : 6
            gc.fillEllipse(in: CGRect(x: p.x - dotSize / 2, y: p.y - dotSize / 2, width: dotSize, height: dotSize))
        }

        // Area label in center
        if drawingData.isClosed {
            let areaSqFt = EstimateGeneratorService.calculateAreaSqFt(drawingData: drawingData)
            if areaSqFt > 0 {
                let centerX = positions.map { transform($0).x }.reduce(0, +) / CGFloat(positions.count)
                let centerY = positions.map { transform($0).y }.reduce(0, +) / CGFloat(positions.count)
                let areaLabel = "\(Int(areaSqFt.rounded())) sq ft"
                let fontSize: CGFloat = rect.width > 600 ? 24 : 14
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: accentColor.withAlphaComponent(0.6)
                ]
                let nsLabel = areaLabel as NSString
                let labelSize = nsLabel.size(withAttributes: attrs)
                nsLabel.draw(
                    at: CGPoint(x: centerX - labelSize.width / 2, y: centerY - labelSize.height / 2),
                    withAttributes: attrs
                )
            }
        }
    }

    // MARK: - Material Table (Share Image)

    private static func renderMaterialTable(
        lineItems: [EstimateGeneratorService.GeneratedLineItem],
        in rect: CGRect,
        context gc: CGContext
    ) {
        let grouped = Dictionary(grouping: lineItems, by: { $0.category })
        let categoryOrder = ["Surface", "Substructure", "Railing", "Stairs", "Other"]

        var y = rect.origin.y
        let rowHeight: CGFloat = 44
        let categoryHeaderHeight: CGFloat = 36

        for category in categoryOrder {
            guard let items = grouped[category], !items.isEmpty else { continue }
            guard y + categoryHeaderHeight < rect.maxY else { break }

            // Category header
            drawText(
                category.uppercased(),
                at: CGPoint(x: rect.origin.x, y: y + 8),
                font: .systemFont(ofSize: 16, weight: .bold),
                color: accentColor,
                maxWidth: rect.width
            )
            y += categoryHeaderHeight

            // Separator under header
            gc.setStrokeColor(lightBorder.cgColor)
            gc.setLineWidth(0.5)
            gc.move(to: CGPoint(x: rect.origin.x, y: y))
            gc.addLine(to: CGPoint(x: rect.maxX, y: y))
            gc.strokePath()

            for item in items {
                guard y + rowHeight < rect.maxY else { break }

                // Item name
                drawText(
                    item.name,
                    at: CGPoint(x: rect.origin.x + 8, y: y + 10),
                    font: .systemFont(ofSize: 20, weight: .medium),
                    color: darkText,
                    maxWidth: rect.width * 0.6
                )

                // Quantity + unit (right-aligned)
                let qty = item.quantity == item.quantity.rounded() ? "\(Int(item.quantity))" : String(format: "%.1f", item.quantity)
                let qtyText = "\(qty) \(item.unit)"
                let qtyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                    .foregroundColor: mediumText
                ]
                let qtySize = (qtyText as NSString).size(withAttributes: qtyAttrs)
                (qtyText as NSString).draw(
                    at: CGPoint(x: rect.maxX - qtySize.width, y: y + 10),
                    withAttributes: qtyAttrs
                )

                y += rowHeight
            }
        }
    }

    // MARK: - Material Table (PDF, more compact)

    private static func renderPDFMaterialTable(
        lineItems: [EstimateGeneratorService.GeneratedLineItem],
        in rect: CGRect,
        context gc: CGContext
    ) {
        let grouped = Dictionary(grouping: lineItems, by: { $0.category })
        let categoryOrder = ["Surface", "Substructure", "Railing", "Stairs", "Other"]

        // Table header
        var y = rect.origin.y
        let colItem: CGFloat = rect.origin.x
        let colQty: CGFloat = rect.origin.x + rect.width * 0.65
        let colUnit: CGFloat = rect.origin.x + rect.width * 0.82

        let headerFont = UIFont.systemFont(ofSize: 9, weight: .bold)
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: mediumText]
        ("ITEM" as NSString).draw(at: CGPoint(x: colItem, y: y), withAttributes: headerAttrs)
        ("QTY" as NSString).draw(at: CGPoint(x: colQty, y: y), withAttributes: headerAttrs)
        ("UNIT" as NSString).draw(at: CGPoint(x: colUnit, y: y), withAttributes: headerAttrs)
        y += 16

        gc.setStrokeColor(lightBorder.cgColor)
        gc.setLineWidth(0.5)
        gc.move(to: CGPoint(x: rect.origin.x, y: y))
        gc.addLine(to: CGPoint(x: rect.maxX, y: y))
        gc.strokePath()
        y += 6

        let rowFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let rowBoldFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let rowHeight: CGFloat = 18
        let categoryGap: CGFloat = 10

        for category in categoryOrder {
            guard let items = grouped[category], !items.isEmpty else { continue }
            guard y + rowHeight < rect.maxY else { break }

            // Category label
            let catAttrs: [NSAttributedString.Key: Any] = [.font: rowBoldFont, .foregroundColor: accentColor]
            (category.uppercased() as NSString).draw(at: CGPoint(x: colItem, y: y), withAttributes: catAttrs)
            y += rowHeight

            for item in items {
                guard y + rowHeight < rect.maxY else { break }

                let itemAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: darkText]
                let qtyAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: mediumText]

                (item.name as NSString).draw(at: CGPoint(x: colItem + 8, y: y), withAttributes: itemAttrs)

                let qty = item.quantity == item.quantity.rounded() ? "\(Int(item.quantity))" : String(format: "%.1f", item.quantity)
                (qty as NSString).draw(at: CGPoint(x: colQty, y: y), withAttributes: qtyAttrs)
                (item.unit as NSString).draw(at: CGPoint(x: colUnit, y: y), withAttributes: qtyAttrs)

                y += rowHeight
            }

            y += categoryGap
        }

        // Summary line
        y += 6
        gc.move(to: CGPoint(x: rect.origin.x, y: y))
        gc.addLine(to: CGPoint(x: rect.maxX, y: y))
        gc.strokePath()
        y += 8

        let totalItems = lineItems.count
        let summaryAttrs: [NSAttributedString.Key: Any] = [.font: rowBoldFont, .foregroundColor: darkText]
        ("\(totalItems) line items" as NSString).draw(at: CGPoint(x: colItem, y: y), withAttributes: summaryAttrs)
    }

    // MARK: - Helpers

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor,
        maxWidth: CGFloat
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let constrainedSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let rect = (text as NSString).boundingRect(
            with: constrainedSize,
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        )
        (text as NSString).draw(in: CGRect(origin: point, size: rect.size), withAttributes: attrs)
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
