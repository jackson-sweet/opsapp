//
//  GuidedCatalogSetupModelTests.swift
//  OPSTests
//
//  Draft-store round-trip + GuidedCatalogSetupModel navigation/summary tests.
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupModelTests: XCTestCase {

    // MARK: - Draft persistence (Task 2)

    func test_draftStore_roundTripsAndClears() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuidedCatalogSetupDraftTests-\(UUID().uuidString)", isDirectory: true)
        let store = GuidedCatalogSetupDraftStore(rootURL: tmp)
        let context = CatalogSetupDraftContext(companyId: "co1", userId: "u1", scope: "catalog-guided")

        let snapshot = GuidedCatalogSetupDraftSnapshot(
            context: context,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000), // whole second → iso8601 round-trips exactly
            phase: .module(index: 1),
            profile: BusinessProfile(sells: .mix, pricing: .fixedJob,
                                     materialUse: .some, inventory: .costOnly, trackCost: true),
            productLines: [ProductLineDraft(id: "d1", kind: .service, name: "Install labor",
                                            sellText: "120", costText: "60")],
            savedLines: [SavedProductLine(id: "abc", name: "Install labor", kind: .service, sell: 120)]
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(context: context), snapshot)

        try store.clear(context: context)
        XCTAssertNil(try store.load(context: context))
    }

    func test_draftStore_scopeIsolation_returnsNilForOtherScope() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuidedCatalogSetupDraftTests-\(UUID().uuidString)", isDirectory: true)
        let store = GuidedCatalogSetupDraftStore(rootURL: tmp)
        let saved = CatalogSetupDraftContext(companyId: "co1", userId: "u1", scope: "catalog-guided")
        let other = CatalogSetupDraftContext(companyId: "co1", userId: "u1", scope: "guided")

        try store.save(.init(context: saved, updatedAt: Date(timeIntervalSince1970: 0),
                             phase: .plan, profile: nil, productLines: [], savedLines: []))
        XCTAssertNotNil(try store.load(context: saved))
        XCTAssertNil(try store.load(context: other))
    }

    // MARK: - Model navigation + summary (Task 3)

    @MainActor private func makeModel() -> GuidedCatalogSetupModel {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcs-model-\(UUID().uuidString)", isDirectory: true)
        return GuidedCatalogSetupModel(companyId: "c", userId: "u",
                                       draftStore: GuidedCatalogSetupDraftStore(rootURL: tmp))
    }

    @MainActor
    func test_confirmPlan_entersFirstModule() {
        let m = makeModel()
        m.profile = BusinessProfile(sells: .services, pricing: .hourly,
                                    materialUse: .none, inventory: nil, trackCost: true)
        m.confirmPlan()
        XCTAssertEqual(m.modules, [.services])
        XCTAssertEqual(m.phase, .module(index: 0))
    }

    @MainActor
    func test_advanceModule_reachesDoneAfterLast() {
        let m = makeModel()
        m.profile = BusinessProfile(sells: .services, pricing: .hourly,
                                    materialUse: .none, inventory: nil, trackCost: true)
        m.confirmPlan()
        m.advanceModule()
        XCTAssertEqual(m.phase, .done)
    }

    func test_summaryLine_pluralization() {
        XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 1, goods: 0), "1 service")
        XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 2, goods: 3), "2 services · 3 goods")
        XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 0, goods: 0), "Nothing built")
    }

    // MARK: - Default unit seeding

    func test_missingDefaultUnits_skipsExistingCaseInsensitive() {
        let ft = CatalogUnit(companyId: "c", display: "ft", dimension: "length")
        let missing = GuidedCatalogSetupModel.missingDefaultUnits(existing: [ft])
        XCTAssertFalse(missing.contains { $0.display == "FT" })          // existing ft not re-seeded
        XCTAssertTrue(missing.contains { $0.display == "HR" })           // still seeds the rest
        XCTAssertEqual(missing.count, GuidedCatalogSetupModel.defaultUnitPack.count - 1)
    }

    func test_missingDefaultUnits_emptyCompany_seedsWholePack() {
        XCTAssertEqual(GuidedCatalogSetupModel.missingDefaultUnits(existing: []).count,
                       GuidedCatalogSetupModel.defaultUnitPack.count)
    }
}
