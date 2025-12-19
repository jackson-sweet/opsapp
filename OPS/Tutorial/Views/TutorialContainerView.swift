//
//  TutorialContainerView.swift
//  OPS
//
//  80% scaled container for tutorial content with proper touch passthrough.
//  Positions content in the upper portion of the screen to make room for tooltips.
//

import SwiftUI

/// Container view that scales content to 80% for the tutorial experience
/// Positions content at the top of the screen with room for tooltips below
struct TutorialContainerView<Content: View>: View {
    let content: Content
    let scale: CGFloat

    /// Creates a tutorial container with specified scale
    /// - Parameters:
    ///   - scale: The scale factor for the content (default: 0.8 = 80%)
    ///   - content: The view content to display
    init(scale: CGFloat = 0.8, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.scale = scale
    }

    var body: some View {
        GeometryReader { geometry in
            // Calculate the scaled content dimensions
            let scaledWidth = geometry.size.width
            let scaledHeight = geometry.size.height * 0.75 // Leave 25% for tooltip area

            content
                .scaleEffect(scale)
                .frame(width: scaledWidth, height: scaledHeight)
                .clipped()
                // Position in upper portion of screen
                .position(
                    x: geometry.size.width / 2,
                    y: scaledHeight / 2
                )
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialContainerView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialContainerView {
            VStack {
                Text("Tutorial Content")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Button("Action") {
                    // Preview action
                }
                .padding()
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.background)
        }
        .background(Color.gray.opacity(0.3))
    }
}
#endif
