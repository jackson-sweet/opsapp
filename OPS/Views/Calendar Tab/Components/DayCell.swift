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

    // Animated border transition (Bug 6)
    @Namespace private var selectionBorderNS

    var body: some View {
        Button(action: onTap) {
            ZStack {
                VStack(spacing: 6) {
                    // Day number
                    Text(DateHelper.dayString(from: date))
                        .font(OPSStyle.Typography.cardBody)
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
                        isToday ? OPSStyle.Colors.primaryAccent : Color.clear,
                        lineWidth: 1
                    )
            )
            // Selected border — animated spring transition (Bug 6)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.primaryText : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
                    .animation(
                        UIAccessibility.isReduceMotionEnabled
                            ? .none
                            : OPSStyle.Animation.smooth,
                        value: isSelected
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
                OPSStyle.Colors.primaryAccent.opacity(0.20)
            } else if isSelected {
                // Selected gets transparent background (outline only)
                Color.clear
            } else {
                Color.clear
            }
        }
    }
}
