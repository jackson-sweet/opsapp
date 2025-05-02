//
//  ProjectCarousel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

// First, create a simpler version that separates concerns
struct ProjectCarousel: View {
    let projects: [Project]
    @Binding var selectedIndex: Int
    @Binding var showStartConfirmation: Bool
    let isInProjectMode: Bool
    let activeProjectID: String?
    let onStart: (Project) -> Void
    let onStop: (Project) -> Void
    let onLongPress: (Project) -> Void
    
    var body: some View {
            ZStack(alignment: .top){
            TabView(selection: $selectedIndex) {
                // Create card views for each project
                ForEach(projects.indices, id: \.self) { index in
                    makeProjectCard(for: index)
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Hide default dots
            .frame(height: 140)
            
            
        }
        .onChange(of: selectedIndex) { _, _ in
            if showStartConfirmation {
                showStartConfirmation = false
            }
        }

    
    }
    
    
    private func makeProjectCard(for index: Int) -> some View {
        let project = projects[index]
        return ProjectCardView(
            project: project,
            isSelected: selectedIndex == index,
            showConfirmation: showStartConfirmation && selectedIndex == index,
            isActiveProject: activeProjectID == project.id,
            currentIndex: selectedIndex,
            totalCount: projects.count,
            onTap: {
                handleCardTap(forIndex: index)
            },
            onStart: {
                onStart(project)
            },
            onStop: {
                onStop(project)
            },
            onLongPress: {
                onLongPress(project)
            }
        )
    }
    
    private func handleCardTap(forIndex index: Int) {
        if selectedIndex == index {
            // Toggle confirmation if already selected
            showStartConfirmation.toggle()
        } else {
            // Select this card
            selectedIndex = index
            showStartConfirmation = false
        }
    }
}

// Create a dedicated view for the card content
enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

// Then fix the ProjectCardView implementation
struct ProjectCardView: View {
    let project: Project
    let isSelected: Bool
    let showConfirmation: Bool
    let isActiveProject: Bool
    let currentIndex: Int
    let totalCount: Int
    let onTap: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLongPress: () -> Void
    
    // State for visual feedback, separate from other logic
    @State private var isLongPressing = false
    
    var body: some View {
        ZStack {
            // Fixed size container for card
            ZStack {
                // Card background
                ZStack {
                    // Base background - more transparent
                    Color("CardBackground")
                        .opacity(0.3)
                    
                    // Less blur
                    Rectangle()
                        .fill(Color.clear)
                        .background(Material.thinMaterial.opacity(0.7))
                    
                    // Highlight effect - only applied to background
                    if isLongPressing {
                        OPSStyle.Colors.primaryAccent.opacity(0.15)
                    }
                }
                
                // Content with fixed width and exactly 12px perimeter padding
                ZStack(alignment: .topTrailing) {
                    // Main content
                    VStack(alignment: .leading, spacing: 2) {
                        // Project title
                        Text(project.title)
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        
                        // Client name
                        Text(project.clientName)
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                        
                        // Address with components
                        Text(extractAddressComponents(project.address))
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(12) // Exactly 12px of perimeter padding
                    .frame(width: 362, alignment: .leading)
                    
                    // Page indicators in top right corner
                    HStack(spacing: 12) {
                        ForEach(0..<totalCount, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.5))
                                .frame(width: 13, height: 13)
                        }
                    }
                    .padding(6)
                    //.background(Color.black.opacity(0.3))
                    .cornerRadius(10)
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                }
            }
            // Fixed exact dimensions - no additional padding needed
            .frame(width: 362, height: 85)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .scaleEffect(isLongPressing ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLongPressing)
            
            // Confirmation overlay as a separate layer
            if showConfirmation {
                if isActiveProject {
                    // Stop overlay
                    Button(action: onStop) {
                        Text("Stop Project?")
                            .font(OPSStyle.Typography.bodyBold)
                            .padding()
                            .frame(width: 362, height: 85)
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
                            .frame(width: 362, height: 85)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
        }
        .contentShape(Rectangle()) // Make entire card tappable
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, pressing: { isPressing in
            // Update visual state only
            isLongPressing = isPressing
        }, perform: {
            // Trigger haptic and action when complete
            HapticFeedback.impact(.medium)
            onLongPress()
        })
    }
    
    // Format address components
    private func extractAddressComponents(_ address: String) -> String {
        // Split the address if possible to extract components
        let components = address.components(separatedBy: ",")
        
        if components.count > 1 {
            // If we have components, format them nicely
            let streetInfo = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let cityInfo = components.count > 1 ? components[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            return "\(streetInfo), \(cityInfo)"
        } else {
            // If no clear components, just return the original
            return address
        }
    }
}
