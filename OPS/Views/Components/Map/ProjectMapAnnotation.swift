//
//  ProjectMapAnnotation.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit

// Temporary popup for old map compatibility
struct OldProjectMarkerPopup: View {
    let project: Project
    var onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text(project.effectiveClientName)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Button(action: onTap) {
                Text("View Details")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OPSStyle.Colors.cardBackground)
                .shadow(radius: 4)
        )
    }
}

// Using SF Symbols instead of custom shape markers

// Custom annotation view for SwiftUI MapKit integration
struct ProjectMapAnnotation: View {
    let project: Project
    let isSelected: Bool
    let isActiveProject: Bool
    let onTap: () -> Void
    
    @State private var showPopup = false
    
    // Helper function to get color for status indicator
    private func getStatusColor(_ status: Status) -> Color {
        switch status {
        case .rfq:
            return Color(red: 0.95, green: 0.8, blue: 0.2)     // Brighter yellow
        case .estimated:
            return Color(red: 0.2, green: 0.6, blue: 0.9)      // Brighter blue
        case .accepted:
            return Color(red: 0.2, green: 0.8, blue: 0.4)      // Brighter green
        case .inProgress:
            return Color(red: 0.95, green: 0.5, blue: 0.2)     // Brighter orange
        case .completed:
            return Color(red: 0.3, green: 0.9, blue: 0.5)      // Brighter green
        case .closed:
            return Color(red: 0.6, green: 0.6, blue: 0.6)      // Brighter gray
        default:
            return Color(red: 0.6, green: 0.6, blue: 0.6)      // Default gray
        }
    }
    
    // Size configuration
    private var circleSize: CGFloat {
        if isActiveProject {
            return 48  // Active project has largest marker
        } else if isSelected {
            return 42  // Selected project marker is medium sized
        } else {
            return 36  // Default marker size
        }
    }
    
    // Font size for the marker symbol
    private var markerSize: CGFloat {
        if isActiveProject {
            return circleSize * 0.9
        } else if isSelected {
            return circleSize * 0.85
        } else {
            return circleSize * 0.8
        }
    }
    
    // Color based on selection state
    private var markerColor: Color {
        if isActiveProject {
            return OPSStyle.Colors.secondaryAccent  // Active projects use secondaryAccent
        } else if isSelected {
            return OPSStyle.Colors.primaryAccent     // Selected projects use primaryAccent
        } else {
            return Color.white                      // Default is white as requested
        }
    }
    
    // SF Symbol to use based on selection state
    private var markerSymbol: String {
        if isActiveProject {
            return "mappin.circle"             // Active project uses filled circle marker
        } else if isSelected {
            return "mappin.circle"             // Selected project uses filled circle marker
        } else {
            return "mappin"                        // Default projects use simple pin
        }
    }
    
    // Status icon function removed as we no longer show status icons
    
    var body: some View {
        ZStack {
            // SF Symbols marker design
            // NOTE: Tap handling is done through MKMapViewDelegate didSelect method
            // SwiftUI gestures are disabled because they conflict with native map tap handling
            MarkerView()
                .allowsHitTesting(false)  // Disable SwiftUI hit testing - let MKMapView handle it

            // Show popup when showPopup is true, regardless of selection state
            if showPopup {
                // Use the old ProjectMarkerPopup implementation for the old map
                OldProjectMarkerPopup(project: project, onTap: onTap)
                    .offset(y: circleSize * 2.5) // Significantly increased offset to position popup much lower
                    .allowsHitTesting(true) // CRITICAL: Make sure hit testing is allowed!
                    .zIndex(9999) // Super high zIndex to make sure it's on top
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: showPopup)
            }
        }
    }
    
    // Extracted marker view for better organization and proper gesture handling
    private func MarkerView() -> some View {
        return ZStack {
            // Active marker with subtle pulse animation
            if isActiveProject {
                // Pulse effect for active project
                Circle()
                    .fill(OPSStyle.Colors.secondaryAccent.opacity(0.15))
                    .frame(width: circleSize * 1.8, height: circleSize * 1.8)
                    .scaleEffect(1.0) // Removed animation that could interfere with positioning
                    .blur(radius: 2)
            }
            
            // Main marker with different symbol based on state
            Image(systemName: markerSymbol)
                .font(.system(size: markerSize, weight: .semibold))
                .foregroundColor(markerColor)
                .shadow(color: OPSStyle.Colors.shadowColor, radius: 2, x: 0, y: 2)
        }
        // Use an extremely large hit area for better touch recognition
        .contentShape(Rectangle())
        // Make sure the entire area is tappable with a large transparent background
        .background(
            Color.clear
                .frame(width: circleSize * 5, height: circleSize * 5)
                .contentShape(Rectangle())
        )
        // Debug visual for tap area
        #if DEBUG
        //.border(Color.red.opacity(0.2), width: 1) // Uncomment to see tap area during development
        #endif
    }
    
    // Helper function to handle tap gesture
    private func handleTap() {
        // Always show the popup when tapping a marker
        withAnimation(.easeInOut(duration: 0.3)) {
            // If already showing, toggle off. If not showing, turn on.
            // This ensures we can hide our own popup but won't interfere with others
            showPopup = !showPopup
        }
        
        // Strong haptic feedback to confirm tap
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare() // Prepare for better responsiveness
        generator.impactOccurred(intensity: 1.0) // Use full intensity for clear feedback
        
        // Call the parent handler after a very slight delay to ensure animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onTap()
        }
        
        // Print detailed debug message to console
    }
    
    // Helper function to handle long press gesture
    private func handleLongPress() {
        // Always show popup on long press
        withAnimation {
            showPopup = true
        }
        
        // Call the parent handler
        onTap()
        
        // Stronger haptic feedback for long press
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        // Print debug message to console
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
