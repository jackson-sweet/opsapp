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
}
