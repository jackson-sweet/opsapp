//
//  ProjectSettingsView.swift
//  OPS
//
//  Project-related settings for office crews and admins
//

import SwiftUI
import SwiftData

// Settings row component for ProjectSettingsView
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let showChevron: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 30)
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Chevron
            if showChevron {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct ProjectSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Project Settings",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)
                
                // Direct navigation to Task Settings
                NavigationLink(destination: TaskSettingsView()) {
                    SettingsRow(
                        icon: "square.grid.2x2",
                        title: "Task Types",
                        subtitle: "Manage task categories and icons",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 20)

                NavigationLink(destination: SchedulingTypeExplanationView()) {
                    SettingsRow(
                        icon: "calendar.badge.clock",
                        title: "Scheduling Type",
                        subtitle: "Project Based vs Task Based",
                        showChevron: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// Project Settings Suggestions:
// 1. Task Types Management (implemented)
// 2. Project Templates - Create reusable project structures with predefined tasks
// 3. Default Project Color - Set company-wide default project color
// 4. Scheduling Mode Defaults - Choose between task-based or project-based scheduling
// 5. Status Workflows - Define custom status transitions and rules
// 6. Task Dependencies - Set up task relationships and prerequisites
// 7. Milestone Management - Define project milestones and checkpoints
// 8. Resource Allocation - Assign default crews or equipment to project types
// 9. Budget Templates - Set up standard budget categories for projects
// 10. Document Templates - Create standard documents for different project phases
// 11. Quality Checklists - Define inspection and quality control checklists
// 12. Client Communication Settings - Default communication preferences per project type