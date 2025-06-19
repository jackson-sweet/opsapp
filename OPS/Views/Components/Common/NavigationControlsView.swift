//
//  NavigationControlsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI

/// A loading banner that displays while navigation is being calculated
struct NavigationLoadingBanner: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Loading spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
                    .frame(width: 30, height: 30)
                
                // Loading text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calculating route...")
                        .font(OPSStyle.Typography.subtitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Finding the best path to your destination")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Cancel button
                Button(action: {
                    // Post notification to stop routing
                    NotificationCenter.default.post(
                        name: Notification.Name("StopRouting"), 
                        object: nil
                    )
                }) {
                    Text("Cancel")
                        .font(OPSStyle.Typography.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.errorStatus)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(color: Color.black, radius: 4, x: 0, y: 2)
        .onAppear {
            isAnimating = true
        }
    }
}

/// A container view for navigation controls to reduce complexity in HomeView
struct NavigationControlsView: View {
    // Routing state
    let isRouting: Bool
    let currentNavStep: NavigationStep?
    @Binding var showFullDirectionsView: Bool
    let routeDirections: [String]
    let estimatedArrival: String?
    let routeDistance: String?
    
    // Project state
    let isInProjectMode: Bool
    let activeProject: Project?
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                // Action buttons for active project - at bottom
                Spacer()
                actionButtons
            }.padding(.bottom, 40)
            
            // Navigation view at top - position by hand
            if isRouting {
                VStack {
                    // Top position with safe area spacing
                    navigationView
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
        }
        .onChange(of: isRouting) { _, newValue in
        }
        .onChange(of: currentNavStep) { _, newStep in
        }
    }
    
    // Extract the navigation view into a computed property
    private var navigationView: some View {
        Group {
            if isRouting {
                if let currentStep = currentNavStep {
                    // Navigation data is ready
                    if showFullDirectionsView {
                        // Full directions view with dismiss handler
                        RouteDirectionsView(
                            directions: routeDirections,
                            estimatedArrival: estimatedArrival,
                            distance: routeDistance,
                            onDismiss: {
                                // Hide the full directions view
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showFullDirectionsView = false
                                }
                            }
                        )
                    } else {
                        // Compact navigation banner at top
                        NavigationBanner(
                            instruction: currentStep.instruction,
                            distance: currentStep.distance,
                            isLastStep: currentStep.isLastStep,
                            onEndNavigation: {
                                // Post notification to stop routing but not end project
                                NotificationCenter.default.post(
                                    name: Notification.Name("StopRouting"), 
                                    object: nil
                                )
                            }
                        )
                        .transition(.move(edge: .top))
                        .onTapGesture {
                            // Toggle to show full directions when tapped - use a faster animation
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFullDirectionsView = true
                            }
                        }
                    }
                } else {
                    // Show loading state while route is being calculated
                    NavigationLoadingBanner()
                        .transition(.move(edge: .top))
                }
            } else {
                // Empty view when not routing
                EmptyView()
            }
        }
    }
    
    // Extract the action buttons into a computed property
    private var actionButtons: some View {
        Group {
            if isInProjectMode, let project = activeProject {
                ProjectActionBar(project: project)
            } else {
                EmptyView()
            }
        }
    }
}

#if DEBUG
// Preview
struct NavigationControlsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationControlsView(
            isRouting: true,
            currentNavStep: NavigationStep(
                instruction: "Turn left on Main Street",
                distance: "200m",
                distanceValue: 200,
                isLastStep: false
            ),
            showFullDirectionsView: .constant(false),
            routeDirections: ["Turn left on Main Street", "Continue for 500m"],
            estimatedArrival: "10:30 AM (5 min)",
            routeDistance: "1.2 km",
            isInProjectMode: true,
            activeProject: Project(
                id: "test",
                title: "Test Project",
                status: .inProgress
            )
        )
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
