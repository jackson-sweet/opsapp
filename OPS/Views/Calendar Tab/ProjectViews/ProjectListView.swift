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
                
                // Card with project count - not tappable
                ZStack {
                    // Project count card with softer edges
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 60, height: 60)
                    
                    // Stacked cards effect for depth
                    if viewModel.calendarEventsForSelectedDate.count > 0 {
                        ForEach(0..<min(3, viewModel.calendarEventsForSelectedDate.count), id: \.self) { index in
                            // Use event color for the border if available
                            let event = viewModel.calendarEventsForSelectedDate[min(index, viewModel.calendarEventsForSelectedDate.count - 1)]
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(event.swiftUIColor.opacity(0.6), lineWidth: 1)
                                .fill(Color(OPSStyle.Colors.cardBackgroundDark))
                                .frame(width: 50 + CGFloat(index * 2), height: 50 + CGFloat(index * 2))
                        }
                    }
                    
                    // Event count number
                    Text("\(viewModel.calendarEventsForSelectedDate.count)")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(.white)
                }
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
        ForEach(Array(viewModel.calendarEventsForSelectedDate.enumerated()), id: \.element.id) { index, event in
            // Get the associated project for this calendar event
            if let project = event.project {
                CalendarProjectCard(
                    project: project,
                    isFirst: index == 0,
                    onTap: {
                        // Print debug info
                        
                        // Use the notification approach to be consistent with how we show projects elsewhere
                        // This ensures we're only using one mechanism for showing project details
                        
                        // Send only the projectID in the notification to avoid potential issues with sending objects
                        let userInfo: [String: String] = ["projectID": project.id]
                        
                        // Post the notification with just the project ID
                        // Post notification with just the ID
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowCalendarProjectDetails"),
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                )
            }
        }
        .padding(.bottom, 20)
    }
}
