import CoreGraphics
import Foundation

public enum DeckCodeCheckEngine {
    public static func evaluate(
        _ drawingData: DeckDrawingData,
        profile: DeckCodeProfile,
        settings: DeckCodeCheckSettings
    ) -> DeckCodeReport {
        guard settings == .enabled else {
            return DeckCodeReport(
                profileId: profile.id,
                jurisdictionId: profile.jurisdiction.id,
                settings: settings,
                evaluated: true,
                findings: []
            )
        }

        let scaleFactor = drawingData.effectiveScaleFactor
        let findings = evaluatedFramingFindings(
            framing: drawingData.framing,
            profile: profile,
            scaleFactor: scaleFactor
        )

        return DeckCodeReport(
            profileId: profile.id,
            jurisdictionId: profile.jurisdiction.id,
            settings: settings,
            evaluated: true,
            findings: findings
        )
    }

    private static func evaluatedFramingFindings(
        framing: FramingPlan?,
        profile: DeckCodeProfile,
        scaleFactor: Double
    ) -> [DeckCodeFinding] {
        guard let framing, scaleFactor > 0 else { return [] }

        var findings: [DeckCodeFinding] = []
        for memberSet in framing.members {
            for member in memberSet.members {
                for rule in profile.rules where rule.scope.matches(member) {
                    guard let finding = evaluate(
                        member,
                        levelId: memberSet.levelId,
                        rule: rule,
                        profile: profile,
                        scaleFactor: scaleFactor
                    ) else {
                        continue
                    }
                    findings.append(finding)
                }
            }
        }
        return findings
    }

    private static func evaluate(
        _ member: FramingMember,
        levelId: String,
        rule: DeckCodeRule,
        profile: DeckCodeProfile,
        scaleFactor: Double
    ) -> DeckCodeFinding? {
        switch (rule.metric, rule.limit.kind) {
        case (.memberSpan, .maximumInches):
            let measuredInches = memberSpanInches(member, scaleFactor: scaleFactor)
            let allowedInches = rule.limit.inches
            guard measuredInches > allowedInches else { return nil }

            return DeckCodeFinding(
                id: findingID(
                    jurisdictionId: profile.jurisdiction.id,
                    ruleId: rule.id,
                    levelId: levelId,
                    memberId: member.id
                ),
                element: DeckCodeElementReference(
                    memberId: member.id,
                    levelId: levelId,
                    role: member.role
                ),
                jurisdictionId: profile.jurisdiction.id,
                ruleId: rule.id,
                ruleToken: rule.token,
                severity: rule.severity,
                citation: rule.citation,
                source: profile.source,
                measurement: DeckCodeMeasurement(
                    metric: rule.metric,
                    measuredInches: measuredInches,
                    allowedInches: allowedInches
                ),
                annotationToken: rule.annotationToken,
                messageToken: rule.messageToken,
                lineAnchor: DeckCodeLineAnchor(start: member.start, end: member.end)
            )
        }
    }

    private static func memberSpanInches(_ member: FramingMember, scaleFactor: Double) -> Double {
        let dx = Double(member.end.x - member.start.x)
        let dy = Double(member.end.y - member.start.y)
        return sqrt(dx * dx + dy * dy) / scaleFactor
    }

    private static func findingID(
        jurisdictionId: String,
        ruleId: String,
        levelId: String,
        memberId: String
    ) -> String {
        [
            "code",
            jurisdictionId,
            ruleId,
            levelId,
            memberId,
        ].joined(separator: ":")
    }
}
