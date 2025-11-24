//
//  LocationCard.swift
//  OPS
//
//  Reusable location/address display card - built on SectionCard base
//

import SwiftUI
import MapKit

struct LocationCard: View {
    let address: String
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        SectionCard(
            icon: OPSStyle.Icons.address,
            title: "Location",
            actionIcon: latitude != nil && longitude != nil ? "arrow.triangle.turn.up.right.circle.fill" : nil,
            actionLabel: latitude != nil && longitude != nil ? "Navigate" : nil,
            onAction: latitude != nil && longitude != nil ? openInMaps : nil
        ) {
            Text(address)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
