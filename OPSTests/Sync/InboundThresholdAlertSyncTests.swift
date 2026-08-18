//
//  InboundThresholdAlertSyncTests.swift
//  OPSTests
//
//  The inventory-threshold rail must cross the narrow server RPC
//  (`sync_threshold_alert_notification`), never a direct `notifications`
//  insert — the 2026-07-15 notification-creation hardening revoked app-role
//  INSERT, so the end-of-sync rail write InboundProcessor used to hand-roll
//  (mark-read sweep -> unread probe -> insert) 42501'd on every sync and the
//  rail went silently dead.
//
//  What these tests pin:
//    1. The count handed to the syncer is exactly what OrderSuggestionEngine
//       derives from the local store (wiring proof over a populated store; the
//       threshold cascade's own row-level behavior is pinned by
//       OrderSuggestionEngineTests).
//    2. EVERY sync reports — zero included. The clear lane IS a zero report:
//       the server auto-clears the rail when it hears zero, so a client that
//       skipped reporting zero would leave a stale "below threshold" entry
//       standing after stock is restored.
//    3. The count is company-scoped — another company's low stock must never
//       reach this operator's rail.
//    4. A transport failure stays isolated. The reconcile is non-throwing by
//       construction (single do/catch); a sync must never break because the
//       rail write failed.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class InboundThresholdAlertSyncTests: XCTestCase {

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let otherCompanyId = "99999999-9999-4999-8999-999999999999"

    // MARK: - Spy

    /// Records every count reported to the rail RPC and can fail the transport
    /// on demand. The reconcile reports once per pass, so plain storage is
    /// race-free.
    private final class ThresholdAlertSyncSpy: ThresholdAlertSyncing {
        private(set) var reportedCounts: [Int] = []
        var shouldFail = false

        func syncThresholdAlert(count: Int) async throws -> String {
            reportedCounts.append(count)
            if shouldFail {
                throw URLError(.notConnectedToInternet)
            }
            // Mirrors the server's verdict vocabulary.
            return count == 0 ? "cleared" : "created"
        }
    }

    // MARK: - 1. Store-derived count reaches the syncer verbatim

    /// A populated store with one variant below a category-inherited
    /// threshold, one below a family default, one sitting exactly ON the
    /// threshold (the engine counts `<=`), and four decoys that must not
    /// inflate the rail: a variant whose own override puts it above the line,
    /// an inactive one, a soft-deleted one, and a family with no threshold
    /// anywhere in the cascade.
    func test_reportsStoreDerivedCountVerbatim() async throws {
        let context = try makeContext()
        let fixture = try seedMixedStore(in: context)

        // The count the engine derives from exactly these company-scoped rows.
        let expected = OrderSuggestionEngine().suggest(
            variants: fixture.variants,
            families: fixture.families,
            categories: fixture.categories
        ).count

        // The wiring proof must not pass over a degenerate fixture.
        XCTAssertEqual(
            expected, 3,
            "fixture must produce exactly three below-threshold variants — category-inherited, family-default, and the on-the-line boundary"
        )

        let spy = ThresholdAlertSyncSpy()

        await InboundProcessor.reconcileThresholdAlert(
            context: context,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.reportedCounts, [expected],
            "the syncer must receive exactly the count OrderSuggestionEngine derives from the store — one report per sync pass"
        )
    }

    // MARK: - 2. Zero still reports (the clear lane)

    /// Stock restored above the line: the rail clears only because the client
    /// reports zero. A client that returned early on zero would strand the
    /// existing unread alert forever.
    func test_reportsZeroWhenNothingIsBelowThreshold() async throws {
        let context = try makeContext()

        let family = CatalogItem(
            id: "fam-stocked",
            companyId: companyId,
            name: "Stocked",
            defaultWarningThreshold: 10
        )
        context.insert(family)
        // Comfortably above the line.
        context.insert(variant(id: "v-stocked", familyId: family.id, quantity: 250))
        // Below the line but inactive / deleted — neither may resurrect the rail.
        context.insert(variant(id: "v-inactive", familyId: family.id, quantity: 0, active: false))
        context.insert(variant(id: "v-deleted", familyId: family.id, quantity: 0, deletedAt: Date()))
        try context.save()

        let spy = ThresholdAlertSyncSpy()

        await InboundProcessor.reconcileThresholdAlert(
            context: context,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.reportedCounts, [0],
            "zero must still cross the RPC — the server's clear-at-zero is the only thing that retires a standing rail entry"
        )
    }

    /// A company that has never synced catalog rows still reports — the rail
    /// clear must not depend on rows existing to be counted.
    func test_reportsZeroForAnEmptyStore() async throws {
        let context = try makeContext()
        let spy = ThresholdAlertSyncSpy()

        await InboundProcessor.reconcileThresholdAlert(
            context: context,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.reportedCounts, [0],
            "an empty store must report zero, not skip the report"
        )
    }

    // MARK: - 3. Company scoping

    /// Identical below-threshold rows belonging to another company must not
    /// reach this operator's rail — pins that the company filter is doing real
    /// work rather than passing everything through.
    func test_countScopesToTheReportingCompany() async throws {
        let context = try makeContext()

        let foreignFamily = CatalogItem(
            id: "fam-foreign",
            companyId: otherCompanyId,
            name: "Foreign",
            defaultWarningThreshold: 10
        )
        context.insert(foreignFamily)
        context.insert(
            CatalogVariant(
                id: "v-foreign",
                companyId: otherCompanyId,
                catalogItemId: foreignFamily.id,
                quantity: 0
            )
        )
        try context.save()

        let spy = ThresholdAlertSyncSpy()

        await InboundProcessor.reconcileThresholdAlert(
            context: context,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.reportedCounts, [0],
            "another company's low stock must never be counted into this operator's rail"
        )
    }

    // MARK: - 4. Transport failure isolation

    /// The reconcile is `async` and NOT `async throws`: a rail failure cannot
    /// propagate into the sync pass by construction, and this test would stop
    /// compiling if that single do/catch were ever dropped. It also pins that
    /// the failing report was actually attempted, so the next sync retries
    /// against a server that is idempotent.
    func test_transportFailureDoesNotEscapeTheReconcile() async throws {
        let context = try makeContext()
        let fixture = try seedMixedStore(in: context)
        XCTAssertFalse(fixture.variants.isEmpty)

        let spy = ThresholdAlertSyncSpy()
        spy.shouldFail = true

        await InboundProcessor.reconcileThresholdAlert(
            context: context,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.reportedCounts, [3],
            "the failing pass must still have attempted the report exactly once"
        )
    }

    // MARK: - Fixture

    private struct SeededStore {
        let variants: [CatalogVariant]
        let families: [CatalogItem]
        let categories: [CatalogCategory]
    }

    /// Three counting rows and four decoys, all saved to the store; returns the
    /// company-scoped rows so a test can run the engine over exactly them.
    private func seedMixedStore(in context: ModelContext) throws -> SeededStore {
        // Threshold source A: category default, inherited by a family that
        // declares none of its own.
        let category = CatalogCategory(
            id: "cat-1",
            companyId: companyId,
            name: "Fasteners",
            defaultWarningThreshold: 10
        )
        let inheritingFamily = CatalogItem(
            id: "fam-inherit",
            companyId: companyId,
            name: "Inherits Category",
            categoryId: category.id
        )
        // Threshold source B: family default.
        let familyDefaulted = CatalogItem(
            id: "fam-default",
            companyId: companyId,
            name: "Family Default",
            defaultWarningThreshold: 100
        )
        // No threshold anywhere in the cascade — never suggestible.
        let familyUnthresholded = CatalogItem(
            id: "fam-none",
            companyId: companyId,
            name: "No Threshold"
        )
        // Another company's rows, seeded alongside as a scoping decoy.
        let foreignFamily = CatalogItem(
            id: "fam-foreign",
            companyId: otherCompanyId,
            name: "Foreign",
            defaultWarningThreshold: 10
        )

        let counting = [
            // Below the category-inherited threshold of 10.
            variant(id: "v-inherit-low", familyId: inheritingFamily.id, quantity: 2),
            // Below the family default of 100.
            variant(id: "v-default-low", familyId: familyDefaulted.id, quantity: 30),
            // Exactly ON the line — the engine counts `quantity <= warning`.
            variant(id: "v-on-the-line", familyId: inheritingFamily.id, quantity: 10)
        ]
        let decoys = [
            // Variant override lifts it above its family's default.
            variant(id: "v-override-ok", familyId: familyDefaulted.id, quantity: 30, warning: 5),
            variant(id: "v-inactive", familyId: inheritingFamily.id, quantity: 0, active: false),
            variant(id: "v-deleted", familyId: inheritingFamily.id, quantity: 0, deletedAt: Date()),
            variant(id: "v-no-threshold", familyId: familyUnthresholded.id, quantity: 0)
        ]
        let foreignVariant = CatalogVariant(
            id: "v-foreign-low",
            companyId: otherCompanyId,
            catalogItemId: foreignFamily.id,
            quantity: 0
        )

        let families = [inheritingFamily, familyDefaulted, familyUnthresholded]
        let variants = counting + decoys

        context.insert(category)
        for seededFamily in families + [foreignFamily] { context.insert(seededFamily) }
        for seededVariant in variants + [foreignVariant] { context.insert(seededVariant) }
        try context.save()

        return SeededStore(variants: variants, families: families, categories: [category])
    }

    private func variant(
        id: String,
        familyId: String,
        quantity: Double,
        warning: Double? = nil,
        active: Bool = true,
        deletedAt: Date? = nil
    ) -> CatalogVariant {
        let variant = CatalogVariant(
            id: id,
            companyId: companyId,
            catalogItemId: familyId,
            quantity: quantity,
            warningThreshold: warning,
            isActive: active
        )
        variant.deletedAt = deletedAt
        return variant
    }

    // MARK: - Container

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CatalogItem.self,
            CatalogVariant.self,
            CatalogCategory.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
