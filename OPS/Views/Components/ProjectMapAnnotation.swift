//
//  ProjectMapAnnotation.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit

// Custom annotation view for SwiftUI MapKit integration
struct ProjectMapAnnotation: View {
    let project: Project
    let isSelected: Bool
    let isActiveProject: Bool
    let onTap: () -> Void
    
    @State private var showPopup = false
    
    // Size configuration
    private var circleSize: CGFloat {
        if isActiveProject {
            return 36
        } else if isSelected {
            return 30
        } else {
            return 24
        }
    }
    
    var body: some View {
        ZStack {
            // The marker
            ZStack {
                // Active marker with pulse
                if isActiveProject {
                    // Pulse animation
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                        .frame(width: circleSize * 1.3, height: circleSize * 1.3)
                        .scaleEffect(showPopup ? 1.3 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: showPopup
                        )
                }
                
                // Circle background
                Circle()
                    .fill(isActiveProject || isSelected ? OPSStyle.Colors.primaryAccent : Color.white)
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white,
                                lineWidth: isActiveProject ? 3 : (isSelected ? 2 : 0)
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(isActiveProject ? 0.4 : 0.2),
                        radius: isActiveProject ? 4 : 2,
                        x: 0,
                        y: isActiveProject ? 2 : 1
                    )
                
                // Icon
                Image(systemName: "location.fill")
                    .font(.system(size: isActiveProject ? 16 : (isSelected ? 14 : 12)))
                    .foregroundColor(isActiveProject || isSelected ? .white : OPSStyle.Colors.secondaryAccent)
            }
            .onTapGesture {
                // Toggle popup state
                showPopup.toggle()
                
                // Call the parent handler
                onTap()
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
            
            // Popup only shown when selected and popup state is true
            if isSelected && showPopup {
                ProjectMarkerPopup(project: project, onTap: onTap)
                    .offset(y: -160) // Offset above the marker
                    .zIndex(100)
            }
        }
    }
}

struct ProjectMapAnnotationPreviews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                ProjectMapAnnotation(
                    project: Project(
                        id: "1",
                        title: "Office Building Renovation",
                        status: .accepted
                    ),
                    isSelected: false,
                    isActiveProject: false,
                    onTap: {}
                )
                
                ProjectMapAnnotation(
                    project: Project(
                        id: "2", 
                        title: "Hospital Extension",
                        status: .inProgress
                    ),
                    isSelected: true,
                    isActiveProject: false,
                    onTap: {}
                )
                
                ProjectMapAnnotation(
                    project: Project(
                        id: "3",
                        title: "School Renovation",
                        status: .completed
                    ),
                    isSelected: true,
                    isActiveProject: true,
                    onTap: {}
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
