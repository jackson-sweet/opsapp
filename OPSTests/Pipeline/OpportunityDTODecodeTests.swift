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
        XCTAssertNil(dto.operatorActionRequiredAt)
        XCTAssertNil(dto.toModel().handledAt)
        XCTAssertNil(dto.toModel().operatorActionRequiredAt)
    }

    func testDecodesAndMapsNewColumns() throws {
        let dto = try decode(#","handled_at":"2026-07-16T09:00:00Z","operator_action_required_at":"2026-07-17T09:00:00Z","ai_summary":"Quote sent.","ai_summary_updated_at":"2026-07-15T09:00:00Z""#)
        XCTAssertEqual(dto.aiSummary, "Quote sent.")
        let model = dto.toModel()
        XCTAssertNotNil(model.handledAt)
        XCTAssertNotNil(model.operatorActionRequiredAt)
        XCTAssertEqual(model.aiSummary, "Quote sent.")
        XCTAssertNotNil(model.aiSummaryUpdatedAt)
    }

    func testOperatorActionRequiredPatchUsesOnlyCanonicalColumn() throws {
        let stamp = "2026-07-23T07:00:00.000Z"
        let data = try JSONEncoder().encode(
            MarkOperatorActionRequiredPatch(operatorActionRequiredAt: stamp)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        XCTAssertEqual(object, ["operator_action_required_at": stamp])
    }

    func testLogQuickTouchParamsUseCanonicalRpcKeys() throws {
        let requestId = "00000000-0000-0000-0000-0000000000cc"
        let data = try JSONEncoder().encode(
            LogOpportunityQuickTouchParams(
                requestId: requestId,
                opportunityId: "opportunity-1",
                type: "text_message",
                subject: "TEXT MESSAGE"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["p_request_id"] as? String, requestId)
        XCTAssertEqual(object["p_opportunity_id"] as? String, "opportunity-1")
        XCTAssertEqual(object["p_type"] as? String, "text_message")
        XCTAssertEqual(object["p_subject"] as? String, "TEXT MESSAGE")
        XCTAssertEqual(object.count, 4)
    }

    func testLogQuickTouchResultDecodesBothAuthoritativeRows() throws {
        let json = """
        {
          "activity": {
            "id": "activity-1",
            "opportunity_id": "00000000-0000-0000-0000-0000000000aa",
            "company_id": "00000000-0000-0000-0000-0000000000bb",
            "type": "text_message",
            "created_at": "2026-07-23T07:00:00.000Z"
          },
          "opportunity": {
            "id": "00000000-0000-0000-0000-0000000000aa",
            "company_id": "00000000-0000-0000-0000-0000000000bb",
            "contact_name": "Helen",
            "stage": "quoted",
            "stage_entered_at": "2026-07-08T12:00:00Z",
            "handled_at": "2026-07-23T07:00:00.000Z",
            "created_at": "2026-07-01T12:00:00Z",
            "updated_at": "2026-07-23T07:00:00Z"
          }
        }
        """
        let result = try JSONDecoder().decode(
            LogOpportunityQuickTouchResult.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(result.activity.id, "activity-1")
        XCTAssertEqual(
            result.opportunity.id,
            "00000000-0000-0000-0000-0000000000aa"
        )
        XCTAssertNotNil(result.opportunity.handledAt)
    }

    func testUndoQuickTouchParamsUseCanonicalRpcKeys() throws {
        let data = try JSONEncoder().encode(
            UndoOpportunityQuickTouchParams(
                activityId: "activity-1",
                opportunityId: "opportunity-1"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["p_activity_id"] as? String, "activity-1")
        XCTAssertEqual(object["p_opportunity_id"] as? String, "opportunity-1")
        XCTAssertEqual(object.count, 2)
    }
}
