//
//  DeckStairRenderPlanner.swift
//  OPS
//
//  Shared stair geometry planner for read-only deck renderers.
//

import CoreGraphics
import SwiftUI

struct DeckStairRenderPlan {
    let baseStart: CGPoint
    let baseEnd: CGPoint
    let farStart: CGPoint
    let farEnd: CGPoint
    let outline: [CGPoint]
    let treadLines: [DeckStairTreadLine]
    let dimensionLabels: [DeckStairDimensionLabel]

    var framePoints: [CGPoint] {
        outline + dimensionLabels.map(\.position)
    }
}

struct DeckStairTreadLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

struct DeckStairDimensionLabel: Equatable {
    enum Kind: Equatable {
        case width
        case run
        case rail
    }

    let kind: Kind
    let text: String
    let position: CGPoint
}

/// Tread count + sloped rail run for one stair — the shared source for every
/// 2D stair label. The rail run is the stair triangle's hypotenuse (total
/// rise over total horizontal run): the length a stair railing actually
/// follows, which is what a railing order is measured by.
struct DeckStairRailInfo: Equatable {
    let treadCount: Int
    let railRunInches: Double
}

extension DeckDrawingData {
    /// Total rise (inches) a fixed-rise stair on `edge` spans: the stored
    /// rise when the user set one, else the owning context's resolved render
    /// height — the same fallback the 3D scene uses, so labels and geometry
    /// never disagree.
    func stairTotalRiseInches(for edge: DeckEdge) -> Double? {
        guard let config = edge.stairConfig else { return nil }
        if let stored = config.totalRiseInches, stored > 0 { return stored }
        if isMultiLevel {
            for (index, level) in levels.enumerated() where level.edge(byId: edge.id) != nil {
                return renderElevationFeet(for: level, levelIndex: index) * 12.0
            }
            return nil
        }
        return renderElevationFeetSingleLevel * 12.0
    }

    /// Rail info for a fixed-rise stair on `edge`, or nil when the edge
    /// carries no stair.
    func stairRailInfo(for edge: DeckEdge) -> DeckStairRailInfo? {
        guard let config = edge.stairConfig,
              let riseInches = stairTotalRiseInches(for: edge), riseInches > 0 else { return nil }
        let treadCount = config.treadCount
            ?? StairConfig.calculateTreadCount(totalRise: riseInches, risePerStep: config.risePerStep)
        guard treadCount > 0 else { return nil }
        return DeckStairRailInfo(
            treadCount: treadCount,
            railRunInches: StairConfig.stringerLength(
                totalRise: riseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
        )
    }

    /// Rail info for a level-connection stair. Rise derives from the two
    /// levels' resolved heights (the connection's live geometry), so the
    /// label tracks height edits exactly like the rendered stair does.
    func stairRailInfo(for connection: LevelConnection) -> DeckStairRailInfo? {
        guard let riseInches = elevationDifference(
            upperLevelId: connection.upperLevelId,
            lowerLevelId: connection.lowerLevelId
        ), riseInches > 0 else { return nil }
        let config = connection.stairConfig
        let treadCount = config.treadCount
            ?? StairConfig.calculateTreadCount(totalRise: riseInches, risePerStep: config.risePerStep)
        guard treadCount > 0 else { return nil }
        return DeckStairRailInfo(
            treadCount: treadCount,
            railRunInches: StairConfig.stringerLength(
                totalRise: riseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
        )
    }
}

enum DeckStairRenderPlanner {

    static func plan(
        edgeStart start: CGPoint,
        edgeEnd end: CGPoint,
        polygonVertices: [CGPoint],
        config: StairConfig,
        treadCount: Int,
        scaleFactor: Double,
        measurementSystem: MeasurementSystem,
        totalRiseInches: Double? = nil
    ) -> DeckStairRenderPlan? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let edgeLength = hypot(dx, dy)
        guard edgeLength > 0, treadCount > 0, scaleFactor > 0 else { return nil }

        let edgeUnit = CGVector(dx: dx / edgeLength, dy: dy / edgeLength)
        let outward: CGVector
        if polygonVertices.count >= 3 {
            let resolved = PolygonMath.outwardPerpendicular(
                edgeStart: start,
                edgeEnd: end,
                polygonVertices: polygonVertices
            )
            outward = CGVector(dx: CGFloat(resolved.x), dy: CGFloat(resolved.y))
        } else {
            outward = CGVector(dx: -dy / edgeLength, dy: dx / edgeLength)
        }
        let stairNormal = config.flipDirection
            ? CGVector(dx: -outward.dx, dy: -outward.dy)
            : outward

        let scale = CGFloat(scaleFactor)
        let stairWidthCanvas = min(max(0, CGFloat(config.width) * scale), edgeLength)
        let totalRunInches = Double(treadCount) * config.runPerTread
        let stairDepthCanvas = CGFloat(totalRunInches) * scale
        guard stairWidthCanvas > 0, stairDepthCanvas > 0 else { return nil }

        let availableGap = max(0, edgeLength - stairWidthCanvas)
        let offsetCanvas = CGFloat(config.offset) * scale
        let rawStartDistance: CGFloat
        switch config.alignment {
        case .left:
            rawStartDistance = offsetCanvas
        case .center:
            rawStartDistance = (availableGap / 2) + offsetCanvas
        case .right:
            rawStartDistance = availableGap - offsetCanvas
        }
        let startDistance = min(max(0, rawStartDistance), availableGap)

        let baseStart = CGPoint(
            x: start.x + edgeUnit.dx * startDistance,
            y: start.y + edgeUnit.dy * startDistance
        )
        let baseEnd = CGPoint(
            x: baseStart.x + edgeUnit.dx * stairWidthCanvas,
            y: baseStart.y + edgeUnit.dy * stairWidthCanvas
        )
        let farStart = CGPoint(
            x: baseStart.x + stairNormal.dx * stairDepthCanvas,
            y: baseStart.y + stairNormal.dy * stairDepthCanvas
        )
        let farEnd = CGPoint(
            x: baseEnd.x + stairNormal.dx * stairDepthCanvas,
            y: baseEnd.y + stairNormal.dy * stairDepthCanvas
        )

        let treadLines: [DeckStairTreadLine] = (1..<min(treadCount, 30)).map { index in
            let t = CGFloat(index) / CGFloat(treadCount)
            let lineStart = CGPoint(
                x: baseStart.x + stairNormal.dx * stairDepthCanvas * t,
                y: baseStart.y + stairNormal.dy * stairDepthCanvas * t
            )
            let lineEnd = CGPoint(
                x: baseEnd.x + stairNormal.dx * stairDepthCanvas * t,
                y: baseEnd.y + stairNormal.dy * stairDepthCanvas * t
            )
            return DeckStairTreadLine(start: lineStart, end: lineEnd)
        }

        let widthInches = Double(stairWidthCanvas / scale)
        let labelInset = min(
            CGFloat(OPSStyle.Layout.spacing3),
            max(CGFloat(OPSStyle.Layout.spacing2), stairDepthCanvas * 0.25)
        )
        let lateralLabelInset = min(
            CGFloat(OPSStyle.Layout.spacing3),
            max(CGFloat(OPSStyle.Layout.spacing2), stairWidthCanvas * 0.28)
        )

        let widthLabelPoint = midpoint(baseStart, baseEnd)
            .offset(by: stairNormal, distance: labelInset)
        let runLabelPoint = midpoint(baseStart, farStart)
            .offset(by: CGVector(dx: -edgeUnit.dx, dy: -edgeUnit.dy), distance: lateralLabelInset)

        var labels = [
            DeckStairDimensionLabel(
                kind: .width,
                text: "WIDTH \(DimensionEngine.format(widthInches, system: measurementSystem))",
                position: widthLabelPoint
            ),
            DeckStairDimensionLabel(
                kind: .run,
                text: "RUN \(DimensionEngine.format(totalRunInches, system: measurementSystem))",
                position: runLabelPoint
            )
        ]

        // Rail run — the stair triangle's hypotenuse (rise over horizontal
        // run), the length a stair railing follows. Emitted only when the
        // caller knows the rise; mirrored on the flank opposite the RUN chip.
        if let totalRiseInches, totalRiseInches > 0 {
            let railRunInches = StairConfig.stringerLength(
                totalRise: totalRiseInches,
                treadCount: treadCount,
                runPerTread: config.runPerTread
            )
            let railLabelPoint = midpoint(baseEnd, farEnd)
                .offset(by: edgeUnit, distance: lateralLabelInset)
            labels.append(
                DeckStairDimensionLabel(
                    kind: .rail,
                    text: "RAIL \(DimensionEngine.format(railRunInches, system: measurementSystem))",
                    position: railLabelPoint
                )
            )
        }

        return DeckStairRenderPlan(
            baseStart: baseStart,
            baseEnd: baseEnd,
            farStart: farStart,
            farEnd: farEnd,
            outline: [baseStart, baseEnd, farEnd, farStart],
            treadLines: treadLines,
            dimensionLabels: labels
        )
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

private extension CGPoint {
    func offset(by vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: x + vector.dx * distance,
            y: y + vector.dy * distance
        )
    }
}
