//
//  MapboxConfig.swift
//  OPS
//
//  Mapbox SDK configuration — access token setup.
//  Style URIs are managed by OPSMapStyle.swift.
//

import Foundation
import MapboxMaps

enum MapboxConfig {
    /// Mapbox public access token.
    static let publicToken = "MAPBOX_TOKEN_PLACEHOLDER"

    /// Call once at app launch (e.g. in the App init) to set the global access token.
    static func configure() {
        MapboxOptions.accessToken = publicToken
    }
}
