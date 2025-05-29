//
//  MiniMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI
import MapKit

// Anchor preference key for markers
struct AnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue()) { (current, _) in current }
    }
}

struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let address: String
    var onTap: () -> Void
    
    // Map settings from user preferences
    @AppStorage("map3DBuildings") private var map3DBuildings = false
    @AppStorage("mapDefaultType") private var mapDefaultType = "standard"
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let coordinate = coordinate {
                    // Map with location using user's preferred settings
                    Map(initialPosition: .region(region(for: coordinate))) {
                        Annotation("Project Location", coordinate: coordinate) {
                            // Use SF Symbols marker - clean version without background, with white color
                            Image(systemName: "pin")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(Color.white)
                                .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 2)
                        }
                    }
                    .mapStyle(mapStyle())
                    .mapControls {
                        // Compass removed per user request
                    }
                    .allowsHitTesting(false) // Map interactions will be handled by the parent button
                    .disabled(true)
                } else {
                    // Fallback for no coordinates
                    OPSStyle.Colors.cardBackgroundDark
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "map.slash")
                                    .font(.system(size: 32))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text("NO ADDRESS")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Text("No location available")
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
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008) // Slightly closer zoom for better focus
        )
    }
    
    // Helper to apply user's map style preferences
    @MainActor private func mapStyle() -> MapStyle {
        switch mapDefaultType {
        case "satellite":
            return .imagery(elevation: map3DBuildings ? .realistic : .flat)
        case "hybrid":
            return .hybrid(elevation: map3DBuildings ? .realistic : .flat)
        default: // "standard"
            return .standard(elevation: map3DBuildings ? .realistic : .flat)
        }
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
