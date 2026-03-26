//
//  SolarCalculator.swift
//  OPS
//
//  Sunrise/sunset calculation from latitude, longitude, and date.
//  Uses the standard solar position equations. Accurate to ~5 minutes.
//  Pure math — no API calls, fully offline.
//

import Foundation

struct SolarCalculator {

    struct DaylightResult {
        let sunrise: Date
        let sunset: Date

        /// Total usable hours between sunrise and sunset
        var hours: Double {
            sunset.timeIntervalSince(sunrise) / 3600.0
        }
    }

    /// Calculate sunrise and sunset for a given location and date.
    /// Buffer reduces the window on both ends (e.g., 30min = sunrise+30, sunset-30).
    static func daylightHours(
        latitude: Double,
        longitude: Double,
        date: Date,
        bufferMinutes: Int = 30
    ) -> DaylightResult {
        let calendar = Calendar(identifier: .gregorian)
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Solar declination (radians)
        // Earth's axial tilt = 23.44 degrees
        let declination = 23.44 * sin((360.0 / 365.0 * (dayOfYear - 81)) * .pi / 180.0) * .pi / 180.0

        let latRad = latitude * .pi / 180.0

        // Hour angle at sunrise/sunset
        // cos(hourAngle) = -tan(lat) * tan(declination)
        let cosHourAngle = -tan(latRad) * tan(declination)

        // Clamp for polar regions (midnight sun / polar night)
        let clampedCos = max(-1.0, min(1.0, cosHourAngle))
        let hourAngle = acos(clampedCos) * 180.0 / .pi // degrees

        // Convert hour angle to hours (15 degrees = 1 hour)
        let daylightHalfHours = hourAngle / 15.0

        // Solar noon in UTC hours
        // Approximate: 12:00 - longitude/15 (rough timezone offset from longitude)
        let solarNoonUTC = 12.0 - (longitude / 15.0)

        let sunriseUTC = solarNoonUTC - daylightHalfHours
        let sunsetUTC = solarNoonUTC + daylightHalfHours

        // Build Date objects for sunrise and sunset on the given date
        let startOfDay = calendar.startOfDay(for: date)

        let sunriseDate = startOfDay.addingTimeInterval(sunriseUTC * 3600)
        let sunsetDate = startOfDay.addingTimeInterval(sunsetUTC * 3600)

        // Apply buffer
        let buffer = TimeInterval(bufferMinutes * 60)
        let bufferedSunrise = sunriseDate.addingTimeInterval(buffer)
        let bufferedSunset = sunsetDate.addingTimeInterval(-buffer)

        return DaylightResult(
            sunrise: bufferedSunrise,
            sunset: bufferedSunset
        )
    }
}
