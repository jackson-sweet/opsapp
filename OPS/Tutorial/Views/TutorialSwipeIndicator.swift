//
//  TutorialSwipeIndicator.swift
//  OPS
//
//  Slide-to-unlock style shimmer animation indicator for swipe gestures.
//  Shows directional arrows with animated shimmer effect.
//

import SwiftUI

/// Animated swipe indicator with shimmer effect for tutorial hints
struct TutorialSwipeIndicator: View {
    /// Direction of the swipe hint
    let direction: TutorialSwipeDirection

    /// The target frame where the indicator should appear
    let targetFrame: CGRect

    /// Animation state
    @State private var shimmerOffset: CGFloat = -100

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Arrow indicators
                arrowStack
                    .position(x: targetFrame.midX, y: targetFrame.midY)

                // Shimmer gradient overlay
                shimmerGradient
                    .mask(
                        RoundedRectangle(cornerRadius: 8)
                            .frame(width: targetFrame.width, height: targetFrame.height)
                            .position(x: targetFrame.midX, y: targetFrame.midY)
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startShimmerAnimation()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var arrowStack: some View {
        switch direction {
        case .left, .right:
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    arrowImage
                        .opacity(Double(index + 1) / 3.0 * 0.8)
                }
            }
        case .up, .down:
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    arrowImage
                        .opacity(Double(index + 1) / 3.0 * 0.8)
                }
            }
        }
    }

    private var arrowImage: some View {
        Image(systemName: arrowIcon)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
    }

    private var shimmerGradient: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.4), .clear],
            startPoint: shimmerStartPoint,
            endPoint: shimmerEndPoint
        )
        .frame(width: shimmerWidth, height: shimmerHeight)
        .offset(shimmerOffsetValue)
        .position(x: targetFrame.midX, y: targetFrame.midY)
    }

    // MARK: - Computed Properties

    private var arrowIcon: String {
        switch direction {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        }
    }

    private var shimmerStartPoint: UnitPoint {
        switch direction {
        case .left: return .trailing
        case .right: return .leading
        case .up: return .bottom
        case .down: return .top
        }
    }

    private var shimmerEndPoint: UnitPoint {
        switch direction {
        case .left: return .leading
        case .right: return .trailing
        case .up: return .top
        case .down: return .bottom
        }
    }

    private var shimmerWidth: CGFloat {
        switch direction {
        case .left, .right:
            return targetFrame.width + 200
        case .up, .down:
            return targetFrame.width
        }
    }

    private var shimmerHeight: CGFloat {
        switch direction {
        case .left, .right:
            return targetFrame.height
        case .up, .down:
            return targetFrame.height + 200
        }
    }

    private var shimmerOffsetValue: CGSize {
        switch direction {
        case .left:
            return CGSize(width: -shimmerOffset, height: 0)
        case .right:
            return CGSize(width: shimmerOffset, height: 0)
        case .up:
            return CGSize(width: 0, height: -shimmerOffset)
        case .down:
            return CGSize(width: 0, height: shimmerOffset)
        }
    }

    // MARK: - Animation

    private func startShimmerAnimation() {
        shimmerOffset = -150

        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            shimmerOffset = 150
        }
    }
}

// MARK: - Simple Swipe Arrow Indicator

/// Simpler animated arrow indicator without the shimmer effect
struct SimpleSwipeIndicator: View {
    let direction: TutorialSwipeDirection

    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: arrowIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.3 + Double(index) * 0.25))
            }
        }
        .offset(animationOffset)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                offset = 10
            }
        }
    }

    private var arrowIcon: String {
        switch direction {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        }
    }

    private var animationOffset: CGSize {
        switch direction {
        case .left: return CGSize(width: -offset, height: 0)
        case .right: return CGSize(width: offset, height: 0)
        case .up: return CGSize(width: 0, height: -offset)
        case .down: return CGSize(width: 0, height: offset)
        }
    }
}

// MARK: - Positioned Swipe Indicator

/// Swipe indicator positioned relative to a target frame
struct PositionedSwipeIndicator: View {
    let direction: TutorialSwipeDirection
    let targetFrame: CGRect
    let showShimmer: Bool

    init(
        direction: TutorialSwipeDirection,
        targetFrame: CGRect,
        showShimmer: Bool = true
    ) {
        self.direction = direction
        self.targetFrame = targetFrame
        self.showShimmer = showShimmer
    }

    var body: some View {
        if showShimmer {
            TutorialSwipeIndicator(
                direction: direction,
                targetFrame: targetFrame
            )
        } else {
            SimpleSwipeIndicator(direction: direction)
                .position(x: targetFrame.midX, y: targetFrame.midY)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialSwipeIndicator_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // Target card
                RoundedRectangle(cornerRadius: 12)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(width: 200, height: 80)
                    .overlay(
                        Text("Swipe Me")
                            .foregroundColor(.white)
                    )

                // Simple indicators for each direction
                HStack(spacing: 30) {
                    SimpleSwipeIndicator(direction: .left)
                    SimpleSwipeIndicator(direction: .right)
                    SimpleSwipeIndicator(direction: .up)
                    SimpleSwipeIndicator(direction: .down)
                }
            }

            // Full shimmer indicator
            TutorialSwipeIndicator(
                direction: .right,
                targetFrame: CGRect(x: 100, y: 200, width: 200, height: 80)
            )
        }
    }
}
#endif
