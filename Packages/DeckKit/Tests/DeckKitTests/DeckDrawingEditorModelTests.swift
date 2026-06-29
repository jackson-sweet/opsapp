import CoreGraphics
import XCTest
@testable import DeckKit

@MainActor
final class DeckDrawingEditorModelTests: XCTestCase {
    func testDrawLineCreatesPersistedDimensionedEdge() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: DeckDrawingData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        model.beginLine(at: CGPoint(x: 100, y: 100))
        model.updateLine(to: CGPoint(x: 148, y: 100))
        model.endLine(at: CGPoint(x: 148, y: 100))

        XCTAssertEqual(model.drawingData.vertices.count, 2)
        XCTAssertEqual(model.drawingData.edges.count, 1)
        XCTAssertEqual(model.drawingData.edges.first?.dimension, 24)
        XCTAssertEqual(persisted.last?.edges.count, 1)
    }

    func testClosingLineSnapsToExistingVertexAndClosesSurface() {
        let model = DeckDrawingEditorModel(drawingData: DeckDrawingData(), capabilities: .full)

        drawLine(model, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 360, y: 120))
        drawLine(model, from: CGPoint(x: 360, y: 120), to: CGPoint(x: 360, y: 360))
        drawLine(model, from: CGPoint(x: 360, y: 360), to: CGPoint(x: 120, y: 360))
        drawLine(model, from: CGPoint(x: 120, y: 360), to: CGPoint(x: 120, y: 120))

        XCTAssertEqual(model.drawingData.vertices.count, 4)
        XCTAssertEqual(model.drawingData.edges.count, 4)
        XCTAssertTrue(model.drawingData.isClosed)
        XCTAssertTrue(model.drawingData.hasAnyClosedSurface)
    }

    func testGenerateFramingRequiresFullAuthoringCapability() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let lightModel = DeckDrawingEditorModel(drawingData: data, capabilities: .light)
        let fullModel = DeckDrawingEditorModel(drawingData: data, capabilities: .full)

        XCTAssertFalse(lightModel.generateFraming())
        XCTAssertNil(lightModel.drawingData.framing)

        XCTAssertTrue(fullModel.generateFraming())
        XCTAssertFalse(fullModel.drawingData.framing?.members.flatMap(\.members).isEmpty ?? true)
    }

    func testCodeComplianceRequiresFullAuthoringCapabilityAndInjectedProfile() {
        let data = drawingDataWithJoistSpan(points: 120)

        let lightModel = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .light,
            codeProfile: codeProfile(maxJoistSpanInches: 96)
        )
        let fullModelWithoutProfile = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full
        )
        let fullModel = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            codeProfile: codeProfile(maxJoistSpanInches: 96)
        )

        XCTAssertFalse(lightModel.canRunCodeChecks)
        XCTAssertNil(lightModel.codeReport)
        XCTAssertFalse(fullModelWithoutProfile.canRunCodeChecks)
        XCTAssertNil(fullModelWithoutProfile.codeReport)
        XCTAssertTrue(fullModel.canRunCodeChecks)
        XCTAssertEqual(fullModel.codeCheckSettings, .enabled)
        XCTAssertEqual(fullModel.visibleCodeFindings.map(\.element.memberId), ["joist-1"])
    }

    func testCodeOverlayToggleSuppressesVisibleFindingsWithoutMutatingDrawingData() {
        let data = drawingDataWithJoistSpan(points: 120)
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            codeProfile: codeProfile(maxJoistSpanInches: 96),
            onPersist: { persisted.append($0) }
        )

        XCTAssertEqual(model.codeReport?.settings, .enabled)
        XCTAssertEqual(model.visibleCodeFindings.count, 1)

        model.setCodeChecksEnabled(false)

        XCTAssertEqual(model.codeCheckSettings, .disabled)
        XCTAssertEqual(model.codeReport?.settings, .disabled)
        XCTAssertTrue(model.visibleCodeFindings.isEmpty)
        XCTAssertTrue(persisted.isEmpty)

        model.setCodeChecksEnabled(true)

        XCTAssertEqual(model.codeCheckSettings, .enabled)
        XCTAssertEqual(model.visibleCodeFindings.count, 1)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testCodeReportRefreshesAfterFramingRegeneration() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            codeProfile: codeProfile(maxJoistSpanInches: 1)
        )

        XCTAssertNil(model.drawingData.framing)
        XCTAssertTrue(model.visibleCodeFindings.isEmpty)

        XCTAssertTrue(model.generateFraming())

        XCTAssertFalse(model.visibleCodeFindings.isEmpty)
        XCTAssertTrue(model.visibleCodeFindings.allSatisfy { $0.element.kind == .framingMember })
    }

    private func drawLine(_ model: DeckDrawingEditorModel, from start: CGPoint, to end: CGPoint) {
        model.beginLine(at: start)
        model.updateLine(to: end)
        model.endLine(at: end)
    }

    private func drawingDataWithJoistSpan(points: Double) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [
                        FramingMember(
                            id: "joist-1",
                            role: .joist,
                            start: .zero,
                            end: CGPoint(x: points, y: 0)
                        ),
                    ]
                )
            ],
            generationSource: .manual
        )
        return data
    }

    private func codeProfile(maxJoistSpanInches: Double) -> DeckCodeProfile {
        DeckCodeProfile(
            id: "profile-inline",
            jurisdiction: DeckJurisdiction(id: "jurisdiction-inline"),
            source: DeckCodeProfileSource(profileSourceToken: "deck.code.source.testProfile"),
            rules: [
                DeckCodeRule(
                    id: "joist-span",
                    token: "deck.code.rule.joistSpan.max",
                    scope: DeckCodeRuleScope(memberRole: .joist),
                    metric: .memberSpan,
                    limit: .maximumInches(maxJoistSpanInches),
                    severity: .violation,
                    citation: DeckCodeCitation(
                        authorityToken: "deck.code.authority.test",
                        sectionToken: "deck.code.section.test"
                    ),
                    annotationToken: DeckCodeAnnotationToken("deck.code.annotation.violation.memberInline"),
                    messageToken: DeckCodeMessageToken("deck.code.message.memberSpanExceeded")
                )
            ]
        )
    }
}
