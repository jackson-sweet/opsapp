//
//  LeadsCaughtUp.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the Leads "all caught up" state. Shown
//  when the active filter has no leads. An olive check ring + a terse status
//  line; no illustration, no coaching language (DESIGN.md empty-state rules).
//

import SwiftUI

struct LeadsCaughtUp: View {
    let title: String
    let label: String
    let hint: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.oliveFillM.opacity(0.4))
                Circle()
                    .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .frame(width: 54, height: 54)

            Text(title)
                .font(OPSStyle.Typography.screenTitle(for: title))
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.top, OPSStyle.Layout.spacing3)

            Text("// \(label)")
                .font(OPSStyle.Typography.miniLabel)
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.textMute)
                .padding(.top, OPSStyle.Layout.spacing2_5)

            Text("[ \(hint) ]")
                .font(OPSStyle.Typography.miniLabel)
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .multilineTextAlignment(.center)
                .padding(.top, OPSStyle.Layout.spacing2_5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
        .padding(.vertical, 40)
    }
}
