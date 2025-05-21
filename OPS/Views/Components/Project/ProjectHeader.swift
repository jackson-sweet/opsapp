//
//  ProjectHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//



import SwiftUI

struct ProjectHeader: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var inProgressManager = InProgressManager.shared
    var project: Project?
    
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Status with correct styling - using primaryText instead of secondaryAccent
                // since secondaryAccent should only be used to indicate active projects
                Text(project?.status.rawValue.uppercased() ?? "IN PROGRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let project = project {
                    // Project
                    Text(project.title)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    // Client Name
                    Text(project.clientName)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                    // Address
                    Text(project.address)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Buttons stack
            HStack(spacing: 12) {
                
                // Close button
                Button(action: {
                    // If we're in navigation mode, stop routing first
                    if inProgressManager.isRouting {
                        inProgressManager.stopRouting()
                    }
                    appState.exitProjectMode()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .padding()
    }
    
}
