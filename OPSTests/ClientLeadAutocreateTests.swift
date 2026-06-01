//
//  ClientLeadAutocreateTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class ClientLeadAutocreateTests: XCTestCase {

    func testClientCreatedLeadUsesLiveSchemaAllowedSourceAndPriority() throws {
        let client = Client(
            id: "client-1",
            name: "  West Shore Decks  ",
            email: "ops@example.com",
            phoneNumber: "250-555-0199",
            address: "12 Bay St",
            companyId: "company-1"
        )

        let dto = try XCTUnwrap(
            ClientLeadAutocreate.makeOpportunityDTO(for: client, companyId: "company-1")
        )

        XCTAssertEqual(dto.companyId, "company-1")
        XCTAssertEqual(dto.contactName, "West Shore Decks")
        XCTAssertEqual(dto.title, "West Shore Decks — lead")
        XCTAssertEqual(dto.source, ClientLeadAutocreate.schemaAllowedSource)
        XCTAssertEqual(dto.source, "other")
        XCTAssertEqual(dto.clientId, "client-1")
        XCTAssertEqual(dto.priority, ClientLeadAutocreate.schemaAllowedPriority)
        XCTAssertEqual(dto.priority, "medium")
    }

    func testClientCreatedLeadPayloadDropsBlankOptionalFields() throws {
        let client = Client(
            id: "client-2",
            name: "North Ridge",
            email: "   ",
            phoneNumber: "",
            address: "  ",
            companyId: "company-1"
        )

        let dto = try XCTUnwrap(
            ClientLeadAutocreate.makeOpportunityDTO(for: client, companyId: "company-1")
        )

        XCTAssertNil(dto.contactEmail)
        XCTAssertNil(dto.contactPhone)
        XCTAssertNil(dto.address)
        XCTAssertNil(dto.description)
    }

    func testClientCreatedLeadSkipsBlankNames() {
        let client = Client(id: "client-3", name: "   ", companyId: "company-1")

        XCTAssertNil(ClientLeadAutocreate.makeOpportunityDTO(for: client, companyId: "company-1"))
    }
}
