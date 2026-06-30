import CoreGraphics
import XCTest
@testable import DeckKit

final class LedgerStrategyEngineTests: XCTestCase {
    func test_brickCladdingForcesFreestanding() throws {
        let edge = houseEdge(material: .brick)

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: 144,
            package: nil
        )

        guard case let .freestanding(detail, fallback) = strategy else {
            return XCTFail("Brick must not return an attach strategy.")
        }
        XCTAssertEqual(detail.cladding, .brick)
        XCTAssertFalse(detail.attachmentAllowed)
        XCTAssertEqual(fallback.beamMembers.single?.role, .beam)
    }

    func test_stoneCladdingForcesFreestanding() throws {
        let edge = houseEdge(material: .stone)

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: 144,
            package: nil
        )

        guard case let .freestanding(detail, _) = strategy else {
            return XCTFail("Stone must not return an attach strategy.")
        }
        XCTAssertEqual(detail.cladding, .stone)
        XCTAssertFalse(detail.attachmentAllowed)
    }

    func test_attachableCladdingsAllowAttach() throws {
        for material in [HouseEdgeMaterial.stucco, .hardie, .woodVertical, .vinyl] {
            let edge = houseEdge(material: material)

            let strategy = LedgerStrategyEngine.strategy(
                for: edge,
                houseSideBeamSpanInches: 144,
                package: nil
            )

            guard case let .attach(detail) = strategy else {
                return XCTFail("\(material) should allow a ledger detail.")
            }
            XCTAssertEqual(detail.cladding, material)
            XCTAssertTrue(detail.attachmentAllowed)
            XCTAssertNil(detail.fastenerSchedule)
        }
    }

    func test_parapetDefaultsToFreestanding() throws {
        let edge = houseEdge(material: .parapet)

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: 96,
            package: nil
        )

        guard case let .freestanding(detail, _) = strategy else {
            return XCTFail("Parapet must default to freestanding.")
        }
        XCTAssertEqual(detail.cladding, .parapet)
        XCTAssertFalse(detail.attachmentAllowed)
    }

    func test_freestandingEmitsBeamAndFootingsAlongHouseEdgeGeometry() throws {
        let data = drawingData(widthPoints: 144, scaleFactor: 1, material: .brick)
        let edge = try XCTUnwrap(data.edges.first)

        let strategy = LedgerStrategyEngine.strategy(for: edge, in: data, package: nil)

        guard case let .freestanding(_, fallback) = strategy else {
            return XCTFail("Brick must produce freestanding fallback geometry.")
        }

        let beam = try XCTUnwrap(fallback.beamMembers.single)
        XCTAssertEqual(beam.role, .beam)
        XCTAssertEqual(beam.start, CGPoint(x: 12, y: 24))
        XCTAssertEqual(beam.end, CGPoint(x: 156, y: 24))
        XCTAssertNil(beam.nominalSize)
        XCTAssertNil(beam.sizing)

        XCTAssertEqual(fallback.footingAnchors.count, 3)
        XCTAssertEqual(fallback.footingAnchors.map(\.position), [
            CGPoint(x: 12, y: 24),
            CGPoint(x: 84, y: 24),
            CGPoint(x: 156, y: 24)
        ])
        XCTAssertTrue(fallback.footingAnchors.allSatisfy { $0.sizing == nil })
    }

    func test_spanOnlyApiEmitsGeometryWithoutSizingClaim() throws {
        let edge = houseEdge(material: .brick)

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: 144,
            package: nil
        )

        guard case let .freestanding(_, fallback) = strategy else {
            return XCTFail("Brick must produce freestanding fallback geometry.")
        }

        let beam = try XCTUnwrap(fallback.beamMembers.single)
        XCTAssertEqual(beam.start, .zero)
        XCTAssertEqual(beam.end, CGPoint(x: 144, y: 0))
        XCTAssertNil(beam.nominalSize)
        XCTAssertNil(beam.sizing)
        XCTAssertEqual(fallback.footingAnchors.count, 3)
    }

    func test_rationaleIsObjectiveNegativeOnlyAndMentionsJurisdictionWhenPackageMissing() throws {
        let edge = houseEdge(material: .brick)

        let strategy = LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: 144,
            package: nil
        )

        guard case let .freestanding(_, fallback) = strategy else {
            return XCTFail("Brick must produce freestanding fallback geometry.")
        }

        XCTAssertEqual(
            fallback.rationale,
            "Brick cladding is not a code-recognized ledger substrate. OPS switches this edge to a freestanding house-side beam. Select a jurisdiction before using this in a permit set."
        )
        let lowercased = fallback.rationale.lowercased()
        for forbidden in ["safe", "compliant", "guaranteed", "will pass"] {
            XCTAssertFalse(lowercased.contains(forbidden))
        }
        XCTAssertTrue(lowercased.contains("not a code-recognized ledger substrate"))
    }

    func test_resolvedDetailReturnsPersistableLedgerDetail() throws {
        let freestanding = LedgerStrategyEngine.strategy(
            for: houseEdge(material: .stone),
            houseSideBeamSpanInches: 144,
            package: nil
        )
        let attach = LedgerStrategyEngine.strategy(
            for: houseEdge(material: .vinyl),
            houseSideBeamSpanInches: 144,
            package: nil
        )

        XCTAssertEqual(
            LedgerStrategyEngine.resolvedDetail(freestanding),
            LedgerDetail(cladding: .stone, attachmentAllowed: false)
        )
        XCTAssertEqual(
            LedgerStrategyEngine.resolvedDetail(attach),
            LedgerDetail(cladding: .vinyl, attachmentAllowed: true)
        )
    }

    private func houseEdge(
        id: String = "E-house",
        material: HouseEdgeMaterial?
    ) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: "V1",
            endVertexId: "V2",
            edgeType: .houseEdge,
            houseEdgeMaterial: material
        )
    }

    private func drawingData(
        widthPoints: Double,
        scaleFactor: Double,
        material: HouseEdgeMaterial
    ) -> DeckDrawingData {
        let v1 = DeckVertex(id: "V1", position: CGPoint(x: 12, y: 24))
        let v2 = DeckVertex(id: "V2", position: CGPoint(x: 12 + widthPoints, y: 24))
        var data = DeckDrawingData()
        data.vertices = [v1, v2]
        data.edges = [houseEdge(material: material)]
        data.scaleFactor = scaleFactor
        return data
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
