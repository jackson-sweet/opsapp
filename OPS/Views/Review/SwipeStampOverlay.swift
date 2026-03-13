//
//  SwipeStampOverlay.swift
//  OPS
//

import SwiftUI

/// Stamp overlay that appears as user drags a card in a direction.
struct SwipeStampOverlay: View {
    let direction: SwipeDirection
    let progress: CGFloat // 0.0 to 1.0
    var actionConfig: SwipeActionConfig? = nil

    private var displayLabel: String { actionConfig?.label ?? direction.label }
    private var displayIcon: String { actionConfig?.icon ?? direction.icon }
    private var displayColor: Color { actionConfig?.color ?? direction.color }

    var body: some View {
        ZStack {
            // Fade-to-black as drag progresses
            Color.black.opacity(0.6 * Double(progress))

            // Subtle directional color tint
            displayColor.opacity(0.12 * Double(progress))

            VStack(spacing: 10) {
                Image(systemName: displayIcon)
                    .font(.system(size: 40, weight: .light))
                Text(displayLabel)
                    .font(OPSStyle.Typography.headingBold)
                    .tracking(2.0)
            }
            .foregroundColor(displayColor)
            .opacity(Double(progress))
            .rotationEffect(.degrees(direction.stampRotation))
        }
        .allowsHitTesting(false)
    }
}
