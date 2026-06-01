//
//  GuidedStockCommitOrchestrationTests.swift
//  OPSTests
//
//  TDD coverage for GuidedStockSetupModel.commitAll:
//  - multi-family success → .complete, correct summary counts, draft cleared
//  - mid-loop failure → .partial, prior groups recorded, failed group NOT recorded
//  - retry after partial skips already-committed, re-sends only the failed group
//  - offline guard → .idle, zero commits issued
//  - bundle ordering → bundle group commits AFTER non-bundle groups
//

import XCTest
@testable import OPS

// MARK: - Test double

@MainActor
private final class FakeCommitService: CatalogSetupCommitting {

    /// Every draftId whose commit was called, in order.
    var recordedDraftIds: [String] = []
    var reconcileCallCount = 0

    /// Closure-based scripting: return .committed or .rejected per payload.
    var scriptedOutcome: (CatalogSetupSavePayload) -> CatalogSetupCommitOutcome = { payload in
        let draftId = payload.draftId
        return .committed(
            CatalogSetupSaveResponse(
                ok: true,
                idMap: [
                    payload.family.clientId: "srv-\(draftId)",
                    "product::\(draftId)": "psrv-\(draftId)"
                ]
            )
        )
    }

    func commit(
        payload: CatalogSetupSavePayload,
        saveAttempt: CatalogSetupSaveAttempt
    ) async throws -> CatalogSetupCommitOutcome {
        recordedDraftIds.append(payload.draftId)
        return scriptedOutcome(payload)
    }

    func reconcile(
        payload: CatalogSetupSavePayload,
        response: CatalogSetupSaveResponse
    ) -> CatalogSetupReconcileResult {
        reconcileCallCount += 1
        return .clean
    }
}

// MARK: - Helpers

@MainActor
private func tempStore() -> GuidedStockSetupDraftStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("guided-orchestration-\(UUID().uuidString)", isDirectory: true)
    return GuidedStockSetupDraftStore(rootURL: dir)
}

/// Builds a minimal confirmed single-item group with a .piece measurement and one
/// stock entry, so that validateStockQuantities passes and a payload can be built.
/// `variantKey` must match the variant id emitted by GuidedStockDraftBuilder for a
/// single-item group: "\(id)::single".
private func makeConfirmedGroup(
    id: String,
    familyName: String,
    memberItemIds: [String]? = nil,
    sellMode: GuidedSellMode? = nil,
    bundleChildren: [GuidedBundleChild] = []
) -> GuidedStructuredGroup {
    let effectiveMemberIds = memberItemIds ?? [id]
    return GuidedStructuredGroup(
        id: id,
        familyName: familyName,
        memberItemIds: effectiveMemberIds,
        isSingleItem: true,
        attributes: [],
        measurement: .piece,
        stockEntries: [
            GuidedStockEntry(variantKey: "\(id)::single", pieceCount: 1)
        ],
        product: GuidedProductAnswers(
            sellMode: sellMode,
            sellingUsesStock: nil,
            bundleChildren: bundleChildren
        ),
        isConfirmed: true
    )
}

private let noopResolve: (GuidedMeasurement) async throws -> String = { _ in "unit-1" }

// MARK: - Tests

@MainActor
final class GuidedStockCommitOrchestrationTests: XCTestCase {

    // MARK: Multi-family success

    func test_multiFamily_success_completesWithCounts() async {
        let model = GuidedStockSetupModel(companyId: "co-1", userId: "u1", draftStore: tempStore())
        let g1 = makeConfirmedGroup(id: "grp-1", familyName: "Vinyl")
        let g2 = makeConfirmedGroup(id: "grp-2", familyName: "Carpet")
        model.groups = [g1, g2]

        let fake = FakeCommitService()
        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: true)

        // Progress must be .complete
        guard case .complete(let summary) = model.commitProgress else {
            return XCTFail("Expected .complete, got \(model.commitProgress)")
        }

        // Both groups committed
        XCTAssertEqual(summary.familyCount, 2)
        XCTAssertTrue(model.committedGroupIds.contains("grp-1"))
        XCTAssertTrue(model.committedGroupIds.contains("grp-2"))

        // Fake recorded exactly two commits
        XCTAssertEqual(fake.recordedDraftIds.count, 2)

        // Draft cleared after success
        XCTAssertFalse(model.hasDraftToResume, "Draft must be cleared on full success")
    }

    // MARK: Mid-loop failure → partial

    func test_midLoopFailure_isPartial_priorCommitted() async {
        let model = GuidedStockSetupModel(companyId: "co-1", userId: "u1", draftStore: tempStore())
        let g1 = makeConfirmedGroup(id: "grp-1", familyName: "Vinyl")
        let g2 = makeConfirmedGroup(id: "grp-2", familyName: "Carpet")
        model.groups = [g1, g2]

        let fake = FakeCommitService()
        // Succeed g1, fail g2
        fake.scriptedOutcome = { payload in
            if payload.draftId == "grp-2" {
                return .rejected(message: "server rejected")
            }
            return .committed(
                CatalogSetupSaveResponse(
                    ok: true,
                    idMap: [
                        payload.family.clientId: "srv-\(payload.draftId)",
                        "product::\(payload.draftId)": "psrv-\(payload.draftId)"
                    ]
                )
            )
        }

        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: true)

        guard case .partial(let failedIds) = model.commitProgress else {
            return XCTFail("Expected .partial, got \(model.commitProgress)")
        }
        XCTAssertEqual(failedIds, ["grp-2"])

        // g1 committed; g2 not
        XCTAssertTrue(model.committedGroupIds.contains("grp-1"), "g1 must be in committedGroupIds")
        XCTAssertFalse(model.committedGroupIds.contains("grp-2"), "g2 must NOT be in committedGroupIds")
    }

    // MARK: Retry after partial skips committed, re-sends failed

    func test_retry_afterPartial_skipsCommitted_resendsFailed() async {
        let model = GuidedStockSetupModel(companyId: "co-1", userId: "u1", draftStore: tempStore())
        let g1 = makeConfirmedGroup(id: "grp-1", familyName: "Vinyl")
        let g2 = makeConfirmedGroup(id: "grp-2", familyName: "Carpet")
        model.groups = [g1, g2]

        // First run: fail g2
        let fake = FakeCommitService()
        fake.scriptedOutcome = { payload in
            if payload.draftId == "grp-2" {
                return .rejected(message: "server rejected")
            }
            return .committed(
                CatalogSetupSaveResponse(
                    ok: true,
                    idMap: [
                        payload.family.clientId: "srv-\(payload.draftId)",
                        "product::\(payload.draftId)": "psrv-\(payload.draftId)"
                    ]
                )
            )
        }
        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: true)

        // Reset fake for second run; now succeed everything
        fake.recordedDraftIds = []
        fake.scriptedOutcome = { payload in
            return .committed(
                CatalogSetupSaveResponse(
                    ok: true,
                    idMap: [
                        payload.family.clientId: "srv-\(payload.draftId)",
                        "product::\(payload.draftId)": "psrv-\(payload.draftId)"
                    ]
                )
            )
        }

        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: true)

        // Second run must have sent ONLY grp-2 (grp-1 was already committed)
        XCTAssertEqual(fake.recordedDraftIds, ["grp-2"],
                       "Retry must skip the already-committed group and resend only the failed one")

        // Final state: complete
        guard case .complete = model.commitProgress else {
            return XCTFail("Expected .complete on retry, got \(model.commitProgress)")
        }
    }

    // MARK: Offline guard

    func test_offline_holdsWithoutCommitting() async {
        let model = GuidedStockSetupModel(companyId: "co-1", userId: "u1", draftStore: tempStore())
        model.groups = [makeConfirmedGroup(id: "grp-1", familyName: "Vinyl")]

        let fake = FakeCommitService()
        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: false)

        guard case .idle = model.commitProgress else {
            return XCTFail("Expected .idle when offline, got \(model.commitProgress)")
        }
        XCTAssertEqual(fake.recordedDraftIds.count, 0, "No commits must be issued when offline")
    }

    // MARK: Bundle ordering

    func test_bundleOrdering_bundleCommitsAfterChildren() async {
        // Three groups: two normal (g1, g2) and one bundle (gb) that references them.
        let g1 = makeConfirmedGroup(id: "grp-child-1", familyName: "Widget A", memberItemIds: ["item-1"])
        let g2 = makeConfirmedGroup(id: "grp-child-2", familyName: "Widget B", memberItemIds: ["item-2"])
        let gb = makeConfirmedGroup(
            id: "grp-bundle",
            familyName: "Kit",
            memberItemIds: ["item-bundle"],
            sellMode: .inPackage,
            bundleChildren: [
                GuidedBundleChild(capturedItemId: "item-1", isRequired: true),
                GuidedBundleChild(capturedItemId: "item-2", isRequired: true)
            ]
        )

        let model = GuidedStockSetupModel(companyId: "co-1", userId: "u1", draftStore: tempStore())
        // Deliberately seed with bundle first to prove ordering is NOT insertion order
        model.groups = [gb, g1, g2]

        let fake = FakeCommitService()
        await model.commitAll(service: fake, resolveUnitId: noopResolve, isOnline: true)

        // Bundle group must appear LAST in commit order
        XCTAssertEqual(fake.recordedDraftIds.count, 3, "All three groups must be committed")
        XCTAssertEqual(fake.recordedDraftIds.last, "grp-bundle",
                       "Bundle group must commit AFTER its child groups")

        // Non-bundle groups must appear before the bundle
        let bundleIndex = fake.recordedDraftIds.firstIndex(of: "grp-bundle")!
        let child1Index = fake.recordedDraftIds.firstIndex(of: "grp-child-1")!
        let child2Index = fake.recordedDraftIds.firstIndex(of: "grp-child-2")!
        XCTAssertLessThan(child1Index, bundleIndex, "grp-child-1 must commit before grp-bundle")
        XCTAssertLessThan(child2Index, bundleIndex, "grp-child-2 must commit before grp-bundle")
    }
}
