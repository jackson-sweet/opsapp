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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with ETA and distance
            HStack {
                VStack(alignment: .leading) {
                    Text("ESTIMATED ARRIVAL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(estimatedArrival ?? "Calculating...")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("DISTANCE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(distance ?? "Calculating...")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackground)
            
            // Only show directions when expanded
            if showFullDirections {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        ForEach(directions.indices, id: \.self) { index in
                            HStack(alignment: .top) {
                                Text("\(index + 1).")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                                    .frame(width: 25, alignment: .leading)
                                
                                Text(directions[index])
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(.horizontal)
                            
                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                        }
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: 200)
                .background(OPSStyle.Colors.background.opacity(0.9))
            }
            
            // Toggle button
            Button(action: {
                withAnimation {
                    showFullDirections.toggle()
                }
            }) {
                HStack {
                    Text(showFullDirections ? "Hide Directions" : "Show Directions")
                        .font(OPSStyle.Typography.captionBold)
                    
                    Image(systemName: showFullDirections ? "chevron.up" : "chevron.down")
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .background(OPSStyle.Colors.cardBackground)
            }
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(radius: 2)
    }
}