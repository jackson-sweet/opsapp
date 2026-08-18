//
//  CalendarHolidayCard.swift
//  OPS
//
//  Bug 23ecb01a — a statutory holiday on the day list, wearing the same
//  dashed treatment as a personal event so it reads as context around the
//  work rather than as work.
//
//  Deliberately inert: no tap, no edit, no delete, no drag. A statutory
//  holiday is a fact about the day, not something anybody schedules — giving
//  it controls would only invite taps that can do nothing.
//

import SwiftUI

struct CalendarHolidayCard: View {
    let holiday: StatutoryHoliday

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            iconTile

            VStack(alignment: .leading, spacing: 5) {
                Text(holiday.name)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(dateString)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            badge
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .frame(minHeight: 64)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .stroke(
                    OPSStyle.Colors.tanLineM,
                    style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [4, 3])
                )
        )
        // Matches CalendarUserEventCard / CalendarEventCard breathing room.
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(OPSStyle.Colors.tanFillM)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .stroke(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
                )

            Image(systemName: "flag.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tanTextM)
        }
        .frame(width: 34, height: 34)
    }

    private var badge: some View {
        Text(holiday.jurisdiction.badge)
            .font(OPSStyle.Typography.miniLabel)
            .foregroundColor(OPSStyle.Colors.tanTextM)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .stroke(
                        OPSStyle.Colors.tanLineM,
                        style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [3, 2])
                    )
            )
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: holiday.date).uppercased()
    }
}
