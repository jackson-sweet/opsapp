//
//  UnlinkedInboxRow.swift
//  OPS
//
//  The one row that stands in for a pile of inbox notifications the app cannot
//  route (bug 589e3b1e). It replaces N identical dead taps with N counted once,
//  said plainly, and pointed at the surface that can actually clear them.
//
//  It deliberately offers no "open" action. Every member resolved to no lead;
//  a button here would land the operator on the LEADS tab with nothing to do —
//  which is the dead tap this row exists to remove. MARK READ appears only when
//  every member may honestly be marked read: a persistent row stands for an
//  unresolved condition, and `NotificationReadPolicy` forbids the rail from
//  clearing one (in production every member is persistent, so the row is
//  informational — the truth, not a lever that does nothing).
//

import SwiftUI
import UIKit

struct UnlinkedInboxRow: View {
    let group: UnlinkedInboxGroup
    let timestamp: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let onMarkRead: () -> Void

    private typealias Copy = NotificationInboxGrouping.Copy

    var body: some View {
        NotificationRowChrome(
            title: Copy.title,
            bodyText: bodyText,
            bodyAccessibilityLabel: Copy.body(count: group.count),
            timestamp: timestamp,
            isRead: group.isRead,
            isExpanded: isExpanded,
            onToggle: onToggle,
            icon: {
                // A reply is owed — the same glyph and tan attention tone the
                // `leads_waiting` rows these replace already carry.
                NotificationIconBadge(
                    systemName: "arrowshape.turn.up.left",
                    tint: OPSStyle.Colors.warningStatus
                )
            },
            detail: { detail }
        )
    }

    // MARK: - Body line

    /// Mono count, Mohave prose. Numbers are always mono (DESIGN.md §4), so the
    /// two halves carry different fonts and the row composes them.
    private var bodyText: Text {
        Text("\(group.count)")
            .font(OPSStyle.Typography.captionBold)
            .foregroundStyle(bodyTint)
        + Text(Copy.bodySuffix(count: group.count))
            .font(OPSStyle.Typography.smallBody)
            .foregroundStyle(bodyTint)
    }

    private var bodyTint: Color {
        group.isRead ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText
    }

    // MARK: - Expanded detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            NotificationDetailDivider()

            // The readout, not a restatement: the server's own row titles and
            // how many of each. This is what the operator was scrolling past
            // eighty-five times, said once. The sentence above already carries
            // the count and the next step — repeating it here would be noise.
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                ForEach(group.sources, id: \.title) { source in
                    sourceLine(source)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing1)

            if group.isMarkReadPermitted {
                NotificationActionButton(
                    label: Copy.markReadLabel,
                    systemImage: OPSStyle.Icons.checkmarkCircle,
                    action: onMarkRead
                )
            }

            Spacer().frame(height: OPSStyle.Layout.spacing2)
        }
    }

    private func sourceLine(_ source: UnlinkedInboxGroup.Source) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text("//")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.textMute)

            Text(source.title.uppercased())
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Text("\(source.count)")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .monospacedDigit()
        }
        .frame(minHeight: OPSStyle.Layout.spacing4)
    }
}
