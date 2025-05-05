//
//  MiniMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI
import MapKit

struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let address: String
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let coordinate = coordinate {
                    // Map with location
                    Map(initialPosition: .region(region(for: coordinate))) {
                        Annotation("Project Location", coordinate: coordinate) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "mappin")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .allowsHitTesting(false) // Map interactions will be handled by the parent button
                    .disabled(true)
                } else {
                    // Fallback for no coordinates
                    OPSStyle.Colors.cardBackgroundDark
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "map")
                                    .font(.system(size: 32))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(address)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Text("Tap to open in Maps")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                            }
                        )
                }
                
                // Overlay for tap hint
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 1, y: 1)
                            .padding(12)
                    }
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    
    // Helper to create region
    private func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}

// Helper function to open Maps app
func openInMaps(coordinate: CLLocationCoordinate2D?, address: String) {
    if let coordinate = coordinate {
        // If we have coordinates, create a Maps URL
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Project Location"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    } else if !address.isEmpty {
        // Otherwise try to use the address string
        let addressString = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?address=\(addressString)") {
            UIApplication.shared.open(url)
        }
    }
}