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
            // Semi-transparent background with blur
            ZStack {
                
                BlurView(style: .dark)
                    .cornerRadius(50)
                    .frame(width: 362, height: 85)
                
                HStack(spacing: 20) {
                    ForEach(ProjectAction.allCases, id: \.self) { action in
                        
                        Button(action: {
                            handleAction(action)
                        }) {
                            Image(systemName: action.iconName)
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.secondaryAccent)
                                .frame(width: 72, height: 72)
                                .background(
                                    Circle()
                                        .fill(OPSStyle.Colors.cardBackground)
                                )
                        }
            
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 85)
            .frame(maxWidth: 362)
            
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
        case .status: return "checkmark.circle"
        case .notes: return "doc.text"
        case .edit: return "pencil"
        case .camera: return "camera"
        }
    }
}

