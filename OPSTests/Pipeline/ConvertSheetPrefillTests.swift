//
//  ConvertSheetPrefillTests.swift
//  OPSTests
//
//  Bug a7df1f37 — the convert sheet prefilled its ADDRESS field from the
//  opportunity alone. A lead created from a client page routinely carries no
//  address of its own while the linked client record holds one, so the server
//  preflight answered `address_required` and the sheet demanded the operator
//  retype an address the system already had.
//
//  The prefill now falls back to the linked client, and says so: a value
//  sourced from the client is TAGGED before the operator commits, because the
//  create path writes the visible address back onto the opportunity.
//
//  The lead summary card gets the same treatment for contact identity — an
//  opportunity with empty contact fields shows the client's name and phone
//  instead of a bare em dash.
//

import XCTest
@testable import OPS

final class ConvertSheetPrefillTests: XCTestCase {

    // MARK: - Address

    /// The lead's own address is authoritative. A client address must never
    /// silently displace an address the operator already put on the lead.
    func testOpportunityAddressWinsAndIsNotTaggedAsClientSourced() {
        let prefill = ConvertToProjectSheet.addressPrefill(
            opportunityAddress: "3998 Holland Ave, Victoria BC",
            opportunityLatitude: 48.46,
            opportunityLongitude: -123.37,
            clientAddress: "12 Douglas St, Victoria BC",
            clientLatitude: 48.42,
            clientLongitude: -123.36
        )

        XCTAssertEqual(prefill.text, "3998 Holland Ave, Victoria BC")
        XCTAssertEqual(prefill.latitude, 48.46)
        XCTAssertEqual(prefill.longitude, -123.37)
        XCTAssertFalse(prefill.isFromClient)
    }

    /// The regression: a lead with no address of its own inherits the client's,
    /// coordinates included, and the field is marked as client-sourced.
    func testBlankOpportunityAddressInheritsTheClientAddressAndIsTagged() {
        let prefill = ConvertToProjectSheet.addressPrefill(
            opportunityAddress: "   ",
            opportunityLatitude: nil,
            opportunityLongitude: nil,
            clientAddress: "12 Douglas St, Victoria BC",
            clientLatitude: 48.42,
            clientLongitude: -123.36
        )

        XCTAssertEqual(prefill.text, "12 Douglas St, Victoria BC")
        XCTAssertEqual(prefill.latitude, 48.42)
        XCTAssertEqual(prefill.longitude, -123.36)
        XCTAssertTrue(prefill.isFromClient)
    }

    /// Coordinates travel with the address they were resolved for, or not at
    /// all — a client address with no geo must not borrow the lead's.
    func testClientAddressWithoutCoordinatesCarriesNoCoordinates() {
        let prefill = ConvertToProjectSheet.addressPrefill(
            opportunityAddress: nil,
            opportunityLatitude: 48.46,
            opportunityLongitude: -123.37,
            clientAddress: "12 Douglas St",
            clientLatitude: nil,
            clientLongitude: nil
        )

        XCTAssertEqual(prefill.text, "12 Douglas St")
        XCTAssertNil(prefill.latitude)
        XCTAssertNil(prefill.longitude)
        XCTAssertTrue(prefill.isFromClient)
    }

    /// Neither side has an address — nothing is prefilled and nothing is
    /// claimed to come from the client.
    func testNoAddressAnywhereLeavesTheFieldEmptyAndUntagged() {
        let prefill = ConvertToProjectSheet.addressPrefill(
            opportunityAddress: nil,
            opportunityLatitude: nil,
            opportunityLongitude: nil,
            clientAddress: "  ",
            clientLatitude: 48.42,
            clientLongitude: -123.36
        )

        XCTAssertEqual(prefill.text, "")
        XCTAssertNil(prefill.latitude)
        XCTAssertNil(prefill.longitude)
        XCTAssertFalse(prefill.isFromClient)
    }

    // MARK: - Lead summary contact

    /// A lead whose contact fields were never filled in still identifies its
    /// human — the client record already knows who this is.
    func testEmptyOpportunityContactFallsBackToTheClientRecord() {
        let contact = ConvertToProjectSheet.leadSummaryContact(
            opportunityName: "",
            opportunityPhone: nil,
            clientName: "Calloway Homes",
            clientPhone: "250-555-0142"
        )

        XCTAssertEqual(contact.name, "Calloway Homes")
        XCTAssertEqual(contact.phone, "250-555-0142")
    }

    /// The lead's own contact details stay authoritative when present.
    func testOpportunityContactWinsOverTheClientRecord() {
        let contact = ConvertToProjectSheet.leadSummaryContact(
            opportunityName: "Helen Calloway",
            opportunityPhone: "250-555-0199",
            clientName: "Calloway Homes",
            clientPhone: "250-555-0142"
        )

        XCTAssertEqual(contact.name, "Helen Calloway")
        XCTAssertEqual(contact.phone, "250-555-0199")
    }

    /// Fields fall back independently — a lead can carry a name without a
    /// phone and still borrow the client's number.
    func testContactFieldsFallBackIndependently() {
        let contact = ConvertToProjectSheet.leadSummaryContact(
            opportunityName: "Helen Calloway",
            opportunityPhone: "  ",
            clientName: "Calloway Homes",
            clientPhone: "250-555-0142"
        )

        XCTAssertEqual(contact.name, "Helen Calloway")
        XCTAssertEqual(contact.phone, "250-555-0142")
    }

    /// Nothing anywhere renders the canonical empty state, never a blank line.
    func testNoContactAnywhereRendersTheEmptyDash() {
        let contact = ConvertToProjectSheet.leadSummaryContact(
            opportunityName: "",
            opportunityPhone: nil,
            clientName: nil,
            clientPhone: nil
        )

        XCTAssertEqual(contact.name, "—")
        XCTAssertNil(contact.phone)
    }
}
