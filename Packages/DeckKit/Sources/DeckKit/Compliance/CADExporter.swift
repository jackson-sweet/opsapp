import Foundation

public enum CADExportFormat: String, Codable, CaseIterable {
    case vectorPDF
    case dwg
    case dxf
}

public enum CADExportResult: Equatable {
    case data(Data)
    case requiresPaidConverter(format: CADExportFormat, note: String)
}

public enum CADExporter {
    public static func export(
        _ data: DeckDrawingData,
        format: CADExportFormat,
        sheets: [PlanSheetKind],
        titleBlock: TitleBlock,
        package: CodePackage
    ) -> CADExportResult {
        switch format {
        case .vectorPDF:
            let report = complianceReport(for: data, titleBlock: titleBlock, package: package)
            let pdf = PlanSetEngine.renderPermitSet(
                data,
                compliance: report,
                sheets: sheets,
                titleBlock: titleBlock,
                package: package
            )
            return .data(pdf)
        case .dwg, .dxf:
            return .requiresPaidConverter(
                format: format,
                note: "\(format.rawValue.uppercased()) export requires a paid CAD converter and explicit cost approval before configuration."
            )
        }
    }

    private static func complianceReport(
        for data: DeckDrawingData,
        titleBlock: TitleBlock,
        package: CodePackage
    ) -> ComplianceReport {
        let edition = packageEdition(package)
        if let report = data.permitMeta?.lastComplianceResult,
           report.packageEdition == edition {
            return report
        }

        return ComplianceReport(
            mode: .design,
            packageEdition: edition,
            generatedAt: titleBlock.generatedDate,
            findings: [
                ComplianceFinding(
                    id: "cad_export:compliance:not_run",
                    item: "code check",
                    severity: .notAssessable,
                    currentValue: nil,
                    targetValue: nil,
                    codeSection: "not run",
                    fix: "Run code check before permit submission.",
                    confidence: .low,
                    evidence: nil,
                    source: .notAssessable
                )
            ],
            summaryStatement: "code check not run",
            disclaimer: ComplianceStrings.disclaimer
        )
    }

    private static func packageEdition(_ package: CodePackage) -> String {
        package.edition ?? package.jurisdictionId
    }
}
