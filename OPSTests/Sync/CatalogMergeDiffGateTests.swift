//
//  CatalogMergeDiffGateTests.swift
//  OPSTests
//
//  Thirteen catalog-family merges run on EVERY delta pass (pullDelta seeds
//  epoch cursors for all entity types, so they never skip). Un-gated they
//  rewrote `lastSyncedAt` on every local row — and the variant↔option-value
//  junction wiped and reinserted its whole company scope — which saved the
//  DataActor context and broadcast `.dataActorDidSave` even when the server
//  returned byte-identical data. Every such save wakes the main-context merge,
//  @Query invalidation, and the sync-pill inventory refresh.
//
//  Gated in two waves. First: catalog options, option values, the variant
//  junction, item tags, product materials, product bundle items. Second: the
//  rest of the family — catalog orders and order items, company default
//  products, product options, product option values, pricing modifiers, and
//  products themselves. Products were the quiet one: they carry no
//  `lastSyncedAt`, so their cost was pure same-value reassignment, which
//  SwiftData dirties anyway (pinned by the write-semantics test below).
//
//  The contract pinned here: a merge whose payload matches the store opens no
//  transaction at all, so there is no save and no notification. A merge that
//  carries a real change writes exactly the rows that changed and nothing else.
//

import SwiftData
import XCTest
@testable import OPS

final class CatalogMergeDiffGateTests: XCTestCase {

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let otherCompanyId = "99999999-9999-4999-8999-999999999999"

    // MARK: - Transaction semantics

    /// The gate depends on skipping `transaction` entirely rather than trusting
    /// an empty one to stay silent. This pins which of those two the store
    /// actually does, so a SwiftData behaviour change surfaces here first.
    func test_emptyTransactionDoesNotPostDidSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try context.transaction { }

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an empty transaction posted ModelContext.didSave — the gate must skip the transaction, never rely on an empty one"
        )
    }

    // MARK: - Catalog options

    func test_catalogOptions_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [optionDTO(id: "opt-1", name: "Color"), optionDTO(id: "opt-2", name: "Mount")]

        try await actor.mergeCatalogOptions(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptions(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged catalog-options pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(CatalogOption.self, in: container), 2)
    }

    func test_catalogOptions_changedName_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptions(
            dtos: [optionDTO(id: "opt-1", name: "Color"), optionDTO(id: "opt-2", name: "Mount")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptions(
            dtos: [optionDTO(id: "opt-1", name: "Colour"), optionDTO(id: "opt-2", name: "Mount")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.eventCount, 1, "a real field change must save exactly once")
        XCTAssertEqual(recorder.totalUpdated, 1, "only the renamed row may be updated — observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalInserted, 0)
        XCTAssertEqual(recorder.totalDeleted, 0)

        let context = ModelContext(container)
        let renamed = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOption>()).first { $0.id == "opt-1" })
        XCTAssertEqual(renamed.name, "Colour")
    }

    /// The un-gated merge cleared `needsSync` on every pass. A row still
    /// flagged for outbound push is therefore a genuine pending write, and the
    /// gate must not mistake it for clean.
    func test_catalogOptions_pendingFlagIsClearedEvenWhenFieldsMatch() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)

        let seed = ModelContext(container)
        let option = CatalogOption(id: "opt-1", catalogItemId: "item-1", name: "Color", sortOrder: 0)
        option.needsSync = true
        seed.insert(option)
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptions(dtos: [optionDTO(id: "opt-1", name: "Color")], companyId: companyId)

        let context = ModelContext(container)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOption>()).first)
        XCTAssertFalse(stored.needsSync, "inbound merge must still clear the pending flag")
    }

    func test_catalogOptions_membershipChange_touchesOnlyTheAddedAndRemovedRows() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptions(
            dtos: [optionDTO(id: "opt-1", name: "Color"), optionDTO(id: "opt-2", name: "Mount")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptions(
            dtos: [optionDTO(id: "opt-1", name: "Color"), optionDTO(id: "opt-3", name: "Finish")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged row must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogOption>()).map(\.id))
        XCTAssertEqual(ids, ["opt-1", "opt-3"])
    }

    /// Pruning stays scoped to items this company owns.
    func test_catalogOptions_leavesCrossCompanyRowsAlone() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        try seedCatalogItem(id: "foreign-item", companyId: otherCompanyId, in: container)

        let seed = ModelContext(container)
        seed.insert(CatalogOption(id: "foreign-opt", catalogItemId: "foreign-item", name: "Theirs", sortOrder: 0))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptions(dtos: [optionDTO(id: "opt-1", name: "Color")], companyId: companyId)

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogOption>()).map(\.id))
        XCTAssertEqual(ids, ["opt-1", "foreign-opt"], "another company's options must survive the prune")
    }

    // MARK: - Catalog option values

    func test_catalogOptionValues_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(CatalogOption(id: "opt-1", catalogItemId: "item-1", name: "Color", sortOrder: 0))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [
            CatalogOptionValueDTO(id: "val-1", optionId: "opt-1", value: "Black", sortOrder: 0),
            CatalogOptionValueDTO(id: "val-2", optionId: "opt-1", value: "White", sortOrder: 1)
        ]
        try await actor.mergeCatalogOptionValues(dtos: dtos)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptionValues(dtos: dtos)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged option-value pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(CatalogOptionValue.self, in: container), 2)
    }

    func test_catalogOptionValues_changedValue_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(CatalogOption(id: "opt-1", catalogItemId: "item-1", name: "Color", sortOrder: 0))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptionValues(dtos: [
            CatalogOptionValueDTO(id: "val-1", optionId: "opt-1", value: "Black", sortOrder: 0),
            CatalogOptionValueDTO(id: "val-2", optionId: "opt-1", value: "White", sortOrder: 1)
        ])

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptionValues(dtos: [
            CatalogOptionValueDTO(id: "val-1", optionId: "opt-1", value: "Matte black", sortOrder: 0),
            CatalogOptionValueDTO(id: "val-2", optionId: "opt-1", value: "White", sortOrder: 1)
        ])

        XCTAssertEqual(recorder.totalUpdated, 1, "only the changed value may be rewritten — observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalInserted, 0)
        XCTAssertEqual(recorder.totalDeleted, 0)

        let context = ModelContext(container)
        let changed = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOptionValue>()).first { $0.id == "val-1" })
        XCTAssertEqual(changed.value, "Matte black")
    }

    func test_catalogOptionValues_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(CatalogOption(id: "opt-1", catalogItemId: "item-1", name: "Color", sortOrder: 0))
        // Value whose option is not resident locally — outside the prune scope.
        seed.insert(CatalogOptionValue(id: "val-orphan", optionId: "opt-unknown", value: "Orphan", sortOrder: 0))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOptionValues(dtos: [
            CatalogOptionValueDTO(id: "val-1", optionId: "opt-1", value: "Black", sortOrder: 0),
            CatalogOptionValueDTO(id: "val-2", optionId: "opt-1", value: "White", sortOrder: 1)
        ])

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOptionValues(dtos: [
            CatalogOptionValueDTO(id: "val-1", optionId: "opt-1", value: "Black", sortOrder: 0),
            CatalogOptionValueDTO(id: "val-3", optionId: "opt-1", value: "Bronze", sortOrder: 1)
        ])

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged value must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogOptionValue>()).map(\.id))
        XCTAssertEqual(ids, ["val-1", "val-3", "val-orphan"], "the out-of-scope value must survive the prune")
    }

    // MARK: - Variant ↔ option-value junction (was wipe + reinsert)

    func test_variantOptionValues_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedVariant(id: "var-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [
            CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-1"),
            CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-2")
        ]
        try await actor.mergeCatalogVariantOptionValues(dtos: dtos, companyId: companyId)
        XCTAssertEqual(try count(CatalogVariantOptionValue.self, in: container), 2)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogVariantOptionValues(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged junction pass must not wipe and reinsert — observed \(recorder.describe())"
        )
        XCTAssertEqual(
            try count(CatalogVariantOptionValue.self, in: container), 2,
            "row count must stay stable across passes"
        )
    }

    func test_variantOptionValues_membershipChange_touchesExactlyTheTwoChangedRows() async throws {
        let container = try makeContainer()
        try seedVariant(id: "var-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogVariantOptionValues(
            dtos: [
                CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-1"),
                CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-2")
            ],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        // val-2 removed, val-3 added; val-1 unchanged.
        try await actor.mergeCatalogVariantOptionValues(
            dtos: [
                CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-1"),
                CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-3")
            ],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let pairs = Set(try context.fetch(FetchDescriptor<CatalogVariantOptionValue>()).map(\.optionValueId))
        XCTAssertEqual(pairs, ["val-1", "val-3"])
    }

    /// Content parity with the wipe+reinsert scheme: after a pass the company's
    /// junction rows are exactly the server's, one row per pair.
    func test_variantOptionValues_convergesOnServerSet_withoutDuplicates() async throws {
        let container = try makeContainer()
        try seedVariant(id: "var-1", in: container)

        // Two pre-existing duplicates for the same pair — the shape the old
        // wipe+reinsert left behind whenever a server row's variant was not
        // resident locally at merge time.
        let seed = ModelContext(container)
        seed.insert(CatalogVariantOptionValue(variantId: "var-1", optionValueId: "val-1"))
        seed.insert(CatalogVariantOptionValue(variantId: "var-1", optionValueId: "val-1"))
        seed.insert(CatalogVariantOptionValue(variantId: "var-1", optionValueId: "stale"))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogVariantOptionValues(
            dtos: [CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-1")],
            companyId: companyId
        )

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CatalogVariantOptionValue>())
        XCTAssertEqual(rows.count, 1, "duplicates and stale pairs must both be collapsed")
        XCTAssertEqual(rows.first?.optionValueId, "val-1")
    }

    func test_variantOptionValues_leavesOtherCompaniesJoinsAlone() async throws {
        let container = try makeContainer()
        try seedVariant(id: "var-1", in: container)
        try seedVariant(id: "foreign-var", companyId: otherCompanyId, in: container)

        let seed = ModelContext(container)
        seed.insert(CatalogVariantOptionValue(variantId: "foreign-var", optionValueId: "val-9"))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogVariantOptionValues(
            dtos: [CatalogVariantOptionValueDTO(variantId: "var-1", optionValueId: "val-1")],
            companyId: companyId
        )

        let context = ModelContext(container)
        let pairs = Set(try context.fetch(FetchDescriptor<CatalogVariantOptionValue>()).map { "\($0.variantId)/\($0.optionValueId)" })
        XCTAssertEqual(pairs, ["var-1/val-1", "foreign-var/val-9"])
    }

    // MARK: - Catalog item tags

    func test_catalogItemTags_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [
            CatalogItemTagDTO(id: "tag-join-1", catalogItemId: "item-1", tagId: "tag-1"),
            CatalogItemTagDTO(id: "tag-join-2", catalogItemId: "item-1", tagId: "tag-2")
        ]
        try await actor.mergeCatalogItemTags(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogItemTags(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged item-tag pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(CatalogItemTag.self, in: container), 2)
    }

    func test_catalogItemTags_retagged_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogItemTags(
            dtos: [
                CatalogItemTagDTO(id: "tag-join-1", catalogItemId: "item-1", tagId: "tag-1"),
                CatalogItemTagDTO(id: "tag-join-2", catalogItemId: "item-1", tagId: "tag-2")
            ],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogItemTags(
            dtos: [
                CatalogItemTagDTO(id: "tag-join-1", catalogItemId: "item-1", tagId: "tag-9"),
                CatalogItemTagDTO(id: "tag-join-2", catalogItemId: "item-1", tagId: "tag-2")
            ],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalInserted, 0)
        XCTAssertEqual(recorder.totalDeleted, 0)
    }

    func test_catalogItemTags_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        try seedCatalogItem(id: "item-1", in: container)
        try seedCatalogItem(id: "foreign-item", companyId: otherCompanyId, in: container)

        // Join on another company's item — outside the prune scope.
        let seed = ModelContext(container)
        seed.insert(CatalogItemTag(id: "tag-join-foreign", catalogItemId: "foreign-item", tagId: "tag-9"))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogItemTags(
            dtos: [
                CatalogItemTagDTO(id: "tag-join-1", catalogItemId: "item-1", tagId: "tag-1"),
                CatalogItemTagDTO(id: "tag-join-2", catalogItemId: "item-1", tagId: "tag-2")
            ],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogItemTags(
            dtos: [
                CatalogItemTagDTO(id: "tag-join-1", catalogItemId: "item-1", tagId: "tag-1"),
                CatalogItemTagDTO(id: "tag-join-3", catalogItemId: "item-1", tagId: "tag-3")
            ],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged join must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogItemTag>()).map(\.id))
        XCTAssertEqual(
            ids, ["tag-join-1", "tag-join-3", "tag-join-foreign"],
            "another company's join must survive the prune"
        )
    }

    // MARK: - Product materials

    func test_productMaterials_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [materialDTO(id: "mat-1", quantityPerUnit: 2.5), materialDTO(id: "mat-2", quantityPerUnit: 1)]
        try await actor.mergeProductMaterials(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductMaterials(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged product-materials pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(ProductMaterial.self, in: container), 2)
    }

    func test_productMaterials_changedQuantity_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 2.5), materialDTO(id: "mat-2", quantityPerUnit: 1)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 4), materialDTO(id: "mat-2", quantityPerUnit: 1)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(context.fetch(FetchDescriptor<ProductMaterial>()).first { $0.id == "mat-1" })
        XCTAssertEqual(changed.quantityPerUnit, 4, accuracy: 0.0001)
    }

    /// `variant_selector` is jsonb kept as a raw string — it must take part in
    /// the diff, or a recipe selector change would never land.
    func test_productMaterials_changedVariantSelector_updatesRow() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 1, selector: #"{"color":"black"}"#)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 1, selector: #"{"color":"white"}"#)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<ProductMaterial>()).first)
        XCTAssertEqual(stored.variantSelectorJSON, #"{"color":"white"}"#)
    }

    func test_productMaterials_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)

        // Recipe row on a product this company does not own — outside the prune scope.
        let seed = ModelContext(container)
        seed.insert(ProductMaterial(id: "mat-orphan", productId: "prod-foreign", quantityPerUnit: 1))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 2.5), materialDTO(id: "mat-2", quantityPerUnit: 1)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductMaterials(
            dtos: [materialDTO(id: "mat-1", quantityPerUnit: 2.5), materialDTO(id: "mat-3", quantityPerUnit: 4)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged material must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<ProductMaterial>()).map(\.id))
        XCTAssertEqual(ids, ["mat-1", "mat-3", "mat-orphan"], "the out-of-scope recipe row must survive the prune")
    }

    // MARK: - Product bundle items

    func test_productBundleItems_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [bundleItemDTO(id: "bundle-1", quantity: 2), bundleItemDTO(id: "bundle-2", quantity: 1)]
        try await actor.mergeProductBundleItems(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductBundleItems(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged bundle-items pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(ProductBundleItem.self, in: container), 2)
    }

    func test_productBundleItems_changedQuantity_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 2), bundleItemDTO(id: "bundle-2", quantity: 1)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 7), bundleItemDTO(id: "bundle-2", quantity: 1)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(context.fetch(FetchDescriptor<ProductBundleItem>()).first { $0.id == "bundle-1" })
        XCTAssertEqual(changed.quantity, 7, accuracy: 0.0001)
    }

    func test_productBundleItems_pendingLocalEditSurvivesTheMerge() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 2)],
            companyId: companyId
        )

        let seed = ModelContext(container)
        let local = try XCTUnwrap(seed.fetch(FetchDescriptor<ProductBundleItem>()).first)
        local.quantity = 99
        local.needsSync = true
        try seed.save()

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 2)],
            companyId: companyId
        )

        let context = ModelContext(container)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<ProductBundleItem>()).first)
        XCTAssertEqual(stored.quantity, 99, accuracy: 0.0001, "an in-flight local edit must not be clobbered")
        XCTAssertTrue(stored.needsSync)
    }

    func test_productBundleItems_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)

        // Child row under a bundle this company does not own — outside the prune scope.
        let seed = ModelContext(container)
        seed.insert(
            ProductBundleItem(
                id: "bundle-orphan",
                companyId: otherCompanyId,
                bundleProductId: "prod-foreign",
                childProductId: "child-foreign"
            )
        )
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 2), bundleItemDTO(id: "bundle-2", quantity: 1)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductBundleItems(
            dtos: [bundleItemDTO(id: "bundle-1", quantity: 2), bundleItemDTO(id: "bundle-3", quantity: 5)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged child must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<ProductBundleItem>()).map(\.id))
        XCTAssertEqual(ids, ["bundle-1", "bundle-3", "bundle-orphan"], "the out-of-scope child must survive the prune")
    }

    // MARK: - SwiftData write semantics

    /// Decides whether a merge that assigns identical values is silent or not.
    /// `ProductSyncLocalStore.merge` writes no `lastSyncedAt`, so its per-pass
    /// cost rests entirely on this behaviour — the exclusion rationale in the
    /// review notes is only valid while this holds.
    func test_reassigningIdenticalValuesStillDirtiesTheRow() throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(Product(id: "prod-probe", companyId: companyId, name: "Deck board"))
        try seed.save()

        let context = ModelContext(container)
        context.autosaveEnabled = false
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<Product>()).first)

        row.name = row.name
        row.basePrice = row.basePrice

        XCTAssertTrue(
            context.hasChanges,
            "SwiftData no longer dirties a row on identical reassignment — ProductSyncLocalStore can be left un-gated, and this test should flip"
        )
    }

    // MARK: - Catalog orders

    func test_catalogOrders_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [orderDTO(id: "order-1", status: "draft"), orderDTO(id: "order-2", status: "sent")]
        try await actor.mergeCatalogOrders(dtos: dtos, companyId: companyId)
        XCTAssertEqual(try count(CatalogOrder.self, in: container), 2)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrders(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged catalog-orders pass must not save — observed \(recorder.describe())"
        )
    }

    func test_catalogOrders_statusChange_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOrders(
            dtos: [orderDTO(id: "order-1", status: "draft"), orderDTO(id: "order-2", status: "sent")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrders(
            dtos: [orderDTO(id: "order-1", status: "fulfilled"), orderDTO(id: "order-2", status: "sent")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOrder>()).first { $0.id == "order-1" })
        XCTAssertEqual(changed.status, .fulfilled)
    }

    /// An order the server stops reporting is tombstoned exactly once — the
    /// pre-gate code re-stamped `deletedAt` on every subsequent pass.
    func test_catalogOrders_droppedOrder_isTombstonedOnceThenSilent() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOrders(
            dtos: [orderDTO(id: "order-1", status: "draft"), orderDTO(id: "order-2", status: "sent")],
            companyId: companyId
        )

        let firstRecorder = StoreWriteRecorder()
        try await actor.mergeCatalogOrders(dtos: [orderDTO(id: "order-1", status: "draft")], companyId: companyId)
        firstRecorder.stop()
        XCTAssertEqual(firstRecorder.totalUpdated, 1, "the dropped order must be tombstoned — observed \(firstRecorder.describe())")

        let context = ModelContext(container)
        let dropped = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOrder>()).first { $0.id == "order-2" })
        let tombstonedAt = try XCTUnwrap(dropped.deletedAt)

        let secondRecorder = StoreWriteRecorder()
        defer { secondRecorder.stop() }

        try await actor.mergeCatalogOrders(dtos: [orderDTO(id: "order-1", status: "draft")], companyId: companyId)

        XCTAssertEqual(
            secondRecorder.eventCount, 0,
            "an already-tombstoned order must not be re-stamped — observed \(secondRecorder.describe())"
        )

        let after = ModelContext(container)
        let stillDropped = try XCTUnwrap(after.fetch(FetchDescriptor<CatalogOrder>()).first { $0.id == "order-2" })
        XCTAssertEqual(stillDropped.deletedAt, tombstonedAt, "the deletion time must not drift forward")
    }

    /// A field held back by a pending local write can never justify a save.
    func test_catalogOrders_pendingFieldWriteDoesNotForceASave() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOrders(dtos: [orderDTO(id: "order-1", status: "draft")], companyId: companyId)

        // Local edit in flight: the operation ledger protects `title`.
        let seed = ModelContext(container)
        let operation = SyncOperation(
            entityType: SyncEntityType.catalogOrder.rawValue,
            entityId: "order-1",
            operationType: "update",
            payload: Data(#"{"title":"Local title"}"#.utf8),
            changedFields: ["title"]
        )
        seed.insert(operation)
        let order = try XCTUnwrap(seed.fetch(FetchDescriptor<CatalogOrder>()).first)
        order.title = "Local title"
        try seed.save()

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrders(
            dtos: [orderDTO(id: "order-1", status: "draft", title: "Server title")],
            companyId: companyId
        )

        XCTAssertEqual(
            recorder.eventCount, 0,
            "the only field the server changed is protected, so the pass must not save at all — observed \(recorder.describe())"
        )

        let context = ModelContext(container)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOrder>()).first)
        XCTAssertEqual(stored.title, "Local title", "a protected field must never be overwritten inbound")
    }

    // MARK: - Catalog order items

    func test_catalogOrderItems_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [orderItemDTO(id: "item-1", quantity: 4), orderItemDTO(id: "item-2", quantity: 1)]
        try await actor.mergeCatalogOrderItems(dtos: dtos, orderId: "order-1")
        XCTAssertEqual(try count(CatalogOrderItem.self, in: container), 2)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrderItems(dtos: dtos, orderId: "order-1")

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged order-items pass must not save — observed \(recorder.describe())"
        )
    }

    func test_catalogOrderItems_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()

        // Child of a different order — the prune is scoped to one order.
        let seed = ModelContext(container)
        seed.insert(
            CatalogOrderItem(
                id: "item-other-order",
                orderId: "order-2",
                catalogVariantId: "var-9",
                quantityRequested: 1
            )
        )
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOrderItems(
            dtos: [orderItemDTO(id: "item-1", quantity: 4), orderItemDTO(id: "item-2", quantity: 1)],
            orderId: "order-1"
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrderItems(
            dtos: [orderItemDTO(id: "item-1", quantity: 4), orderItemDTO(id: "item-3", quantity: 2)],
            orderId: "order-1"
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "the unchanged item must not be rewritten — observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogOrderItem>()).map(\.id))
        XCTAssertEqual(
            ids, ["item-1", "item-3", "item-other-order"],
            "another order's child must survive a prune scoped to this order"
        )
    }

    func test_catalogOrderItems_quantityChange_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCatalogOrderItems(
            dtos: [orderItemDTO(id: "item-1", quantity: 4), orderItemDTO(id: "item-2", quantity: 1)],
            orderId: "order-1"
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCatalogOrderItems(
            dtos: [orderItemDTO(id: "item-1", quantity: 9), orderItemDTO(id: "item-2", quantity: 1)],
            orderId: "order-1"
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(context.fetch(FetchDescriptor<CatalogOrderItem>()).first { $0.id == "item-1" })
        XCTAssertEqual(changed.quantityRequested, 9, accuracy: 0.0001)
    }

    // MARK: - Company default products

    func test_companyDefaultProducts_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [defaultProductDTO(componentType: "railing", productId: "prod-1"),
                    defaultProductDTO(componentType: "gate", productId: "prod-2")]
        try await actor.mergeCompanyDefaultProducts(dtos: dtos, companyId: companyId)
        XCTAssertEqual(try count(CompanyDefaultProduct.self, in: container), 2)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCompanyDefaultProducts(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged default-products pass must not save — observed \(recorder.describe())"
        )
    }

    func test_companyDefaultProducts_repointedDefault_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCompanyDefaultProducts(
            dtos: [defaultProductDTO(componentType: "railing", productId: "prod-1"),
                   defaultProductDTO(componentType: "gate", productId: "prod-2")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCompanyDefaultProducts(
            dtos: [defaultProductDTO(componentType: "railing", productId: "prod-9"),
                   defaultProductDTO(componentType: "gate", productId: "prod-2")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(
            context.fetch(FetchDescriptor<CompanyDefaultProduct>()).first { $0.componentType == .railing }
        )
        XCTAssertEqual(changed.productId, "prod-9")
    }

    func test_companyDefaultProducts_droppedDefault_isDeletedThenSilent() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeCompanyDefaultProducts(
            dtos: [defaultProductDTO(componentType: "railing", productId: "prod-1"),
                   defaultProductDTO(componentType: "gate", productId: "prod-2")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCompanyDefaultProducts(
            dtos: [defaultProductDTO(componentType: "railing", productId: "prod-1")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "observed \(recorder.describe())")
        XCTAssertEqual(try count(CompanyDefaultProduct.self, in: container), 1)
    }

    /// A component_type this build cannot parse is coerced to `.railing` by
    /// toModel(), so keying the server set by the raw string while keying local
    /// rows by the parsed one made the row unmatchable: it inserted a duplicate
    /// railing every pass and pruned the genuine railing at the same time.
    func test_companyDefaultProducts_unknownComponentType_isSkippedAndStaysSilent() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [
            defaultProductDTO(componentType: "railing", productId: "prod-1"),
            defaultProductDTO(componentType: "holographic_canopy", productId: "prod-2")
        ]

        try await actor.mergeCompanyDefaultProducts(dtos: dtos, companyId: companyId)

        let afterFirst = ModelContext(container)
        let firstRows = try afterFirst.fetch(FetchDescriptor<CompanyDefaultProduct>())
        XCTAssertEqual(firstRows.count, 1, "the unparseable row must not be stored at all")
        XCTAssertEqual(firstRows.first?.componentType, .railing)
        XCTAssertEqual(firstRows.first?.productId, "prod-1", "the genuine railing default must be the one kept")

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeCompanyDefaultProducts(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged pass carrying an unknown component_type must still be silent — observed \(recorder.describe())"
        )

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CompanyDefaultProduct>())
        XCTAssertEqual(rows.count, 1, "the unknown type must not accumulate duplicate railing rows")
        XCTAssertEqual(rows.first?.productId, "prod-1", "the genuine railing default must survive the prune")
    }

    // MARK: - Products (ProductSyncLocalStore)

    func test_products_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [productDTO(id: "prod-1", name: "Cedar board"), productDTO(id: "prod-2", name: "Railing kit")]
        try await actor.mergeProducts(dtos: dtos, companyId: companyId)
        XCTAssertEqual(try count(Product.self, in: container), 2)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProducts(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged products pass must not save — observed \(recorder.describe())"
        )
    }

    func test_products_renamed_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProducts(
            dtos: [productDTO(id: "prod-1", name: "Cedar board"), productDTO(id: "prod-2", name: "Railing kit")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProducts(
            dtos: [productDTO(id: "prod-1", name: "Cedar decking"), productDTO(id: "prod-2", name: "Railing kit")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let renamed = try XCTUnwrap(context.fetch(FetchDescriptor<Product>()).first { $0.id == "prod-1" })
        XCTAssertEqual(renamed.name, "Cedar decking")
    }

    /// A product dropped by the server is deactivated once; the pre-gate code
    /// re-assigned `isActive = false` on every later pass.
    func test_products_droppedProduct_isDeactivatedOnceThenSilent() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProducts(
            dtos: [productDTO(id: "prod-1", name: "Cedar board"), productDTO(id: "prod-2", name: "Railing kit")],
            companyId: companyId
        )

        let firstRecorder = StoreWriteRecorder()
        try await actor.mergeProducts(dtos: [productDTO(id: "prod-1", name: "Cedar board")], companyId: companyId)
        firstRecorder.stop()
        XCTAssertEqual(firstRecorder.totalUpdated, 1, "the dropped product must be deactivated — observed \(firstRecorder.describe())")

        let context = ModelContext(container)
        let dropped = try XCTUnwrap(context.fetch(FetchDescriptor<Product>()).first { $0.id == "prod-2" })
        XCTAssertFalse(dropped.isActive)

        let secondRecorder = StoreWriteRecorder()
        defer { secondRecorder.stop() }

        try await actor.mergeProducts(dtos: [productDTO(id: "prod-1", name: "Cedar board")], companyId: companyId)

        XCTAssertEqual(
            secondRecorder.eventCount, 0,
            "an already-deactivated product must not be rewritten — observed \(secondRecorder.describe())"
        )
    }

    // MARK: - Product options

    func test_productOptions_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [productOptionDTO(id: "popt-1", name: "Color"), productOptionDTO(id: "popt-2", name: "Height")]
        try await actor.mergeProductOptions(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptions(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged product-options pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(ProductOption.self, in: container), 2)
    }

    func test_productOptions_renamed_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductOptions(
            dtos: [productOptionDTO(id: "popt-1", name: "Color"), productOptionDTO(id: "popt-2", name: "Height")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptions(
            dtos: [productOptionDTO(id: "popt-1", name: "Colour"), productOptionDTO(id: "popt-2", name: "Height")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")
    }

    func test_productOptions_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)

        // Option on a product this company does not own — outside the prune scope.
        let seed = ModelContext(container)
        seed.insert(ProductOption(id: "popt-orphan", productId: "prod-foreign", name: "Theirs", kind: .select))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductOptions(
            dtos: [productOptionDTO(id: "popt-1", name: "Color"), productOptionDTO(id: "popt-2", name: "Height")],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptions(
            dtos: [productOptionDTO(id: "popt-1", name: "Color"), productOptionDTO(id: "popt-3", name: "Finish")],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<ProductOption>()).map(\.id))
        XCTAssertEqual(ids, ["popt-1", "popt-3", "popt-orphan"], "the out-of-scope option must survive the prune")
    }

    // MARK: - Product option values

    func test_productOptionValues_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(ProductOption(id: "popt-1", productId: "prod-1", name: "Color", kind: .select))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [productOptionValueDTO(id: "pval-1", value: "Black"),
                    productOptionValueDTO(id: "pval-2", value: "White")]
        try await actor.mergeProductOptionValues(dtos: dtos)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptionValues(dtos: dtos)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged product-option-values pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(ProductOptionValue.self, in: container), 2)
    }

    func test_productOptionValues_changedValue_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(ProductOption(id: "popt-1", productId: "prod-1", name: "Color", kind: .select))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductOptionValues(
            dtos: [productOptionValueDTO(id: "pval-1", value: "Black"),
                   productOptionValueDTO(id: "pval-2", value: "White")]
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptionValues(
            dtos: [productOptionValueDTO(id: "pval-1", value: "Matte black"),
                   productOptionValueDTO(id: "pval-2", value: "White")]
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")
    }

    func test_productOptionValues_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        seed.insert(ProductOption(id: "popt-1", productId: "prod-1", name: "Color", kind: .select))
        // Value whose option is not resident locally — outside the prune scope.
        seed.insert(ProductOptionValue(id: "pval-orphan", optionId: "popt-unknown", value: "Orphan", sortOrder: 0))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductOptionValues(
            dtos: [productOptionValueDTO(id: "pval-1", value: "Black"),
                   productOptionValueDTO(id: "pval-2", value: "White")]
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductOptionValues(
            dtos: [productOptionValueDTO(id: "pval-1", value: "Black"),
                   productOptionValueDTO(id: "pval-3", value: "Bronze")]
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<ProductOptionValue>()).map(\.id))
        XCTAssertEqual(ids, ["pval-1", "pval-3", "pval-orphan"], "the out-of-scope value must survive the prune")
    }

    // MARK: - Product pricing modifiers

    func test_productPricingModifiers_secondIdenticalPass_writesNothing() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dtos = [pricingModifierDTO(id: "pmod-1", amount: 12.5), pricingModifierDTO(id: "pmod-2", amount: 3)]
        try await actor.mergeProductPricingModifiers(dtos: dtos, companyId: companyId)

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductPricingModifiers(dtos: dtos, companyId: companyId)

        XCTAssertEqual(
            recorder.eventCount, 0,
            "an unchanged pricing-modifiers pass must not save — observed \(recorder.describe())"
        )
        XCTAssertEqual(try count(ProductPricingModifier.self, in: container), 2)
    }

    func test_productPricingModifiers_changedAmount_updatesOnlyThatRow() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductPricingModifiers(
            dtos: [pricingModifierDTO(id: "pmod-1", amount: 12.5), pricingModifierDTO(id: "pmod-2", amount: 3)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductPricingModifiers(
            dtos: [pricingModifierDTO(id: "pmod-1", amount: 20), pricingModifierDTO(id: "pmod-2", amount: 3)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalUpdated, 1, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let changed = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProductPricingModifier>()).first { $0.id == "pmod-1" }
        )
        XCTAssertEqual(changed.amount, 20, accuracy: 0.0001)
    }

    func test_productPricingModifiers_membershipChange_touchesOnlyTheChangedRows() async throws {
        let container = try makeContainer()
        try seedProduct(id: "prod-1", in: container)

        // Modifier on a product this company does not own — outside the prune scope.
        let seed = ModelContext(container)
        seed.insert(
            ProductPricingModifier(
                id: "pmod-orphan",
                productId: "prod-foreign",
                optionId: "popt-foreign",
                modifierKind: .addFlat,
                amount: 1
            )
        )
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        try await actor.mergeProductPricingModifiers(
            dtos: [pricingModifierDTO(id: "pmod-1", amount: 12.5), pricingModifierDTO(id: "pmod-2", amount: 3)],
            companyId: companyId
        )

        let recorder = StoreWriteRecorder()
        defer { recorder.stop() }

        try await actor.mergeProductPricingModifiers(
            dtos: [pricingModifierDTO(id: "pmod-1", amount: 12.5), pricingModifierDTO(id: "pmod-3", amount: 7)],
            companyId: companyId
        )

        XCTAssertEqual(recorder.totalInserted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalDeleted, 1, "observed \(recorder.describe())")
        XCTAssertEqual(recorder.totalUpdated, 0, "observed \(recorder.describe())")

        let context = ModelContext(container)
        let ids = Set(try context.fetch(FetchDescriptor<ProductPricingModifier>()).map(\.id))
        XCTAssertEqual(ids, ["pmod-1", "pmod-3", "pmod-orphan"], "the out-of-scope modifier must survive the prune")
    }

    // MARK: - Field-level drift guards

    // Two merges were big enough to need their differ and their writer split
    // into separate functions: catalog orders (`catalogOrderDiffers` /
    // `applyCatalogOrder`) and products (`ProductSyncLocalStore.differs` /
    // `.merge`). Split code drifts. A field the writer sets but the differ
    // never inspects goes silently stale — the server changes it, the gate says
    // "nothing to do", and the device keeps showing the old value until some
    // other field on the same row happens to change. A field the differ reports
    // but the writer never sets is the opposite failure: the gate opens on every
    // single pass, the row is rewritten, and the store saves forever — exactly
    // the lag this whole change set exists to kill.
    //
    // Both directions are the same assertion run one field at a time: change
    // that field alone, the gate must open, the value must land, and the very
    // next identical pass must be silent. The tests walk the production field
    // lists, so a field added to a merge without a case here fails outright
    // rather than shipping uncovered.

    func test_catalogOrders_everyMergeFieldOpensTheGateThenConverges() async throws {
        let cases = orderDriftCases

        for field in DataActor.catalogOrderMergeFields {
            guard let drift = cases[field] else {
                XCTFail("no drift case registered for catalog-order merge field `\(field)`")
                continue
            }

            let container = try makeContainer()
            let actor = DataActor(modelContainer: container)
            await actor.configure()

            let base = OrderSpec(companyId: companyId)
            try await actor.mergeCatalogOrders(dtos: [base.dto()], companyId: companyId)

            var changed = base
            drift.mutate(&changed)
            let dtos = [changed.dto()]

            let opening = StoreWriteRecorder()
            try await actor.mergeCatalogOrders(dtos: dtos, companyId: companyId)
            opening.stop()
            XCTAssertEqual(
                opening.totalUpdated, 1,
                "`\(field)` changed on the server but the differ never reported it — the row goes stale — observed \(opening.describe())"
            )

            let context = ModelContext(container)
            let row = try XCTUnwrap(
                context.fetch(FetchDescriptor<CatalogOrder>()).first { $0.id == base.id }
            )
            XCTAssertTrue(
                drift.landed(row),
                "`\(field)` opened the gate but the apply never wrote it to the row"
            )

            let settled = StoreWriteRecorder()
            try await actor.mergeCatalogOrders(dtos: dtos, companyId: companyId)
            settled.stop()
            XCTAssertEqual(
                settled.eventCount, 0,
                "`\(field)` still differs after the merge wrote it — every later pass saves for nothing — observed \(settled.describe())"
            )
        }
    }

    /// Products are checked against the differ/writer pair directly. No pending
    /// operations exist on these rows, so the accept set is the whole field
    /// list — precisely what `acceptableFields` resolves to on a clean row.
    func test_products_everyMergeFieldOpensTheGateThenConverges() throws {
        let accept = Set(ProductSyncLocalStore.mergeFields)
        let cases = productDriftCases

        for field in ProductSyncLocalStore.mergeFields {
            guard let drift = cases[field] else {
                XCTFail("no drift case registered for product merge field `\(field)`")
                continue
            }

            let container = try makeContainer()
            let context = ModelContext(container)

            let base = ProductSpec(companyId: companyId)
            try ProductSyncLocalStore.merge(dto: base.dto(), context: context, accepting: accept)
            try context.save()

            let row = try XCTUnwrap(
                context.fetch(FetchDescriptor<Product>()).first { $0.id == base.id }
            )
            XCTAssertFalse(
                ProductSyncLocalStore.differs(dto: base.dto(), from: row, accepting: accept),
                "the freshly inserted row already differs from the payload that made it — `toModel` and `differs` disagree on `\(field)`'s neighbourhood"
            )

            var changed = base
            drift.mutate(&changed)
            let dto = changed.dto()

            XCTAssertTrue(
                ProductSyncLocalStore.differs(dto: dto, from: row, accepting: accept),
                "`\(field)` changed on the server but the differ never reported it — the row goes stale"
            )

            try ProductSyncLocalStore.merge(dto: dto, context: context, accepting: accept)
            try context.save()

            XCTAssertTrue(
                drift.landed(row),
                "`\(field)` opened the gate but the merge never wrote it to the row"
            )
            XCTAssertFalse(
                ProductSyncLocalStore.differs(dto: dto, from: row, accepting: accept),
                "`\(field)` still differs after the merge wrote it — every later pass saves for nothing"
            )
        }
    }

    // MARK: - Drift-guard tables

    /// One case per writable field: how the server changes it, and how to tell
    /// the change reached the row. Values are distinct per field so a write
    /// landing in the wrong property fails rather than passing by coincidence.
    private struct Drift<Spec, Row> {
        let mutate: (inout Spec) -> Void
        let landed: (Row) -> Bool
    }

    private var orderDriftCases: [String: Drift<OrderSpec, CatalogOrder>] {
        [
            "companyId": Drift(
                mutate: { [otherCompanyId] in $0.companyId = otherCompanyId },
                landed: { [otherCompanyId] in $0.companyId == otherCompanyId }
            ),
            "status": Drift(
                mutate: { $0.status = "fulfilled" },
                landed: { $0.status == .fulfilled }
            ),
            "title": Drift(
                mutate: { $0.title = "Cedar restock" },
                landed: { $0.title == "Cedar restock" }
            ),
            "supplierName": Drift(
                mutate: { $0.supplierName = "Northland Lumber" },
                landed: { $0.supplierName == "Northland Lumber" }
            ),
            "supplierContact": Drift(
                mutate: { $0.supplierContact = "dispatch@northland.test" },
                landed: { $0.supplierContact == "dispatch@northland.test" }
            ),
            "expectedDeliveryDate": Drift(
                mutate: { $0.expectedDeliveryDate = "2026-09-15" },
                landed: { $0.expectedDeliveryDate == SupabaseDate.parseDateOnly("2026-09-15") }
            ),
            "notes": Drift(
                mutate: { $0.notes = "Tailgate delivery only" },
                landed: { $0.notes == "Tailgate delivery only" }
            ),
            "createdById": Drift(
                mutate: { $0.createdById = "22222222-2222-4222-8222-222222222222" },
                landed: { $0.createdById == "22222222-2222-4222-8222-222222222222" }
            ),
            "sentAt": Drift(
                mutate: { $0.sentAt = "2026-08-04T09:30:00+00:00" },
                landed: { $0.sentAt == SupabaseDate.parse("2026-08-04T09:30:00+00:00") }
            ),
            "fulfilledAt": Drift(
                mutate: { $0.fulfilledAt = "2026-08-05T10:31:00+00:00" },
                landed: { $0.fulfilledAt == SupabaseDate.parse("2026-08-05T10:31:00+00:00") }
            ),
            "cancelledAt": Drift(
                mutate: { $0.cancelledAt = "2026-08-06T11:32:00+00:00" },
                landed: { $0.cancelledAt == SupabaseDate.parse("2026-08-06T11:32:00+00:00") }
            ),
            "deletedAt": Drift(
                mutate: { $0.deletedAt = "2026-08-07T12:33:00+00:00" },
                landed: { $0.deletedAt == SupabaseDate.parse("2026-08-07T12:33:00+00:00") }
            )
        ]
    }

    private var productDriftCases: [String: Drift<ProductSpec, Product>] {
        [
            "companyId": Drift(
                mutate: { [otherCompanyId] in $0.companyId = otherCompanyId },
                landed: { [otherCompanyId] in $0.companyId == otherCompanyId }
            ),
            "name": Drift(
                mutate: { $0.name = "Cedar decking" },
                landed: { $0.name == "Cedar decking" }
            ),
            "productDescription": Drift(
                mutate: { $0.productDescription = "Kiln-dried, S4S" },
                landed: { $0.productDescription == "Kiln-dried, S4S" }
            ),
            "type": Drift(
                mutate: { $0.type = "LABOR" },
                landed: { $0.type == .labor }
            ),
            "kind": Drift(
                mutate: { $0.kind = "package" },
                landed: { $0.kind == .package }
            ),
            "basePrice": Drift(
                mutate: { $0.basePrice = 43.75 },
                landed: { $0.basePrice == 43.75 }
            ),
            "unitCost": Drift(
                mutate: { $0.unitCost = 21.5 },
                landed: { $0.unitCost == 21.5 }
            ),
            "pricingUnit": Drift(
                mutate: { $0.pricingUnit = "linear_foot" },
                landed: { $0.pricingUnit == .linearFoot }
            ),
            "unit": Drift(
                mutate: { $0.unit = "board foot" },
                landed: { $0.unit == "board foot" }
            ),
            "category": Drift(
                mutate: { $0.category = "Decking" },
                landed: { $0.category == "Decking" }
            ),
            "categoryId": Drift(
                mutate: { $0.categoryId = "cat-7" },
                landed: { $0.categoryId == "cat-7" }
            ),
            "sku": Drift(
                mutate: { $0.sku = "CDR-2X6-16" },
                landed: { $0.sku == "CDR-2X6-16" }
            ),
            "thumbnailUrl": Drift(
                mutate: { $0.thumbnailUrl = "https://cdn.test/cedar.png" },
                landed: { $0.thumbnailUrl == "https://cdn.test/cedar.png" }
            ),
            "taxable": Drift(
                mutate: { $0.isTaxable = false },
                landed: { $0.taxable == false }
            ),
            "isActive": Drift(
                mutate: { $0.isActive = false },
                landed: { $0.isActive == false }
            ),
            "isFavorite": Drift(
                mutate: { $0.isFavorite = true },
                landed: { $0.isFavorite == true }
            ),
            "minimumCharge": Drift(
                mutate: { $0.minimumCharge = 125 },
                landed: { $0.minimumCharge == 125 }
            ),
            "minimumQuantity": Drift(
                mutate: { $0.minimumQuantity = 3 },
                landed: { $0.minimumQuantity == 3 }
            ),
            "showBomOnEstimate": Drift(
                mutate: { $0.showBomOnEstimate = true },
                landed: { $0.showBomOnEstimate == true }
            ),
            "showInStorefront": Drift(
                mutate: { $0.showInStorefront = true },
                landed: { $0.showInStorefront == true }
            ),
            "tieredPricingJSON": Drift(
                mutate: { $0.tieredPricingJSON = #"{"tiers":[]}"# },
                landed: { $0.tieredPricingJSON == #"{"tiers":[]}"# }
            ),
            "taskTypeId": Drift(
                mutate: { $0.taskTypeId = "33333333-3333-4333-8333-333333333333" },
                landed: { $0.taskTypeId == "33333333-3333-4333-8333-333333333333" }
            ),
            "taskTypeRef": Drift(
                mutate: { $0.taskTypeRef = "framing" },
                landed: { $0.taskTypeRef == "framing" }
            ),
            "unitId": Drift(
                mutate: { $0.unitId = "44444444-4444-4444-8444-444444444444" },
                landed: { $0.unitId == "44444444-4444-4444-8444-444444444444" }
            ),
            "linkedCatalogItemId": Drift(
                mutate: { $0.linkedCatalogItemId = "55555555-5555-4555-8555-555555555555" },
                landed: { $0.linkedCatalogItemId == "55555555-5555-4555-8555-555555555555" }
            ),
            "bundlePricingMode": Drift(
                mutate: { $0.bundlePricingMode = "override" },
                landed: { $0.bundlePricingMode == "override" }
            ),
            "createdAt": Drift(
                mutate: { $0.createdAt = "2026-07-04T00:00:00+00:00" },
                landed: { $0.createdAt == SupabaseDate.parse("2026-07-04T00:00:00+00:00") }
            )
        ]
    }

    /// Mutable mirrors of the two DTOs, which are immutable by design. Baseline
    /// values match the `orderDTO` / `productDTO` fixtures above; each drift
    /// case changes exactly one of them.
    private struct OrderSpec {
        var id = "order-1"
        var companyId: String
        var status = "draft"
        var title: String? = nil
        var supplierName: String? = nil
        var supplierContact: String? = nil
        var expectedDeliveryDate: String? = nil
        var notes: String? = nil
        var createdById: String? = nil
        var createdAt = "2026-08-01T00:00:00+00:00"
        var updatedAt = "2026-08-02T00:00:00+00:00"
        var sentAt: String? = nil
        var fulfilledAt: String? = nil
        var cancelledAt: String? = nil
        var deletedAt: String? = nil

        func dto() -> CatalogOrderDTO {
            CatalogOrderDTO(
                id: id,
                companyId: companyId,
                status: status,
                title: title,
                supplierName: supplierName,
                supplierContact: supplierContact,
                expectedDeliveryDate: expectedDeliveryDate,
                notes: notes,
                createdById: createdById,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sentAt: sentAt,
                fulfilledAt: fulfilledAt,
                cancelledAt: cancelledAt,
                deletedAt: deletedAt
            )
        }
    }

    private struct ProductSpec {
        var id = "prod-1"
        var companyId: String
        var name = "Cedar board"
        var productDescription: String? = nil
        var basePrice: Double = 42
        var unitCost: Double? = 20
        var unit: String? = nil
        var category: String? = nil
        var categoryId: String? = nil
        var sku: String? = nil
        var thumbnailUrl: String? = nil
        var kind: String? = "good"
        var pricingUnit: String? = "each"
        var type: String? = "MATERIAL"
        var isTaxable: Bool? = true
        var isActive = true
        var isFavorite = false
        var minimumCharge: Double? = nil
        var minimumQuantity: Double? = nil
        var showBomOnEstimate = false
        var showInStorefront = false
        var tieredPricingJSON: String? = nil
        var taskTypeId: String? = nil
        var taskTypeRef: String? = nil
        var unitId: String? = nil
        var linkedCatalogItemId: String? = nil
        var bundlePricingMode: String? = nil
        var createdAt = "2026-08-01T00:00:00+00:00"
        var updatedAt = "2026-08-02T00:00:00+00:00"

        func dto() -> ProductDTO {
            ProductDTO(
                id: id,
                companyId: companyId,
                name: name,
                description: productDescription,
                basePrice: basePrice,
                unitCost: unitCost,
                unit: unit,
                category: category,
                categoryId: categoryId,
                sku: sku,
                thumbnailUrl: thumbnailUrl,
                kind: kind,
                pricingUnit: pricingUnit,
                type: type,
                isTaxable: isTaxable,
                isActive: isActive,
                isFavorite: isFavorite,
                minimumCharge: minimumCharge,
                minimumQuantity: minimumQuantity,
                showBomOnEstimate: showBomOnEstimate,
                showInStorefront: showInStorefront,
                tieredPricing: tieredPricingJSON.map { RawJSONColumn(rawJSONString: $0) },
                taskTypeId: taskTypeId,
                taskTypeRef: taskTypeRef,
                unitId: unitId,
                linkedCatalogItemId: linkedCatalogItemId,
                bundlePricingMode: bundlePricingMode,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CatalogItem.self,
            CatalogVariant.self,
            CatalogOption.self,
            CatalogOptionValue.self,
            CatalogVariantOptionValue.self,
            CatalogItemTag.self,
            CatalogOrder.self,
            CatalogOrderItem.self,
            CompanyDefaultProduct.self,
            Product.self,
            ProductMaterial.self,
            ProductBundleItem.self,
            ProductOption.self,
            ProductOptionValue.self,
            ProductPricingModifier.self,
            // acceptableFields / hasPendingOperations query this on the orders path.
            SyncOperation.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        // A #Predicate fetch of SyncOperation TRAPS (EXC_BREAKPOINT inside
        // SwiftData, uncatchable) against a store whose operation table has
        // never held a row — see the note on ProjectCacheMerge.operations. The
        // orders path runs exactly such a fetch via acceptableFields, so
        // materialize the table with an inert row scoped to no real entity.
        let warmup = ModelContext(container)
        warmup.insert(
            SyncOperation(
                entityType: "diffGateWarmup",
                entityId: "diffGateWarmup",
                operationType: "update",
                payload: Data("{}".utf8),
                changedFields: []
            )
        )
        try warmup.save()

        return container
    }

    private func count<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetch(FetchDescriptor<T>()).count
    }

    private func seedCatalogItem(id: String, companyId: String? = nil, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(CatalogItem(id: id, companyId: companyId ?? self.companyId, name: "Item \(id)"))
        try context.save()
    }

    private func seedVariant(id: String, companyId: String? = nil, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(CatalogVariant(id: id, companyId: companyId ?? self.companyId, catalogItemId: "item-1"))
        try context.save()
    }

    private func seedProduct(id: String, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(Product(id: id, companyId: companyId, name: "Product \(id)"))
        try context.save()
    }

    private func optionDTO(id: String, name: String, sortOrder: Int = 0) -> CatalogOptionDTO {
        CatalogOptionDTO(
            id: id,
            catalogItemId: "item-1",
            name: name,
            sortOrder: sortOrder,
            createdAt: "2026-08-01T00:00:00+00:00"
        )
    }

    private func materialDTO(
        id: String,
        quantityPerUnit: Double,
        selector: String? = nil
    ) -> ProductMaterialDTO {
        ProductMaterialDTO(
            id: id,
            productId: "prod-1",
            catalogVariantId: "var-1",
            catalogItemId: nil,
            variantSelector: selector.map { RawJSONColumn(rawJSONString: $0) },
            quantityPerUnit: quantityPerUnit,
            scaledByOptionId: nil,
            unitId: "unit-1",
            notes: nil
        )
    }

    private func productDTO(id: String, name: String) -> ProductDTO {
        ProductDTO(
            id: id,
            companyId: companyId,
            name: name,
            description: nil,
            basePrice: 42,
            unitCost: 20,
            unit: nil,
            category: nil,
            categoryId: nil,
            sku: nil,
            thumbnailUrl: nil,
            kind: "good",
            pricingUnit: "each",
            type: "MATERIAL",
            isTaxable: true,
            isActive: true,
            isFavorite: false,
            minimumCharge: nil,
            minimumQuantity: nil,
            showBomOnEstimate: false,
            showInStorefront: false,
            tieredPricing: nil,
            taskTypeId: nil,
            taskTypeRef: nil,
            unitId: nil,
            linkedCatalogItemId: nil,
            bundlePricingMode: nil,
            createdAt: "2026-08-01T00:00:00+00:00",
            updatedAt: "2026-08-02T00:00:00+00:00"
        )
    }

    private func orderDTO(id: String, status: String, title: String? = nil) -> CatalogOrderDTO {
        CatalogOrderDTO(
            id: id,
            companyId: companyId,
            status: status,
            title: title,
            supplierName: nil,
            supplierContact: nil,
            expectedDeliveryDate: nil,
            notes: nil,
            createdById: nil,
            createdAt: "2026-08-01T00:00:00+00:00",
            updatedAt: "2026-08-02T00:00:00+00:00",
            sentAt: nil,
            fulfilledAt: nil,
            cancelledAt: nil,
            deletedAt: nil
        )
    }

    private func orderItemDTO(id: String, quantity: Double) -> CatalogOrderItemDTO {
        CatalogOrderItemDTO(
            id: id,
            orderId: "order-1",
            catalogVariantId: "var-1",
            quantityRequested: quantity,
            costPerUnit: 4.25,
            notes: nil
        )
    }

    private func defaultProductDTO(componentType: String, productId: String) -> CompanyDefaultProductDTO {
        CompanyDefaultProductDTO(
            companyId: companyId,
            componentType: componentType,
            productId: productId,
            createdAt: "2026-08-01T00:00:00+00:00",
            updatedAt: "2026-08-02T00:00:00+00:00"
        )
    }

    private func productOptionDTO(id: String, name: String) -> ProductOptionDTO {
        ProductOptionDTO(
            id: id,
            productId: "prod-1",
            name: name,
            kind: "select",
            affectsPrice: true,
            affectsRecipe: false,
            required: true,
            defaultValue: nil,
            optionDefaultSource: nil,
            sortOrder: 0
        )
    }

    private func productOptionValueDTO(id: String, value: String) -> ProductOptionValueDTO {
        ProductOptionValueDTO(id: id, optionId: "popt-1", value: value, sortOrder: 0)
    }

    private func pricingModifierDTO(id: String, amount: Double) -> ProductPricingModifierDTO {
        ProductPricingModifierDTO(
            id: id,
            productId: "prod-1",
            optionId: "popt-1",
            triggerValueId: "pval-1",
            triggerIntMin: nil,
            triggerIntMax: nil,
            modifierKind: "add_per_unit",
            amount: amount
        )
    }

    private func bundleItemDTO(id: String, quantity: Double) -> ProductBundleItemDTO {
        ProductBundleItemDTO(
            id: id,
            companyId: companyId,
            bundleProductId: "prod-1",
            childProductId: "child-\(id)",
            quantity: quantity,
            relationshipKind: "required",
            suggestionReason: nil,
            compatibilitySelector: nil,
            displayOrder: 0,
            createdAt: "2026-08-01T00:00:00+00:00",
            updatedAt: "2026-08-02T00:00:00+00:00",
            deletedAt: nil
        )
    }
}

/// Records every `ModelContext.didSave` in the process with its identifier
/// counts. SwiftData does not name the saving context in the notification, so
/// exact counts are only meaningful because these tests run one actor against
/// one in-memory store and nothing else writes during the measured window.
private final class StoreWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(inserted: Int, updated: Int, deleted: Int)] = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            func ids(_ key: ModelContext.NotificationKey) -> Int {
                (info[key.rawValue] as? [PersistentIdentifier])?.count ?? 0
            }
            self?.append(
                inserted: ids(.insertedIdentifiers),
                updated: ids(.updatedIdentifiers),
                deleted: ids(.deletedIdentifiers)
            )
        }
    }

    private func append(inserted: Int, updated: Int, deleted: Int) {
        lock.lock()
        defer { lock.unlock() }
        events.append((inserted, updated, deleted))
    }

    var eventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    var totalInserted: Int {
        lock.lock(); defer { lock.unlock() }
        return events.reduce(0) { $0 + $1.inserted }
    }

    var totalUpdated: Int {
        lock.lock(); defer { lock.unlock() }
        return events.reduce(0) { $0 + $1.updated }
    }

    var totalDeleted: Int {
        lock.lock(); defer { lock.unlock() }
        return events.reduce(0) { $0 + $1.deleted }
    }

    func describe() -> String {
        lock.lock(); defer { lock.unlock() }
        guard !events.isEmpty else { return "no saves" }
        return events
            .map { "+\($0.inserted)/~\($0.updated)/-\($0.deleted)" }
            .joined(separator: ", ")
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
