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
//    • SELECTION   — white caps joined by an interior that brightens toward
//      each cap and eases to quiet at the span's middle, the whole unit traced
//      by a hairline outline. The gradient is one continuous curve across the
//      entire selection, sampled per cell, and the outline stays OPEN where a
//      week row wraps — so a range reads as a single object however many rows
//      it crosses. Drawn ABOVE the signals so the operator's own pick is
//      always the loudest thing on the grid.
//
//  Days before the dependency floor recede to 35% — a guide, never a gate.
//  Every day on the grid is tappable, including those.
//

import SwiftUI

struct SchedulerDayCell: View {
    let date: Date
    let signals: SchedulerDayContext.DaySignals
    let role: SchedulerSelection.DayRole
    /// This day's place in the selection — 0-based index and inclusive day
    /// count — so the interior can draw its slice of the span-wide gradient.
    /// nil outside a completed range.
    let spanPosition: (index: Int, count: Int)?
    /// What the selection's outline does at this cell's two horizontal ends.
    /// Decided by the grid, which owns layout; nil where no outline belongs.
    let spanEdge: SpanEdgeStroke.Closure?
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
            spanOutline

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
            ZStack {
                // The quiet base is unchanged — the gradient only lifts the
                // days nearest the caps, so the middle of a long span stays
                // exactly as calm as it was.
                Rectangle()
                    .fill(OPSStyle.Colors.surfaceActive)
                Rectangle()
                    .fill(interiorGradient)
            }
        }
    }

    // MARK: - Span gradient

    /// The selection's brightness curve as a function of position `p` across
    /// the whole span: 1 hard against either white cap, easing symmetrically to
    /// 0 at the middle. One global curve — every cell samples the same
    /// function, so neighbouring cells meet at identical values and the span
    /// reads as one object rather than a row of tiles.
    private static func nearnessToCap(_ p: Double) -> Double {
        1 - min(p, 1 - p) * 2
    }

    private static func spanFill(at p: Double) -> Color {
        OPSStyle.Colors.primaryText
            .opacity(OPSStyle.Layout.schedulerSpanEdgeOpacity * nearnessToCap(p))
    }

    /// This cell's slice of that curve. Day `i` of `count` owns
    /// `p ∈ [i/count, (i+1)/count]`, which is a straight ramp — two stops —
    /// unless the curve's vertex at `p = 0.5` falls inside the cell, in which
    /// case it needs a third stop there or the kink would flatten into a ramp
    /// and the span would read lopsided. (A three-day span is the extreme
    /// case: its single interior day dips in its own centre, which is the
    /// curve telling the truth about where the middle is.)
    private var interiorGradient: LinearGradient {
        guard let span = spanPosition, span.count > 0 else {
            return LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)
        }

        let width = 1.0 / Double(span.count)
        let left = Double(span.index) * width
        let right = left + width

        var stops = [Gradient.Stop(color: Self.spanFill(at: left), location: 0)]
        if left < 0.5, right > 0.5 {
            stops.append(
                Gradient.Stop(
                    color: Self.spanFill(at: 0.5),
                    location: CGFloat((0.5 - left) / width)
                )
            )
        }
        stops.append(Gradient.Stop(color: Self.spanFill(at: right), location: 1))

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Span outline

    /// The hairline that traces the selection as one unit. Above the fill,
    /// below the content — it frames the pick without competing with the day
    /// number or the signal bars sitting inside it.
    @ViewBuilder
    private var spanOutline: some View {
        if let spanEdge {
            SpanEdgeStroke(
                closure: spanEdge,
                cornerRadius: OPSStyle.Layout.cardCornerRadius,
                inset: OPSStyle.Layout.Border.standard / 2
            )
            .stroke(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.standard)
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

// MARK: - Span outline

/// One day's share of the outline around a whole selection: the top and bottom
/// edges always, plus a rounded closing edge wherever the selection genuinely
/// ends.
///
/// Where a span runs off the side of a week row it is continuing, not ending,
/// so that edge is left OPEN and the two hairlines run flush to the margin —
/// the same continuation language wrapped text selection uses. Interior day
/// boundaries are never stroked vertically; a selection is one object, not a
/// fence of cells.
struct SpanEdgeStroke: Shape {
    /// Which horizontal ends of this cell close the selection off.
    enum Closure: Equatable {
        /// Mid-span on both sides — two bare hairlines, top and bottom.
        case open
        case leading
        case trailing
        case both
    }

    let closure: Closure
    let cornerRadius: CGFloat
    /// Half the stroke width, so a centred hairline sits fully inside the cell
    /// instead of bleeding into the gap between week rows.
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let closesLeading = closure == .leading || closure == .both
        let closesTrailing = closure == .trailing || closure == .both
        let top = rect.minY + inset
        let bottom = rect.maxY - inset
        let leading = rect.minX + (closesLeading ? inset : 0)
        let trailing = rect.maxX - (closesTrailing ? inset : 0)
        guard bottom > top, trailing > leading else { return path }

        let radius = min(cornerRadius, (bottom - top) / 2, trailing - leading)

        switch closure {
        case .open:
            path.move(to: CGPoint(x: leading, y: top))
            path.addLine(to: CGPoint(x: trailing, y: top))
            path.move(to: CGPoint(x: leading, y: bottom))
            path.addLine(to: CGPoint(x: trailing, y: bottom))

        case .leading:
            // One unbroken run: in along the top, around the cap, back out
            // along the bottom.
            path.move(to: CGPoint(x: trailing, y: top))
            path.addArc(
                tangent1End: CGPoint(x: leading, y: top),
                tangent2End: CGPoint(x: leading, y: bottom),
                radius: radius
            )
            path.addArc(
                tangent1End: CGPoint(x: leading, y: bottom),
                tangent2End: CGPoint(x: trailing, y: bottom),
                radius: radius
            )
            path.addLine(to: CGPoint(x: trailing, y: bottom))

        case .trailing:
            path.move(to: CGPoint(x: leading, y: top))
            path.addArc(
                tangent1End: CGPoint(x: trailing, y: top),
                tangent2End: CGPoint(x: trailing, y: bottom),
                radius: radius
            )
            path.addArc(
                tangent1End: CGPoint(x: trailing, y: bottom),
                tangent2End: CGPoint(x: leading, y: bottom),
                radius: radius
            )
            path.addLine(to: CGPoint(x: leading, y: bottom))

        case .both:
            path.addRoundedRect(
                in: CGRect(x: leading, y: top, width: trailing - leading, height: bottom - top),
                cornerSize: CGSize(width: radius, height: radius)
            )
        }

        return path
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
