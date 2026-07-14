//
//  OpportunityImagesMappingTests.swift
//  OPSTests
//
//  Mapping coverage for the opportunities columns iOS deferred in LEADS
//  Phase 1 and adopts now: images (text[]), latitude, longitude. The DTO
//  must round-trip them, the model must carry them through apply(), and the
//  edit patch must emit explicit nulls so a cleared coordinate actually
//  clears server-side (same contract as EditOpportunityPatch's other keys).
//

import XCTest
@testable import OPS

final class OpportunityImagesMappingTests: XCTestCase {

    // MARK: - DTO → model

    func test_OpportunityDTO_decodesImagesAndCoordinates_intoModel() throws {
        let json = """
        {
            "id": "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            "company_id": "11111111-2222-3333-4444-555555555555",
            "contact_name": "Helen Calloway",
            "stage": "quoted",
            "stage_entered_at": "2026-07-01T12:00:00Z",
            "created_at": "2026-06-20T09:30:00Z",
            "updated_at": "2026-07-10T16:45:00Z",
            "images": [
                "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/opportunities/1/2/a.jpg",
                "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/opportunities/1/2/b.jpg"
            ],
            "latitude": 48.4284,
            "longitude": -123.3656
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: json)
        let model = dto.toModel()

        XCTAssertEqual(model.images.count, 2)
        XCTAssertEqual(model.images.first?.hasSuffix("a.jpg"), true)
        XCTAssertEqual(model.latitude, 48.4284)
        XCTAssertEqual(model.longitude, -123.3656)
    }

    func test_OpportunityDTO_missingImages_decodesToEmptyArray() throws {
        let json = """
        {
            "id": "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            "company_id": "11111111-2222-3333-4444-555555555555",
            "contact_name": "Trevor Akinola",
            "stage": "new_lead",
            "stage_entered_at": "2026-07-01T12:00:00Z",
            "created_at": "2026-06-20T09:30:00Z",
            "updated_at": "2026-07-10T16:45:00Z"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: json)
        let model = dto.toModel()

        XCTAssertEqual(model.images, [])
        XCTAssertNil(model.latitude)
        XCTAssertNil(model.longitude)
    }

    // MARK: - apply() refresh copy

    func test_Apply_copiesImagesAndCoordinates() {
        let a = Opportunity(
            id: "aaaaaaaa-0000-0000-0000-000000000001",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "A"
        )
        let b = Opportunity(
            id: "aaaaaaaa-0000-0000-0000-000000000001",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "B"
        )
        b.images = ["https://example.com/x.jpg"]
        b.latitude = 49.25
        b.longitude = -123.1

        a.apply(b)

        XCTAssertEqual(a.images, ["https://example.com/x.jpg"])
        XCTAssertEqual(a.latitude, 49.25)
        XCTAssertEqual(a.longitude, -123.1)

        // And the reverse: a refresh that DROPS images/coords must clear them,
        // never leave stale local values behind (apply() contract).
        let c = Opportunity(
            id: "aaaaaaaa-0000-0000-0000-000000000001",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "C"
        )
        b.apply(c)
        XCTAssertEqual(b.images, [])
        XCTAssertNil(b.latitude)
        XCTAssertNil(b.longitude)
    }

    // MARK: - Edit patch explicit nulls

    func test_EditOpportunityPatch_emitsExplicitNullCoordinates() throws {
        let patch = EditOpportunityPatch(
            title: nil,
            contactName: "Helen Calloway",
            contactEmail: nil,
            contactPhone: nil,
            description: nil,
            address: nil,
            estimatedValue: nil,
            source: "referral",
            priority: "medium",
            latitude: nil,
            longitude: nil
        )

        let data = try JSONEncoder().encode(patch)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Keys must be PRESENT with JSON null — encodeIfPresent would omit
        // them and a cleared coordinate would silently survive server-side.
        XCTAssertTrue(object.keys.contains("latitude"))
        XCTAssertTrue(object.keys.contains("longitude"))
        XCTAssertTrue(object["latitude"] is NSNull)
        XCTAssertTrue(object["longitude"] is NSNull)
    }

    func test_EditOpportunityPatch_carriesCoordinateValues() throws {
        let patch = EditOpportunityPatch(
            title: "Roof tear-off",
            contactName: "Helen Calloway",
            contactEmail: nil,
            contactPhone: nil,
            description: nil,
            address: "1240 Maple Ave",
            estimatedValue: 14_200,
            source: "referral",
            priority: "medium",
            latitude: 48.4284,
            longitude: -123.3656
        )

        let data = try JSONEncoder().encode(patch)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["latitude"] as? Double, 48.4284)
        XCTAssertEqual(object["longitude"] as? Double, -123.3656)
    }

    // MARK: - Create DTO key omission

    func test_CreateOpportunityDTO_omitsCoordinatesWhenNil() throws {
        let dto = CreateOpportunityDTO(
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway"
        )
        let data = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Synthesized Codable omits nil optionals — a create must not send
        // latitude: null (PostgREST would write the column explicitly).
        XCTAssertFalse(object.keys.contains("latitude"))
        XCTAssertFalse(object.keys.contains("longitude"))
    }

    func test_CreateOpportunityDTO_carriesCoordinatesWhenSet() throws {
        let dto = CreateOpportunityDTO(
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway",
            latitude: 48.4284,
            longitude: -123.3656
        )
        let data = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["latitude"] as? Double, 48.4284)
        XCTAssertEqual(object["longitude"] as? Double, -123.3656)
    }
}
