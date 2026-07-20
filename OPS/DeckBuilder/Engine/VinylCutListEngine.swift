// OPS/OPS/DeckBuilder/Engine/VinylCutListEngine.swift

import CoreGraphics
import Foundation

enum VinylLayoutDirection: String, Codable, CaseIterable, Identifiable {
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

enum VinylPatternMode: String, Codable, CaseIterable, Identifiable {
    case solid
    case linear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "SOLID"
        case .linear: return "LINEAR"
        }
    }
}

struct VinylOrderSettings: Equatable, Codable {
    var color: String
    var catalogItemId: String?
    var catalogVariantId: String?
    var rollWidthInches: Double
    var seamOverlapInches: Double
    var edgeWrapInches: Double
    var direction: VinylLayoutDirection
    var patternMode: VinylPatternMode
    var allowsDirectionalChanges: Bool
    /// Minimum leftover width (inches) for a remnant to be worth banking as an
    /// offcut. Below this it is treated as scrap and neither reused nor banked.
    var offcutMinWidthInches: Double

    enum CodingKeys: String, CodingKey {
        case color
        case catalogItemId
        case catalogVariantId
        case rollWidthInches
        case seamOverlapInches
        case edgeWrapInches
        case direction
        case patternMode
        case allowsDirectionalChanges
        case offcutMinWidthInches
    }

    init(
        color: String,
        catalogItemId: String? = nil,
        catalogVariantId: String? = nil,
        rollWidthInches: Double,
        seamOverlapInches: Double,
        edgeWrapInches: Double,
        direction: VinylLayoutDirection,
        patternMode: VinylPatternMode = .solid,
        allowsDirectionalChanges: Bool = false,
        offcutMinWidthInches: Double = 6
    ) {
        self.color = color
        self.catalogItemId = catalogItemId
        self.catalogVariantId = catalogVariantId
        self.rollWidthInches = rollWidthInches
        self.seamOverlapInches = seamOverlapInches
        self.edgeWrapInches = edgeWrapInches
        self.direction = direction
        self.patternMode = patternMode
        self.allowsDirectionalChanges = allowsDirectionalChanges
        self.offcutMinWidthInches = offcutMinWidthInches
    }

    /// Custom decode so partial / legacy JSON round-trips with `.default`'s
    /// values instead of throwing on a missing key (DeckGeometry house style).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        self.catalogItemId = try c.decodeIfPresent(String.self, forKey: .catalogItemId)
        self.catalogVariantId = try c.decodeIfPresent(String.self, forKey: .catalogVariantId)
        self.rollWidthInches = try c.decodeIfPresent(Double.self, forKey: .rollWidthInches) ?? 72
        self.seamOverlapInches = try c.decodeIfPresent(Double.self, forKey: .seamOverlapInches) ?? 1.5
        self.edgeWrapInches = try c.decodeIfPresent(Double.self, forKey: .edgeWrapInches) ?? 6
        self.direction = try c.decodeIfPresent(VinylLayoutDirection.self, forKey: .direction) ?? .automatic
        let rawPatternMode = try c.decodeIfPresent(String.self, forKey: .patternMode)
        self.patternMode = rawPatternMode.flatMap(VinylPatternMode.init(rawValue:)) ?? .solid
        self.allowsDirectionalChanges = try c.decodeIfPresent(Bool.self, forKey: .allowsDirectionalChanges) ?? false
        self.offcutMinWidthInches = try c.decodeIfPresent(Double.self, forKey: .offcutMinWidthInches) ?? 6
    }

    static let `default` = VinylOrderSettings(
        color: "",
        rollWidthInches: 72,
        seamOverlapInches: 1.5,
        edgeWrapInches: 6,
        direction: .automatic,
        patternMode: .solid,
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
            patternMode: patternMode,
            allowsDirectionalChanges: allowsDirectionalChanges,
            offcutMinWidthInches: max(0, offcutMinWidthInches)
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
    /// Boundary vertex ids for this segment (face order). Used by
    /// `DeckMaterialsEngine`'s interior-seam test — a pair shared by two faces is
    /// an interior seam and gets no flashing. Nil ⇒ never treated as interior
    /// (preview fallback edges carry no vertex identity).
    let startVertexId: String?
    let endVertexId: String?
    /// True when the matched deck edge carries a parapet-wall railing — parapet
    /// edges get 90° flash like a house edge.
    let isParapet: Bool
    /// The matched deck edge's real-world dimension (inches) when > 0, else nil.
    /// `DeckMaterialsEngine` falls back to canvas length ÷ scale when nil.
    let dimensionInches: Double?

    init(
        id: String,
        start: CGPoint,
        end: CGPoint,
        edgeType: EdgeType,
        label: String?,
        startVertexId: String? = nil,
        endVertexId: String? = nil,
        isParapet: Bool = false,
        dimensionInches: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.edgeType = edgeType
        self.label = label
        self.startVertexId = startVertexId
        self.endVertexId = endVertexId
        self.isParapet = isParapet
        self.dimensionInches = dimensionInches
    }
}

/// A remnant the cut plan produces — leftover roll width × the strip length —
/// worth banking as a reusable offcut. Surfaced so the operator can commit it to
/// stock after cutting.
struct VinylProducedOffcut: Identifiable, Equatable {
    let id: String
    let sourceSurfaceLabel: String
    let widthInches: Double
    let lengthInches: Double

    var areaSqFt: Double { (widthInches * lengthInches) / 144.0 }
}

/// A banked offcut already on hand, fed into the planner so reuse spans jobs —
/// the plan prefers a matching banked offcut over purchasing new material.
struct VinylOnHandOffcut: Identifiable, Equatable {
    let id: String
    let label: String
    let widthInches: Double
    let lengthInches: Double
}

struct VinylDirectionRegion: Identifiable, Equatable {
    let id: String
    let polygon: [CGPoint]
    let runAngleDegrees: Double
}

struct VinylSeamSegment: Equatable {
    let start: CGPoint
    let end: CGPoint
}

struct VinylDirectionTransition: Identifiable, Equatable {
    let id: String
    let houseEdgeId: String
    let segments: [VinylSeamSegment]
    let firstRegionId: String
    let secondRegionId: String
}

enum VinylPlanIssue: Equatable {
    case mixedRunMissingHouseAlignedTransition(surfaceId: String)
}

struct VinylCutPlan: Equatable {
    static let wallAlignedTransitionBlocker = "NO HOUSE-WALL SPLIT · LOCK RUN OR MARK WALL"

    let settings: VinylOrderSettings
    let surfaces: [VinylSurfaceCutPlan]
    let reuseNotes: [VinylReuseNote]
    /// New remnants this plan yields (excludes banked offcuts that were merely
    /// reused). Empty unless the cut produces a width ≥ `offcutMinWidthInches`.
    let producedOffcuts: [VinylProducedOffcut]
    let issues: [VinylPlanIssue]

    var isOrderable: Bool {
        issues.isEmpty
    }

    var blockingMessage: String? {
        isOrderable ? nil : Self.wallAlignedTransitionBlocker
    }

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

    var runDirectionSummary: String {
        let summaries = surfaces.map(\.runDirectionSummary)
        guard let first = summaries.first else { return "—" }
        return summaries.allSatisfy { $0 == first } ? first : "MIXED"
    }

    /// `rolls` (e.g. "3 ROLLS @ 75'") is appended as a ROLLS line when the order
    /// is placed in full-roll mode; nil/empty leaves the note cut-list-identical.
    func orderNotes(projectTitle: String, deckTitle: String, rolls: String? = nil) -> String {
        guard isOrderable else { return "" }
        var lines: [String] = []
        lines.append("// VINYL ORDER")
        lines.append("PROJECT: \(projectTitle)")
        lines.append("DESIGN: \(deckTitle)")
        lines.append("COLOR: \(settings.color.isEmpty ? "FIELD CONFIRM" : settings.color)")
        lines.append("ROLL: \(vinylFormatInches(settings.rollWidthInches))")
        lines.append("SEAM OVERLAP: \(vinylFormatInches(settings.seamOverlapInches))")
        lines.append("EDGE WRAP: \(vinylFormatInches(settings.edgeWrapInches))")
        lines.append("RUN: \(runDirectionSummary)")
        if let rolls, !rolls.isEmpty {
            lines.append("ROLLS: \(rolls)")
        }
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
        cutSeparator: VinylCutListSeparator = .lines,
        projectTitle: String = "",
        rolls: String = ""
    ) -> String {
        VinylCutListTextTemplate.render(
            messageTemplate: messageTemplate,
            cutTemplate: cutTemplate,
            cutSeparator: cutSeparator,
            projectTitle: projectTitle,
            plan: self,
            rolls: rolls
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
        projectTitle: String = "",
        plan: VinylCutPlan,
        rolls: String = ""
    ) -> String {
        guard plan.isOrderable else { return "" }
        let trimmedMessageTemplate = rawMessageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageTemplate = trimmedMessageTemplate.isEmpty ? defaultMessageTemplate : rawMessageTemplate
        let color = plan.settings.color.isEmpty ? "FIELD CONFIRM" : plan.settings.color
        let cuts = cutLines(for: plan, cutTemplate: rawCutTemplate).joined(separator: cutSeparator.separator)

        return replacingTokens(
            in: messageTemplate,
            replacements: [
                "color": color,
                "cuts": cuts,
                "cut_count": "\(plan.totalPurchasedStripCount)",
                "project": projectTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                // Full-roll summary (e.g. "3 ROLLS @ 75'"); empty in cut-list mode
                // so a [rolls] token in a custom template quietly disappears.
                "rolls": rolls
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
        guard plan.isOrderable else { return [] }
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
                    "roll_width": vinylFormatInches(group.rollWidthInches),
                    "run": group.runDirectionSummary
                ]
            )
        }
    }

    /// Internal (not private): the bulk-order composer reuses the exact same
    /// token conventions for its per-job section template.
    static func replacingTokens(in template: String, replacements: [String: String]) -> String {
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
    let runAngleDegrees: Double
    let runDirectionLabel: String
    let lengthInches: Double
    let rollWidthInches: Double
    let requiredWidthInches: Double
    let bandStartInches: Double
    let bandEndInches: Double
    let runStartInches: Double
    let runEndInches: Double
    let directionRegionId: String?
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
            runAngleDegrees: runAngleDegrees,
            runDirectionLabel: runDirectionLabel,
            lengthInches: lengthInches,
            rollWidthInches: rollWidthInches,
            requiredWidthInches: requiredWidthInches,
            bandStartInches: bandStartInches,
            bandEndInches: bandEndInches,
            runStartInches: runStartInches,
            runEndInches: runEndInches,
            directionRegionId: directionRegionId,
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
    let runAngleDegrees: Double
    let runDirectionLabel: String
    let isPurchased: Bool
    let sourceSurfaceLabel: String?

    var id: String {
        [
            surfaceLabel,
            "\(count)",
            "\(lengthInches)",
            "\(rollWidthInches)",
            "\(runAngleDegrees.rounded())",
            runDirectionLabel,
            isPurchased ? "purchased" : "offcut",
            sourceSurfaceLabel ?? ""
        ].joined(separator: "|")
    }

    var runDirectionSummary: String {
        vinylRunDirectionSummary(label: runDirectionLabel, angleDegrees: runAngleDegrees)
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
                abs($0.runAngleDegrees - cut.runAngleDegrees) < 0.1 &&
                $0.runDirectionLabel == cut.runDirectionLabel &&
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
                    runAngleDegrees: old.runAngleDegrees,
                    runDirectionLabel: old.runDirectionLabel,
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
                    runAngleDegrees: cut.runAngleDegrees,
                    runDirectionLabel: cut.runDirectionLabel,
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
    let scaleFactor: Double
    let boundingWidthInches: Double
    let boundingHeightInches: Double
    let surfaceAreaSqFt: Double
    let perimeterFeet: Double
    let resolvedDirection: VinylLayoutDirection
    let runAxis: VinylRunAxis
    let runAngleDegrees: Double
    let runDirectionLabel: String
    let stripCount: Int
    let stripLengthInches: Double
    let rollWidthInches: Double
    let targetCrossInches: Double
    let coverageCrossInches: Double
    let offcutWidthInches: Double
    let cutAreaSqFt: Double
    let cuts: [VinylCutPiece]
    let edges: [VinylOrderSurfaceEdge]
    let directionRegions: [VinylDirectionRegion]
    let directionTransitions: [VinylDirectionTransition]

    var displayLabel: String {
        if let levelName, !levelName.isEmpty {
            return "\(levelName) / \(label)"
        }
        return label
    }

    var hasMixedRunAxes: Bool {
        Set(cuts.map { Int($0.runAngleDegrees.rounded()) }).count > 1
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

    var runDirectionSummary: String {
        vinylRunDirectionSummary(label: runDirectionLabel, angleDegrees: runAngleDegrees)
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
    private struct VinylRunDirection: Equatable {
        let angleDegrees: Double
        let label: String

        init(angleDegrees: Double, label: String) {
            self.angleDegrees = VinylCutListEngine.normalizedAngle(angleDegrees)
            self.label = label
        }

        var runAxis: VinylRunAxis {
            abs(angleDegrees - 90) < 0.1 ? .vertical : .horizontal
        }

        private var radians: Double {
            angleDegrees * .pi / 180
        }

        func project(_ point: CGPoint) -> CGPoint {
            let cosValue = cos(radians)
            let sinValue = sin(radians)
            let x = Double(point.x)
            let y = Double(point.y)
            return CGPoint(
                x: (x * cosValue) + (y * sinValue),
                y: (-x * sinValue) + (y * cosValue)
            )
        }
    }

    private struct EdgeDirectionSample {
        let angleDegrees: Double
        let weight: Double
        let label: String
    }

    /// A direction-transition boundary projected into one candidate's run/cross
    /// coordinate space. Exterior edge wrap belongs only outside the original
    /// deck polygon; this boundary identifies the split edge that must stay
    /// unwrapped while each region is cut independently.
    private struct ProjectedNoWrapBoundary {
        private enum RunBoundary {
            case minimum
            case maximum
        }

        private struct Segment {
            let start: CGPoint
            let end: CGPoint
        }

        private let segments: [Segment]
        private let runBoundary: RunBoundary?
        let excludesCrossMinimum: Bool
        let excludesCrossMaximum: Bool

        init?(
            polygon: [CGPoint],
            seamSegments: [VinylSeamSegment],
            scaleFactor: Double,
            direction: VinylRunDirection
        ) {
            guard !polygon.isEmpty, !seamSegments.isEmpty, scaleFactor > 0 else { return nil }

            let projectedSegments = seamSegments.map { segment in
                Segment(
                    start: direction.project(CGPoint(
                        x: Double(segment.start.x) / scaleFactor,
                        y: Double(segment.start.y) / scaleFactor
                    )),
                    end: direction.project(CGPoint(
                        x: Double(segment.end.x) / scaleFactor,
                        y: Double(segment.end.y) / scaleFactor
                    ))
                )
            }
            guard let reference = projectedSegments.first else { return nil }

            let projectedPolygon = polygon.map {
                direction.project(CGPoint(
                    x: Double($0.x) / scaleFactor,
                    y: Double($0.y) / scaleFactor
                ))
            }
            let centroid = CGPoint(
                x: projectedPolygon.map(\.x).reduce(0, +) / CGFloat(projectedPolygon.count),
                y: projectedPolygon.map(\.y).reduce(0, +) / CGFloat(projectedPolygon.count)
            )
            let deltaRun = Double(reference.end.x - reference.start.x)
            let deltaCross = Double(reference.end.y - reference.start.y)
            let epsilon = 0.001

            self.segments = projectedSegments
            if abs(deltaCross) <= epsilon {
                let seamCross = Double(reference.start.y)
                self.runBoundary = nil
                self.excludesCrossMinimum = Double(centroid.y) > seamCross
                self.excludesCrossMaximum = Double(centroid.y) < seamCross
            } else {
                let lineRunAtCentroid = Double(reference.start.x)
                    + ((Double(centroid.y - reference.start.y) / deltaCross) * deltaRun)
                self.runBoundary = Double(centroid.x) > lineRunAtCentroid ? .minimum : .maximum
                self.excludesCrossMinimum = false
                self.excludesCrossMaximum = false
            }
        }

        func wrapsRunMinimum(rawRun: Double, bandMinimum: Double, bandMaximum: Double) -> Bool {
            guard runBoundary == .minimum,
                  let seamRange = seamRunRange(bandMinimum: bandMinimum, bandMaximum: bandMaximum) else {
                return true
            }
            return abs(rawRun - seamRange.minimum) > 0.05
        }

        func wrapsRunMaximum(rawRun: Double, bandMinimum: Double, bandMaximum: Double) -> Bool {
            guard runBoundary == .maximum,
                  let seamRange = seamRunRange(bandMinimum: bandMinimum, bandMaximum: bandMaximum) else {
                return true
            }
            return abs(rawRun - seamRange.maximum) > 0.05
        }

        private func seamRunRange(
            bandMinimum: Double,
            bandMaximum: Double
        ) -> (minimum: Double, maximum: Double)? {
            var runs: [Double] = []
            for segment in segments {
                let startCross = Double(segment.start.y)
                let endCross = Double(segment.end.y)
                let lowCross = max(min(startCross, endCross), bandMinimum)
                let highCross = min(max(startCross, endCross), bandMaximum)
                guard highCross >= lowCross - 0.001 else { continue }

                let deltaCross = endCross - startCross
                if abs(deltaCross) <= 0.001 {
                    guard startCross >= bandMinimum - 0.001,
                          startCross <= bandMaximum + 0.001 else { continue }
                    runs.append(Double(segment.start.x))
                    runs.append(Double(segment.end.x))
                    continue
                }

                let deltaRun = Double(segment.end.x - segment.start.x)
                for cross in [lowCross, highCross] {
                    let ratio = (cross - startCross) / deltaCross
                    runs.append(Double(segment.start.x) + (deltaRun * ratio))
                }
            }
            guard let minimum = runs.min(), let maximum = runs.max() else { return nil }
            return (minimum, maximum)
        }
    }

    private struct DirectionCluster {
        var samples: [EdgeDirectionSample]

        var totalWeight: Double {
            samples.reduce(0) { $0 + $1.weight }
        }

        var meanAngleDegrees: Double {
            VinylCutListEngine.axialMeanAngle(samples.map { ($0.angleDegrees, $0.weight) })
        }

        var label: String {
            samples.contains { $0.label == "HOUSE EDGE" } ? "HOUSE EDGE" : "LONG EDGE"
        }
    }

    private struct SurfaceCandidate {
        let surface: VinylOrderSurfaceInput
        let width: Double
        let height: Double
        let areaSqIn: Double
        let perimeterIn: Double
        let resolvedDirection: VinylLayoutDirection
        let runAxis: VinylRunAxis
        let runAngleDegrees: Double
        let runDirectionLabel: String
        let targetCross: Double
        let coverageCross: Double
        let cuts: [VinylCutPiece]
        let directionRegions: [VinylDirectionRegion]
        let directionTransitions: [VinylDirectionTransition]
        let issues: [VinylPlanIssue]

        var cutAreaSqFt: Double {
            cuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
        }

        var stripCount: Int { cuts.count }

        func adding(issue: VinylPlanIssue) -> SurfaceCandidate {
            SurfaceCandidate(
                surface: surface,
                width: width,
                height: height,
                areaSqIn: areaSqIn,
                perimeterIn: perimeterIn,
                resolvedDirection: resolvedDirection,
                runAxis: runAxis,
                runAngleDegrees: runAngleDegrees,
                runDirectionLabel: runDirectionLabel,
                targetCross: targetCross,
                coverageCross: coverageCross,
                cuts: cuts,
                directionRegions: directionRegions,
                directionTransitions: directionTransitions,
                issues: issues + [issue]
            )
        }
    }

    private struct RegionDirectionChoice {
        let direction: VinylRunDirection
        let cuts: [VinylCutPiece]

        var cutAreaSqFt: Double {
            cuts.reduce(0) { $0 + $1.fullRollAreaSqFt }
        }
    }

    private struct OffcutLane {
        let id: String
        let sourceSurfaceId: String
        let sourceSurfaceLabel: String
        var width: Double
        let length: Double
        /// Seeded from a banked stock offcut — reused for planning but not
        /// re-banked as a new remnant.
        let isOnHand: Bool
    }

    static func makePlan(
        surfaces: [VinylOrderSurfaceInput],
        settings rawSettings: VinylOrderSettings,
        availableOffcuts: [VinylOnHandOffcut] = []
    ) -> VinylCutPlan {
        let settings = rawSettings.normalized
        let preferredVisualDirection = settings.direction == .automatic && settings.patternMode == .linear
            ? preferredVisualRunDirection(for: surfaces)
            : nil
        let candidates = surfaces.compactMap { surface in
            candidate(surface, settings: settings, preferredVisualDirection: preferredVisualDirection)
        }
        let (packedCuts, producedOffcuts) = assignOffcuts(
            candidates.flatMap(\.cuts),
            settings: settings,
            availableOffcuts: availableOffcuts
        )
        let cutsBySurface = Dictionary(grouping: packedCuts, by: \.surfaceId)
        let plans = candidates.map { candidate in
            surfacePlan(from: candidate, cuts: cutsBySurface[candidate.surface.id] ?? [])
        }
        return VinylCutPlan(
            settings: settings,
            surfaces: plans,
            reuseNotes: reuseNotes(for: plans),
            producedOffcuts: producedOffcuts,
            issues: candidates.flatMap(\.issues)
        )
    }

    private static func candidate(
        _ surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        preferredVisualDirection: VinylRunDirection?
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
            direction: .lengthwise,
            runDirectionLabel: settings.direction == .automatic ? "MIN WASTE" : "LENGTH"
        )
        let widthwise = axisCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            direction: .widthwise,
            runDirectionLabel: settings.direction == .automatic ? "MIN WASTE" : "WIDTH"
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

        if settings.patternMode == .linear {
            if settings.direction == .automatic, let preferredVisualDirection {
                return directionalCandidate(
                    surface: surface,
                    settings: settings,
                    width: width,
                    height: height,
                    areaSqIn: areaSqIn,
                    perimeterIn: perimeterIn,
                    resolvedDirection: .automatic,
                    runDirection: preferredVisualDirection,
                    idPrefix: "linear-\(vinylFormatAngleForId(preferredVisualDirection.angleDegrees))"
                )
            }
            return sameDirection
        }

        var baseline = sameDirection
        if settings.direction == .automatic,
           let angled = bestSolidAngleCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            baseline: baseline
           ) {
            baseline = angled
        }

        guard settings.allowsDirectionalChanges else {
            return baseline
        }

        let legalMixed = wallAlignedMixedCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn
        )
        if let legalMixed, isBetterCandidate(legalMixed, than: baseline) {
            return legalMixed
        }

        if legalMixed == nil,
           let unconstrainedMixed = unconstrainedMixedAxisCandidate(
                surface: surface,
                settings: settings,
                width: width,
                height: height,
                areaSqIn: areaSqIn,
                perimeterIn: perimeterIn
           ),
           isBetterCandidate(unconstrainedMixed, than: baseline) {
            return baseline.adding(issue: .mixedRunMissingHouseAlignedTransition(surfaceId: surface.id))
        }
        return baseline
    }

    private static func isBetterCandidate(_ candidate: SurfaceCandidate, than baseline: SurfaceCandidate) -> Bool {
        if abs(candidate.cutAreaSqFt - baseline.cutAreaSqFt) > 0.01 {
            return candidate.cutAreaSqFt < baseline.cutAreaSqFt
        }
        return candidate.stripCount < baseline.stripCount
    }

    private static func axisCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double,
        direction: VinylLayoutDirection,
        runDirectionLabel: String
    ) -> SurfaceCandidate {
        let angleDegrees: Double
        switch direction {
        case .automatic:
            preconditionFailure("Resolve automatic before building a vinyl cut candidate.")
        case .lengthwise:
            angleDegrees = width >= height ? 0 : 90
        case .widthwise:
            angleDegrees = width < height ? 0 : 90
        }

        return directionalCandidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            resolvedDirection: direction,
            runDirection: VinylRunDirection(angleDegrees: angleDegrees, label: runDirectionLabel),
            idPrefix: direction.rawValue
        )
    }

    private static func directionalCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double,
        resolvedDirection: VinylLayoutDirection,
        runDirection: VinylRunDirection,
        idPrefix: String
    ) -> SurfaceCandidate {
        let directionRegionId = "\(surface.id)-region-\(idPrefix)"
        let cuts = cutsForPolygon(
            surface: surface,
            settings: settings,
            direction: runDirection,
            idPrefix: idPrefix,
            directionRegionId: directionRegionId
        )
        let targetCross = crossSpan(for: surface.positions, scaleFactor: surface.scaleFactor, direction: runDirection) + (settings.edgeWrapInches * 2)

        return SurfaceCandidate(
            surface: surface,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            resolvedDirection: resolvedDirection,
            runAxis: runDirection.runAxis,
            runAngleDegrees: runDirection.angleDegrees,
            runDirectionLabel: runDirection.label,
            targetCross: targetCross,
            coverageCross: coverageCross(stripCount: cuts.count, settings: settings),
            cuts: cuts,
            directionRegions: [
                VinylDirectionRegion(
                    id: directionRegionId,
                    polygon: surface.positions,
                    runAngleDegrees: runDirection.angleDegrees
                )
            ],
            directionTransitions: [],
            issues: []
        )
    }

    private static func bestSolidAngleCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double,
        baseline: SurfaceCandidate
    ) -> SurfaceCandidate? {
        let candidates = edgeDerivedRunDirections(for: surface)
            .filter { direction in
                angularDistance(direction.angleDegrees, 0) > 2 &&
                    angularDistance(direction.angleDegrees, 90) > 2
            }
            .map { direction in
                directionalCandidate(
                    surface: surface,
                    settings: settings,
                    width: width,
                    height: height,
                    areaSqIn: areaSqIn,
                    perimeterIn: perimeterIn,
                    resolvedDirection: .automatic,
                    runDirection: VinylRunDirection(angleDegrees: direction.angleDegrees, label: "MIN WASTE"),
                    idPrefix: "solid-\(vinylFormatAngleForId(direction.angleDegrees))"
                )
            }
            .filter { !$0.cuts.isEmpty }

        guard let best = candidates.min(by: {
            if abs($0.cutAreaSqFt - $1.cutAreaSqFt) > 0.01 {
                return $0.cutAreaSqFt < $1.cutAreaSqFt
            }
            return $0.stripCount < $1.stripCount
        }) else {
            return nil
        }

        return best.cutAreaSqFt < baseline.cutAreaSqFt * 0.95 ? best : nil
    }

    private static func wallAlignedMixedCandidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double
    ) -> SurfaceCandidate? {
        let houseEdges = surface.edges.filter {
            $0.edgeType == .houseEdge && SnapEngine.distance($0.start, $0.end) > 0.5
        }
        guard !houseEdges.isEmpty else { return nil }

        var candidates: [SurfaceCandidate] = []
        for edge in houseEdges {
            let split = PolygonSplitter.split(
                polygon: surface.positions,
                lineA: edge.start,
                lineB: edge.end
            )
            guard split.didSplit else { continue }

            let seamSegments = interiorTransitionSegments(
                split.chordSegments,
                polygon: surface.positions,
                lineA: edge.start,
                lineB: edge.end,
                scaleFactor: surface.scaleFactor
            )
            guard !seamSegments.isEmpty else { continue }

            let firstPolygon = simplifiedPolygon(split.sideA)
            let secondPolygon = simplifiedPolygon(split.sideB)
            guard firstPolygon.count >= 3, secondPolygon.count >= 3 else { continue }
            let firstRegionId = "\(surface.id)-wall-\(edge.id)-a"
            let secondRegionId = "\(surface.id)-wall-\(edge.id)-b"
            let firstSurface = regionSurface(from: surface, positions: firstPolygon)
            let secondSurface = regionSurface(from: surface, positions: secondPolygon)
            let firstChoices = regionDirectionChoices(
                for: firstSurface,
                sourceSurface: surface,
                settings: settings,
                regionId: firstRegionId,
                idPrefix: "wall-\(edge.id)-a",
                nonWrappingSegments: seamSegments
            )
            let secondChoices = regionDirectionChoices(
                for: secondSurface,
                sourceSurface: surface,
                settings: settings,
                regionId: secondRegionId,
                idPrefix: "wall-\(edge.id)-b",
                nonWrappingSegments: seamSegments
            )

            for first in firstChoices {
                for second in secondChoices where angularDistance(first.direction.angleDegrees, second.direction.angleDegrees) > 2 {
                    let cuts = first.cuts + second.cuts
                    guard !cuts.isEmpty else { continue }
                    candidates.append(
                        SurfaceCandidate(
                            surface: surface,
                            width: width,
                            height: height,
                            areaSqIn: areaSqIn,
                            perimeterIn: perimeterIn,
                            resolvedDirection: settings.direction,
                            runAxis: first.direction.runAxis,
                            runAngleDegrees: first.direction.angleDegrees,
                            runDirectionLabel: "MIXED",
                            targetCross: max(width, height) + (settings.edgeWrapInches * 2),
                            coverageCross: coverageCross(stripCount: cuts.count, settings: settings),
                            cuts: cuts,
                            directionRegions: [
                                VinylDirectionRegion(
                                    id: firstRegionId,
                                    polygon: firstPolygon,
                                    runAngleDegrees: first.direction.angleDegrees
                                ),
                                VinylDirectionRegion(
                                    id: secondRegionId,
                                    polygon: secondPolygon,
                                    runAngleDegrees: second.direction.angleDegrees
                                )
                            ],
                            directionTransitions: [
                                VinylDirectionTransition(
                                    id: "\(surface.id)-transition-\(edge.id)",
                                    houseEdgeId: edge.id,
                                    segments: seamSegments,
                                    firstRegionId: firstRegionId,
                                    secondRegionId: secondRegionId
                                )
                            ],
                            issues: []
                        )
                    )
                }
            }
        }

        return candidates.min { lhs, rhs in
            isBetterCandidate(lhs, than: rhs)
        }
    }

    private static func simplifiedPolygon(_ polygon: [CGPoint]) -> [CGPoint] {
        var points: [CGPoint] = []
        for point in polygon where points.last.map({ SnapEngine.distance($0, point) >= 0.01 }) ?? true {
            points.append(point)
        }
        if points.count > 1,
           let first = points.first,
           let last = points.last,
           SnapEngine.distance(first, last) < 0.01 {
            points.removeLast()
        }

        var removed = true
        while removed, points.count >= 3 {
            removed = false
            for index in points.indices {
                let previous = points[(index - 1 + points.count) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                let cross = abs(
                    Double(current.x - previous.x) * Double(next.y - current.y) -
                        Double(current.y - previous.y) * Double(next.x - current.x)
                )
                let scale = max(
                    1,
                    SnapEngine.distance(previous, current) + SnapEngine.distance(current, next)
                )
                if cross / scale < 0.01 {
                    points.remove(at: index)
                    removed = true
                    break
                }
            }
        }
        return points
    }

    private static func regionSurface(
        from surface: VinylOrderSurfaceInput,
        positions: [CGPoint]
    ) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: surface.id,
            label: surface.label,
            levelName: surface.levelName,
            positions: positions,
            scaleFactor: surface.scaleFactor
        )
    }

    private static func regionDirectionChoices(
        for region: VinylOrderSurfaceInput,
        sourceSurface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        regionId: String,
        idPrefix: String,
        nonWrappingSegments: [VinylSeamSegment]
    ) -> [RegionDirectionChoice] {
        let directions: [VinylRunDirection]
        switch settings.direction {
        case .automatic:
            var unique: [VinylRunDirection] = []
            let proposed = [
                VinylRunDirection(angleDegrees: 0, label: "MIXED"),
                VinylRunDirection(angleDegrees: 90, label: "MIXED")
            ] + edgeDerivedRunDirections(for: sourceSurface).map {
                VinylRunDirection(angleDegrees: $0.angleDegrees, label: "MIXED")
            }
            for direction in proposed where !unique.contains(where: {
                angularDistance($0.angleDegrees, direction.angleDegrees) <= 2
            }) {
                unique.append(direction)
            }
            directions = unique
        case .lengthwise, .widthwise:
            guard let manual = manualRegionDirection(
                for: region.positions,
                layoutDirection: settings.direction
            ) else { return [] }
            directions = [manual]
        }

        return directions.compactMap { direction in
            let cuts = cutsForPolygon(
                surface: region,
                settings: settings,
                direction: direction,
                idPrefix: "\(idPrefix)-\(vinylFormatAngleForId(direction.angleDegrees))",
                directionRegionId: regionId,
                nonWrappingSegments: nonWrappingSegments
            )
            guard !cuts.isEmpty else { return nil }
            return RegionDirectionChoice(direction: direction, cuts: cuts)
        }
    }

    private static func manualRegionDirection(
        for positions: [CGPoint],
        layoutDirection: VinylLayoutDirection
    ) -> VinylRunDirection? {
        guard positions.count >= 3 else { return nil }
        let longest = positions.indices
            .map { index -> (angle: Double, length: Double) in
                let start = positions[index]
                let end = positions[(index + 1) % positions.count]
                let dx = Double(end.x - start.x)
                let dy = Double(end.y - start.y)
                return (
                    angle: normalizedAngle(atan2(dy, dx) * 180 / .pi),
                    length: sqrt((dx * dx) + (dy * dy))
                )
            }
            .max { $0.length < $1.length }
        guard let longest, longest.length > 0.01 else { return nil }

        let angle: Double
        let label: String
        switch layoutDirection {
        case .automatic:
            return nil
        case .lengthwise:
            angle = longest.angle
            label = "LENGTH"
        case .widthwise:
            angle = longest.angle + 90
            label = "WIDTH"
        }
        return VinylRunDirection(angleDegrees: angle, label: label)
    }

    private static func interiorTransitionSegments(
        _ chords: [PolygonSplitter.ChordSegment],
        polygon: [CGPoint],
        lineA: CGPoint,
        lineB: CGPoint,
        scaleFactor: Double
    ) -> [VinylSeamSegment] {
        let dx = Double(lineB.x - lineA.x)
        let dy = Double(lineB.y - lineA.y)
        let length = sqrt((dx * dx) + (dy * dy))
        guard length > 0.5 else { return [] }
        let probeDistance = max(0.25, min(2, scaleFactor * 0.25))
        let normalX = CGFloat((-dy / length) * probeDistance)
        let normalY = CGFloat((dx / length) * probeDistance)

        // `PolygonSplitter.chords` pairs sorted boundary hits. When the source
        // house edge itself lies on the polygon boundary, reversing the line can
        // expose the interior extension that follows that boundary run. Merge
        // both orientations, then let the two-sided probe reject the exterior
        // wall segment in either direction.
        let candidates = chords + PolygonSplitter.chords(
            polygon: polygon,
            lineA: lineB,
            lineB: lineA
        )
        var accepted: [VinylSeamSegment] = []
        for chord in candidates {
            guard SnapEngine.distance(chord.start, chord.end) > 0.5 else { continue }
            let midpoint = CGPoint(
                x: (chord.start.x + chord.end.x) / 2,
                y: (chord.start.y + chord.end.y) / 2
            )
            let firstProbe = CGPoint(x: midpoint.x + normalX, y: midpoint.y + normalY)
            let secondProbe = CGPoint(x: midpoint.x - normalX, y: midpoint.y - normalY)
            guard PolygonMath.pointInPolygon(firstProbe, vertices: polygon),
                  PolygonMath.pointInPolygon(secondProbe, vertices: polygon) else {
                continue
            }
            let duplicate = accepted.contains { segment in
                (SnapEngine.distance(segment.start, chord.start) < 0.5 &&
                    SnapEngine.distance(segment.end, chord.end) < 0.5) ||
                    (SnapEngine.distance(segment.start, chord.end) < 0.5 &&
                        SnapEngine.distance(segment.end, chord.start) < 0.5)
            }
            if !duplicate {
                accepted.append(VinylSeamSegment(start: chord.start, end: chord.end))
            }
        }
        return accepted
    }

    /// Detection-only model of the former free rectilinear optimizer. Its cuts
    /// are never returned to an order. It only tells validation that an unlocked
    /// turned layout would have won without a legal house-wall transition.
    private static func unconstrainedMixedAxisCandidate(
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
            let horizontal = cutsForPolygon(
                surface: rectSurface,
                settings: settings,
                direction: VinylRunDirection(angleDegrees: 0, label: "MIXED"),
                idPrefix: "mixed-\(index)-h"
            )
            let vertical = cutsForPolygon(
                surface: rectSurface,
                settings: settings,
                direction: VinylRunDirection(angleDegrees: 90, label: "MIXED"),
                idPrefix: "mixed-\(index)-v"
            )
            let horizontalArea = horizontal.reduce(0) { $0 + $1.fullRollAreaSqFt }
            let verticalArea = vertical.reduce(0) { $0 + $1.fullRollAreaSqFt }
            switch settings.direction {
            case .automatic:
                cuts.append(contentsOf: horizontalArea <= verticalArea ? horizontal : vertical)
            case .lengthwise:
                cuts.append(contentsOf: rect.width >= rect.height ? horizontal : vertical)
            case .widthwise:
                cuts.append(contentsOf: rect.width < rect.height ? horizontal : vertical)
            }
        }

        guard Set(cuts.map { Int($0.runAngleDegrees.rounded()) }).count > 1 else { return nil }

        return SurfaceCandidate(
            surface: surface,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            resolvedDirection: settings.direction,
            runAxis: cuts.first?.runAxis ?? .horizontal,
            runAngleDegrees: cuts.first?.runAngleDegrees ?? 0,
            runDirectionLabel: "MIXED",
            targetCross: max(width, height) + (settings.edgeWrapInches * 2),
            coverageCross: coverageCross(stripCount: cuts.count, settings: settings),
            cuts: cuts,
            directionRegions: [],
            directionTransitions: [],
            issues: []
        )
    }

    private static func surfacePlan(from candidate: SurfaceCandidate, cuts: [VinylCutPiece]) -> VinylSurfaceCutPlan {
        VinylSurfaceCutPlan(
            id: candidate.surface.id,
            label: candidate.surface.label,
            levelName: candidate.surface.levelName,
            positions: candidate.surface.positions,
            scaleFactor: candidate.surface.scaleFactor,
            boundingWidthInches: candidate.width,
            boundingHeightInches: candidate.height,
            surfaceAreaSqFt: candidate.areaSqIn / 144.0,
            perimeterFeet: candidate.perimeterIn / 12.0,
            resolvedDirection: candidate.resolvedDirection,
            runAxis: candidate.runAxis,
            runAngleDegrees: candidate.runAngleDegrees,
            runDirectionLabel: candidate.runDirectionLabel,
            stripCount: cuts.count,
            stripLengthInches: cuts.map(\.lengthInches).max() ?? 0,
            rollWidthInches: cuts.first?.rollWidthInches ?? 0,
            targetCrossInches: candidate.targetCross,
            coverageCrossInches: candidate.coverageCross,
            offcutWidthInches: cuts.map { max(0, $0.rollWidthInches - $0.requiredWidthInches) }.max() ?? 0,
            cutAreaSqFt: cuts.reduce(0) { $0 + $1.fullRollAreaSqFt },
            cuts: cuts,
            edges: candidate.surface.edges,
            directionRegions: candidate.directionRegions,
            directionTransitions: candidate.directionTransitions
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

    /// Packs cuts against reusable offcut lanes — both banked offcuts already on
    /// hand (`availableOffcuts`, so reuse spans jobs) and the new leftover-width
    /// remnants this job's cuts create. Returns the cuts (with reuse provenance
    /// stamped) plus the NEW remnants worth banking (the on-hand ones that merely
    /// got reused are not re-reported).
    private static func assignOffcuts(
        _ cuts: [VinylCutPiece],
        settings: VinylOrderSettings,
        availableOffcuts: [VinylOnHandOffcut]
    ) -> (cuts: [VinylCutPiece], producedOffcuts: [VinylProducedOffcut]) {
        let minWidth = settings.offcutMinWidthInches
        // Seed lanes from banked offcuts, widest first, so the planner prefers a
        // banked offcut over purchasing new material before it ever cuts a roll.
        var offcuts: [OffcutLane] = availableOffcuts
            .sorted {
                if abs($0.widthInches - $1.widthInches) > 0.01 { return $0.widthInches > $1.widthInches }
                return $0.lengthInches > $1.lengthInches
            }
            .map {
                OffcutLane(
                    id: $0.id,
                    sourceSurfaceId: "stock:\($0.id)",
                    sourceSurfaceLabel: $0.label,
                    width: $0.widthInches,
                    length: $0.lengthInches,
                    isOnHand: true
                )
            }
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
                if offcuts[index].width < minWidth {
                    offcuts.remove(at: index)
                }
            } else {
                assignedById[cut.id] = cut
                let leftoverWidth = cut.rollWidthInches - cut.requiredWidthInches
                if leftoverWidth > 0, leftoverWidth >= minWidth {
                    offcuts.append(OffcutLane(
                        id: "offcut-\(cut.id)",
                        sourceSurfaceId: cut.surfaceId,
                        sourceSurfaceLabel: cut.displayLabel,
                        width: leftoverWidth,
                        length: cut.lengthInches,
                        isOnHand: false
                    ))
                }
            }
        }

        // Surviving lanes that this job created (not the banked ones) and still
        // carry usable width are the remnants the operator can bank to stock.
        let producedOffcuts = offcuts
            .filter { !$0.isOnHand && $0.width > 0 && $0.width >= minWidth && $0.length > 0 }
            .map {
                VinylProducedOffcut(
                    id: $0.id,
                    sourceSurfaceLabel: $0.sourceSurfaceLabel,
                    widthInches: $0.width,
                    lengthInches: $0.length
                )
            }

        return (cuts.compactMap { assignedById[$0.id] }, producedOffcuts)
    }

    private static func cutsForPolygon(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        direction: VinylRunDirection,
        idPrefix: String,
        directionRegionId: String? = nil,
        nonWrappingSegments: [VinylSeamSegment] = []
    ) -> [VinylCutPiece] {
        let polygon = surface.positions.map {
            CGPoint(x: Double($0.x) / surface.scaleFactor, y: Double($0.y) / surface.scaleFactor)
        }
        let projectedPolygon = polygon.map(direction.project)
        guard let bounds = bounds(for: projectedPolygon) else { return [] }

        let noWrapBoundary = ProjectedNoWrapBoundary(
            polygon: surface.positions,
            seamSegments: nonWrappingSegments,
            scaleFactor: surface.scaleFactor,
            direction: direction
        )

        let crossMin = bounds.minY - (noWrapBoundary?.excludesCrossMinimum == true ? 0 : settings.edgeWrapInches)
        let crossMax = bounds.maxY + (noWrapBoundary?.excludesCrossMaximum == true ? 0 : settings.edgeWrapInches)
        let effectiveCoverage = max(1, settings.rollWidthInches - settings.seamOverlapInches)
        let step = min(1.0, effectiveCoverage)
        var best: [VinylCutPiece] = []
        var bestArea = Double.infinity
        var offset = 0.0

        while offset < effectiveCoverage {
            let cuts = cutsForOffset(
                polygon: projectedPolygon,
                surface: surface,
                settings: settings,
                direction: direction,
                idPrefix: idPrefix,
                directionRegionId: directionRegionId,
                noWrapBoundary: noWrapBoundary,
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
                polygon: projectedPolygon,
                surface: surface,
                settings: settings,
                direction: direction,
                idPrefix: idPrefix,
                directionRegionId: directionRegionId,
                noWrapBoundary: noWrapBoundary,
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
        direction: VinylRunDirection,
        idPrefix: String,
        directionRegionId: String?,
        noWrapBoundary: ProjectedNoWrapBoundary?,
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
            let requiredWidth = max(1, min(settings.rollWidthInches, min(bandEnd, crossMax) - max(bandStart, crossMin)))
            // A band can straddle disjoint material — the two upstands of a
            // U-shape with the void between them (bug 3ab9c10b). Each maximal
            // run of material in the band is its own cut; a single strip must
            // never bridge a void that spans the band's full width, or the void
            // gets charged as purchased material and waste.
            for (runIndex, run) in runSpansInBand(polygon: polygon, bandMin: bandStart, bandMax: bandEnd).enumerated() {
                let runStartWrap = noWrapBoundary?.wrapsRunMinimum(
                    rawRun: run.min,
                    bandMinimum: bandStart,
                    bandMaximum: bandEnd
                ) ?? true
                let runEndWrap = noWrapBoundary?.wrapsRunMaximum(
                    rawRun: run.max,
                    bandMinimum: bandStart,
                    bandMaximum: bandEnd
                ) ?? true
                let runStart = run.min - (runStartWrap ? settings.edgeWrapInches : 0)
                let runEnd = run.max + (runEndWrap ? settings.edgeWrapInches : 0)
                let length = max(1, runEnd - runStart)
                cuts.append(VinylCutPiece(
                    id: "\(surface.id)-\(idPrefix)-\(index)-\(runIndex)-\(vinylFormatInches(length))-\(vinylFormatInches(requiredWidth))",
                    surfaceId: surface.id,
                    surfaceLabel: surface.label,
                    levelName: surface.levelName,
                    runAxis: direction.runAxis,
                    runAngleDegrees: direction.angleDegrees,
                    runDirectionLabel: direction.label,
                    lengthInches: length,
                    rollWidthInches: settings.rollWidthInches,
                    requiredWidthInches: requiredWidth,
                    bandStartInches: max(bandStart, crossMin),
                    bandEndInches: min(bandEnd, crossMax),
                    runStartInches: runStart,
                    runEndInches: runEnd,
                    directionRegionId: directionRegionId,
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

    /// The maximal runs of deck material a roll laid in this band must cover, in
    /// the run axis. A run is one cut. Two runs stay separate only when NO
    /// cross-sample within the band bridges them — i.e. the gap is a true void
    /// spanning the band's full width (the U-shape centre cut-out). If any
    /// sample bridges the gap (connected material, e.g. a band straddling the
    /// U's base), the runs merge into one full-width strip. Union-and-merge
    /// across every sample yields exactly that: the void-spanning bug charged
    /// the whole span; this charges only real material.
    private static func runSpansInBand(
        polygon: [CGPoint],
        bandMin: Double,
        bandMax: Double
    ) -> [(min: Double, max: Double)] {
        let epsilon = 0.001
        var samples: [Double] = [
            bandMin + epsilon,
            (bandMin + bandMax) / 2,
            bandMax - epsilon
        ]
        for point in polygon {
            let cross = Double(point.y)
            if cross > bandMin + epsilon && cross < bandMax - epsilon {
                samples.append(cross)
                samples.append(max(bandMin + epsilon, cross - epsilon))
                samples.append(min(bandMax - epsilon, cross + epsilon))
            }
        }

        var intervals: [(min: Double, max: Double)] = []
        for sample in samples where sample > bandMin && sample < bandMax {
            intervals.append(contentsOf: scanIntervals(polygon: polygon, cross: sample))
        }
        guard !intervals.isEmpty else { return [] }

        // Merge overlapping/touching intervals — touching (shared endpoint)
        // counts as connected so a seam-aligned split never fragments solid
        // material. Whatever the sample order, sort by start first.
        intervals.sort { $0.min < $1.min }
        var merged: [(min: Double, max: Double)] = [intervals[0]]
        for interval in intervals.dropFirst() {
            let lastIndex = merged.count - 1
            if interval.min <= merged[lastIndex].max + epsilon {
                merged[lastIndex].max = max(merged[lastIndex].max, interval.max)
            } else {
                merged.append(interval)
            }
        }
        return merged.filter { $0.max > $0.min }
    }

    private static func scanIntervals(
        polygon: [CGPoint],
        cross: Double
    ) -> [(min: Double, max: Double)] {
        guard polygon.count >= 3 else { return [] }
        var intersections: [Double] = []
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let aCross = Double(a.y)
            let bCross = Double(b.y)
            guard (aCross <= cross && bCross > cross) || (bCross <= cross && aCross > cross) else {
                continue
            }
            let ratio = (cross - aCross) / (bCross - aCross)
            let aRun = Double(a.x)
            let bRun = Double(b.x)
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

    private static func preferredVisualRunDirection(for surfaces: [VinylOrderSurfaceInput]) -> VinylRunDirection? {
        let samples = surfaces.flatMap { edgeDirectionSamples(for: $0, includePositionFallback: false) }
        let houseSamples = samples.filter { $0.label == "HOUSE EDGE" }

        if let cluster = bestDirectionCluster(from: houseSamples) {
            return VinylRunDirection(angleDegrees: cluster.meanAngleDegrees, label: cluster.label)
        }

        if let cluster = bestDirectionCluster(from: samples) {
            return VinylRunDirection(angleDegrees: cluster.meanAngleDegrees, label: cluster.label)
        }

        return nil
    }

    private static func edgeDerivedRunDirections(for surface: VinylOrderSurfaceInput) -> [VinylRunDirection] {
        directionClusters(from: edgeDirectionSamples(for: surface, includePositionFallback: true))
            .sorted {
                if abs($0.totalWeight - $1.totalWeight) > 0.01 {
                    return $0.totalWeight > $1.totalWeight
                }
                return $0.meanAngleDegrees < $1.meanAngleDegrees
            }
            .map { VinylRunDirection(angleDegrees: $0.meanAngleDegrees, label: $0.label) }
    }

    private static func edgeDirectionSamples(
        for surface: VinylOrderSurfaceInput,
        includePositionFallback: Bool
    ) -> [EdgeDirectionSample] {
        let edgeSamples = surface.edges.compactMap { edge -> EdgeDirectionSample? in
            let dx = Double(edge.end.x - edge.start.x)
            let dy = Double(edge.end.y - edge.start.y)
            let length = sqrt((dx * dx) + (dy * dy))
            guard length > 0.01 else { return nil }
            let isHouseEdge = edge.edgeType == .houseEdge
            return EdgeDirectionSample(
                angleDegrees: normalizedAngle(atan2(dy, dx) * 180 / .pi),
                weight: isHouseEdge ? length * 4 : length,
                label: isHouseEdge ? "HOUSE EDGE" : "LONG EDGE"
            )
        }

        guard edgeSamples.isEmpty, includePositionFallback else {
            return edgeSamples
        }

        return surface.positions.indices.compactMap { index -> EdgeDirectionSample? in
            let start = surface.positions[index]
            let end = surface.positions[(index + 1) % surface.positions.count]
            let dx = Double(end.x - start.x)
            let dy = Double(end.y - start.y)
            let length = sqrt((dx * dx) + (dy * dy))
            guard length > 0.01 else { return nil }
            return EdgeDirectionSample(
                angleDegrees: normalizedAngle(atan2(dy, dx) * 180 / .pi),
                weight: length,
                label: "LONG EDGE"
            )
        }
    }

    private static func bestDirectionCluster(from samples: [EdgeDirectionSample]) -> DirectionCluster? {
        directionClusters(from: samples).max {
            if abs($0.totalWeight - $1.totalWeight) > 0.01 {
                return $0.totalWeight < $1.totalWeight
            }
            return $0.meanAngleDegrees > $1.meanAngleDegrees
        }
    }

    private static func directionClusters(from samples: [EdgeDirectionSample]) -> [DirectionCluster] {
        var clusters: [DirectionCluster] = []
        for sample in samples.sorted(by: { $0.weight > $1.weight }) {
            if let index = clusters.firstIndex(where: { angularDistance($0.meanAngleDegrees, sample.angleDegrees) <= 5 }) {
                clusters[index].samples.append(sample)
            } else {
                clusters.append(DirectionCluster(samples: [sample]))
            }
        }
        return clusters
    }

    private static func axialMeanAngle(_ weightedAngles: [(angleDegrees: Double, weight: Double)]) -> Double {
        var x = 0.0
        var y = 0.0
        for item in weightedAngles where item.weight > 0 {
            let radians = normalizedAngle(item.angleDegrees) * .pi / 90
            x += cos(radians) * item.weight
            y += sin(radians) * item.weight
        }
        guard x.isFinite, y.isFinite, abs(x) + abs(y) > 0.0001 else {
            return normalizedAngle(weightedAngles.first?.angleDegrees ?? 0)
        }
        return normalizedAngle(atan2(y, x) * 90 / .pi)
    }

    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(normalizedAngle(a) - normalizedAngle(b))
        return min(difference, 180 - difference)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 180)
        if normalized < 0 {
            normalized += 180
        }
        if abs(normalized - 180) < 0.001 {
            normalized = 0
        }
        return normalized
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

    private static func crossSpan(
        for positions: [CGPoint],
        scaleFactor: Double,
        direction: VinylRunDirection
    ) -> Double {
        let values = positions.map {
            direction.project(CGPoint(x: Double($0.x) / scaleFactor, y: Double($0.y) / scaleFactor)).y
        }
        return span(values)
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

/// Internal (not private): the bulk order wizard renders roll widths with the
/// same convention as the order sheet's [roll_width] token.
func vinylFormatInches(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return "\(Int(rounded))\""
    }
    return String(format: "%.1f\"", rounded)
}

private func vinylFormatAngle(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return "\(Int(rounded)) DEG"
    }
    return String(format: "%.1f DEG", rounded)
}

private func vinylFormatAngleForId(_ value: Double) -> String {
    vinylFormatAngle(value)
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: ".", with: "_")
}

private func vinylRunDirectionSummary(label: String, angleDegrees: Double) -> String {
    if label == "MIXED" {
        return "MIXED"
    }
    return "\(label) @ \(vinylFormatAngle(angleDegrees))"
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
