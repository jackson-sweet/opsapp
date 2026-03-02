//
//  MapStyleApplicator.swift
//  OPS
//
//  Applies OPS color overrides to a loaded Mapbox base style via
//  runtime styling.  Enumerates all layers in the current style
//  and rewrites colors by matching layer IDs to categories
//  (water, road, building, label, etc.).
//
//  Called once after each style load — including initial load and
//  any subsequent style switch triggered by the user.
//

import MapboxMaps
import UIKit

enum MapStyleApplicator {

    // MARK: - Public

    /// Apply an OPS map style profile to the given MapView.
    /// Must be called AFTER the base Mapbox style has fully loaded.
    static func apply(_ style: OPSMapStyle, to mapView: MapView, show3DBuildings: Bool = true) {
        let colors = style.colors

        let allLayers: [LayerInfo]
        do {
            allLayers = try mapView.mapboxMap.allLayerIdentifiers
        } catch {
            print("[MapStyleApplicator] Could not enumerate layers: \(error)")
            return
        }

        for info in allLayers {
            apply(to: info, colors: colors, mapView: mapView, show3DBuildings: show3DBuildings)
        }
    }

    /// Toggle 3D building extrusion visibility without re-applying the full style.
    static func set3DBuildings(_ enabled: Bool, mapView: MapView) {
        let allLayers: [LayerInfo]
        do {
            allLayers = try mapView.mapboxMap.allLayerIdentifiers
        } catch { return }

        for info in allLayers where info.type == .fillExtrusion {
            let id = info.id.lowercased()
            guard id.contains("building") || id.contains("extrusion") else { continue }
            try? mapView.mapboxMap.updateLayer(withId: info.id, type: FillExtrusionLayer.self) { layer in
                layer.visibility = .constant(enabled ? .visible : .none)
            }
        }
    }

    // MARK: - Per-Layer Dispatch

    private static func apply(
        to info: LayerInfo,
        colors: MapStyleColors,
        mapView: MapView,
        show3DBuildings: Bool
    ) {
        let id = info.id.lowercased()

        switch info.type {
        case .background:
            applyBackground(id: info.id, colors: colors, mapView: mapView)

        case .fill:
            applyFill(id: info.id, lowerId: id, colors: colors, mapView: mapView)

        case .line:
            applyLine(id: info.id, lowerId: id, colors: colors, mapView: mapView)

        case .symbol:
            applySymbol(id: info.id, lowerId: id, colors: colors, mapView: mapView)

        case .fillExtrusion:
            if id.contains("building") || id.contains("extrusion") {
                try? mapView.mapboxMap.updateLayer(withId: info.id, type: FillExtrusionLayer.self) { layer in
                    layer.fillExtrusionColor = .constant(StyleColor(colors.building))
                    layer.visibility = .constant(show3DBuildings ? .visible : .none)
                }
            }

        default:
            break
        }
    }

    // MARK: - Background

    private static func applyBackground(
        id: String,
        colors: MapStyleColors,
        mapView: MapView
    ) {
        try? mapView.mapboxMap.updateLayer(withId: id, type: BackgroundLayer.self) { layer in
            layer.backgroundColor = .constant(StyleColor(colors.land))
        }
    }

    // MARK: - Fill Layers (water, buildings, parks, land)

    private static func applyFill(
        id: String,
        lowerId: String,
        colors: MapStyleColors,
        mapView: MapView
    ) {
        if lowerId.contains("water") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: FillLayer.self) { layer in
                layer.fillColor = .constant(StyleColor(colors.water))
            }
        } else if lowerId.contains("building") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: FillLayer.self) { layer in
                layer.fillColor = .constant(StyleColor(colors.building))
            }
        } else if lowerId.contains("park") || lowerId.contains("green") || lowerId.contains("vegetation") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: FillLayer.self) { layer in
                layer.fillColor = .constant(StyleColor(colors.park))
            }
        } else if lowerId.contains("land") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: FillLayer.self) { layer in
                layer.fillColor = .constant(StyleColor(colors.land))
            }
        }
    }

    // MARK: - Line Layers (roads, waterways, boundaries)

    private static func applyLine(
        id: String,
        lowerId: String,
        colors: MapStyleColors,
        mapView: MapView
    ) {
        // Road casings (outlines drawn beneath road fill)
        if lowerId.contains("case") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.roadCase))
            }
            return
        }

        // Waterways (rivers, streams)
        if lowerId.contains("waterway") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.waterway))
            }
            return
        }

        // Administrative boundaries
        if lowerId.contains("admin") || lowerId.contains("boundary") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.boundary))
            }
            return
        }

        // Roads (and bridges / tunnels which follow the same naming)
        let isRoad = lowerId.contains("road") || lowerId.contains("bridge")
            || lowerId.contains("tunnel") || lowerId.contains("street")
        guard isRoad else { return }

        if lowerId.contains("motorway") || lowerId.contains("trunk") || lowerId.contains("primary") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.roadPrimary))
            }
        } else if lowerId.contains("secondary") || lowerId.contains("tertiary") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.roadSecondary))
            }
        } else {
            try? mapView.mapboxMap.updateLayer(withId: id, type: LineLayer.self) { layer in
                layer.lineColor = .constant(StyleColor(colors.roadMinor))
            }
        }
    }

    // MARK: - Symbol Layers (labels, POIs)

    private static func applySymbol(
        id: String,
        lowerId: String,
        colors: MapStyleColors,
        mapView: MapView
    ) {
        // Hide POIs when the profile requests a clean field map
        if colors.hidePOIs && (lowerId.contains("poi") || lowerId.contains("transit")) {
            try? mapView.mapboxMap.updateLayer(withId: id, type: SymbolLayer.self) { layer in
                layer.visibility = .constant(.none)
            }
            return
        }

        // Road / street labels
        if lowerId.contains("road") || lowerId.contains("street") || lowerId.contains("path") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: SymbolLayer.self) { layer in
                layer.textColor = .constant(StyleColor(colors.labelSecondary))
            }
            return
        }

        // Place labels (cities, neighborhoods, etc.)
        if lowerId.contains("label") || lowerId.contains("place") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: SymbolLayer.self) { layer in
                layer.textColor = .constant(StyleColor(colors.labelPrimary))
            }
            return
        }

        // POI labels (when not hidden)
        if lowerId.contains("poi") {
            try? mapView.mapboxMap.updateLayer(withId: id, type: SymbolLayer.self) { layer in
                layer.textColor = .constant(StyleColor(colors.poi))
            }
        }
    }
}
