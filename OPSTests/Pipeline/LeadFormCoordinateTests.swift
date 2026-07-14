//
//  LeadFormCoordinateTests.swift
//  OPSTests
//
//  Coordinates ride the address in the lead form: set by an autocomplete
//  selection / reverse geocode, kept while the text still matches the string
//  they were resolved for, and cleared the moment the operator hand-edits.
//  Stale coords must never outlive a changed address.
//

import XCTest
@testable import OPS

final class LeadFormCoordinateTests: XCTestCase {

    private func opportunity(
        address: String? = "1240 Maple Ave",
        latitude: Double? = 48.4284,
        longitude: Double? = -123.3656
    ) -> Opportunity {
        let opp = Opportunity(
            id: "aaaaaaaa-0000-0000-0000-000000000001",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway"
        )
        opp.address = address
        opp.latitude = latitude
        opp.longitude = longitude
        return opp
    }

    func test_HydratedForm_keepsCoordinates_whileAddressUntouched() {
        var form = LeadForm(from: opportunity())

        // The onChange fires once with the unchanged string in real usage —
        // that must NOT clear coords.
        form.addressTextChanged("1240 Maple Ave")

        XCTAssertEqual(form.latitude, 48.4284)
        XCTAssertEqual(form.longitude, -123.3656)
    }

    func test_ManualEdit_clearsCoordinates() {
        var form = LeadForm(from: opportunity())

        form.address = "1240 Maple Av"      // deleted a character
        form.addressTextChanged("1240 Maple Av")

        XCTAssertNil(form.latitude)
        XCTAssertNil(form.longitude)
    }

    func test_Selection_resolvesCoordinates_andSurvivesItsOwnOnChange() {
        var form = LeadForm(from: opportunity(address: nil, latitude: nil, longitude: nil))

        // Autocomplete select: binding updates first (onChange fires), THEN
        // onAddressSelected resolves. Simulate that exact order.
        form.address = "972 Lyall St, Esquimalt"
        form.addressTextChanged("972 Lyall St, Esquimalt")
        form.addressResolved("972 Lyall St, Esquimalt", latitude: 48.43, longitude: -123.41)

        XCTAssertEqual(form.latitude, 48.43)
        XCTAssertEqual(form.longitude, -123.41)

        // Typing over the resolved string clears them again.
        form.address = "972 Lyall St, Esquimalt B"
        form.addressTextChanged("972 Lyall St, Esquimalt B")
        XCTAssertNil(form.latitude)
        XCTAssertNil(form.longitude)
    }

    func test_ClearingAddress_clearsCoordinates() {
        var form = LeadForm(from: opportunity())

        form.address = ""
        form.addressTextChanged("")

        XCTAssertNil(form.latitude)
        XCTAssertNil(form.longitude)
    }
}
