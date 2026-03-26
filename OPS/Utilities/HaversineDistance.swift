//
//  HaversineDistance.swift
//  OPS
//
//  Haversine formula for great-circle distance between two lat/lng points.
//  Pure math — no CoreLocation runtime dependency.
//

import Foundation

struct HaversineDistance {

    private static let earthRadiusKm: Double = 6371.0

    /// Calculate distance in kilometers between two coordinates.
    static func km(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    /// Check if two coordinates are within a given radius (km).
    static func isWithinRadius(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double,
        radiusKm: Double
    ) -> Bool {
        return km(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2) <= radiusKm
    }
}
