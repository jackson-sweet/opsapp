//
//  RouteDirectionsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct RouteDirectionsView: View {
    let directions: [String]
    let estimatedArrival: String?
    let distance: String?
    @State private var showFullDirections = false
    var onDismiss: (() -> Void)? // Added dismissal handler
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with ETA and distance - styled to match reference design
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
            .background(Color.black.opacity(0.7))
            
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
                            }
                            .padding(.horizontal)
                            
                            Divider()
                                .background(Color.white.opacity(0.3))
                        }
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: 200)
                .background(Color.black.opacity(0.8))
            }
            
            // Toggle button with improved styling
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
                .background(Color.black.opacity(0.6))
            }
            
            // Single clean action button row
            VStack(spacing: 0) {
                // First button: Hide directions
                Button(action: {
                    // Dismiss this view
                    if let dismiss = onDismiss {
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.up")
                        Text("Hide Directions")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                }
                
                // Divider
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Second button: Stop navigation
                Button(action: {
                    // Post notification to stop routing
                    NotificationCenter.default.post(
                        name: Notification.Name("StopRouting"),
                        object: nil
                    )
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Stop Navigation")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .foregroundColor(.white)
                }
            }
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(radius: 4, x: 0, y: 2)
    }
}