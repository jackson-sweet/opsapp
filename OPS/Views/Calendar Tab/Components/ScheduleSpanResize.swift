//
//  ScheduleSpanResize.swift
//  OPS
//
//  Shared pinch-to-resize primitives for schedule cards. The math is isolated so
//  task and user-event cards preserve the same calendar-day semantics as drag/drop.
//

import SwiftUI

enum ScheduleSpanResize {
    static func inclusiveDayCount(start: Date, end: Date, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let raw = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(raw + 1, 1)
    }

    static func dayCount(anchorDayCount: Int, magnification: CGFloat, maxDayCount: Int = 60) -> Int {
        let anchor = max(anchorDayCount, 1)
        let scaled = (CGFloat(anchor) * magnification).rounded()
        return min(max(Int(scaled), 1), max(maxDayCount, 1))
    }

    static func endDate(
        start: Date,
        preservingEndTimeFrom originalEnd: Date,
        dayCount: Int,
        calendar: Calendar = .current
    ) -> Date {
        let clampedDays = max(dayCount, 1)
        let targetEndDay = calendar.date(
            byAdding: .day,
            value: clampedDays - 1,
            to: calendar.startOfDay(for: start)
        ) ?? calendar.startOfDay(for: start)
        let endTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: originalEnd)
        return calendar.date(
            bySettingHour: endTime.hour ?? 0,
            minute: endTime.minute ?? 0,
            second: endTime.second ?? 0,
            of: targetEndDay
        ) ?? targetEndDay
    }

    static func isSameMoment(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.compare(lhs, to: rhs, toGranularity: .second) == .orderedSame
    }
}

private struct ScheduleSpanResizeModifier: ViewModifier {
    let currentDayCount: Int
    let onCommit: (Int) -> Void

    @State private var anchorDayCount: Int?
    @State private var previewDayCount: Int?
    @State private var lastFeedbackDayCount: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let previewDayCount {
                    ScheduleSpanResizeBadge(dayCount: previewDayCount)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: previewDayCount)
            .simultaneousGesture(
                MagnificationGesture(minimumScaleDelta: 0.03)
                    .onChanged { scale in
                        if anchorDayCount == nil {
                            anchorDayCount = currentDayCount
                            lastFeedbackDayCount = currentDayCount
                            UISelectionFeedbackGenerator().prepare()
                        }

                        let anchor = anchorDayCount ?? currentDayCount
                        let dayCount = ScheduleSpanResize.dayCount(anchorDayCount: anchor, magnification: scale)
                        previewDayCount = dayCount

                        if lastFeedbackDayCount != dayCount {
                            UISelectionFeedbackGenerator().selectionChanged()
                            lastFeedbackDayCount = dayCount
                        }
                    }
                    .onEnded { scale in
                        let anchor = anchorDayCount ?? currentDayCount
                        let dayCount = ScheduleSpanResize.dayCount(anchorDayCount: anchor, magnification: scale)
                        reset()

                        guard dayCount != currentDayCount else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onCommit(dayCount)
                    }
            )
    }

    private func reset() {
        anchorDayCount = nil
        previewDayCount = nil
        lastFeedbackDayCount = nil
    }
}

private struct ScheduleSpanResizeBadge: View {
    let dayCount: Int

    var body: some View {
        Text(dayCount == 1 ? "1 DAY" : "\(dayCount) DAYS")
            .font(OPSStyle.Typography.miniLabel)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(OPSStyle.Colors.cardBackground.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 0.5)
            )
    }
}

extension View {
    @ViewBuilder
    func resizableScheduleSpan(
        currentDayCount: Int?,
        enabled: Bool,
        onCommit: @escaping (Int) -> Void
    ) -> some View {
        if enabled, let currentDayCount {
            modifier(ScheduleSpanResizeModifier(currentDayCount: currentDayCount, onCommit: onCommit))
        } else {
            self
        }
    }
}
