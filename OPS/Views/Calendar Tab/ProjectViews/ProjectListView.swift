//
//  ProjectListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// ProjectListView.swift
import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    
    // Separate new and ongoing events
    private var newEvents: [CalendarEvent] {
        viewModel.calendarEventsForSelectedDate.filter { event in
            Calendar.current.isDate(event.startDate ?? Date(), inSameDayAs: viewModel.selectedDate)
        }
    }
    
    private var ongoingEvents: [CalendarEvent] {
        viewModel.calendarEventsForSelectedDate.filter { event in
            let startDate = event.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: viewModel.selectedDate)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Selected date header based on reference design
            // IMPORTANT: Header should NOT be in ScrollView
            HStack(alignment: .top) {
                // Day of week and month/day in vertical layout
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeek)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(monthDayText)
                        .font(OPSStyle.Typography.cardSubtitle)
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
                    Text("\(viewModel.calendarEventsForSelectedDate.count)")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .segmentedEventBorder(
                    events: viewModel.calendarEventsForSelectedDate,  // Show border for all events
                    isSelected: false,
                    cornerRadius: 10
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Only the content area should be in the ScrollView, not the header
            if viewModel.calendarEventsForSelectedDate.isEmpty {
                emptyStateView
            } else {
                // Project list content in ScrollView
                ScrollView {
                    projectListView
                }
            }
        }
        .overlay(
            // White border for first/selected project card
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // Split the date into components for better styling
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: viewModel.selectedDate).uppercased()
    }
    
    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: viewModel.selectedDate)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("[ No projects scheduled ]".uppercased())
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var projectListView: some View {
        VStack(spacing: 16) {
            // New events section
            ForEach(Array(newEvents.enumerated()), id: \.element.id) { index, event in
                CalendarEventCard(
                    event: event,
                    isFirst: index == 0,
                    isOngoing: false,
                    onTap: {
                        handleEventTap(event)
                    }
                )
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
                            handleEventTap(event)
                        }
                    )
                }
            }
        }
        .padding(.bottom, 20)
    }
    
    private func handleEventTap(_ event: CalendarEvent) {
        // Check if this is a task event or project event
        if event.type == .task, let task = event.task {
            // For task events, send task ID and project ID
            let userInfo: [String: String] = [
                "taskID": task.id,
                "projectID": task.projectId
            ]
            
            // Post notification for task details
            NotificationCenter.default.post(
                name: Notification.Name("ShowCalendarTaskDetails"),
                object: nil,
                userInfo: userInfo
            )
        } else {
            // For project events, send just project ID
            let userInfo: [String: String] = ["projectID": event.projectId]
            
            // Post notification for project details
            NotificationCenter.default.post(
                name: Notification.Name("ShowCalendarProjectDetails"),
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
