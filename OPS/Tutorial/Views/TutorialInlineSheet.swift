//
//  TutorialInlineSheet.swift
//  OPS
//
//  Custom sheet presentation that stays in the same view hierarchy.
//  Unlike native iOS sheets, this allows tutorial overlays (tooltips) to appear on top.
//  Mimics native sheet appearance with slide-up animation, rounded corners, and drag-to-dismiss.
//

import SwiftUI

/// Custom sheet overlay that presents content within the same view hierarchy
/// This allows tutorial tooltips to remain visible on top of the "sheet"
struct TutorialInlineSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content
    let interactiveDismissDisabled: Bool

    /// Animation state
    @State private var dragOffset: CGFloat = 0
    @State private var appeared: Bool = false

    init(isPresented: Binding<Bool>, interactiveDismissDisabled: Bool = false, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.interactiveDismissDisabled = interactiveDismissDisabled
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.black
                    .opacity(appeared ? 0.4 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !interactiveDismissDisabled {
                            dismiss()
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: appeared)

                // Sheet content
                VStack(spacing: 0) {
                    Spacer()

                    ZStack(alignment: .top) {
                        // Sheet content - NavigationView takes full height
                        content
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 20,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 20
                                )
                            )

                        // Drag indicator - only shown when dismiss is allowed
                        if !interactiveDismissDisabled {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 36, height: 5)
                                .padding(.top, 8)
                        }
                    }
                    .frame(height: geometry.size.height * 0.92) // Cover 92% of screen for nav bar visibility
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 20
                        )
                        .fill(OPSStyle.Colors.background)
                    )
                    .offset(y: appeared ? dragOffset : geometry.size.height)
                    .gesture(
                        interactiveDismissDisabled ? nil : DragGesture()
                            .onChanged { value in
                                // Only allow dragging down
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                // Dismiss if dragged far enough or with enough velocity
                                if value.translation.height > 120 || value.predictedEndTranslation.height > 200 {
                                    dismiss()
                                } else {
                                    // Snap back
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appeared)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                }
            }
        }
        .onAppear {
            // Animate in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            appeared = false
            dragOffset = 0
        }
        // Delay actual dismissal to allow animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialInlineSheet_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var showSheet = true

        var body: some View {
            ZStack {
                // Background content
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack {
                    Text("Main Content")
                        .foregroundColor(.white)

                    Button("Show Sheet") {
                        showSheet = true
                    }
                    .padding()
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(8)
                }

                // Inline sheet
                if showSheet {
                    TutorialInlineSheet(isPresented: $showSheet) {
                        VStack {
                            Text("Sheet Content")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)

                            Spacer()

                            Button("Close") {
                                showSheet = false
                            }
                            .padding()
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(8)
                            .padding(.bottom, 40)
                        }
                        .padding()
                    }
                }

                // Tooltip stays on top
                VStack {
                    TutorialTooltipCard(text: "This tooltip stays visible!", animated: false)
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                    Spacer()
                }
            }
        }
    }

    static var previews: some View {
        PreviewContainer()
    }
}
#endif
