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

    func testSurfaceSheet_hiddenWhenCapabilityAbsent() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let lightModel = DeckDrawingEditorModel(drawingData: data, capabilities: .light)
        let fullModel = DeckDrawingEditorModel(drawingData: data, capabilities: .full)

        XCTAssertEqual(lightModel.surfaceEditorEntries.map(\.kind), [.opsDecksProUpsell])
        XCTAssertEqual(lightModel.surfaceEditorEntries.first?.title, "Available in OPS Decks Pro")
        XCTAssertEqual(lightModel.surfaceEditorEntries.filter(\.isUpsell).count, 1)
        XCTAssertFalse(lightModel.surfaceEditorEntries.contains { $0.kind == .surfacePattern })
        XCTAssertFalse(lightModel.surfaceEditorEntries.contains { $0.kind == .stairDetail })
        XCTAssertFalse(lightModel.surfaceEditorEntries.contains { $0.kind == .surfaceFeatures })
        XCTAssertFalse(lightModel.surfaceEditorEntries.contains { $0.kind == .overheadStructure })

        XCTAssertEqual(fullModel.surfaceEditorEntries.map(\.kind), [
            .surfacePattern,
            .stairDetail,
            .surfaceFeatures,
            .overheadStructure,
        ])
        XCTAssertFalse(fullModel.surfaceEditorEntries.contains { $0.isUpsell })
    }

    func testEngineNeverInvokedInLight() throws {
        let data = drawingDataWithDeckEdge()
        let overhead = overheadStructure()
        let stairConfig = StairConfig(
            width: 48,
            totalRiseInches: 36,
            stringerStyle: .closed,
            stringerMaterial: .steel,
            treadMaterial: .twoBySix
        )
        let package = CodePackage(jurisdictionId: "US-IRC", edition: "IRC 2021")
        var engineCalls = 0
        var persisted: [DeckDrawingData] = []

        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .light,
            onPersist: { persisted.append($0) },
            surfaceEngineRunner: DeckSurfaceEditorEngineRunner(
                overheadSize: { structure, load, codePackage in
                    engineCalls += 1
                    return OverheadSizingCoordinator.size(structure, load: load, package: codePackage)
                },
                stairDetail: { base, treadType, treadMaterial, spacing, species, grade, codePackage, stringerType in
                    engineCalls += 1
                    return StairDetailEngine.detail(
                        base: base,
                        treadType: treadType,
                        treadMaterial: treadMaterial,
                        stringerSpacingInchesOC: spacing,
                        species: species,
                        grade: grade,
                        package: codePackage,
                        stringerType: stringerType
                    )
                }
            )
        )

        XCTAssertFalse(model.setSurfacePattern(.diagonal, forSurfaceId: "surface-1"))
        XCTAssertFalse(model.setSurfaceFeatures(fastenerSystem: .hiddenClip, fascia: true, skirting: nil, finish: nil))
        XCTAssertNil(model.configureStairDetail(edgeId: "edge-1", config: stairConfig, package: package))
        XCTAssertFalse(model.upsertOverheadStructure(overhead, package: package))

        XCTAssertEqual(engineCalls, 0)
        XCTAssertNil(model.drawingData.surfaceFeatures)
        XCTAssertNil(model.drawingData.overhead)
        XCTAssertNil(model.drawingData.edges.first?.stairConfig)
        XCTAssertTrue(model.drawingData.framing?.members.flatMap(\.members).allSatisfy { $0.sizing == nil } ?? true)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testFullSurfaceEditorsPersistPhase6Blocks() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let surfaceId = try XCTUnwrap(data.detectedSurfaces.first?.id)
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.setSurfacePattern(.pictureFrame, forSurfaceId: surfaceId, pictureFrameCourses: 2))
        XCTAssertTrue(model.setSurfaceFeatures(
            fastenerSystem: .hiddenClip,
            fascia: true,
            skirting: SkirtingSpec(material: "privacy lattice", ventilated: true),
            finish: FinishSpec(kind: "cut-end seal", coats: 2),
            builtIn: BuiltInFeature(id: "bench-1", kind: .bench, polygon: data.orderedPositions, heightInches: 18),
            lighting: LightingPlan(fixtures: [.zero], transformerWatts: 60)
        ))
        XCTAssertTrue(model.upsertOverheadStructure(overheadStructure(), package: nil))

        XCTAssertEqual(model.drawingData.surfaceFeatures?.patterns.first?.pattern, .pictureFrame)
        XCTAssertEqual(model.drawingData.surfaceFeatures?.patterns.first?.pictureFrameCourses, 2)
        XCTAssertEqual(model.drawingData.surfaceFeatures?.fastenerSystem, .hiddenClip)
        XCTAssertEqual(model.drawingData.surfaceFeatures?.fascia, true)
        XCTAssertEqual(model.drawingData.surfaceFeatures?.skirting?.material, "privacy lattice")
        XCTAssertEqual(model.drawingData.surfaceFeatures?.finishes.first?.kind, "cut-end seal")
        XCTAssertEqual(model.drawingData.surfaceFeatures?.builtIns.first?.id, "bench-1")
        XCTAssertEqual(model.drawingData.surfaceFeatures?.lighting?.fixtures, [.zero])
        XCTAssertEqual(model.drawingData.surfaceFeatures?.lighting?.transformerWatts, 60)
        XCTAssertEqual(model.drawingData.overhead?.structures.first?.id, "overhead-1")
        XCTAssertEqual(persisted.last?.surfaceFeatures, model.drawingData.surfaceFeatures)
        XCTAssertEqual(persisted.last?.overhead, model.drawingData.overhead)
    }

    private func drawLine(_ model: DeckDrawingEditorModel, from start: CGPoint, to end: CGPoint) {
        model.beginLine(at: start)
        model.updateLine(to: end)
        model.endLine(at: end)
    }

    private func drawingDataWithDeckEdge() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        data.edges = [
            DeckEdge(id: "edge-1", startVertexId: "v1", endVertexId: "v2", dimension: 144),
        ]
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "level-main",
                    members: [
                        FramingMember(
                            id: "joist-1",
                            role: .joist,
                            start: .zero,
                            end: CGPoint(x: 120, y: 0)
                        ),
                    ]
                )
            ],
            generationSource: .manual
        )
        return data
    }

    private func overheadStructure() -> OverheadStructure {
        OverheadStructure(
            id: "overhead-1",
            kind: .pergola,
            framing: [
                FramingMember(
                    id: "beam-1",
                    role: .beam,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 120, y: 0)
                ),
            ]
        )
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
