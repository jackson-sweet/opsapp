import SwiftUI

// MARK: - GuidedStockStructureView
//
// STRUCTURE stage scaffold — grouping and variant-resolution phase of the wizard.
// Centered section title + intro; navigation and the REVIEW CTA are owned by
// GuidedStockSetupFlow. Later phases replace this body with the real structure questions.

struct GuidedStockStructureView: View {

    @ObservedObject var model: GuidedStockSetupModel

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("LET'S SORT IT OUT")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("We'll group what's the same and split what's different.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }
}
