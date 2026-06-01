import SwiftUI

// MARK: - GuidedStockDoneView
//
// DONE stage scaffold — completion screen of the guided stock wizard.
// Centered section title + intro. The container's bottom bar is hidden for .done;
// close/follow-on actions are wired by GuidedStockSetupFlow via the onClose callback.
// Later phases replace this body with the real summary counts and next-step actions.

struct GuidedStockDoneView: View {

    @ObservedObject var model: GuidedStockSetupModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("STOCK SYSTEM BUILT")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Your stock is ready.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }
}
