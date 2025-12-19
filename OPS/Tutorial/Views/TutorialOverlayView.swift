//
//  TutorialOverlayView.swift
//  OPS
//
//  Dark overlay with animated cutout for highlighting tutorial targets.
//  Uses compositing to create a "spotlight" effect on the target area.
//

import SwiftUI

/// Dark overlay that creates a spotlight effect by cutting out a target area
struct TutorialOverlayView: View {
    /// The frame of the area to reveal (in global coordinates)
    let cutoutFrame: CGRect

    /// Corner radius for the cutout
    let cornerRadius: CGFloat

    /// Padding around the cutout frame
    let padding: CGFloat

    /// Opacity of the dark overlay
    let overlayOpacity: Double

    /// Creates a tutorial overlay with a cutout
    /// - Parameters:
    ///   - cutoutFrame: The frame to reveal through the overlay
    ///   - cornerRadius: Corner radius for the rounded cutout (default: 12)
    ///   - padding: Extra padding around the cutout (default: 8)
    ///   - overlayOpacity: Opacity of the dark overlay (default: 0.6)
    init(
        cutoutFrame: CGRect,
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 8,
        overlayOpacity: Double = 0.6
    ) {
        self.cutoutFrame = cutoutFrame
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.overlayOpacity = overlayOpacity
    }

    var body: some View {
        GeometryReader { geometry in
            // Dark overlay with cutout
            Color.black.opacity(overlayOpacity)
                .compositingGroup()
                .mask(
                    ZStack {
                        // Full rectangle
                        Rectangle()
                            .fill(Color.white)

                        // Cutout area (if frame is valid)
                        if cutoutFrame != .zero {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .frame(
                                    width: cutoutFrame.width + padding * 2,
                                    height: cutoutFrame.height + padding * 2
                                )
                                .position(
                                    x: cutoutFrame.midX,
                                    y: cutoutFrame.midY
                                )
                                .blendMode(.destinationOut)
                        }
                    }
                )
                .ignoresSafeArea()
        }
        // Don't capture touches - allow passthrough to content below
        .allowsHitTesting(false)
        // Animate cutout position changes
        .animation(.easeInOut(duration: 0.3), value: cutoutFrame)
    }
}

// MARK: - Animated Highlight Border

/// Optional animated border around the cutout area for extra emphasis
struct TutorialHighlightBorder: View {
    let cutoutFrame: CGRect
    let cornerRadius: CGFloat
    let padding: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        if cutoutFrame != .zero {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                .frame(
                    width: cutoutFrame.width + padding * 2,
                    height: cutoutFrame.height + padding * 2
                )
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .position(
                    x: cutoutFrame.midX,
                    y: cutoutFrame.midY
                )
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.05
                        pulseOpacity = 1.0
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: cutoutFrame)
        }
    }
}

// MARK: - Combined Overlay with Highlight

/// Complete tutorial overlay with both the dark mask and highlight border
struct TutorialSpotlight: View {
    let cutoutFrame: CGRect
    let cornerRadius: CGFloat
    let padding: CGFloat
    let showHighlight: Bool

    init(
        cutoutFrame: CGRect,
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 8,
        showHighlight: Bool = true
    ) {
        self.cutoutFrame = cutoutFrame
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.showHighlight = showHighlight
    }

    var body: some View {
        ZStack {
            TutorialOverlayView(
                cutoutFrame: cutoutFrame,
                cornerRadius: cornerRadius,
                padding: padding
            )

            if showHighlight {
                TutorialHighlightBorder(
                    cutoutFrame: cutoutFrame,
                    cornerRadius: cornerRadius,
                    padding: padding
                )
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background content
            VStack {
                Text("Background Content")
                    .foregroundColor(.white)

                Button("Target Button") {
                    // Action
                }
                .padding()
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.background)

            // Overlay with cutout
            TutorialSpotlight(
                cutoutFrame: CGRect(x: 150, y: 400, width: 120, height: 44)
            )
        }
    }
}
#endif
