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
    let coordinator: MapCoordinator
    let onStartProject: ((Project) -> Void)?
    @State private var showFullDetails = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    
    var body: some View {
        // let _ = print("🟡 ProjectDetailsCard: Rendering for project: \(project.title)")
        VStack(alignment: .leading, spacing: 0) {
            // Handle to drag
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(OPSStyle.Colors.secondaryText.opacity(0.5))
                    .frame(width: 40, height: 5)
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                // print("🟡 Drag handle tapped - dismissing card")
                // Allow tapping the handle to dismiss
                coordinator.showingProjectDetails = false
            }
            
            // Project info
            VStack(alignment: .leading, spacing: 12) {
                // Title and status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        
                        Text(project.clientName)
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    StatusBadge.forJobStatus(project.status)
                }
                
                // Address
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Text(project.address)
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
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
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
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text("START")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .onTapGesture {
                            guard !isStarting else { return }
                            
                            // print("🔵 START button tapped for project: \(project.title)")
                            isStarting = true
                            errorMessage = nil
                            
                            // Validate project has coordinates
                            guard project.coordinate != nil else {
                                // print("❌ Project has no coordinates!")
                                errorMessage = "Project location not available"
                                isStarting = false
                                return
                            }
                            
                            // Start the project
                            // print("🔵 Calling onStartProject callback")
                            onStart(project)
                            
                            // Also start navigation
                            Task {
                                do {
                                    // print("🔵 Starting navigation...")
                                    try await coordinator.startNavigation()
                                    // print("✅ Navigation started successfully")
                                    isStarting = false
                                } catch {
                                    isStarting = false
                                    errorMessage = error.localizedDescription
                                    // print("❌ Navigation error: \(error)")
                                }
                            }
                        }
                    }
                    
                    // View details button
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16))
                        Text("DETAILS")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
                    .onTapGesture { 
                        // print("🔵 DETAILS button tapped for project: \(project.title)")
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
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: -5)
        .sheet(isPresented: $showFullDetails) {
            ProjectDetailsView(project: project)
        }
        .onTapGesture {
            // Catch any taps on the card itself (not buttons)
            // print("🟡 ProjectDetailsCard: Card background tapped")
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

