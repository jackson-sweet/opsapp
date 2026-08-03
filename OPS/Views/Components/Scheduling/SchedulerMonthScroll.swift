//
//  SchedulerMonthScroll.swift
//  OPS
//
//  The schedule sheet's one scrolling region: a continuous month list, the
//  same Apple-Calendar reading model the Schedule tab already uses.
//
//  Chevron paging was removed deliberately. A crew's next opening is often
//  "sometime in the next six weeks", and that answer straddles a month
//  boundary — paging forces the operator to hold two grids in their head to
//  see one span. Scrolling shows the span.
//
//  Month tracking follows MonthGridView's proven PreferenceKey + threshold
//  pattern (iOS 17.6 floor — none of the iOS 18 scroll-position APIs).
//

import SwiftUI

struct SchedulerMonthScroll: View {
    let context: SchedulerDayContext
    let selection: SchedulerSelection
    /// Month the pinned header names — written as the operator scrolls.
    @Binding var visibleMonth: Date
    /// Set by the jump picker; cleared once the scroll has been performed.
    @Binding var scrollRequest: Date?
    /// Month the list opens on: the persisted start, else the suggestion, else today.
    let anchorMonth: Date
    let onTapDay: (Date) -> Void
    let onLongPressDay: (Date) -> Void

    @State private var hasPerformedInitialScroll = false
    /// Suppresses month tracking while we drive the scroll ourselves, so an
    /// in-flight jump cannot be re-labelled by the months it flies past.
    @State private var isProgrammaticScroll = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// Two years around the anchor. Beyond that the jump picker is the right
    /// tool — nobody thumbs through 14 months of grid.
    private var monthsToDisplay: [Date] {
        var months: [Date] = []
        for offset in -12...12 {
            if let month = calendar.date(byAdding: .month, value: offset, to: anchorMonth),
               let monthStart = calendar.dateInterval(of: .month, for: month)?.start {
                months.append(monthStart)
            }
        }
        return months
    }

    /// Monday-first, nil-padded to whole weeks. Out-of-month ghost days are
    /// omitted entirely — a scrolling list already shows the neighbouring
    /// month, so repeating it inside the grid only invites mis-taps.
    private func datesForMonth(_ monthStart: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthInterval.start),
              let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return [] }

        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysFromMonday = (firstWeekday + 5) % 7

        var dates: [Date?] = Array(repeating: nil, count: daysFromMonday)
        var cursor = firstOfMonth
        while cursor <= lastOfMonth {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        while dates.count % 7 != 0 {
            dates.append(nil)
        }
        return dates
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(Array(monthsToDisplay.enumerated()), id: \.offset) { index, monthStart in
                        monthSection(monthStart, isFirst: index == 0)
                            .id(monthStart)
                    }
                }
            }
            .coordinateSpace(name: "schedulerScroll")
            .onAppear {
                guard !hasPerformedInitialScroll,
                      let target = calendar.dateInterval(of: .month, for: anchorMonth)?.start else { return }
                isProgrammaticScroll = true
                // Land on the anchor month without an animated fly-through —
                // the sheet should open already showing the right weeks.
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                    hasPerformedInitialScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + OPSStyle.Animation.durationPage) {
                        isProgrammaticScroll = false
                    }
                }
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request,
                      let target = calendar.dateInterval(of: .month, for: request)?.start else { return }
                isProgrammaticScroll = true
                withAnimation(OPSStyle.Animation.standard) {
                    proxy.scrollTo(target, anchor: .top)
                }
                visibleMonth = target
                DispatchQueue.main.asyncAfter(deadline: .now() + OPSStyle.Animation.durationStagger) {
                    isProgrammaticScroll = false
                    scrollRequest = nil
                }
            }
        }
    }

    // MARK: - Month

    @ViewBuilder
    private func monthSection(_ monthStart: Date, isFirst: Bool) -> some View {
        let dates = datesForMonth(monthStart)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("//")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                Text(SchedulerDayContext.monthCaption(monthStart, calendar: calendar))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(.top, isFirst ? 0 : OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .background(monthOffsetReader(monthStart))

            LazyVGrid(columns: columns, spacing: OPSStyle.Layout.Border.thick) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let role = selection.role(for: date, calendar: calendar)
                        SchedulerDayCell(
                            date: date,
                            signals: context.signals(for: date),
                            role: role,
                            spanPosition: selection.spanPosition(for: date, calendar: calendar),
                            spanEdge: spanEdge(for: role),
                            isToday: calendar.isDateInToday(date),
                            onTap: { onTapDay(date) },
                            onLongPress: { onLongPressDay(date) }
                        )
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.schedulerDayCellHeight)
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
    }

    /// What the selection's outline does at a day's two horizontal ends.
    ///
    /// Layout belongs to the grid, so the grid decides this and the cell never
    /// infers weekday math. The rule the layout produces is a short one: an end
    /// closes only where the SELECTION ends. Everything else — the next day
    /// along, or the wrap into the following week row — is a continuation, so
    /// it stays open and the two hairlines simply run flush to the margin. That
    /// is why a row boundary needs no flag of its own: a wrap edge is by
    /// definition not a cap, and only caps ever close.
    private func spanEdge(for role: SchedulerSelection.DayRole) -> SpanEdgeStroke.Closure? {
        switch role {
        case .none:
            return nil
        case .single:
            // A one-day pick is already a solid white block. Outlining
            // something that is its own boundary is a line drawn for the sake
            // of drawing a line.
            return nil
        case .start:
            return .leading
        case .end:
            return .trailing
        case .interior:
            return .open
        }
    }

    /// Publishes the month's distance from the scroll view's top and names the
    /// month whose first week is closest to it — MonthGridView's threshold
    /// approach, which behaves identically on the 17.6 deployment target.
    private func monthOffsetReader(_ monthStart: Date) -> some View {
        GeometryReader { geometry in
            let offset = geometry.frame(in: .named("schedulerScroll")).minY
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self, value: offset)
                .onChange(of: offset) { _, newOffset in
                    updateVisibleMonth(monthStart, offset: newOffset)
                }
                .onAppear {
                    updateVisibleMonth(monthStart, offset: offset)
                }
        }
    }

    private func updateVisibleMonth(_ monthStart: Date, offset: CGFloat) {
        guard !isProgrammaticScroll else { return }
        // ~200pt: the month takes the header a little before its grid reaches
        // the top, which is when a reader has already started reading it.
        let threshold: CGFloat = 200
        guard offset > -threshold && offset < threshold else { return }
        guard !calendar.isDate(visibleMonth, equalTo: monthStart, toGranularity: .month) else { return }

        withAnimation(OPSStyle.Animation.fast) {
            visibleMonth = monthStart
        }
    }
}
