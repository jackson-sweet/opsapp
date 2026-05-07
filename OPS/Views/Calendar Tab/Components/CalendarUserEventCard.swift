//
//  CalendarUserEventCard.swift
//  OPS
//
//  Card for personal events and time-off requests in the day canvas.
//  Personal events: dashed border, dark fill.
//  Time-off requests: amber fill + border, status badge.
//

import SwiftUI

struct CalendarUserEventCard: View {
    let event: CalendarUserEvent
    let onTap: () -> Void
    let onDelete: () -> Void
    /// Opens the editor. Optional so older callers (none today) keep working.
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Content
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
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Status/type badge (top-right)
            VStack {
                statusBadge
                Spacer()
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
        .frame(minHeight: 64)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(cardBorder)
        // Bug 3 — Match CalendarEventCard / CalendarProjectCard for consistent
        // vertical breathing room in week and day views.
        .padding(.vertical, 8)
        .padding(.horizontal)
        .onTapGesture {
            // Tap opens the editor when one's wired up (DayCanvasView), and
            // falls back to onTap (currently a no-op) for any legacy caller.
            if let onEdit { onEdit() } else { onTap() }
        }
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

    @ViewBuilder
    private var statusBadge: some View {
        if event.isTimeOff {
            Text(statusLabel)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(statusColor.opacity(0.35), lineWidth: 0.5)
                )
        } else {
            Text("PERSONAL")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(OPSStyle.Colors.secondaryText.opacity(0.4),
                                style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                )
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if event.isTimeOff {
            // Amber tint for time-off
            Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.12)
        } else {
            // One step darker than cardBackgroundDark for personal events
            Color(red: 13/255, green: 13/255, blue: 13/255)
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        if event.isTimeOff {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.35),
                        lineWidth: 0.5)
        } else {
            // Dashed border for personal events
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        }
    }

    // MARK: - Helpers

    private var eventTypeFallback: String {
        event.isTimeOff ? "TIME OFF REQUEST" : "PERSONAL EVENT"
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
        case .pending:  return Color(red: 196/255, green: 168/255, blue: 104/255)  // amber
        case .approved: return Color(red: 165/255, green: 179/255, blue: 104/255)  // muted green
        case .denied:   return Color(red: 147/255, green: 50/255,  blue: 26/255)   // error red
        case .none:     return Color(red: 196/255, green: 168/255, blue: 104/255)
        }
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
