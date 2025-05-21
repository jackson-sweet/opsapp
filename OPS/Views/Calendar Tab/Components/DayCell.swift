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
            VStack(spacing: 6) {
                // Day number
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(textColor)
                
                // Day name (e.g., "We")
                Text(DateHelper.twoLetterWeekdayString(from: date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                // Project count indicator
                if projectCount > 0 {
                    Text("\(projectCount)")
                        .font(OPSStyle.Typography.smallCaption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(OPSStyle.Colors.primaryAccent)
                        .clipShape(Circle())
                        .padding(.vertical, 2)
                } else {
                    Spacer()
                        .frame(height: 20)
                }
            }
            .frame(width: 56, height: 76)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                // Minimal rectangle border for selected day
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1)
                    .foregroundStyle(isSelected ? OPSStyle.Colors.cardBackground : Color.clear)
            )
        }
    }
    
    private var isToday: Bool {
        DateHelper.isToday(date)
    }
    
    private var hasProjects: Bool {
        projectCount > 0
    }
    
    private var textColor: Color {
        if isSelected {
            return OPSStyle.Colors.primaryText
        } else if isToday {
            return OPSStyle.Colors.primaryAccent
        } else {
            return OPSStyle.Colors.secondaryText
        }
    }
    
    private var background: some View {
        Group {
            if isSelected {
                // Darker background for selected day
                OPSStyle.Colors.cardBackgroundDark
            } else if isToday {
                // Slightly lighter background for today
                OPSStyle.Colors.cardBackground
            } else {
                // Clear background for other days
                Color.clear
            }
        }
    }
}
