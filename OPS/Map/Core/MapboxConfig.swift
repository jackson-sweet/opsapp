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
    /// Mapbox public access token — loaded from Info.plist key "MBXAccessToken".
    static let publicToken: String = {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
              !token.isEmpty else {
            fatalError("Missing MBXAccessToken in Info.plist — add your Mapbox token there.")
        }
        return token
    }()

    /// Call once at app launch (e.g. in the App init) to set the global access token.
    static func configure() {
        MapboxOptions.accessToken = publicToken
    }
}
