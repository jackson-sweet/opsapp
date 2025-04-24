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
        ScrollView {
            LazyVStack(spacing: 0) {
                // Selected date header
                HStack {
                    Text(dateString.uppercased())
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 60, height: 60)
                            .cornerRadius(10)
                            
                        Text("\(viewModel.projectsForSelectedDate.count)")
                            .font(OPSStyle.Typography.largeTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                .padding()
                
                if viewModel.projectsForSelectedDate.isEmpty {
                    emptyStateView
                } else {
                    projectListView
                }
            }
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE\nMMMM d"
        return formatter.string(from: viewModel.selectedDate)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("No projects scheduled")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            // Random motivational quote
            if let quote = AppConfiguration.UX.noProjectQuotes.randomElement() {
                Text(quote)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private var projectListView: some View {
        ForEach(Array(viewModel.projectsForSelectedDate.enumerated()), id: \.element.id) { index, project in
            CalendarProjectCard(
                project: project,
                isFirst: index == 0,
                onTap: {
                    appState.enterProjectMode(projectID: project.id)
                }
            )
        }
        .padding(.bottom, 20)
    }
}
