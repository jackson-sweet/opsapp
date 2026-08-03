import XCTest
@testable import OPS

final class SiteVisitDTOTests: XCTestCase {
    private let visitId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let companyId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
    private let opportunityId = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
    private let userId = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"

    func testParentDecodesSnakeCaseFractionalDatesAndCanonicalizesUUIDs() throws {
        let data = Data("""
        {
          "id": "\(visitId)",
          "company_id": "\(companyId)",
          "opportunity_id": "\(opportunityId)",
          "project_id": "LEGACY-PROJECT",
          "project_ref": null,
          "client_id": null,
          "client_ref": null,
          "scheduled_at": "2026-07-31T18:12:45.123456+00:00",
          "duration_minutes": 75,
          "assignee_ids": ["\(userId)"],
          "status": "in_progress",
          "completed_at": null,
          "notes": "Front elevation",
          "internal_notes": null,
          "measurements": null,
          "photos": [],
          "activity_id": null,
          "calendar_event_id": null,
          "created_by": "\(userId)",
          "created_at": "2026-07-31T18:12:45Z",
          "updated_at": "2026-07-31T18:13:00.000001Z",
          "deleted_at": null
        }
        """.utf8)

        let dto = try JSONDecoder().decode(SiteVisitDTO.self, from: data)

        XCTAssertEqual(dto.id, visitId.lowercased())
        XCTAssertEqual(dto.companyId, companyId.lowercased())
        XCTAssertEqual(dto.opportunityId, opportunityId.lowercased())
        XCTAssertEqual(dto.projectId, "legacy-project")
        XCTAssertEqual(dto.assigneeIds, [userId.lowercased()])
        XCTAssertEqual(dto.status, .inProgress)
        XCTAssertEqual(dto.durationMinutes, 75)
        XCTAssertNotNil(dto.scheduledAt)
        XCTAssertNotNil(dto.updatedAt)
    }

    func testParentLegacyOptionalFieldsMayBeAbsent() throws {
        let data = Data("""
        {
          "id": "\(visitId)",
          "company_id": "\(companyId)",
          "scheduled_at": "2026-07-31T18:12:45Z",
          "status": "scheduled",
          "created_by": "\(userId)"
        }
        """.utf8)

        let dto = try JSONDecoder().decode(SiteVisitDTO.self, from: data)

        XCTAssertEqual(dto.durationMinutes, 60)
        XCTAssertEqual(dto.assigneeIds, [])
        XCTAssertEqual(dto.photos, [])
        XCTAssertNil(dto.createdAt)
        XCTAssertNil(dto.updatedAt)
    }

    func testMalformedRequiredUUIDStatusAndDateAreRejected() {
        let invalidRows = [
            "{\"id\":\"not-a-uuid\",\"company_id\":\"\(companyId)\",\"scheduled_at\":\"2026-07-31T18:12:45Z\",\"status\":\"scheduled\",\"created_by\":\"\(userId)\"}",
            "{\"id\":\"\(visitId)\",\"company_id\":\"\(companyId)\",\"scheduled_at\":\"2026-07-31T18:12:45Z\",\"status\":\"unknown\",\"created_by\":\"\(userId)\"}",
            "{\"id\":\"\(visitId)\",\"company_id\":\"\(companyId)\",\"scheduled_at\":\"not-a-date\",\"status\":\"scheduled\",\"created_by\":\"\(userId)\"}",
        ]

        for row in invalidRows {
            XCTAssertThrowsError(try JSONDecoder().decode(SiteVisitDTO.self, from: Data(row.utf8)))
        }
    }

    func testChecklistAnswerValuePreservesEveryCurrentShape() throws {
        let value = SiteVisitChecklistValue(
            text: "12 ft by 18 ft",
            boolValue: false,
            choice: "na",
            artifactIds: ["AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA01"],
            deckDesignId: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA02"
        )
        let answer = SiteVisitChecklistAnswer(
            id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA03",
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: opportunityId,
            siteVisitTypeId: "system-estimate",
            fieldId: "measurements",
            label: "Measurements",
            kind: .measurement,
            required: true,
            helpText: "Overall dimensions",
            sortOrder: 10,
            answerValue: value,
            createdBy: userId
        )

        let payload = try UpsertSiteVisitChecklistAnswerDTO(model: answer)
        let encoded = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let answerValue = try XCTUnwrap(object["answer_value"] as? [String: Any])

        XCTAssertEqual(answerValue["text"] as? String, "12 ft by 18 ft")
        XCTAssertEqual(answerValue["boolValue"] as? Bool, false)
        XCTAssertEqual(answerValue["choice"] as? String, "na")
        XCTAssertEqual(answerValue["artifactIds"] as? [String], ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01"])
        XCTAssertEqual(answerValue["deckDesignId"] as? String, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02")

        let dto = try JSONDecoder().decode(SiteVisitChecklistAnswerDTO.self, from: encoded)
        XCTAssertEqual(dto.answerValue, payload.answerValue)
    }

    func testIdentityPayloadNeverEncodesLocalSearchText() throws {
        let draft = SiteVisitIdentityDraft(
            id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA04",
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: opportunityId,
            searchText: "private local search",
            clientName: "North Shore Roofing",
            preferredEmail: "ops@example.com",
            createdBy: userId
        )

        let payload = try UpsertSiteVisitIdentityDraftDTO(model: draft)
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.contains("searchText"))
        XCTAssertFalse(json.contains("search_text"))
        XCTAssertFalse(json.contains("private local search"))
        XCTAssertTrue(json.contains("client_name"))
    }

    func testArtifactDimensionsUseExistingCompatibilityDecoder() throws {
        let data = Data("""
        {
          "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA05",
          "site_visit_id": "\(visitId)",
          "company_id": "\(companyId)",
          "opportunity_id": "\(opportunityId)",
          "kind": "dimensioned_photo",
          "source": "lidar",
          "asset_url": "https://cdn.ops.test/original.heic",
          "rendered_asset_url": "https://cdn.ops.test/rendered.png",
          "dimensions": {
            "schema_version": 1,
            "capture_mode": "lidar",
            "calibration": {"method":"lidar","scale_factor":1,"estimated_accuracy_meters":0.01},
            "intrinsics": {"fx":1,"fy":1,"cx":0,"cy":0,"image_width":100,"image_height":100},
            "measurements": [],
            "openings": []
          },
          "included_in_project_review": true,
          "captured_at": "2026-07-31T18:12:45.123456Z",
          "created_by": "\(userId)",
          "created_at": "2026-07-31T18:12:45Z",
          "updated_at": "2026-07-31T18:12:45Z"
        }
        """.utf8)

        let dto = try JSONDecoder().decode(SiteVisitArtifactDTO.self, from: data)

        XCTAssertEqual(dto.dimensions?.captureMode, .lidar)
        XCTAssertEqual(dto.dimensions?.intrinsics.imageWidth, 100)
        XCTAssertEqual(dto.kind, .dimensionedPhoto)
        XCTAssertEqual(dto.source, .lidar)
    }

    func testCreatePayloadRequiresScheduledAtAndCreatedBy() throws {
        let missingActor = SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertThrowsError(try CreateSiteVisitDTO(model: missingActor))

        let visit = SiteVisit(
            id: visitId,
            opportunityId: opportunityId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1),
            createdBy: userId
        )
        let payload = try CreateSiteVisitDTO(model: visit)
        XCTAssertEqual(payload.id, visitId.lowercased())
        XCTAssertEqual(payload.companyId, companyId.lowercased())
        XCTAssertEqual(payload.createdBy, userId.lowercased())
        XCTAssertEqual(payload.status, .inProgress)
    }
}
