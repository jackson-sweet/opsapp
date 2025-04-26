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
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            
            HStack {
                // Client name
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                // Address
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(
            // Custom background with blur effect
            ZStack {
                Color("CardBackground")
                    .opacity(0.5)
                
                // Apply blur effect
                Rectangle()
                    .fill(Color.clear)
                    .background(Material.ultraThinMaterial)
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
        .overlay(confirmationOverlay)
        .contentShape(Rectangle()) // Make entire card tappable
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
    
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
