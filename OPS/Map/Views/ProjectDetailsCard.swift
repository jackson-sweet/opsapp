//
//  ProjectDetailsCard.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Simplified project details card for map

import SwiftUI
import MapKit

struct ProjectDetailsCard: View {
    let project: Project
    let selectedTask: ProjectTask?
    let coordinator: MapCoordinator
    let onStartProject: ((Project) -> Void)?
    @State private var showFullDetails = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var taskTypeBadge: String? {
        return selectedTask?.taskType?.display
    }

    private var taskColor: Color {
        if let task = selectedTask,
           let color = Color(hex: task.effectiveColor) {
            return color
        }
        return OPSStyle.Colors.secondaryText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Dismiss button
            HStack {
                Spacer()

                Button(action: {
                    coordinator.showingProjectDetails = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.trailing, 16)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            // Project info
            VStack(alignment: .leading, spacing: 12) {
                // Title and status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        StatusBadge.forJobStatus(project.status)

                        // Show task type badge if this is a task event
                        if let taskType = taskTypeBadge {
                            Text(taskType.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(taskColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .fill(taskColor.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                                .stroke(taskColor.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                                        )
                                )
                        }
                    }
                }
                
                // Address
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(project.address ?? "No address")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
                
                // Distance (if available)
                if let userLocation = coordinator.userLocation,
                   let projectCoordinate = project.coordinate {
                    let distance = userLocation.distance(from: CLLocation(latitude: projectCoordinate.latitude, longitude: projectCoordinate.longitude))
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text(formatDistance(distance))
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    // Start/Navigate button
                    if let onStart = onStartProject {
                        HStack {
                            if isStarting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            }
                            Text("START")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .onTapGesture {
                            guard !isStarting else { return }
                            
                            isStarting = true
                            errorMessage = nil
                            
                            // Validate project has coordinates
                            guard project.coordinate != nil else {
                                errorMessage = "Project location not available"
                                isStarting = false
                                return
                            }
                            
                            // Start the project
                            onStart(project)
                            
                            // Also start navigation
                            Task {
                                do {
                                    try await coordinator.startNavigation()
                                    isStarting = false
                                } catch {
                                    isStarting = false
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                    
                    // View details button
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("DETAILS")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.secondaryText, lineWidth: OPSStyle.Layout.Border.thick)
                    )
                    .onTapGesture { 
                        showFullDetails = true 
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(minHeight: 250) // Ensure minimum height to show all content
        .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
        .contentShape(Rectangle()) // Make entire card tappable
        .background(
            ZStack {
                BlurView(style: .systemMaterialDark)
                OPSStyle.Colors.cardBackground.opacity(0.3)
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius, corners: [.topLeft, .topRight])
        .sheet(isPresented: $showFullDetails) {
            ProjectDetailsView(project: project)
        }
        .onTapGesture {
            // Catch any taps on the card itself (not buttons)
        }
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0f m away", distance)
        } else {
            return String(format: "%.1f km away", distance / 1000)
        }
    }
}

