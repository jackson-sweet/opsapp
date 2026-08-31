//
//  OpportunityProjectLinkFetchTests.swift
//  OPSTests
//
//  Bug 7d94c9f3 — the project action bar's BOOK VISIT entry resolves the
//  project's linked lead through `OpportunityRepository.fetchLinked(
//  toProjectId:)`, which selects on `opportunities.project_id`. Network
//  repositories in this codebase are proven by decode / param-shape tests
//  rather than live calls, so this file pins the two payload contracts the
//  new read path depends on:
//
//    1. `OpportunityDTO` actually decodes the `project_id` column (the
//       column the new filter selects on) — a rename or a dropped coding key
//       would silently return leads whose link the app cannot see.
//    2. `CreateOpportunityDTO` still omits nil keys and carries the
//       `repeat_client` identity trio (source / client_id / address) that the
//       BOOK VISIT picker's client-materialization lane sends (Task 5).
//       PostgREST writes a null FK when a nil optional is encoded as `null`
//       instead of being omitted.
//

import XCTest
@testable import OPS

final class OpportunityProjectLinkFetchTests: XCTestCase {

    // MARK: - project_id decode (the fetchLinked(toProjectId:) contract)

    /// A converted lead's row carries `project_id`. `fetchLinked(toProjectId:)`
    /// filters on that column and hands the decoded row to the project details
    /// view model, so the coding key must survive.
    func testOpportunityDTODecodesProjectIdColumn() throws {
        let json = """
        {
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "company_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "title": "Cedar deck rebuild",
            "contact_name": "Dana Rowe",
            "stage": "won",
            "stage_entered_at": "2026-08-01T12:00:00Z",
            "project_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
            "client_id": "dddddddd-dddd-dddd-dddd-dddddddddddd",
            "assigned_to": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            "created_at": "2026-07-20T09:30:00Z",
            "updated_at": "2026-08-01T12:00:00Z"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)

        XCTAssertEqual(
            dto.projectId,
            "cccccccc-cccc-cccc-cccc-cccccccccccc",
            "project_id must decode — it is the column fetchLinked(toProjectId:) filters on"
        )
        XCTAssertEqual(dto.clientId, "dddddddd-dddd-dddd-dddd-dddddddddddd")
        XCTAssertEqual(dto.assignedTo, "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
        XCTAssertEqual(dto.companyId, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    /// An unconverted lead decodes with a nil `project_id` — the gate reads
    /// this as "no linked lead" and hides the bar entry rather than offering
    /// a verb that cannot anchor a booking.
    func testOpportunityDTODecodesMissingProjectIdAsNil() throws {
        let json = """
        {
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "company_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "stage": "qualifying",
            "stage_entered_at": "2026-08-01T12:00:00Z",
            "created_at": "2026-07-20T09:30:00Z",
            "updated_at": "2026-08-01T12:00:00Z"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)

        XCTAssertNil(dto.projectId, "an unconverted lead carries no project_id")
    }

    /// The decoded row must round-trip into the SwiftData model with the link
    /// intact — the view model upserts `dto.toModel()` and then reads
    /// `lead.id` to resolve the open booking.
    func testOpportunityDTOToModelCarriesProjectLink() throws {
        let json = """
        {
            "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "company_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "contact_name": "Dana Rowe",
            "stage": "won",
            "stage_entered_at": "2026-08-01T12:00:00Z",
            "project_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
            "assigned_to": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            "created_at": "2026-07-20T09:30:00Z",
            "updated_at": "2026-08-01T12:00:00Z"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let model = try JSONDecoder().decode(OpportunityDTO.self, from: data).toModel()

        XCTAssertEqual(model.projectId, "cccccccc-cccc-cccc-cccc-cccccccccccc")
        XCTAssertEqual(model.assignedTo, "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
        XCTAssertFalse(model.isDeleted)
    }

    // MARK: - CreateOpportunityDTO: the repeat_client materialization payload

    /// The BOOK VISIT picker materializes a bookable lead for an existing
    /// client with `source: "repeat_client"` — one of the nine values the live
    /// `opportunities_source_check` constraint allows. The client identity
    /// (client_id) and site address must reach the INSERT, and the title is
    /// derived from the contact name rather than sent empty.
    func testCreateOpportunityDTOEncodesRepeatClientSource() throws {
        let dto = CreateOpportunityDTO(
            contactName: "Dana Rowe",
            contactEmail: "dana@example.com",
            contactPhone: "+15555550123",
            address: "18 Alder Way, Squamish, BC",
            source: "repeat_client",
            clientId: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            latitude: 49.7016,
            longitude: -123.1558
        )

        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["source"] as? String, "repeat_client")
        XCTAssertEqual(json["client_id"] as? String, "dddddddd-dddd-dddd-dddd-dddddddddddd")
        XCTAssertEqual(json["address"] as? String, "18 Alder Way, Squamish, BC")
        XCTAssertEqual(json["contact_name"] as? String, "Dana Rowe")
        XCTAssertEqual(json["contact_email"] as? String, "dana@example.com")
        XCTAssertEqual(json["contact_phone"] as? String, "+15555550123")
        XCTAssertEqual(json["latitude"] as? Double, 49.7016)
        XCTAssertEqual(json["longitude"] as? Double, -123.1558)

        // Title is derived from the contact name — the picker omits it.
        XCTAssertEqual(json["title"] as? String, "Dana Rowe")
    }

    /// Nil optionals must be OMITTED, never encoded as `null`: PostgREST
    /// writes a null column for an explicit null, which would clear a value
    /// the guarded create is supposed to leave untouched.
    func testCreateOpportunityDTOOmitsNilKeys() throws {
        let dto = CreateOpportunityDTO(
            contactName: "Dana Rowe",
            source: "repeat_client",
            clientId: "dddddddd-dddd-dddd-dddd-dddddddddddd"
        )

        let data = try JSONEncoder().encode(dto)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        for absent in [
            "contact_email",
            "contact_phone",
            "address",
            "description",
            "estimated_value",
            "source_thread_key",
            "priority",
            "expected_close_date",
            "quote_delivery_method",
            "latitude",
            "longitude"
        ] {
            XCTAssertNil(
                json[absent],
                "\(absent) must be omitted when nil, not sent as null: \(jsonString)"
            )
        }

        XCTAssertEqual(json["source"] as? String, "repeat_client")
        XCTAssertEqual(json["client_id"] as? String, "dddddddd-dddd-dddd-dddd-dddddddddddd")
    }
}
