//
//  ClientLeadAutocreateTests.swift
//  OPSTests
//
//  Bug 44db2ea4 — CREATE LEAD was dead in the BOOK VISIT and log-activity
//  flows, and said so in Postgres.
//
//  The inline "New Lead" mini-forms sent `source: "log_activity"`. The live
//  `opportunities_source_check` has never permitted that value, so the insert
//  was refused every single time — prod holds zero opportunities with that
//  source, meaning not one lead created through those forms has ever landed
//  since the code shipped. The sheet then rendered the constraint violation
//  verbatim into the form, which is the exact thing SyncStatusCopy's founding
//  rule forbids: a field user never sees a raw database error.
//
//  The fix is conformance, not a widened constraint. `ClientLeadAutocreate` is
//  the single client mirror of the database vocabulary, and every inline form
//  builds through its factory — so no form can invent a source again.
//
//  What is locked here: the allowlist itself (against the live constraint), the
//  clamp, the factory, and — the regression test that would have caught this —
//  that every source `UnifiedLogActivityViewModel` can produce is one the
//  database actually accepts.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ClientLeadAutocreateFactoryTests: XCTestCase {

    private typealias Autocreate = ClientLeadAutocreate

    // MARK: - The vocabulary

    /// Verbatim from the live constraint (verified against prod 2026-08-31):
    /// CHECK (source = ANY (ARRAY['referral','website','email','phone',
    /// 'walk_in','social_media','repeat_client','voice_log','other'])).
    /// If a migration ever changes it, this fails and the mirror gets updated
    /// in the same commit — which is the whole point of keeping one.
    func testPermittedSourcesMirrorsTheLiveConstraint() {
        XCTAssertEqual(
            Autocreate.permittedSources,
            [
                "referral", "website", "email", "phone", "walk_in",
                "social_media", "repeat_client", "voice_log", "other",
            ]
        )
        XCTAssertFalse(
            Autocreate.permittedSources.contains("log_activity"),
            "The value that broke every inline lead create"
        )
        XCTAssertTrue(
            Autocreate.permittedSources.contains(Autocreate.schemaAllowedSource),
            "The standing default must itself be legal"
        )
    }

    // MARK: - The clamp

    func testConformedSourcePassesEveryLegalValueThrough() {
        for source in Autocreate.permittedSources {
            XCTAssertEqual(
                Autocreate.conformedSource(source),
                source,
                "A legal source must survive unchanged"
            )
        }
    }

    func testConformedSourceClampsAnythingTheDatabaseWouldRefuse() {
        XCTAssertEqual(Autocreate.conformedSource("log_activity"), "other")
        XCTAssertEqual(Autocreate.conformedSource("site_visit"), "other")
        XCTAssertEqual(Autocreate.conformedSource(""), "other")
        XCTAssertEqual(Autocreate.conformedSource("PHONE"), "other", "The contract is lowercase")
        XCTAssertEqual(Autocreate.conformedSource(nil), "other")
    }

    // MARK: - The factory

    func testInlineLeadDTOConformsAnUnspecifiedSource() throws {
        let dto = try XCTUnwrap(
            Autocreate.makeInlineLeadDTO(name: "Frank Williams", email: nil, phone: nil)
        )
        XCTAssertEqual(dto.source, Autocreate.schemaAllowedSource)
        XCTAssertEqual(dto.contactName, "Frank Williams")
    }

    func testInlineLeadDTOConformsAnIllegalSource() throws {
        let dto = try XCTUnwrap(
            Autocreate.makeInlineLeadDTO(
                name: "Frank Williams",
                email: nil,
                phone: nil,
                source: "log_activity"
            )
        )
        XCTAssertEqual(dto.source, "other", "The form's word never reaches the database unchecked")
    }

    func testInlineLeadDTOKeepsALegalSource() throws {
        let dto = try XCTUnwrap(
            Autocreate.makeInlineLeadDTO(
                name: "Frank Williams",
                email: nil,
                phone: nil,
                source: "phone"
            )
        )
        XCTAssertEqual(dto.source, "phone")
    }

    /// The reporter's own screenshot: Frank Williams / +1 250 858-1916.
    func testInlineLeadDTOTrimsAndNilsBlankContactDetails() throws {
        let dto = try XCTUnwrap(
            Autocreate.makeInlineLeadDTO(
                name: "  Frank Williams  ",
                email: "   ",
                phone: "  +1 250 858-1916 "
            )
        )
        XCTAssertEqual(dto.contactName, "Frank Williams")
        XCTAssertNil(dto.contactEmail, "A blank field is absent, not an empty string")
        XCTAssertEqual(dto.contactPhone, "+1 250 858-1916")
        // Title falls back to the contact name — the inline form collects no title.
        XCTAssertEqual(dto.title, "Frank Williams")
        XCTAssertNil(dto.clientId, "An inline lead has no customer record behind it yet")
    }

    func testInlineLeadDTORefusesANamelessLead() {
        XCTAssertNil(Autocreate.makeInlineLeadDTO(name: "", email: nil, phone: nil))
        XCTAssertNil(Autocreate.makeInlineLeadDTO(name: "   \n ", email: "a@b.co", phone: "555"))
    }

    // MARK: - The regression that would have caught it

    /// Every source the unified log sheet can stamp on an inline lead must be
    /// one the database accepts. This is the assertion whose absence let
    /// `"log_activity"` ship and fail silently in the field.
    func testEveryUnifiedLogEntryProducesADatabaseLegalSource() throws {
        let entries: [UnifiedLogActivityViewModel.Entry] = [
            .genericFAB,
            .capture(.fab),
            .capture(.appShortcut),
            .capture(.postCallPrompt),
            .capture(.autoOutbound),
            .postCall(PendingOutboundCall(
                opportunityId: "opp-99",
                contactName: "Maria Chen",
                phoneNumber: "6045550142",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )),
            .leadDetail(Opportunity(
                id: "opp-1",
                companyId: "co-1",
                contactName: "Eric Devlin",
                stage: .quoting
            ))
        ]

        for entry in entries {
            let viewModel = UnifiedLogActivityViewModel(entry: entry)
            let source = viewModel.newLeadSource
            XCTAssertTrue(
                Autocreate.permittedSources.contains(source),
                "\(source) is not in the opportunities_source_check allowlist"
            )
        }
    }

    /// The dial paths keep `phone` — legal, and truer than the generic default.
    func testDialEntriesStayAttributedToThePhone() {
        XCTAssertEqual(
            UnifiedLogActivityViewModel(entry: .capture(.fab)).newLeadSource,
            "phone"
        )
        XCTAssertEqual(
            UnifiedLogActivityViewModel(entry: .genericFAB).newLeadSource,
            Autocreate.schemaAllowedSource
        )
    }
}
