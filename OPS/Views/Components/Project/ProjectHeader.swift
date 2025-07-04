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
                HStack (alignment: .top) {
                    
                    Text(project?.status.rawValue.uppercased() ?? "IN PROGRESS")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Close button
                    Button(action: {
                        print("🔴 ProjectHeader: X button tapped")
                        // If we're in navigation mode, stop routing first
                        if inProgressManager.isRouting {
                            print("🔴 ProjectHeader: Stopping routing")
                            inProgressManager.stopRouting()
                        }
                        
                        // Also post a notification to stop navigation in the new map
                        NotificationCenter.default.post(
                            name: Notification.Name("StopNavigation"),
                            object: nil
                        )
                        
                        print("🔴 ProjectHeader: Exiting project mode")
                        appState.exitProjectMode()
                    }) {
                        HStack(alignment: .center, spacing: 4) {
                            Text("STOP PROJECT")
                                .font(OPSStyle.Typography.smallButton)
                                .foregroundColor(OPSStyle.Colors.cardBackground)
                                .padding(4)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.cardBackground)
                                .padding(4)
                            
                        }
                        .padding(.horizontal, 8)
                        .background(
                            Color(OPSStyle.Colors.primaryText)
                        )
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        
                    }
                    
                }
                    
                if let project = project {
                    // Project
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    // Client Name
                    Text(project.clientName)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                    // Address
                    Text(project.address.formatAsSimpleAddress())
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
           
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            
            
        }
        .background(
            ZStack {
                // Blur effect
                BlurView(style: .systemUltraThinMaterialDark).opacity(0.6)
                
                // Semi-transparent overlay
                Color(OPSStyle.Colors.cardBackgroundDark)
                    .opacity(0.5)
                
            }
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
}
