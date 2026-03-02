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
    let eventCount: Int
    let tasks: [ProjectTask]
    let onTap: () -> Void

    init(date: Date, isSelected: Bool, eventCount: Int, tasks: [ProjectTask] = [], onTap: @escaping () -> Void) {
        self.date = date
        self.isSelected = isSelected
        self.eventCount = eventCount
        self.tasks = tasks
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(DateHelper.dayAbbreviation(from: date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(isToday ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                Text(DateHelper.dayString(from: date))
                    .font(.custom("Mohave-SemiBold", size: 18))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                densityBarsView
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(cellBackground)
            .cornerRadius(2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: isSelected ? 1 : 0)
            )
            .opacity(isPast ? 0.55 : 1.0)
        }
        .disabled(false)
    }

    private var densityBarsView: some View {
        let overflow = tasks.count > 4
        let displayTasks = Array(tasks.prefix(overflow ? 3 : 4))

        return VStack(spacing: 1) {
            ForEach(Array(displayTasks.enumerated()), id: \.offset) { index, task in
                RoundedRectangle(cornerRadius: 1)
                    .fill(task.swiftUIColor.opacity(0.85))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
            }
            if overflow {
                Text("···")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(height: 3)
            }
        }
        .frame(height: 20)
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
        HStack(spacing: 8) {
            WeekDayCell(
                date: Date(),
                isSelected: false,
                eventCount: 2,
                onTap: {}
            )
            
            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                isSelected: true,
                eventCount: 0,
                onTap: {}
            )
            
            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                isSelected: false,
                eventCount: 5,
                onTap: {}
            )
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}
