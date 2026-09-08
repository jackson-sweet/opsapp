import SwiftData
import XCTest
@testable import OPS

final class RecoveryAttentionSummaryTests: XCTestCase {
    @MainActor
    func testHealthyCompactStatusDoesNotRequireCaptureOrDrawingTables() async throws {
        let schema = Schema([SyncOperation.self, LocalPhoto.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let summary = try await Task.detached {
            try RecoveryAttentionReader.read(container: container, companyId: "company", autocreates: [], quarantinedVisitIds: [])
        }.value
        XCTAssertEqual(summary, RecoveryAttentionSummary())
    }

    func testStageReviewRemainsOnePacketAndHasItsOwnDetailedMember() throws {
        let now = Date()
        let stage = SyncOpSnapshot(id: UUID(), entityType: "siteVisit", entityId: "visit",
            operationType: SiteVisitSyncOperation.stageOperationType, status: "parked", retryCount: 4,
            lastAttemptedAt: now, lastError: "STAGE REVIEW REQUIRED · OPEN LEAD", createdAt: now, siteVisitId: "visit")
        let completion = SyncOpSnapshot(id: UUID(), entityType: "siteVisit", entityId: "visit",
            operationType: SiteVisitSyncOperation.completionOperationType, status: "pending", retryCount: 0,
            lastAttemptedAt: nil, lastError: nil, createdAt: now, siteVisitId: "visit")
        let detailed = RecoveryInventory.build(ops: [completion, stage], autocreates: [], photos: [], drafts: [], artifacts: [], orphans: [], now: now)
        let compact = RecoveryInventory.attentionSummary(ops: [completion, stage], autocreates: [], photos: [], drafts: [], deckArtifacts: [])
        XCTAssertEqual(compact.attentionCount, 1)
        XCTAssertTrue(compact.anyParked)
        guard case .bundle(let bundle) = try XCTUnwrap(detailed.attention.first) else { return XCTFail("Expected packet") }
        XCTAssertEqual(bundle.blockedStage, .leadStage)
        XCTAssertEqual(bundle.members.count, 2)
        XCTAssertEqual(Set(bundle.syncOperationIds), [completion.id, stage.id])
        XCTAssertEqual(bundle.members.first(where: { $0.role == .other("lead stage") })?.syncOpId, stage.id)
        XCTAssertEqual(SyncStatusCopy.PendingWork.siteVisitPacketSummary(capturedItemCount: 0, blockedStage: bundle.blockedStage), "0 CAPTURED · LEAD STAGE")
    }

    func testCompactSummaryMatchesDetailedInventoryForMixedAndBundledWork() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drafts = [DraftSnapshot(id: "draft", siteVisitId: "visit", clientId: "client", opportunityId: "lead", displayName: "Synthetic", createdAt: now, lastCommittedAt: nil)]
        let artifacts = [ArtifactSnapshot(id: "artifact", siteVisitId: "visit", deckDesignId: "deck", kind: "deck")]
        let statuses = ["pending", "inProgress", "failed", "parked", "completed", "declined"]
        for first in statuses {
            for second in statuses {
                let ops = [op("client", "client", first, now), op("deckDesign", "deck", second, now), op("siteVisit", "other", second, now, visit: "other")]
                let autos = [AutocreateSnapshot(clientId: "client", name: "Synthetic", createdAt: now, attempts: 1, lastAttemptAt: nil, lastError: nil, isParked: first == "parked")]
                let photos = [PhotoSnapshot(id: "photo", entityType: "opportunity", entityId: "lead", status: "failed", createdAt: now)]
                let detailed = RecoveryInventory.build(ops: ops, autocreates: autos, photos: photos, drafts: drafts, artifacts: artifacts, orphans: [], now: now)
                let compact = RecoveryInventory.attentionSummary(ops: ops, autocreates: autos, photos: photos, drafts: drafts, deckArtifacts: artifacts)
                XCTAssertEqual(compact.attentionCount, detailed.attentionCount)
                XCTAssertEqual(compact.anyParked, detailed.attention.contains { $0.tone == .parked })
            }
        }
    }

    func testQuarantineSuppressesDraftJoinAndCompletedHistoryDoesNotAffectBadge() {
        let now = Date()
        let drafts = [DraftSnapshot(id: "draft", siteVisitId: "visit", clientId: "client", opportunityId: nil, displayName: "", createdAt: now, lastCommittedAt: nil)]
        let quarantine = QuarantinedSiteVisitSnapshot(id: "q", userId: "user", companyId: "company", siteVisitId: "visit", reason: .parentDeleted, createdAt: now, capturedItemCount: 1)
        let history = (0..<2625).map { op("project", "history-\($0)", "completed", now) }
        let ops = history + [op("client", "client", "failed", now), op("siteVisit", "visit", "parked", now, visit: "visit")]
        let detailed = RecoveryInventory.build(ops: ops, autocreates: [], photos: [], drafts: drafts, artifacts: [], orphans: [], quarantines: [quarantine], now: now)
        let compact = RecoveryInventory.attentionSummary(ops: ops, autocreates: [], photos: [], drafts: drafts, deckArtifacts: [], quarantinedVisitIds: ["visit"])
        XCTAssertEqual(compact.attentionCount, detailed.attentionCount)
        XCTAssertEqual(compact.attentionCount, 2)
        XCTAssertTrue(compact.anyParked)
    }

    /// Bug 7a726160 — every home-swipe killed the app. Backgrounding fails an
    /// in-flight upload, the save wakes `RecoveryRefreshMonitor`, and the compact
    /// reader finally reaches its deck-artifact join — whose `#Predicate` used
    /// `deckDesignId ?? ""`. SwiftData cannot translate nil-coalescing, Core Data
    /// raised an Objective-C exception inside `performAndWait`, and the process
    /// aborted on a utility thread (eleven identical crash reports on the
    /// founder's phone, 2026-09-08). The healthy-path test above never reaches
    /// this branch; this one seeds exactly the store shape that does.
    @MainActor
    func testAttentionBranchJoinsDeckArtifactsWithoutTrapping() async throws {
        let schema = Schema([SyncOperation.self, LocalPhoto.self, SiteVisitIdentityDraft.self, SiteVisitCaptureArtifact.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // A live deck-design operation makes `deckIds` non-empty; a failed
        // client operation gets the reader past its "nothing needs attention"
        // early return — the two conditions the crashing branch requires.
        let deckOp = SyncOperation(entityType: "deckDesign", entityId: "DECK-1", operationType: "update", payload: Data(), changedFields: [])
        let failedClientOp = SyncOperation(entityType: "client", entityId: "client-1", operationType: "create", payload: Data(), changedFields: [])
        failedClientOp.status = "failed"
        context.insert(deckOp)
        context.insert(failedClientOp)
        // An uncommitted identity draft is what pulls the deck artifacts in.
        context.insert(SiteVisitIdentityDraft(siteVisitId: "visit-1", companyId: "company", notes: "Synthetic"))
        context.insert(SiteVisitCaptureArtifact(
            siteVisitId: "visit-1", companyId: "company",
            kind: .deckDesign, source: .deckBuilder, deckDesignId: "deck-1"
        ))
        try context.save()

        let summary = try await Task.detached(priority: .utility) {
            try RecoveryAttentionReader.read(container: container, companyId: "company", autocreates: [], quarantinedVisitIds: [])
        }.value

        // The deck op joins the draft's packet (pending tone, no attention);
        // the failed client op stands alone as the single attention item.
        XCTAssertEqual(summary.attentionCount, 1)
        XCTAssertFalse(summary.anyParked)
    }

    private func op(_ type: String, _ id: String, _ status: String, _ date: Date, visit: String? = nil) -> SyncOpSnapshot {
        SyncOpSnapshot(id: UUID(), entityType: type, entityId: id, operationType: "update", status: status, retryCount: 0, lastAttemptedAt: nil, lastError: nil, createdAt: date, siteVisitId: visit)
    }
}
