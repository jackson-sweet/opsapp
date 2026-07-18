//
//  OpportunityDTODecodeTests.swift
//  OPSTests
//
//  Migration-safety proof for the Leads chase columns (2026-07 redesign):
//  opportunities rows decode with AND without handled_at / ai_summary /
//  ai_summary_updated_at, so shipped builds and the new build read the same
//  table safely (additive-only contract).
//

import XCTest
@testable import OPS

final class OpportunityDTODecodeTests: XCTestCase {
    private func decode(_ extra: String) throws -> OpportunityDTO {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000aa","company_id":"00000000-0000-0000-0000-0000000000bb",
         "contact_name":"Helen","stage":"quoted","stage_entered_at":"2026-07-08T12:00:00Z",
         "created_at":"2026-07-01T12:00:00Z","updated_at":"2026-07-15T12:00:00Z"\(extra)}
        """
        return try JSONDecoder().decode(OpportunityDTO.self, from: Data(json.utf8))
    }

    func testDecodesWithoutNewColumns() throws {          // shipped-build shape
        let dto = try decode("")
        XCTAssertNil(dto.handledAt); XCTAssertNil(dto.aiSummary); XCTAssertNil(dto.aiSummaryUpdatedAt)
        XCTAssertNil(dto.toModel().handledAt)
    }

    func testDecodesAndMapsNewColumns() throws {
        let dto = try decode(#","handled_at":"2026-07-16T09:00:00Z","ai_summary":"Quote sent.","ai_summary_updated_at":"2026-07-15T09:00:00Z""#)
        XCTAssertEqual(dto.aiSummary, "Quote sent.")
        let model = dto.toModel()
        XCTAssertNotNil(model.handledAt); XCTAssertEqual(model.aiSummary, "Quote sent."); XCTAssertNotNil(model.aiSummaryUpdatedAt)
    }
}
