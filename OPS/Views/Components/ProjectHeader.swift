//
//  ProjectHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct ProjectHeader: View {
    @EnvironmentObject private var appState: AppState
    var project: Project?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(project?.status.rawValue.uppercased() ?? "IN PROGRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                
                if let project = project {
                    Text("\(project.clientName), \(project.title)")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    
                    Text(project.address)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                appState.exitProjectMode()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
}