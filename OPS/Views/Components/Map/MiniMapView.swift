//
//  MiniMapView.swift
//  OPS
//
//  Mini map component for displaying a single project location.
//  When Mapbox SDK is available, uses the same dark OPS style and
//  segmented-ring pin as the main map. Falls back to Apple MapKit otherwise.
//  Non-interactive — tapping opens Apple Maps for directions.
//

import SwiftUI
import MapKit

struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let address: String
    var onTap: () -> Void

    /// Optional project context for rendering the segmented-ring pin.
    /// When nil, a simple location dot is shown instead.
    var projectName: String? = nil
    var status: Status? = nil
    var taskColorHexes: [String] = []

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let coordinate = coordinate {
                    mapContent(coordinate: coordinate)
                } else {
                    // Fallback for no coordinates
                    OPSStyle.Colors.cardBackgroundDark
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "map.slash")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
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
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(8)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Circle())
                            .padding(12)
                    }
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - Map Content

    @ViewBuilder
    private func mapContent(coordinate: CLLocationCoordinate2D) -> some View {
        #if canImport(MapboxMaps)
        // Mapbox: same dark OPS style + segmented-ring pin as main map
        MiniMapboxView(
            coordinate: coordinate,
            projectName: projectName,
            status: status,
            taskColorHexes: taskColorHexes
        )
        #else
        // Apple MapKit fallback (used until Mapbox SDK is added via SPM)
        Map(initialPosition: .region(region(for: coordinate))) {
            Annotation("", coordinate: coordinate) {
                mapPin
            }
        }
        .mapStyle(.standard(
            elevation: .flat,
            emphasis: .muted,
            pointsOfInterest: .excludingAll
        ))
        .mapControls { }
        .allowsHitTesting(false)
        .disabled(true)
        #endif
    }

    /// Simple pin view for Apple MapKit fallback.
    private var mapPin: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 16, height: 16)

            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
    }

    private func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }
}

// MARK: - Mapbox Implementation (compiled only when SDK is available)

#if canImport(MapboxMaps)
import MapboxMaps

private struct MiniMapboxView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let projectName: String?
    let status: Status?
    let taskColorHexes: [String]

    @AppStorage("mapStyle") private var mapStyleRaw = "dark"

    private var opsMapStyle: OPSMapStyle {
        OPSMapStyle(rawValue: mapStyleRaw) ?? .dark
    }

    func makeUIView(context: Context) -> MapView {
        let style = opsMapStyle
        let camera = CameraOptions(
            center: coordinate,
            zoom: 13.5,
            pitch: 0
        )
        let options = MapInitOptions(
            cameraOptions: camera,
            styleURI: style.baseStyleURI
        )
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), mapInitOptions: options)
        mapView.backgroundColor = style.backgroundColor

        // Disable all interactions — parent Button handles tap
        mapView.gestures.options.panEnabled = false
        mapView.gestures.options.pinchEnabled = false
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.doubleTapToZoomInEnabled = false
        mapView.gestures.options.doubleTouchToZoomOutEnabled = false
        mapView.gestures.options.quickZoomEnabled = false

        // Hide ornaments
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // Add annotation
        context.coordinator.addAnnotation(
            to: mapView,
            coordinate: coordinate,
            projectName: projectName,
            status: status,
            taskColorHexes: taskColorHexes
        )

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var annotationManager: PointAnnotationManager?

        func addAnnotation(
            to mapView: MapView,
            coordinate: CLLocationCoordinate2D,
            projectName: String?,
            status: Status?,
            taskColorHexes: [String]
        ) {
            let manager = mapView.annotations.makePointAnnotationManager()

            let pinImage: UIImage
            if let name = projectName, let status = status {
                pinImage = ProjectAnnotationRenderer.renderProject(
                    name: name,
                    status: status,
                    taskColorHexes: taskColorHexes,
                    isSelected: true
                )
            } else {
                pinImage = Self.renderLocationDot()
            }

            var annotation = PointAnnotation(coordinate: coordinate)
            annotation.image = .init(image: pinImage, name: "mini-map-pin")
            annotation.iconAnchor = .bottom

            manager.annotations = [annotation]
            self.annotationManager = manager
        }

        private static func renderLocationDot() -> UIImage {
            let size = CGSize(width: 16, height: 16)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let cgContext = context.cgContext
                let center = CGPoint(x: 8, y: 8)
                cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                cgContext.setLineWidth(2)
                cgContext.addArc(center: center, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                cgContext.strokePath()
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.addArc(center: center, radius: 3, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                cgContext.fillPath()
            }
        }
    }
}
#endif

// MARK: - Helper

func openInMaps(coordinate: CLLocationCoordinate2D?, address: String) {
    if let coordinate = coordinate {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Project Location"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    } else if !address.isEmpty {
        let addressString = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?address=\(addressString)") {
            UIApplication.shared.open(url)
        }
    }
}
