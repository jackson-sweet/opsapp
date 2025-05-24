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
    let projectCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                VStack(spacing: 4) {
                    // Day abbreviation
                    Text(DateHelper.dayAbbreviation(from: date))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(dayAbbreviationColor)
                    
                    // Day number
                    Text(DateHelper.dayString(from: date))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(textColor)
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
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(cellBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                // White border for selected day
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white, lineWidth: isSelected ? 1 : 0)
            )
        }
        .disabled(false) // Always enabled in week view
    }
    
    private var isToday: Bool {
        DateHelper.isToday(date)
    }
    
    private var isCurrentWeek: Bool {
        let calendar = Calendar.current
        let today = Date()
        return calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear)
    }
    
    private var dayAbbreviationColor: Color {
        if isToday {
            return .white
        } else {
            return OPSStyle.Colors.secondaryText
        }
    }
    
    private var textColor: Color {
        if isToday {
            return .white
        } else if isSelected {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.primaryText.opacity(0.8)
        }
    }
    
    private var cellBackground: some View {
        Group {
            if isToday {
                OPSStyle.Colors.primaryAccent
            } else if isSelected {
                OPSStyle.Colors.cardBackground
            } else if isCurrentWeek {
                OPSStyle.Colors.cardBackground.opacity(0.3)
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
                projectCount: 2,
                onTap: {}
            )
            
            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                isSelected: true,
                projectCount: 0,
                onTap: {}
            )
            
            WeekDayCell(
                date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                isSelected: false,
                projectCount: 5,
                onTap: {}
            )
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}