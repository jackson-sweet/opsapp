//
//  LabelPlacerTests.swift
//  OPSTests
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5
//

import XCTest
import CoreGraphics
@testable import OPS

final class LabelPlacerTests: XCTestCase {

    private let canvas = CGSize(width: 800, height: 1000)
    private let chip = CGSize(width: 80, height: 22)

    /// Four widely-separated measurements — every placement should resolve to
    /// north on the first try, no collisions.
    func test_fourPlacements_noCollision_allNorth() {
        let inputs: [LabelPlacer.Input] = [
            .init(id: UUID(), pointA: CGPoint(x: 100, y: 500), pointB: CGPoint(x: 200, y: 500), chipSize: chip),
            .init(id: UUID(), pointA: CGPoint(x: 500, y: 500), pointB: CGPoint(x: 600, y: 500), chipSize: chip),
            .init(id: UUID(), pointA: CGPoint(x: 100, y: 700), pointB: CGPoint(x: 200, y: 700), chipSize: chip),
            .init(id: UUID(), pointA: CGPoint(x: 500, y: 700), pointB: CGPoint(x: 600, y: 700), chipSize: chip),
        ]
        let placements = LabelPlacer.place(inputs: inputs, canvasSize: canvas)
        XCTAssertEqual(placements.count, 4)
        for p in placements {
            XCTAssertEqual(p.placement.side, .north)
            XCTAssertEqual(p.placement.leaderLengthPx, Double(LabelPlacer.defaultMinLeaderPx))
            XCTAssertFalse(p.collidesWithSibling)
        }
        XCTAssertNoIntersections(placements)
    }

    /// Five placements stacked tightly — at least one entry must take a
    /// different side or a longer leader; the placer must extend rather
    /// than allow overlap.
    func test_fivePlacements_collisionTriggersAlternateSlot() {
        // Five line midpoints all at the same Y — first lands north,
        // second tries north (collides), tries east, etc.
        let baseX: CGFloat = 150
        let stepX: CGFloat = 90  // slightly bigger than chip width
        let y: CGFloat = 500
        let inputs: [LabelPlacer.Input] = (0..<5).map { i in
            let mid = baseX + CGFloat(i) * stepX
            return .init(
                id: UUID(),
                pointA: CGPoint(x: mid - 30, y: y),
                pointB: CGPoint(x: mid + 30, y: y),
                chipSize: chip
            )
        }
        let placements = LabelPlacer.place(inputs: inputs, canvasSize: canvas)
        XCTAssertEqual(placements.count, 5)
        XCTAssertNoIntersections(placements)

        let sides = placements.map { $0.placement.side }
        let allNorth = sides.allSatisfy { $0 == .north }
        let allSameLeader = Set(placements.map { $0.placement.leaderLengthPx }).count == 1
        XCTAssertFalse(allNorth && allSameLeader,
                       "Expected at least one alternate slot or extended leader on tight layout")
    }

    /// When every slot is blocked at every leader length, the placer must
    /// fall back to the first side at max leader and mark `collidesWithSibling`.
    func test_allBlocked_fallsBackAndFlagsCollision() {
        let id = UUID()
        let chipBigger = CGSize(width: 600, height: 900)  // chip fills almost whole canvas
        let input = LabelPlacer.Input(
            id: id,
            pointA: CGPoint(x: 400, y: 500),
            pointB: CGPoint(x: 410, y: 500),
            chipSize: chipBigger
        )
        let placements = LabelPlacer.place(
            inputs: [input],
            canvasSize: canvas,
            minLeaderPx: 800,
            maxLeaderPx: 900
        )
        XCTAssertEqual(placements.count, 1)
        XCTAssertTrue(placements[0].collidesWithSibling,
                      "Expected fallback to flag collision when no slot fits within canvas")
        XCTAssertEqual(placements[0].placement.side, .north)
    }

    /// A measurement near the top of the canvas should not pick north (would
    /// clip); it should take south, east, or west instead.
    func test_topEdge_skipsNorthForLowerSlot() {
        let input = LabelPlacer.Input(
            id: UUID(),
            pointA: CGPoint(x: 400, y: 10),
            pointB: CGPoint(x: 500, y: 10),
            chipSize: chip
        )
        let placements = LabelPlacer.place(inputs: [input], canvasSize: canvas)
        XCTAssertEqual(placements.count, 1)
        XCTAssertNotEqual(placements[0].placement.side, .north,
                          "North would clip off top of canvas")
    }

    /// Placement is deterministic — same input order produces same output.
    func test_deterministic() {
        let inputs: [LabelPlacer.Input] = (0..<6).map { i in
            .init(
                id: UUID(),
                pointA: CGPoint(x: 100 + CGFloat(i) * 80, y: 400),
                pointB: CGPoint(x: 160 + CGFloat(i) * 80, y: 400),
                chipSize: chip
            )
        }
        let a = LabelPlacer.place(inputs: inputs, canvasSize: canvas)
        let b = LabelPlacer.place(inputs: inputs, canvasSize: canvas)
        XCTAssertEqual(
            a.map { "\($0.placement.side)|\($0.placement.leaderLengthPx)|\($0.chipRect)" },
            b.map { "\($0.placement.side)|\($0.placement.leaderLengthPx)|\($0.chipRect)" }
        )
    }

    // MARK: - Helpers

    private func XCTAssertNoIntersections(_ placements: [LabelPlacer.Placement],
                                          file: StaticString = #file,
                                          line: UInt = #line) {
        for i in 0..<placements.count {
            for j in (i + 1)..<placements.count {
                if placements[i].chipRect.intersects(placements[j].chipRect) {
                    XCTFail("Chips \(i) and \(j) intersect: \(placements[i].chipRect) vs \(placements[j].chipRect)",
                            file: file, line: line)
                }
            }
        }
    }
}
