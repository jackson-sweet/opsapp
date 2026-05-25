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
    private static let hostedXCTestTokenEnvironmentKey = "OPS_HOSTED_XCTEST_MBX_ACCESS_TOKEN"

    /// Mapbox public access token — loaded from Info.plist key "MBXAccessToken".
    static let publicToken: String = {
        if let token = normalizedToken(Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String) {
            return token
        }

        if isRunningUnderXCTest,
           let token = normalizedToken(ProcessInfo.processInfo.environment[hostedXCTestTokenEnvironmentKey]) {
            return token
        }

        fatalError("Missing MBXAccessToken in Info.plist — add your Mapbox token there.")
    }()

    /// Call once at app launch (e.g. in the App init) to set the global access token.
    static func configure() {
        MapboxOptions.accessToken = publicToken
    }

    private static var isRunningUnderXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCInjectBundleInto"] != nil
    }

    private static func normalizedToken(_ rawToken: String?) -> String? {
        guard let token = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              !token.hasPrefix("$(") else {
            return nil
        }
        return token
    }
}
