//
//  NavigationBanner.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit

/// A banner that displays the next navigation instruction during active routing
struct NavigationBanner: View {
    let instruction: String
    let distance: String
    let isLastStep: Bool
    var onEndNavigation: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Left icon - arrow in the direction of the turn
                turnArrow
                    .frame(width: 30, height: 30)
                
                // Direction text and distance
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(distance)
                            .font(OPSStyle.Typography.subtitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // End navigation button
                        if let endAction = onEndNavigation {
                            Button(action: endAction) {
                                Text("End")
                                    .font(OPSStyle.Typography.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(OPSStyle.Colors.errorStatus)
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                        }
                    }
                    
                    Text(instruction)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(color: Color.black, radius: 4, x: 0, y: 2)
    }
    
    /// Determines which arrow icon to show based on the instruction
    private var turnArrow: some View {
        // Default is continue straight
        let imageName: String
        
        if isLastStep {
            // Final destination
            imageName = "location.fill"
        } else if instruction.lowercased().contains("right") {
            // Right turn
            if instruction.lowercased().contains("slight") {
                imageName = "arrow.turn.up.right"
            } else if instruction.lowercased().contains("sharp") {
                imageName = "arrow.turn.down.right"
            } else {
                imageName = "arrow.right"
            }
        } else if instruction.lowercased().contains("left") {
            // Left turn
            if instruction.lowercased().contains("slight") {
                imageName = "arrow.turn.up.left"
            } else if instruction.lowercased().contains("sharp") {
                imageName = "arrow.turn.down.left"
            } else {
                imageName = "arrow.left"
            }
        } else if instruction.lowercased().contains("u-turn") {
            // U-turn
            imageName = "arrow.uturn.left"
        } else if instruction.lowercased().contains("continue") || instruction.lowercased().contains("head") {
            // Continue straight
            imageName = "arrow.up"
        } else if instruction.lowercased().contains("destination") || instruction.lowercased().contains("arrive") {
            // Arrived
            imageName = "checkmark.circle.fill"
        } else {
            // Default
            imageName = "arrow.up"
        }
        
        return Image(systemName: imageName)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.white)
    }
}

// Preview provider
#if DEBUG
struct NavigationBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            NavigationBanner(instruction: "Turn right onto Main St", distance: "200m", isLastStep: false)
            
            NavigationBanner(instruction: "Continue on Highway 1", distance: "2.4 km", isLastStep: false)
            
            NavigationBanner(instruction: "Turn left at the traffic light", distance: "500m", isLastStep: false)
            
            NavigationBanner(instruction: "You have arrived at your destination", distance: "0m", isLastStep: true)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
