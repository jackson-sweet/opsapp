//
//  TacticalLoadingBar.swift
//  OPS
//
//  Minimal loading indicator using vertical bars
//  Matches OPS tactical minimalism design philosophy
//

import SwiftUI

/// Tactical loading bar with vertical bars that fill as progress increases
/// Designed for tactical minimalism - no animations, just clean progress indication
struct TacticalLoadingBar: View {
    let progress: Double // 0.0 to 1.0
    let barCount: Int
    let barWidth: CGFloat
    let barHeight: CGFloat
    let spacing: CGFloat
    let emptyColor: Color
    let fillColor: Color

    init(
        progress: Double = 0.5,
        barCount: Int = 8,
        barWidth: CGFloat = 2,
        barHeight: CGFloat = 6,
        spacing: CGFloat = 4,
        emptyColor: Color = Color.white.opacity(0.2),
        fillColor: Color = Color.white.opacity(0.6)
    ) {
        self.progress = min(max(progress, 0.0), 1.0) // Clamp between 0 and 1
        self.barCount = barCount
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.spacing = spacing
        self.emptyColor = emptyColor
        self.fillColor = fillColor
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Rectangle()
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight)
            }
        }
    }

    /// Determine color based on progress
    private func barColor(for index: Int) -> Color {
        let progressBarCount = Int(ceil(Double(barCount) * progress))
        return index < progressBarCount ? fillColor : emptyColor
    }
}

/// Animated version with subtle pulse effect for indeterminate loading
struct TacticalLoadingBarAnimated: View {
    let barCount: Int
    let barWidth: CGFloat
    let barHeight: CGFloat
    let spacing: CGFloat
    let emptyColor: Color
    let fillColor: Color

    @State private var animationOffset: Int = 0
    @State private var timer: Timer?

    init(
        barCount: Int = 8,
        barWidth: CGFloat = 2,
        barHeight: CGFloat = 6,
        spacing: CGFloat = 4,
        emptyColor: Color = Color.white.opacity(0.2),
        fillColor: Color = Color.white.opacity(0.6)
    ) {
        self.barCount = barCount
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.spacing = spacing
        self.emptyColor = emptyColor
        self.fillColor = fillColor
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Rectangle()
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }

    /// Determine color based on animation
    private func barColor(for index: Int) -> Color {
        // Create a wave effect - 3 bars are lit at a time
        let activeRange = 3
        let normalizedIndex = (index + barCount - animationOffset) % barCount
        return normalizedIndex < activeRange ? fillColor : emptyColor
    }

    private func startAnimation() {
        // Stop any existing timer
        stopAnimation()

        // Create and store timer reference
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.linear(duration: 0.15)) {
                animationOffset = (animationOffset + 1) % barCount
            }
        }

        // Ensure timer fires on main run loop
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview("Determinate Progress") {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack(spacing: 40) {
            VStack(spacing: 8) {
                Text("0% Progress")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TacticalLoadingBar(progress: 0.0)
            }

            VStack(spacing: 8) {
                Text("25% Progress")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TacticalLoadingBar(progress: 0.25)
            }

            VStack(spacing: 8) {
                Text("50% Progress")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TacticalLoadingBar(progress: 0.5)
            }

            VStack(spacing: 8) {
                Text("75% Progress")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TacticalLoadingBar(progress: 0.75)
            }

            VStack(spacing: 8) {
                Text("100% Progress")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TacticalLoadingBar(progress: 1.0)
            }
        }
    }
}

#Preview("Animated Loading") {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Indeterminate Loading")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            TacticalLoadingBarAnimated()
        }
    }
}
