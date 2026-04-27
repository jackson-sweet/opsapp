//
//  OPSMapView.swift
//  OPS
//
//  UIViewRepresentable wrapper around Mapbox MapView.
//  Dark #0A0A0A background while tiles load, user location puck,
//  all standard gestures enabled.
//

import SwiftUI
import MapboxMaps

struct OPSMapView: UIViewRepresentable {
    @ObservedObject var coordinator: OPSMapCoordinator

    // MARK: - Make

    func makeUIView(context: Context) -> MapView {
        let style = coordinator.mapStyle
        let options = MapInitOptions(styleURI: style.baseStyleURI)
        // Use the screen bounds at init so Metal layer's contentsScale resolves
        // to the device pixel ratio. A degenerate 64x64 frame triggers Mapbox's
        // "Invalid size" fallback and a nan content-scale on the MetalView. Bug 003434d9.
        let mapView = MapView(frame: UIScreen.main.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Match the style's land color while tiles stream in
        mapView.backgroundColor = style.backgroundColor

        // --- Hide scale bar ornament ---
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // --- User location puck ---
        mapView.location.options.puckType = .puck2D(
            Puck2DConfiguration(scale: .constant(0.8))
        )
        mapView.location.options.puckBearing = .course
        mapView.location.options.puckBearingEnabled = true

        // --- Observe camera changes (user gestures like tilt/pan) ---
        context.coordinator.cameraChangedCancellable = mapView.mapboxMap.onCameraChanged.observe { [weak opsCoord = coordinator] event in
            guard let opsCoord else { return }
            let state = event.cameraState
            // Track user-initiated pitch changes for 3D building auto-enable
            Task { @MainActor in
                opsCoord.cameraPitch = state.pitch
            }
        }

        // Hand the raw MapView to the coordinator so it can
        // create annotation managers, drive the camera, etc.
        coordinator.setupMapView(mapView)

        return mapView
    }

    // MARK: - Update

    func updateUIView(_ mapView: MapView, context: Context) {
        // Camera position, annotations, and route lines are all
        // driven imperatively by the coordinator — nothing to
        // reconcile here on the SwiftUI side.
    }

    // MARK: - Coordinator (UIKit bridge)

    func makeCoordinator() -> MapViewCoordinator {
        MapViewCoordinator()
    }

    /// Holds Mapbox cancellables that need to live as long as the UIView.
    class MapViewCoordinator {
        var cameraChangedCancellable: (any Cancelable)?

        deinit {
            cameraChangedCancellable?.cancel()
        }
    }
}
