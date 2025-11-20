//
//  LocationCard.swift
//  OPS
//
//  Reusable location/address display card
//

import SwiftUI
import MapKit

struct LocationCard: View {
    let address: String
    let latitude: Double?
    let longitude: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: OPSStyle.Icons.address)
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("LOCATION")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Navigate button if coordinates available
                if latitude != nil && longitude != nil {
                    Button(action: openInMaps) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.system(size: 16))
                            Text("Navigate")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.bottom, 8)
            
            // Address
            Text(address)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func openInMaps() {
        guard let lat = latitude, let lon = longitude else { return }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = address
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}