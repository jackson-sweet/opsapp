//
//  CalendarProjectCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarProjectCard.swift
import SwiftUI

struct CalendarProjectCard: View {
    let project: Project
    let isFirst: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Status indicator
                Rectangle()
                    .fill(project.statusColor)
                    .frame(width: 4)
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    
                    Text(project.clientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                    
                    Text(project.address)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                
                Spacer()
            }
            .padding()
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .contentShape(Rectangle()) // Make entire card tappable
        }
        .padding(.top, isFirst ? 0 : 8)
        .padding(.horizontal)
    }
}