//
//  LeadDetailsAddressPresentation.swift
//  OPS
//
//  Pure presentation policy for the Lead Details ADDRESS row. Keeping the
//  blank/routable decision outside SwiftUI makes the row deterministic and
//  prevents whitespace-only values from exposing a dead directions action.
//

import Foundation

enum LeadDetailsAddressPresentation: Equatable {
    case empty
    case routable(String)

    static func resolve(_ rawAddress: String?) -> Self {
        let address = rawAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return address.isEmpty ? .empty : .routable(address)
    }

    var displayValue: String {
        switch self {
        case .empty:
            return "—"
        case .routable(let address):
            return address
        }
    }

    static func directionsURL(
        address: String?,
        latitude: Double?,
        longitude: Double?
    ) -> URL? {
        let trimmedAddress = address?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let destination: String
        if !trimmedAddress.isEmpty {
            destination = trimmedAddress
        } else if let latitude, let longitude {
            destination = "\(latitude),\(longitude)"
        } else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        return components.url
    }
}
