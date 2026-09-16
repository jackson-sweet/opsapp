//
//  RailingTakeoff.swift
//  OPS
//
//  Railing run takeoff from a Deck Designer drawing. Groups railed deck
//  edges into physical runs and counts what an installer orders against
//  them: linear feet, left and right end posts, 90° corners, off-angle
//  (45°) corners, and runs that return into the house.
//
//  Pure function over `DeckDrawingData` — no SwiftData, no I/O. The counts
//  feed the integer product options ("Left ends", "Corners", …) that the
//  recipe engine scales end-post, corner-sleeve and hardware materials by.
//
//  Rules (plan docs/plans/2026-09-15-recipe-engine-railing-bridge.md):
//  - D5  one group per railing system; totals only.
//  - D6  handedness: standing outside the deck facing the railing, the run
//        end on your left is a left end. A run walked with the deck on the
//        walker's right ends on its left end. With no closed surface to say
//        where the deck is, walk order is edge order (`edge_order` basis).
//  - D7  turn θ between consecutive run edges (0° = straight):
//        θ ≤ 10° straight; |θ − 90°| ≤ 10° convex → corner, reflex → an end
//        post on each side; anything else → off-angle corner + an end post
//        on each side.
//  - D8  a run end sharing a vertex with a house edge is a house return; it
//        is still an end post.
//  - D9  stair and gate openings deduct their width (ComponentEmitter's net
//        length rule) and terminate the rail on both sides.
//
//  Judgment calls:
//  - A vertex joining three or more railing edges of the same group ends
//    every run that meets there (each takes its own end post). Pairing
//    "the straightest two" would guess at how the installer ties a T in;
//    terminating all of them never under-orders posts.
//  - Groups are keyed by railing type AND the catalog vocabulary that picks
//    the product variant (color, mount type, mount surface, parapet wall
//    material). A white picket run is a different line than a black one.
//  - Runs are built per level and never join across levels; totals are
//    aggregated per group across the whole drawing.
//  - Without a closed surface, convex vs. reflex follows the run's dominant
//    turn direction (a run wraps the deck it guards); a tie counts every
//    right-angle turn as a convex corner.
//

import Foundation
import CoreGraphics

enum RailingTakeoff {

    /// Turns at or below this angle are a straight run (no hardware).
    static let straightToleranceDegrees: Double = 10
    /// Turns within this many degrees of 90° are right-angle corners.
    static let rightAngleToleranceDegrees: Double = 10

    enum HandednessBasis: String, Equatable {
        /// A detected closed surface decided which side of the run the deck is on.
        case surface
        /// No surface decided it for at least one run; walk order is edge order.
        case edgeOrder = "edge_order"
    }

    enum Hand: String, Equatable {
        case left
        case right
    }

    /// A run end at a drawing vertex.
    struct Terminal: Equatable {
        let vertexId: String
        /// Nil on single-level drawings.
        let levelId: String?
        let hand: Hand
        let isHouseReturn: Bool
    }

    struct Group: Equatable {
        let railingType: RailingType
        let color: String
        let mountType: String
        let mountSurface: String
        /// Parapet walls only.
        let wallMaterial: HouseEdgeMaterial?

        let linearFeet: Double
        let leftEnds: Int
        let rightEnds: Int
        let corners: Int
        let offAngleCorners: Int
        let houseReturns: Int
        let handednessBasis: HandednessBasis

        /// Railed edge ids in the group, in drawing order.
        let edgeIds: [String]
        /// Every vertex run end (openings terminate mid-edge and have none).
        let terminals: [Terminal]

        /// The `railing` component metadata consumed by
        /// `DesignToEstimateAdapter`.
        var componentMetadata: [String: AnyCodable] {
            var meta: [String: AnyCodable] = [
                "linear_feet": AnyCodable(linearFeet),
                "left_ends": AnyCodable(leftEnds),
                "right_ends": AnyCodable(rightEnds),
                "corners": AnyCodable(corners),
                "off_angle_corners": AnyCodable(offAngleCorners),
                "house_returns": AnyCodable(houseReturns),
                "handedness_basis": AnyCodable(handednessBasis.rawValue),
                "railing_type": AnyCodable(railingType.rawValue),
                "color": AnyCodable(color),
                "mount_type": AnyCodable(mountType),
                "mount_surface": AnyCodable(mountSurface),
            ]
            if let wallMaterial {
                meta["wall_material"] = AnyCodable(wallMaterial.rawValue)
            }
            return meta
        }
    }

    // MARK: - Entry point

    static func compute(data: DeckDrawingData) -> [Group] {
        var accumulators: [GroupKey: Accumulator] = [:]

        if data.isMultiLevel {
            for level in data.levels {
                accumulate(
                    plane: Plane(
                        levelId: level.id,
                        vertices: level.vertices,
                        edges: level.edges,
                        surfaces: level.detectedSurfaces
                    ),
                    into: &accumulators
                )
            }
        } else {
            accumulate(
                plane: Plane(
                    levelId: nil,
                    vertices: data.vertices,
                    edges: data.edges,
                    surfaces: data.detectedSurfaces
                ),
                into: &accumulators
            )
        }

        return accumulators
            .sorted { $0.key < $1.key }
            .map { key, acc in
                Group(
                    railingType: key.railingType,
                    color: key.color,
                    mountType: key.mountType,
                    mountSurface: key.mountSurface,
                    wallMaterial: key.wallMaterial,
                    linearFeet: (acc.netInches / 12.0 * 100).rounded() / 100,
                    leftEnds: acc.leftEnds,
                    rightEnds: acc.rightEnds,
                    corners: acc.corners,
                    offAngleCorners: acc.offAngleCorners,
                    houseReturns: acc.houseReturns,
                    handednessBasis: acc.everyRunSurfaceBased ? .surface : .edgeOrder,
                    edgeIds: acc.edgeIds,
                    terminals: acc.terminals
                )
            }
    }

    // MARK: - Grouping

    private struct GroupKey: Hashable, Comparable {
        let railingType: RailingType
        let color: String
        let mountType: String
        let mountSurface: String
        let wallMaterial: HouseEdgeMaterial?

        init(_ railing: RailingConfig) {
            railingType = railing.railingType
            color = railing.color
            mountType = railing.mountType
            mountSurface = railing.mountSurface
            wallMaterial = railing.railingType == .parapetWall ? railing.wallMaterial : nil
        }

        private var sortTuple: (Int, String, String, String, String) {
            (
                RailingType.allCases.firstIndex(of: railingType) ?? Int.max,
                color,
                mountType,
                mountSurface,
                wallMaterial?.rawValue ?? ""
            )
        }

        static func < (lhs: GroupKey, rhs: GroupKey) -> Bool {
            lhs.sortTuple < rhs.sortTuple
        }
    }

    private struct Accumulator {
        var netInches: Double = 0
        var leftEnds = 0
        var rightEnds = 0
        var corners = 0
        var offAngleCorners = 0
        var houseReturns = 0
        var everyRunSurfaceBased = true
        var edgeIds: [String] = []
        var terminals: [Terminal] = []
    }

    private struct Plane {
        let levelId: String?
        let vertices: [DeckVertex]
        let edges: [DeckEdge]
        let surfaces: [DetectedSurface]
    }

    private static func accumulate(plane: Plane, into accumulators: inout [GroupKey: Accumulator]) {
        let positions = Dictionary(plane.vertices.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })

        var houseVertexIds = Set<String>()
        for edge in plane.edges where edge.edgeType == .houseEdge {
            houseVertexIds.insert(edge.startVertexId)
            houseVertexIds.insert(edge.endVertexId)
        }

        // Railed deck edges, grouped, in drawing order.
        var groupOrder: [GroupKey] = []
        var edgesByGroup: [GroupKey: [DeckEdge]] = [:]
        for edge in plane.edges {
            guard edge.edgeType == .deckEdge,
                  let railing = edge.railingConfig,
                  edge.startVertexId != edge.endVertexId,
                  positions[edge.startVertexId] != nil,
                  positions[edge.endVertexId] != nil else { continue }
            let key = GroupKey(railing)
            if edgesByGroup[key] == nil { groupOrder.append(key) }
            edgesByGroup[key, default: []].append(edge)
        }
        guard !groupOrder.isEmpty else { return }

        let faceSides = FaceSides(surfaces: plane.surfaces)

        for key in groupOrder {
            let edges = edgesByGroup[key] ?? []
            var acc = accumulators[key] ?? Accumulator()

            for edge in edges {
                acc.edgeIds.append(edge.id)
                acc.netInches += ComponentEmitter.netRailingInches(edge: edge)
                let openings = openingCount(edge: edge)
                acc.leftEnds += openings
                acc.rightEnds += openings
            }

            for chain in buildRuns(edges: edges) {
                let run = orient(chain, faceSides: faceSides)
                if !run.surfaceBased { acc.everyRunSurfaceBased = false }
                count(run: run, positions: positions, houseVertexIds: houseVertexIds, levelId: plane.levelId, into: &acc)
            }

            accumulators[key] = acc
        }
    }

    /// Stair openings (with a real width) and gates each break the rail.
    private static func openingCount(edge: DeckEdge) -> Int {
        let gates = edge.assignedItems.filter { $0.isGate }.count
        let stair = (edge.stairConfig?.width ?? 0) > 0 ? 1 : 0
        return gates + stair
    }

    // MARK: - Runs

    private struct Step {
        let edge: DeckEdge
        let from: String
        let to: String

        var reversed: Step { Step(edge: edge, from: to, to: from) }
    }

    private struct Chain {
        var steps: [Step]
        let isLoop: Bool
    }

    private struct Run {
        let steps: [Step]
        let isLoop: Bool
        let surfaceBased: Bool
        /// True when the deck is on the walker's right. Nil when nothing
        /// decided it (edge-order basis).
        let deckOnRight: Bool?
    }

    /// Splits one group's edges into maximal runs. Runs pass through vertices
    /// of degree 2 and end at every other vertex (free ends and 3+ junctions).
    /// Returned chains walk in edge order: the chain's first-drawn edge is
    /// traversed start → end.
    private static func buildRuns(edges: [DeckEdge]) -> [Chain] {
        var incident: [String: [Int]] = [:]
        var vertexOrder: [String] = []
        for (index, edge) in edges.enumerated() {
            for vertexId in [edge.startVertexId, edge.endVertexId] {
                if incident[vertexId] == nil { vertexOrder.append(vertexId) }
                incident[vertexId, default: []].append(index)
            }
        }
        func degree(_ vertexId: String) -> Int { incident[vertexId]?.count ?? 0 }

        var visited = Set<Int>()
        var chains: [(chain: Chain, firstEdgeIndex: Int)] = []

        func walk(from start: String, edgeIndex first: Int) -> [(Step, Int)] {
            var steps: [(Step, Int)] = []
            var current = start
            var edgeIndex = first
            while true {
                visited.insert(edgeIndex)
                let edge = edges[edgeIndex]
                let next = edge.startVertexId == current ? edge.endVertexId : edge.startVertexId
                steps.append((Step(edge: edge, from: current, to: next), edgeIndex))
                current = next
                guard degree(current) == 2,
                      let following = incident[current]?.first(where: { !visited.contains($0) }) else { break }
                edgeIndex = following
            }
            return steps
        }

        for vertexId in vertexOrder where degree(vertexId) != 2 {
            for edgeIndex in incident[vertexId] ?? [] where !visited.contains(edgeIndex) {
                let steps = walk(from: vertexId, edgeIndex: edgeIndex)
                chains.append((Chain(steps: steps.map(\.0), isLoop: false), steps.map(\.1).min() ?? edgeIndex))
            }
        }
        for edgeIndex in edges.indices where !visited.contains(edgeIndex) {
            // Every remaining edge sits on a cycle of degree-2 vertices.
            let steps = walk(from: edges[edgeIndex].startVertexId, edgeIndex: edgeIndex)
            chains.append((Chain(steps: steps.map(\.0), isLoop: true), steps.map(\.1).min() ?? edgeIndex))
        }

        return chains.map { entry in
            var chain = entry.chain
            let firstDrawn = edges[entry.firstEdgeIndex]
            if let step = chain.steps.first(where: { $0.edge.id == firstDrawn.id }),
               step.from != firstDrawn.startVertexId {
                chain.steps = chain.steps.reversed().map(\.reversed)
            }
            return chain
        }
    }

    /// Decides which side of the run the deck is on and, when a surface
    /// decides it, reverses the walk so the deck is on the walker's right.
    private static func orient(_ chain: Chain, faceSides: FaceSides) -> Run {
        var rightVotes = 0
        var leftVotes = 0
        var firstVote: Bool?
        for step in chain.steps {
            guard let onRight = faceSides.interiorOnRight(from: step.from, to: step.to) else { continue }
            if firstVote == nil { firstVote = onRight }
            if onRight { rightVotes += 1 } else { leftVotes += 1 }
        }
        guard let firstVote else {
            return Run(steps: chain.steps, isLoop: chain.isLoop, surfaceBased: false, deckOnRight: nil)
        }
        let deckOnRight = rightVotes == leftVotes ? firstVote : rightVotes > leftVotes
        let steps = deckOnRight ? chain.steps : chain.steps.reversed().map(\.reversed)
        return Run(steps: steps, isLoop: chain.isLoop, surfaceBased: true, deckOnRight: true)
    }

    // MARK: - Counting

    private struct Turn {
        let degrees: Double
        /// > 0 turns right on screen (canvas is y-down), < 0 turns left.
        let cross: Double
    }

    private static func count(
        run: Run,
        positions: [String: CGPoint],
        houseVertexIds: Set<String>,
        levelId: String?,
        into acc: inout Accumulator
    ) {
        let steps = run.steps
        guard !steps.isEmpty else { return }

        var turns: [Turn] = []
        let joints = run.isLoop ? steps.count : steps.count - 1
        for i in 0..<joints {
            let incoming = steps[i]
            let outgoing = steps[(i + 1) % steps.count]
            if let turn = turn(incoming: incoming, outgoing: outgoing, positions: positions) {
                turns.append(turn)
            }
        }

        // Which turn direction wraps the deck.
        let convexTurnsRight: Bool? = {
            if run.deckOnRight == true { return true }
            let bent = turns.filter { $0.degrees > straightToleranceDegrees && $0.cross != 0 }
            let balance = bent.reduce(0) { $0 + ($1.cross > 0 ? 1 : -1) }
            if balance == 0 { return nil }
            return balance > 0
        }()

        for turn in turns {
            guard turn.degrees > straightToleranceDegrees else { continue }
            if abs(turn.degrees - 90) <= rightAngleToleranceDegrees {
                let convex = convexTurnsRight.map { $0 == (turn.cross > 0) } ?? true
                if convex {
                    acc.corners += 1
                } else {
                    acc.leftEnds += 1
                    acc.rightEnds += 1
                }
            } else {
                acc.offAngleCorners += 1
                acc.leftEnds += 1
                acc.rightEnds += 1
            }
        }

        guard !run.isLoop, let first = steps.first, let last = steps.last else { return }
        let ends: [(String, Hand)] = [(first.from, .right), (last.to, .left)]
        for (vertexId, hand) in ends {
            let isHouseReturn = houseVertexIds.contains(vertexId)
            if hand == .left { acc.leftEnds += 1 } else { acc.rightEnds += 1 }
            if isHouseReturn { acc.houseReturns += 1 }
            acc.terminals.append(Terminal(vertexId: vertexId, levelId: levelId, hand: hand, isHouseReturn: isHouseReturn))
        }
    }

    private static func turn(incoming: Step, outgoing: Step, positions: [String: CGPoint]) -> Turn? {
        guard let a = positions[incoming.from],
              let b = positions[incoming.to],
              let c = positions[outgoing.to] else { return nil }
        let d1x = Double(b.x - a.x), d1y = Double(b.y - a.y)
        let d2x = Double(c.x - b.x), d2y = Double(c.y - b.y)
        guard hypot(d1x, d1y) > 0, hypot(d2x, d2y) > 0 else { return nil }
        let cross = d1x * d2y - d1y * d2x
        let dot = d1x * d2x + d1y * d2y
        let degrees = atan2(abs(cross), dot) * 180 / .pi
        return Turn(degrees: degrees, cross: cross)
    }

    // MARK: - Deck side from detected surfaces

    /// For each boundary edge that belongs to exactly one closed surface,
    /// which side of the edge the surface lies on.
    private struct FaceSides {
        private struct Entry {
            let from: String
            let interiorOnRight: Bool
        }
        private var entries: [String: [Entry]] = [:]

        init(surfaces: [DetectedSurface]) {
            for surface in surfaces {
                let ids = surface.vertexIds
                guard ids.count >= 3, ids.count == surface.positions.count else { continue }
                // Shoelace sign in y-down canvas space: positive winds
                // clockwise on screen, which keeps the interior on the
                // walker's right.
                let area = PolygonMath.signedArea(vertices: surface.positions)
                guard area != 0 else { continue }
                for i in ids.indices {
                    let u = ids[i]
                    let w = ids[(i + 1) % ids.count]
                    entries[Self.key(u, w), default: []].append(Entry(from: u, interiorOnRight: area > 0))
                }
            }
        }

        func interiorOnRight(from: String, to: String) -> Bool? {
            guard let found = entries[Self.key(from, to)], found.count == 1, let entry = found.first else {
                return nil
            }
            return entry.from == from ? entry.interiorOnRight : !entry.interiorOnRight
        }

        private static func key(_ a: String, _ b: String) -> String {
            a < b ? "\(a)\u{1F}\(b)" : "\(b)\u{1F}\(a)"
        }
    }
}
