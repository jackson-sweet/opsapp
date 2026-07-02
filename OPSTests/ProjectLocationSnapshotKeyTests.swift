//
//  ProjectLocationSnapshotKeyTests.swift
//  OPSTests
//
//  The header snapshot re-rendered (full Snapshotter spin-up: style load,
//  tile fetch, render, teardown) every ~100 m the operator moved — even
//  hundreds of km from the project where no dot would ever draw. These
//  tests pin the in-frame gate.
//

import XCTest
import CoreLocation
@testable import OPS

final class ProjectLocationSnapshotKeyTests: XCTestCase {

    private let project = CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207)

    private func key(user: CLLocationCoordinate2D?) -> String {
        ProjectLocationSnapshotView.renderKey(
            projectCoordinate: project,
            userCoordinate: user,
            size: CGSize(width: 390, height: 320),
            styleRaw: "dark",
            taskColorHexes: ["#FF0000"],
            statusDescription: "active"
        )
    }

    func testFarAwayUserProducesSameKeyAsNoUser() {
        let far = CLLocationCoordinate2D(latitude: 49.5, longitude: -123.1207) // ~24 km north
        XCTAssertEqual(key(user: far), key(user: nil))
    }

    func testNearbyUserIsFoldedIntoKey() {
        let near = CLLocationCoordinate2D(latitude: 49.2830, longitude: -123.1210) // ~40 m away
        XCTAssertNotEqual(key(user: near), key(user: nil))
    }

    func testGPSJitterWithinBucketIsStable() {
        let a = CLLocationCoordinate2D(latitude: 49.28271, longitude: -123.12072)
        let b = CLLocationCoordinate2D(latitude: 49.28274, longitude: -123.12069)
        XCTAssertEqual(key(user: a), key(user: b))
    }

    func testMeaningfulMoveNearProjectRefreshesKey() {
        let a = CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207)
        let b = CLLocationCoordinate2D(latitude: 49.2840, longitude: -123.1207) // ~145 m
        XCTAssertNotEqual(key(user: a), key(user: b))
    }
}
