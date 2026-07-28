//
//  MonthJumpPicker.swift
//  OPS
//
//  Jump-to-month sheet. Extracted verbatim from MonthGridView so the schedule
//  sheet's continuous month scroll can reuse the same control instead of
//  growing a second, subtly different one.
//
//  The only change from its original form: it no longer reaches into
//  CalendarViewModel. It takes the month to highlight and hands the chosen
//  month back, so both the calendar tab and the scheduler drive their own
//  scroll from the same picker.
//

import SwiftUI

struct MonthJumpPicker: View {
    /// The month currently in view — highlighted as selected.
    let selectedMonth: Date
    /// Called with the first day of the chosen month.
    let onSelect: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayYear: Int

    private let calendar = Calendar.current
    private let monthNames = Calendar.current.shortMonthSymbols

    init(selectedMonth: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedMonth = selectedMonth
        self.onSelect = onSelect
        self._displayYear = State(initialValue: Calendar.current.component(.year, from: selectedMonth))
    }

    /// The month (1-12) currently in view
    private var currentMonth: Int {
        calendar.component(.month, from: selectedMonth)
    }

    /// The year currently in view
    private var currentYear: Int {
        calendar.component(.year, from: selectedMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("JUMP TO DATE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1)

                Spacer()

                Button("DONE") {
                    dismiss()
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing4)

            // Year navigation
            HStack {
                Button {
                    withAnimation(OPSStyle.Animation.fast) { displayYear -= 1 }
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }

                Spacer()

                Text(String(displayYear))
                    .font(OPSStyle.Typography.headingBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .contentTransition(.numericText())

                Spacer()

                Button {
                    withAnimation(OPSStyle.Animation.fast) { displayYear += 1 }
                } label: {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing3_5)

            // Month grid (3x4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2_5), count: 3), spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(1...12, id: \.self) { month in
                    let isSelected = month == currentMonth && displayYear == currentYear
                    let isCurrentMonth = month == calendar.component(.month, from: Date()) && displayYear == calendar.component(.year, from: Date())

                    Button {
                        selectMonth(month)
                    } label: {
                        Text(monthNames[month - 1].uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.surfaceInput)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(
                                        isCurrentMonth && !isSelected ? OPSStyle.Colors.primaryAccent.opacity(OPSStyle.Layout.Opacity.medium) : OPSStyle.Colors.cardBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Spacer().frame(height: OPSStyle.Layout.spacing4)

            // Today shortcut
            Button {
                let today = Date()
                let todayYear = calendar.component(.year, from: today)
                let todayMonth = calendar.component(.month, from: today)
                displayYear = todayYear
                selectMonth(todayMonth)
            } label: {
                Text("TODAY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .tracking(1)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(OPSStyle.Layout.Opacity.light), lineWidth: 0.5)
                    )
            }
            .padding(.bottom, OPSStyle.Layout.spacing3_5)
        }
        .background(OPSStyle.Colors.background)
    }

    private func selectMonth(_ month: Int) {
        var components = DateComponents()
        components.year = displayYear
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components),
              let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelect(monthStart)
        dismiss()
    }
}
