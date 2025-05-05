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
            HStack(spacing: 0) {
                // Left status bar based on reference design - wider and more visible
                Rectangle()
                    .fill(project.statusColor)
                    .frame(width: 8)
                    .shadow(color: project.statusColor.opacity(0.6), radius: 2, x: 1, y: 0)
                
                // Content area
                VStack(alignment: .leading, spacing: 6) {
                    // Project title in all caps
                    Text(project.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .textCase(.uppercase)
                    
                    // Client name
                    Text(project.clientName)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                    
                    // Address
                    Text(project.address)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                Spacer()
            }
            .background(cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .contentShape(Rectangle()) // Make entire card tappable
            .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
    }
    
    // Use darker background color for card
    private var cardBackground: some View {
        Color.black.opacity(0.7)
    }
}
