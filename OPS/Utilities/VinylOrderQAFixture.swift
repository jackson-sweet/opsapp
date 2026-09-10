//
//  VinylOrderQAFixture.swift
//  OPS
//
//  One synthetic deck, shared by the DEBUG QA host and the snapshot proofs, so
//  what the principal drives on the simulator and what the PNGs show are the
//  same drawing.
//
//  The shape is an L — the common real deck that a rectangle never exercises:
//  a house edge, an inside corner, six outer edges all over the two-foot
//  dimension floor, and two run regions once a direction change is allowed.
//

#if DEBUG
import CoreGraphics
import Foundation

enum VinylOrderQAFixture {

    /// 24' along the house, 12' deep, returning 8' further out over a 10' leg.
    /// Canvas units are inches (`scaleFactor` 1), so the drawing's own scale and
    /// the deck's real dimensions are the same number — an edge that reads
    /// `24'` in the label really is 288 inches long.
    static let houseEdgeId = "qa-house"

    static func surfaceInput() -> VinylOrderSurfaceInput {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 288, y: 0),
            CGPoint(x: 288, y: 144),
            CGPoint(x: 120, y: 144),
            CGPoint(x: 120, y: 240),
            CGPoint(x: 0, y: 240)
        ]

        return VinylOrderSurfaceInput(
            id: "qa-surface",
            label: "Rear Deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: houseEdgeId,
                    start: positions[0],
                    end: positions[1],
                    edgeType: .houseEdge,
                    label: nil,
                    dimensionInches: 288
                ),
                VinylOrderSurfaceEdge(
                    id: "qa-east",
                    start: positions[1],
                    end: positions[2],
                    edgeType: .deckEdge,
                    label: nil,
                    dimensionInches: 144
                ),
                VinylOrderSurfaceEdge(
                    id: "qa-return",
                    start: positions[2],
                    end: positions[3],
                    edgeType: .deckEdge,
                    label: nil,
                    dimensionInches: 168
                ),
                VinylOrderSurfaceEdge(
                    id: "qa-step",
                    start: positions[3],
                    end: positions[4],
                    edgeType: .deckEdge,
                    label: nil,
                    dimensionInches: 96
                ),
                VinylOrderSurfaceEdge(
                    id: "qa-south",
                    start: positions[4],
                    end: positions[5],
                    edgeType: .deckEdge,
                    label: nil,
                    dimensionInches: 120
                ),
                VinylOrderSurfaceEdge(
                    id: "qa-west",
                    start: positions[5],
                    end: positions[0],
                    edgeType: .deckEdge,
                    label: nil,
                    dimensionInches: 240
                )
            ]
        )
    }

    static func plan(settings: VinylOrderSettings = .default) -> VinylCutPlan {
        VinylCutListEngine.makePlan(surfaces: [surfaceInput()], settings: settings)
    }

    static let projectTitle = "HARBOUR RESIDENCE"
    static let deckTitle = "Rear Deck"
}
#endif
