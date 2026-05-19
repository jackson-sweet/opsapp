//
//  CashflowForecastViewModelTests.swift
//  OPSTests
//
//  Layer-toggle persistence test for CashflowForecastViewModel. Does NOT
//  exercise the load() path — that requires Supabase. Engine math is tested
//  separately in CashflowForecastEngineTests.
//

import XCTest
@testable import OPS

@MainActor
final class CashflowForecastViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cashflow.layers.committed")
        defaults.removeObject(forKey: "cashflow.layers.contracted")
        defaults.removeObject(forKey: "cashflow.layers.pipeline")
        defaults.removeObject(forKey: "cashflow.layers.recurring")
        defaults.removeObject(forKey: "cashflow.horizonWeeks")
    }

    func testDefaultLayersAllOn() {
        let vm = CashflowForecastViewModel()
        XCTAssertTrue(vm.layerSet.contains(.committed))
        XCTAssertTrue(vm.layerSet.contains(.contracted))
        XCTAssertTrue(vm.layerSet.contains(.pipeline))
        XCTAssertTrue(vm.layerSet.contains(.recurring))
    }

    func testSetLayerTogglesIndividualLayer() {
        let vm = CashflowForecastViewModel()
        vm.setLayer(.pipeline, included: false)
        XCTAssertFalse(vm.layerSet.contains(.pipeline))
        XCTAssertTrue(vm.layerSet.contains(.committed))
        XCTAssertTrue(vm.layerSet.contains(.contracted))
        XCTAssertTrue(vm.layerSet.contains(.recurring))
    }

    func testSetupRebindsCompanyId() {
        let vm = CashflowForecastViewModel()
        XCTAssertEqual(vm.companyIdForExternalUse, "")
        vm.setup(companyId: "co-123", dashboardVM: MoneyDashboardViewModel())
        XCTAssertEqual(vm.companyIdForExternalUse, "co-123")
    }
}
