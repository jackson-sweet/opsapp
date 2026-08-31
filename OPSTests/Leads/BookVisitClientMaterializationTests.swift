//
//  BookVisitClientMaterializationTests.swift
//  OPSTests
//
//  Bug 55f40233 / f8951223 — the FAB's BOOK VISIT lane lists open leads AND
//  existing clients. Booking is opportunity-anchored (`book_site_visit` takes
//  `p_opportunity_id`), so a client tap must first resolve to a bookable lead:
//  the newest still-open linked lead when one exists, else a fresh
//  `repeat_client` lead bound to that client.
//
//  These exercise the PRODUCTION helpers the picker calls — not copies of the
//  logic — so the tested behavior and the shipped behavior cannot drift.
//

import XCTest
@testable import OPS

final class BookVisitClientMaterializationTests: XCTestCase {

    private static let companyId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    // MARK: - Fixtures

    private func makeLead(
        id: String,
        stage: PipelineStage,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil
    ) -> Opportunity {
        let lead = Opportunity(
            id: id,
            companyId: Self.companyId,
            contactName: "Dana Rowe",
            stage: stage
        )
        lead.deletedAt = deletedAt
        lead.archivedAt = archivedAt
        return lead
    }

    private func makeClient(
        id: String = "dddddddd-dddd-dddd-dddd-dddddddddddd",
        name: String = "Dana Rowe",
        email: String? = "dana@example.com",
        phone: String? = "+15555550123",
        address: String? = "18 Alder Way, Squamish, BC",
        latitude: Double? = 49.7016,
        longitude: Double? = -123.1558
    ) -> Client {
        let client = Client(
            id: id,
            name: name,
            email: email,
            phoneNumber: phone,
            address: address,
            companyId: Self.companyId
        )
        client.latitude = latitude
        client.longitude = longitude
        return client
    }

    // MARK: - Which rows the booking lane offers

    /// Leads and clients are both bookable entry points; jobs are not — a
    /// booking anchors to an opportunity, and a job's own lead is reachable
    /// from the job's action bar instead (bug 7d94c9f3).
    func testLeadsOnlyTargetsIncludeClientsExcludeProjects() {
        let lead = ActivityTarget.opportunity(makeLead(id: "lead-1", stage: .qualifying))
        let client = ActivityTarget.client(makeClient())
        let project = ActivityTarget.project(
            Project(id: "job-1", title: "Cedar deck rebuild", status: .inProgress)
        )

        XCTAssertTrue(ActivityTargetPickerView.leadsOnlyFilter(lead))
        XCTAssertTrue(
            ActivityTargetPickerView.leadsOnlyFilter(client),
            "a repeat customer must be bookable — this is the bug"
        )
        XCTAssertFalse(ActivityTargetPickerView.leadsOnlyFilter(project))
        XCTAssertFalse(ActivityTargetPickerView.leadsOnlyFilter(.unbound))
    }

    /// The filter is what `loadTargets` runs, so a mixed list reduces to
    /// exactly the bookable rows in their original order.
    func testLeadsOnlyFilterReducesAMixedList() {
        let targets: [ActivityTarget] = [
            .opportunity(makeLead(id: "lead-1", stage: .qualifying)),
            .project(Project(id: "job-1", title: "Cedar deck", status: .inProgress)),
            .client(makeClient()),
            .unbound
        ]

        let kept = targets.filter(ActivityTargetPickerView.leadsOnlyFilter)

        XCTAssertEqual(kept.count, 2)
        guard case .opportunity = kept[0] else { return XCTFail("expected the lead first") }
        guard case .client = kept[1] else { return XCTFail("expected the client second") }
    }

    // MARK: - Resolving the client's bookable lead

    /// The newest OPEN lead wins. Terminal, deleted, and archived rows are
    /// finished business and must never be handed to the booking sheet — the
    /// list arrives newest-first from `fetchAllLinked`.
    func testOpenLeadPredicatePicksFirstNonTerminal() {
        let models = [
            makeLead(id: "deleted", stage: .qualifying, deletedAt: Date()),
            makeLead(id: "won", stage: .won),
            makeLead(id: "archived", stage: .quoting, archivedAt: Date()),
            makeLead(id: "open", stage: .quoting),
            makeLead(id: "older-open", stage: .newLead)
        ]

        XCTAssertEqual(
            ActivityTargetPickerView.firstOpenLead(in: models)?.id,
            "open",
            "the newest open lead wins; deleted/won/archived rows are skipped"
        )
    }

    /// A client whose every lead is closed gets nil — the caller then mints a
    /// fresh `repeat_client` lead, which is the honest pipeline record for a
    /// repeat customer's new job.
    func testAllTerminalLeadsYieldNil() {
        let models = [
            makeLead(id: "won", stage: .won),
            makeLead(id: "lost", stage: .lost),
            makeLead(id: "discarded", stage: .discarded)
        ]

        XCTAssertNil(ActivityTargetPickerView.firstOpenLead(in: models))
    }

    /// A client with no leads at all yields nil.
    func testEmptyLeadListYieldsNil() {
        XCTAssertNil(ActivityTargetPickerView.firstOpenLead(in: []))
    }

    /// A deleted row is skipped even when its stage is open — soft-deleted
    /// leads are gone as far as every surface is concerned.
    func testDeletedOpenLeadIsSkipped() {
        let models = [makeLead(id: "deleted-open", stage: .qualifying, deletedAt: Date())]
        XCTAssertNil(ActivityTargetPickerView.firstOpenLead(in: models))
    }

    // MARK: - The materialized lead's payload

    /// The fresh lead carries the client's identity so the booking sheet, the
    /// pipeline, and the site visit all describe the same customer. `source`
    /// must be a value the live `opportunities_source_check` constraint
    /// allows — `repeat_client` is both legal and semantically exact.
    func testRepeatClientDTOCarriesClientIdentity() throws {
        let dto = ActivityTargetPickerView.materializationDTO(for: makeClient())

        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["source"] as? String, "repeat_client")
        XCTAssertEqual(json["client_id"] as? String, "dddddddd-dddd-dddd-dddd-dddddddddddd")
        XCTAssertEqual(json["contact_name"] as? String, "Dana Rowe")
        XCTAssertEqual(json["contact_email"] as? String, "dana@example.com")
        XCTAssertEqual(json["contact_phone"] as? String, "+15555550123")
        XCTAssertEqual(json["address"] as? String, "18 Alder Way, Squamish, BC")
        XCTAssertEqual(json["latitude"] as? Double, 49.7016)
        XCTAssertEqual(json["longitude"] as? Double, -123.1558)
    }

    /// `repeat_client` is one of the nine values the live constraint permits.
    /// A regression here fails the INSERT server-side with a CHECK violation,
    /// which surfaces to the operator as an opaque create rejection.
    func testMaterializationSourceIsSchemaAllowed() {
        let allowed: Set<String> = [
            "referral", "website", "email", "phone", "walk_in",
            "social_media", "repeat_client", "voice_log", "other"
        ]
        let source = ActivityTargetPickerView.materializationDTO(for: makeClient()).source

        XCTAssertEqual(source, "repeat_client")
        XCTAssertTrue(
            allowed.contains(source ?? ""),
            "the materialized lead's source must be one the live "
                + "opportunities_source_check constraint permits"
        )
    }

    /// A client carrying no contact details still produces a valid lead: the
    /// nil fields are omitted (never sent as null) and the title falls back to
    /// the contact name, so the guarded create has everything it requires.
    func testSparseClientStillProducesAValidLead() throws {
        let sparse = makeClient(
            name: "Winona Keys",
            email: nil,
            phone: nil,
            address: nil,
            latitude: nil,
            longitude: nil
        )

        let data = try JSONEncoder().encode(
            ActivityTargetPickerView.materializationDTO(for: sparse)
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["contact_name"] as? String, "Winona Keys")
        XCTAssertEqual(json["title"] as? String, "Winona Keys")
        XCTAssertEqual(json["source"] as? String, "repeat_client")
        for absent in ["contact_email", "contact_phone", "address", "latitude", "longitude"] {
            XCTAssertNil(json[absent], "\(absent) must be omitted, not null")
        }
    }
}
