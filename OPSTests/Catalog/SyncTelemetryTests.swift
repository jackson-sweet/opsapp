//
//  SyncTelemetryTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class SyncTelemetryTests: XCTestCase {
    func test_buildEvent_includesEntityTypeAndAppVersion() {
        let event = SyncTelemetry.buildEvent(
            entityType: "catalogItem",
            error: NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"]),
            isFullSync: true,
            companyId: "company-123",
            userId: "user-456"
        )

        XCTAssertEqual(event["event_name"] as? String, "sync_entity_failed")
        XCTAssertEqual(event["entity_type"] as? String, "catalogItem")
        XCTAssertEqual(event["error_class"] as? String, "TestDomain")
        XCTAssertEqual(event["error_code"] as? Int, 42)
        XCTAssertEqual(event["error_message"] as? String, "boom")
        XCTAssertEqual(event["sync_phase"] as? String, "full")
        XCTAssertEqual(event["company_id"] as? String, "company-123")
        XCTAssertEqual(event["user_id"] as? String, "user-456")
        XCTAssertNotNil(event["app_version"])
    }

    func test_buildEvent_deltaSyncPhase() {
        let event = SyncTelemetry.buildEvent(
            entityType: "catalogVariant",
            error: NSError(domain: "X", code: 1),
            isFullSync: false,
            companyId: "c",
            userId: "u"
        )
        XCTAssertEqual(event["sync_phase"] as? String, "delta")
    }
}
