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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(headerDate)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(DateHelper.monthYearString(from: viewModel.selectedDate))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            VStack {
                Text("PROJECTS")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text("\(viewModel.projectsForSelectedDate.count)")
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
        DateHelper.fullDateString(from: viewModel.selectedDate).uppercased()
    }
}