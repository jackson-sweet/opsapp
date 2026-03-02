//
//  DayCell.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// DayCell.swift
import SwiftUI

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let projectCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                VStack(spacing: 6) {
                    // Day number
                    Text(DateHelper.dayString(from: date))
                        .font(.custom("Mohave-SemiBold", size: 13))
                        .foregroundColor(textColor)

                    // Day name (e.g., "We")
                    Text(DateHelper.twoLetterWeekdayString(from: date))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()
                        .frame(height: 20)
                }
            }
            .frame(width: 56, height: 76)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            // Today border
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        isToday ? Color(red: 89/255, green: 119/255, blue: 148/255) : Color.clear,
                        lineWidth: 1
                    )
            )
            // Selected border (white, overrides today border)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.primaryText : Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }

    private var isToday: Bool {
        DateHelper.isToday(date)
    }

    private var textColor: Color {
        if isSelected || isToday {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }

    private var background: some View {
        Group {
            if isToday {
                // Today gets a subtle tinted background fill
                Color(red: 89/255, green: 119/255, blue: 148/255).opacity(0.20)
            } else if isSelected {
                // Selected gets transparent background (outline only)
                Color.clear
            } else {
                Color.clear
            }
        }
    }
}
