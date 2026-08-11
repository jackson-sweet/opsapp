//
//  CatalogMergeDiffGateTests.swift
//  OPSTests
//
//  Seven catalog-family syncs run on EVERY delta pass (pullDelta seeds epoch
//  cursors for all entity types, so they never skip). Un-gated they rewrote
//  `lastSyncedAt` on every local row — and the variant↔option-value junction
//  wiped and reinserted its whole company scope — which saved the DataActor
//  context and broadcast `.dataActorDidSave` even when the server returned
//  byte-identical data. Every such save wakes the main-context merge, @Query
//  invalidation, and the sync-pill inventory refresh.
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

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CatalogItem.self,
            CatalogVariant.self,
            CatalogOption.self,
            CatalogOptionValue.self,
            CatalogVariantOptionValue.self,
            CatalogItemTag.self,
            Product.self,
            ProductMaterial.self,
            ProductBundleItem.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
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
