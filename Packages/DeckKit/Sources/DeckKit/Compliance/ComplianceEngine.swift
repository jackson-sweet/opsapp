import Foundation

public enum ComplianceEngine {
    public enum Mode: String, Codable {
        case design
        case asBuilt
    }

    public static func evaluate(
        _ data: DeckDrawingData,
        mode: Mode,
        package: CodePackage
    ) -> ComplianceReport {
        let findings: [ComplianceFinding] = []
        return ComplianceReport(
            mode: mode,
            packageEdition: package.edition ?? package.jurisdictionId,
            generatedAt: Date(),
            findings: findings,
            summaryStatement: summary(for: findings),
            disclaimer: ComplianceStrings.disclaimer
        )
    }

    private static func summary(for findings: [ComplianceFinding]) -> String {
        let concernCount = findings.filter { finding in
            finding.severity != .notAssessable
        }.count
        guard concernCount > 0 else { return ComplianceStrings.noFailures }
        if concernCount == 1 { return "1 code concern identified" }
        return "\(concernCount) code concerns identified"
    }
}
