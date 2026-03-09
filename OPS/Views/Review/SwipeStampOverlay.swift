//
//  SwipeStampOverlay.swift
//  OPS
//

import SwiftUI

/// Stamp overlay that appears as user drags a card in a direction.
struct SwipeStampOverlay: View {
    let direction: SwipeDirection
    let progress: CGFloat // 0.0 to 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(direction.color.opacity(0.2 * Double(progress)))

            VStack(spacing: 8) {
                Image(systemName: direction.icon)
                    .font(.system(size: 48, weight: .bold))
                Text(direction.label)
                    .font(OPSStyle.Typography.headingBold)
                    .tracking(1.2)
            }
            .foregroundColor(direction.color)
            .opacity(Double(progress))
            .rotationEffect(.degrees(direction.stampRotation))
        }
        .allowsHitTesting(false)
    }
}
