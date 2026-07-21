//
//  LeadMapHeader.swift
//  OPS
//
//  Map hero behind the top of LeadDetailView — the ProjectMapHeader
//  treatment adapted to a lead (address + coordinates instead of a Project).
//  Map background only: no nav bar, no scroll gradient. The nav bar lives in
//  LeadDetailView's top layer for reliable tap targets; the 90pt gradient
//  scrolls with the content. Renders ONLY when the lead has coordinates —
//  the no-address / no-coordinate case is handled by the caller (plain
//  canvas, zero layout shift).
//

import SwiftUI
import CoreLocation

struct LeadMapHeader: View {
    let latitude: Double
    let longitude: Double
    let pinLabel: String
    /// Operator's current location — "you are here" dot when inside the frame.
    var userCoordinate: CLLocationCoordinate2D?
    let onMapTap: () -> Void

    static let mapHeight: CGFloat = 320

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ProjectLocationSnapshotView(
                coordinate: coordinate,
                projectName: pinLabel,
                // Leads are pre-project by definition — the RFQ tone is the
                // honest pin state for a job that doesn't exist yet.
                status: .rfq,
                taskColorHexes: [],
                userCoordinate: userCoordinate,
                zoomLevel: 13.0
            )
            .frame(height: Self.mapHeight)
            .contentShape(Rectangle())
            .onTapGesture { onMapTap() }

            // Bottom gradient — fully opaque well before the frame's bottom
            // edge so the snapshot's baked-in Mapbox watermark/attribution
            // band can never read through (the old 40pt half-strength fade
            // let the attribution text bleed at ~60% cover).
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: OPSStyle.Colors.background.opacity(0.85), location: 0.45),
                    .init(color: OPSStyle.Colors.background, location: 0.7),
                    .init(color: OPSStyle.Colors.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .allowsHitTesting(false)
        }
        .frame(height: Self.mapHeight)
    }
}

/// Owns the LocationManager observation so location ticks re-render ONLY this
/// header subtree — the ProjectMapHeaderSection lesson applied from day one.
struct LeadMapHeaderSection: View {
    let latitude: Double
    let longitude: Double
    let pinLabel: String
    let onMapTap: () -> Void

    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        LeadMapHeader(
            latitude: latitude,
            longitude: longitude,
            pinLabel: pinLabel,
            userCoordinate: locationManager.userLocation,
            onMapTap: onMapTap
        )
    }
}
