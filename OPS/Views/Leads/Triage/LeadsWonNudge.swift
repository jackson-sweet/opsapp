//
//  LeadsWonNudge.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the compact "won → convert to jobs"
//  banner. Surfaces deals marked won that haven't been turned into projects yet
//  (`triageBuckets.unconvertedWon`); tapping starts the conversion flow.
//

import SwiftUI

struct LeadsWonNudge: View {
    let count: Int
    let totalValue: Double
    var onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.oliveFillM))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) WON · \(BooksFormat.compact(totalValue))")
                        .font(OPSStyle.Typography.miniLabelBold)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                        .monospacedDigit()
                    Text(count == 1 ? "Convert to a job" : "Convert to jobs")
                        .font(.custom("Mohave-Regular", size: 13))
                        .foregroundColor(OPSStyle.Colors.text2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous).fill(OPSStyle.Colors.oliveFillM.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous).strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityLabel("\(count) won, convert to jobs")
    }
}
