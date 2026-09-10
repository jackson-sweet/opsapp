//
//  VinylOrderQAHost.swift
//  OPS
//
//  DEBUG-only harness for the vinyl ORDER LAYOUT workspace (bugs 317da29f and
//  1a8e48af). Launch with `-OPS_VINYL_ORDER_QA`.
//
//  It renders the REAL `VinylOrderWorkspace` against a synthetic L-shaped deck,
//  in the same `.fullScreenCover` presentation the order sheet uses, and opens
//  it on appear so a single `simctl launch` + `simctl io screenshot` lands on
//  the screen under review. Closing returns to this card, whose numbers show
//  that a setting turned inside the workspace really did re-plan.
//
//  No auth, no network, no SwiftData: the workspace takes plain values, so the
//  harness re-plans through `VinylCutListEngine.makePlan` and nothing else.
//

#if DEBUG
import SwiftUI

struct VinylOrderQAHost: View {
    @State private var settings = VinylOrderSettings.default
    @State private var plan = VinylOrderQAFixture.plan()
    @State private var viewport = VinylOrderViewportState()
    @State private var isShowingWorkspace = false
    @State private var replanCount = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("// VINYL ORDER QA")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)

                Text(VinylOrderWorkspaceCopy.summaryLine(for: plan))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .monospacedDigit()
                    .accessibilityIdentifier("qa_vinyl_summary")

                Text("REPLANS \(replanCount)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
                    .accessibilityIdentifier("qa_vinyl_replans")

                Button {
                    isShowingWorkspace = true
                } label: {
                    Text("OPEN ORDER LAYOUT")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                        .nestedCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("qa_vinyl_open")

                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing5)
        }
        .preferredColorScheme(.dark)
        .onAppear { isShowingWorkspace = true }
        .fullScreenCover(isPresented: $isShowingWorkspace) {
            VinylOrderWorkspace(
                plan: plan,
                projectTitle: VinylOrderQAFixture.projectTitle,
                deckTitle: VinylOrderQAFixture.deckTitle,
                measurementSystem: .imperial,
                settings: $settings,
                viewport: $viewport,
                onSettingsChanged: recomputePlan,
                onClose: { isShowingWorkspace = false }
            )
        }
    }

    private func recomputePlan() {
        plan = VinylOrderQAFixture.plan(settings: settings)
        replanCount += 1
    }
}
#endif
