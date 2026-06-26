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
    private static let hostedXCTestFallbackToken = "pk.ops-hosted-xctest"

    /// Mapbox public access token — loaded from Info.plist key "MBXAccessToken".
    static let publicToken: String = {
        if let token = resolvedPublicToken(
            infoPlistToken: Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
            environment: ProcessInfo.processInfo.environment,
            isRunningUnderXCTest: isRunningUnderXCTest
        ) {
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

    static func resolvedPublicToken(
        infoPlistToken: String?,
        environment: [String: String],
        isRunningUnderXCTest: Bool
    ) -> String? {
        if let token = normalizedToken(infoPlistToken) {
            return token
        }

        guard isRunningUnderXCTest else {
            return nil
        }

        if let token = normalizedToken(environment[hostedXCTestTokenEnvironmentKey]) {
            return token
        }

        return hostedXCTestFallbackToken
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
