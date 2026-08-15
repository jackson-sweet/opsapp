//
//  CalendarSiteVisitCard.swift
//  OPS
//
//  A booked site visit on the day canvas — the calendar's third source,
//  beside project tasks and personal events. Tan is the design system's
//  site-visit semantic; the mobile status-tag tokens keep it legible in sun.
//
//  Visits are appointments, not tasks: no drag-reschedule, no cascade, no
//  crew scheduling. Tap raises the same branch grammar as every lead
//  surface — start it, move it, or open the lead.
//

import SwiftUI

struct CalendarSiteVisitCard: View {
    let leadName: String
    let address: String?
    let scheduledAt: Date
    let durationMinutes: Int
    let isInProgress: Bool
    let onTap: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var windowLine: String {
        let start = Self.timeFormatter.string(from: scheduledAt)
        let end = Self.timeFormatter.string(
            from: scheduledAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        )
        return "\(start) – \(end)".uppercased()
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            iconTile

            VStack(alignment: .leading, spacing: 5) {
                Text(leadName)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(windowLine)
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .monospacedDigit()
                    if let address, !address.isEmpty {
                        Text(address)
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusTag
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(OPSStyle.Colors.tanFillM)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Site visit, \(leadName), \(windowLine.lowercased())")
        .accessibilityAddTraits(.isButton)
    }

    // CalendarUserEventCard's iconTile anatomy exactly — the three sources
    // must read as siblings on the day canvas.
    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(OPSStyle.Colors.tanFillM)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .stroke(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
                )

            Image(systemName: OPSStyle.Icons.camera)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tanTextM)
        }
        .frame(width: 34, height: 34)
    }

    private var statusTag: some View {
        Text(isInProgress ? "ON SITE" : "BOOKED")
            .font(OPSStyle.Typography.miniLabelBold)
            .tracking(1.2)
            .foregroundColor(OPSStyle.Colors.tanTextM)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.tanFillM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
