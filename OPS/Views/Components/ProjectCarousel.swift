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
        TabView(selection: $selectedIndex) {
            // Create card views for each project
            ForEach(projects.indices, id: \.self) { index in
                makeProjectCard(for: index)
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .frame(height: 140)
       // .background(backgroundView)
        .onChange(of: selectedIndex) { _, _ in
            if showStartConfirmation {
                showStartConfirmation = false
            }
        }
    }
    
    // Extract the background to a separate view
    private var backgroundView: some View {
        ZStack {
            Color("CardBackground").opacity(0.5)
            Rectangle()
                .fill(Color.clear)
                .background(Material.ultraThinMaterial)
        }
    }
    
    // Create a separate function to build each card
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
    
    // Extract tap logic to its own function
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
struct ProjectCardView: View {
    let project: Project
    let isSelected: Bool
    let showConfirmation: Bool
    let isActiveProject: Bool
    let onTap: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        cardContent
            .padding(.horizontal)
            .contentShape(Rectangle()) // Make entire card tappable
            .onTapGesture(perform: onTap)
            .onLongPressGesture(perform: onLongPress)
    }
    
    // Extract card content to reduce nesting
    private var cardContent: some View {
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
        .background(cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(confirmationOverlay)
    }
    
    // Extract background to reduce complexity
    private var cardBackground: some View {
        ZStack {
            Color("CardBackground")
                .opacity(0.5)
            
            Rectangle()
                .fill(Color.clear)
                .background(Material.ultraThinMaterial)
        }
    }
    
    // Extract overlay to separate view builder
    @ViewBuilder
    private var confirmationOverlay: some View {
        if showConfirmation {
            if isActiveProject {
                // Stop overlay
                Button(action: onStop) {
                    Text("Stop Project?")
                        .font(OPSStyle.Typography.bodyBold)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }
}
