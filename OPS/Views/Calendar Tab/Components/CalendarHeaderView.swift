//
//  CalendarHeaderView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarHeaderView.swift
import SwiftUI

struct CalendarHeaderView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject private var dataController: DataController
    
    // Store today's date on creation for the header
    private let today = Date()
    
    var body: some View {
        // Match the reference design with darker background
        Button(action: {
            // Reset to week view and today's date
            viewModel.viewMode = .week
            viewModel.selectDate(Date())
        }) {
            HStack(spacing: 0) {
                // Left side - day label and date
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("TODAY")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Divider()
                            .frame(maxHeight: 12)
                        
                        Text(monthDayText)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    Text(weekdayText)
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fontWeight(.bold)
                    
                    
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Right side - event count
                VStack(spacing: 4) {
                    Text("EVENTS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("\(todaysEventCount)")
                        .font(OPSStyle.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .contentShape(Rectangle()) // Makes entire area tappable
    }
    
    // Split the date formatting for better control
    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: today).uppercased()
    }
    
    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: today)
    }
    
    private var headerDate: String {
        // Always show today's date in the header
        DateHelper.fullDateString(from: today).uppercased()
    }
    
    private var monthYearString: String {
        // Show the selected month and year
        DateHelper.monthYearString(from: viewModel.selectedDate)
    }
    
    private var visibleMonthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.visibleMonth)
    }
    
    private var visibleMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: viewModel.visibleMonth).uppercased()
    }
    
    // Get calendar events for today specifically, not the selected date
    private var todaysEventCount: Int {
        // Get calendar events based on user role
        var calendarEvents = dataController.getCalendarEventsForCurrentUser(for: today)
        
        // Apply team member filter if selected
        if let selectedMemberId = viewModel.selectedTeamMemberId {
            calendarEvents = calendarEvents.filter { event in
                // Check if member is in the event or its task
                let hasInEvent = event.getTeamMemberIds().contains(selectedMemberId) ||
                                event.teamMembers.contains(where: { $0.id == selectedMemberId })
                
                let hasInTask = event.task?.getTeamMemberIds().contains(selectedMemberId) == true ||
                               event.task?.teamMembers.contains(where: { $0.id == selectedMemberId }) == true
                
                return hasInEvent || hasInTask
            }
        }
        
        return calendarEvents.count
    }
}
