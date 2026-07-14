//
//  DeckDesignOpportunityTests.swift
//  OPSTests
//
//  Deck designs attach to LEADS via deck_designs.opportunity_id. Coverage:
//  DTO round-trip, inbound merge acceptance, canonical id handling, and the
//  lead-scoped display-candidate rule (mirrors DeckDesignSyncTests' project
//  coverage).
//

import SwiftData
import XCTest
@testable import OPS

final class DeckDesignOpportunityTests: XCTestCase {

    func test_Initializer_canonicalizesOpportunityId() {
        let design = DeckDesign(
            companyId: "A612EDC0-5C18-4C4D-AF97-55B9410DD077",
            opportunityId: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9",
            title: "Lead Deck"
        )
        XCTAssertEqual(design.opportunityId, "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")
        XCTAssertTrue(design.isAttached(toOpportunityId: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"))
    }

    func test_DTO_roundTripsOpportunityId() throws {
        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            opportunityId: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Lead Deck"
        )
        let dto = SupabaseDeckDesignDTO.fromModel(design)
        XCTAssertEqual(dto.opportunityId, "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")

        // Wire shape: encoded JSON carries snake_case opportunity_id.
        let encoded = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["opportunity_id"] as? String, "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")

        let decoded = try JSONDecoder().decode(SupabaseDeckDesignDTO.self, from: encoded)
        XCTAssertEqual(decoded.toModel().opportunityId, "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")
    }

    func test_ApplyServerSnapshot_deliversOpportunityId() throws {
        // A clean local row (no pending edits) must accept the server's
        // opportunity link — this is how the other devices learn a deck was
        // drawn on a lead.
        let local = DeckDesign(
            id: "c0509774-2748-479f-92e7-ee7d5dcff14e",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            title: "Lead Deck"
        )
        local.updatedAt = Date(timeIntervalSince1970: 1_000)

        var dto = SupabaseDeckDesignDTO.fromModel(local)
        dto = SupabaseDeckDesignDTO(
            id: dto.id,
            companyId: dto.companyId,
            projectId: nil,
            opportunityId: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: dto.title,
            drawingData: dto.drawingData,
            thumbnailUrl: dto.thumbnailUrl,
            version: dto.version,
            createdBy: dto.createdBy,
            createdAt: dto.createdAt,
            updatedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 2_000)),
            deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))
        XCTAssertEqual(local.opportunityId, "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")
    }

    func test_DisplayCandidate_scopedToOpportunity() {
        let oppId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

        let mine = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            opportunityId: oppId,
            title: "Mine"
        )
        mine.updatedAt = Date(timeIntervalSince1970: 5_000)

        let other = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            opportunityId: "ffffffff-0000-0000-0000-000000000000",
            title: "Someone else's lead"
        )
        other.updatedAt = Date(timeIntervalSince1970: 9_000)

        let deleted = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            opportunityId: oppId,
            title: "Deleted"
        )
        deleted.deletedAt = Date()
        deleted.updatedAt = Date(timeIntervalSince1970: 9_500)

        let candidate = DeckDesign.displayCandidate(
            in: [mine, other, deleted],
            forOpportunityId: oppId
        )
        XCTAssertEqual(candidate?.title, "Mine")
    }

    func test_ConvertedLeadDeck_stillSurfacesOnTheLead() {
        // After conversion the server sets project_id and KEEPS opportunity_id
        // — the lead must keep showing its deck.
        let oppId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
        let converted = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            opportunityId: oppId,
            title: "Converted"
        )

        XCTAssertTrue(converted.isAttached(toOpportunityId: oppId))
        XCTAssertNotNil(DeckDesign.displayCandidate(in: [converted], forOpportunityId: oppId))
    }
}
