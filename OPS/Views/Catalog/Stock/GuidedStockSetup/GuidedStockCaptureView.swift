import SwiftUI

// MARK: - GuidedStockCaptureView
//
// CAPTURE stage scaffold — dump-everything-out phase of the guided stock wizard.
// Centered section title + intro; navigation and the ORGANIZE CTA are owned by
// GuidedStockSetupFlow. Later phases replace this body with the real capture inputs.

struct GuidedStockCaptureView: View {

    @ObservedObject var model: GuidedStockSetupModel

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("WHAT DO YOU STOCK OR SELL?")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Add each thing. We'll organize it next.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }
}
