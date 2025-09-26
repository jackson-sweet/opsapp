//
//  CalendarEventCard.swift
//  OPS
//
//  Card for displaying calendar events with proper task/project information
//

import SwiftUI

struct CalendarEventCard: View {
    let event: CalendarEvent
    let isFirst: Bool
    let isOngoing: Bool
    let onTap: () -> Void
    @EnvironmentObject private var dataController: DataController
    
    init(event: CalendarEvent, isFirst: Bool, isOngoing: Bool = false, onTap: @escaping () -> Void) {
        self.event = event
        self.isFirst = isFirst
        self.isOngoing = isOngoing
        self.onTap = onTap
    }
    
    // Get the associated project for client and address info
    private var associatedProject: Project? {
        // For task events, get the task's project
        if event.type == .task, let task = event.task {
            return task.project
        }
        // For project events, use the direct project
        return event.project
    }
    
    // Get the color for the status bar and task type
    private var displayColor: Color {
        // For project events, use the company's defaultProjectColor
        if event.type == .project {
            if let project = associatedProject,
               let company = dataController.getCompany(id: project.companyId),
               let defaultColor = Color(hex: company.defaultProjectColor) {
                return defaultColor
            }
        }
        
        // For task events, use the task color or event color
        if event.type == .task {
            if let task = event.task,
               let color = Color(hex: task.effectiveColor) {
                return color
            }
        }
        
        // Fallback to event color
        return event.swiftUIColor
    }
    
    // Format the address to show only: street number, street name, municipality
    private var formattedAddress: String {
        guard let project = associatedProject else { return "" }
        
        let address = project.address
        // Split address by comma to get components
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        if components.count >= 2 {
            // Typically: "123 Main St, City, State ZIP"
            // We want: "123 Main St, City"
            return "\(components[0]), \(components[1])"
        } else if components.count == 1 {
            // If no comma, just return the first part
            return components[0]
        }
        
        return address
    }
    
    // Get the display text for task type or "PROJECT"
    private var typeDisplay: String {
        if event.type == .task, let task = event.task, let taskType = task.taskType {
            return taskType.display.uppercased()
        } else if event.type == .project {
            return "PROJECT"
        }
        return ""
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left status bar - color coded by task type or project status
            Rectangle()
                .fill(displayColor)
                .frame(width: 4)
            
            // Content area with badges overlaid
            ZStack(alignment: .topLeading) {
                // Main content - fills available space
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Show project name as the main title
                        if let project = associatedProject {
                            Text(project.title)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                                .textCase(.uppercase)
                            
                            // For task events, show task name as subtitle
                            if event.type == .task, let task = event.task {
                                Text(task.displayTitle)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(1)
                            } else {
                                // For project events, show client name as subtitle
                                Text(project.effectiveClientName)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            // Formatted address (street number, street name, municipality)
                            Text(formattedAddress)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Invisible spacer to reserve space for badges
                    Color.clear
                        .frame(width: 80) // Reserve space for badges
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                // Task type or "PROJECT" badge in top right corner
                VStack {
                    HStack {
                        Spacer()
                        if !typeDisplay.isEmpty {
                            Text(typeDisplay)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(displayColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(displayColor.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(displayColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
                
                // Ongoing badge in bottom right corner
                if isOngoing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("ONGOING")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.trailing, 16)
                }
            }
        }
        .background(cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .contentShape(Rectangle()) // Make entire card tappable
        .shadow(color: Color.black, radius: 2, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
    }
    
    // Use darker background color for card
    private var cardBackground: some View {
        OPSStyle.Colors.cardBackgroundDark
    }
}