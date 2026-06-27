import CoreGraphics
import XCTest
@testable import DeckKit

final class FramingTakeoffTests: XCTestCase {
    func test_takeoff_sumsLinearFeet_perSizeRole() throws {
        let joists = (0..<8).map { index in
            member(
                id: "joist-\(index)",
                role: .joist,
                start: CGPoint(x: 0, y: Double(index) * 16),
                end: CGPoint(x: 144, y: Double(index) * 16),
                nominalSize: .twoByEight
            )
        }
        let beam = member(
            id: "beam-0",
            role: .beam,
            start: CGPoint(x: 0, y: 128),
            end: CGPoint(x: 144, y: 128),
            nominalSize: .twoByTen,
            plyCount: 2
        )
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: joists + [beam])],
            generationSource: .manual
        )

        let takeoff = FramingTakeoff.takeoff(plan, waste: WasteSettings(), scaleFactor: 1)

        let joistRow = try XCTUnwrap(takeoff.lumber.first {
            $0.role == .joist && $0.nominalSize == .twoByEight && $0.plyCount == 1
        })
        XCTAssertEqual(joistRow.totalLinearFeet, 96 * 1.10, accuracy: 0.001)
        XCTAssertEqual(joistRow.pieceCount, 8)

        let beamRow = try XCTUnwrap(takeoff.lumber.first {
            $0.role == .beam && $0.nominalSize == .twoByTen && $0.plyCount == 2
        })
        XCTAssertEqual(beamRow.totalLinearFeet, 24 * 1.10, accuracy: 0.001)
        XCTAssertEqual(beamRow.pieceCount, 1)
        XCTAssertEqual(
            takeoff.hardware.first(where: { $0.kind == "joist_hanger" })?.count,
            16
        )
    }

    func test_takeoff_appliesPerPatternAgnostic_globalWaste() throws {
        let plan = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    member(
                        id: "joist-0",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 120, y: 0),
                        nominalSize: .twoByEight
                    )
                ])
            ],
            generationSource: .manual
        )
        let waste = WasteSettings(
            defaultWastePercent: 12,
            perPatternWastePercent: ["herringbone": 99]
        )

        let takeoff = FramingTakeoff.takeoff(plan, waste: waste, scaleFactor: 1)

        let joistRow = try XCTUnwrap(takeoff.lumber.first { $0.role == .joist })
        XCTAssertEqual(joistRow.totalLinearFeet, 10 * 1.12, accuracy: 0.001)
    }

    func test_takeoff_footingCount_matchesPosts() {
        let posts = (0..<3).map { index in
            member(
                id: "post-\(index)",
                role: .post,
                start: CGPoint(x: Double(index) * 72, y: 0),
                end: CGPoint(x: Double(index) * 72, y: 0),
                nominalSize: .sixBySix
            )
        }
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: posts)],
            generationSource: .manual
        )

        let takeoff = FramingTakeoff.takeoff(plan, waste: WasteSettings(), scaleFactor: 1)

        XCTAssertEqual(takeoff.footingCount, 3)
        XCTAssertEqual(
            takeoff.hardware.first(where: { $0.kind == "post_base" })?.count,
            3
        )
    }

    func test_takeoff_skipsUnsizedMember() {
        let plan = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    member(
                        id: "joist-sized",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 120, y: 0),
                        nominalSize: .twoByEight
                    ),
                    member(
                        id: "joist-unsized",
                        role: .joist,
                        start: CGPoint(x: 0, y: 16),
                        end: CGPoint(x: 120, y: 16),
                        nominalSize: nil
                    ),
                ])
            ],
            generationSource: .manual
        )

        let takeoff = FramingTakeoff.takeoff(plan, waste: WasteSettings(), scaleFactor: 1)

        XCTAssertEqual(takeoff.lumber.count, 1)
        XCTAssertEqual(takeoff.lumber[0].pieceCount, 1)
        XCTAssertEqual(takeoff.lumber[0].totalLinearFeet, 10 * 1.10, accuracy: 0.001)
    }

    private func member(
        id: String,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize?,
        plyCount: Int = 1
    ) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: start,
            end: end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            species: .sprucePineFir,
            grade: .no2
        )
    }
}
