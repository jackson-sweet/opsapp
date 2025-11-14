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
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(textColor)
                    
                    // Day name (e.g., "We")
                    Text(DateHelper.twoLetterWeekdayString(from: date))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                        .frame(height: 20)
                }
                
                // Project count in top-right corner
                if projectCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 16, height: 16)
                                
                                Text("\(projectCount)")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 4)
                            .padding(.trailing, 4)
                        }
                        Spacer()
                    }
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
            return OPSStyle.Colors.secondaryAccent
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }
    
    private var background: some View {
        Group {
            if isToday {
                // Today gets a visible background fill
                OPSStyle.Colors.cardBackground.opacity(0.6)
            } else if isSelected {
                // Selected gets transparent background (outline only)
                Color.clear
            } else {
                Color.clear
            }
        }
    }
}
