//
//  ProjectSummaryCard.swift
//  OPS
//
//  Compact summary card with map and key project info for ProjectDetailsView
//

import SwiftUI
import MapKit
import CoreLocation

/// Compact project summary card with tappable map and key info
///
/// Features:
/// - Compact map view (~80pt) with location pin
/// - Tap anywhere on map to open directions in Maps app
/// - Info row below: address, distance in minutes
struct ProjectSummaryCard: View {
    let project: Project
    @EnvironmentObject private var locationManager: LocationManager

    // MARK: - State
    @State private var estimatedTravelTime: String? = nil

    // MARK: - Computed Properties
    private var shortAddress: String {
        guard let address = project.address, !address.isEmpty else {
            return "No address"
        }
        // Return first line of address (street address)
        return address.components(separatedBy: ",").first ?? address
    }

    /// Extract street number and name for Maps title
    private var streetAddress: String {
        guard let address = project.address, !address.isEmpty else {
            return "Destination"
        }
        // First part before comma is typically street number + street name
        let firstPart = address.components(separatedBy: ",").first ?? address
        return firstPart.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Map Section
            compactMapView
                .frame(height: 80)

            // MARK: - Info Row
            infoRow
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .onAppear {
            calculateTravelTime()
        }
    }

    // MARK: - Compact Map View
    private var compactMapView: some View {
        ZStack {
            if let coordinate = project.coordinate {
                // Map with location
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation("", coordinate: coordinate) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 2)
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .allowsHitTesting(false)
            } else {
                // No location fallback
                OPSStyle.Colors.cardBackground
                    .overlay(
                        HStack(spacing: 8) {
                            Image(systemName: "map.slash")
                                .font(.system(size: 16))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("NO LOCATION")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openInMapsWithTitle(
                coordinate: project.coordinate,
                address: project.address ?? "",
                title: streetAddress
            )
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OPSStyle.Layout.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: OPSStyle.Layout.cornerRadius
            )
        )
    }

    // MARK: - Info Row
    private var infoRow: some View {
        HStack(spacing: 12) {
            // Address with map pin icon
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 11))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(shortAddress.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Distance in minutes
            HStack(spacing: 4) {
                Image(systemName: "car.fill")
                    .font(.system(size: 11))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if let travelTime = estimatedTravelTime {
                    Text(travelTime.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else if project.coordinate != nil {
                    Text("CALCULATING...")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text("—")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Travel Time Calculation
    private func calculateTravelTime() {
        guard let destinationCoordinate = project.coordinate else {
            estimatedTravelTime = nil
            return
        }

        // Get current location
        guard let currentLocation = locationManager.userLocation else {
            estimatedTravelTime = "—"
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculateETA { response, error in
            DispatchQueue.main.async {
                if let eta = response?.expectedTravelTime {
                    let minutes = Int(eta / 60)
                    if minutes < 60 {
                        self.estimatedTravelTime = "\(minutes) MIN"
                    } else {
                        let hours = minutes / 60
                        let remainingMinutes = minutes % 60
                        if remainingMinutes == 0 {
                            self.estimatedTravelTime = "\(hours) HR"
                        } else {
                            self.estimatedTravelTime = "\(hours) HR \(remainingMinutes) MIN"
                        }
                    }
                } else {
                    self.estimatedTravelTime = "—"
                }
            }
        }
    }
}

// MARK: - Helper Function

/// Opens Maps app with directions using a custom title
func openInMapsWithTitle(coordinate: CLLocationCoordinate2D?, address: String, title: String) {
    if let coordinate = coordinate {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = title
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    } else if !address.isEmpty {
        let addressString = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?address=\(addressString)") {
            UIApplication.shared.open(url)
        }
    }
}
