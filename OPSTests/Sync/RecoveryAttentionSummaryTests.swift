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

    private func op(_ type: String, _ id: String, _ status: String, _ date: Date, visit: String? = nil) -> SyncOpSnapshot {
        SyncOpSnapshot(id: UUID(), entityType: type, entityId: id, operationType: "update", status: status, retryCount: 0, lastAttemptedAt: nil, lastError: nil, createdAt: date, siteVisitId: visit)
    }
}
