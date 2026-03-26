import XCTest
@testable import OPS

final class HaversineDistanceTests: XCTestCase {

    func testSamePointReturnsZero() {
        let d = HaversineDistance.km(
            lat1: 53.5461, lon1: -113.4938,
            lat2: 53.5461, lon2: -113.4938
        )
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    func testEdmontonToCalgary() {
        // Edmonton (53.5461, -113.4938) to Calgary (51.0447, -114.0719)
        // Known distance ~299 km
        let d = HaversineDistance.km(
            lat1: 53.5461, lon1: -113.4938,
            lat2: 51.0447, lon2: -114.0719
        )
        XCTAssertEqual(d, 299, accuracy: 5) // within 5km
    }

    func testShortDistance() {
        // Two points ~1km apart in downtown Edmonton
        let d = HaversineDistance.km(
            lat1: 53.5461, lon1: -113.4938,
            lat2: 53.5471, lon2: -113.4808
        )
        XCTAssertGreaterThan(d, 0.5)
        XCTAssertLessThan(d, 2.0)
    }

    func testWithinRadius() {
        // 1km apart, 15km radius => true
        XCTAssertTrue(HaversineDistance.isWithinRadius(
            lat1: 53.5461, lon1: -113.4938,
            lat2: 53.5471, lon2: -113.4808,
            radiusKm: 15.0
        ))
    }

    func testOutsideRadius() {
        // Edmonton to Calgary (~299km), 15km radius => false
        XCTAssertFalse(HaversineDistance.isWithinRadius(
            lat1: 53.5461, lon1: -113.4938,
            lat2: 51.0447, lon2: -114.0719,
            radiusKm: 15.0
        ))
    }
}
