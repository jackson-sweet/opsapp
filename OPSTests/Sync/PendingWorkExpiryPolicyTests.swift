//
//  PendingWorkExpiryPolicyTests.swift
//  OPSTests
//
//  Bug f71113a3 — pending work auto-deletes after 30 days. These tests pin the
//  ONLY question the policy answers: what may leave on its own, and what must
//  never be silently destroyed.
//
//  The line is criticality (bug a3f7cca8): stalled queue metadata — a failed
//  update, a dead lead-delivery request, an empty visit packet — expires; work
//  that exists only on this phone stays, wearing CRITICAL.
//
//  Pure: no SwiftData container, no wall clock. `now` is injected everywhere.
//

import XCTest
@testable import OPS

final class PendingWorkExpiryPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var day: TimeInterval { 24 * 60 * 60 }

    // MARK: - The boundary

    func testWorkOneHourShortOfThirtyDaysSurvives() {
        let item = looseOp(operationType: "update", status: "failed", age: 30 * day - 3_600)
        XCTAssertEqual(decision(item), .keep)
    }

    func testExactlyThirtyDaysExpires() {
        let item = looseOp(operationType: "update", status: "failed", age: 30 * day)
        guard case .expire(.deleteOperations(let ids)) = decision(item) else {
            return XCTFail("30 days exactly must expire — the interval is inclusive")
        }
        XCTAssertEqual(ids.count, 1)
    }

    func testTheExpiryAndTheStaleTagShareOneNumber() {
        let item = looseOp(operationType: "update", status: "failed", age: 30 * day)
        XCTAssertEqual(item.reviewState(now: now), .stale30Days)
        XCTAssertEqual(PendingWorkExpiryPolicy.expiryInterval, 30 * day)
    }

    // MARK: - Only stalled work expires

    /// A crew offline for five weeks reconnects and their queue SENDS. Nothing
    /// that is still progressing may be thrown away for being old.
    func testWaitingWorkNeverExpiresNoMatterHowOld() {
        let pending = looseOp(operationType: "update", status: "pending", age: 45 * day, tone: .waiting)
        XCTAssertEqual(decision(pending), .keep)

        let inFlight = looseOp(operationType: "update", status: "inProgress", age: 45 * day, tone: .waiting)
        XCTAssertEqual(decision(inFlight), .keep)
    }

    // MARK: - Loose operations

    func testStalledUpdateExpiresAndItsOwnIdIsTheScope() {
        let id = UUID()
        let item = looseOp(id: id, operationType: "update", status: "failed", age: 31 * day)
        XCTAssertEqual(decision(item), .expire(.deleteOperations([id])))
    }

    func testStalledDeleteExpires() {
        let item = looseOp(operationType: "delete", status: "parked", age: 31 * day)
        guard case .expire(.deleteOperations) = decision(item) else {
            return XCTFail("a stalled delete is queue metadata and may expire")
        }
    }

    /// A create op is the only path a whole record has to the server. Deleting
    /// it silently orphans that record on this phone forever.
    func testStalledCreateIsNeverDeleted() {
        XCTAssertEqual(
            decision(looseOp(operationType: "create", status: "parked", age: 31 * day)),
            .keep
        )
        XCTAssertEqual(
            decision(looseOp(operationType: "create", status: "failed", age: 400 * day)),
            .keep
        )
    }

    // MARK: - Lead delivery requests

    func testStalledLeadRequestExpires() {
        let item = autocreate(clientId: "CLIENT-1", age: 31 * day, lastError: "400 bad request")
        XCTAssertEqual(decision(item), .expire(.removeLeadRequest(clientId: "CLIENT-1")))
    }

    /// A lead parked behind its customer's refused create lives exactly as long
    /// as that create does — expiring the lead alone would strand a retried
    /// customer with no lead attached.
    func testLeadParkedBehindALiveCustomerCreateIsKept() {
        let item = autocreate(
            clientId: "client-1",
            age: 31 * day,
            lastError: "\(ClientLeadAutocreateError.clientCreateRejectedMarker) for client-1"
        )
        XCTAssertEqual(
            PendingWorkExpiryPolicy.decision(
                for: item,
                now: now,
                clientCreateOpExists: { $0 == "client-1" }
            ),
            .keep
        )
    }

    func testLeadWhoseCustomerCreateIsGoneExpires() {
        let item = autocreate(
            clientId: "client-1",
            age: 31 * day,
            lastError: "\(ClientLeadAutocreateError.clientCreateRejectedMarker) for client-1"
        )
        XCTAssertEqual(
            PendingWorkExpiryPolicy.decision(
                for: item,
                now: now,
                clientCreateOpExists: { _ in false }
            ),
            .expire(.removeLeadRequest(clientId: "client-1"))
        )
    }

    /// The customer-create exemption is scoped to the exact marker the queue
    /// writes. A lead that parked for its OWN reason expires normally.
    func testLeadParkedForItsOwnReasonExpiresEvenWithALiveCustomerCreate() {
        let item = autocreate(clientId: "client-1", age: 31 * day, lastError: "400 source_thread_key")
        XCTAssertEqual(
            PendingWorkExpiryPolicy.decision(
                for: item,
                now: now,
                clientCreateOpExists: { _ in true }
            ),
            .expire(.removeLeadRequest(clientId: "client-1"))
        )
    }

    // MARK: - Site-visit packets

    func testEmptyStalledPacketStopsItsSends() {
        let empty = bundle(capturedItemCount: 0, age: 31 * day)
        guard case .expire(.declineBundleSends(let expired)) = decision(.bundle(empty)) else {
            return XCTFail("an empty stalled packet is noise and may stop sending")
        }
        XCTAssertEqual(expired, empty)
    }

    /// Jackson's own line: an empty failed visit doesn't really matter, one
    /// carrying photos/deck/design is probably pretty critical.
    func testPacketCarryingEvenOneCapturedItemIsKept() {
        XCTAssertEqual(decision(.bundle(bundle(capturedItemCount: 1, age: 31 * day))), .keep)
        XCTAssertEqual(decision(.bundle(bundle(capturedItemCount: 12, age: 400 * day))), .keep)
    }

    /// A request already on the wire cannot be truthfully called off.
    func testEmptyPacketWithASendInFlightIsKept() {
        let inFlight = bundle(capturedItemCount: 0, age: 31 * day, hasOperationInFlight: true)
        XCTAssertEqual(decision(.bundle(inFlight)), .keep)
    }

    // MARK: - The never-silently-destroyed set

    func testTheOnlyCopyOfRealWorkNeverExpires() {
        let photos = RecoveryItem.photos(
            grouped: [
                PhotoSnapshot(
                    id: "photo-1",
                    entityType: "opportunity",
                    entityId: "opp-1",
                    status: "failed",
                    createdAt: now.addingTimeInterval(-400 * day)
                )
            ],
            tone: .attention
        )
        XCTAssertEqual(decision(photos), .keep)

        let draft = RecoveryItem.draft(
            DraftSnapshot(
                id: "draft-1",
                siteVisitId: "visit-1",
                clientId: nil,
                opportunityId: nil,
                displayName: "Site visit — Elm St",
                createdAt: now.addingTimeInterval(-400 * day),
                lastCommittedAt: nil
            )
        )
        XCTAssertEqual(decision(draft), .keep)

        let design = RecoveryItem.orphanDesign(
            OrphanDesignSnapshot(
                id: "design-1",
                title: "Back deck",
                createdAt: now.addingTimeInterval(-400 * day),
                hasThumbnail: false
            )
        )
        XCTAssertEqual(decision(design), .keep)

        let quarantine = RecoveryItem.quarantinedVisit(
            QuarantinedSiteVisitSnapshot(
                id: "quarantine-1",
                userId: "user-1",
                companyId: "company-1",
                siteVisitId: "visit-1",
                reason: .ambiguousBinding,
                createdAt: now.addingTimeInterval(-400 * day),
                capturedItemCount: 3
            )
        )
        XCTAssertEqual(decision(quarantine), .keep)
    }

    /// A device whose clock jumped backward simply defers expiry — it can never
    /// destroy work early.
    func testAClockThatRanBackwardsDefersExpiryRatherThanExpiringEarly() {
        let future = RecoveryItem.op(
            opSnapshot(
                id: UUID(),
                operationType: "update",
                status: "failed",
                createdAt: now.addingTimeInterval(10 * day)
            ),
            tone: .attention,
            nextEligibleAt: nil
        )
        XCTAssertEqual(decision(future), .keep)
    }

    // MARK: - Fixtures

    private func decision(_ item: RecoveryItem) -> PendingWorkExpiryDecision {
        PendingWorkExpiryPolicy.decision(
            for: item,
            now: now,
            clientCreateOpExists: { _ in false }
        )
    }

    private func opSnapshot(
        id: UUID,
        operationType: String,
        status: String,
        createdAt: Date
    ) -> SyncOpSnapshot {
        SyncOpSnapshot(
            id: id,
            entityType: "project",
            entityId: "project-1",
            operationType: operationType,
            status: status,
            retryCount: 20,
            lastAttemptedAt: createdAt,
            lastError: "server rejected",
            createdAt: createdAt
        )
    }

    private func looseOp(
        id: UUID = UUID(),
        operationType: String,
        status: String,
        age: TimeInterval,
        tone: RecoveryTone = .attention
    ) -> RecoveryItem {
        .op(
            opSnapshot(
                id: id,
                operationType: operationType,
                status: status,
                createdAt: now.addingTimeInterval(-age)
            ),
            tone: tone,
            nextEligibleAt: nil
        )
    }

    private func autocreate(
        clientId: String,
        age: TimeInterval,
        lastError: String?
    ) -> RecoveryItem {
        .autocreate(
            AutocreateSnapshot(
                clientId: clientId,
                name: "Charles",
                createdAt: now.addingTimeInterval(-age),
                attempts: 5,
                lastAttemptAt: now.addingTimeInterval(-600),
                lastError: lastError,
                isParked: true
            ),
            tone: .parked,
            nextEligibleAt: nil
        )
    }

    private func bundle(
        capturedItemCount: Int,
        age: TimeInterval,
        hasOperationInFlight: Bool = false
    ) -> SiteVisitBundle {
        let createdAt = now.addingTimeInterval(-age)
        let draft = DraftSnapshot(
            id: "draft-1",
            siteVisitId: "visit-1",
            clientId: nil,
            opportunityId: nil,
            displayName: "Site visit — Elm St",
            createdAt: createdAt,
            lastCommittedAt: nil
        )
        let operationId = UUID()
        return SiteVisitBundle(
            id: "bundle:draft-1",
            title: "Site visit — Elm St",
            createdAt: createdAt,
            members: [],
            tone: .attention,
            draft: draft,
            siteVisitId: "visit-1",
            capturedItemCount: capturedItemCount,
            manifest: capturedItemCount == 0
                ? .empty
                : RecoveryContentManifest(
                    photoCount: capturedItemCount,
                    deckCount: 0,
                    noteCount: 0,
                    measurementCount: 0,
                    answerCount: 0
                ),
            blockedStage: .visit,
            syncOperationIds: [operationId],
            hasOperationInFlight: hasOperationInFlight,
            siteVisitOperationIds: [operationId]
        )
    }
}
