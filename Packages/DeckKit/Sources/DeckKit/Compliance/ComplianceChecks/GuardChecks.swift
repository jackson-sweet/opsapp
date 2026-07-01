import Foundation

enum GuardChecks {
    static func evaluate(
        _ data: DeckDrawingData,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        let guardRules = package.guardRules
        let explicitHeightInches = explicitDeckHeightFeet(data).map { $0 * 12 }

        return data.allEdges.flatMap { edge -> [ComplianceFinding] in
            guard edge.edgeType == .deckEdge else { return [] }

            var findings: [ComplianceFinding] = []
            if let railing = edge.railingConfig {
                findings.append(
                    contentsOf: configuredGuardFindings(
                        edge: edge,
                        railing: railing,
                        mode: mode,
                        guardRules: guardRules
                    )
                )
            } else if let height = explicitHeightInches,
                      height >= guardRules.guardRequiredHeightInches {
                findings.append(
                    missingGuardFinding(
                        edge: edge,
                        heightInches: height,
                        mode: mode,
                        guardRules: guardRules
                    )
                )
            }
            return findings
        }
    }

    private static func configuredGuardFindings(
        edge: DeckEdge,
        railing: RailingConfig,
        mode: ComplianceEngine.Mode,
        guardRules: GuardRules
    ) -> [ComplianceFinding] {
        var findings: [ComplianceFinding] = []

        if railing.postHeight < guardRules.minGuardHeightInches {
            findings.append(
                ComplianceFinding(
                    id: "guard:height:\(edge.id)",
                    item: "Guard height \(edge.id)",
                    severity: .safetyHazard,
                    currentValue: formatInches(railing.postHeight),
                    targetValue: formatInches(guardRules.minGuardHeightInches),
                    codeSection: guardRules.codeSection,
                    fix: "Raise guard to the required height.",
                    confidence: .high,
                    evidence: nil,
                    source: source(for: mode)
                )
            )
        }

        if let maxPostSpacing = guardRules.maxPostSpacingInches,
           railing.maxPostSpacing > maxPostSpacing {
            findings.append(
                ComplianceFinding(
                    id: "guard:post-spacing:\(edge.id)",
                    item: "Guard post spacing \(edge.id)",
                    severity: .safetyHazard,
                    currentValue: formatInches(railing.maxPostSpacing),
                    targetValue: "\(formatInches(maxPostSpacing)) maximum",
                    codeSection: guardRules.codeSection,
                    fix: "Reduce post spacing or use a rated guard layout.",
                    confidence: .high,
                    evidence: nil,
                    source: source(for: mode)
                )
            )
        }

        return findings
    }

    private static func missingGuardFinding(
        edge: DeckEdge,
        heightInches: Double,
        mode: ComplianceEngine.Mode,
        guardRules: GuardRules
    ) -> ComplianceFinding {
        ComplianceFinding(
            id: "guard:required:\(edge.id)",
            item: "Guard \(edge.id)",
            severity: .safetyHazard,
            currentValue: "\(formatWholeInches(heightInches)) above grade",
            targetValue: "guard required at \(formatInches(guardRules.guardRequiredHeightInches))",
            codeSection: guardRules.codeSection,
            fix: "Add a guard on this edge.",
            confidence: .high,
            evidence: nil,
            source: source(for: mode)
        )
    }

    private static func explicitDeckHeightFeet(_ data: DeckDrawingData) -> Double? {
        if let overallElevation = data.overallElevation {
            return overallElevation
        }

        let levelElevations = data.levels.compactMap(\.elevation)
        if let highestLevel = levelElevations.max() {
            return highestLevel
        }

        let vertexElevations = data.allVertices.compactMap(\.elevation)
        guard !vertexElevations.isEmpty else { return nil }
        return vertexElevations.max()
    }

    private static func source(for mode: ComplianceEngine.Mode) -> FindingSource {
        mode == .asBuilt ? .userEntered : .measured
    }

    private static func formatInches(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", value)
    }

    private static func formatWholeInches(_ value: Double) -> String {
        "\(Int(value.rounded()))\""
    }
}
