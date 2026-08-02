//
//  DaySheetLeadAddressActionTests.swift
//  OPSTests
//
//  Regression coverage for bug a093d9cc: one address gesture must resolve to
//  exactly one effect. A route may never copy, and a hold-copy may never open
//  Maps on release.
//

import XCTest
@testable import OPS

final class DaySheetLeadAddressActionTests: XCTestCase {

    func testRoutePerformsOnlyRouteEffect() {
        var routeCount = 0
        var copyCount = 0

        DaySheetLeadAddressAction.route.perform(
            openRoute: { routeCount += 1 },
            copyAddress: { copyCount += 1 }
        )

        XCTAssertEqual(routeCount, 1)
        XCTAssertEqual(copyCount, 0)
    }

    func testCopyPerformsOnlyCopyEffect() {
        var routeCount = 0
        var copyCount = 0

        DaySheetLeadAddressAction.copy.perform(
            openRoute: { routeCount += 1 },
            copyAddress: { copyCount += 1 }
        )

        XCTAssertEqual(routeCount, 0)
        XCTAssertEqual(copyCount, 1)
    }
}
