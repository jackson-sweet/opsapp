//
//  LeadFormClientSeedTests.swift
//  OPSTests
//
//  The "new lead from a client's page" seed: LeadForm.init(fromClient:)
//  prefills the contact fields (and leaves the job blank for the operator).
//

import XCTest
@testable import OPS

final class LeadFormClientSeedTests: XCTestCase {

    func test_initFromClient_prefillsContactFields() {
        let client = Client(id: "cl1", name: "Calloway Homes")
        client.email = "hi@calloway.com"
        client.phoneNumber = "5551234567"
        client.address = "1240 Maple Ave"

        let form = LeadForm(fromClient: client)

        XCTAssertEqual(form.contactName, "Calloway Homes")
        XCTAssertEqual(form.email, "hi@calloway.com")
        XCTAssertEqual(form.phone, "5551234567")
        XCTAssertEqual(form.address, "1240 Maple Ave")
        XCTAssertEqual(form.title, "")          // job stays empty — operator fills it
        XCTAssertEqual(form.stage, .newLead)
    }

    func test_initFromClient_carriesCoordinatesWhenPresent() {
        let client = Client(id: "cl2", name: "Maple Corp")
        client.address = "1240 Maple Ave"
        client.latitude = 43.65
        client.longitude = -79.38

        let form = LeadForm(fromClient: client)

        XCTAssertEqual(form.latitude, 43.65)
        XCTAssertEqual(form.longitude, -79.38)
        XCTAssertEqual(form.lastResolvedAddress, "1240 Maple Ave")
    }

    // MARK: - Bug 55f40233 — the seed path and the pick path converge

    /// A lead opened from a client's page (`init(fromClient:)`) and a lead
    /// bound through USE EXISTING CLIENT (`adoptClient`) must land the operator
    /// in the SAME identity state — one bound state machine, not two. The only
    /// intended divergence is SOURCE: an explicit pick is a repeat customer
    /// calling about new work; the client-page seed keeps the form default.
    func test_adoptClient_matchesSeedIdentityAndSetsRepeatClientSource() {
        let client = Client(id: "cl3", name: "Calloway Homes")
        client.email = "hi@calloway.com"
        client.phoneNumber = "5551234567"
        client.address = "1240 Maple Ave"
        client.latitude = 43.65
        client.longitude = -79.38

        let seeded = LeadForm(fromClient: client)
        var adopted = LeadForm()
        adopted.adoptClient(client)

        XCTAssertEqual(adopted.contactName, seeded.contactName)
        XCTAssertEqual(adopted.email, seeded.email)
        XCTAssertEqual(adopted.phone, seeded.phone)
        XCTAssertEqual(adopted.address, seeded.address)
        XCTAssertEqual(adopted.latitude, seeded.latitude)
        XCTAssertEqual(adopted.longitude, seeded.longitude)
        XCTAssertEqual(adopted.lastResolvedAddress, seeded.lastResolvedAddress)

        XCTAssertEqual(adopted.source, "repeat_client")
        XCTAssertEqual(seeded.source, "website", "the client-page seed keeps the form default")
    }
}
