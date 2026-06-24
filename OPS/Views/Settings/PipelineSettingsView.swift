//
//  PipelineSettingsView.swift
//  OPS
//
//  Pipeline / call-logging preferences. Currently the around-call auto-log
//  switch (feature 154cb8a3) — when on, a call placed from a lead is logged
//  automatically on return instead of prompting.
//

import SwiftUI

struct PipelineSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoLogOutboundCalls") private var autoLogOutboundCalls = true

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(title: "Calls", onBackTapped: { dismiss() })
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        SettingsCard(title: "CALL LOGGING") {
                            SettingsToggle(
                                title: "Auto-log my calls",
                                description: "When you tap CALL on a lead, OPS logs the call for you when you come back. Turn off to be asked each time.",
                                isOn: $autoLogOutboundCalls
                            )
                        }

                        Text("// Only calls you place from a lead are logged. iPhone never shares your call history with apps, so calls from the keypad and incoming calls can't be logged automatically.")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, OPSStyle.Layout.spacing1)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
    }
}
