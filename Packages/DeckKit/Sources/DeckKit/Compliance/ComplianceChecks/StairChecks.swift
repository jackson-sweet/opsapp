import Foundation

enum StairChecks {
    static func evaluate(
        _ data: DeckDrawingData,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        data.allEdges.flatMap { edge -> [ComplianceFinding] in
            guard let stair = edge.stairConfig else { return [] }
            return findings(
                for: stair,
                edgeId: edge.id,
                mode: mode,
                rules: package.stairRules
            )
        }
    }

    private static func findings(
        for stair: StairConfig,
        edgeId: String,
        mode: ComplianceEngine.Mode,
        rules: StairRules
    ) -> [ComplianceFinding] {
        var findings: [ComplianceFinding] = []
        let source = source(for: mode)
        let riser = actualRiserHeight(stair)

        if riser > rules.maxRiserHeightInches {
            findings.append(
                ComplianceFinding(
                    id: "stair:riser:\(edgeId)",
                    item: "Stair riser \(edgeId)",
                    severity: .safetyHazard,
                    currentValue: formatInches(riser),
                    targetValue: "\(formatInches(rules.maxRiserHeightInches)) maximum",
                    codeSection: rules.stairCodeSection,
                    fix: "Reduce riser height or add another tread.",
                    confidence: .high,
                    evidence: nil,
                    source: source
                )
            )
        }

        if stair.runPerTread < rules.minTreadRunInches {
            findings.append(
                ComplianceFinding(
                    id: "stair:tread-run:\(edgeId)",
                    item: "Stair tread run \(edgeId)",
                    severity: .safetyHazard,
                    currentValue: formatInches(stair.runPerTread),
                    targetValue: "\(formatInches(rules.minTreadRunInches)) minimum",
                    codeSection: rules.stairCodeSection,
                    fix: "Increase tread run to the required depth.",
                    confidence: .high,
                    evidence: nil,
                    source: source
                )
            )
        }

        let riserCount = resolvedRiserCount(stair)
        if riserCount >= rules.handrailRequiredRiserCount,
           stair.railingConfig == nil {
            findings.append(
                ComplianceFinding(
                    id: "stair:handrail:\(edgeId)",
                    item: "Stair handrail \(edgeId)",
                    severity: .safetyHazard,
                    currentValue: "no handrail",
                    targetValue: "handrail required at \(rules.handrailRequiredRiserCount) risers",
                    codeSection: rules.handrailCodeSection,
                    fix: "Add a stair handrail.",
                    confidence: .high,
                    evidence: nil,
                    source: source
                )
            )
        }

        return findings
    }

    private static func actualRiserHeight(_ stair: StairConfig) -> Double {
        guard let totalRise = stair.totalRiseInches,
              totalRise > 0 else {
            return stair.risePerStep
        }
        let spec = StairCalculator.calculate(
            totalRise: totalRise,
            width: stair.width,
            risePerStep: stair.risePerStep,
            runPerTread: stair.runPerTread,
            treadCountOverride: stair.treadCount
        )
        return spec.risePerStep
    }

    private static func resolvedRiserCount(_ stair: StairConfig) -> Int {
        if let treadCount = stair.treadCount {
            return treadCount
        }
        guard let totalRise = stair.totalRiseInches,
              totalRise > 0 else {
            return 0
        }
        return StairConfig.calculateTreadCount(totalRise: totalRise, risePerStep: stair.risePerStep)
    }

    private static func source(for mode: ComplianceEngine.Mode) -> FindingSource {
        mode == .asBuilt ? .userEntered : .measured
    }

    private static func formatInches(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.005 {
            return "\(Int(rounded))\""
        }

        var text = String(format: "%.2f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return "\(text)\""
    }
}
