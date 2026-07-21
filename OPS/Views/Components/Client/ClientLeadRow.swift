//
//  ClientLeadRow.swift
//  OPS
//
//  One lead in the client-profile Leads section. Leads with the JOB (title) —
//  the "who" is already the page's subject — so the operator scans what work
//  is on the table and where it stands. Same visual grammar as the Projects
//  rows on ContactDetailView.
//
//  Spec: docs/superpowers/specs/2026-07-21-ios-client-leads-section-design.md
//

import SwiftUI

struct ClientLeadRow: View {
    let lead: Opportunity
    /// History (terminal) rows read quieter than live open leads.
    var isHistory: Bool = false

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(lead.stage.color)
                .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                if let valueText {
                    Text(valueText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Text(lead.stage.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(lead.stage.color)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(lead.stage.color.opacity(OPSStyle.Layout.Opacity.subtle))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(lead.stage.color.opacity(OPSStyle.Layout.Opacity.light), lineWidth: OPSStyle.Layout.Border.standard)
                )

            Image(systemName: "chevron.right")
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
        .opacity(isHistory ? 0.72 : 1)
    }

    // Job first; fall back to the contact when a lead has no title.
    private var primaryLabel: String {
        if let t = lead.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        return lead.displayContactName
    }

    // Won carries actualValue; open leads carry estimatedValue. One rule covers both.
    private var valueText: String? {
        guard let value = lead.actualValue ?? lead.estimatedValue else { return nil }
        return BooksFormat.compact(value)
    }
}
