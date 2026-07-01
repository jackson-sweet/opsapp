import Foundation

enum LedgerChecks {
    static func evaluate(
        _ data: DeckDrawingData,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        guard let ledger = data.house?.ledger else { return [] }

        if !ledger.attachmentAllowed {
            return [
                ComplianceFinding(
                    id: "ledger:attachment",
                    item: "Ledger attachment",
                    severity: .safetyHazard,
                    currentValue: ledger.cladding.rawValue,
                    targetValue: "freestanding required",
                    codeSection: package.ledgerRules.codeSection,
                    fix: "Use a freestanding house-side beam.",
                    confidence: .high,
                    evidence: nil,
                    source: source(for: mode)
                )
            ]
        }

        if mode == .asBuilt {
            return concealedLedgerFindings(package: package)
        }

        var findings: [ComplianceFinding] = []
        if ledger.fastenerSchedule?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            findings.append(
                ComplianceFinding(
                    id: "ledger:fastener-schedule",
                    item: "Ledger fasteners",
                    severity: .notAssessable,
                    currentValue: nil,
                    targetValue: nil,
                    codeSection: package.ledgerRules.codeSection,
                    fix: "Enter ledger fastener schedule before permit review.",
                    confidence: .low,
                    evidence: nil,
                    source: .notAssessable
                )
            )
        }

        if let lateralConnectors = ledger.lateralConnectors {
            if lateralConnectors < package.ledgerRules.minLateralConnectors {
                findings.append(
                    ComplianceFinding(
                        id: "ledger:lateral-connectors",
                        item: "Ledger lateral connectors",
                        severity: .safetyHazard,
                        currentValue: connectorCount(lateralConnectors),
                        targetValue: "\(connectorCount(package.ledgerRules.minLateralConnectors)) minimum",
                        codeSection: package.ledgerRules.codeSection,
                        fix: "Add lateral connectors to meet the selected package.",
                        confidence: .high,
                        evidence: nil,
                        source: source(for: mode)
                    )
                )
            }
        } else {
            findings.append(
                ComplianceFinding(
                    id: "ledger:lateral-connectors",
                    item: "Ledger lateral connectors",
                    severity: .notAssessable,
                    currentValue: nil,
                    targetValue: nil,
                    codeSection: package.ledgerRules.codeSection,
                    fix: "Enter lateral connector count before permit review.",
                    confidence: .low,
                    evidence: nil,
                    source: .notAssessable
                )
            )
        }

        return findings
    }

    private static func concealedLedgerFindings(package: CodePackage) -> [ComplianceFinding] {
        [
            ComplianceFinding(
                id: "ledger:fastener-schedule",
                item: "Ledger fasteners",
                severity: .notAssessable,
                currentValue: nil,
                targetValue: nil,
                codeSection: package.ledgerRules.codeSection,
                fix: "Verify concealed ledger fasteners on site.",
                confidence: .low,
                evidence: nil,
                source: .notAssessable
            ),
            ComplianceFinding(
                id: "ledger:lateral-connectors",
                item: "Ledger lateral connectors",
                severity: .notAssessable,
                currentValue: nil,
                targetValue: nil,
                codeSection: package.ledgerRules.codeSection,
                fix: "Verify lateral connectors on site.",
                confidence: .low,
                evidence: nil,
                source: .notAssessable
            )
        ]
    }

    private static func source(for mode: ComplianceEngine.Mode) -> FindingSource {
        mode == .asBuilt ? .userEntered : .measured
    }

    private static func connectorCount(_ count: Int) -> String {
        count == 1 ? "1 connector" : "\(count) connectors"
    }
}
