//
//  AccuracyBadge.swift
//  OPS
//
//  Renders the bottom-right accuracy chip on `DimensionedAnnotationView`.
//  Four states per spec §3.6:
//
//    • Calibrated         — `±5 MM · CALIBRATED`  (olive)
//    • LiDAR uncalibrated — `±1″ · LIDAR`          (text/white on glass-dense)
//    • Visual SLAM        — `±2″ · VISUAL`         (tan)
//    • No depth           — `NO DEPTH · ESTIMATE`  (textMute grey)
//
//  Format: Cake Mono Light at the chrome size, JetBrains Mono for the
//  numeric/symbol portion (tabular-lining, slashed zero per OPS spec).
//  Single chip; the optional `COPLANAR ONLY` chip below it is a separate
//  view rendered by `DimensionedAnnotationView` so this stays composable.
//
//  Animation: a single `pulse(...)` API for the §5.3 row-6 calibration
//  confirm beat — scale 1.0 → 1.06 → 1.0 over 240 ms + olive opacity
//  ramp, honoring `accessibilityReduceMotion` with a color fade fallback.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.6 §5.3
//

import SwiftUI

public enum AccuracyState: Equatable {
    case calibrated         // ±5 MM · CALIBRATED — olive
    case lidarUncalibrated  // ±1″ · LIDAR — neutral
    case visualSlam         // ±2″ · VISUAL — tan
    case noDepth            // NO DEPTH · ESTIMATE — textMute

    public var displayText: String {
        switch self {
        case .calibrated:        return "\u{00B1}5 MM \u{00B7} CALIBRATED"
        case .lidarUncalibrated: return "\u{00B1}1\u{2033} \u{00B7} LIDAR"
        case .visualSlam:        return "\u{00B1}2\u{2033} \u{00B7} VISUAL"
        case .noDepth:           return "NO DEPTH \u{00B7} ESTIMATE"
        }
    }
}

public struct AccuracyBadge: View {

    public let state: AccuracyState
    /// External trigger for the calibration-confirm pulse (§5.3 row 6).
    /// Toggle to true (the view watches `.onChange` and runs the pulse once,
    /// then resets internally).
    public var pulseTrigger: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0
    @State private var fillOpacity: Double = 1.0

    public init(state: AccuracyState, pulseTrigger: Bool = false) {
        self.state = state
        self.pulseTrigger = pulseTrigger
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(state.displayText)
                .font(.custom("CakeMono-Light", size: 11))
                .tracking(1)
                .foregroundColor(textColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(fillColor.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
        )
        .scaleEffect(scale)
        .onChange(of: pulseTrigger) { _, newValue in
            guard newValue else { return }
            runPulse()
        }
        .accessibilityElement()
        .accessibilityLabel("Accuracy: \(state.displayText)")
    }

    // MARK: - Animation (§5.3 row 6)

    private func runPulse() {
        guard !reduceMotion else {
            // Reduced-motion fallback: 200 ms color fade only.
            withAnimation(OPSStyle.Animation.smooth) {
                fillOpacity = 0.6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                withAnimation(OPSStyle.Animation.smooth) {
                    fillOpacity = 1.0
                }
            }
            return
        }
        // Spec row 6: scale 1.0 → 1.06 → 1.0 over 240 ms + fill opacity
        // 0.8 → 1.0 → 0.8 simultaneous, single OPS curve.
        let curve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12)
        withAnimation(curve) {
            scale = 1.06
            fillOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(curve) {
                scale = 1.0
                fillOpacity = 0.8
            }
        }
    }

    // MARK: - Tokens (§3.6)

    private var fillColor: Color {
        switch state {
        case .calibrated:        return OPSStyle.Colors.olive.opacity(0.85)
        case .lidarUncalibrated: return Color.black.opacity(0.78)
        case .visualSlam:        return OPSStyle.Colors.tan.opacity(0.85)
        case .noDepth:           return OPSStyle.Colors.textMute.opacity(0.85)
        }
    }

    private var textColor: Color {
        switch state {
        case .calibrated, .visualSlam, .noDepth: return Color.black
        case .lidarUncalibrated:                 return OPSStyle.Colors.text
        }
    }

    private var borderColor: Color {
        switch state {
        case .calibrated:        return OPSStyle.Colors.oliveLine
        case .lidarUncalibrated: return OPSStyle.Colors.glassBorder
        case .visualSlam:        return OPSStyle.Colors.tanLine
        case .noDepth:           return OPSStyle.Colors.line
        }
    }
}

/// `COPLANAR ONLY` chip rendered as a sibling below an `AccuracyBadge` when
/// `CalibrationResult.coplanarOnly == true`. Kept as a small standalone view
/// so the badge stack composes cleanly.
public struct CoplanarOnlyChip: View {
    public init() {}
    public var body: some View {
        Text("COPLANAR ONLY")
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .tracking(1)
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.tan.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .strokeBorder(OPSStyle.Colors.tanLine, lineWidth: 0.5)
                    )
            )
            .accessibilityElement()
            .accessibilityLabel("Coplanar only")
    }
}
