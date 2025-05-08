//
//  ProjectHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//



import SwiftUI

struct ProjectHeader: View {
    @EnvironmentObject private var appState: AppState
    var project: Project?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Status with correct styling
                Text(project?.status.rawValue.uppercased() ?? "IN PROGRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                
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
            
            // Close button
            Button(action: {
                appState.exitProjectMode()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
    }
}
