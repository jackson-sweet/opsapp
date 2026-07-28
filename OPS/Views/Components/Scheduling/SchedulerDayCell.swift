//
//  SchedulerDayCell.swift
//  OPS
//
//  One day in the schedule sheet's month scroll.
//
//  The cell carries four independent readings without ever becoming a chart:
//
//    • DAY NUMBER  — mono, top-left. Today wears the accent (number + hairline
//      ring); the accent is a focus marker here, not a CTA.
//    • SIGNAL BARS — up to three 3pt bars along the bottom. White = this
//      project. Tan = the crew is booked. Tan + 45° hatch = the crew is off
//      (the hatch is a second, non-colour cue so the day still reads for a
//      colour-blind operator, and in direct sun).
//    • DENSITY DOT — one dim dot when the day holds work that touches neither
//      this crew nor this project. Presence, not detail.
//    • SELECTION   — white caps and a soft interior, drawn ABOVE the signals
//      so the operator's own pick is always the loudest thing on the grid.
//
//  Days before the dependency floor recede to 35% — a guide, never a gate.
//  Every day on the grid is tappable, including those.
//

import SwiftUI

struct SchedulerDayCell: View {
    let date: Date
    let signals: SchedulerDayContext.DaySignals
    let role: SchedulerSelection.DayRole
    let isToday: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            selectionBackground

            // Today's hairline ring — only when the day isn't already wearing
            // the selection's own chrome.
            if isToday && role == .none {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .strokeBorder(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(dayNumber)
                        .font(OPSStyle.Typography.dataValue)
                        .monospacedDigit()
                        .foregroundColor(numberColor)
                    Spacer(minLength: 0)
                    if signals.otherCount > 0 {
                        Circle()
                            .fill(OPSStyle.Colors.tertiaryText)
                            .frame(
                                width: OPSStyle.Layout.Indicator.dotSM,
                                height: OPSStyle.Layout.Indicator.dotSM
                            )
                    }
                }
                Spacer(minLength: 0)
                signalBars
            }
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .opacity(signals.isPreFloor ? OPSStyle.Layout.schedulerPreFloorOpacity : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: OPSStyle.Layout.schedulerDayCellHeight)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: OPSStyle.Animation.longPressHold) { onLongPress() }
        .animation(reduceMotion ? nil : OPSStyle.Animation.faster, value: role)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Selection chrome

    @ViewBuilder
    private var selectionBackground: some View {
        switch role {
        case .none:
            Color.clear
        case .single:
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.primaryText)
        case .start:
            UnevenRoundedRectangle(
                topLeadingRadius: OPSStyle.Layout.cardCornerRadius,
                bottomLeadingRadius: OPSStyle.Layout.cardCornerRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(OPSStyle.Colors.primaryText)
        case .end:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: OPSStyle.Layout.cardCornerRadius,
                topTrailingRadius: OPSStyle.Layout.cardCornerRadius
            )
            .fill(OPSStyle.Colors.primaryText)
        case .interior:
            Rectangle()
                .fill(OPSStyle.Colors.surfaceActive)
        }
    }

    private var numberColor: Color {
        switch role {
        case .single, .start, .end:
            return OPSStyle.Colors.invertedText
        case .interior:
            return OPSStyle.Colors.primaryText
        case .none:
            return isToday ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText
        }
    }

    // MARK: - Signals

    @ViewBuilder
    private var signalBars: some View {
        // Ordered by how much they should worry the reader: the crew being off
        // is the hardest fact, then the crew being booked, then this project's
        // own adjacent work.
        let bars = [
            signals.crewTimeOff ? SignalBar.timeOff : nil,
            signals.crewBusy ? SignalBar.busy : nil,
            signals.thisProject ? SignalBar.thisProject : nil
        ].compactMap { $0 }

        if !bars.isEmpty {
            VStack(spacing: OPSStyle.Layout.Border.standard) {
                ForEach(bars, id: \.self) { bar in
                    bar.view(muted: role == .single || role == .start || role == .end)
                }
            }
        }
    }

    private enum SignalBar: Hashable {
        case thisProject
        case busy
        case timeOff

        @ViewBuilder
        func view(muted: Bool) -> some View {
            switch self {
            case .thisProject:
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(muted ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                    .frame(height: OPSStyle.Layout.schedulerSignalBarHeight)
            case .busy:
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.warningStatus)
                    .frame(height: OPSStyle.Layout.schedulerSignalBarHeight)
            case .timeOff:
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.tanFillM)
                    .frame(height: OPSStyle.Layout.schedulerSignalBarHeight)
                    .overlay(
                        DiagonalHatch(pitch: OPSStyle.Layout.schedulerSignalHatchPitch)
                            .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
                            .clipShape(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            )
                    )
            }
        }
    }
}

// MARK: - Hatch

/// 45° repeating stripes. Pairs with the time-off fill so the signal survives
/// colour blindness and direct sunlight — the pattern reads even when the tone
/// does not.
struct DiagonalHatch: Shape {
    let pitch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard pitch > 0 else { return path }
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += pitch
        }
        return path
    }
}
