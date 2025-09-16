//
//  DayEventsSheet.swift
//  OPS
//
//  Sheet for displaying calendar events for a selected day
//

import SwiftUI

struct DayEventsSheet: View {
    let date: Date
    let calendarEvents: [CalendarEvent]
    let onEventSelected: (CalendarEvent) -> Void
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    // Separate new and ongoing events
    private var newEvents: [CalendarEvent] {
        calendarEvents.filter { event in
            Calendar.current.isDate(event.startDate ?? Date(), inSameDayAs: date)
        }
    }
    
    private var ongoingEvents: [CalendarEvent] {
        calendarEvents.filter { event in
            let startDate = event.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: date)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
            // Header with day info and dismiss button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeek)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(monthDayText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Card with project count - showing total count (new + ongoing)
                ZStack {
                    // Project count card with softer edges
                    RoundedRectangle(cornerRadius: 10)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 60, height: 60)
                    
                    // Total event count number (new + ongoing)
                    Text("\(calendarEvents.count)")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .segmentedEventBorder(
                    events: calendarEvents,  // Show border for all events
                    isSelected: false,
                    cornerRadius: 10
                )
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.leading, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            
            // Event list
            if calendarEvents.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // New events section
                        ForEach(Array(newEvents.enumerated()), id: \.element.id) { index, event in
                            CalendarEventCard(
                                event: event,
                                isFirst: index == 0,
                                isOngoing: false,
                                onTap: {
                                    // Simply call the selection callback
                                    // This will trigger the sequence in ScheduleView
                                    onEventSelected(event)
                                }
                            )
                            .environmentObject(dataController)
                        }
                        
                        // Ongoing section divider and events
                        if !ongoingEvents.isEmpty {
                            // Divider with count
                            HStack(spacing: 8) {
                                Text("ONGOING")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                // Horizontal line
                                Rectangle()
                                    .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                    .frame(height: 1)
                                
                                // Count
                                Text("[\(ongoingEvents.count)]")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            
                            // Ongoing events
                            ForEach(Array(ongoingEvents.enumerated()), id: \.element.id) { index, event in
                                CalendarEventCard(
                                    event: event,
                                    isFirst: false,
                                    isOngoing: true,
                                    onTap: {
                                        // Simply call the selection callback
                                        // This will trigger the sequence in ScheduleView
                                        onEventSelected(event)
                                    }
                                )
                                .environmentObject(dataController)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                }
            }
            .background(OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all))
            .navigationBarHidden(true) // Hide the default navigation bar
        }
    }
    
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).uppercased()
    }
    
    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("[ No events scheduled ]".uppercased())
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
