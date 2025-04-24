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
            VStack(spacing: 4) {
                Text(DateHelper.dayString(from: date))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(textColor)
                
                Text(DateHelper.weekdayString(from: date))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(textColor.opacity(0.8))
            }
            .frame(width: 64, height: 64)
            .background(background)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
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
            return OPSStyle.Colors.primaryText.opacity(0.7)
        }
    }
    
    private var background: some View {
        Group {
            if isSelected {
                OPSStyle.Colors.cardBackground
            } else if isToday {
                OPSStyle.Colors.cardBackground.opacity(0.3)
            } else {
                Color.clear
            }
        }
    }
}