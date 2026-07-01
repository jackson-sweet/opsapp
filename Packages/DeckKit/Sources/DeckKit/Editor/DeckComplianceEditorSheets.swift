import Foundation
import OPSDesignKit
import SwiftUI

public struct ComplianceReportSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    private let package: CodePackage?

    public init(model: DeckDrawingEditorModel, package: CodePackage?) {
        self.model = model
        self.package = package
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "CODE CHECK"),
            subtitle: String(localized: "Findings, citations, current values, target values.")
        ) {
            if let package {
                complianceContent(package)
            } else {
                CompliancePackageUnavailableView()
            }
        }
    }

    @ViewBuilder
    private func complianceContent(_ package: CodePackage) -> some View {
        if model.requiresComplianceDisclaimer(for: package) {
            ComplianceDisclaimerGatePanel(model: model, package: package)
        } else {
            ComplianceReportActionPanel(
                title: String(localized: "// DESIGN CHECK"),
                buttonTitle: String(localized: "RUN CODE CHECK"),
                action: {
                    _ = model.runCompliance(mode: .design, package: package)
                }
            )

            if let report = model.cachedComplianceReport {
                ComplianceReportPanel(report: report)
            } else {
                DeckSurfaceEditorEmptyState(
                    title: String(localized: "No report"),
                    message: String(localized: "Run a code check to generate findings for this package.")
                )
            }
        }
    }
}

public struct AsBuiltAuditWizardSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    private let package: CodePackage?

    public init(model: DeckDrawingEditorModel, package: CodePackage?) {
        self.model = model
        self.package = package
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "AS-BUILT AUDIT"),
            subtitle: String(localized: "Existing deck. Visible checks only. Hidden work marked verify.")
        ) {
            if let package {
                asBuiltContent(package)
            } else {
                CompliancePackageUnavailableView()
            }
        }
    }

    @ViewBuilder
    private func asBuiltContent(_ package: CodePackage) -> some View {
        if model.requiresComplianceDisclaimer(for: package) {
            ComplianceDisclaimerGatePanel(model: model, package: package)
        } else {
            ComplianceReportActionPanel(
                title: String(localized: "// CURRENT DECK"),
                buttonTitle: String(localized: "RUN AS-BUILT AUDIT"),
                action: {
                    _ = model.runCompliance(mode: .asBuilt, package: package)
                }
            )

            if let report = model.cachedComplianceReport, report.mode == .asBuilt {
                ComplianceReportPanel(report: report)
            } else {
                DeckSurfaceEditorEmptyState(
                    title: String(localized: "No audit"),
                    message: String(localized: "Run the audit after capturing visible geometry and known framing.")
                )
            }
        }
    }
}

public struct PermitPlanSetSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @State private var generatedPDFBytes: Int?

    private let package: CodePackage?
    private let projectName: String

    public init(
        model: DeckDrawingEditorModel,
        package: CodePackage?,
        projectName: String?
    ) {
        self.model = model
        self.package = package
        self.projectName = projectName?.isEmpty == false ? projectName ?? "" : String(localized: "Deck permit set")
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "PERMIT SET"),
            subtitle: String(localized: "Plan sheets, summary, disclaimer stamp.")
        ) {
            if let package {
                permitContent(package)
            } else {
                CompliancePackageUnavailableView()
            }
        }
    }

    @ViewBuilder
    private func permitContent(_ package: CodePackage) -> some View {
        if model.requiresComplianceDisclaimer(for: package) {
            ComplianceDisclaimerGatePanel(model: model, package: package)
        } else {
            DeckSurfaceEditorPanel {
                DeckSurfaceEditorSectionHeader(String(localized: "// SHEETS"))

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(PlanSheetKind.allCases, id: \.rawValue) { sheet in
                        ComplianceValueRow(
                            label: sheet.editorTitle,
                            value: String(localized: "Included")
                        )
                    }

                    Button {
                        let pdf = model.generatePermitSet(
                            sheets: PlanSheetKind.allCases,
                            titleBlock: titleBlock(for: package),
                            package: package
                        )
                        generatedPDFBytes = pdf?.count
                    } label: {
                        DeckSurfaceEditorPrimaryLabel(String(localized: "GENERATE PERMIT SET"))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let generatedPDFBytes {
                DeckSurfaceEditorPanel {
                    DeckSurfaceEditorSectionHeader(String(localized: "// EXPORT"))
                    ComplianceValueRow(
                        label: String(localized: "PDF"),
                        value: ByteCountFormatter.string(fromByteCount: Int64(generatedPDFBytes), countStyle: .file)
                    )
                    Text(ComplianceStrings.disclaimer)
                        .font(OPSStyle.Typography.fieldMetadata)
                        .foregroundStyle(OPSStyle.Colors.text2)
                }
            }
        }
    }

    private func titleBlock(for package: CodePackage) -> TitleBlock {
        TitleBlock(
            projectName: projectName,
            packageEdition: package.edition ?? package.jurisdictionId,
            generatedDate: Date(),
            disclaimer: ComplianceStrings.disclaimer,
            peStamp: model.drawingData.permitMeta?.peStampRequest
        )
    }
}

public struct PEStampRequestSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @State private var reason = ""

    public init(model: DeckDrawingEditorModel) {
        self.model = model
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "PE REVIEW"),
            subtitle: String(localized: "Request licensed engineer review. No self-certification.")
        ) {
            DeckSurfaceEditorPanel {
                DeckSurfaceEditorSectionHeader(String(localized: "// REQUEST"))

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    TextField(String(localized: "Reason"), text: $reason, axis: .vertical)
                        .font(OPSStyle.Typography.fieldDataValue)
                        .foregroundStyle(OPSStyle.Colors.text)
                        .lineLimit(3...5)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.surfaceInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))

                    if model.shouldSurfacePEStampRequest {
                        ComplianceValueRow(
                            label: String(localized: "Trigger"),
                            value: String(localized: "Engineer review flagged")
                        )
                    }

                    Button {
                        _ = model.requestPEStamp(
                            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason,
                            requestedAt: Date()
                        )
                    } label: {
                        DeckSurfaceEditorPrimaryLabel(String(localized: "REQUEST REVIEW"))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let request = model.drawingData.permitMeta?.peStampRequest,
               request.requested {
                DeckSurfaceEditorPanel {
                    DeckSurfaceEditorSectionHeader(String(localized: "// STATUS"))
                    ComplianceValueRow(
                        label: String(localized: "Request"),
                        value: String(localized: "Queued")
                    )
                    ComplianceValueRow(
                        label: String(localized: "Reason"),
                        value: request.reason ?? String(localized: "—")
                    )
                }
            }
        }
        .onAppear {
            reason = model.drawingData.permitMeta?.peStampRequest?.reason ?? ""
        }
    }
}

private struct ComplianceDisclaimerGatePanel: View {
    @ObservedObject var model: DeckDrawingEditorModel
    let package: CodePackage

    var body: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// DISCLAIMER"))

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(ComplianceStrings.disclaimer)
                    .font(OPSStyle.Typography.fieldMetadata)
                    .foregroundStyle(OPSStyle.Colors.text2)

                ComplianceValueRow(
                    label: String(localized: "Package"),
                    value: package.edition ?? package.jurisdictionId
                )

                Button {
                    _ = model.acknowledgeComplianceDisclaimer(for: package, at: Date())
                } label: {
                    DeckSurfaceEditorPrimaryLabel(String(localized: "ACKNOWLEDGE"))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ComplianceReportActionPanel: View {
    let title: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(title)

            Button(action: action) {
                DeckSurfaceEditorPrimaryLabel(buttonTitle)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ComplianceReportPanel: View {
    let report: ComplianceReport

    var body: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// REPORT"))

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                ComplianceValueRow(
                    label: String(localized: "Summary"),
                    value: report.summaryStatement
                )
                ComplianceValueRow(
                    label: String(localized: "Package"),
                    value: report.packageEdition
                )
                ComplianceValueRow(
                    label: String(localized: "Mode"),
                    value: report.mode.editorTitle
                )

                if report.findings.isEmpty {
                    ComplianceFindingEmptyRow()
                } else {
                    ForEach(report.findings) { finding in
                        ComplianceFindingCard(finding: finding)
                    }
                }

                Text(report.disclaimer)
                    .font(OPSStyle.Typography.fieldMetadata)
                    .foregroundStyle(OPSStyle.Colors.text2)
            }
        }
    }
}

private struct ComplianceFindingCard: View {
    let finding: ComplianceFinding

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(finding.item.uppercased())
                        .font(OPSStyle.Typography.fieldPanelTitle)
                        .foregroundStyle(OPSStyle.Colors.text)
                    Text(finding.codeSection)
                        .font(OPSStyle.Typography.fieldMetadata)
                        .foregroundStyle(OPSStyle.Colors.text2)
                }
                Spacer(minLength: OPSStyle.Layout.spacing2)
                ComplianceSeverityBadge(severity: finding.severity)
            }

            ComplianceValueRow(
                label: String(localized: "Current"),
                value: finding.currentValue ?? String(localized: "—")
            )
            ComplianceValueRow(
                label: String(localized: "Target"),
                value: finding.targetValue ?? String(localized: "—")
            )
            ComplianceValueRow(
                label: String(localized: "Fix"),
                value: finding.fix ?? String(localized: "—")
            )
            ComplianceValueRow(
                label: String(localized: "Confidence"),
                value: finding.confidence.rawValue.uppercased()
            )
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(finding.severity.lineColor, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }
}

private struct ComplianceFindingEmptyRow: View {
    var body: some View {
        Text(ComplianceStrings.noFailures.uppercased())
            .font(OPSStyle.Typography.fieldPanelTitle)
            .foregroundStyle(OPSStyle.Colors.oliveTextM)
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.oliveFillM)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.oliveLineM, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }
}

private struct ComplianceSeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.editorTitle)
            .font(OPSStyle.Typography.fieldBadge)
            .foregroundStyle(severity.textColor)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
            .background(severity.fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(severity.lineColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
    }
}

private struct ComplianceValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.fieldCategory)
                .foregroundStyle(OPSStyle.Colors.text3)
                .frame(width: OPSStyle.Layout.touchTargetLarge * 2, alignment: .leading)
            Text(value)
                .font(OPSStyle.Typography.fieldDataValue)
                .foregroundStyle(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CompliancePackageUnavailableView: View {
    var body: some View {
        DeckSurfaceEditorEmptyState(
            title: String(localized: "Jurisdiction not set"),
            message: String(localized: "Select the active code package before running checks or generating permit sheets.")
        )
    }
}

private extension ComplianceEngine.Mode {
    var editorTitle: String {
        switch self {
        case .design: return String(localized: "DESIGN")
        case .asBuilt: return String(localized: "AS-BUILT")
        }
    }
}

private extension PlanSheetKind {
    var editorTitle: String {
        switch self {
        case .planView: return String(localized: "PLAN VIEW")
        case .framingPlan: return String(localized: "FRAMING PLAN")
        case .elevation: return String(localized: "ELEVATION")
        case .crossSection: return String(localized: "CROSS SECTION")
        case .sitePlan: return String(localized: "SITE PLAN")
        case .detailCallout: return String(localized: "DETAIL CALLOUT")
        }
    }
}

private extension Severity {
    var editorTitle: String {
        switch self {
        case .safetyHazard: return String(localized: "FAIL")
        case .marginal: return String(localized: "MARGINAL")
        case .minor: return String(localized: "MINOR")
        case .notAssessable: return String(localized: "VERIFY")
        }
    }

    var textColor: Color {
        switch self {
        case .safetyHazard:
            return OPSStyle.Colors.roseTextM
        case .marginal:
            return OPSStyle.Colors.tanTextM
        case .minor:
            return OPSStyle.Colors.text2
        case .notAssessable:
            return OPSStyle.Colors.text3
        }
    }

    var fillColor: Color {
        switch self {
        case .safetyHazard:
            return OPSStyle.Colors.roseFillM
        case .marginal:
            return OPSStyle.Colors.tanFillM
        case .minor:
            return OPSStyle.Colors.fillNeutralDim
        case .notAssessable:
            return OPSStyle.Colors.fillNeutralDim
        }
    }

    var lineColor: Color {
        switch self {
        case .safetyHazard:
            return OPSStyle.Colors.roseLineM
        case .marginal:
            return OPSStyle.Colors.tanLineM
        case .minor:
            return OPSStyle.Colors.nestedBorder
        case .notAssessable:
            return OPSStyle.Colors.line
        }
    }
}
