//
//  ProjectTeamSyncPayloadTests.swift
//  OPSTests
//
//  Regression coverage for server-derived project team membership sync.
//

import XCTest
@testable import OPS

@MainActor
final class ProjectTeamSyncPayloadTests: XCTestCase {

    func testProjectSyncPayloadDropsDerivedTeamMemberIds() throws {
        let sanitized = OutboundProcessor.sanitizedProjectPayloadForSync([
            "title": "Deck rebuild",
            "team_member_ids": ["crew-a", "crew-b"],
            "project_images": ["image-a"]
        ])

        XCTAssertEqual(sanitized["title"] as? String, "Deck rebuild")
        XCTAssertEqual(sanitized["project_images"] as? [String], ["image-a"])
        XCTAssertNil(sanitized["team_member_ids"])
    }

    func testProjectTaskSyncPayloadKeepsTaskTeamMemberIds() throws {
        let sanitized = OutboundProcessor.sanitizedProjectTaskPayloadForSync([
            "project_id": "project-a",
            "team_member_ids": ["crew-a", "crew-b"],
            "display_order": 3
        ])

        XCTAssertEqual(sanitized["project_id"] as? String, "project-a")
        XCTAssertEqual(sanitized["team_member_ids"] as? [String], ["crew-a", "crew-b"])
        XCTAssertEqual(sanitized["display_order"] as? Int, 3)
    }
}
