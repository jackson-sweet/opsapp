//
//  ProjectMapHeader.swift
//  OPS
//
//  Map background only — no nav bar, no gradient.
//  Nav bar is in ProjectDetailsView (Layer 3) for reliable tap targets.
//  Gradient is in the scroll content layer so it scrolls with the title.
//

import SwiftUI
import MapKit

struct ProjectMapHeader: View {
    let project: Project
    let taskColorHexes: [String]
    let pinLabel: String
    let nearbyProjects: [NearbyProjectPin]
    let onMapTap: () -> Void

    static let mapHeight: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
            // Gradient at bottom — covers Mapbox watermark and softens map edge
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: OPSStyle.Colors.background.opacity(0.4), location: 0.3),
                    .init(color: OPSStyle.Colors.background.opacity(0.8), location: 0.7),
                    .init(color: OPSStyle.Colors.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.mapHeight * 0.4)
            .allowsHitTesting(false)
        }
        .frame(height: Self.mapHeight)
    }

    // MARK: - Map

    private var mapView: some View {
        Group {
            if let coordinate = project.coordinate {
                ProjectLocationMapView(
                    coordinate: coordinate,
                    projectName: pinLabel,
                    status: project.status,
                    taskColorHexes: taskColorHexes,
                    isInteractive: false,
                    zoomLevel: 13.0,
                    nearbyProjects: nearbyProjects,
                    showUserLocation: true
                )
                .frame(height: Self.mapHeight)
                .contentShape(Rectangle())
                .onTapGesture { onMapTap() }
            } else {
                Rectangle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(height: Self.mapHeight)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("No location set")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    )
            }
        }
    }
}

// MARK: - Title Overlay (used in scrollable content)

struct ProjectTitleOverlay: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title.uppercased())
                .font(.custom("Mohave-SemiBold", size: 28))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)

            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
