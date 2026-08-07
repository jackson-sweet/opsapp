//
//  SiteVisitPacketNoteTests.swift
//  OPSTests
//
//  Bug 7649fd48 — the site-visit packet posts one structured system note
//  (event_kind = site_visit) whose content_metadata drives the rich feed
//  card + detail sheet, while content keeps the legacy plain-text packet
//  so web and older builds render unchanged.
//

import XCTest
@testable import OPS

final class SiteVisitPacketNoteTests: XCTestCase {

    private func artifact(
        kind: SiteVisitCaptureArtifactKind,
        title: String? = nil,
        body: String? = nil,
        capturedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            siteVisitId: "sv-1",
            companyId: "c1",
            kind: kind,
            source: .camera,
            title: title,
            body: body,
            capturedAt: capturedAt
        )
    }

    private func payload(checklistLines: [String] = []) -> SiteVisitProjectPayload {
        SiteVisitProjectPayload(
            siteVisitId: "sv-1",
            opportunityId: "opp-1",
            address: "123 Main St",
            photoArtifactIds: [],
            measurementArtifactIds: [],
            noteArtifactIds: [],
            deckDesignIds: [],
            checklistAnswerIds: [],
            checklistLines: checklistLines
        )
    }

    func testBuildsStructuredMetadataAndLegacyContent() throws {
        let artifacts = [
            artifact(kind: .photo),
            artifact(kind: .photo),
            artifact(kind: .measurement, title: "Deck width", body: "14 ft 6 in"),
            artifact(kind: .note, body: "Client wants composite boards"),
            artifact(kind: .transcript, body: "Walkthrough recording summary"),
        ]
        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: artifacts,
            payload: payload(checklistLines: ["Power on site — yes"])
        ))

        // Legacy content preserved for web/older builds.
        XCTAssertTrue(packet.content.hasPrefix("SITE VISIT PACKET"))
        XCTAssertTrue(packet.content.contains("MEASURE :: 14 ft 6 in"))
        XCTAssertTrue(packet.content.contains("Client wants composite boards"))
        XCTAssertTrue(packet.content.contains("Power on site — yes"))

        // Structured metadata for the rich card + sheet.
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(packet.metadataJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(metadata["site_visit_id"] as? String, "sv-1")
        XCTAssertEqual(metadata["photo_count"] as? Int, 2)
        let measurements = try XCTUnwrap(metadata["measurements"] as? [[String: String]])
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements.first?["label"], "Deck width")
        XCTAssertEqual(measurements.first?["value"], "14 ft 6 in")
        let notes = try XCTUnwrap(metadata["notes"] as? [String])
        XCTAssertEqual(notes, ["Client wants composite boards", "Walkthrough recording summary"])
        let checklist = try XCTUnwrap(metadata["checklist"] as? [String])
        XCTAssertEqual(checklist, ["Power on site — yes"])
    }

    func testPhotoOnlyPacketStillBuildsForTheFeedCard() throws {
        // A visit that captured only photos previously produced NO packet note
        // (noteLines empty) — the feed showed nothing about the visit. The
        // packet entry now exists whenever the visit captured anything.
        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: [artifact(kind: .photo)],
            payload: payload()
        ))
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(packet.metadataJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(metadata["photo_count"] as? Int, 1)
        XCTAssertTrue(packet.content.hasPrefix("SITE VISIT PACKET"))
    }

    func testEmptyPacketBuildsNothing() {
        XCTAssertNil(SiteVisitPacketNote.build(artifacts: [], payload: payload()))
    }

    func testMeasurementWithoutTitleFallsBackToGenericLabel() throws {
        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: [artifact(kind: .measurement, title: nil, body: "22 ft")],
            payload: payload()
        ))
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(packet.metadataJSON.utf8)) as? [String: Any]
        )
        let measurements = try XCTUnwrap(metadata["measurements"] as? [[String: String]])
        XCTAssertEqual(measurements.first?["label"], "Measurement")
        XCTAssertEqual(measurements.first?["value"], "22 ft")
    }

    // MARK: - Money never travels in the packet

    /// `content_metadata` is a SYNCED blob on `project_notes`. OPS-Web reads
    /// that column with no financial gate of its own, so anything money-shaped
    /// written here is money published to every viewer of the web activity
    /// feed — the exact leak the record's `finances.view` gate exists to
    /// prevent. The lead's value is therefore resolved at render time from the
    /// local opportunity and never authored into the packet.
    ///
    /// Asserted as an allowlist rather than a single absent key: a future
    /// `deck_price` or `quote_total` would slip past a `estimated_value` check
    /// and leak just the same.
    func testPacketMetadataCarriesNoMoney() throws {
        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: [
                artifact(kind: .photo),
                artifact(kind: .measurement, title: "Deck width", body: "14 ft 6 in"),
                artifact(kind: .note, body: "Client wants composite boards")
            ],
            payload: payload(checklistLines: ["Power on site — yes"])
        ))
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(packet.metadataJSON.utf8)) as? [String: Any]
        )

        let permitted: Set<String> = [
            "site_visit_id", "photo_count", "measurements", "notes",
            "checklist", "checklist_items", "address", "contact_name", "company_name", "deck_design_id"
        ]
        XCTAssertTrue(
            Set(metadata.keys).isSubset(of: permitted),
            "Unlisted key in the synced packet: \(Set(metadata.keys).subtracting(permitted)). Every key here is published to the web activity feed ungated — money must never be one of them."
        )
        XCTAssertFalse(
            metadata.keys.contains("estimated_value"),
            "The lead's value must be resolved at render time behind finances.view, never synced in the packet."
        )
    }

    /// The legacy plain-text half of the packet syncs to the same ungated
    /// column pair — a currency figure in `content` would leak exactly as hard.
    func testLegacyPacketContentCarriesNoCurrencyFigure() throws {
        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: [artifact(kind: .measurement, title: "Deck width", body: "14 ft 6 in")],
            payload: payload()
        ))
        XCTAssertFalse(packet.content.contains("$"))
    }

    func testExcludesInactiveAndExcludedArtifacts() throws {
        let excluded = artifact(kind: .note, body: "should not appear")
        excluded.includedInProjectReview = false
        let deleted = artifact(kind: .note, body: "deleted note")
        deleted.deletedAt = Date()

        let packet = try XCTUnwrap(SiteVisitPacketNote.build(
            artifacts: [excluded, deleted, artifact(kind: .note, body: "kept")],
            payload: payload()
        ))
        XCTAssertFalse(packet.content.contains("should not appear"))
        XCTAssertFalse(packet.content.contains("deleted note"))
        XCTAssertTrue(packet.content.contains("kept"))
    }
}
