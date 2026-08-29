//
//  SiteVisitWeekRail.swift
//  OPS
//
//  The booking sheet's WHEN surface: a paged week rail whose day cells carry
//  their own availability (tan visit markers), the scheduler sheet's grammar
//  at appointment scale. Selection is a day; the sheet owns merging it with
//  the held time-of-day. Monday-first, matching the Schedule tab.
//
//  Pure inputs — the sheet resolves counts via SiteVisitBookingDayContext,
//  so previews and snapshots render any state without a store.
//

import SwiftUI
import UIKit

struct SiteVisitWeekRail: View {
    /// The appointment's current day (start-of-day not required).
    let selectedDate: Date
    /// startOfDay → booked-visit count (rail markers).
    let visitCountsByDay: [Date: Int]
    /// Day tapped. The sheet merges it with the held time-of-day.
    let onSelect: (Date) -> Void

    /// Weeks reachable by paging: this week through 18 months out. A booking
    /// is future-only, so there is nothing to page backwards into.
    private static let weekOffsets = Array(0...78)

    @State private var weekPosition: Int?
    @State private var showingMonthJump = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday — the Schedule tab's convention
        return cal
    }

    private var currentWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? calendar.startOfDay(for: Date())
    }

    private func weekStart(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart) ?? currentWeekStart
    }

    private func weekOffset(containing date: Date) -> Int {
        let target = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let weeks = calendar.dateComponents([.weekOfYear], from: currentWeekStart, to: target).weekOfYear ?? 0
        return min(max(weeks, 0), Self.weekOffsets.count - 1)
    }

    private func days(inWeekStarting start: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            captionRow

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.weekOffsets, id: \.self) { offset in
                        weekPage(offset: offset)
                            .containerRelativeFrame(.horizontal)
                            .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $weekPosition)
            .scrollIndicators(.hidden)
            .frame(height: 68)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .glassSurface()
        .onAppear {
            weekPosition = weekOffset(containing: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            let target = weekOffset(containing: newValue)
            if target != weekPosition {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { weekPosition = target }
            }
        }
        .sheet(isPresented: $showingMonthJump) {
            MonthJumpPicker(selectedMonth: weekStart(forOffset: weekPosition ?? 0)) { monthStart in
                let clamped = max(monthStart, calendar.startOfDay(for: Date()))
                onSelect(clamped)
            }
            .opsSheet(detents: [.medium])
        }
    }

    // MARK: - Caption

    /// "This week / Next week / 2 weeks from now" — the Schedule strip's own
    /// vocabulary (CalendarWeekRowCaption), plus the long-range jump.
    private var captionRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(CalendarWeekRowCaption.title(forWeekContaining: weekStart(forOffset: weekPosition ?? 0)))
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingMonthJump = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(monthToken(weekStart(forOffset: weekPosition ?? 0)))
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Jump to another month")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing1)
    }

    private func monthToken(_ date: Date) -> String {
        Self.monthFormatter.string(from: date).uppercased()
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    // MARK: - Week page

    private func weekPage(offset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(days(inWeekStarting: weekStart(forOffset: offset)), id: \.timeIntervalSince1970) { day in
                SiteVisitRailDayCell(
                    date: day,
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    visitCount: visitCountsByDay[calendar.startOfDay(for: day)] ?? 0,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(day)
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Day cell

/// WeekDayCell's anatomy (abbrev / number / marker zone, selection ring,
/// today wash, past dim) sized for a sheet — the marker zone carries tan
/// visit dots instead of the strip's spanning bars.
struct SiteVisitRailDayCell: View {
    let date: Date
    let isSelected: Bool
    let visitCount: Int
    let onTap: () -> Void

    private var isToday: Bool { DateHelper.isToday(date) }

    private var isPast: Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(DateHelper.dayAbbreviation(from: date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(isToday ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.buttonLarge)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                markerZone
            }
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                isToday
                    ? OPSStyle.Colors.primaryAccent.opacity(0.15) // WeekDayCell's shipped today wash
                    : Color.clear
            )
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: isSelected ? 1.5 : 0)
            )
            .opacity(isPast ? 0.55 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPast)
        .accessibilityLabel(accessibilityText)
    }

    /// Tan dots, one per booked visit up to three, then the strip's "+N"
    /// overflow grammar. Height is reserved so cells never jitter.
    private var markerZone: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(visitCount, 3), id: \.self) { _ in
                Circle()
                    .fill(OPSStyle.Colors.tanTextM)
                    .frame(width: 4, height: 4)
            }
            if visitCount > 3 {
                Text("+\(visitCount - 3)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .frame(height: 6)
    }

    private var accessibilityText: String {
        let day = Self.spokenFormatter.string(from: date)
        var parts = [day]
        if visitCount > 0 {
            parts.append(visitCount == 1 ? "1 visit booked" : "\(visitCount) visits booked")
        }
        if isSelected { parts.append("selected") }
        if isPast { parts.append("past") }
        return parts.joined(separator: ", ")
    }

    private static let spokenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        return formatter
    }()
}

// MARK: - Previews

#if DEBUG
#Preview("SiteVisitWeekRail") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        SiteVisitWeekRail(
            selectedDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            visitCountsByDay: [
                Calendar.current.startOfDay(for: Date()): 2,
                Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!): 5,
            ],
            onSelect: { _ in }
        )
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .preferredColorScheme(.dark)
}
#endif
