import XCTest
@testable import OPS

final class GuidedStockStructuringTests: XCTestCase {

    // MARK: - Convenience

    private func capture(_ name: String) -> GuidedCapturedItem {
        GuidedCapturedItem(name: name)
    }

    // MARK: - Contract tests (these 4 are the binding spec)

    func test_cluster_groupsVinylByColor() {
        let items = ["Vinyl black", "Vinyl white", "Vinyl grey"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].stem, "vinyl")
        XCTAssertEqual(Set(GuidedStockStructuring.proposeValues(for: c[0])), ["black", "white", "grey"])
    }

    func test_cluster_doesNotMergeScrewsAndScrewGun() {
        let items = ["Screws 2in", "Screw gun"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        // They must never end up in the same proposed cluster.
        XCTAssertFalse(c.contains { $0.memberItemIds.count > 1 && Set($0.memberItemIds) == Set(items.map(\.id)) })
        XCTAssertTrue(c.allSatisfy { $0.memberItemIds.count >= 2 ? !(Set($0.memberItemIds) == Set(items.map(\.id))) : true })
    }

    func test_cluster_allDistinct_returnsNoClusters() {
        let items = ["Hammer", "Vinyl", "Ladder", "Paint bucket"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        XCTAssertTrue(c.isEmpty)
    }

    func test_cluster_twoDimensions_vinyl_color_and_width() {
        let items = ["Vinyl black 6ft", "Vinyl white 8ft"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.3)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].stem, "vinyl")
        XCTAssertEqual(c[0].differingTokenSets.count, 2)   // color position + width position
    }

    // MARK: - Additional edge-case tests

    func test_normalize_lowercasesAndTrims() {
        let tokens = GuidedStockStructuring.normalize("  Vinyl BLACK  ")
        XCTAssertEqual(tokens, ["vinyl", "black"])
    }

    func test_normalize_keepsUnitTokens() {
        let tokens = GuidedStockStructuring.normalize("Vinyl 6ft")
        XCTAssertEqual(tokens, ["vinyl", "6ft"])
    }

    func test_normalize_singularPluralDistinct() {
        let screws = GuidedStockStructuring.normalize("Screws")
        let screw = GuidedStockStructuring.normalize("Screw")
        XCTAssertNotEqual(screws, screw)
    }

    func test_cluster_singleItem_returnsNoClusters() {
        let items = [capture("Vinyl black")]
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        XCTAssertTrue(c.isEmpty)
    }

    func test_cluster_emptyInput_returnsNoClusters() {
        let c = GuidedStockStructuring.cluster([], threshold: 0.5)
        XCTAssertTrue(c.isEmpty)
    }

    func test_cluster_duplicateNames_formCluster() {
        let items = [capture("Vinyl black"), capture("Vinyl black")]
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        // Same name → sharedLen=2, minLen=2, similarity=1.0 >= 0.5 → clusters.
        // differingTokenSets is empty because nothing differs, but the cluster still forms.
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].stem, "vinyl black")
        XCTAssertTrue(c[0].differingTokenSets.isEmpty)
    }

    func test_cluster_threeItemsTwoDimensions() {
        // Three vinyl items with both color and size dimensions.
        let items = ["Vinyl black 2in", "Vinyl white 4in", "Vinyl grey 6in"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.3)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].stem, "vinyl")
        XCTAssertEqual(c[0].differingTokenSets.count, 2)
        XCTAssertEqual(Set(c[0].differingTokenSets[0]), ["black", "white", "grey"])
        XCTAssertEqual(Set(c[0].differingTokenSets[1]), ["2in", "4in", "6in"])
    }

    func test_cluster_mixedFamilies_independent() {
        // Vinyl variants cluster together; paint variants cluster separately.
        let items = [
            "Vinyl black", "Vinyl white",
            "Paint red", "Paint blue"
        ].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        XCTAssertEqual(c.count, 2)
        let stems = Set(c.map(\.stem))
        XCTAssertEqual(stems, ["vinyl", "paint"])
    }

    func test_proposeValues_returnsFirstDimension() {
        let items = ["Vinyl black 6ft", "Vinyl white 8ft"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.3)
        XCTAssertEqual(c.count, 1)
        let proposed = GuidedStockStructuring.proposeValues(for: c[0])
        XCTAssertEqual(Set(proposed), ["black", "white"])
    }

    func test_proposeValues_emptyCluster_returnsEmpty() {
        // A cluster with no differing dimensions (exact duplicates).
        let cluster = GuidedStockStructuring.Cluster(
            stem: "vinyl",
            memberItemIds: ["a", "b"],
            differingTokenSets: []
        )
        XCTAssertTrue(GuidedStockStructuring.proposeValues(for: cluster).isEmpty)
    }

    func test_cluster_belowThreshold_returnsNoClusters() {
        // "Vinyl black 6ft" and "Vinyl white 8ft" at threshold 0.5:
        // sharedLen=1, minLen=3, similarity≈0.333 < 0.5 → no cluster.
        let items = ["Vinyl black 6ft", "Vinyl white 8ft"].map(capture)
        let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
        XCTAssertTrue(c.isEmpty)
    }
}
