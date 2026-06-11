//
//  GuidedCatalogSetupAssemblyTests.swift
//  OPSTests
//
//  Assembly cost + margin math, and summary pluralization with packages.
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupAssemblyTests: XCTestCase {

    @MainActor
    private func makeModel() -> GuidedCatalogSetupModel {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcs-asm-\(UUID().uuidString)", isDirectory: true)
        return GuidedCatalogSetupModel(companyId: "c", userId: "u",
                                       draftStore: GuidedCatalogSetupDraftStore(rootURL: tmp))
    }

    @MainActor
    func test_assemblyCost_sumsMaterialsAndLabor() {
        let m = makeModel()
        let materials = [
            AssemblyMaterialDraft(name: "Rail", costText: "10", qtyText: "5"),  // 50
            AssemblyMaterialDraft(name: "Post", costText: "8", qtyText: "4")     // 32
        ]
        let labor = [
            AssemblyLaborDraft(name: "Install", sellText: "60", costText: "30", hoursText: "8") // 240
        ]
        XCTAssertEqual(m.assemblyCost(materials: materials, labor: labor), 322, accuracy: 0.001)
    }

    @MainActor
    func test_assemblyMarginPercent() {
        let m = makeModel()
        let materials = [AssemblyMaterialDraft(name: "Rail", costText: "100", qtyText: "1")] // 100
        let labor = [AssemblyLaborDraft(name: "Install", sellText: "0", costText: "100", hoursText: "1")] // 100
        // cost 200, price 500 → (500-200)/500 = 60%
        XCTAssertEqual(m.assemblyMarginPercent(priceText: "500", materials: materials, labor: labor) ?? -1,
                       60, accuracy: 0.001)
    }

    @MainActor
    func test_assemblyMargin_nilWhenNoPrice() {
        let m = makeModel()
        XCTAssertNil(m.assemblyMarginPercent(priceText: "", materials: [], labor: []))
    }

    func test_summaryLine_includesAssemblies() {
        XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 0, goods: 0, assemblies: 1), "1 package")
        XCTAssertEqual(GuidedCatalogSetupModel.summaryLine(services: 1, goods: 0, assemblies: 2),
                       "2 packages · 1 service")
    }
}
