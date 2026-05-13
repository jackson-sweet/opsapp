//
//  HelperTextOverlay.swift
//  OPS
//
//  Pre-shutter helper chip rendered above the bottom bar of §5.1.
//  Six progressive states map directly off `LiDARCaptureCoordinator.CaptureState`
//  per the spec table:
//
//    Warm-up         → `// INITIALIZING …`
//    Idle (no plane) → `// AIM AT OPENING`
//    Searching       → `// SEARCHING`
//    Wall detected   → `// WALL DETECTED`
//    Opening locked  → `// OPENING LOCKED`
//    Calibration     → `// CALIBRATE · PLACE CARD ON SURFACE`
//    Post-capture    → `// CAPTURED · 0.07s`   (driven by parent flash flag)
//
//  Voice rules: `//` prefix, JetBrains Mono for numbers, sunlight-legible
//  shadow per spec §5.1. Cake Mono Light for body. UPPERCASE at the call site
//  via `.textCase(.uppercase)`.
//
//  Motion (full): offset y −8 → 0 + opacity 0 → 1 over 200 ms (enter),
//  identical reverse on exit, OPS curve. No haptic — paired with shutter haptic.
//  Motion (reduced): fade only, no offset.
//

import SwiftUI

struct HelperTextOverlay: View {
    let state: HelperState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Text("//")
                .font(.panelTitle)
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(state.copy)
                .font(.buttonLabel)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(state.foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(OPSStyle.Colors.glassDenseApprox)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: 1)
                )
        )
        // Sunlight legibility per spec §5.1 — root CLAUDE.md mandates ≥7:1 contrast.
        .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)
        .transition(transition)
        .id(state.id) // forces the transition to re-fire on state change
        .accessibilityLabel(Text(state.copy))
    }

    private var transition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(.opsCurve200)
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)).animation(.opsCurve200),
            removal: .opacity.animation(.opsCurve200)
        )
    }
}

// MARK: - State

extension HelperTextOverlay {
    /// The six progressive states from spec §5.1. The mapping from
    /// `LiDARCaptureCoordinator.CaptureState` is in `DimensionedCaptureView`.
    enum HelperState: String, CaseIterable, Identifiable, Equatable {
        case initializing
        case aimAtOpening
        case searching
        case wallDetected
        case openingLocked
        case calibration
        case capturedFlash

        public var id: String { rawValue }

        /// The literal copy from the spec — DO NOT paraphrase; the spec table is canonical.
        public var copy: String {
            switch self {
            case .initializing:    return "INITIALIZING …"
            case .aimAtOpening:    return "AIM AT OPENING"
            case .searching:       return "SEARCHING"
            case .wallDetected:    return "WALL DETECTED"
            case .openingLocked:   return "OPENING LOCKED"
            case .calibration:     return "CALIBRATE · PLACE CARD ON SURFACE"
            case .capturedFlash:   return "CAPTURED · 0.07S"
            }
        }

        /// Color ladder. Searching/wall-detected reads as neutral progress;
        /// opening-locked promotes to olive (positive); captured-flash stays
        /// neutral text per the spec (not a status color — it's a confirmation beat).
        public var foreground: Color {
            switch self {
            case .initializing, .aimAtOpening, .searching:
                return OPSStyle.Colors.text2
            case .wallDetected:
                return OPSStyle.Colors.text
            case .openingLocked:
                return OPSStyle.Colors.olive
            case .calibration:
                return OPSStyle.Colors.tan
            case .capturedFlash:
                return OPSStyle.Colors.text
            }
        }
    }
}
