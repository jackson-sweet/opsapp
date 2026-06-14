//
//  WeekDayCell.swift
//  OPS
//
//  Week view day cell with corner project count
//

import SwiftUI

struct WeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(DateHelper.dayAbbreviation(from: date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(isToday ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.buttonLarge)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Reserve space for spanning bars overlay (rendered by CalendarDaySelector)
                Spacer(minLength: 0)
            }
            // Bug 3 — Add top + bottom breathing room so day labels and the
            // spanning event bars below them don't crowd the cell border.
            .padding(.top, OPSStyle.Layout.spacing1)
            .padding(.bottom, OPSStyle.Layout.spacing1)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .background(cellBackground)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        OPSStyle.Colors.primaryText,
                        lineWidth: isSelected ? 1.5 : 0
                    )
                    .animation(
                        UIAccessibility.isReduceMotionEnabled
                            ? .none
                            : OPSStyle.Animation.standard,
                        value: isSelected
                    )
            )
            .opacity(isPast ? 0.55 : 1.0)
        }
        .disabled(false)
    }

    private var isPast: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let cellDay = Calendar.current.startOfDay(for: date)
        return cellDay < today && !isToday
    }

    private var isToday: Bool {
        DateHelper.isToday(date)
    }

    private var cellBackground: some View {
        Group {
            if isToday {
                OPSStyle.Colors.primaryAccent.opacity(0.15)
            } else {
                Color.clear
            }
        }
    }
}

// Preview
struct WeekDayCell_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 0) {
            WeekDayCell(
                date: Date(),
                isSelected: false,
                onTap: {}
            )

            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                isSelected: true,
                onTap: {}
            )

            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                isSelected: false,
                onTap: {}
            )
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}
