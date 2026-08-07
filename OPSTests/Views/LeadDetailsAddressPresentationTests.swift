//
//  LeadDetailsAddressPresentationTests.swift
//  OPSTests
//
//  Regression coverage for the Lead Details ADDRESS row. The row must retain
//  the real site string, avoid a false directions affordance for blank data,
//  and keep OPS's canonical empty value.
//

import XCTest
@testable import OPS

final class LeadDetailsAddressPresentationTests: XCTestCase {
    func test_populatedAddressIsTrimmedAndRoutable() {
        let result = LeadDetailsAddressPresentation.resolve(
            "  1240 Maple Avenue, Victoria  "
        )

        XCTAssertEqual(result, .routable("1240 Maple Avenue, Victoria"))
        XCTAssertEqual(result.displayValue, "1240 Maple Avenue, Victoria")
    }

    func test_nilAndWhitespaceAddressesRenderDashWithoutDirections() {
        for address in [nil, "", "   \n  "] as [String?] {
            let result = LeadDetailsAddressPresentation.resolve(address)

            XCTAssertEqual(result, .empty)
            XCTAssertEqual(result.displayValue, "—")
        }
    }

    func test_directionsURLPreservesQueryCharactersAndFallsBackToCoordinates() throws {
        let addressURL = LeadDetailsAddressPresentation.directionsURL(
            address: "  12 A & B Road, Victoria  ",
            latitude: 48.1,
            longitude: -123.2
        )
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(addressURL), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "daddr" })?
                .value,
            "12 A & B Road, Victoria"
        )

        let coordinateURL = LeadDetailsAddressPresentation.directionsURL(
            address: " \n ",
            latitude: 48.4284,
            longitude: -123.3656
        )
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(coordinateURL), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "daddr" })?
                .value,
            "48.4284,-123.3656"
        )
    }
}
