//
//  ProjectMarkerPopup.swift
//  OPS
//
//  Small popup that appears below project markers when tapped during active project

import SwiftUI
import MapKit

struct ProjectMarkerPopup: View {
    let project: Project
    let isActiveProject: Bool
    let onNavigate: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Arrow pointing up to marker
            Triangle()
                .fill(OPSStyle.Colors.cardBackground)
                .frame(width: 20, height: 10)
                .offset(y: 1)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                
                // Client
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                
                // Address
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Text(project.address)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
                
                // Status
                StatusBadge.forJobStatus(project.status)
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Action buttons
                HStack(spacing: 8) {
                    if isActiveProject {
                        // Show current project indicator
                        HStack(spacing: 4) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 12))
                            Text("Current Project")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.secondaryAccent.opacity(0.2))
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                    } else {
                        // View details button
                        Button(action: {
                            // Post notification to show project details
                            NotificationCenter.default.post(
                                name: Notification.Name("ShowProjectDetails"),
                                object: nil,
                                userInfo: ["projectID": project.id]
                            )
                            onDismiss()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                Text("Details")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        
                        // Navigate button
                        Button(action: onNavigate) {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                Text("Navigate")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .frame(width: 200)
            .background(
                ZStack {
                    BlurView(style: .systemMaterialDark)
                    OPSStyle.Colors.cardBackground.opacity(0.9)
                }
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .contentShape(Rectangle()) // Make entire popup tappable
        .onTapGesture {
            // Prevent dismissal when tapping on popup content
        }
        .highPriorityGesture(
            TapGesture()
                .onEnded { _ in
                    // Ensure tap on popup content doesn't dismiss it
                }
        )
        .allowsHitTesting(true)
    }
}

// Triangle shape for arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
