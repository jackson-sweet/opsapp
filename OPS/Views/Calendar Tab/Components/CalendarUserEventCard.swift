//
//  CalendarUserEventCard.swift
//  OPS
//
//  Card for personal events and time-off requests in the day canvas.
//  Personal events: dashed custom-event treatment.
//  Time-off: semantic status treatment with clock badge.
//

import SwiftUI

struct CalendarUserEventCard: View {
    let event: CalendarUserEvent
    let onTap: () -> Void
    let onDelete: () -> Void
    /// Opens the editor. Optional so older callers (none today) keep working.
    var onEdit: (() -> Void)? = nil
    var resizeDayCount: Int? = nil
    var onResizeSpan: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            iconTile

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title.isEmpty ? eventTypeFallback : event.title)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(dateRangeString)
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .frame(minHeight: 64)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius))
        .overlay(cardBorder)
        // Bug 3 — Match CalendarEventCard / CalendarProjectCard for consistent
        // vertical breathing room in week and day views.
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal)
        .onTapGesture {
            // Tap opens the editor when one's wired up (DayCanvasView), and
            // falls back to onTap (currently a no-op) for any legacy caller.
            if let onEdit { onEdit() } else { onTap() }
        }
        .resizableScheduleSpan(
            currentDayCount: resizeDayCount,
            enabled: onResizeSpan != nil,
            onCommit: { onResizeSpan?($0) }
        )
        .contextMenu {
            if onEdit != nil {
                Button { onEdit?() } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Subviews

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(iconBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .stroke(iconBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )

            Image(systemName: iconName)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(iconColor)
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if event.isTimeOff {
            Text(statusLabel)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(statusColor)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(statusBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .stroke(statusBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        } else {
            Text("CUSTOM")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .stroke(OPSStyle.Colors.secondaryText.opacity(0.4),
                                style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [3, 2]))
                )
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if event.isTimeOff {
            statusBackground
        } else {
            OPSStyle.Colors.surfaceInput
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        if event.isTimeOff {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .stroke(statusBorder, lineWidth: OPSStyle.Layout.Border.standard)
        } else {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .stroke(OPSStyle.Colors.cardBorder,
                        style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [4, 3]))
        }
    }

    // MARK: - Helpers

    private var eventTypeFallback: String {
        event.isTimeOff ? "TIME OFF REQUEST" : "PERSONAL EVENT"
    }

    private var iconName: String {
        if event.isTimeOff {
            switch event.eventStatus {
            case .pending:  return "clock.badge.questionmark"
            case .approved: return "clock.badge.checkmark"
            case .denied:   return "clock.badge.xmark"
            case .none:     return "clock"
            }
        }
        return "calendar.badge.plus"
    }

    private var statusLabel: String {
        switch event.eventStatus {
        case .pending:  return "PENDING"
        case .approved: return "APPROVED"
        case .denied:   return "DENIED"
        case .none:     return "TIME OFF"
        }
    }

    private var statusColor: Color {
        switch event.eventStatus {
        case .pending:  return OPSStyle.Colors.tanTextM
        case .approved: return OPSStyle.Colors.oliveTextM
        case .denied:   return OPSStyle.Colors.roseTextM
        case .none:     return OPSStyle.Colors.tanTextM
        }
    }

    private var statusBackground: Color {
        switch event.eventStatus {
        case .pending:  return OPSStyle.Colors.tanFillM
        case .approved: return OPSStyle.Colors.oliveFillM
        case .denied:   return OPSStyle.Colors.roseFillM
        case .none:     return OPSStyle.Colors.tanFillM
        }
    }

    private var statusBorder: Color {
        switch event.eventStatus {
        case .pending:  return OPSStyle.Colors.tanLineM
        case .approved: return OPSStyle.Colors.oliveLineM
        case .denied:   return OPSStyle.Colors.roseLineM
        case .none:     return OPSStyle.Colors.tanLineM
        }
    }

    private var iconColor: Color {
        event.isTimeOff ? statusColor : OPSStyle.Colors.primaryAccent
    }

    private var iconBackground: Color {
        event.isTimeOff ? statusBackground : OPSStyle.Colors.surfaceInput
    }

    private var iconBorder: Color {
        event.isTimeOff ? statusBorder : OPSStyle.Colors.cardBorder
    }

    private var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            return formatter.string(from: event.startDate).uppercased()
        }
        return "\(formatter.string(from: event.startDate).uppercased()) — \(formatter.string(from: event.endDate).uppercased())"
    }
}
