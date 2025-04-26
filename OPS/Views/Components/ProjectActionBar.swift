//
//  ProjectActionBar.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct ProjectActionBar: View {
    let project: Project
    
    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing4) {
            ForEach(ProjectAction.allCases, id: \.self) { action in
                Button(action: {
                    handleAction(action)
                }) {
                    Image(systemName: action.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(OPSStyle.Colors.secondaryAccent)
                        )
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing4)
        .padding(.horizontal)
        .background(
            // Semi-transparent background with blur
            ZStack {
                Color.black.opacity(0.7)
                Rectangle()
                    .fill(Color.clear)
                    .background(Material.ultraThinMaterial)
            }
        )
    }
    
    private func handleAction(_ action: ProjectAction) {
        switch action {
        case .status:
            print("Update status for project: \(project.id)")
        case .notes:
            print("View/edit notes for project: \(project.id)")
        case .edit:
            print("Edit project: \(project.id)")
        case .camera:
            print("Take photo for project: \(project.id)")
        }
    }
}

enum ProjectAction: CaseIterable {
    case status
    case notes
    case edit
    case camera
    
    var iconName: String {
        switch self {
        case .status: return "checkmark.circle.fill"
        case .notes: return "doc.text.fill"
        case .edit: return "pencil"
        case .camera: return "camera.fill"
        }
    }
}
