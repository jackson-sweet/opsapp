//
//  SiteVisitRecordChecklistTests.swift
//  OPSTests
//
//  Structured site-visit checklist metadata remains additive: current clients
//  get field anatomy while older clients keep the exact packet text they
//  already understand.
//

import XCTest
@testable import OPS

final class SiteVisitRecordChecklistTests: XCTestCase {

    private func answer(
        id: String,
        fieldId: String,
        label: String,
        kind: SiteVisitFieldKind,
        sortOrder: Int,
        value: SiteVisitChecklistValue
    ) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: id,
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: fieldId,
            label: label,
            kind: kind,
            required: false,
            sortOrder: sortOrder,
            answerValue: value,
            createdBy: "user-1"
        )
    }

    private func record(from metadata: SiteVisitPacketMetadata) -> SiteVisitRecord {
        SiteVisitRecord.assemble(
            metadata: metadata,
            photoURLs: [],
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            estimatedValue: nil,
            canViewFinancials: false
        )
    }

    func testPacketPreservesStructuredChecklistItemsAndExactLegacyContent() throws {
        let answers = [
            answer(
                id: "answer-access",
                fieldId: "access",
                label: "Access clear",
                kind: .yesNoNA,
                sortOrder: 10,
                value: .choice("yes")
            ),
            answer(
                id: "answer-notes",
                fieldId: "notes",
                label: "Gate notes",
                kind: .longText,
                sortOrder: 20,
                value: .text("Code: 4812 after hours")
            ),
            answer(
                id: "answer-height",
                fieldId: "height",
                label: "Height above grade",
                kind: .measurement,
                sortOrder: 30,
                value: .text("30 in")
            ),
            answer(
                id: "answer-photos",
                fieldId: "conditions",
                label: "Existing conditions",
                kind: .photo,
                sortOrder: 40,
                value: .artifacts(["photo-1", "photo-2"])
            )
        ]

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            address: "1100 Maple Ave",
            artifacts: [],
            checklistAnswers: answers
        )

        let legacyLines = [
            "CHECKLIST :: Access clear: YES",
            "CHECKLIST :: Gate notes: Code: 4812 after hours",
            "CHECKLIST :: Height above grade: 30 in",
            "CHECKLIST :: Existing conditions: 2 CAPTURED"
        ]
        XCTAssertEqual(payload.checklistLines, legacyLines)
        XCTAssertEqual(
            payload.checklistItems,
            [
                SiteVisitPacketChecklistItem(
                    fieldId: "access",
                    label: "Access clear",
                    value: "YES",
                    kind: SiteVisitFieldKind.yesNoNA.rawValue,
                    artifactCount: 0
                ),
                SiteVisitPacketChecklistItem(
                    fieldId: "notes",
                    label: "Gate notes",
                    value: "Code: 4812 after hours",
                    kind: SiteVisitFieldKind.longText.rawValue,
                    artifactCount: 0
                ),
                SiteVisitPacketChecklistItem(
                    fieldId: "height",
                    label: "Height above grade",
                    value: "30 in",
                    kind: SiteVisitFieldKind.measurement.rawValue,
                    artifactCount: 0
                ),
                SiteVisitPacketChecklistItem(
                    fieldId: "conditions",
                    label: "Existing conditions",
                    value: "2 CAPTURED",
                    kind: SiteVisitFieldKind.photo.rawValue,
                    artifactCount: 2
                )
            ]
        )

        let packet = try XCTUnwrap(SiteVisitPacketNote.build(artifacts: [], payload: payload))
        XCTAssertEqual(
            packet.content,
            "SITE VISIT PACKET\n\n" + legacyLines.joined(separator: "\n\n"),
            "The additive metadata must not rewrite the packet consumed by older clients."
        )

        let decoded = try XCTUnwrap(SiteVisitPacketMetadata.decode(from: packet.metadataJSON))
        XCTAssertEqual(decoded.checklist, legacyLines)
        XCTAssertEqual(decoded.checklistItems, payload.checklistItems)
    }

    func testRecordPrefersStructuredChecklistItemsOverLegacyStrings() throws {
        let metadata = try XCTUnwrap(SiteVisitPacketMetadata.decode(from: """
        {
          "checklist": ["CHECKLIST :: Wrong legacy label: stale"],
          "checklist_items": [
            {
              "field_id": "gate-notes",
              "label": "Gate notes",
              "value": "Code: 4812 after hours",
              "kind": "long_text",
              "artifact_count": 0
            }
          ]
        }
        """))

        XCTAssertEqual(
            record(from: metadata).checklistItems,
            [
                SiteVisitRecord.ChecklistItem(
                    fieldId: "gate-notes",
                    label: "Gate notes",
                    value: "Code: 4812 after hours",
                    kind: SiteVisitFieldKind.longText.rawValue,
                    artifactCount: 0
                )
            ]
        )
    }

    func testLegacyChecklistParserPreservesValuesContainingColons() throws {
        let metadata = try XCTUnwrap(SiteVisitPacketMetadata.decode(from: """
        {
          "checklist": [
            "CHECKLIST :: Gate notes: Code: 4812 after hours",
            "CHECKLIST :: Access clear: YES"
          ]
        }
        """))

        XCTAssertEqual(
            record(from: metadata).checklistItems,
            [
                SiteVisitRecord.ChecklistItem(
                    fieldId: nil,
                    label: "Gate notes",
                    value: "Code: 4812 after hours",
                    kind: nil,
                    artifactCount: 0
                ),
                SiteVisitRecord.ChecklistItem(
                    fieldId: nil,
                    label: "Access clear",
                    value: "YES",
                    kind: nil,
                    artifactCount: 0
                )
            ]
        )
    }

    func testMalformedStructuredChecklistFallsBackToLegacyWithoutInvalidatingPacket() throws {
        let metadata = try XCTUnwrap(SiteVisitPacketMetadata.decode(from: """
        {
          "photo_count": 2,
          "checklist": ["CHECKLIST :: Access clear: YES"],
          "checklist_items": [
            { "label": 17, "value": "YES", "kind": "yes_no_na" }
          ]
        }
        """))

        let subject = record(from: metadata)
        XCTAssertEqual(subject.photoCount, 2)
        XCTAssertEqual(
            subject.checklistItems,
            [
                SiteVisitRecord.ChecklistItem(
                    fieldId: nil,
                    label: "Access clear",
                    value: "YES",
                    kind: nil,
                    artifactCount: 0
                )
            ]
        )
    }

    func testMalformedLegacyChecklistLineRemainsVisibleAsValueOnly() throws {
        let metadata = try XCTUnwrap(SiteVisitPacketMetadata.decode(from: """
        { "checklist": ["CHECKLIST :: Walkthrough complete", "Original unprefixed answer"] }
        """))

        let items = record(from: metadata).checklistItems
        XCTAssertEqual(items.map(\.label), [nil, nil])
        XCTAssertEqual(items.map(\.value), ["Walkthrough complete", "Original unprefixed answer"])
    }

    func testRecordRetainsEveryPhotoURLForTheViewer() {
        let urls = (1...7).map { "file:///tmp/site-visit-photo-\($0).jpg" }
        let subject = SiteVisitRecord.assemble(
            metadata: SiteVisitPacketMetadata(
                siteVisitId: "visit-1",
                photoCount: urls.count,
                measurements: nil,
                notes: nil,
                checklist: nil,
                address: nil,
                contactName: nil,
                companyName: nil,
                deckDesignId: nil
            ),
            photoURLs: urls,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            estimatedValue: nil,
            canViewFinancials: false
        )

        XCTAssertEqual(subject.photoURLs, urls)
    }
}
