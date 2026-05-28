//
//  CameraLensOptionPlanner.swift
//  OPS
//
//  Pure planner for native camera lens/zoom stops.
//

import CoreGraphics
import Foundation

struct CameraLensOption: Equatable {
    let zoomFactor: CGFloat
    let label: String
}

enum CameraLensOptionPlanner {

    static func options(
        minZoom: CGFloat,
        maxZoom: CGFloat,
        switchOverZoomFactors: [CGFloat]
    ) -> [CameraLensOption] {
        let lower = max(0.1, minZoom)
        let upper = max(lower, maxZoom)
        let epsilon: CGFloat = 0.05

        let baselineStops: [CGFloat] = [lower, 1, 2, 3]
        let normalized = (baselineStops + switchOverZoomFactors)
            .map(normalize)
            .filter { $0 >= lower - epsilon && $0 <= upper + epsilon }
            .sorted()

        var deduped: [CGFloat] = []
        for candidate in normalized {
            guard !deduped.contains(where: { abs($0 - candidate) < 0.08 }) else { continue }
            deduped.append(clamped(candidate, minZoom: lower, maxZoom: upper))
        }

        if deduped.isEmpty {
            deduped = [lower]
        }

        return deduped.map { CameraLensOption(zoomFactor: $0, label: label(for: $0)) }
    }

    static func clamped(
        _ zoomFactor: CGFloat,
        minZoom: CGFloat,
        maxZoom: CGFloat
    ) -> CGFloat {
        max(minZoom, min(zoomFactor, maxZoom))
    }

    private static func normalize(_ value: CGFloat) -> CGFloat {
        let nearestHalf = (value * 2).rounded() / 2
        if abs(nearestHalf - value) < 0.08 {
            return nearestHalf
        }
        return value
    }

    private static func label(for zoomFactor: CGFloat) -> String {
        if abs(zoomFactor.rounded() - zoomFactor) < 0.01 {
            return "\(Int(zoomFactor.rounded()))x"
        }
        return String(format: "%.1fx", Double(zoomFactor))
    }
}
