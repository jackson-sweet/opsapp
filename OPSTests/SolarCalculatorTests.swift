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

        // Approximate solar calculation — verify daylight duration is reasonable (~17h in summer Edmonton)
        let daylightHours = result.sunset.timeIntervalSince(result.sunrise) / 3600
        XCTAssertGreaterThan(daylightHours, 15, "Summer solstice daylight should be >15h, got \(daylightHours)")
        XCTAssertLessThan(daylightHours, 19, "Summer solstice daylight should be <19h, got \(daylightHours)")
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

        // Approximate solar calculation — verify daylight duration is reasonable (~7.5h in winter Edmonton)
        let daylightHours = result.sunset.timeIntervalSince(result.sunrise) / 3600
        XCTAssertGreaterThan(daylightHours, 6, "Winter solstice daylight should be >6h, got \(daylightHours)")
        XCTAssertLessThan(daylightHours, 9, "Winter solstice daylight should be <9h, got \(daylightHours)")
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
