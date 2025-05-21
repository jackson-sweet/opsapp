//
//  RouteDirectionsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

// Extension to add rounded corners to specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Custom shape for specific corner rounding
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct RouteDirectionsView: View {
    let directions: [String]
    let estimatedArrival: String?
    let distance: String?
    @State private var showFullDirections = false
    var onDismiss: (() -> Void)? // Added dismissal handler
    
    var body: some View {
        // Simplify the layout to remove blank card issue
        VStack(spacing: 0) {
            // Header with ETA and distance
            HStack {
                VStack(alignment: .leading) {
                    Text("ESTIMATED ARRIVAL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(estimatedArrival ?? "Calculating...")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("DISTANCE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(distance ?? "Calculating...")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius, corners: [.topLeft, .topRight])
            
            // Always show next direction first
            if let firstDirection = directions.first {
                HStack {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40)
                    
                    Text(firstDirection)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding()
                .background(OPSStyle.Colors.primaryAccent)
            }
            
            // Only show full list of directions when expanded
            if showFullDirections {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        ForEach(directions.indices.dropFirst(), id: \.self) { index in
                            HStack(alignment: .top) {
                                Text("\(index + 1).")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(.white)
                                    .frame(width: 25, alignment: .leading)
                                
                                Text(directions[index])
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
                            }
                            .padding(.horizontal)
                            
                            if index < directions.count - 2 {
                                Divider()
                                    .background(Color.white.opacity(0.2))
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: 200)
                .background(OPSStyle.Colors.cardBackground)
            }
            
            // Toggle button
            Button(action: {
                withAnimation {
                    showFullDirections.toggle()
                }
            }) {
                HStack {
                    Text(showFullDirections ? "Hide Directions" : "Show All Directions")
                        .font(OPSStyle.Typography.captionBold)
                    
                    Image(systemName: showFullDirections ? "chevron.up" : "chevron.down")
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            }
            
            // Action buttons
            VStack(spacing: 1) { // Small spacing for a divider effect
                // Hide directions button
                Button(action: {
                    if let dismiss = onDismiss {
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.up")
                        Text("Hide Directions")
                    }
                    .font(OPSStyle.Typography.cardSubtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                }
                
                // Stop navigation button
                Button(action: {
                    NotificationCenter.default.post(
                        name: Notification.Name("StopRouting"),
                        object: nil
                    )
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Stop Navigation")
                    }
                    .font(OPSStyle.Typography.cardSubtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(OPSStyle.Colors.errorStatus))
                    .foregroundColor(.white)
                }
            }
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.95))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
}
