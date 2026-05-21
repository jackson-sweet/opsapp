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
    var rollWidthInches: Double
    var seamOverlapInches: Double
    var edgeWrapInches: Double
    var direction: VinylLayoutDirection

    static let `default` = VinylOrderSettings(
        color: "",
        rollWidthInches: 72,
        seamOverlapInches: 1.5,
        edgeWrapInches: 6,
        direction: .automatic
    )

    var normalized: VinylOrderSettings {
        VinylOrderSettings(
            color: color.trimmingCharacters(in: .whitespacesAndNewlines),
            rollWidthInches: max(1, rollWidthInches),
            seamOverlapInches: max(0, min(seamOverlapInches, max(0, rollWidthInches - 1))),
            edgeWrapInches: max(0, edgeWrapInches),
            direction: direction
        )
    }
}

struct VinylOrderSurfaceInput: Identifiable, Equatable {
    let id: String
    let label: String
    let levelName: String?
    let positions: [CGPoint]
    let scaleFactor: Double
}

struct VinylCutPlan: Equatable {
    let settings: VinylOrderSettings
    let surfaces: [VinylSurfaceCutPlan]
    let reuseNotes: [VinylReuseNote]

    var totalCutAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.cutAreaSqFt }
    }

    var totalOrderedSqFt: Int {
        Int(ceil(totalCutAreaSqFt))
    }

    var totalSurfaceAreaSqFt: Double {
        surfaces.reduce(0) { $0 + $1.surfaceAreaSqFt }
    }

    var totalWasteSqFt: Double {
        max(0, totalCutAreaSqFt - totalSurfaceAreaSqFt)
    }

    var totalStripCount: Int {
        surfaces.reduce(0) { $0 + $1.stripCount }
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
}

struct VinylSurfaceCutPlan: Identifiable, Equatable {
    enum RunAxis: String {
        case horizontal
        case vertical
    }

    let id: String
    let label: String
    let levelName: String?
    let positions: [CGPoint]
    let boundingWidthInches: Double
    let boundingHeightInches: Double
    let surfaceAreaSqFt: Double
    let perimeterFeet: Double
    let resolvedDirection: VinylLayoutDirection
    let runAxis: RunAxis
    let stripCount: Int
    let stripLengthInches: Double
    let rollWidthInches: Double
    let targetCrossInches: Double
    let coverageCrossInches: Double
    let offcutWidthInches: Double
    let cutAreaSqFt: Double

    var displayLabel: String {
        if let levelName, !levelName.isEmpty {
            return "\(levelName) / \(label)"
        }
        return label
    }

    var orderLine: String {
        "\(displayLabel.uppercased()): \(stripCount) CUT\(stripCount == 1 ? "" : "S") @ \(vinylFormatInches(stripLengthInches)) X \(vinylFormatInches(rollWidthInches)) / \(resolvedDirection.label) / \(vinylFormatSqFt(cutAreaSqFt)) SQ FT"
    }
}

struct VinylReuseNote: Equatable {
    let sourceSurfaceLabel: String
    let targetSurfaceLabel: String
    let offcutWidthInches: Double
    let offcutLengthInches: Double

    var line: String {
        "\(targetSurfaceLabel.uppercased()) CAN FIT FROM \(sourceSurfaceLabel.uppercased()) OFFCUT: \(vinylFormatInches(offcutWidthInches)) X \(vinylFormatInches(offcutLengthInches))."
    }
}

enum VinylCutListEngine {
    static func makePlan(
        surfaces: [VinylOrderSurfaceInput],
        settings rawSettings: VinylOrderSettings
    ) -> VinylCutPlan {
        let settings = rawSettings.normalized
        let plans = surfaces.compactMap { surface in
            planSurface(surface, settings: settings)
        }
        return VinylCutPlan(
            settings: settings,
            surfaces: plans,
            reuseNotes: reuseNotes(for: plans)
        )
    }

    private static func planSurface(
        _ surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings
    ) -> VinylSurfaceCutPlan? {
        guard surface.positions.count >= 3, surface.scaleFactor > 0 else { return nil }

        let width = span(surface.positions.map(\.x)) / surface.scaleFactor
        let height = span(surface.positions.map(\.y)) / surface.scaleFactor
        guard width > 0, height > 0 else { return nil }

        let areaSqIn = PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: surface.scaleFactor)
        let perimeterIn = PolygonMath.perimeter(vertices: surface.positions) / surface.scaleFactor

        let lengthwise = candidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            direction: .lengthwise
        )
        let widthwise = candidate(
            surface: surface,
            settings: settings,
            width: width,
            height: height,
            areaSqIn: areaSqIn,
            perimeterIn: perimeterIn,
            direction: .widthwise
        )

        switch settings.direction {
        case .automatic:
            if lengthwise.cutAreaSqFt == widthwise.cutAreaSqFt {
                return lengthwise.stripCount <= widthwise.stripCount ? lengthwise : widthwise
            }
            return lengthwise.cutAreaSqFt < widthwise.cutAreaSqFt ? lengthwise : widthwise
        case .lengthwise:
            return lengthwise
        case .widthwise:
            return widthwise
        }
    }

    private static func candidate(
        surface: VinylOrderSurfaceInput,
        settings: VinylOrderSettings,
        width: Double,
        height: Double,
        areaSqIn: Double,
        perimeterIn: Double,
        direction: VinylLayoutDirection
    ) -> VinylSurfaceCutPlan {
        let longSide = max(width, height)
        let shortSide = min(width, height)
        let runsAlongX: Bool
        let stripLength: Double
        let targetCross: Double

        switch direction {
        case .automatic:
            preconditionFailure("Resolve automatic before building a vinyl cut candidate.")
        case .lengthwise:
            stripLength = longSide + (settings.edgeWrapInches * 2)
            targetCross = shortSide + (settings.edgeWrapInches * 2)
            runsAlongX = width >= height
        case .widthwise:
            stripLength = shortSide + (settings.edgeWrapInches * 2)
            targetCross = longSide + (settings.edgeWrapInches * 2)
            runsAlongX = width < height
        }

        let effectiveCoverage = max(1, settings.rollWidthInches - settings.seamOverlapInches)
        let stripCount = max(
            1,
            Int(ceil(max(0, targetCross - settings.seamOverlapInches) / effectiveCoverage))
        )
        let coverage = (Double(stripCount) * settings.rollWidthInches) - (Double(max(0, stripCount - 1)) * settings.seamOverlapInches)
        let cutAreaSqIn = Double(stripCount) * stripLength * settings.rollWidthInches

        return VinylSurfaceCutPlan(
            id: surface.id,
            label: surface.label,
            levelName: surface.levelName,
            positions: surface.positions,
            boundingWidthInches: width,
            boundingHeightInches: height,
            surfaceAreaSqFt: areaSqIn / 144.0,
            perimeterFeet: perimeterIn / 12.0,
            resolvedDirection: direction,
            runAxis: runsAlongX ? .horizontal : .vertical,
            stripCount: stripCount,
            stripLengthInches: stripLength,
            rollWidthInches: settings.rollWidthInches,
            targetCrossInches: targetCross,
            coverageCrossInches: coverage,
            offcutWidthInches: max(0, coverage - targetCross),
            cutAreaSqFt: cutAreaSqIn / 144.0
        )
    }

    private static func reuseNotes(for plans: [VinylSurfaceCutPlan]) -> [VinylReuseNote] {
        guard plans.count >= 2 else { return [] }

        let ordered = plans.sorted { $0.cutAreaSqFt > $1.cutAreaSqFt }
        var usedTargets: Set<String> = []
        var notes: [VinylReuseNote] = []

        for source in ordered {
            guard source.offcutWidthInches >= 6 else { continue }
            for target in ordered where target.id != source.id && !usedTargets.contains(target.id) {
                guard source.stripLengthInches >= target.stripLengthInches,
                      source.offcutWidthInches >= target.targetCrossInches else { continue }
                notes.append(VinylReuseNote(
                    sourceSurfaceLabel: source.displayLabel,
                    targetSurfaceLabel: target.displayLabel,
                    offcutWidthInches: source.offcutWidthInches,
                    offcutLengthInches: source.stripLengthInches
                ))
                usedTargets.insert(target.id)
                break
            }
        }

        return notes
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

private func vinylFormatSqFt(_ value: Double) -> String {
    String(format: "%.1f", value)
}
