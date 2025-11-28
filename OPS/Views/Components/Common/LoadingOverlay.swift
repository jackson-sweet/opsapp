import SwiftUI

struct LoadingOverlayModifier: ViewModifier {
    @Binding var isPresented: Bool
    var message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    TacticalLoadingBarAnimated(
                        barCount: 8,
                        barWidth: 2,
                        barHeight: 10,
                        spacing: 4,
                        emptyColor: OPSStyle.Colors.inputFieldBorder,
                        fillColor: OPSStyle.Colors.primaryAccent
                    )

                    Text(message.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .tracking(2)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    func loadingOverlay(isPresented: Binding<Bool>, message: String = "Loading...") -> some View {
        modifier(LoadingOverlayModifier(isPresented: isPresented, message: message))
    }
}
