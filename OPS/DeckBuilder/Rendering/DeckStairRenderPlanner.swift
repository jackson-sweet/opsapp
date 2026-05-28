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
    }

    let kind: Kind
    let text: String
    let position: CGPoint
}

enum DeckStairRenderPlanner {

    static func plan(
        edgeStart start: CGPoint,
        edgeEnd end: CGPoint,
        polygonVertices: [CGPoint],
        config: StairConfig,
        treadCount: Int,
        scaleFactor: Double,
        measurementSystem: MeasurementSystem
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

        let labels = [
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
