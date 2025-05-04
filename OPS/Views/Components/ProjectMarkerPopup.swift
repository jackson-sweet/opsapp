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
                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            // Address
            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                
                Text(formatAddress(project.address))
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            // Status badge
            StatusBadge(status: project.status)
                .padding(.top, 2)
                .frame(height: 24)
            
            // View details button
            Button(action: onTap) {
                HStack {
                    Text("View Details")
                        .font(OPSStyle.Typography.smallButton)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(OPSStyle.Colors.secondaryAccent)
                .foregroundColor(.white)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(width: 220)
        .background(
            ZStack {
                // Background
                OPSStyle.Colors.cardBackground
                    .opacity(0.95)
                
                // Subtle gradient overlay
                LinearGradient(
                    gradient: Gradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear
                        ]
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .overlay(
            // Top arrow indicator
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

// Triangle shape for the popup arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

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
