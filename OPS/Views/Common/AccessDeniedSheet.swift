//
//  AccessDeniedSheet.swift
//  OPS
//
//  Shown when a user taps a Spotlight result (or other deep link) that their
//  current role is no longer permitted to open. Honest and direct — no blame,
//  no tech jargon, clear next step.
//

import SwiftUI

struct AccessDeniedSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            Image(OPSStyle.Icons.navSetSecurity)
                .font(.system(size: 64, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("ACCESS RESTRICTED")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(message)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing5)

            Text("Contact your admin if you need access.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing5)

            Spacer()

            Button(action: { dismiss() }) {
                Text("OK")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing5)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
