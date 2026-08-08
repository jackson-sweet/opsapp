import XCTest
@testable import OPS

@MainActor
final class CatalogBulkVariantExpansionModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CatalogBulkVariantExpansionModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSelectionOnlyIncludesSelectableFamiliesAndSelectAllUsesVisibleRows() {
        let model = makeModel()

        model.toggleFamily("valid", selectableFamilyIds: ["valid"])
        model.toggleFamily("invalid", selectableFamilyIds: ["valid"])
        XCTAssertEqual(model.selectedFamilyIds, ["valid"])

        model.selectAllVisible(["valid", "second", "invalid"], selectableFamilyIds: ["valid", "second"])
        XCTAssertEqual(model.selectedFamilyIds, ["valid", "second"])

        model.clearVisible(["valid"])
        XCTAssertEqual(model.selectedFamilyIds, ["second"])
    }

    func testChangeValidationBlocksBlankDuplicateAndExistingValues() {
        let model = makeModel()
        model.setAxisName("Top profile")
        model.setExistingValue("Round top")
        model.setNewValue(" flat top ", at: model.newValues[0].id)
        XCTAssertNil(model.changeValidationMessage)

        model.addNewValue()
        model.setNewValue("FLAT TOP", at: model.newValues[1].id)
        XCTAssertEqual(model.changeValidationMessage, "Each new value must be unique.")

        model.setNewValue("Round Top", at: model.newValues[1].id)
        XCTAssertEqual(model.changeValidationMessage, "A new value matches the existing value.")
    }

    func testDraftRoundTripPreservesMeaningfulStateAndIdempotencyKey() throws {
        let model = makeModel()
        model.toggleFamily("rail", selectableFamilyIds: ["rail"])
        model.advance()
        model.setAxisName("Top profile")
        model.setExistingValue("Round top")
        model.setNewValue("Flat top", at: model.newValues[0].id)
        model.advance()

        let restored = makeModel()
        XCTAssertEqual(restored.stage, .review)
        XCTAssertEqual(restored.selectedFamilyIds, ["rail"])
        XCTAssertEqual(restored.axisName, "Top profile")
        XCTAssertEqual(restored.existingValue, "Round top")
        XCTAssertEqual(restored.trimmedNewValues, ["Flat top"])
        XCTAssertEqual(restored.idempotencyKey, model.idempotencyKey)
    }

    func testApplyStateAccountsForOfflineSavingAndPreviewSafety() {
        let model = configuredReviewModel()
        XCTAssertFalse(model.canApply(isOnline: false, canManage: true, previewCanApply: true))
        XCTAssertFalse(model.canApply(isOnline: true, canManage: false, previewCanApply: true))
        XCTAssertFalse(model.canApply(isOnline: true, canManage: true, previewCanApply: false))

        model.beginApply()
        XCTAssertFalse(model.canApply(isOnline: true, canManage: true, previewCanApply: true))
        model.finishApply()
        XCTAssertTrue(model.canApply(isOnline: true, canManage: true, previewCanApply: true))
    }

    func testStaleRejectionReturnsToReviewWithoutLosingDraft() {
        let model = configuredReviewModel()
        model.beginApply()
        model.handleRejection(code: "stale_catalog", message: "Catalog changed.")

        XCTAssertEqual(model.stage, .review)
        XCTAssertEqual(model.errorMessage, "Catalog changed.")
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.trimmedNewValues, ["Flat top"])
    }

    func testIdempotencyConflictCanRenewKeyWithoutLosingCurrentDraft() {
        let model = configuredReviewModel()
        let originalKey = model.idempotencyKey

        model.renewIdempotencyKey()

        XCTAssertNotEqual(model.idempotencyKey, originalKey)
        XCTAssertEqual(model.stage, .review)
        XCTAssertEqual(model.selectedFamilyIds, ["rail"])
        XCTAssertEqual(model.trimmedNewValues, ["Flat top"])
    }

    func testSuccessClearsPersistedDraftAndCapturesSummary() {
        let model = configuredReviewModel()
        model.beginApply()
        model.handleSuccess(familyCount: 12, newVariantCount: 24)

        XCTAssertEqual(model.completion, .init(familyCount: 12, newVariantCount: 24))
        XCTAssertFalse(model.isSaving)

        let restored = makeModel()
        XCTAssertEqual(restored.stage, .families)
        XCTAssertTrue(restored.selectedFamilyIds.isEmpty)
        XCTAssertTrue(restored.axisName.isEmpty)
    }

    private func configuredReviewModel() -> CatalogBulkVariantExpansionModel {
        let model = makeModel()
        model.toggleFamily("rail", selectableFamilyIds: ["rail"])
        model.advance()
        model.setAxisName("Top profile")
        model.setExistingValue("Round top")
        model.setNewValue("Flat top", at: model.newValues[0].id)
        model.advance()
        return model
    }

    private func makeModel() -> CatalogBulkVariantExpansionModel {
        CatalogBulkVariantExpansionModel(
            companyId: "company",
            defaults: defaults,
            draftKeyPrefix: "test.bulk-variant"
        )
    }
}
