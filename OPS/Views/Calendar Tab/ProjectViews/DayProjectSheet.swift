//
//  DayProjectSheet.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct DayProjectSheet: View {
    let date: Date
    let projects: [Project]
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with day info and dismiss button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeek)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(monthDayText)
                        .font(.system(size: 18))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Project count
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 44, height: 44)
                    
                    Text("\(projects.count)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.leading, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            
            // Project list
            if projects.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            CalendarProjectCard(
                                project: project,
                                isFirst: index == 0,
                                onTap: {
                                    // First dismiss this sheet
                                    dismiss()
                                    
                                    // Then show project details after a brief delay
                                    // This ensures the dismissal animation completes first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        appState.viewProjectDetails(project)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all))
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
            Spacer()
            
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
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}