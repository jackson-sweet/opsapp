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
    let onStart: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(project.title)
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            HStack {
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
        .overlay(
            ZStack {
                if showConfirmation {
                    if isActiveProject {
                        // Show stop overlay for active project
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
                        // Show start overlay for non-active projects
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
        )
        .onTapGesture {
            NotificationCenter.default.post(
                name: NSNotification.Name("ProjectCardTapped"), 
                object: nil, 
                userInfo: ["projectId": project.id]
            )
        }
        .onLongPressGesture {
            NotificationCenter.default.post(
                name: NSNotification.Name("ProjectCardLongPressed"), 
                object: nil, 
                userInfo: ["projectId": project.id]
            )
        }
    }
}