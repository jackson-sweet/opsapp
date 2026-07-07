//
//  CreateActivityDTOTests.swift
//  OPSTests
//
//  Covers the unified-activity data-layer widening (Task 0.1 / 0.2):
//  an activity can be parented to a lead (opportunity), client, OR job
//  (project) and carry an author (created_by). PostgREST requires that a
//  nil parent be OMITTED from the encoded JSON — never sent as `null` — so a
//  client-targeted activity must not carry `opportunity_id` at all.
//

import XCTest
@testable import OPS

final class CreateActivityDTOTests: XCTestCase {

    // MARK: - Task 0.1: CreateActivityDTO encoding (nil parents omitted)

    /// A client-targeted activity carries client_id + created_by but NO
    /// opportunity_id. The synthesized Codable encoder must omit the nil
    /// optional entirely (not emit `"opportunity_id": null`), or PostgREST
    /// would try to write a null opportunity FK.
    func test_CreateActivityDTO_clientTargeted_omitsNilOpportunityId() throws {
        let dto = CreateActivityDTO(
            companyId: "22222222-2222-2222-2222-222222222222",
            type: "note",
            bodyText: "Left voicemail with the client",
            clientId: "44444444-4444-4444-4444-444444444444",
            createdBy: "33333333-3333-3333-3333-333333333333"
        )

        let data = try JSONEncoder().encode(dto)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        // (a) nil opportunityId must be OMITTED, not encoded as null.
        XCTAssertFalse(
            jsonString.contains("opportunity_id"),
            "nil opportunityId must be omitted from the encoded JSON (PostgREST would write a null FK): \(jsonString)"
        )

        // (b) the set parent + author + company must all be present.
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["client_id"] as? String, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(json["company_id"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(json["created_by"] as? String, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(json["type"] as? String, "note")
        XCTAssertEqual(json["body_text"] as? String, "Left voicemail with the client")

        // The nil parents are absent as keys entirely.
        XCTAssertNil(json["opportunity_id"], "opportunity_id key must be absent")
        XCTAssertNil(json["project_id"], "project_id key must be absent when nil")
        XCTAssertNil(json["site_visit_id"], "site_visit_id key must be absent when nil")
    }

    /// A project (job) targeted activity carries project_id and omits the
    /// other parents.
    func test_CreateActivityDTO_projectTargeted_omitsNilOpportunityId() throws {
        let dto = CreateActivityDTO(
            companyId: "co",
            type: "note",
            projectId: "job-123",
            createdBy: "user-1"
        )
        let data = try JSONEncoder().encode(dto)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(jsonString.contains("opportunity_id"),
                       "nil opportunityId must be omitted: \(jsonString)")
        XCTAssertFalse(jsonString.contains("client_id"),
                       "nil clientId must be omitted: \(jsonString)")

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["project_id"] as? String, "job-123")
        XCTAssertEqual(json["created_by"] as? String, "user-1")
    }

    /// The legacy opportunity-targeted shape still encodes opportunity_id and
    /// omits the newly-added parents — existing call sites are unchanged.
    func test_CreateActivityDTO_opportunityTargeted_encodesOpportunityId() throws {
        let dto = CreateActivityDTO(
            opportunityId: "opp-1",
            companyId: "co",
            type: "note",
            bodyText: "Quote sent"
        )
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["opportunity_id"] as? String, "opp-1")
        XCTAssertNil(json["client_id"], "client_id absent for an opportunity-targeted activity")
        XCTAssertNil(json["project_id"], "project_id absent for an opportunity-targeted activity")
        XCTAssertNil(json["created_by"], "created_by absent when not supplied")
    }

    // MARK: - Task 0.2: ActivityDTO decoding (client_id / project_id → model)

    /// A row parented to a client + job decodes those FKs and toModel()
    /// populates Activity.clientId / Activity.projectId.
    func test_ActivityDTO_decodesClientAndProjectParents() throws {
        let json = """
        {
          "id": "act-1",
          "opportunity_id": null,
          "company_id": "co",
          "type": "note",
          "subject": null,
          "body_text": "Discussed scope on site",
          "content": null,
          "direction": null,
          "outcome": null,
          "duration_minutes": null,
          "call_source": null,
          "caller_number": null,
          "call_started_at": null,
          "is_read": null,
          "has_attachments": null,
          "attachment_count": null,
          "client_id": "44444444-4444-4444-4444-444444444444",
          "project_id": "job-123",
          "created_by": "33333333-3333-3333-3333-333333333333",
          "created_at": "2026-07-05T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(ActivityDTO.self, from: data)
        XCTAssertEqual(dto.clientId, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(dto.projectId, "job-123")
        XCTAssertNil(dto.opportunityId)

        let model = dto.toModel()
        XCTAssertEqual(model.clientId, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(model.projectId, "job-123")
        XCTAssertNil(model.opportunityId, "opportunityId is nil for a client/job-parented activity")
        XCTAssertEqual(model.createdBy, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(model.type, .note)
    }

    /// A legacy opportunity-parented row (no client_id / project_id keys)
    /// still decodes — the new fields are absent and stay nil.
    func test_ActivityDTO_legacyOpportunityRow_decodesWithNilNewParents() throws {
        let json = """
        {
          "id": "act-2",
          "opportunity_id": "opp-1",
          "company_id": "co",
          "type": "call",
          "created_at": "2026-07-05T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(ActivityDTO.self, from: data)
        XCTAssertEqual(dto.opportunityId, "opp-1")
        XCTAssertNil(dto.clientId)
        XCTAssertNil(dto.projectId)

        let model = dto.toModel()
        XCTAssertEqual(model.opportunityId, "opp-1")
        XCTAssertNil(model.clientId)
        XCTAssertNil(model.projectId)
    }
}
