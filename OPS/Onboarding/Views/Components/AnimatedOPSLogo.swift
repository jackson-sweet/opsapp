//
//  AnimatedOPSLogo.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-30.
//

import SwiftUI

struct AnimatedOPSLogo: View {
    var onAnimationComplete: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 60) {
                // OPS Logo - Static display
                ZStack {
                    // All three paths shown immediately
                    OPSLogoPath(layerIndex: 0)
                        .fill(Color.white)
                    
                    OPSLogoPath(layerIndex: 1)
                        .fill(Color.white)
                    
                    OPSLogoPath(layerIndex: 2)
                        .fill(Color.white)
                }
                .frame(width: 200, height: 200)
                
                // Welcome text with arrow
                HStack(spacing: 16) {
                    Text("WELCOME TO OPS")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Image(systemName: "arrow.right")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .onAppear {
            // Simple delay before proceeding
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onAnimationComplete?()
            }
        }
    }
}

// Shape for each nested layer of the OPS logo
struct OPSLogoPath: Shape {
    let layerIndex: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let strokeWidth: CGFloat = 20
        let gap: CGFloat = 30
        let inset = CGFloat(layerIndex) * gap
        
        // Calculate the working rect for this layer
        let workingRect = rect.insetBy(dx: inset, dy: inset)
        
        // Define key dimensions
        let width = workingRect.width
        let height = workingRect.height
        
        // Different corner radii - top left and bottom right are double the others
        let largeRadius = min(width, height) * 0.3  // Larger radius for TL and BR
        let smallRadius = min(width, height) * 0.15 // Smaller radius for TR and BL
        
        // Define the opening at the left end of the bottom edge
        let openingWidth = width * 0.25
        
        // Create the outer path (clockwise from opening)
        // Start at the left end of bottom edge (at the opening)
        let startX = workingRect.minX
        let startY = workingRect.maxY
        
        path.move(to: CGPoint(x: startX, y: startY))
        
        // Draw up the left side
        path.addLine(to: CGPoint(x: startX, y: workingRect.minY + largeRadius))
        
        // Top left corner (large radius)
        path.addArc(
            center: CGPoint(x: startX + largeRadius, y: workingRect.minY + largeRadius),
            radius: largeRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        
        // Top edge
        path.addLine(to: CGPoint(x: workingRect.maxX - smallRadius, y: workingRect.minY))
        
        // Top right corner (small radius)
        path.addArc(
            center: CGPoint(x: workingRect.maxX - smallRadius, y: workingRect.minY + smallRadius),
            radius: smallRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        
        // Right edge
        path.addLine(to: CGPoint(x: workingRect.maxX, y: workingRect.maxY - largeRadius))
        
        // Bottom right corner (large radius)
        path.addArc(
            center: CGPoint(x: workingRect.maxX - largeRadius, y: workingRect.maxY - largeRadius),
            radius: largeRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // Bottom edge (from right to opening)
        path.addLine(to: CGPoint(x: startX + openingWidth, y: workingRect.maxY))
        
        // Now create the inner path (counter-clockwise from opening)
        // This creates the "track" or "channel" effect
        let innerInset = strokeWidth + gap * 0.3 // Distance to inner edge
        
        // Sharp edge at opening (no curve here)
        path.addLine(to: CGPoint(x: startX + openingWidth, y: workingRect.maxY - innerInset))
        
        // Inner bottom edge (going left)
        path.addLine(to: CGPoint(x: workingRect.maxX - largeRadius, y: workingRect.maxY - innerInset))
        
        // Inner bottom right corner (following the large radius)
        let innerBRRadius = largeRadius - innerInset
        if innerBRRadius > 0 {
            path.addArc(
                center: CGPoint(x: workingRect.maxX - largeRadius, y: workingRect.maxY - largeRadius),
                radius: innerBRRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(0),
                clockwise: true
            )
        }
        
        // Inner right edge
        path.addLine(to: CGPoint(x: workingRect.maxX - innerInset, y: workingRect.minY + smallRadius))
        
        // Inner top right corner (following the small radius)
        let innerTRRadius = smallRadius - innerInset
        if innerTRRadius > 0 {
            path.addArc(
                center: CGPoint(x: workingRect.maxX - smallRadius, y: workingRect.minY + smallRadius),
                radius: innerTRRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }
        
        // Inner top edge
        path.addLine(to: CGPoint(x: startX + largeRadius, y: workingRect.minY + innerInset))
        
        // Inner top left corner (following the large radius)
        let innerTLRadius = largeRadius - innerInset
        if innerTLRadius > 0 {
            path.addArc(
                center: CGPoint(x: startX + largeRadius, y: workingRect.minY + largeRadius),
                radius: innerTLRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        }
        
        // Inner left edge (down to opening)
        path.addLine(to: CGPoint(x: startX + innerInset, y: startY - innerInset))
        
        // Sharp edge back to start
        path.addLine(to: CGPoint(x: startX, y: startY))
        
        return path
    }
}

#Preview {
    AnimatedOPSLogo()
}