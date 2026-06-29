import CoreGraphics
import XCTest
@testable import DeckKit

final class CodeComplianceEngineTests: XCTestCase {
    func test_evaluate_reportsJoistSpanViolationWithInlineAnchorAndTokens() throws {
        let data = drawingData(
            member: FramingMember(
                id: "joist-east-001",
                role: .joist,
                start: CGPoint(x: 10, y: 20),
                end: CGPoint(x: 130, y: 20),
                nominalSize: .twoByEight,
                spacingInchesOC: 16
            )
        )
        let profile = profile(maxJoistSpanInches: 119)

        let report = DeckCodeCheckEngine.evaluate(data, profile: profile, settings: .enabled)

        XCTAssertTrue(report.evaluated)
        XCTAssertEqual(report.profileId, "profile-north-ops")
        XCTAssertEqual(report.jurisdictionId, "jurisdiction-north-ops")
        XCTAssertEqual(report.findings.count, 1)

        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.id, "code:jurisdiction-north-ops:rule-joist-span:level-main:joist-east-001")
        XCTAssertEqual(finding.element.kind, .framingMember)
        XCTAssertEqual(finding.element.memberId, "joist-east-001")
        XCTAssertEqual(finding.element.levelId, "level-main")
        XCTAssertEqual(finding.element.role, .joist)
        XCTAssertEqual(finding.jurisdictionId, "jurisdiction-north-ops")
        XCTAssertEqual(finding.ruleToken, "deck.code.rule.joistSpan.max")
        XCTAssertEqual(finding.citation?.authorityToken, "deck.code.authority.northOps")
        XCTAssertEqual(finding.citation?.sectionToken, "deck.code.section.joistSpan.synthetic")
        XCTAssertEqual(finding.source?.profileSourceToken, "deck.code.source.syntheticProfile")
        XCTAssertEqual(finding.severity, .violation)
        XCTAssertEqual(finding.measurement.metric, .memberSpan)
        XCTAssertEqual(finding.measurement.measuredInches, 120, accuracy: 0.000001)
        XCTAssertEqual(finding.measurement.allowedInches, 119, accuracy: 0.000001)
        XCTAssertEqual(finding.annotationToken.rawValue, "deck.code.annotation.violation.memberInline")
        XCTAssertEqual(finding.messageToken.rawValue, "deck.code.message.memberSpanExceeded")
        XCTAssertEqual(finding.lineAnchor, DeckCodeLineAnchor(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 130, y: 20)
        ))
    }

    func test_disabledSettings_returnsEvaluatedDisabledReportWithoutFindings() {
        let data = drawingData(
            member: FramingMember(
                id: "joist-east-001",
                role: .joist,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 240, y: 0)
            )
        )

        let report = DeckCodeCheckEngine.evaluate(data, profile: profile(maxJoistSpanInches: 96), settings: .disabled)

        XCTAssertTrue(report.evaluated)
        XCTAssertEqual(report.settings, .disabled)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func test_profileLimitDrivesSpanEvaluation() {
        let data = drawingData(
            member: FramingMember(
                id: "joist-east-001",
                role: .joist,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 120, y: 0)
            )
        )

        let restrictive = DeckCodeCheckEngine.evaluate(data, profile: profile(maxJoistSpanInches: 119), settings: .enabled)
        let permissive = DeckCodeCheckEngine.evaluate(data, profile: profile(maxJoistSpanInches: 121), settings: .enabled)

        XCTAssertEqual(restrictive.findings.count, 1)
        XCTAssertTrue(permissive.findings.isEmpty)
    }

    func test_codeProfileAndReport_roundTripCodableWithStableTokens() throws {
        let profile = profile(maxJoistSpanInches: 119)
        let data = drawingData(
            member: FramingMember(
                id: "joist-east-001",
                role: .joist,
                start: CGPoint(x: 10, y: 20),
                end: CGPoint(x: 130, y: 20)
            )
        )
        let report = DeckCodeCheckEngine.evaluate(data, profile: profile, settings: .enabled)

        let decodedProfile = try roundTrip(profile)
        let decodedReport = try roundTrip(report)

        XCTAssertEqual(decodedProfile, profile)
        XCTAssertEqual(decodedReport, report)
        XCTAssertEqual(decodedReport.findings.first?.annotationToken.rawValue, "deck.code.annotation.violation.memberInline")
        XCTAssertEqual(decodedReport.findings.first?.messageToken.rawValue, "deck.code.message.memberSpanExceeded")
    }

    private func drawingData(member: FramingMember) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [member]
                )
            ],
            generationSource: .manual
        )
        return data
    }

    private func profile(maxJoistSpanInches: Double) -> DeckCodeProfile {
        DeckCodeProfile(
            id: "profile-north-ops",
            jurisdiction: DeckJurisdiction(id: "jurisdiction-north-ops"),
            source: DeckCodeProfileSource(profileSourceToken: "deck.code.source.syntheticProfile"),
            rules: [
                DeckCodeRule(
                    id: "rule-joist-span",
                    token: "deck.code.rule.joistSpan.max",
                    scope: DeckCodeRuleScope(memberRole: .joist),
                    metric: .memberSpan,
                    limit: .maximumInches(maxJoistSpanInches),
                    severity: .violation,
                    citation: DeckCodeCitation(
                        authorityToken: "deck.code.authority.northOps",
                        sectionToken: "deck.code.section.joistSpan.synthetic"
                    ),
                    annotationToken: DeckCodeAnnotationToken("deck.code.annotation.violation.memberInline"),
                    messageToken: DeckCodeMessageToken("deck.code.message.memberSpanExceeded")
                )
            ]
        )
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
