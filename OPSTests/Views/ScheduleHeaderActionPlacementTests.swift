//
//  ScheduleHeaderActionPlacementTests.swift
//  OPSTests
//
//  Regression proof for bug 625d0c58: Month is a direct Schedule header
//  action. Filters and team scope remain grouped as secondary configuration.
//

#if DEBUG
import XCTest
@testable import OPS

final class ScheduleHeaderActionPlacementTests: XCTestCase {
    func testMonthAndSearchStayPrimaryWhileFiltersAndScopeRemainSecondary() {
        let placement = ScheduleHeaderActionPlacementPolicy.placement(
            hasMonthAction: true,
            hasFilterAction: true,
            hasScopeAction: true
        )

        XCTAssertEqual(placement.primary, [.month, .search])
        XCTAssertEqual(placement.secondary, [.filters, .scope])
    }

}
#endif
