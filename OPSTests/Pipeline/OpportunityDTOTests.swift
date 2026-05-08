//
//  OpportunityDTOTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class OpportunityDTOTests: XCTestCase {

    // MARK: - OpportunityDTO

    func test_OpportunityDTO_decodesFullSchema() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "company_id": "22222222-2222-2222-2222-222222222222",
          "title": "Devlin roof replacement",
          "contact_name": "Eric Devlin",
          "contact_email": "eric@devlin.com",
          "contact_phone": "555-1234",
          "description": "Full roof tear-off",
          "address": "123 Main St",
          "stage": "quoting",
          "stage_entered_at": "2026-05-01T12:00:00Z",
          "stage_manually_set": true,
          "assigned_to": "33333333-3333-3333-3333-333333333333",
          "priority": "high",
          "source": "referral",
          "quote_delivery_method": "email",
          "estimated_value": 24000,
          "actual_value": null,
          "win_probability": 60,
          "expected_close_date": "2026-06-15",
          "actual_close_date": null,
          "next_follow_up_at": "2026-05-10T09:00:00Z",
          "last_activity_at": "2026-05-05T15:30:00Z",
          "project_id": null,
          "client_id": "44444444-4444-4444-4444-444444444444",
          "lost_reason": null,
          "lost_notes": null,
          "deleted_at": null,
          "archived_at": null,
          "tags": ["urgent", "referral"],
          "source_email_id": null,
          "correspondence_count": 4,
          "outbound_count": 2,
          "inbound_count": 2,
          "last_inbound_at": "2026-05-05T15:30:00Z",
          "last_outbound_at": "2026-05-04T10:00:00Z",
          "last_message_direction": "inbound",
          "created_at": "2026-04-25T08:00:00Z",
          "updated_at": "2026-05-05T15:30:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)
        XCTAssertEqual(dto.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(dto.title, "Devlin roof replacement")
        XCTAssertEqual(dto.stage, "quoting")
        XCTAssertEqual(dto.estimatedValue, 24000)
        XCTAssertEqual(dto.winProbability, 60)
        XCTAssertEqual(dto.tags, ["urgent", "referral"])
        XCTAssertEqual(dto.correspondenceCount, 4)
        XCTAssertEqual(dto.lastMessageDirection, "inbound")

        let opp = dto.toModel()
        XCTAssertEqual(opp.contactName, "Eric Devlin")
        XCTAssertEqual(opp.stage, .quoting)
        XCTAssertEqual(opp.weightedValue, 24000 * 0.6, accuracy: 0.01)
        XCTAssertTrue(opp.stageManuallySet)
    }

    func test_OpportunityDTO_decodesMinimalRow() throws {
        let json = """
        {
          "id": "abc",
          "company_id": "co",
          "title": null,
          "contact_name": null,
          "contact_email": null, "contact_phone": null, "description": null, "address": null,
          "stage": "new_lead",
          "stage_entered_at": "2026-05-07T00:00:00Z",
          "stage_manually_set": null,
          "assigned_to": null, "priority": null, "source": null, "quote_delivery_method": null,
          "estimated_value": null, "actual_value": null, "win_probability": null,
          "expected_close_date": null, "actual_close_date": null,
          "next_follow_up_at": null, "last_activity_at": null,
          "project_id": null, "client_id": null,
          "lost_reason": null, "lost_notes": null,
          "deleted_at": null, "archived_at": null,
          "tags": null, "source_email_id": null,
          "correspondence_count": null, "outbound_count": null, "inbound_count": null,
          "last_inbound_at": null, "last_outbound_at": null, "last_message_direction": null,
          "created_at": "2026-05-07T00:00:00Z",
          "updated_at": "2026-05-07T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)
        let opp = dto.toModel()
        XCTAssertEqual(opp.contactName, "")
        XCTAssertEqual(opp.tags, [])
        XCTAssertEqual(opp.correspondenceCount, 0)
        XCTAssertFalse(opp.stageManuallySet)
    }

    // MARK: - CreateFollowUpDTO bug fix

    func test_CreateFollowUpDTO_includesRequiredTitleAndDescription() throws {
        let dto = CreateFollowUpDTO(
            companyId: "co",
            opportunityId: "opp",
            title: "Follow up with Devlin re quote",
            description: "He asked about timeline",
            type: "call",
            dueAt: "2026-05-10T09:00:00Z",
            reminderAt: nil,
            assignedTo: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["title"] as? String, "Follow up with Devlin re quote")
        XCTAssertEqual(json["description"] as? String, "He asked about timeline")
        XCTAssertNil(json["notes"], "FollowUp DB column is `description`, not `notes` (bug fix)")
    }

    // MARK: - StageTransitionDTO

    func test_StageTransitionDTO_decodesPostgresInterval() throws {
        let json = """
        {
          "id": "t1",
          "company_id": "co",
          "opportunity_id": "opp",
          "from_stage": "quoting",
          "to_stage": "quoted",
          "transitioned_at": "2026-05-07T12:00:00Z",
          "transitioned_by": "user-uuid",
          "duration_in_stage": "2 days 03:00:00"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StageTransitionDTO.self, from: data)
        let model = dto.toModel()
        XCTAssertEqual(model.fromStage, .quoting)
        XCTAssertEqual(model.toStage, .quoted)
        let duration = try XCTUnwrap(model.durationInStage)
        XCTAssertEqual(duration, 2 * 86400 + 3 * 3600, accuracy: 0.01)
    }

    func test_ISO8601DurationParser_postgresFormats() {
        XCTAssertEqual(ISO8601DurationParser.parse("03:00:00"), 3 * 3600)
        XCTAssertEqual(ISO8601DurationParser.parse("1 day 12:00:00"), 86400 + 12 * 3600)
        XCTAssertEqual(ISO8601DurationParser.parse("2 days"), 2 * 86400)
        XCTAssertEqual(ISO8601DurationParser.parse("01:30:45"), 3600 + 30 * 60 + 45)
    }
}
