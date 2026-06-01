import SwiftUI

// MARK: - GuidedStockPrimeView
//
// PRIME screen — the opening stage of the guided stock setup wizard (spec §7.0).
// Explains the flow at a high level and gives the operator confidence to start.
// Owns its own START CTA; the flow container hides the bottom bar on .prime.

struct GuidedStockPrimeView: View {

    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            centerContent
            Spacer()
            bottomActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }

    // MARK: - Center content

    private var centerContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("SET UP STOCK")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Let's get everything you stock or sell into OPS. First you'll dump it all out — don't worry about organizing. Then we'll sort it into the right shape together.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStart()
            } label: {
                Text("START →")
            }
            .buttonStyle(GuidedPrimeCTAButtonStyle())
            .accessibilityLabel("Start guided stock setup")
            .accessibilityHint("Begins the stock capture step.")

            Text("// Takes a few minutes. You can stop and pick up where you left off.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }
}

// MARK: - GuidedPrimeCTAButtonStyle
//
// START button on the PRIME screen: full-width 52pt, primaryAccent solid fill,
// white text, buttonRadius corners. Distinct from the flow container's CTA style
// because PRIME owns its button directly (the container hides the bottom bar here).

private struct GuidedPrimeCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(OPSStyle.Colors.primaryAccent.opacity(configuration.isPressed ? 0.80 : 1.0))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}
