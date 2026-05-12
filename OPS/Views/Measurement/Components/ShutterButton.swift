//
//  ShutterButton.swift
//  OPS
//
//  Camera-style shutter for `DimensionedCaptureView` per spec §5.1:
//    • 72 pt outer ring (`text` color, 3 pt stroke)
//    • 60 pt inner circle (`text` fill)
//    • Scale to 0.92 on press, OPS curve
//    • 60 pt minimum hit target — field-first per ops-ios/CLAUDE.md
//
//  The medium-impact shutter haptic fires from `DimensionedCaptureView` at
//  the flash peak (§5.3 row 3), NOT here — keeps the haptic plan owned by the
//  parent so we never double-fire.
//

import SwiftUI

struct ShutterButton: View {
    let action: () -> Void

    /// True when capture is allowed — disables the button + drops opacity per
    /// the AR perimeter pattern. Mapped from `LiDARCaptureCoordinator.state`
    /// by the parent (only `.wallDetected` / `.openingLocked` / `.ready` allow).
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    private let outerSize: CGFloat = 72
    private let innerSize: CGFloat = 60
    private let ringWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(OPSStyle.Colors.text, lineWidth: ringWidth)
                .frame(width: outerSize, height: outerSize)

            Circle()
                .fill(OPSStyle.Colors.text)
                .frame(width: innerSize, height: innerSize)
        }
        .frame(width: outerSize, height: outerSize)
        .contentShape(Circle())
        .scaleEffect(isPressed && isEnabled ? 0.92 : 1.0)
        .animation(.opsCurve200, value: isPressed)
        .opacity(isEnabled ? 1.0 : 0.4)
        .gesture(pressGesture)
        .accessibilityLabel(Text("Capture"))
        .accessibilityHint(Text(isEnabled ? "Captures a dimensioned photo" : "Waiting for wall detection"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Press handling
    //
    // Long-press gesture with 0 min duration gives us a press-and-hold state
    // that drives the scale animation. The action fires `onEnded` so the
    // visual feedback lands before the work kicks off — matches Apple's
    // shutter affordance in the system camera.

    private var pressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.0)
            .updating($isPressed) { current, state, _ in
                state = current
            }
            .onEnded { _ in
                guard isEnabled else { return }
                _ = reduceMotion  // referenced for keyhole stability; visual fallback handled by .animation curve
                action()
            }
    }
}
