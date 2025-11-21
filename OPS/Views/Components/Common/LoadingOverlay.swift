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

                VStack(spacing: 16) {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryText)
                        .scaleEffect(1.2)

                    Text(message)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(24)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
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
