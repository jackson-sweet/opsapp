//
//  AppStoreVersionService.swift
//  OPS
//
//  Queries Apple's public iTunes Lookup API for the live App Store version of
//  this app, so the Update Gate can nudge users the moment a newer build is
//  available — without an admin publishing anything. Free, public endpoint.
//  Fails open (nil) on any error: no result simply means "no auto-nudge".
//

import Foundation

struct AppStoreVersion {
    let version: String
    let appStoreURL: String?
}

final class AppStoreVersionService {

    private struct LookupResponse: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let version: String?
            let trackViewUrl: String?
            let trackId: Int?
        }
    }

    /// Returns the current App Store version + a link to the listing, or nil on
    /// any failure (offline, throttled, app not found, malformed response).
    func fetchLatest(bundleIdentifier: String? = Bundle.main.bundleIdentifier) async -> AppStoreVersion? {
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else { return nil }

        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        var items = [URLQueryItem(name: "bundleId", value: bundleId)]
        if let region = Locale.current.region?.identifier {
            items.append(URLQueryItem(name: "country", value: region))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let first = decoded.results.first, let version = first.version, !version.isEmpty else {
                return nil
            }
            let storeURL = first.trackViewUrl
                ?? first.trackId.map { "https://apps.apple.com/app/id\($0)" }
            return AppStoreVersion(version: version, appStoreURL: storeURL)
        } catch {
            print("[APP_MESSAGE] App Store lookup failed (fail-open): \(error.localizedDescription)")
            return nil
        }
    }
}
