import XCTest
@testable import OPS

@MainActor
final class GuidedStockSetupModelTests: XCTestCase {

    private func tempStore() -> GuidedStockSetupDraftStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guided-drafts-\(UUID().uuidString)", isDirectory: true)
        return GuidedStockSetupDraftStore(rootURL: dir)
    }

    func test_advance_and_back_clampToValidRange() {
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: tempStore())
        XCTAssertEqual(model.stage, .prime)
        model.back()                            // clamped at .prime
        XCTAssertEqual(model.stage, .prime)
        model.advance(); XCTAssertEqual(model.stage, .capture)
        model.advance(); XCTAssertEqual(model.stage, .structure)
        model.advance(); XCTAssertEqual(model.stage, .blueprint)
        model.advance(); XCTAssertEqual(model.stage, .done)
        model.advance(); XCTAssertEqual(model.stage, .done)   // clamped at .done
        model.back();    XCTAssertEqual(model.stage, .blueprint)
    }

    func test_persist_and_restore_roundTripsState() {
        let store = tempStore()
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: store)
        model.capturedItems = [
            GuidedCapturedItem(name: "Vinyl black", kind: .stock),
            GuidedCapturedItem(name: "Install labor", kind: .sell)
        ]
        model.groups = [GuidedStructuredGroup(familyName: "Vinyl", memberItemIds: [model.capturedItems[0].id], isSingleItem: false, isConfirmed: true)]
        model.committedGroupIds = ["grp-x"]
        model.advance()   // -> .capture, also persists
        model.persist()

        let restored = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: store)
        XCTAssertTrue(restored.restoreIfAvailable())
        XCTAssertEqual(restored.stage, .capture)
        XCTAssertEqual(restored.capturedItems, model.capturedItems)
        XCTAssertEqual(restored.groups, model.groups)
        XCTAssertEqual(restored.committedGroupIds, ["grp-x"])
    }

    func test_restore_returnsFalse_whenNoDraft() {
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: tempStore())
        XCTAssertFalse(model.restoreIfAvailable())
    }

    func test_restore_returnsFalse_whenContextEmpty() {
        let model = GuidedStockSetupModel(companyId: "", userId: "", draftStore: tempStore())
        model.persist()                          // no-op (no context)
        XCTAssertFalse(model.restoreIfAvailable())
    }

    func test_clearDraft_removesPersistedState() {
        let store = tempStore()
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: store)
        model.capturedItems = [GuidedCapturedItem(name: "Screws")]
        model.persist()
        XCTAssertTrue(model.hasDraftToResume)
        model.clearDraft()
        XCTAssertFalse(model.hasDraftToResume)
    }

    // MARK: - seedGroupsFromCapture tests

    func test_seed_clustersBecomeVersionedCandidates() {
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: tempStore())
        model.capturedItems = [
            GuidedCapturedItem(name: "Vinyl black"),
            GuidedCapturedItem(name: "Vinyl white"),
            GuidedCapturedItem(name: "Vinyl grey")
        ]
        model.seedGroupsFromCapture(threshold: 0.5)

        XCTAssertEqual(model.groups.count, 1, "Three vinyl colour variants should form exactly one cluster group")
        let group = model.groups[0]
        XCTAssertFalse(group.isSingleItem, "Clustered group must be versioned (isSingleItem == false)")
        XCTAssertEqual(group.memberItemIds.count, 3, "All three members must be in the group")
        let firstAttrValues = Set(group.attributes.first?.values ?? [])
        XCTAssertEqual(firstAttrValues, ["black", "white", "grey"],
                       "First attribute values must match the differing colour tokens")
    }

    func test_seed_distinctItemsBecomeSingleCandidates() {
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: tempStore())
        model.capturedItems = [
            GuidedCapturedItem(name: "Hammer"),
            GuidedCapturedItem(name: "Ladder")
        ]
        model.seedGroupsFromCapture(threshold: 0.5)

        XCTAssertEqual(model.groups.count, 2, "Two distinct items must produce two single-item groups")
        XCTAssertTrue(model.groups.allSatisfy { $0.isSingleItem }, "All groups must be single-item")
    }

    func test_seed_isIdempotent() {
        let model = GuidedStockSetupModel(companyId: "c1", userId: "u1", draftStore: tempStore())
        model.capturedItems = [
            GuidedCapturedItem(name: "Vinyl black"),
            GuidedCapturedItem(name: "Vinyl white")
        ]
        model.seedGroupsFromCapture(threshold: 0.5)
        let firstGroupIds = model.groups.map(\.id)

        model.seedGroupsFromCapture(threshold: 0.5)   // second call — must be a no-op
        let secondGroupIds = model.groups.map(\.id)

        XCTAssertEqual(firstGroupIds, secondGroupIds, "Calling seedGroupsFromCapture twice must not duplicate groups")
        XCTAssertEqual(model.groups.count, firstGroupIds.count, "Group count must remain stable after second seed call")
    }
}
