//
//  ProjectMarkerPopup.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI

struct ProjectMarkerPopup: View {
    let project: Project
    var onTap: () -> Void
    
    // Animation states
    @State private var isAnimating = false
    // No button tap functionality
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Project title
            Text(project.title)
                .font(OPSStyle.Typography.cardSubtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            
            // Client name
            HStack(spacing: 4) {
                Image(systemName: "building.2")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            // Address
            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text(formatAddress(project.address))
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            // Status badge
            StatusBadge.forJobStatus(project.status)
                .padding(.top, 2)
                .frame(height: 24)
        }
        .padding(12)
        .frame(width: 220)
        .background(
            ZStack {
                // Background
                OPSStyle.Colors.cardBackground
                    .opacity(0.95)
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .overlay(
            // Top arrow indicator (pointing up from top of card to the pin)
            Triangle()
                .fill(OPSStyle.Colors.cardBackground.opacity(0.95))
                .frame(width: 16, height: 8)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: -8)
            , alignment: .top
        )
        .scaleEffect(isAnimating ? 1.0 : 0.7)
        .opacity(isAnimating ? 1.0 : 0)
        .onAppear {
            // Simple animation without using withAnimation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        // If the address is too long, trim and add ellipsis
        let maxLength = 30
        if address.count > maxLength {
            let endIndex = address.index(address.startIndex, offsetBy: maxLength)
            return String(address[..<endIndex]) + "..."
        }
        return address
    }
}

// Triangle shape for the popup arrow pointing up (for top of card)
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Start at top center point
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        // Line to bottom left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Line to bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Close path back to top center
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

// Triangle shape for the popup arrow pointing down (for bottom of card)
struct BottomTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))  // Point at bottom
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)) // Line to top left
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)) // Line to top right
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) // Back to bottom point
        return path
    }
}

// Button functionality removed

// For representation in previews
struct ProjectMarkerPopupPreviews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            ProjectMarkerPopup(
                project: Project(
                    id: "1",
                    title: "Office Building Renovation",
                    status: .pending
                ),
                onTap: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
