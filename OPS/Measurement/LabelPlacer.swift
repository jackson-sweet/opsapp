//
//  LabelPlacer.swift
//  OPS
//
//  Greedy N/E/S/W placement for dimension labels with collision avoidance.
//  Per spec §3.5: "Labels auto-route to avoid overlap (a simple greedy
//  placement: try N/E/S/W of the line midpoint, pick first non-colliding
//  slot at increasing leader length)."
//
//  Inputs:
//    • The two image-space endpoints of each measurement (photo pixel
//      coordinates).
//    • A canvas size (the rendered output dimensions — screen for the
//      annotation view, page for PDF).
//    • A measured label chip size (the renderer computes this from the
//      formatted text dimensions).
//
//  Outputs:
//    • A `Placement` per measurement: chip rect in canvas space and the
//      `LabelPlacement` (side + leader length) ready for persistence on
//      `DimensionsData.Measurement`.
//
//  Algorithm:
//    1. For each measurement in input order, compute midpoint of its
//       endpoints.
//    2. Walk leader lengths from `minLeaderPx` upward in steps of
//       `leaderStepPx` until either a non-colliding slot is found OR
//       `maxLeaderPx` is reached.
//    3. At each leader length, try sides in the order N, E, S, W.
//    4. A slot is non-colliding if its chip rect (a) lies within the
//       canvas (no clipping) and (b) does not intersect any previously
//       placed chip nor any endpoint pixel.
//    5. If no slot is found at `maxLeaderPx`, fall back to the
//       N side at `maxLeaderPx` even if it collides — the renderer
//       handles collisions by allowing overlap rather than dropping the
//       label.
//
//  Pure-Swift; UI-free; deterministic for unit testing.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5
//

import Foundation
import CoreGraphics

public enum LabelPlacer {

    /// Input for a single measurement.
    public struct Input: Equatable {
        public let id: UUID
        public let pointA: CGPoint
        public let pointB: CGPoint
        public let chipSize: CGSize

        public init(id: UUID, pointA: CGPoint, pointB: CGPoint, chipSize: CGSize) {
            self.id = id
            self.pointA = pointA
            self.pointB = pointB
            self.chipSize = chipSize
        }
    }

    /// Output for a single measurement.
    public struct Placement: Equatable {
        public let id: UUID
        public let chipRect: CGRect
        public let placement: DimensionsData.Measurement.LabelPlacement
        /// `true` if the greedy walk exhausted all leader lengths and the
        /// renderer should expect this chip to overlap. Surfaced for tests.
        public let collidesWithSibling: Bool

        public init(id: UUID, chipRect: CGRect,
                    placement: DimensionsData.Measurement.LabelPlacement,
                    collidesWithSibling: Bool) {
            self.id = id
            self.chipRect = chipRect
            self.placement = placement
            self.collidesWithSibling = collidesWithSibling
        }
    }

    /// Greedy walk defaults — match the spec's "increasing leader length"
    /// language. Chips are typically ~80 pt wide × 22 pt tall on screen.
    public static let defaultMinLeaderPx: CGFloat = 36
    public static let defaultMaxLeaderPx: CGFloat = 140
    public static let defaultLeaderStepPx: CGFloat = 18

    /// Place all measurements. Order is preserved; later entries see earlier
    /// chips as obstacles.
    public static func place(
        inputs: [Input],
        canvasSize: CGSize,
        minLeaderPx: CGFloat = defaultMinLeaderPx,
        maxLeaderPx: CGFloat = defaultMaxLeaderPx,
        leaderStepPx: CGFloat = defaultLeaderStepPx,
        sides: [DimensionsData.Measurement.LabelPlacement.Side] = [.north, .east, .south, .west]
    ) -> [Placement] {
        var occupied: [CGRect] = []
        var results: [Placement] = []
        results.reserveCapacity(inputs.count)

        for input in inputs {
            let midpoint = CGPoint(
                x: (input.pointA.x + input.pointB.x) / 2,
                y: (input.pointA.y + input.pointB.y) / 2
            )
            let endpoints = [input.pointA, input.pointB]

            let found = findSlot(
                midpoint: midpoint,
                chipSize: input.chipSize,
                canvasSize: canvasSize,
                obstacles: occupied,
                endpoints: endpoints,
                minLeaderPx: minLeaderPx,
                maxLeaderPx: maxLeaderPx,
                leaderStepPx: leaderStepPx,
                sides: sides
            )

            occupied.append(found.rect)
            results.append(Placement(
                id: input.id,
                chipRect: found.rect,
                placement: DimensionsData.Measurement.LabelPlacement(
                    side: found.side,
                    leaderLengthPx: Double(found.leader)
                ),
                collidesWithSibling: found.collides
            ))
        }
        return results
    }

    // MARK: - Slot search

    private struct Slot {
        let rect: CGRect
        let side: DimensionsData.Measurement.LabelPlacement.Side
        let leader: CGFloat
        let collides: Bool
    }

    private static func findSlot(
        midpoint: CGPoint,
        chipSize: CGSize,
        canvasSize: CGSize,
        obstacles: [CGRect],
        endpoints: [CGPoint],
        minLeaderPx: CGFloat,
        maxLeaderPx: CGFloat,
        leaderStepPx: CGFloat,
        sides: [DimensionsData.Measurement.LabelPlacement.Side]
    ) -> Slot {
        var leader = minLeaderPx
        let canvas = CGRect(origin: .zero, size: canvasSize)

        while leader <= maxLeaderPx {
            for side in sides {
                let rect = chipRect(
                    midpoint: midpoint,
                    chipSize: chipSize,
                    side: side,
                    leader: leader
                )
                guard canvas.contains(rect) else { continue }
                let collidesObstacle = obstacles.contains { $0.intersects(rect) }
                let coversEndpoint = endpoints.contains { rect.contains($0) }
                if !collidesObstacle, !coversEndpoint {
                    return Slot(rect: rect, side: side, leader: leader, collides: false)
                }
            }
            leader += leaderStepPx
        }

        // Fallback: place at max leader on the first side regardless of collision.
        let fallbackSide = sides.first ?? .north
        let fallbackRect = chipRect(
            midpoint: midpoint,
            chipSize: chipSize,
            side: fallbackSide,
            leader: maxLeaderPx
        )
        return Slot(rect: fallbackRect, side: fallbackSide, leader: maxLeaderPx, collides: true)
    }

    /// Computes the chip rect at a given side + leader length away from the
    /// midpoint of the measurement line. Chip is centred on its anchor point.
    static func chipRect(
        midpoint: CGPoint,
        chipSize: CGSize,
        side: DimensionsData.Measurement.LabelPlacement.Side,
        leader: CGFloat
    ) -> CGRect {
        let anchor: CGPoint
        switch side {
        case .north: anchor = CGPoint(x: midpoint.x, y: midpoint.y - leader)
        case .south: anchor = CGPoint(x: midpoint.x, y: midpoint.y + leader)
        case .east:  anchor = CGPoint(x: midpoint.x + leader, y: midpoint.y)
        case .west:  anchor = CGPoint(x: midpoint.x - leader, y: midpoint.y)
        }
        return CGRect(
            x: anchor.x - chipSize.width / 2,
            y: anchor.y - chipSize.height / 2,
            width: chipSize.width,
            height: chipSize.height
        )
    }
}
