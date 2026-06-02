import SwiftUI

// MARK: - GuidedStockDoneView
//
// DONE stage (spec §7.4) — shown after commitAll completes successfully.
// Displays a centered hero title, a summary line of what was built, and
// three action buttons: DONE (dismiss), REFINE IN ADVANCED (open catalog
// setup sheet), ADD MORE (reset flow to CAPTURE for additional items).
//
// The container (GuidedStockSetupFlow) owns all three action closures so
// this view remains purely presentational with no direct dependencies on
// DataController, model, or navigation state.

struct GuidedStockDoneView: View {

    let summary: GuidedStockSummary
    var onDone: () -> Void
    var onRefineInAdvanced: () -> Void
    var onAddMore: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: OPSStyle.Layout.spacing5)

                // MARK: Hero title
                Text("STOCK SYSTEM BUILT")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                Spacer(minLength: OPSStyle.Layout.spacing4)

                // MARK: Summary line — JetBrains Mono / dataValue for field readability
                Text(GuidedStockSetupModel.summaryLine(summary))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                Spacer(minLength: OPSStyle.Layout.spacing5)

                // MARK: Action buttons
                VStack(spacing: OPSStyle.Layout.spacing2) {

                    // Primary — DONE
                    Button {
                        onDone()
                    } label: {
                        Text("DONE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done — close setup")

                    // Secondary — REFINE IN ADVANCED
                    Button {
                        onRefineInAdvanced()
                    } label: {
                        Text("REFINE IN ADVANCED")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.separator, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open advanced catalog setup")

                    // Tertiary — ADD MORE
                    Button {
                        onAddMore()
                    } label: {
                        Text("ADD MORE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add more items to stock")
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                Spacer(minLength: OPSStyle.Layout.spacing4)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
