//
//  ProjectAutoNamerTests.swift
//  OPSTests
//
//  Regression coverage for the client-side mirror of the server's
//  `private.derive_project_name` (projects_autoname trigger). The two MUST
//  stay in lockstep: the preview iOS shows before conversion has to match
//  the name the server derives after it.
//

import XCTest
@testable import OPS

final class ProjectAutoNamerTests: XCTestCase {

    // MARK: - Comma-separated addresses (canonical autocomplete output)

    func testCommaAddressUsesStreetLineBeforeFirstComma() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "972 Lyall St, Esquimalt, BC V9A 5E8", clientName: nil),
            "972 Lyall St"
        )
    }

    func testCommaAddressTrimsWhitespace() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "  1075 Pandora Ave ,  Victoria", clientName: "Maverick"),
            "1075 Pandora Ave"
        )
    }

    // MARK: - Comma-less addresses (hand-typed; bug bbc2d228)

    func testCommalessAddressExtractsCivicNumberPlusStreet() {
        // The live failure: title became the entire string because the server
        // split on a comma that wasn't there.
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "972 Lyall St Esquimalt BC V9A 5E8", clientName: nil),
            "972 Lyall St"
        )
    }

    func testCommalessMultiWordStreetName() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "3040 Cedar Hill Rd Victoria BC", clientName: nil),
            "3040 Cedar Hill Rd"
        )
    }

    func testCommalessKeepsDirectionalSuffix() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "123 8th Ave SW Calgary AB", clientName: nil),
            "123 8th Ave SW"
        )
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "88 King St W Toronto ON", clientName: nil),
            "88 King St W"
        )
    }

    func testCommalessKeepsUnitPrefixes() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "4-972 Lyall St Esquimalt", clientName: nil),
            "4-972 Lyall St"
        )
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "Unit 4 972 Lyall St Esquimalt", clientName: nil),
            "Unit 4 972 Lyall St"
        )
    }

    func testCommalessLongFormStreetType() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "972 Lyall Street Esquimalt", clientName: nil),
            "972 Lyall Street"
        )
    }

    func testCommalessIsCaseInsensitiveAndPreservesTypedCasing() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "972 lyall st esquimalt bc", clientName: nil),
            "972 lyall st"
        )
    }

    func testCommalessWithoutRecognizableStreetFallsBackToFullAddress() {
        // No civic number / street suffix — same behavior as the server today:
        // the whole trimmed address becomes the name.
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "Acreage behind the old mill", clientName: nil),
            "Acreage behind the old mill"
        )
    }

    // MARK: - Fallback chain (mirrors derive_project_name exactly)

    func testBlankAddressFallsBackToClientPossessive() {
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: "   ", clientName: "Maverick Exteriors"),
            "Maverick Exteriors's Project"
        )
        XCTAssertEqual(
            ProjectAutoNamer.derive(address: nil, clientName: " Dana "),
            "Dana's Project"
        )
    }

    func testNoAddressNoClientFallsBackToNewProject() {
        XCTAssertEqual(ProjectAutoNamer.derive(address: nil, clientName: nil), "New project")
        XCTAssertEqual(ProjectAutoNamer.derive(address: "", clientName: "  "), "New project")
    }

    // MARK: - Address canonicalization (comma-less → comma form)

    /// The server's LIVE derive_project_name only splits on commas. iOS
    /// canonicalizes hand-typed comma-less addresses at the persistence
    /// boundary so the server derives the same street-line name we preview.
    func testCanonicalizeInsertsCommaAfterStreetLine() {
        XCTAssertEqual(
            ProjectAutoNamer.canonicalizedAddress("972 Lyall St Esquimalt BC V9A 5E8"),
            "972 Lyall St, Esquimalt BC V9A 5E8"
        )
        XCTAssertEqual(
            ProjectAutoNamer.canonicalizedAddress("3040 Cedar Hill Rd Victoria BC"),
            "3040 Cedar Hill Rd, Victoria BC"
        )
    }

    func testCanonicalizeLeavesCommaAddressesUntouched() {
        XCTAssertEqual(
            ProjectAutoNamer.canonicalizedAddress("972 Lyall St, Esquimalt, BC"),
            "972 Lyall St, Esquimalt, BC"
        )
    }

    func testCanonicalizeLeavesBareStreetLineUntouched() {
        XCTAssertEqual(ProjectAutoNamer.canonicalizedAddress("972 Lyall St"), "972 Lyall St")
    }

    func testCanonicalizeLeavesUnrecognizableAddressesUntouched() {
        XCTAssertEqual(
            ProjectAutoNamer.canonicalizedAddress("Acreage behind the old mill"),
            "Acreage behind the old mill"
        )
    }

    func testCanonicalizeIsIdempotent() {
        let once = ProjectAutoNamer.canonicalizedAddress("972 Lyall St Esquimalt BC")
        XCTAssertEqual(ProjectAutoNamer.canonicalizedAddress(once), once)
    }
}
