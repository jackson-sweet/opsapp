//
//  SiteVisitIdentityRequirementsTests.swift
//  OPSTests
//
//  COMPANY is not a requirement. Most site visits are residential — the
//  operator met a person at a house, and there is no business to name. The
//  form used to tag COMPANY with the same REQUIRED marker as NAME (both read
//  the shared name-or-company predicate), so a homeowner visit showed a
//  requirement the operator could never satisfy honestly.
//
//  These tests pin the real rule: a lead needs an identity (a person's name,
//  or a business when the business IS the client), a way to reach them (email
//  OR phone), and a site address. COMPANY is optional — always.
//

import XCTest
@testable import OPS

final class SiteVisitIdentityRequirementsTests: XCTestCase {

    private func resolve(
        name: String = "",
        company: String = "",
        email: String = "",
        additionalEmails: String = "",
        phone: String = "",
        address: String = ""
    ) -> SiteVisitIdentityRequirements {
        SiteVisitIdentityRequirements.resolve(
            name: name,
            company: company,
            email: email,
            additionalEmails: additionalEmails,
            phone: phone,
            address: address
        )
    }

    // MARK: - COMPANY is optional

    func test_company_isOptional_whenNothingHasBeenEntered() {
        XCTAssertEqual(resolve().company, .optional,
                       "COMPANY must never advertise a requirement — a residential visit has no business to name.")
    }

    func test_company_staysOptional_evenOnAFullyCompletedForm() {
        let requirements = resolve(
            name: "Dale Harmon",
            email: "dale@example.com",
            address: "1100 Maple Ave"
        )
        XCTAssertEqual(requirements.company, .optional,
                       "A complete lead with no company is complete — COMPANY stays optional throughout.")
    }

    // MARK: - NAME carries the identity requirement

    func test_name_isRequired_andOutstandingWhenNoIdentityExists() {
        XCTAssertEqual(resolve().name, .required(satisfied: false))
    }

    func test_name_isSatisfied_byThePersonsName() {
        XCTAssertEqual(resolve(name: "Dale Harmon").name, .required(satisfied: true))
    }

    func test_name_isSatisfied_byACompanyWhenTheBusinessIsTheClient() {
        // A commercial visit can legitimately carry only the business name.
        // The identity requirement is satisfied; COMPANY still never shows a marker.
        let requirements = resolve(company: "Harmon Roofing")
        XCTAssertEqual(requirements.name, .required(satisfied: true),
                       "A business name is a valid identity — it satisfies the requirement.")
        XCTAssertEqual(requirements.company, .optional)
    }

    // MARK: - Contact method stays required (WS-A's server gate depends on it)

    func test_contactMethod_isOutstanding_untilAnEmailOrPhoneArrives() {
        let requirements = resolve(name: "Dale Harmon")
        XCTAssertEqual(requirements.email, .required(satisfied: false))
        XCTAssertEqual(requirements.phone, .required(satisfied: false))
    }

    func test_contactMethod_isSatisfied_byPhoneAlone() {
        let requirements = resolve(name: "Dale Harmon", phone: "555-0134")
        XCTAssertEqual(requirements.email, .required(satisfied: true))
        XCTAssertEqual(requirements.phone, .required(satisfied: true))
    }

    func test_contactMethod_isSatisfied_byAnAdditionalEmailAlone() {
        let requirements = resolve(name: "Dale Harmon", additionalEmails: "ops@example.com")
        XCTAssertEqual(requirements.email, .required(satisfied: true))
    }

    // MARK: - Address stays required

    func test_address_isRequired_andSatisfiedOnlyByAnAddress() {
        XCTAssertEqual(resolve().address, .required(satisfied: false))
        XCTAssertEqual(resolve(address: "1100 Maple Ave").address, .required(satisfied: true))
    }

    // MARK: - Whitespace is not an answer

    func test_whitespaceOnlyEntriesDoNotSatisfyAnything() {
        let requirements = resolve(name: "   ", company: "\n", phone: "  ", address: "\t")
        XCTAssertEqual(requirements.name, .required(satisfied: false))
        XCTAssertEqual(requirements.phone, .required(satisfied: false))
        XCTAssertEqual(requirements.address, .required(satisfied: false))
    }
}
