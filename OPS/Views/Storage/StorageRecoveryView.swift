import SwiftUI

/// No model context or authenticated service is required to render this screen.
struct StorageRecoveryView: View {
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                Text("LOCAL DATA UNAVAILABLE")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("OPS couldn't open your local data. Your stored files have been kept on this device.")
                    .font(OPSStyle.Typography.body)
                    .foregroundStyle(OPSStyle.Colors.primaryText)

                Text("Retry. If this continues, contact OPS support before reinstalling. Work waiting to sync may only exist on this device.")
                    .font(OPSStyle.Typography.body)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, OPSStyle.Layout.emptyStatePadding)
        }
        .safeAreaInset(edge: .bottom) {
            Button("RETRY") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                retry()
            }
            .opsPrimaryButtonStyle()
            .padding(OPSStyle.Layout.contentPadding)
            .background(OPSStyle.Colors.background)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
