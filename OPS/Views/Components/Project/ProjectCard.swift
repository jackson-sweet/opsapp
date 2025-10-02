//
//  ProjectCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI

struct ProjectCard: View {
    let project: Project
    let isSelected: Bool
    let showConfirmation: Bool
    let isActiveProject: Bool
    let onTap: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Project title
            Text(project.title)
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            
                // Client name
                Text(project.clientName)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                // Address
                Text(project.address ?? "No address")
                .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            
        }
        .padding()
        .background(
            // Custom background with blur effect
            BlurView(style: .dark)
                .cornerRadius(5)
                .opacity(0.5)
                .frame(width: 362, height: 85)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
        .overlay(confirmationOverlay)
        .contentShape(Rectangle()) // Make entire card tappable
        // REMOVE ALL GESTURE HANDLERS HERE - Let ProjectCardView handle gestures
    
    }
    
    @ViewBuilder
    private var confirmationOverlay: some View {
        if showConfirmation {
            if isActiveProject {
                // Stop overlay
                Button(action: onStop) {
                    Text("Stop Project?")
                        .font(OPSStyle.Typography.bodyBold)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(Color.red)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            } else {
                // Start overlay
                Button(action: onStart) {
                    Text("Start Project?")
                        .font(OPSStyle.Typography.bodyBold)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }
}
