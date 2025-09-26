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
    let events: [CalendarEvent]
    let onTap: () -> Void
    
    // Computed counts for new vs ongoing
    private var newEventCount: Int {
        events.filter { event in
            Calendar.current.isDate(event.startDate ?? Date(), inSameDayAs: date)
        }.count
    }
    
    private var ongoingEventCount: Int {
        events.filter { event in
            let startDate = event.startDate ?? Date()
            let endDate = event.endDate ?? Date()
            return startDate < date && date <= endDate
        }.count
    }
    
    init(date: Date, isSelected: Bool, eventCount: Int, events: [CalendarEvent] = [], onTap: @escaping () -> Void) {
        self.date = date
        self.isSelected = isSelected
        self.eventCount = eventCount
        self.events = events
        self.onTap = onTap
    }
    
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
                
                // New event count in top-right corner
                if newEventCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 16, height: 16)
                                
                                Text("\(newEventCount)")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(Color.black)
                            }
                            .padding(.top, 4)
                            .padding(.trailing, 2)
                        }
                        Spacer()
                    }
                }
                
                // Ongoing event count in bottom-right corner
                if ongoingEventCount > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 14, height: 14)
                                
                                Text("\(ongoingEventCount)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                            .padding(.bottom, 4)
                            .padding(.trailing, 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            //.background(cellBackground)
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
