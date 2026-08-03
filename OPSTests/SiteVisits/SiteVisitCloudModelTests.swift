//
//  SiteVisitCloudModelTests.swift
//  OPSTests
//
//  Local model contract for the cloud-backed site-visit packet.
//

import SwiftData
import XCTest
@testable import OPS

final class SiteVisitCloudModelTests: XCTestCase {
    func testNewVisitStartsInProgressWithCanonicalIdsAndCloudDefaults() {
        let createdAt = Date(timeIntervalSince1970: 10_000)
        let visit = SiteVisit(
            id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            opportunityId: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            companyId: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC",
            status: .inProgress,
            createdAt: createdAt
        )

        XCTAssertEqual(visit.id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(visit.opportunityId, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        XCTAssertEqual(visit.companyId, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertEqual(visit.status, .inProgress)
        XCTAssertEqual(visit.scheduledAt, createdAt, "Every newly-created visit must have the non-null server schedule timestamp immediately.")
        XCTAssertEqual(visit.durationMinutes, 60)
        XCTAssertEqual(visit.assigneeIds, [])
        XCTAssertEqual(visit.photos, [])
        XCTAssertTrue(visit.needsSync)
        XCTAssertNil(visit.lastSyncedAt)
        XCTAssertNil(visit.deletedAt)
    }

    func testVisitPersistsServerBackedFieldsAndExistingActivitySlot() throws {
        let schema = Schema(versionedSchema: OPSSchemaV22.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let visit = SiteVisit(
            companyId: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            projectId: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            projectRef: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE",
            clientId: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC",
            clientRef: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF",
            status: .inProgress,
            loggedActivityId: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD",
            createdAt: Date(timeIntervalSince1970: 10_000)
        )
        visit.durationMinutes = 90
        visit.assigneeIds = ["user-1", "user-2"]
        visit.internalNotes = "Bring a second ladder"
        visit.measurements = "North wall: 18 ft"
        visit.photos = ["https://cdn.ops.test/visit.jpg"]
        visit.calendarEventId = "calendar-1"
        visit.createdBy = "user-1"
        visit.updatedAt = Date(timeIntervalSince1970: 11_000)
        context.insert(visit)
        try context.save()

        let reread = try XCTUnwrap(try context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(reread.projectId, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        XCTAssertEqual(reread.projectRef, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
        XCTAssertEqual(reread.clientId, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertEqual(reread.clientRef, "ffffffff-ffff-4fff-8fff-ffffffffffff")
        XCTAssertEqual(reread.durationMinutes, 90)
        XCTAssertEqual(reread.assigneeIds, ["user-1", "user-2"])
        XCTAssertEqual(reread.internalNotes, "Bring a second ladder")
        XCTAssertEqual(reread.measurements, "North wall: 18 ft")
        XCTAssertEqual(reread.photos, ["https://cdn.ops.test/visit.jpg"])
        XCTAssertEqual(reread.calendarEventId, "calendar-1")
        XCTAssertEqual(reread.createdBy, "user-1")
        XCTAssertEqual(reread.loggedActivityId, "dddddddd-dddd-4ddd-8ddd-dddddddddddd")
    }

    func testIdentityDraftCanonicalizesCloudIdsWithoutTreatingSearchAsCloudState() {
        let draft = SiteVisitIdentityDraft(
            id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            siteVisitId: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            companyId: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC",
            opportunityId: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD",
            clientId: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE",
            subClientId: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF",
            searchText: "not part of a cloud payload",
            clientName: "North Shore Homes"
        )

        XCTAssertEqual(draft.id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(draft.siteVisitId, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        XCTAssertEqual(draft.companyId, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertEqual(draft.opportunityId, "dddddddd-dddd-4ddd-8ddd-dddddddddddd")
        XCTAssertEqual(draft.clientId, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
        XCTAssertEqual(draft.subClientId, "ffffffff-ffff-4fff-8fff-ffffffffffff")
        XCTAssertEqual(draft.searchText, "not part of a cloud payload", "Search remains local UI state; DTO tests guard that it is never encoded.")
        XCTAssertTrue(draft.needsSync)
        XCTAssertNil(draft.lastSyncedAt)
        XCTAssertNil(draft.deletedAt)
    }
}
