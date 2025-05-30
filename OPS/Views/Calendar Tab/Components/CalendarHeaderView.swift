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
                    Text("TODAY")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(weekdayText)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fontWeight(.bold)
                    
                    Text(monthDayText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Right side - project count
                VStack(spacing: 4) {
                    Text("PROJECTS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("\(todaysProjectCount)")
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
        .padding(.horizontal)
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
    
    // Get projects for today specifically, not the selected date
    private var todaysProjectCount: Int {
        // Filter by current user to match what's shown in the project list
        dataController.getProjects(
            for: today,
            assignedTo: dataController.currentUser
        ).count
    }
}
