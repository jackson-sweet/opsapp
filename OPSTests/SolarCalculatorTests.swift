import XCTest
@testable import OPS

final class SolarCalculatorTests: XCTestCase {

    func testEdmontonSummerSolstice() {
        // Edmonton (53.5461N) on June 21 — sunrise ~5:04, sunset ~22:07 local
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!

        let result = SolarCalculator.daylightHours(
            latitude: 53.5461,
            longitude: -113.4938,
            date: date,
            bufferMinutes: 0
        )

        // Sunrise should be between 5:00-5:15 UTC-6
        let sunriseHour = cal.component(.hour, from: result.sunrise)
        XCTAssertEqual(sunriseHour, 5, "Summer solstice sunrise in Edmonton should be ~5 AM")

        // Sunset should be between 21:00-22:15 UTC-6
        let sunsetHour = cal.component(.hour, from: result.sunset)
        XCTAssertTrue(sunsetHour >= 21 && sunsetHour <= 22, "Summer solstice sunset in Edmonton should be ~10 PM")
    }

    func testEdmontonWinterSolstice() {
        // Edmonton on Dec 21 — sunrise ~8:48, sunset ~16:15 local
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        let date = cal.date(from: DateComponents(year: 2026, month: 12, day: 21))!

        let result = SolarCalculator.daylightHours(
            latitude: 53.5461,
            longitude: -113.4938,
            date: date,
            bufferMinutes: 0
        )

        let sunriseHour = cal.component(.hour, from: result.sunrise)
        XCTAssertTrue(sunriseHour >= 8 && sunriseHour <= 9, "Winter solstice sunrise should be ~8:48 AM")

        let sunsetHour = cal.component(.hour, from: result.sunset)
        XCTAssertTrue(sunsetHour >= 16 && sunsetHour <= 17, "Winter solstice sunset should be ~4:15 PM")
    }

    func testBufferReducesWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!

        let noBuffer = SolarCalculator.daylightHours(
            latitude: 53.5461, longitude: -113.4938, date: date, bufferMinutes: 0
        )
        let withBuffer = SolarCalculator.daylightHours(
            latitude: 53.5461, longitude: -113.4938, date: date, bufferMinutes: 30
        )

        // Buffer should push sunrise later and sunset earlier
        XCTAssertGreaterThan(withBuffer.sunrise, noBuffer.sunrise)
        XCTAssertLessThan(withBuffer.sunset, noBuffer.sunset)

        // 30 min buffer on each side = 60 min less total
        let noBufferMinutes = noBuffer.sunset.timeIntervalSince(noBuffer.sunrise) / 60
        let withBufferMinutes = withBuffer.sunset.timeIntervalSince(withBuffer.sunrise) / 60
        XCTAssertEqual(noBufferMinutes - withBufferMinutes, 60, accuracy: 1)
    }

    func testAvailableHoursCalculation() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!

        let result = SolarCalculator.daylightHours(
            latitude: 53.5461, longitude: -113.4938, date: date, bufferMinutes: 30
        )

        // Edmonton summer: ~17 hours daylight minus 1 hour buffer = ~16 hours
        let hours = result.sunset.timeIntervalSince(result.sunrise) / 3600
        XCTAssertGreaterThan(hours, 14)
        XCTAssertLessThan(hours, 18)
    }
}
