//
//  ProjectCarousel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct ProjectCarousel: View {
    let projects: [Project]
    @Binding var selectedIndex: Int
    @Binding var showStartConfirmation: Bool
    let isInProjectMode: Bool
    let activeProjectID: String?
    let onStart: (Project) -> Void
    let onStop: (Project) -> Void
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                ProjectCard(
                    project: project,
                    isSelected: selectedIndex == index,
                    showConfirmation: showStartConfirmation && selectedIndex == index,
                    isActiveProject: activeProjectID == project.id,
                    onStart: { onStart(project) },
                    onStop: { onStop(project) }
                )
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .frame(height: 120)
        .background(OPSStyle.Colors.cardBackground.opacity(0.7))
        .onChange(of: selectedIndex) { _, _ in
            showStartConfirmation = false
        }
    }
}