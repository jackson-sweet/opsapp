//
//  SiteVisitRecordTests.swift
//  OPSTests
//
//  The SITE VISIT RECORD is what a visit captured, assembled once and rendered
//  two ways (compact row on a timeline, full sheet behind it). These tests pin
//  the assembly rules, because everything visual downstream depends on them:
//
//   - sections appear ONLY when they hold content (ruthless omission — the
//     record never renders empty scaffolding for a section that captured
//     nothing);
//   - the capture tally reads as the operator's own shorthand
//     ("4 PHOTOS · 2 MEASUREMENTS · DECK");
//   - and — the hard requirement — every value denominated in currency is
//     OMITTED ENTIRELY for a viewer without financial visibility. Not masked,
//     not blurred, not a placeholder: absent, leaving no gap that advertises
//     hidden money.
//
//  The value itself is handed to the assembler by the surface, resolved from
//  the LOCAL opportunity at render time. It is deliberately not carried in the
//  visit's synced packet: `project_notes.content_metadata` crosses to OPS-Web,
//  which applies no financial gate of its own, so a number written there would
//  be published past the very permission this gate enforces.
//

import XCTest
@testable import OPS

final class SiteVisitRecordTests: XCTestCase {

    private func metadata(
        photoCount: Int? = nil,
        measurements: [SiteVisitPacketMetadata.Measurement]? = nil,
        notes: [String]? = nil,
        checklist: [String]? = nil,
        address: String? = nil,
        contactName: String? = nil,
        companyName: String? = nil,
        deckDesignId: String? = nil
    ) -> SiteVisitPacketMetadata {
        SiteVisitPacketMetadata(
            siteVisitId: "visit-1",
            photoCount: photoCount,
            measurements: measurements,
            notes: notes,
            checklist: checklist,
            address: address,
            contactName: contactName,
            companyName: companyName,
            deckDesignId: deckDesignId
        )
    }

    private func record(
        _ meta: SiteVisitPacketMetadata,
        photoURLs: [String] = [],
        estimatedValue: Double? = nil,
        canViewFinancials: Bool = true
    ) -> SiteVisitRecord {
        SiteVisitRecord.assemble(
            metadata: meta,
            photoURLs: photoURLs,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            estimatedValue: estimatedValue,
            canViewFinancials: canViewFinancials
        )
    }

    // MARK: - Financial gating (the hard requirement)

    func test_value_isOmittedEntirely_forAViewerWithoutFinancialVisibility() {
        let subject = record(metadata(), estimatedValue: 18_400, canViewFinancials: false)
        XCTAssertNil(subject.value,
                     "Crew without pricing visibility must never receive the number — not masked, absent.")
        XCTAssertFalse(subject.sections.contains(.value),
                       "The VALUE section must not render at all, so no gap advertises hidden money.")
    }

    func test_value_isPresent_forAViewerWithFinancialVisibility() {
        let subject = record(metadata(), estimatedValue: 18_400, canViewFinancials: true)
        XCTAssertEqual(subject.value, "$18,400")
        XCTAssertTrue(subject.sections.contains(.value))
    }

    func test_noValueSection_whenTheVisitCarriesNoMoneyAtAll() {
        let subject = record(metadata(photoCount: 2), canViewFinancials: true)
        XCTAssertNil(subject.value,
                     "Permission grants visibility; it does not invent a value that was never captured.")
        XCTAssertFalse(subject.sections.contains(.value))
    }

    /// The number is resolved from the local opportunity at render time, never
    /// read out of the visit's packet — because the packet syncs to a column
    /// OPS-Web renders with no financial gate. A record built from a fully
    /// populated packet and no locally resolved value therefore shows no money,
    /// no matter how cleared the viewer is.
    func test_value_comesFromTheLiveOpportunity_notTheSyncedPacket() {
        let full = metadata(
            photoCount: 3,
            measurements: [.init(label: "Deck", value: "12' x 16'")],
            notes: ["Gate code 4417"],
            checklist: ["Deck design"],
            address: "1100 Maple Ave",
            contactName: "Helen Calloway",
            companyName: "Calloway Ltd",
            deckDesignId: "design-1"
        )
        let unresolved = record(full, estimatedValue: nil, canViewFinancials: true)
        XCTAssertNil(unresolved.value,
                     "A packet cannot supply the value — only the local opportunity can.")
        XCTAssertFalse(unresolved.sections.contains(.value))

        let resolved = record(full, estimatedValue: 18_400, canViewFinancials: true)
        XCTAssertEqual(resolved.value, "$18,400")
        XCTAssertEqual(
            resolved.sections.subtracting([.value]),
            unresolved.sections,
            "Resolving the value adds the money line and disturbs nothing else."
        )
    }

    func test_value_isOmitted_whenTheOpportunityCarriesZero() {
        XCTAssertNil(record(metadata(), estimatedValue: 0, canViewFinancials: true).value,
                     "A lead worth nothing yet has no value to show — zero is not a figure.")
    }

    func test_everyOtherSectionIsIdentical_acrossBothPermissionStates() {
        let meta = metadata(
            photoCount: 3,
            measurements: [.init(label: "Deck", value: "12' x 16'")],
            notes: ["Gate code 4417"],
            checklist: ["Deck design"],
            address: "1100 Maple Ave",
            contactName: "Helen Calloway"
        )
        let permitted = record(meta, estimatedValue: 18_400, canViewFinancials: true)
        let restricted = record(meta, estimatedValue: 18_400, canViewFinancials: false)

        XCTAssertEqual(
            permitted.sections.subtracting([.value]),
            restricted.sections,
            "Hiding money must not disturb anything else the visit captured."
        )
        XCTAssertEqual(permitted.summaryLine, restricted.summaryLine,
                       "The capture tally counts evidence, never money — it reads the same for everyone.")
    }

    // MARK: - Ruthless omission

    func test_anEmptyVisitRendersNoSections() {
        XCTAssertTrue(record(metadata()).sections.isEmpty,
                      "A record with nothing captured renders no scaffolding.")
    }

    func test_photoSectionAppearsOnlyWithPhotos() {
        XCTAssertFalse(record(metadata()).sections.contains(.photos))
        XCTAssertTrue(record(metadata(photoCount: 1), photoURLs: ["a.jpg"]).sections.contains(.photos))
    }

    func test_measurementsSectionAppearsOnlyWithMeasurements() {
        XCTAssertFalse(record(metadata(measurements: [])).sections.contains(.measurements))
        XCTAssertTrue(
            record(metadata(measurements: [.init(label: "Deck", value: "12' x 16'")]))
                .sections.contains(.measurements)
        )
    }

    func test_identitySectionAppearsOnlyWhenSomebodyWasNamed() {
        XCTAssertFalse(record(metadata()).sections.contains(.identity))
        XCTAssertTrue(record(metadata(contactName: "Helen Calloway")).sections.contains(.identity))
        XCTAssertTrue(record(metadata(companyName: "Calloway Ltd")).sections.contains(.identity))
    }

    func test_identityLine_joinsThePersonAndTheBusinessWhenBothExist() {
        XCTAssertEqual(
            record(metadata(contactName: "Helen Calloway", companyName: "Calloway Ltd")).identityLine,
            "HELEN CALLOWAY · CALLOWAY LTD"
        )
        XCTAssertEqual(record(metadata(contactName: "Helen Calloway")).identityLine, "HELEN CALLOWAY")
        XCTAssertEqual(record(metadata(companyName: "Calloway Ltd")).identityLine, "CALLOWAY LTD")
    }

    func test_deckSectionAppearsOnlyWhenADesignIsAttached() {
        XCTAssertFalse(record(metadata()).sections.contains(.deck))
        XCTAssertTrue(record(metadata(deckDesignId: "design-1")).sections.contains(.deck))
    }

    // MARK: - Capture tally

    func test_summaryLine_readsAsTheOperatorsShorthand() {
        let subject = record(metadata(
            photoCount: 4,
            measurements: [
                .init(label: "Deck", value: "12' x 16'"),
                .init(label: "Stairs", value: "4 risers")
            ],
            deckDesignId: "design-1"
        ))
        XCTAssertEqual(subject.summaryLine, "4 PHOTOS · 2 MEASUREMENTS · DECK")
    }

    func test_summaryLine_singularizesACountOfOne() {
        XCTAssertEqual(
            record(metadata(photoCount: 1, measurements: [.init(label: "Deck", value: "12'")])).summaryLine,
            "1 PHOTO · 1 MEASUREMENT"
        )
    }

    func test_summaryLine_isNilWhenNothingWasCaptured() {
        XCTAssertNil(record(metadata()).summaryLine,
                     "Nothing captured means no tally line — not an empty string sitting in the row.")
    }

    // MARK: - Photo strip

    func test_photoStrip_showsTheFirstFourAndCountsTheRemainder() {
        let subject = record(
            metadata(photoCount: 7),
            photoURLs: (1...7).map { "photo-\($0).jpg" }
        )
        XCTAssertEqual(subject.visiblePhotoURLs.count, 4)
        XCTAssertEqual(subject.additionalPhotoCount, 3, "The rest collapse into a +N tile.")
    }

    func test_photoStrip_hasNoOverflowTileWhenEverythingFits() {
        let subject = record(metadata(photoCount: 3), photoURLs: ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(subject.visiblePhotoURLs.count, 3)
        XCTAssertEqual(subject.additionalPhotoCount, 0)
    }

    /// The count comes from the metadata (written at capture, device-independent);
    /// the thumbnails come from synced project photos, which may not have landed
    /// on this device yet. The tally must still be honest.
    func test_photoCountSurvives_evenWhenNoThumbnailsHaveSyncedYet() {
        let subject = record(metadata(photoCount: 5), photoURLs: [])
        XCTAssertEqual(subject.photoCount, 5)
        XCTAssertEqual(subject.summaryLine, "5 PHOTOS")
        XCTAssertTrue(subject.visiblePhotoURLs.isEmpty)
    }
}
