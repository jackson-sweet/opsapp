//
//  ProjectDetailsExpenseCacheTests.swift
//  OPSTests
//
//  The Expenses tab re-fetched from Supabase on every tab switch. These
//  tests pin the staleness rule that lets a visit render the cached list
//  instantly while realtime (.opsExpensesDidChange) stays the authoritative
//  refresh path.
//

import XCTest
@testable import OPS

final class ProjectDetailsExpenseCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testNeverLoadedIsStale() {
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: nil, hasData: true, now: now, maxAge: 300))
    }

    func testFreshWithDataSkipsReload() {
        XCTAssertTrue(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-60), hasData: true, now: now, maxAge: 300))
    }

    func testFreshButEmptyReloads() {
        // An empty list may mean the first fetch failed silently — refetch.
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-60), hasData: false, now: now, maxAge: 300))
    }

    func testStaleReloads() {
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-301), hasData: true, now: now, maxAge: 300))
    }
}
