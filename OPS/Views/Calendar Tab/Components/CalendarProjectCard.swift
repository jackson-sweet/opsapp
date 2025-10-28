//
//  CalendarProjectCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


import SwiftUI

struct CalendarProjectCard: View {
    let project: Project
    let isFirst: Bool
    let onTap: () -> Void
    
    var body: some View {
        // When used with NavigationLink, the onTap action is optional
        HStack(spacing: 0) {
                // Left status bar based on reference design - wider and more visible
                Rectangle()
                .fill(project.status == .closed ? .white : project.statusColor)
                    .frame(width: 4)
                
                // Content area
                VStack(alignment: .leading, spacing: 6) {
                    // Project title in all caps
                    Text(project.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .textCase(.uppercase)
                    
                    // Client name
                    Text(project.effectiveClientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                    
                    // Address
                    Text(project.address ?? "No address")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                Spacer()
            }
            .background(cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .contentShape(Rectangle()) // Make entire card tappable
            .shadow(color: Color.black, radius: 2, x: 0, y: 1)
            .onTapGesture {
                onTap()
            }
        .padding(.vertical, 4)
        .padding(.horizontal)
    }
    
    // Use darker background color for card
    private var cardBackground: some View {
        OPSStyle.Colors.cardBackgroundDark
    }
}
