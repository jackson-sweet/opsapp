//
//  GuidedCatalogSetupProfileTests.swift
//  OPSTests
//
//  Pure-logic tests for BusinessProfile → setup-module derivation.
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupProfileTests: XCTestCase {

    // Cleaning company: services-only, hourly, track cost.
    func test_servicesOnly_yieldsServicesModuleOnly() {
        let p = BusinessProfile(sells: .services, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: true)
        XCTAssertEqual(p.setupModules, [.services])
        XCTAssertFalse(p.runStock)
        XCTAssertFalse(p.runAssemblies)
    }

    // Fencing co (Canpro): mix, all-in price, lots of parts, count stock, track cost.
    func test_fencingCo_leadsWithAssembly_includesStock() {
        let p = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                materialUse: .heavy, inventory: .tracked, trackCost: true)
        XCTAssertEqual(p.setupModules.first, .assembly) // hero leads
        XCTAssertTrue(p.setupModules.contains(.stock))
        XCTAssertTrue(p.runMaterials)
    }

    // Goods reseller: goods, line-item, no materials → goods only, no stock.
    func test_goodsLineItem_noMaterials_yieldsGoodsOnly() {
        let p = BusinessProfile(sells: .goods, pricing: .lineItem,
                                materialUse: .none, inventory: nil, trackCost: false)
        XCTAssertEqual(p.setupModules, [.goods])
    }

    // Cost-only materials (not tracked) → no stock module, but materials still on.
    func test_materialsCostOnly_noStockModule() {
        let p = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                materialUse: .some, inventory: .costOnly, trackCost: true)
        XCTAssertTrue(p.runMaterials)
        XCTAssertFalse(p.runStock)
    }

    // Safety floor: an incoherent combo never yields zero modules.
    func test_zeroModuleFloor() {
        let p = BusinessProfile(sells: .goods, pricing: .hourly,
                                materialUse: .none, inventory: nil, trackCost: false)
        XCTAssertFalse(p.setupModules.isEmpty)
    }

    // De-dup: assembly + services + goods never repeat a kind.
    func test_modulesAreUnique() {
        let p = BusinessProfile(sells: .mix, pricing: .mixed,
                                materialUse: .some, inventory: .tracked, trackCost: true)
        XCTAssertEqual(p.setupModules.count, Set(p.setupModules).count)
    }
}
