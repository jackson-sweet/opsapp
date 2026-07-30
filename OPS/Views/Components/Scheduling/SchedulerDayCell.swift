//
//  SchedulerDayCell.swift
//  OPS
//
//  One day in the schedule sheet's month scroll.
//
//  The cell carries four independent readings without ever becoming a chart:
//
//    • DAY NUMBER  — mono, top-left. Today wears the accent (number + hairline
//      ring); the accent is a focus marker here, not a CTA. Inside a
//      selection it wears whichever ink survives the ground beneath it.
//    • SIGNAL BARS — up to three 3pt bars along the bottom. White = this
//      project. Tan = the crew is booked. Tan + 45° hatch = the crew is off
//      (the hatch is a second, non-colour cue so the day still reads for a
//      colour-blind operator, and in direct sun).
//    • DENSITY DOT — one dim dot when the day holds work that touches neither
//      this crew nor this project. Presence, not detail.
//    • SELECTION   — white caps whose fill runs on into the span. The interior
//      leaves each cap at exactly the cap's own white and eases to quiet about
//      a day in, so there is no seam to find: cap and interior are one object.
//      The whole unit is traced by a hairline outline that stays OPEN where a
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
                // The quiet base carries the whole interior; the curve on top
                // reaches the caps' own white at each seam and is out of the
                // way within a day of it, so the middle of a long span stays
                // exactly as calm as it was.
                Rectangle()
                    .fill(OPSStyle.Colors.surfaceActive)
                Rectangle()
                    .fill(interiorGradient)
            }
        }
    }

    // MARK: - Span gradient

    /// Where this cell sits inside the selection's interior — which interior
    /// cell it is, and how many there are. nil unless the cell genuinely is
    /// one, so the caps and the outside never pay for the curve.
    private var interiorPosition: (index: Int, count: Int)? {
        guard let span = spanPosition else { return nil }
        let count = span.count - 2          // the two caps are not interior
        let index = span.index - 1
        guard count > 0, index >= 0, index < count else { return nil }
        return (index: index, count: count)
    }

    /// This cell's slice of the span curve. The curve decides where it has to
    /// be sampled; the cell only turns those samples into stops.
    private var interiorGradient: LinearGradient {
        guard let interior = interiorPosition else { return Self.emptyGradient }

        let stops = SchedulerSpanCurve
            .stopPositions(interiorIndex: interior.index, interiorCount: interior.count)
            .map { position -> Gradient.Stop in
                // A cell is exactly one unit wide in span coordinates, so the
                // position's offset into the cell is already the stop's
                // location. Brightness 1 resolves to `primaryText` at full
                // strength — the caps' fill exactly, which is what makes the
                // seam disappear.
                Gradient.Stop(
                    color: OPSStyle.Colors.primaryText
                        .opacity(SchedulerSpanCurve.brightness(at: position, interiorCount: interior.count)),
                    location: CGFloat(position - Double(interior.index))
                )
            }

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private static let emptyGradient = LinearGradient(
        colors: [.clear, .clear],
        startPoint: .leading,
        endPoint: .trailing
    )

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
            // The cap's white now carries a full day into the span, so an
            // interior number can be sitting on near-white ground. Read the
            // curve where the glyphs actually are, and wear whichever ink
            // survives it — the caps' own black, or the usual white.
            return numberPrefersInvertedInk
                ? OPSStyle.Colors.invertedText
                : OPSStyle.Colors.primaryText
        case .none:
            return isToday ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText
        }
    }

    /// Whether the ground under the day number carries more of the cap's white
    /// than it does the quiet base. Judged across the whole glyph run rather
    /// than at one point, because a cap-adjacent cell is a ramp, not a tone.
    private var numberPrefersInvertedInk: Bool {
        guard let interior = interiorPosition else { return false }
        return SchedulerSpanCurve.numberBandBrightness(
            interiorIndex: interior.index,
            interiorCount: interior.count
        ) > OPSStyle.Layout.schedulerSpanNumberFlipBrightness
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

        // The bars keep their own colours across the blend, deliberately. A
        // full-width bar lying over a white-to-quiet ramp cannot be one
        // correct colour, and a bar that changed tone mid-span would read as
        // the day's availability changing rather than its background. These
        // are presence signals, not values — tan and the hatch hold on both
        // grounds — so only the caps, flat white end to end, invert.
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

// MARK: - Span curve

/// The brightness a selection wears across its interior, as a function of
/// position measured in day cells from the start cap's seam.
///
/// Brightness 1 is the cap's own fill — `primaryText` at full strength — and
/// that is precisely the value at each seam, so a cap and the day beside it
/// meet at one colour and fuse. From there the white eases out quadratically
/// over `schedulerSpanBlendCells` and everything deeper stays at the quiet
/// base. Anchoring the blend to the seams rather than stretching it across the
/// whole span is the point: a fortnight-long booking then looks exactly like a
/// three-day one at both ends and says nothing in between, which is honest —
/// the middle of a long range has nothing to report.
///
/// The two seams' ramps ADD, clamped at the caps' own white. On every span of
/// four days or more they never reach each other, so the sum is just whichever
/// ramp is in range and nothing about a long span changes. It matters on
/// exactly one length: a three-day booking, whose single interior day sits
/// inside both ramps at once. Adding there leaves that day white at both seams
/// and merely soft in the middle. Taking the nearer seam instead would drive it
/// to the quiet base dead centre — a dark stripe through the middle of a
/// three-day pill, which is the abrupt step this whole curve exists to erase,
/// reintroduced at the one span short enough to make it obvious.
enum SchedulerSpanCurve {

    /// How far the glow reaches in from each seam. Clamped to the interior's
    /// own width, so a seam always spends its full budget and stops only where
    /// the interior does. On a three-day span — the only span short enough for
    /// the clamp to bite — both ramps therefore cover the lone interior day end
    /// to end and overlap across all of it, which is what holds that day at the
    /// caps' white on both edges instead of pinching it out in the middle.
    static func blendWidth(interiorCount: Int) -> Double {
        guard interiorCount > 0 else { return 0 }
        return min(OPSStyle.Layout.schedulerSpanBlendCells, Double(interiorCount))
    }

    /// Brightness `x` cells in from the start cap's seam, where the interior
    /// runs 0…`interiorCount`. A quadratic ease-out from each seam — the app's
    /// one easing curve held still: fast off the mark, long settle — with the
    /// two summed and the sum clamped at 1 so the interior can never outshine
    /// the caps it is fusing with. Summing rather than taking the nearer seam
    /// changes nothing wherever the two ramps stay out of each other's way,
    /// which is every span of four days or more; on a three-day span it is what
    /// holds the lone interior at half the caps' white through its middle
    /// instead of letting it fall to the quiet base and read as a break.
    static func brightness(at x: Double, interiorCount: Int) -> Double {
        let interior = Double(interiorCount)
        let blend = blendWidth(interiorCount: interiorCount)
        guard blend > 0 else { return 0 }

        let position = min(max(x, 0), interior)
        let fromStart = max(0, 1 - position / blend)
        let fromEnd = max(0, 1 - (interior - position) / blend)
        return min(1, fromStart * fromStart + fromEnd * fromEnd)
    }

    /// Where interior cell `interiorIndex` has to be sampled, in span
    /// coordinates, for a LinearGradient to tell the truth about it.
    ///
    /// A gradient runs straight lines between its stops, so a cell needs its
    /// two edges, every knee that lands inside it — where a blend runs out,
    /// and where the two sides meet — and one sample through the middle of
    /// each remaining segment the quadratic actually bends across. That is
    /// enough to keep the ease honest at a 48pt cell without pretending a
    /// gradient is a shader, and a flat stretch (the whole middle of a long
    /// span) pays nothing for it. Fixed positions, never a sweep at some
    /// arbitrary resolution.
    static func stopPositions(interiorIndex: Int, interiorCount: Int) -> [Double] {
        let cellStart = Double(interiorIndex)
        let cellEnd = cellStart + 1
        let blend = blendWidth(interiorCount: interiorCount)

        // Ascending, ties collapsed — on a short span all three knees land on
        // the same spot.
        var edges = [cellStart]
        for knee in [blend, Double(interiorCount) / 2, Double(interiorCount) - blend].sorted() {
            guard knee > edges[edges.count - 1], knee < cellEnd else { continue }
            edges.append(knee)
        }
        edges.append(cellEnd)

        var positions: [Double] = []
        for (position, next) in zip(edges, edges.dropFirst()) {
            positions.append(position)
            let bends = brightness(at: position, interiorCount: interiorCount) > 0
                || brightness(at: next, interiorCount: interiorCount) > 0
            if bends {
                positions.append((position + next) / 2)
            }
        }
        positions.append(cellEnd)
        return positions
    }

    /// Mean brightness under the day number of interior cell `interiorIndex`
    /// — three samples across the glyph run, which is all it takes to
    /// characterise a monotone ramp, and the number never straddles more.
    static func numberBandBrightness(interiorIndex: Int, interiorCount: Int) -> Double {
        let origin = Double(interiorIndex)
        let start = origin + OPSStyle.Layout.schedulerSpanNumberBandStart
        let end = origin + OPSStyle.Layout.schedulerSpanNumberBandEnd
        let samples = [start, (start + end) / 2, end]
        let total = samples.reduce(0.0) { $0 + brightness(at: $1, interiorCount: interiorCount) }
        return total / Double(samples.count)
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
