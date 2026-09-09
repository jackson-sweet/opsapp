//
//  VinylOrderWorkspaceCopy.swift
//  OPS
//
//  Every string the order-layout workspace renders, in one testable place.
//
//  Voice: terse, uppercase, `//` on the context line, numbers always mono and
//  always formatted, `—` for empty. Nothing is said twice — the header carries
//  identity and size, the peek line carries the numbers that move when the
//  operator turns a setting.
//

import Foundation

enum VinylOrderWorkspaceCopy {

    static let screen = "ORDER LAYOUT"
    static let fitAction = "FIT"
    static let fullScreenAction = "FULL SCREEN"
    static let settingsSection = "SETTINGS"
    static let cutListSection = "CUT LIST"
    static let empty = "—"

    // MARK: - Header

    /// `// ORDER LAYOUT · 24' × 12' · REAR DECK`
    ///
    /// Size before name on purpose: the line truncates from the right on a long
    /// deck title, and the deck's dimensions are the thing the operator opened
    /// this screen to read. The project title sits above it, so the job is
    /// already named.
    static func contextLine(
        plan: VinylCutPlan,
        deckTitle: String?,
        measurementSystem: MeasurementSystem
    ) -> String {
        var parts = ["// \(screen)"]
        if let size = boundingSizeLine(for: plan, measurementSystem: measurementSystem) {
            parts.append(size)
        }
        let trimmed = deckTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            parts.append(trimmed.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    /// `24' × 12'`, or `24' × 12' +1` when the plan covers more surfaces than
    /// the one being measured. Nil when there is no surface to measure.
    static func boundingSizeLine(
        for plan: VinylCutPlan,
        measurementSystem: MeasurementSystem
    ) -> String? {
        guard let surface = plan.surfaces.first else { return nil }

        let size = DimensionEngine.format(surface.boundingWidthInches, system: measurementSystem)
            + " × "
            + DimensionEngine.format(surface.boundingHeightInches, system: measurementSystem)

        let others = plan.surfaces.count - 1
        return others > 0 ? "\(size) +\(others)" : size
    }

    // MARK: - Settings sheet

    /// `6 CUTS · 68 SQ FT · 18% WASTE`
    ///
    /// The three numbers every setting on the sheet moves: how many pieces get
    /// cut, how much material gets bought, and how much of it ends up on the
    /// floor. Waste is the reason to touch RUN or WRAP at all, so it is on the
    /// line the operator can see without opening anything.
    static func summaryLine(for plan: VinylCutPlan) -> String {
        guard !plan.surfaces.isEmpty else { return empty }

        let cuts = plan.totalStripCount
        return [
            "\(cuts) CUT\(cuts == 1 ? "" : "S")",
            "\(plan.totalOrderedSqFt) SQ FT",
            "\(wastePercent(of: plan))% WASTE"
        ].joined(separator: " · ")
    }

    /// Offcut as a share of what gets purchased, rounded to a whole percent —
    /// never a raw float.
    static func wastePercent(of plan: VinylCutPlan) -> Int {
        let purchased = plan.totalPurchasedCutAreaSqFt
        guard purchased > 0 else { return 0 }
        return Int((plan.totalWasteSqFt / purchased * 100).rounded())
    }

    // MARK: - Accessibility

    static let windowLabel = "Order layout"
    static let windowHint = "Opens full screen"
    static let closeLabel = "Close order layout"
    static let fitLabel = "Fit layout"
    static let drawingLabel = "Order layout drawing"
    static let zoomLabel = "Zoom"
    static let settingsSheetLabel = "Order settings"
    static let settingsExpandHint = "Opens the order settings"
    static let settingsCollapseHint = "Closes the order settings"

    /// Spoken zoom level for the drawing's adjustable action. Always a whole
    /// percent — never a raw scale float.
    static func zoomValue(scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}
