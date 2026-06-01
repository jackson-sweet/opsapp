import SwiftUI

// MARK: - GuidedStockBlueprintView
//
// BLUEPRINT stage scaffold — pre-commit review phase of the wizard.
// Centered section title + intro; navigation, the BUILD IT CTA, and the offline
// banner are owned by GuidedStockSetupFlow. Later phases replace this body
// with the real blueprint cards and tap-to-edit interactions.

struct GuidedStockBlueprintView: View {

    @ObservedObject var model: GuidedStockSetupModel

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("YOUR BLUEPRINT")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Here's how we'll set it up. Tap anything to change it.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }
}
