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
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
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
    let onTap: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLongPress: () -> Void
    
    // State for visual feedback, separate from other logic
    @State private var isLongPressing = false
    
    var body: some View {
        ZStack {
            // Card content with visual feedback
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Project title
                Text(project.title)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                
                HStack {
                    // Client name
                    Text(project.clientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    // Address
                    Text(project.address)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding()
            .background(
                ZStack {
                    // Base background
                    Color("CardBackground")
                        .opacity(0.5)
                    
                    Rectangle()
                        .fill(Color.clear)
                        .background(Material.ultraThinMaterial)
                    
                    // Highlight effect - only applied to background
                    if isLongPressing {
                        OPSStyle.Colors.primaryAccent.opacity(0.15)
                    }
                }
            )
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
        .padding(.horizontal)
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
}
