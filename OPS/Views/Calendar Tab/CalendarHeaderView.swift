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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(headerDate)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(monthYearString)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            VStack {
                Text("PROJECTS")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text("\(todaysProjectCount)")
                    .font(OPSStyle.Typography.largeTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.2))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
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
        // Direct access - no conditionals needed
        dataController.getProjects(for: today).count
    }
}
