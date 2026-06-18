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

    /// Optional callback invoked when the mini map successfully resolves
    /// the address string to coordinates. Callers (ProjectDetailsView,
    /// ProjectSummaryCard) forward these to DataController so the project
    /// model gets hydrated and subsequent renders short-circuit the
    /// geocode. Bug bec71df9.
    var onResolvedCoordinate: ((CLLocationCoordinate2D) -> Void)? = nil

    /// Locally-resolved coordinate from geocoding the address string when
    /// the parent didn't supply one. Prefers the parent's coordinate when
    /// both are present to avoid UI flicker mid-load.
    @State private var resolvedCoordinate: CLLocationCoordinate2D? = nil
    @State private var isResolving: Bool = false

    /// The coordinate to actually render — parent-supplied takes priority,
    /// fallback to the locally-resolved value.
    private var effectiveCoordinate: CLLocationCoordinate2D? {
        coordinate ?? resolvedCoordinate
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let coord = effectiveCoordinate {
                    mapContent(coordinate: coord)
                } else if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // We have an address string but no coordinate (yet).
                    // Show a placeholder that's distinct from the "no
                    // address at all" state — indicates loading / pending
                    // resolution. Bug bec71df9.
                    OPSStyle.Colors.background
                        .overlay(
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                if isResolving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "mappin.slash.circle")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Text(isResolving ? "LOADING MAP" : "TAP TO SET LOCATION")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)

                                if !isResolving {
                                    Text(address)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                        )
                } else {
                    // Fallback for no coordinates AND no address at all.
                    OPSStyle.Colors.background
                        .overlay(
                            VStack(spacing: OPSStyle.Layout.spacing2) {
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
                            .padding(OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Circle())
                            .padding(OPSStyle.Layout.spacing2_5)
                    }
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .onAppear { kickoffGeocodeIfNeeded() }
        .onChange(of: coordinate?.latitude) { _, _ in
            // If the parent coordinate arrives after our render-time
            // geocode kicked off, stop the local attempt.
            if coordinate != nil { resolvedCoordinate = nil; isResolving = false }
        }
        .onChange(of: address) { _, _ in
            // Address changed — re-attempt geocode with the new value.
            resolvedCoordinate = nil
            kickoffGeocodeIfNeeded()
        }
    }

    /// Bug bec71df9 — forward-geocode the address string on first render
    /// when coordinates are missing. Some legacy projects have an address
    /// but no lat/lng (Bubble import failed, or sync race). Without this,
    /// the mini map shows an empty-state card even though we could trivially
    /// resolve the coords on device. Cache the result back via
    /// onResolvedCoordinate so the parent can persist and skip future
    /// lookups.
    private func kickoffGeocodeIfNeeded() {
        guard coordinate == nil,
              resolvedCoordinate == nil,
              !isResolving else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isResolving = true
        Task { @MainActor in
            defer { isResolving = false }
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(trimmed)
                guard let location = placemarks.first?.location else { return }
                let coord = location.coordinate

                // Validate finite coords before committing.
                guard coord.latitude.isFinite,
                      coord.longitude.isFinite,
                      abs(coord.latitude) <= 90,
                      abs(coord.longitude) <= 180,
                      !(abs(coord.latitude) < 0.0001 && abs(coord.longitude) < 0.0001) else {
                    return
                }

                // Skip if the address changed mid-flight.
                guard address.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }

                resolvedCoordinate = coord
                onResolvedCoordinate?(coord)
            } catch {
                // Silent — fallback empty state already rendered.
            }
        }
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
        // Use the screen bounds at init so Metal layer's contentsScale resolves
        // to the device pixel ratio. A degenerate 64x64 frame triggers Mapbox's
        // "Invalid size" fallback and a nan content-scale on the MetalView. Bug 003434d9.
        let mapView = MapView(frame: UIScreen.main.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
