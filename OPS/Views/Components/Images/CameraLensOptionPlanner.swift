//
//  CameraLensOptionPlanner.swift
//  OPS
//
//  Pure planner for native camera lens/zoom stops.
//
//  AVFoundation zoom factors are RAW: on a virtual multi-camera device,
//  factor 1.0 is the widest constituent lens. On ultra-wide-bearing
//  hardware that lens is what users know as "0.5x" — the 1x wide lens
//  only engages at the first switch-over factor (2.0 on every ultra-wide
//  iPhone to date). Users think in the native Camera app's magnification
//  numbers, so the planner picks stops and writes labels in that
//  user-facing space and converts back to raw factors for the device.
//  Bug 56c37df2.
//

import CoreGraphics
import Foundation

struct CameraLensOption: Equatable {
    /// Raw `videoZoomFactor` to apply to the capture device.
    let zoomFactor: CGFloat
    /// User-facing magnification label ("0.5x", "1x", "3x").
    let label: String
}

enum CameraLensOptionPlanner {

    /// Builds the lens-stop row for a capture device.
    ///
    /// - Parameters:
    ///   - minZoom: raw `minAvailableVideoZoomFactor`.
    ///   - maxZoom: raw zoom ceiling (already clamped by the caller).
    ///   - switchOverZoomFactors: raw `virtualDeviceSwitchOverVideoZoomFactors`.
    ///   - wideLensZoomFactor: raw factor at which the user-facing 1x wide
    ///     lens engages — 1 on single-lens and wide+tele devices, the first
    ///     switch-over factor on ultra-wide-bearing virtual devices.
    static func options(
        minZoom: CGFloat,
        maxZoom: CGFloat,
        switchOverZoomFactors: [CGFloat],
        wideLensZoomFactor: CGFloat = 1
    ) -> [CameraLensOption] {
        let lowerRaw = max(0.1, minZoom)
        let upperRaw = max(lowerRaw, maxZoom)
        let baseline = wideLensZoomFactor >= 0.1 ? wideLensZoomFactor : 1
        let epsilon: CGFloat = 0.05

        // Everything below happens in user-facing magnification space
        // (raw factor ÷ wide-lens baseline) so the stops and labels come
        // out matching what the native Camera app shows for the same
        // framing.
        let lowerUser = lowerRaw / baseline
        let upperUser = upperRaw / baseline

        // The widest stop (0.5x when an ultra-wide is present), the wide
        // lens itself, and the 2x/3x crop stops users reach for. Lens
        // switch-overs land on their true magnification (2x/3x/5x tele).
        let baselineStops: [CGFloat] = [lowerUser, 1, 2, 3]
        let switchOverStops = switchOverZoomFactors.map { $0 / baseline }

        let normalized = (baselineStops + switchOverStops)
            .map(normalize)
            .filter { $0 >= lowerUser - epsilon && $0 <= upperUser + epsilon }
            .sorted()

        var deduped: [CGFloat] = []
        for candidate in normalized {
            guard !deduped.contains(where: { abs($0 - candidate) < 0.08 }) else { continue }
            deduped.append(candidate)
        }

        if deduped.isEmpty {
            deduped = [lowerUser]
        }

        return deduped.map { userStop in
            CameraLensOption(
                zoomFactor: clamped(userStop * baseline, minZoom: lowerRaw, maxZoom: upperRaw),
                label: label(for: userStop)
            )
        }
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

    private static func label(for magnification: CGFloat) -> String {
        if abs(magnification.rounded() - magnification) < 0.01 {
            return "\(Int(magnification.rounded()))x"
        }
        return String(format: "%.1fx", Double(magnification))
    }
}
