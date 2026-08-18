//
//  VinylCatalogNotificationRPCTests.swift
//  OPSTests
//
//  Seven rails that fire off deck-builder, catalog-setup, and inventory work
//  must cross narrow server RPCs, never a client-side `notifications` insert —
//  the 2026-07-15 notification-creation hardening revoked app-role INSERT, so
//  every one of these legacy inserts 42501'd and the rail went silently dead
//  (bug e302355c ADDENDUM). The surfaces:
//
//    • VINYL ORDER DRAFTED   → `notify_vinyl_order_drafted`
//    • VINYL ORDERED (bulk)  → `notify_vinyl_bulk_ordered`
//    • OFFCUT BANKED         → `notify_vinyl_offcut_banked`
//    • guided setup ×3       → `notify_guided_setup_completed`
//    • inventory thresholds  → `notify_inventory_threshold_crossed`
//
//  Each dispatch was lifted out of the view/service that owned it so the
//  decisions that survive the rewrite stay pinned. What these tests pin:
//
//    1. Every id and count crosses its seam verbatim, once. The server derives
//       recipients and renders the copy from those anchors alone — a mangled id
//       silently notifies nobody, and a re-derived count silently lies.
//    2. The drafted-order rail keeps its status branch: a throw downgrades the
//       sheet to "ORDER DRAFTED / RAIL FAILED", success never does. The order
//       is already on the server by then; a dead rail must not fail the draft.
//    3. Guided setup's zero-work gate never touches the seam. Nothing built is
//       nothing to announce — and the server rejects an all-zero summary
//       outright, so the call would be pure noise.
//    4. The inventory push targets EXACTLY the ids the server reports it gave
//       new rows, and is skipped entirely when that list is empty. The server
//       recounts the item's status from the stored row; an empty list is an
//       honest "it's healthy now", not a reason to push at a stale local guess.
//    5. Transport failure stays contained everywhere. The write these rails
//       announce has already landed by the time they run.
//

import XCTest
@testable import OPS

final class VinylCatalogNotificationRPCTests: XCTestCase {

    // MARK: - Spies

    /// Records the drafted-order rail calls and plays back a scripted result.
    private final class VinylOrderDraftedSpy: VinylOrderDraftedNotifying {
        struct Call: Equatable {
            let projectId: String
            let noteId: String
            let orderedSqFt: Int
        }

        private(set) var calls: [Call] = []
        /// `created` or `noop` — both mean the rail holds the row.
        var result = "created"
        var failure: Error?

        func notifyVinylOrderDrafted(projectId: String, noteId: String, orderedSqFt: Int) async throws -> String {
            calls.append(Call(projectId: projectId, noteId: noteId, orderedSqFt: orderedSqFt))
            if let failure { throw failure }
            return result
        }
    }

    private final class VinylBulkOrderedSpy: VinylBulkOrderedNotifying {
        private(set) var markedCounts: [Int] = []
        var failure: Error?

        func notifyVinylBulkOrdered(markedCount: Int) async throws -> String {
            markedCounts.append(markedCount)
            if let failure { throw failure }
            return "created"
        }
    }

    private final class VinylOffcutBankedSpy: VinylOffcutBankedNotifying {
        struct Call: Equatable {
            let stockUnitId: String
            let projectId: String?
        }

        private(set) var calls: [Call] = []
        var failure: Error?

        func notifyVinylOffcutBanked(stockUnitId: String, projectId: String?) async throws -> String {
            calls.append(Call(stockUnitId: stockUnitId, projectId: projectId))
            if let failure { throw failure }
            return "created"
        }
    }

    /// Records the whole guided-setup parameter block — the kind AND every
    /// count — so a count wired to the wrong slot cannot pass.
    private final class GuidedSetupCompletionSpy: GuidedSetupCompletionNotifying {
        struct Call: Equatable {
            let kind: String
            let productCount: Int?
            let recipeCount: Int?
            let serviceCount: Int?
            let goodCount: Int?
            let assemblyCount: Int?
            let familyCount: Int?
            let variantCount: Int?
            let rollCount: Int?
            let offcutCount: Int?
            let bundleCount: Int?
        }

        private(set) var calls: [Call] = []
        var failure: Error?

        func notifyGuidedSetupCompleted(
            kind: String,
            productCount: Int?,
            recipeCount: Int?,
            serviceCount: Int?,
            goodCount: Int?,
            assemblyCount: Int?,
            familyCount: Int?,
            variantCount: Int?,
            rollCount: Int?,
            offcutCount: Int?,
            bundleCount: Int?
        ) async throws -> String {
            calls.append(
                Call(
                    kind: kind,
                    productCount: productCount,
                    recipeCount: recipeCount,
                    serviceCount: serviceCount,
                    goodCount: goodCount,
                    assemblyCount: assemblyCount,
                    familyCount: familyCount,
                    variantCount: variantCount,
                    rollCount: rollCount,
                    offcutCount: offcutCount,
                    bundleCount: bundleCount
                )
            )
            if let failure { throw failure }
            return "created"
        }
    }

    private final class InventoryThresholdSpy: InventoryThresholdNotifying {
        private(set) var itemIds: [String] = []
        /// Ids the server reports as having received NEW rail rows.
        var notified: [String] = []
        var failure: Error?

        func notifyInventoryThresholdCrossed(itemId: String) async throws -> [String] {
            itemIds.append(itemId)
            if let failure { throw failure }
            return notified
        }
    }

    /// Captures the push the threshold dispatcher would hand OneSignal.
    /// `OneSignalService` is a singleton with no seam, so the dispatcher takes
    /// the send as a closure — the test substitutes this recorder and no
    /// network work is ever attempted.
    private final class PushRecorder: @unchecked Sendable {
        private(set) var payloads: [InventoryThresholdNotificationDispatcher.PushPayload] = []

        func record(_ payload: InventoryThresholdNotificationDispatcher.PushPayload) {
            payloads.append(payload)
        }
    }

    /// Counts `.notificationReceived` posts — the in-app rail refresh the
    /// guided and offcut surfaces fire so the badge updates without a sync.
    private final class RefreshCounter: @unchecked Sendable {
        var count = 0
    }

    /// Runs `body` with an observer on the rail-refresh notification and
    /// reports how many times it fired. Posts are delivered synchronously on
    /// the posting thread, so the count is settled when `body` returns.
    private func refreshPosts(during body: () async -> Void) async -> Int {
        let counter = RefreshCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .notificationReceived,
            object: nil,
            queue: nil
        ) { _ in
            counter.count += 1
        }
        await body()
        NotificationCenter.default.removeObserver(token)
        return counter.count
    }

    // MARK: - 1. Vinyl order drafted: verbatim anchors

    func test_draftedOrderForwardsProjectNoteAndSquareFootageVerbatim() async {
        let spy = VinylOrderDraftedSpy()

        let outcome = await VinylOrderNotificationDispatcher.dispatchDrafted(
            projectId: "3f9c1a52-7d6b-4e18-9a02-5c7d41be8f30",
            noteId: "b1a93017-2c4e-4f95-8d61-0e7f3a2c9d84",
            orderedSqFt: 428,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(
                projectId: "3f9c1a52-7d6b-4e18-9a02-5c7d41be8f30",
                noteId: "b1a93017-2c4e-4f95-8d61-0e7f3a2c9d84",
                orderedSqFt: 428
            )],
            "One call, anchors unchanged — the server renders the copy from the project and note rows this id pair names"
        )
        XCTAssertEqual(outcome, .delivered, "A server that took the row is not a rail failure")
    }

    // MARK: - 2. The railFailed branch, both directions

    func test_draftedOrderRailFailureIsReportedAsRailFailed() async {
        let spy = VinylOrderDraftedSpy()
        spy.failure = URLError(.notConnectedToInternet)

        let outcome = await VinylOrderNotificationDispatcher.dispatchDrafted(
            projectId: "p-offline",
            noteId: "n-offline",
            orderedSqFt: 96,
            syncer: spy
        )

        XCTAssertEqual(
            outcome,
            .railFailed,
            "The order is already drafted server-side — the sheet must say the rail missed, not that the draft failed"
        )
        XCTAssertEqual(spy.calls.count, 1, "Best-effort: attempted exactly once, never retried into the draft path")
    }

    func test_draftedOrderNoopResultIsNotARailFailure() async {
        let spy = VinylOrderDraftedSpy()
        // The server already holds an unread row for this note. Nothing new was
        // written, but the crew is told — that is not a failure.
        spy.result = "noop"

        let outcome = await VinylOrderNotificationDispatcher.dispatchDrafted(
            projectId: "p-dedupe",
            noteId: "n-dedupe",
            orderedSqFt: 12,
            syncer: spy
        )

        XCTAssertEqual(outcome, .delivered, "A deduped row is a standing row — the status line must read clean")
    }

    // MARK: - 3. Vinyl bulk order: one summary, count verbatim

    func test_bulkSummaryForwardsMarkedCountVerbatim() async {
        let spy = VinylBulkOrderedSpy()

        await VinylBulkOrderNotificationDispatcher.dispatchSummary(markedCount: 7, syncer: spy)

        XCTAssertEqual(
            spy.markedCounts,
            [7],
            "One summary row per run carrying the marked count — seven jobs must never become seven calls, and the date is the server's clock"
        )
    }

    func test_bulkSummaryContainsTransportFailureAndKeepsWorking() async {
        let spy = VinylBulkOrderedSpy()
        spy.failure = URLError(.timedOut)

        await VinylBulkOrderNotificationDispatcher.dispatchSummary(markedCount: 3, syncer: spy)
        spy.failure = nil
        await VinylBulkOrderNotificationDispatcher.dispatchSummary(markedCount: 1, syncer: spy)

        XCTAssertEqual(
            spy.markedCounts,
            [3, 1],
            "The throw is swallowed at the seam: the jobs stay marked ordered and the next run still announces"
        )
    }

    // MARK: - 4. Offcut banked: stock unit + project verbatim

    func test_offcutBankedForwardsStockUnitAndProjectVerbatim() async {
        let spy = VinylOffcutBankedSpy()

        await VinylOffcutBankedNotificationDispatcher.dispatchBanked(
            userId: "user-cutter",
            stockUnitId: "8c31889e-4f2a-4b71-9d33-0a17c5be6d42",
            projectId: "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58",
            syncer: spy
        )
        await VinylOffcutBankedNotificationDispatcher.dispatchBanked(
            userId: "user-cutter",
            stockUnitId: "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3",
            projectId: nil,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [
                .init(
                    stockUnitId: "8c31889e-4f2a-4b71-9d33-0a17c5be6d42",
                    projectId: "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58"
                ),
                .init(stockUnitId: "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3", projectId: nil),
            ],
            "The banked row's own id crosses the seam — the server measures the strip from that row, so the copy can no longer disagree with stock. A bank off a project-less cut carries no project."
        )
    }

    func test_offcutBankedWithoutASignedInUserNeverTouchesTheSeamOrTheRail() async {
        let spy = VinylOffcutBankedSpy()

        let posts = await refreshPosts {
            await VinylOffcutBankedNotificationDispatcher.dispatchBanked(
                userId: "",
                stockUnitId: "stock-orphan",
                projectId: nil,
                syncer: spy
            )
        }

        XCTAssertTrue(spy.calls.isEmpty, "No operator, no rail row — a half-initialized session must not post as somebody")
        XCTAssertEqual(posts, 0, "Nothing was announced, so nothing asks the rail to refresh")
    }

    func test_offcutBankedRefreshesTheRailEvenWhenTheServerCallFails() async {
        let spy = VinylOffcutBankedSpy()
        spy.failure = URLError(.notConnectedToInternet)

        let posts = await refreshPosts {
            await VinylOffcutBankedNotificationDispatcher.dispatchBanked(
                userId: "user-cutter",
                stockUnitId: "stock-offline",
                projectId: "p-offline",
                syncer: spy
            )
        }

        XCTAssertEqual(spy.calls.count, 1, "Attempted once; the strip is already banked, so a failed rail row is not the cut's problem")
        XCTAssertEqual(posts, 1, "The local rail still refreshes — shipped behaviour, and the badge may hold rows this call knows nothing about")
    }

    // MARK: - 5. Guided setup: kind + counts land in their own slots

    func test_productSetupReportsItsProductAndRecipeCounts() async {
        let spy = GuidedSetupCompletionSpy()

        await GuidedSetupNotificationDispatcher.dispatch(
            .products(products: 12, recipes: 4),
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(
                kind: "product_setup",
                productCount: 12,
                recipeCount: 4,
                serviceCount: nil,
                goodCount: nil,
                assemblyCount: nil,
                familyCount: nil,
                variantCount: nil,
                rollCount: nil,
                offcutCount: nil,
                bundleCount: nil
            )],
            "Product setup reports products and recipes and nothing else — the server assembles the body from exactly these slots"
        )
    }

    func test_catalogSetupReportsItsServiceGoodAndAssemblyCounts() async {
        let spy = GuidedSetupCompletionSpy()

        await GuidedSetupNotificationDispatcher.dispatch(
            .catalog(services: 5, goods: 3, assemblies: 2),
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(
                kind: "catalog_setup",
                productCount: nil,
                recipeCount: nil,
                serviceCount: 5,
                goodCount: 3,
                assemblyCount: 2,
                familyCount: nil,
                variantCount: nil,
                rollCount: nil,
                offcutCount: nil,
                bundleCount: nil
            )],
            "Catalog setup reports services, goods, and packages — the counts the shipped summary line named"
        )
    }

    func test_stockSetupReportsAllSixStockCounts() async {
        let spy = GuidedSetupCompletionSpy()

        await GuidedSetupNotificationDispatcher.dispatch(
            .stock(families: 2, variants: 9, rolls: 4, offcuts: 6, products: 3, bundles: 1),
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(
                kind: "stock_setup",
                productCount: 3,
                recipeCount: nil,
                serviceCount: nil,
                goodCount: nil,
                assemblyCount: nil,
                familyCount: 2,
                variantCount: 9,
                rollCount: 4,
                offcutCount: 6,
                bundleCount: 1
            )],
            "Stock setup fills six slots — a family counted as a variant would misreport what the operator just built"
        )
    }

    // MARK: - 6. Guided setup: nothing built, nothing announced

    func test_guidedSetupWithNothingBuiltNeverTouchesTheSeamOrTheRail() async {
        let spy = GuidedSetupCompletionSpy()

        let posts = await refreshPosts {
            // A run that saved nothing: recipes without a product row cannot
            // stand alone, and an all-zero summary is rejected server-side.
            await GuidedSetupNotificationDispatcher.dispatch(.products(products: 0, recipes: 3), syncer: spy)
            await GuidedSetupNotificationDispatcher.dispatch(.catalog(services: 0, goods: 0, assemblies: 0), syncer: spy)
            await GuidedSetupNotificationDispatcher.dispatch(
                .stock(families: 0, variants: 0, rolls: 0, offcuts: 0, products: 0, bundles: 0),
                syncer: spy
            )
        }

        XCTAssertTrue(
            spy.calls.isEmpty,
            "Nothing was built, so there is nothing to announce — the gate holds before the call, not after"
        )
        XCTAssertEqual(posts, 0, "No row, no rail refresh")
    }

    func test_guidedSetupAnnouncesAndRefreshesTheRailOnSuccess() async {
        let spy = GuidedSetupCompletionSpy()

        let posts = await refreshPosts {
            await GuidedSetupNotificationDispatcher.dispatch(.catalog(services: 1, goods: 0, assemblies: 0), syncer: spy)
        }

        XCTAssertEqual(spy.calls.count, 1, "One saved service is work worth announcing")
        XCTAssertEqual(posts, 1, "The rail refreshes so the badge reflects the new row immediately")
    }

    func test_guidedSetupContainsTransportFailure() async {
        let spy = GuidedSetupCompletionSpy()
        spy.failure = URLError(.notConnectedToInternet)

        let posts = await refreshPosts {
            await GuidedSetupNotificationDispatcher.dispatch(.products(products: 2, recipes: 0), syncer: spy)
        }

        XCTAssertEqual(spy.calls.count, 1, "Attempted once — the catalog rows are already saved, so the flow must still close")
        XCTAssertEqual(posts, 1, "The rail refresh is unconditional once work was announced — shipped behaviour")
    }

    // MARK: - 7. Inventory threshold: the push follows the server's list

    func test_thresholdPushTargetsExactlyTheIdsTheServerGaveNewRows() async {
        let spy = InventoryThresholdSpy()
        spy.notified = ["manager-a", "manager-c"]
        let recorder = PushRecorder()

        let notified = await InventoryThresholdNotificationDispatcher.dispatch(
            itemId: "a417a994-6b21-4f0c-9e83-7d5c2b64af10",
            title: "Critical Stock Alert",
            body: "2x4 Lumber 8ft is critically low (3 remaining)",
            type: "inventory_critical",
            syncer: spy,
            push: { recorder.record($0) }
        )

        XCTAssertEqual(spy.itemIds, ["a417a994-6b21-4f0c-9e83-7d5c2b64af10"], "The item id crosses verbatim; the server recomputes the status from that row")
        XCTAssertEqual(notified, ["manager-a", "manager-c"])
        XCTAssertEqual(
            recorder.payloads,
            [.init(
                userIds: ["manager-a", "manager-c"],
                title: "Critical Stock Alert",
                body: "2x4 Lumber 8ft is critically low (3 remaining)",
                data: ["type": "inventory_critical", "screen": "inventory"]
            )],
            "The push reaches exactly the people the server gave a new rail row — never a locally guessed permission list"
        )
    }

    func test_thresholdWithNoNewRowsSkipsThePushEntirely() async {
        let spy = InventoryThresholdSpy()
        // The server recounted and found the item healthy — or everyone already
        // holds an unread alert for it. Either way there is nothing to push.
        spy.notified = []
        let recorder = PushRecorder()

        let notified = await InventoryThresholdNotificationDispatcher.dispatch(
            itemId: "item-healthy",
            title: "Low Stock Warning",
            body: "Deck screws is running low (40 remaining)",
            type: "inventory_warning",
            syncer: spy,
            push: { recorder.record($0) }
        )

        XCTAssertEqual(spy.itemIds, ["item-healthy"], "The server is still asked — only it knows the stored quantity and who already knows")
        XCTAssertTrue(notified.isEmpty)
        XCTAssertTrue(
            recorder.payloads.isEmpty,
            "An empty server list is an honest recount, not a reason to buzz phones off a stale local reading"
        )
    }

    func test_thresholdRailFailureIsContainedAndPushesNobody() async {
        let spy = InventoryThresholdSpy()
        spy.notified = ["manager-a"]
        spy.failure = URLError(.notConnectedToInternet)
        let recorder = PushRecorder()

        let notified = await InventoryThresholdNotificationDispatcher.dispatch(
            itemId: "item-offline",
            title: "Critical Stock Alert",
            body: "Anchors is critically low (0 remaining)",
            type: "inventory_critical",
            syncer: spy,
            push: { recorder.record($0) }
        )

        XCTAssertTrue(notified.isEmpty, "A failed rail call reports nobody — the quantity save it follows already succeeded")
        XCTAssertTrue(
            recorder.payloads.isEmpty,
            "Rail and push can no longer disagree: no server list, no push"
        )
        XCTAssertEqual(spy.itemIds.count, 1, "Attempted once, never retried into the save path")
    }
}
