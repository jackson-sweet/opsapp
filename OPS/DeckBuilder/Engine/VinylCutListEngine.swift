// OPS/OPS/DeckBuilder/Engine/VinylCutListEngine.swift

import CoreGraphics
import Foundation

enum VinylLayoutDirection: String, CaseIterable, Identifiable {
    case automatic
    case lengthwise
    case widthwise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "AUTO"
        case .lengthwise: return "LENGTH"
        case .widthwise: return "WIDTH"
        }
    }
}

struct VinylOrderSettings: Equatable {
    var color: String
    var catalogItemId: String?
    var catalogVariantId: String?
    var rollWidthInches: Double
    var seamOverlapInches: Double
    var edgeWrapInches: Double
    var direction: VinylLayoutDirection
    var allowsDirectionalChanges: Bool

    init(
        color: String,
        catalogItemId: String? = nil,
        catalogVariantId: String? = nil,
        rollWidthInches: Double,
        seamOverlapInches: Double,
        edgeWrapInches: Double,
        direction: VinylLayoutDirection,
        allowsDirectionalChanges: Bool = false
    ) {
        self.color = color
        self.catalogItemId = catalogItemId
        self.catalogVariantId = catalogVariantId
        self.rollWidthInches = rollWidthInches
        self.seamOverlapInches = seamOverlapInches
        self.edgeWrapInches = edgeWrapInches
        self.direction = direction
        self.allowsDirectionalChanges = allowsDirectionalChanges
    }

    static let `default` = VinylOrderSettings(
        color: "",
        rollWidthInches: 72,
        seamOverlapInches: 1.5,
        edgeWrapInches: 6,
        direction: .automatic,
        allowsDirectionalChanges: false
    )

    var normalized: VinylOrderSettings {
        VinylOrderSettings(
            color: color.trimmingCharacters(in: .whitespacesAndNewlines),
            catalogItemId: normalizedOptionalId(catalogItemId),
            catalogVariantId: normalizedOptionalId(catalogVariantId),
            rollWidthInches: max(1, rollWidthInches),
            seamOverlapInches: max(0, min(seamOverlapInches, max(0, rollWidthInches - 1))),
            edgeWrapInches: max(0, edgeWrapInches),
            direction: direction,
            allowsDirectionalChanges: allowsDirectionalChanges
        )
    }

    private func normalizedOptionalId(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct VinylOrderSurfaceInput: Identifiable, Equatable {
    let id: String
    let label: String
    let levelName: String?
    let positions: [CGPoint]
    let scaleFactor: Double
    var edges: [VinylOrderSurfaceEdge] = []
}

struct VinylOrderSurfaceEdge: Identifiable, Equatable {
    let id: String
    let start: CGPoint
    let end: CGPoint
    let edgeType: EdgeType
    let label: String?
}

struct VinylCutPlan: Equatable {
    let settings: VinylOrderSettings
    let surfaces: [VinylSurfaceCutPlan]
    let reuseNotes: [VinylReuseNote]

    var totalCutAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.cutAreaSqFt }
    }

    var totalReusedCutAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.reusedCutAreaSqFt }
    }

    var totalPurchasedCutAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.purchasedCutAreaSqFt }
    }

    var totalOrderedSqFt: Int {
        Int(ceil(totalPurchasedCutAreaSqFt))
    }

    var totalSurfaceAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.surfaceAreaSqFt }
    }

    var totalWasteSqFt: Double {
        max(0, totalPurchasedCutAreaSqFt - totalSurfaceAreaSqFt)
    }

    var totalStripCount: Int {
        surfaces.reduce(0) { $0 + $1.stripCount }
    }

    var totalPurchasedStripCount: Int {
        surfaces.reduce(0) { $0 + $1.purchasedCuts.count }
    }

    var hasReusableOffcuts: Bool {
        !reuseNotes.isEmpty
    }

    func orderNotes(projectTitle: String, deckTitle: String) -> String {
        var lines: [String] = []
        lines.append("// VINYL ORDER")
        lines.append("PROJECT: \(projectTitle)")
        lines.append("DESIGN: \(deckTitle)")
        lines.append("COLOR: \(settings.color.isEmpty ? "FIELD CONFIRM" : settings.color)")
        lines.append("ROLL: \(vinylFormatInches(settings.rollWidthInches))")
        lines.append("SEAM OVERLAP: \(vinylFormatInches(settings.seamOverlapInches))")
        lines.append("EDGE WRAP: \(vinylFormatInches(settings.edgeWrapInches))")
        lines.append("ORDER AREA: \(totalOrderedSqFt) SQ FT")
        lines.append("SURFACE AREA: \(vinylFormatSqFt(totalSurfaceAreaSqFt)) SQ FT")
        if totalReusedCutAreaSqFt > 0 {
            lines.append("REUSED AREA: \(vinylFormatSqFt(totalReusedCutAreaSqFt)) SQ FT")
        }
        lines.append("CUT WASTE: \(vinylFormatSqFt(totalWasteSqFt)) SQ FT")
        lines.append("")
        lines.append("// CUT LIST")
        for surface in surfaces {
            lines.append(surface.orderLine)
        }
        if reuseNotes.isEmpty {
            lines.append("OFFCUTS: NO FULL-SURFACE REUSE FOUND. KEEP LONG OFFCUTS FOR WRAPS AND PATCHES.")
        } else {
            lines.append("")
            lines.append("// OFFCUT REUSE")
            for note in reuseNotes {
                lines.append(note.line)
            }
        }
        return lines.joined(separator: "\n")
    }

    func textMessageBody(
        messageTemplate: String = VinylCutListTextTemplate.defaultMessageTemplate,
        cutTemplate: String = VinylCutListTextTemplate.defaultCutTemplate,
        cutSeparator: VinylCutListSeparator = .lines
    ) -> String {
        VinylCutListTextTemplate.render(
            messageTemplate: messageTemplate,
            cutTemplate: cutTemplate,
            cutSeparator: cutSeparator,
            plan: self
        )
    }

    func textMessageBody(template: String) -> String {
        textMessageBody(messageTemplate: template)
    }
}

enum VinylCutListSeparator: String, CaseIterable, Identifiable {
    case lines
    case comma

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lines: return "LINES"
        case .comma: return "COMMA"
        }
    }

    var separator: String {
        switch self {
        case .lines: return "\n"
        case .comma: return ", "
        }
    }
}

enum VinylCutListTextTemplate {
    static let messageStorageKey = "deckBuilder.vinylOrder.cutListTemplate"
    static let cutStorageKey = "deckBuilder.vinylOrder.cutTemplate"
    static let separatorStorageKey = "deckBuilder.vinylOrder.cutSeparator"
    static let storageKey = messageStorageKey
    static let defaultMessageTemplate = "Color: [color]\n[cuts]"
    static let defaultCutTemplate = "-[quantity] @ [length]"
    static let defaultTemplate = defaultMessageTemplate

    static func render(
        messageTemplate rawMessageTemplate: String,
        cutTemplate rawCutTemplate: String,
        cutSeparator: VinylCutListSeparator,
        plan: VinylCutPlan
    ) -> String {
        let trimmedMessageTemplate = rawMessageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageTemplate = trimmedMessageTemplate.isEmpty ? defaultMessageTemplate : rawMessageTemplate
        let color = plan.settings.color.isEmpty ? "FIELD CONFIRM" : plan.settings.color
        let cuts = cutLines(for: plan, cutTemplate: rawCutTemplate).joined(separator: cutSeparator.separator)

        return replacingTokens(
            in: messageTemplate,
            replacements: [
                "color": color,
                "cuts": cuts,
                "cut_count": "\(plan.totalPurchasedStripCount)"
            ]
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func render(template rawTemplate: String, plan: VinylCutPlan) -> String {
        render(
            messageTemplate: rawTemplate,
            cutTemplate: defaultCutTemplate,
            cutSeparator: .lines,
            plan: plan
        )
    }

    static func cutLines(for plan: VinylCutPlan, cutTemplate rawCutTemplate: String = defaultCutTemplate) -> [String] {
        let purchased = plan.surfaces.flatMap(\.purchasedCuts)
        guard !purchased.isEmpty else { return ["—"] }
        let trimmedCutTemplate = rawCutTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutTemplate = trimmedCutTemplate.isEmpty ? defaultCutTemplate : rawCutTemplate

        return VinylCutGroup.groups(from: purchased).map { group in
            replacingTokens(
                in: cutTemplate,
                replacements: [
                    "quantity": "\(group.count)",
                    "length": vinylFormatFeetAndInches(group.lengthInches),
                    "surface": group.surfaceLabel.uppercased(),
                    "roll_width": vinylFormatInches(group.rollWidthInches)
                ]
            )
        }
    }

    private static func replacingTokens(in template: String, replacements: [String: String]) -> String {
        var rendered = template
        for (key, value) in replacements {
            let titleKey = key
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")

            [
                "[\(key)]",
                "[\(key.uppercased())]",
                "[\(titleKey)]",
                "{{\(key)}}",
                "{{\(key.uppercased())}}"
            ].forEach { token in
                rendered = rendered.replacingOccurrences(of: token, with: value)
            }
        }
        return rendered
    }
}

enum VinylRunAxis: String, Equatable {
    case horizontal
    case vertical
}

struct VinylCutPiece: Identifiable, Equatable {
    let id: String
    let surfaceId: String
    let surfaceLabel: String
    let levelName: String?
    let runAxis: VinylRunAxis
    let lengthInches: Double
    let rollWidthInches: Double
    let requiredWidthInches: Double
    let bandStartInches: Double
    let bandEndInches: Double
    let runStartInches: Double
    let runEndInches: Double
    let isPurchased: Bool
    let sourceSurfaceId: String?
    let sourceSurfaceLabel: String?

    var displayLabel: String {
        if let levelName, !levelName.isEmpty {
            return "\(levelName) / \(surfaceLabel)"
        }
        return surfaceLabel
    }

    var fullRollAreaSqFt: Double {
        (lengthInches * rollWidthInches) / 144.0
    }

    func assignedFrom(
        surfaceId: String,
        surfaceLabel: String
    ) -> VinylCutPiece {
        VinylCutPiece(
            id: id,
            surfaceId: self.surfaceId,
            surfaceLabel: self.surfaceLabel,
            levelName: levelName,
            runAxis: runAxis,
            lengthInches: lengthInches,
            rollWidthInches: rollWidthInches,
            requiredWidthInches: requiredWidthInches,
            bandStartInches: bandStartInches,
            bandEndInches: bandEndInches,
            runStartInches: runStartInches,
            runEndInches: runEndInches,
            isPurchased: false,
            sourceSurfaceId: surfaceId,
            sourceSurfaceLabel: surfaceLabel
        )
    }
}

struct VinylCutGroup: Identifiable, Equatable {
    let surfaceLabel: String
    let count: Int
    let lengthInches: Double
    let rollWidthInches: Double
    let runAxis: VinylRunAxis
    let isPurchased: Bool
    let sourceSurfaceLabel: String?

    var id: String {
        [
            surfaceLabel,
            "\(count)",
            "\(lengthInches)",
            "\(rollWidthInches)",
            isPurchased ? "purchased" : "offcut",
            sourceSurfaceLabel ?? ""
        ].joined(separator: "|")
    }

    var orderFragment: String {
        "\(count) CUT\(count == 1 ? "" : "S") @ \(vinylFormatFeetAndInches(lengthInches))"
    }

    var textLine: String {
        "\(surfaceLabel.uppercased()): \(count) @ \(vinylFormatFeetAndInches(lengthInches))"
    }

    var displayLine: String {
        if isPurchased {
            return orderFragment
        }
        return "\(orderFragment) FROM \(sourceSurfaceLabel?.uppercased() ?? "OFFCUT")"
    }

    static func groups(from cuts: [VinylCutPiece]) -> [VinylCutGroup] {
        var grouped: [VinylCutGroup] = []
        for cut in cuts {
            let sourceLabel = cut.sourceSurfaceLabel
            if let index = grouped.firstIndex(where: {
                $0.surfaceLabel == cut.displayLabel &&
                abs($0.lengthInches - cut.lengthInches) < 0.01 &&
                abs($0.rollWidthInches - cut.rollWidthInches) < 0.01 &&
                $0.isPurchased == cut.isPurchased &&
                $0.sourceSurfaceLabel == sourceLabel
            }) {
                let old = grouped[index]
                grouped[index] = VinylCutGroup(
                    surfaceLabel: old.surfaceLabel,
                    count: old.count + 1,
                    lengthInches: old.lengthInches,
                    rollWidthInches: old.rollWidthInches,
                    runAxis: old.runAxis,
                    isPurchased: old.isPurchased,
                    sourceSurfaceLabel: old.sourceSurfaceLabel
                )
            } else {
                grouped.append(VinylCutGroup(
                    surfaceLabel: cut.displayLabel,
                    count: 1,
                    lengthInches: cut.lengthInches,
                    rollWidthInches: cut.rollWidthInches,
                    runAxis: cut.runAxis,
                    isPurchased: cut.isPurchased,
                    sourceSurfaceLabel: sourceLabel
                ))
            }
        }
        return grouped
    }
}

struct VinylSurfaceCutPlan: Identifiable, Equatable {

    let id: String
    let label: String
    let levelName: String?
    let positions: [CGPoint]
    let boundingWidthInches: Double
    let boundingHeightInches: Double
    let surfaceAreaSqFt: Double
    let perimeterFeet: Double
    let resolvedDirection: VinylLayoutDirection
    let runAxis: VinylRunAxis
    let stripCount: Int
    let stripLengthInches: Double
    let rollWidthInches: Double
    let targetCrossInches: Double
    let coverageCrossInches: Double
    let offcutWidthInches: Double
    let cutAreaSqFt: Double
    let cuts: [VinylCutPiece]
    let edges: [VinylOrderSurfaceEdge]

    var displayLabel: String {
        if let levelName, !levelName.isEmpty {
            return "\(levelName) / \(label)"
        }
        return label
    }

    var hasMixedRunAxes: Bool {
        Set(cuts.map(\.runAxis)).count > 1
    }

    var purchasedCuts: [VinylCutPiece] {
        cuts.filter(\.isPurchased)
    }

    var reusedCuts: [VinylCutPiece] {
        cuts.filter { !$0.isPurchased }
    }

    var purchasedCutAreaSqFt: Double {
        purchasedCuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
    }

    var reusedCutAreaSqFt: Double {
        reusedCuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
    }

    var orderLine: String {
        let fragments = VinylCutGroup.groups(from: cuts).map(\.displayLine).joined(separator: "; ")
        return "\(displayLabel.uppercased()): \(fragments)"
    }
}

struct VinylReuseNote: Equatable {
    let sourceSurfaceId: String
    let sourceSurfaceLabel: String
    let targetSurfaceId: String
    let targetSurfaceLabel: String
    let offcutWidthInches: Double
    let offcutLengthInches: Double

    var line: String {
        "\(targetSurfaceLabel.uppercased()) CAN FIT FROM \(sourceSurfaceLabel.uppercased()) OFFCUT: \(vinylFormatInches(offcutWidthInches)) X \(vinylFormatInches(offcutLengthInches))."
    }
}

enum VinylCutListEngine {
    private struct SurfaceCandidate {
        let surface: VinylOrderSurfaceInput
        let width: Double
        let height: Double
        let areaSqIn: Double
        let perimeterIn: Double
        let resolvedDirection: VinylLayoutDirection
        let runAxis: VinylRunAxis
        let targetCross: Double
        let coverageCross: Double
        let cuts: [VinylCutPiece]

        var cutAreaSqFt: Double {
            cuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
        }

        var stripCount: Int { cuts.count }
    }

    private struct OffcutLane {
        let sourceSurfaceId: String
        let sourceSurfaceLabel: String
        var width: Double
        let length: Double
    }

    static func makePlan(
        surfaces: [VinylOrderSurfaceInput],
        settings rawSettings: VinylOrderSettings
    ) -> VinylCutPlan {
        let settings = rawSettings.normalized
        let candidates = surfaces.compactMap { surface in
            candidate(surface, settings: settings)
        }
        let packedCuts = assignOffcuts(candidates.flatMap(\.cuts))
        let cutsBySurface = Dictionary(grouping: packedCuts, by: \.surfaceId)
        let plans = candidates.map { candidate in
            surfacePlan(from: candidate, cuts: cutsBySurface[candidate.surface.id] ?? [])
        }
        return VinylCutPlan(
            settings: settings,
            surfaces: plans,
            reuseNotes: reuseNotes(for: plans)
        )
    }

    private static func candidate(
        _ surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings
    ) -> SurfaceCandidate? {
        guard surface.positions.count >= 3, surface.scaleFactor > 0 else { return nil }

        let width = span(surface.positions.map(\.x)) / surface.scaleFactor
        let height = span(surface.positions.map(\.y)) / surface.scaleFactor
        guard width > 0, height > 0 else { return nil }

        let areaSqIn = PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: surface.scaleFactor)
        let perimeterIn = PolygonMath.perimeter(vertices: surface.positions) / surface.scaleFactor

        let lengthwise = axisCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            direction: .lengthwise
        )
        let widthwise = axisCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            direction: .widthwise
        )

        let sameDirection: SurfaceCandidate
        switch settings.direction {
        case .automatic:
            if lengthwise.cutAreaSqFt == widthwise.cutAreaSqFt {
                sameDirection = lengthwise.stripCount <= widthwise.stripCount ? lengthwise : widthwise
            } else {
                sameDirection = lengthwise.cutAreaSqFt < widthwise.cutAreaSqFt ? lengthwise : widthwise
            }
        case .lengthwise:
            sameDirection = lengthwise
        case .widthwise:
            sameDirection = widthwise
        }

        guard settings.direction == .automatic,
              settings.allowsDirectionalChanges,
              let mixed = mixedAxisCandidate(
                surface: surface,
                settings: settings,
                width: width,
                height: height,
                areaSqIn: areaSqIn,
                perimeterIn: perimeterIn
              ) else {
            return sameDirection
        }

        if mixed.cutAreaSqFt == sameDirection.cutAreaSqFt {
            return mixed.stripCount < sameDirection.stripCount ? mixed : sameDirection
        }
        return mixed.cutAreaSqFt < sameDirection.cutAreaSqFt ? mixed : sameDirection
    }

    private static func axisCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double,
        direction: VinylLayoutDirection
    ) -> SurfaceCandidate {
        let axis: VinylRunAxis
        switch direction {
        case .automatic:
            preconditionFailure("Resolve automatic before building a vinyl cut candidate.")
        case .lengthwise:
            axis = width >= height ? .horizontal : .vertical
        case .widthwise:
            axis = width < height ? .horizontal : .vertical
        }

        let cuts = cutsForPolygon(surface: surface, settings: settings, axis: axis, idPrefix: direction.rawValue)
        let targetCross = crossSpan(for: surface.positions, scaleFactor: surface.scaleFactor, axis: axis) + (settings.edgeWrapInches * 2)

        return SurfaceCandidate(
            surface: surface,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            resolvedDirection: direction,
            runAxis: axis,
            targetCross: targetCross,
            coverageCross: coverageCross(stripCount: cuts.count, settings: settings),
            cuts: cuts
        )
    }

    private static func mixedAxisCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double
    ) -> SurfaceCandidate? {
        let rectangles = rectilinearRectangles(for: surface.positions, scaleFactor: surface.scaleFactor)
        guard rectangles.count > 1 else { return nil }

        var cuts: [VinylCutPiece] = []
        for (index, rect) in rectangles.enumerated() {
            let rectSurface = VinylOrderSurfaceInput(
                id: surface.id,
                label: surface.label,
                levelName: surface.levelName,
                positions: [
                    CGPoint(x: rect.minX * surface.scaleFactor, y: rect.minY * surface.scaleFactor),
                    CGPoint(x: rect.maxX * surface.scaleFactor, y: rect.minY * surface.scaleFactor),
                    CGPoint(x: rect.maxX * surface.scaleFactor, y: rect.maxY * surface.scaleFactor),
                    CGPoint(x: rect.minX * surface.scaleFactor, y: rect.maxY * surface.scaleFactor)
                ],
                scaleFactor: surface.scaleFactor
            )
            let horizontal = cutsForPolygon(surface: rectSurface, settings: settings, axis: .horizontal, idPrefix: "mixed-\(index)-h")
            let vertical = cutsForPolygon(surface: rectSurface, settings: settings, axis: .vertical, idPrefix: "mixed-\(index)-v")
            let horizontalArea = horizontal.reduce(0) { $0 + $1.fullRollAreaSqFt }
            let verticalArea = vertical.reduce(0) { $0 + $1.fullRollAreaSqFt }
            cuts.append(contentsOf: horizontalArea <= verticalArea ? horizontal : vertical)
        }

        guard Set(cuts.map(\.runAxis)).count > 1 else { return nil }

        return SurfaceCandidate(
            surface: surface,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            resolvedDirection: .automatic,
            runAxis: cuts.first?.runAxis ?? .horizontal,
            targetCross: max(width, height) + (settings.edgeWrapInches * 2),
            coverageCross: coverageCross(stripCount: cuts.count, settings: settings),
            cuts: cuts
        )
    }

    private static func surfacePlan(from candidate: SurfaceCandidate, cuts: [VinylCutPiece]) -> VinylSurfaceCutPlan {
        VinylSurfaceCutPlan(
            id: candidate.surface.id,
            label: candidate.surface.label,
            levelName: candidate.surface.levelName,
            positions: candidate.surface.positions,
            boundingWidthInches: candidate.width,
            boundingHeightInches: candidate.height,
            surfaceAreaSqFt: candidate.areaSqIn / 144.0,
            perimeterFeet: candidate.perimeterIn / 12.0,
            resolvedDirection: candidate.resolvedDirection,
            runAxis: candidate.runAxis,
            stripCount: cuts.count,
            stripLengthInches: cuts.map(\.lengthInches).max() ?? 0,
            rollWidthInches: cuts.first?.rollWidthInches ?? 0,
            targetCrossInches: candidate.targetCross,
            coverageCrossInches: candidate.coverageCross,
            offcutWidthInches: cuts.map { max(0, $0.rollWidthInches - $0.requiredWidthInches) }.max() ?? 0,
            cutAreaSqFt: cuts.reduce(0) { $0 + $1.fullRollAreaSqFt },
            cuts: cuts,
            edges: candidate.surface.edges
        )
    }

    private static func reuseNotes(for plans: [VinylSurfaceCutPlan]) -> [VinylReuseNote] {
        plans.flatMap(\.reusedCuts).map { cut in
            VinylReuseNote(
                sourceSurfaceId: cut.sourceSurfaceId ?? "",
                sourceSurfaceLabel: cut.sourceSurfaceLabel ?? "OFFCUT",
                targetSurfaceId: cut.surfaceId,
                targetSurfaceLabel: cut.displayLabel,
                offcutWidthInches: cut.requiredWidthInches,
                offcutLengthInches: cut.lengthInches
            )
        }
    }

    private static func assignOffcuts(_ cuts: [VinylCutPiece]) -> [VinylCutPiece] {
        var offcuts: [OffcutLane] = []
        var assignedById: [String: VinylCutPiece] = [:]
        let ordered = cuts.sorted {
            if abs($0.fullRollAreaSqFt - $1.fullRollAreaSqFt) > 0.01 {
                return $0.fullRollAreaSqFt > $1.fullRollAreaSqFt
            }
            if abs($0.lengthInches - $1.lengthInches) > 0.01 {
                return $0.lengthInches > $1.lengthInches
            }
            return $0.id < $1.id
        }

        for cut in ordered {
            if let index = offcuts.firstIndex(where: {
                $0.width + 0.01 >= cut.requiredWidthInches &&
                $0.length + 0.01 >= cut.lengthInches
            }) {
                let source = offcuts[index]
                assignedById[cut.id] = cut.assignedFrom(surfaceId: source.sourceSurfaceId, surfaceLabel: source.sourceSurfaceLabel)
                offcuts[index].width -= cut.requiredWidthInches
                if offcuts[index].width < 6 {
                    offcuts.remove(at: index)
                }
            } else {
                assignedById[cut.id] = cut
                let leftoverWidth = cut.rollWidthInches - cut.requiredWidthInches
                if leftoverWidth >= 6 {
                    offcuts.append(OffcutLane(
                        sourceSurfaceId: cut.surfaceId,
                        sourceSurfaceLabel: cut.displayLabel,
                        width: leftoverWidth,
                        length: cut.lengthInches
                    ))
                }
            }
        }

        return cuts.compactMap { assignedById[$0.id] }
    }

    private static func cutsForPolygon(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        axis: VinylRunAxis,
        idPrefix: String
    ) -> [VinylCutPiece] {
        let polygon = surface.positions.map {
            CGPoint(x: Double($0.x) / surface.scaleFactor, y: Double($0.y) / surface.scaleFactor)
        }
        guard let bounds = bounds(for: polygon) else { return [] }

        let crossMin = (axis == .horizontal ? bounds.minY : bounds.minX) - settings.edgeWrapInches
        let crossMax = (axis == .horizontal ? bounds.maxY : bounds.maxX) + settings.edgeWrapInches
        let effectiveCoverage = max(1, settings.rollWidthInches - settings.seamOverlapInches)
        let step = min(1.0, effectiveCoverage)
        var best: [VinylCutPiece] = []
        var bestArea = Double.infinity
        var offset = 0.0

        while offset < effectiveCoverage {
            let cuts = cutsForOffset(
                polygon: polygon,
                surface: surface,
                settings: settings,
                axis: axis,
                idPrefix: idPrefix,
                crossMin: crossMin,
                crossMax: crossMax,
                offset: offset
            )
            let area = cuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
            if !cuts.isEmpty,
               area < bestArea || (abs(area - bestArea) < 0.01 && cuts.count < best.count) {
                best = cuts
                bestArea = area
            }
            offset += step
        }

        if best.isEmpty {
            return cutsForOffset(
                polygon: polygon,
                surface: surface,
                settings: settings,
                axis: axis,
                idPrefix: idPrefix,
                crossMin: crossMin,
                crossMax: crossMax,
                offset: 0
            )
        }
        return best
    }

    private static func cutsForOffset(
        polygon: [CGPoint],
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        axis: VinylRunAxis,
        idPrefix: String,
        crossMin: Double,
        crossMax: Double,
        offset: Double
    ) -> [VinylCutPiece] {
        let effectiveCoverage = max(1, settings.rollWidthInches - settings.seamOverlapInches)
        var cuts: [VinylCutPiece] = []
        var bandStart = crossMin - offset
        var index = 0
        while bandStart < crossMax - 0.01 {
            let bandEnd = bandStart + settings.rollWidthInches
            if let run = runSpanInBand(polygon: polygon, bandMin: bandStart, bandMax: bandEnd, axis: axis) {
                let runStart = run.min - settings.edgeWrapInches
                let runEnd = run.max + settings.edgeWrapInches
                let length = max(1, runEnd - runStart)
                let requiredWidth = max(1, min(settings.rollWidthInches, min(bandEnd, crossMax) - max(bandStart, crossMin)))
                cuts.append(VinylCutPiece(
                    id: "\(surface.id)-\(idPrefix)-\(index)-\(vinylFormatInches(length))-\(vinylFormatInches(requiredWidth))",
                    surfaceId: surface.id,
                    surfaceLabel: surface.label,
                    levelName: surface.levelName,
                    runAxis: axis,
                    lengthInches: length,
                    rollWidthInches: settings.rollWidthInches,
                    requiredWidthInches: requiredWidth,
                    bandStartInches: max(bandStart, crossMin),
                    bandEndInches: min(bandEnd, crossMax),
                    runStartInches: runStart,
                    runEndInches: runEnd,
                    isPurchased: true,
                    sourceSurfaceId: nil,
                    sourceSurfaceLabel: nil
                ))
            }
            bandStart += effectiveCoverage
            index += 1
        }
        return cuts
    }

    private static func runSpanInBand(
        polygon: [CGPoint],
        bandMin: Double,
        bandMax: Double,
        axis: VinylRunAxis
    ) -> (min: Double, max: Double)? {
        let epsilon = 0.001
        var samples: [Double] = [
            bandMin + epsilon,
            (bandMin + bandMax) / 2,
            bandMax - epsilon
        ]
        for point in polygon {
            let cross = axis == .horizontal ? Double(point.y) : Double(point.x)
            if cross > bandMin + epsilon && cross < bandMax - epsilon {
                samples.append(cross)
                samples.append(max(bandMin + epsilon, cross - epsilon))
                samples.append(min(bandMax - epsilon, cross + epsilon))
            }
        }

        var minRun = Double.infinity
        var maxRun = -Double.infinity
        for sample in samples where sample > bandMin && sample < bandMax {
            for interval in scanIntervals(polygon: polygon, cross: sample, axis: axis) {
                minRun = min(minRun, interval.min)
                maxRun = max(maxRun, interval.max)
            }
        }

        guard minRun.isFinite, maxRun.isFinite, maxRun > minRun else { return nil }
        return (minRun, maxRun)
    }

    private static func scanIntervals(
        polygon: [CGPoint],
        cross: Double,
        axis: VinylRunAxis
    ) -> [(min: Double, max: Double)] {
        guard polygon.count >= 3 else { return [] }
        var intersections: [Double] = []
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let aCross = axis == .horizontal ? Double(a.y) : Double(a.x)
            let bCross = axis == .horizontal ? Double(b.y) : Double(b.x)
            guard (aCross <= cross && bCross > cross) || (bCross <= cross && aCross > cross) else {
                continue
            }
            let ratio = (cross - aCross) / (bCross - aCross)
            let aRun = axis == .horizontal ? Double(a.x) : Double(a.y)
            let bRun = axis == .horizontal ? Double(b.x) : Double(b.y)
            intersections.append(aRun + ((bRun - aRun) * ratio))
        }

        let sorted = intersections.sorted()
        var intervals: [(min: Double, max: Double)] = []
        var index = 0
        while index + 1 < sorted.count {
            if sorted[index + 1] > sorted[index] {
                intervals.append((sorted[index], sorted[index + 1]))
            }
            index += 2
        }
        return intervals
    }

    private static func rectilinearRectangles(for positions: [CGPoint], scaleFactor: Double) -> [CGRect] {
        guard positions.count >= 4, scaleFactor > 0 else { return [] }
        let polygon = positions.map {
            CGPoint(x: Double($0.x) / scaleFactor, y: Double($0.y) / scaleFactor)
        }
        let xs = Array(Set(polygon.map { Double($0.x) })).sorted()
        let ys = Array(Set(polygon.map { Double($0.y) })).sorted()
        guard xs.count >= 2, ys.count >= 2 else { return [] }

        var filled = Array(
            repeating: Array(repeating: false, count: ys.count - 1),
            count: xs.count - 1
        )
        for xIndex in 0..<(xs.count - 1) {
            for yIndex in 0..<(ys.count - 1) {
                let center = CGPoint(x: (xs[xIndex] + xs[xIndex + 1]) / 2, y: (ys[yIndex] + ys[yIndex + 1]) / 2)
                filled[xIndex][yIndex] = PolygonMath.pointInPolygon(center, vertices: polygon)
            }
        }

        var rectangles: [CGRect] = []
        while let best = largestFilledRectangle(filled: filled, xs: xs, ys: ys) {
            rectangles.append(best.rect)
            for x in best.xRange {
                for y in best.yRange {
                    filled[x][y] = false
                }
            }
        }
        return rectangles
    }

    private static func largestFilledRectangle(
        filled: [[Bool]],
        xs: [Double],
        ys: [Double]
    ) -> (rect: CGRect, xRange: Range<Int>, yRange: Range<Int>)? {
        var best: (rect: CGRect, xRange: Range<Int>, yRange: Range<Int>, area: Double)?
        for xStart in filled.indices {
            for yStart in filled[xStart].indices where filled[xStart][yStart] {
                for xEnd in (xStart + 1)...filled.count {
                    for yEnd in (yStart + 1)...filled[xStart].count {
                        let xRange = xStart..<xEnd
                        let yRange = yStart..<yEnd
                        guard xRange.allSatisfy({ x in yRange.allSatisfy { filled[x][$0] } }) else { continue }
                        let rect = CGRect(
                            x: xs[xStart],
                            y: ys[yStart],
                            width: xs[xEnd] - xs[xStart],
                            height: ys[yEnd] - ys[yStart]
                        )
                        let area = Double(rect.width * rect.height)
                        if area > (best?.area ?? -1) {
                            best = (rect, xRange, yRange, area)
                        }
                    }
                }
            }
        }
        guard let best else { return nil }
        return (best.rect, best.xRange, best.yRange)
    }

    private static func coverageCross(stripCount: Int, settings: VinylOrderSettings) -> Double {
        guard stripCount > 0 else { return 0 }
        return (Double(stripCount) * settings.rollWidthInches) -
            (Double(max(0, stripCount - 1)) * settings.seamOverlapInches)
    }

    private static func crossSpan(for positions: [CGPoint], scaleFactor: Double, axis: VinylRunAxis) -> Double {
        let values = positions.map { axis == .horizontal ? $0.y : $0.x }
        return span(values) / scaleFactor
    }

    private static func bounds(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = Double(first.x)
        var maxX = Double(first.x)
        var minY = Double(first.y)
        var maxY = Double(first.y)
        for point in points.dropFirst() {
            minX = min(minX, Double(point.x))
            maxX = max(maxX, Double(point.x))
            minY = min(minY, Double(point.y))
            maxY = max(maxY, Double(point.y))
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func span(_ values: [CGFloat]) -> Double {
        guard let min = values.min(), let max = values.max() else { return 0 }
        return Double(max - min)
    }
}

private func vinylFormatInches(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return "\(Int(rounded))\""
    }
    return String(format: "%.1f\"", rounded)
}

func vinylFormatFeetAndInches(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    let feet = Int(rounded / 12)
    let inches = rounded - Double(feet * 12)
    let wholeInches = inches.rounded()
    let inchText: String

    if abs(inches - wholeInches) < 0.001 {
        inchText = "\(Int(wholeInches))"
    } else {
        inchText = String(format: "%.1f", inches)
    }

    if feet > 0, abs(inches) < 0.001 {
        return "\(feet)'"
    }

    if feet > 0 {
        return "\(feet)' \(inchText)\""
    }

    return "\(inchText)\""
}

private func vinylFormatSqFt(_ value: Double) -> String {
    String(format: "%.1f", value)
}

struct VinylCatalogCandidate: Equatable {
    let itemId: String
    let variantId: String
    let itemName: String
    let itemDescription: String?
    let itemNotes: String?
    let variantSku: String?
    let itemUnitId: String?
    let variantUnitId: String?
    let isItemActive: Bool
    let itemDeleted: Bool
    let isVariantActive: Bool
    let variantDeleted: Bool
}

enum VinylCatalogMatcher {
    static func bestMatch(
        from candidates: [VinylCatalogCandidate],
        preferredRollWidthInches: Double
    ) -> VinylCatalogCandidate? {
        candidates
            .compactMap { candidate -> (candidate: VinylCatalogCandidate, score: Int)? in
                guard candidate.isItemActive,
                      !candidate.itemDeleted,
                      candidate.isVariantActive,
                      !candidate.variantDeleted else { return nil }

                let searchable = searchText(for: candidate)
                guard searchable.contains("vinyl"),
                      containsMembraneMaterialTerm(searchable),
                      !searchable.contains("diverter") else { return nil }

                return (candidate, score(for: searchable, preferredRollWidthInches: preferredRollWidthInches))
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                let lhsName = $0.candidate.itemName.localizedStandardCompare($1.candidate.itemName)
                if lhsName != .orderedSame { return lhsName == .orderedAscending }
                let lhsSku = ($0.candidate.variantSku ?? "").localizedStandardCompare($1.candidate.variantSku ?? "")
                if lhsSku != .orderedSame { return lhsSku == .orderedAscending }
                return $0.candidate.variantId < $1.candidate.variantId
            }
            .first?
            .candidate
    }

    private static func searchText(for candidate: VinylCatalogCandidate) -> String {
        [
            candidate.itemName,
            candidate.itemDescription,
            candidate.itemNotes,
            candidate.variantSku,
            candidate.itemUnitId,
            candidate.variantUnitId
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    private static func containsMembraneMaterialTerm(_ searchable: String) -> Bool {
        searchable.contains("membrane") ||
        searchable.contains("deck") ||
        searchable.contains("roll") ||
        searchable.contains("sheet")
    }

    private static func score(for searchable: String, preferredRollWidthInches: Double) -> Int {
        var score = 0
        if searchable.contains("membrane") { score += 40 }
        if searchable.contains("sheet") || searchable.contains("roll") { score += 20 }
        if searchable.contains("deck") { score += 10 }
        if contains(width: preferredRollWidthInches, in: searchable) { score += 8 }
        return score
    }

    private static func contains(width: Double, in searchable: String) -> Bool {
        let rounded = Int(width.rounded())
        let tokens = [
            "\(rounded)",
            "\(rounded)\"",
            "\(rounded) in",
            "\(rounded)-in",
            "\(rounded)in"
        ]
        return tokens.contains { searchable.contains($0) }
    }
}
