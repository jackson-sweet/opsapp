//
//  GuidedCatalogSetupSurveyTests.swift
//  OPSTests
//
//  Branching + finalize tests for the diagnostic survey.
//

import XCTest
@testable import OPS

final class GuidedCatalogSetupSurveyTests: XCTestCase {

    func test_servicesPath_skipsMaterialsAndStock() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.services), to: &a)
        XCTAssertEqual(SurveyFlow.next(after: .sells, answers: a), .pricing)
        SurveyFlow.apply(.pricing(.hourly), to: &a)
        XCTAssertEqual(SurveyFlow.next(after: .pricing, answers: a), .trackCost)
    }

    func test_goodsPath_asksMaterials() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.goods), to: &a)
        SurveyFlow.apply(.pricing(.lineItem), to: &a)
        XCTAssertEqual(SurveyFlow.next(after: .pricing, answers: a), .materials)
    }

    func test_noMaterials_skipsStock() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.goods), to: &a)
        SurveyFlow.apply(.materialUse(.none), to: &a)
        XCTAssertEqual(SurveyFlow.next(after: .materials, answers: a), .trackCost)
    }

    func test_materials_asksStock() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.materialUse(.heavy), to: &a)
        XCTAssertEqual(SurveyFlow.next(after: .materials, answers: a), .stock)
    }

    func test_finalize_fencingCo() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.mix), to: &a)
        SurveyFlow.apply(.pricing(.fixedJob), to: &a)
        SurveyFlow.apply(.materialUse(.heavy), to: &a)
        SurveyFlow.apply(.inventory(.tracked), to: &a)
        SurveyFlow.apply(.trackCost(true), to: &a)
        XCTAssertEqual(SurveyFlow.finalize(a),
                       BusinessProfile(sells: .mix, pricing: .fixedJob,
                                       materialUse: .heavy, inventory: .tracked, trackCost: true))
    }

    func test_finalize_incomplete_returnsNil() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.services), to: &a)
        XCTAssertNil(SurveyFlow.finalize(a))
    }

    func test_finalize_servicesOnly_inventoryNil() {
        var a = SurveyAnswers()
        SurveyFlow.apply(.sells(.services), to: &a)
        SurveyFlow.apply(.pricing(.hourly), to: &a)
        SurveyFlow.apply(.trackCost(true), to: &a)
        let p = SurveyFlow.finalize(a)
        XCTAssertEqual(p?.materialUse, BusinessMaterialUse.none)
        XCTAssertNil(p?.inventory)
    }
}
