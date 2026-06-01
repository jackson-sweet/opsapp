import XCTest
@testable import OPS

final class GuidedStockDraftBuilderTests: XCTestCase {

    private func group(single: Bool, attributes: [GuidedAttribute]) -> GuidedStructuredGroup {
        GuidedStructuredGroup(familyName: "Vinyl", memberItemIds: ["a", "b"], isSingleItem: single, attributes: attributes, isConfirmed: true)
    }

    func test_singleItem_hasNoAttributes_andOneVariant() {
        let g = group(single: true, attributes: [])
        XCTAssertTrue(GuidedStockDraftBuilder.attributeDrafts(for: g).isEmpty)
        let variants = GuidedStockDraftBuilder.variantDrafts(for: g)
        XCTAssertEqual(variants.count, 1)
        XCTAssertTrue(variants[0].optionValueIds.isEmpty)
        XCTAssertEqual(GuidedStockDraftBuilder.variantCount(for: g), 1)
    }

    func test_oneDimension_threeValues_threeVariants() {
        let g = group(single: false, attributes: [GuidedAttribute(name: "Color", values: ["black", "white", "grey"])])
        let attrs = GuidedStockDraftBuilder.attributeDrafts(for: g)
        XCTAssertEqual(attrs.count, 1)
        XCTAssertEqual(attrs[0].name, "Color")
        XCTAssertEqual(attrs[0].values.map(\.value), ["black", "white", "grey"])
        XCTAssertEqual(GuidedStockDraftBuilder.variantCount(for: g), 3)
    }

    func test_twoDimensions_multiplyVariants() {
        let g = group(single: false, attributes: [
            GuidedAttribute(name: "Color", values: ["black", "white"]),
            GuidedAttribute(name: "Width", values: ["6ft", "8ft"])
        ])
        XCTAssertEqual(GuidedStockDraftBuilder.attributeDrafts(for: g).count, 2)
        XCTAssertEqual(GuidedStockDraftBuilder.variantCount(for: g), 4)
    }

    func test_ids_areDeterministic_acrossRebuilds() {
        let g = group(single: false, attributes: [GuidedAttribute(id: "attr-color", name: "Color", values: ["black", "white"])])
        let a1 = GuidedStockDraftBuilder.attributeDrafts(for: g)
        let a2 = GuidedStockDraftBuilder.attributeDrafts(for: g)
        XCTAssertEqual(a1.map(\.id), a2.map(\.id))
        XCTAssertEqual(a1.flatMap { $0.values.map(\.id) }, a2.flatMap { $0.values.map(\.id) })
        XCTAssertEqual(a1[0].values.map(\.id), ["attr-color::black", "attr-color::white"])
        let v1 = GuidedStockDraftBuilder.variantDrafts(for: g).map(\.id)
        let v2 = GuidedStockDraftBuilder.variantDrafts(for: g).map(\.id)
        XCTAssertEqual(v1, v2)   // stable variant signatures
    }

    func test_emptyAndBlankAttributesAreDropped() {
        let g = group(single: false, attributes: [
            GuidedAttribute(name: "Color", values: ["black", "  ", ""]),
            GuidedAttribute(name: "  ", values: ["x"])
        ])
        let attrs = GuidedStockDraftBuilder.attributeDrafts(for: g)
        XCTAssertEqual(attrs.count, 1)
        XCTAssertEqual(attrs[0].values.map(\.value), ["black"])
    }
}
