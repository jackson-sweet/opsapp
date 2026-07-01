import Foundation

enum StructuralChecks {
    static func evaluate(
        _ data: DeckDrawingData,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        framingFindings(data.framing, mode: mode, package: package)
            + footingFindings(data.footings, mode: mode, package: package)
    }

    private static func framingFindings(
        _ framing: FramingPlan?,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        guard let framing else { return [] }

        return framing.members.flatMap { set in
            set.members.compactMap { member in
                finding(for: member, levelId: set.levelId, mode: mode, package: package)
            }
        }
    }

    private static func finding(
        for member: FramingMember,
        levelId: String,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> ComplianceFinding? {
        let id = "structural:framing:\(levelId):\(member.id)"
        let item = "\(member.role.complianceLabel) \(member.id)"

        guard let sizing = member.sizing else {
            return ComplianceFinding(
                id: id,
                item: item,
                severity: .notAssessable,
                currentValue: nil,
                targetValue: nil,
                codeSection: package.edition ?? package.jurisdictionId,
                fix: "Run structural sizing before permit review.",
                confidence: .low,
                evidence: nil,
                source: .notAssessable
            )
        }

        switch sizing.outcome {
        case let .outOfEnvelope(reason, citation):
            return ComplianceFinding(
                id: id,
                item: item,
                severity: .safetyHazard,
                currentValue: reason,
                targetValue: nil,
                codeSection: citation.codeSection,
                fix: "Have this member reviewed by a licensed engineer.",
                confidence: .high,
                evidence: nil,
                source: source(for: mode)
            )
        case let .ok(value, citation, _):
            guard value.utilization > 1 else { return nil }
            return ComplianceFinding(
                id: id,
                item: item,
                severity: .safetyHazard,
                currentValue: "\(Int((value.utilization * 100).rounded()))% utilization",
                targetValue: "100% maximum",
                codeSection: citation.codeSection,
                fix: "Resize the member or reduce the span/load.",
                confidence: .high,
                evidence: nil,
                source: source(for: mode)
            )
        }
    }

    private static func footingFindings(
        _ footings: FootingPlan?,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        guard let footings else { return [] }

        return footings.footings.compactMap { footing in
            guard footing.sizing == nil else { return nil }
            return ComplianceFinding(
                id: "structural:footing:\(footing.id)",
                item: "Footing \(footing.id)",
                severity: .notAssessable,
                currentValue: nil,
                targetValue: nil,
                codeSection: package.edition ?? package.jurisdictionId,
                fix: mode == .asBuilt
                    ? "Verify footing size and depth on site."
                    : "Run footing sizing before permit review.",
                confidence: .low,
                evidence: nil,
                source: .notAssessable
            )
        }
    }

    private static func source(for mode: ComplianceEngine.Mode) -> FindingSource {
        mode == .asBuilt ? .userEntered : .measured
    }
}

private extension FramingRole {
    var complianceLabel: String {
        switch self {
        case .joist: "Joist"
        case .beam: "Beam"
        case .post: "Post"
        case .ledger: "Ledger"
        case .rimBand: "Rim band"
        case .blocking: "Blocking"
        case .bridging: "Bridging"
        case .cantilever: "Cantilever"
        }
    }
}
