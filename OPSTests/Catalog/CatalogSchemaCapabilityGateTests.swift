//
//  CatalogSchemaCapabilityGateTests.swift
//  OPSTests
//
//  Tests for the pure classifier and resolver in CatalogSchemaCapabilityGate.
//  Network probes are not tested here (they require a live client); only the
//  deterministic logic that maps errors to probe results and probe results to
//  stored booleans is exercised.
//

import XCTest
@testable import OPS

final class CatalogSchemaCapabilityGateTests: XCTestCase {

    // MARK: - classifyProbeError

    func test_classify_urlError_isUnknown() {
        XCTAssertEqual(CatalogSchemaCapabilityGate.classifyProbeError(URLError(.timedOut)), .unknown)
        XCTAssertEqual(CatalogSchemaCapabilityGate.classifyProbeError(URLError(.notConnectedToInternet)), .unknown)
    }

    func test_classify_missingTableMessage_isMissing() {
        let err = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "relation \"catalog_stock_units\" does not exist"]
        )
        XCTAssertEqual(CatalogSchemaCapabilityGate.classifyProbeError(err), .missing)
    }

    func test_classify_opaqueServerError_isUnknown_notMissing() {
        let err = NSError(
            domain: "PostgrestError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "internal server error"]
        )
        XCTAssertEqual(CatalogSchemaCapabilityGate.classifyProbeError(err), .unknown)
    }

    // MARK: - resolveCapability

    func test_resolveCapability_unknownRetainsLastKnown() {
        XCTAssertTrue(CatalogSchemaCapabilityGate.resolveCapability(probe: .unknown, lastKnown: true))
        XCTAssertFalse(CatalogSchemaCapabilityGate.resolveCapability(probe: .unknown, lastKnown: false))
    }

    func test_resolveCapability_availableAndMissingAreDefinitive() {
        XCTAssertTrue(CatalogSchemaCapabilityGate.resolveCapability(probe: .available, lastKnown: false))
        XCTAssertFalse(CatalogSchemaCapabilityGate.resolveCapability(probe: .missing, lastKnown: true))
    }
}
