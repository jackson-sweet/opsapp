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
                // Re-enable long press to show project details
                print("ProjectCarousel: Long press detected for project \(project.id)")
                onLongPress(project)
            }
        )
    }
    
    private func handleCardTap(forIndex index: Int) {
        print("ProjectCarousel: handleCardTap called for index \(index)")
        
        // Add guard for isInProjectMode to prevent unwanted behavior during project mode
        guard !isInProjectMode else {
            print("ProjectCarousel: Ignoring tap in project mode")
            return
        }
        
        if selectedIndex == index {
            // Toggle confirmation ONLY - this is the only action on tap for selected card
            // Set a guard to avoid interfering with long press
            DispatchQueue.main.async {
                self.showStartConfirmation.toggle()
                print("ProjectCarousel: Toggling showStartConfirmation to \(self.showStartConfirmation)")
            }
        } else {
            // Select this card - the only action for a new card
            selectedIndex = index
            // Always hide confirmation when selecting a new card
            showStartConfirmation = false
            print("ProjectCarousel: Selected new card at index \(index)")
        }
        
        // Debug log to verify behavior
        print("ProjectCarousel: After tap processing - selectedIndex: \(selectedIndex), showStartConfirmation: \(showStartConfirmation)")
    }
}

// Create a dedicated view for the card content
enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    // Specialized feedback for long press success
    static func longPressSuccess() {
        // First a heavy impact
        impact(.heavy)
        
        // Then a success notification after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
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
    
    // Use State for the long press state
    @State private var isLongPressing = false
    
    var body: some View {
        ZStack {
            // Fixed size container for card
            ZStack {
                // Card background
                ZStack {
                    // Base background
                    Color("CardBackground")
                        .opacity(0.3)
                    
                    Rectangle()
                        .fill(Color.clear)
                        .background(Material.thinMaterial.opacity(0.7))
                    
                    // Subtle background color for completed projects
                    if project.status.isCompleted {
                        OPSStyle.Colors.statusColor(for: .completed).opacity(0.1)
                    }
                    
                    // Simple highlight for long press
                    if isLongPressing {
                        OPSStyle.Colors.primaryAccent.opacity(0.3)
                    }
                }
                
                // Content with fixed width 
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
                    .padding(12)
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
                    .cornerRadius(10)
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                    
                    // Completed status badge in bottom right
                    if project.status.isCompleted {
                        Text("COMPLETED")
                            .font(OPSStyle.Typography.smallCaption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(OPSStyle.Colors.statusColor(for: .completed))
                            .cornerRadius(3)
                            .padding([.bottom, .trailing], 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .frame(width: 362, height: 85)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .scaleEffect(isLongPressing ? 0.97 : 1.0)
            .background(Color.clear) // Important for hit testing
            .contentShape(Rectangle()) // Make the entire card recognizable for gestures
            
            // Confirmation overlay
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
            
            // Simple text indicator for long press
            if isLongPressing {
                Text("Long press to view details")
                    .font(OPSStyle.Typography.cardBody)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(Color.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .position(x: 362/2, y: 85-20)
            }
        }
        // Go back to using standard SwiftUI gesture modifiers
        .onTapGesture {
            print("Simple tap detected for \(project.title)")
            onTap()
        }
        .onLongPressGesture(minimumDuration: 1.0, pressing: { isPressing in
            // Update the long press state
            isLongPressing = isPressing
            print("Long press state: \(isPressing ? "started" : "ended") for \(project.title)")
        }, perform: {
            // This is called when the long press is completed
            print("Long press completed for \(project.title)")
            HapticFeedback.impact(.heavy)
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
