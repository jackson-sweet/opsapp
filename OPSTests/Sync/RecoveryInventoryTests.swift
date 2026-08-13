//
//  RecoveryInventoryTests.swift
//  OPSTests
//
//  SYNC RECOVERY · T5 — exhaustive coverage of the pure PENDING WORK inventory
//  builder (spec §4). Every test constructs plain snapshots directly (no
//  SwiftData container) and drives the real `RecoveryInventory.build(...)`, with a
//  fixed `now` so results are byte-deterministic.
//
//  Branches covered: bundle join for all four roles + case-insensitive keys;
//  worst-tone precedence (parked > attention > waiting); member consumption (no
//  double-render); draft-section vs healthy-draft omission; loose op/autocreate/
//  photo placement by tone; completed-op exclusion; photo grouping by entityId;
//  orphan ordering; counts / totalActive / isEmpty; nextEligibleAt for both
//  backoff formulas (present in future, nil when elapsed / non-retrying); and
//  order-independence of the output for a fixed `now`.
//

import XCTest
@testable import OPS

@MainActor
final class RecoveryInventoryTests: XCTestCase {
    func test_quarantinedSiteVisitRendersOnlyAsProtectedUnlinkedWork() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let quarantine = QuarantinedSiteVisitSnapshot(
            id: "quarantine-1",
            userId: "user-1",
            companyId: "company-1",
            siteVisitId: "visit-1",
            reason: .ambiguousBinding,
            createdAt: now,
            capturedItemCount: 2
        )

        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [
                DraftSnapshot(
                    id: "draft-1",
                    siteVisitId: "VISIT-1",
                    clientId: nil,
                    opportunityId: nil,
                    displayName: "Duplicate draft row",
                    createdAt: now,
                    lastCommittedAt: nil
                ),
            ],
            artifacts: [],
            orphans: [],
            quarantines: [quarantine],
            now: now
        )

        XCTAssertTrue(inventory.attention.isEmpty)
        XCTAssertTrue(inventory.sending.isEmpty)
        XCTAssertTrue(inventory.drafts.isEmpty)
        XCTAssertEqual(inventory.unlinked, [.quarantinedVisit(quarantine)])
    }


    // MARK: - Fixtures

    /// Snapshot creation instant baseline; offsets keep events ordered.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    /// The fixed "now" every build uses.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func opSnap(
        id: UUID = UUID(),
        entityType: String = "client",
        entityId: String = "c1",
        operationType: String = "update",
        status: String = "pending",
        retryCount: Int = 0,
        lastAttemptedAt: Date? = nil,
        lastError: String? = nil,
        createdAt: Date? = nil,
        siteVisitId: String? = nil
    ) -> SyncOpSnapshot {
        SyncOpSnapshot(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            status: status,
            retryCount: retryCount,
            lastAttemptedAt: lastAttemptedAt,
            lastError: lastError,
            createdAt: createdAt ?? base,
            siteVisitId: siteVisitId
        )
    }

    private func autocreateSnap(
        clientId: String = "c1",
        name: String = "Amber Chen",
        createdAt: Date? = nil,
        attempts: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil,
        isParked: Bool = false
    ) -> AutocreateSnapshot {
        AutocreateSnapshot(
            clientId: clientId,
            name: name,
            createdAt: createdAt ?? base,
            attempts: attempts,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            isParked: isParked
        )
    }

    private func photoSnap(
        id: String = UUID().uuidString,
        entityType: String = "projectPhoto",
        entityId: String = "e1",
        status: String = "local",
        createdAt: Date? = nil
    ) -> PhotoSnapshot {
        PhotoSnapshot(
            id: id,
            entityType: entityType,
            entityId: entityId,
            status: status,
            createdAt: createdAt ?? base
        )
    }

    private func draftSnap(
        id: String = UUID().uuidString,
        siteVisitId: String = "v1",
        clientId: String? = "c1",
        opportunityId: String? = nil,
        displayName: String = "Charles",
        createdAt: Date? = nil,
        lastCommittedAt: Date? = nil
    ) -> DraftSnapshot {
        DraftSnapshot(
            id: id,
            siteVisitId: siteVisitId,
            clientId: clientId,
            opportunityId: opportunityId,
            displayName: displayName,
            createdAt: createdAt ?? base,
            lastCommittedAt: lastCommittedAt
        )
    }

    private func artifactSnap(
        id: String = UUID().uuidString,
        siteVisitId: String = "v1",
        deckDesignId: String? = "d1",
        kind: String = "deck_design"
    ) -> ArtifactSnapshot {
        ArtifactSnapshot(id: id, siteVisitId: siteVisitId, deckDesignId: deckDesignId, kind: kind)
    }

    private func orphanSnap(
        id: String = UUID().uuidString,
        title: String = "Site visit deck",
        createdAt: Date? = nil,
        hasThumbnail: Bool = false
    ) -> OrphanDesignSnapshot {
        OrphanDesignSnapshot(id: id, title: title, createdAt: createdAt ?? base, hasThumbnail: hasThumbnail)
    }

    private func build(
        ops: [SyncOpSnapshot] = [],
        autocreates: [AutocreateSnapshot] = [],
        photos: [PhotoSnapshot] = [],
        drafts: [DraftSnapshot] = [],
        artifacts: [ArtifactSnapshot] = [],
        orphans: [OrphanDesignSnapshot] = []
    ) -> RecoveryInventory {
        RecoveryInventory.build(
            ops: ops,
            autocreates: autocreates,
            photos: photos,
            drafts: drafts,
            artifacts: artifacts,
            orphans: orphans,
            now: now
        )
    }

    // MARK: - Extractors

    private func bundles(_ items: [RecoveryItem]) -> [SiteVisitBundle] {
        items.compactMap { if case let .bundle(bundle) = $0 { return bundle } else { return nil } }
    }

    private func looseOps(_ items: [RecoveryItem]) -> [(SyncOpSnapshot, RecoveryTone, Date?)] {
        items.compactMap { if case let .op(snap, tone, next) = $0 { return (snap, tone, next) } else { return nil } }
    }

    private func looseAutocreates(_ items: [RecoveryItem]) -> [(AutocreateSnapshot, RecoveryTone, Date?)] {
        items.compactMap { if case let .autocreate(snap, tone, next) = $0 { return (snap, tone, next) } else { return nil } }
    }

    private func loosePhotos(_ items: [RecoveryItem]) -> [([PhotoSnapshot], RecoveryTone)] {
        items.compactMap { if case let .photos(group, tone) = $0 { return (group, tone) } else { return nil } }
    }

    private func draftItems(_ items: [RecoveryItem]) -> [DraftSnapshot] {
        items.compactMap { if case let .draft(draft) = $0 { return draft } else { return nil } }
    }

    private func orphanItems(_ items: [RecoveryItem]) -> [OrphanDesignSnapshot] {
        items.compactMap { if case let .orphanDesign(design) = $0 { return design } else { return nil } }
    }

    // MARK: - Retention and discard capabilities

    func testUnsentWorkIsRetainedAtTwentyNineThirtyAndThirtyOneDays() {
        let day: TimeInterval = 24 * 60 * 60
        let drafts = [29, 30, 31].map { age in
            draftSnap(
                id: "draft-\(age)",
                siteVisitId: "visit-\(age)",
                clientId: nil,
                createdAt: now.addingTimeInterval(-Double(age) * day)
            )
        }

        let inventory = build(drafts: drafts)

        XCTAssertEqual(inventory.drafts.count, 3)
        let states = Dictionary(uniqueKeysWithValues: inventory.drafts.map {
            ($0.id, $0.reviewState(now: now))
        })
        XCTAssertEqual(states["draft-29"], .current)
        XCTAssertEqual(states["draft-30"], .stale30Days)
        XCTAssertEqual(states["draft-31"], .stale30Days)
    }

    func testEveryRecoveryItemDeclaresAnHonestDiscardCapability() {
        let pendingOp = RecoveryItem.op(
            opSnap(operationType: "create"),
            tone: .waiting,
            nextEligibleAt: nil
        )
        XCTAssertEqual(
            pendingOp.discardPolicy,
            .unavailable(.queuedMutationRequiresReconciliation)
        )

        let activeLead = RecoveryItem.autocreate(
            autocreateSnap(isParked: false),
            tone: .waiting,
            nextEligibleAt: nil
        )
        XCTAssertEqual(
            activeLead.discardPolicy,
            .unavailable(.deliveryMayBeInProgress)
        )

        let parkedLead = RecoveryItem.autocreate(
            autocreateSnap(isParked: true),
            tone: .parked,
            nextEligibleAt: nil
        )
        XCTAssertEqual(
            parkedLead.discardPolicy,
            .available(.leadDeliveryRequest)
        )

        let localPhotos = RecoveryItem.photos(
            grouped: [photoSnap(status: "local")],
            tone: .waiting
        )
        XCTAssertEqual(
            localPhotos.discardPolicy,
            .unavailable(.uploadMayBeInProgress)
        )

        let failedPhotos = RecoveryItem.photos(
            grouped: [photoSnap(status: "failed"), photoSnap(status: "failed")],
            tone: .attention
        )
        XCTAssertEqual(
            failedPhotos.discardPolicy,
            .available(.localPhotos(count: 2))
        )

        let draft = draftSnap(clientId: nil)
        XCTAssertEqual(
            RecoveryItem.draft(draft).discardPolicy,
            .unavailable(.draftRequiresResume)
        )

        let orphan = orphanSnap()
        XCTAssertEqual(
            RecoveryItem.orphanDesign(orphan).discardPolicy,
            .unavailable(.designRequiresReview)
        )

        let quarantine = QuarantinedSiteVisitSnapshot(
            id: "quarantine",
            userId: "user",
            companyId: "company",
            siteVisitId: "visit",
            reason: .ambiguousBinding,
            createdAt: base,
            capturedItemCount: 1
        )
        XCTAssertEqual(
            RecoveryItem.quarantinedVisit(quarantine).discardPolicy,
            .available(.quarantinedVisit(capturedItemCount: 1))
        )
    }

    /// PENDING WORK deletes queued SENDS, not records — so only the two scopes
    /// that really erase the phone's only copy may warn as destructive. A
    /// stopped send must never borrow that language.
    func testOnlyScopesThatEraseTheOnlyCopyAreDestructive() {
        XCTAssertTrue(RecoveryDiscardScope.localPhotos(count: 3).isDestructive)
        XCTAssertTrue(
            RecoveryDiscardScope.quarantinedVisit(capturedItemCount: 4).isDestructive
        )
        XCTAssertFalse(RecoveryDiscardScope.queuedSends(count: 2).isDestructive)
        XCTAssertFalse(RecoveryDiscardScope.leadDeliveryRequest.isDestructive)
    }

    func testSiteVisitDiscardIsAvailableOnlyWhenNoStageIsExecuting() throws {
        let draft = draftSnap(siteVisitId: "visit", clientId: nil)
        let pending = opSnap(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: "visit",
            operationType: "create",
            status: "pending",
            siteVisitId: "visit"
        )
        let pendingInventory = build(ops: [pending], drafts: [draft])
        let pendingBundle = try XCTUnwrap(
            (pendingInventory.sending + pendingInventory.attention).first
        )
        XCTAssertEqual(
            pendingBundle.discardPolicy,
            .available(.queuedSends(count: 1))
        )

        let executing = opSnap(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: "visit",
            operationType: "create",
            status: "inProgress",
            siteVisitId: "visit"
        )
        let executingInventory = build(ops: [executing], drafts: [draft])
        let executingBundle = try XCTUnwrap(
            (executingInventory.sending + executingInventory.attention).first
        )
        XCTAssertEqual(
            executingBundle.discardPolicy,
            .unavailable(.operationInProgress)
        )
    }

    // MARK: - Bundle join (all roles) + consumption

    func testBundleJoinsAllFourRolesInOrderAndConsumesMembers() {
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1", opportunityId: "opp1")
        let clientOp = opSnap(entityType: "client", entityId: "c1", operationType: "create", status: "pending")
        let deckOp = opSnap(entityType: "deckDesign", entityId: "d1", operationType: "linkOpportunity", status: "failed")
        let inventory = build(
            ops: [clientOp, deckOp],
            autocreates: [autocreateSnap(clientId: "c1")],
            photos: [photoSnap(entityId: "opp1", status: "local")],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        )

        // Exactly one bundle, no loose items — every member was consumed.
        XCTAssertEqual(bundles(inventory.attention).count, 1)
        XCTAssertTrue(looseOps(inventory.attention).isEmpty)
        XCTAssertTrue(looseOps(inventory.sending).isEmpty)
        XCTAssertTrue(looseAutocreates(inventory.attention).isEmpty)
        XCTAssertTrue(looseAutocreates(inventory.sending).isEmpty)
        XCTAssertTrue(loosePhotos(inventory.attention).isEmpty)
        XCTAssertTrue(loosePhotos(inventory.sending).isEmpty)

        let bundle = bundles(inventory.attention)[0]
        XCTAssertEqual(bundle.id, "bundle:\(draft.id)")
        XCTAssertEqual(bundle.title, "Charles")
        XCTAssertEqual(bundle.members.map(\.role), [.client, .lead, .deck, .photos])

        // The photos member carries the one photo id.
        guard let photosMember = bundle.members.first(where: { $0.role == .photos }) else {
            return XCTFail("expected a photos member")
        }
        XCTAssertEqual(photosMember.photoIds.count, 1)
        // The client member references its op id.
        guard let clientMember = bundle.members.first(where: { $0.role == .client }) else {
            return XCTFail("expected a client member")
        }
        XCTAssertEqual(clientMember.syncOpId, clientOp.id)
        // The lead member references the client id.
        guard let leadMember = bundle.members.first(where: { $0.role == .lead }) else {
            return XCTFail("expected a lead member")
        }
        XCTAssertEqual(leadMember.autocreateClientId, "c1")
    }

    func testBundleToneIsWorstMemberParked() {
        // waiting client op + attention (failed) deck op + parked autocreate → parked.
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1")
        let inventory = build(
            ops: [
                opSnap(entityType: "client", entityId: "c1", status: "pending"),
                opSnap(entityType: "deckDesign", entityId: "d1", status: "failed")
            ],
            autocreates: [autocreateSnap(clientId: "c1", isParked: true)],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        )

        let bundle = bundles(inventory.attention).first
        XCTAssertEqual(bundle?.tone, .parked)
        XCTAssertEqual(inventory.attention.count, 1)
        XCTAssertTrue(inventory.sending.isEmpty)
    }

    func testBundleWithOnlyWaitingMembersLandsInSending() {
        let draft = draftSnap(clientId: "c1")
        let inventory = build(
            ops: [opSnap(entityType: "client", entityId: "c1", status: "pending")],
            drafts: [draft]
        )
        XCTAssertTrue(inventory.attention.isEmpty)
        XCTAssertEqual(bundles(inventory.sending).count, 1)
        XCTAssertEqual(bundles(inventory.sending).first?.tone, .waiting)
    }

    func testCloudPacketGroupsVisitRowsMediaAndCompletionIntoOneRecoveryItem() {
        let parent = opSnap(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: "v1",
            operationType: "create",
            status: "pending",
            siteVisitId: "v1"
        )
        let artifact = opSnap(
            entityType: SyncEntityType.siteVisitArtifact.rawValue,
            entityId: "artifact-1",
            operationType: "create",
            status: "failed",
            siteVisitId: "v1"
        )
        let media = opSnap(
            entityType: SyncEntityType.siteVisitArtifact.rawValue,
            entityId: "artifact-1",
            operationType: SiteVisitSyncOperation.mediaOperationType,
            status: "parked",
            siteVisitId: "v1"
        )
        let answer = opSnap(
            entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
            entityId: "answer-1",
            operationType: "create",
            status: "pending",
            siteVisitId: "v1"
        )
        let completion = opSnap(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: "v1",
            operationType: SiteVisitSyncOperation.completionOperationType,
            status: "pending",
            siteVisitId: "v1"
        )

        let inventory = build(ops: [parent, artifact, media, answer, completion])

        let packetRows = bundles(inventory.attention)
        XCTAssertEqual(packetRows.count, 1)
        XCTAssertTrue(inventory.sending.isEmpty)
        XCTAssertTrue(looseOps(inventory.attention).isEmpty)

        let bundle = try! XCTUnwrap(packetRows.first)
        XCTAssertEqual(bundle.id, "visit:v1")
        XCTAssertEqual(bundle.siteVisitId, "v1")
        XCTAssertEqual(bundle.capturedItemCount, 2, "media retries must not double-count their artifact")
        XCTAssertEqual(bundle.blockedStage, .media)
        XCTAssertEqual(bundle.members.map(\.role), [
            .other("visit"), .other("media"), .other("completion")
        ])
        XCTAssertEqual(Set(bundle.syncOperationIds), Set([parent.id, artifact.id, media.id, answer.id, completion.id]))
    }

    func testCloudPacketJoinsExistingDraftAndLegacyMembersWithoutDuplicateRows() {
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1", displayName: "Lyall St")
        let client = opSnap(entityType: "client", entityId: "c1", status: "pending")
        let completion = opSnap(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: "v1",
            operationType: SiteVisitSyncOperation.completionOperationType,
            status: "parked",
            siteVisitId: "v1"
        )

        let inventory = build(ops: [client, completion], drafts: [draft])

        let bundle = try! XCTUnwrap(bundles(inventory.attention).first)
        XCTAssertEqual(inventory.attention.count, 1)
        XCTAssertTrue(inventory.sending.isEmpty)
        XCTAssertEqual(bundle.id, "bundle:\(draft.id)")
        XCTAssertEqual(bundle.title, "Lyall St")
        XCTAssertEqual(bundle.blockedStage, .completion)
        XCTAssertEqual(Set(bundle.syncOperationIds), Set([client.id, completion.id]))
    }

    func testSyncOpSnapshotDecodesSiteVisitRoutingFromDurablePayload() throws {
        let payload = SiteVisitSyncOperation.Payload(
            companyId: "COMPANY",
            siteVisitId: "VISIT-1",
            entityId: "ARTIFACT-1"
        )
        let operation = SyncOperation(
            entityType: SyncEntityType.siteVisitArtifact.rawValue,
            entityId: "artifact-1",
            operationType: "create",
            payload: try JSONEncoder().encode(payload),
            changedFields: []
        )

        XCTAssertEqual(SyncOpSnapshot(from: operation).siteVisitId, "visit-1")
    }

    func testBundleToneAttentionBeatsWaiting() {
        // failed client op (attention) + pending deck op (waiting) → attention.
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1")
        let inventory = build(
            ops: [
                opSnap(entityType: "client", entityId: "c1", status: "failed"),
                opSnap(entityType: "deckDesign", entityId: "d1", status: "pending")
            ],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        )
        XCTAssertEqual(bundles(inventory.attention).first?.tone, .attention)
    }

    // MARK: - Role key correctness + case-insensitivity

    func testBundleJoinKeysAreCaseInsensitive() {
        // Draft client id mixed-case; op / autocreate / deck keys differ in case.
        let draft = draftSnap(siteVisitId: "v1", clientId: "AbC")
        let inventory = build(
            ops: [
                opSnap(entityType: "client", entityId: "abc", status: "pending"),
                opSnap(entityType: "deckDesign", entityId: "D1", status: "pending")
            ],
            autocreates: [autocreateSnap(clientId: "ABC")],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        )
        let bundle = bundles(inventory.sending).first
        XCTAssertEqual(bundle?.members.map(\.role), [.client, .lead, .deck])
        XCTAssertTrue(looseOps(inventory.sending).isEmpty, "case-folded ops must be consumed, not loose")
    }

    func testClientOpWithDifferentClientIdStaysLoose() {
        // Draft references c1; the client op is for c2 → not a member.
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1")
        let inventory = build(
            ops: [
                opSnap(entityType: "client", entityId: "c1", status: "pending"),   // joins
                opSnap(entityType: "client", entityId: "c2", status: "pending")    // loose
            ],
            drafts: [draft]
        )
        XCTAssertEqual(bundles(inventory.sending).first?.members.count, 1)
        let loose = looseOps(inventory.sending)
        XCTAssertEqual(loose.count, 1)
        XCTAssertEqual(loose.first?.0.entityId, "c2")
    }

    func testDeckOpJoinsOnlyThroughVisitArtifactLink() {
        // d1 is tied to the visit by an artifact; d2 is not.
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1")
        let inventory = build(
            ops: [
                opSnap(entityType: "deckDesign", entityId: "d1", status: "pending"),
                opSnap(entityType: "deckDesign", entityId: "d2", status: "pending")
            ],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        )
        let bundle = bundles(inventory.sending).first
        XCTAssertEqual(bundle?.members.map(\.role), [.deck])
        let loose = looseOps(inventory.sending)
        XCTAssertEqual(loose.map { $0.0.entityId }, ["d2"])
    }

    func testArtifactFromOtherVisitDoesNotLinkDeck() {
        // Artifact ties d1 to visit v2, but the draft is v1 → deck op stays loose,
        // and (no members) the draft drops to the drafts section.
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1", opportunityId: nil, lastCommittedAt: nil)
        let inventory = build(
            ops: [opSnap(entityType: "deckDesign", entityId: "d1", status: "pending")],
            drafts: [draft],
            artifacts: [artifactSnap(siteVisitId: "v2", deckDesignId: "d1")]
        )
        XCTAssertTrue(bundles(inventory.sending).isEmpty)
        XCTAssertEqual(looseOps(inventory.sending).map { $0.0.entityId }, ["d1"])
        XCTAssertEqual(draftItems(inventory.drafts).count, 1)
    }

    // MARK: - Photo bundle linkage (the documented finding)

    func testPhotosJoinBundleOnlyWhenDraftBoundToOpportunity() {
        // Bound draft: photo whose entityId == opportunityId is absorbed.
        let draft = draftSnap(clientId: "c1", opportunityId: "opp1")
        let inventory = build(
            ops: [opSnap(entityType: "client", entityId: "c1", status: "pending")],
            photos: [photoSnap(entityId: "opp1", status: "local")],
            drafts: [draft]
        )
        let bundle = bundles(inventory.sending).first
        XCTAssertEqual(bundle?.members.contains { $0.role == .photos }, true)
        XCTAssertTrue(loosePhotos(inventory.sending).isEmpty, "opportunity-linked photo must be consumed")
    }

    func testPhotosDoNotJoinUnboundDraftAndStayLoose() {
        // Unbound draft (no opportunityId): the photo cannot join — it renders loose.
        let draft = draftSnap(clientId: "c1", opportunityId: nil)
        let inventory = build(
            ops: [opSnap(entityType: "client", entityId: "c1", status: "pending")],
            photos: [photoSnap(entityId: "opp1", status: "local")],
            drafts: [draft]
        )
        let bundle = bundles(inventory.sending).first
        XCTAssertEqual(bundle?.members.contains { $0.role == .photos }, false)
        XCTAssertEqual(loosePhotos(inventory.sending).count, 1)
    }

    // MARK: - Draft section vs omission

    func testUnboundUncommittedDraftWithNoMembersGoesToDrafts() {
        let draft = draftSnap(clientId: nil, opportunityId: nil, lastCommittedAt: nil)
        let inventory = build(drafts: [draft])
        XCTAssertEqual(draftItems(inventory.drafts).map(\.id), [draft.id])
        XCTAssertTrue(inventory.attention.isEmpty)
        XCTAssertTrue(inventory.sending.isEmpty)
    }

    func testBoundDraftWithNoMembersIsOmitted() {
        let draft = draftSnap(clientId: "c1", opportunityId: "opp1", lastCommittedAt: base)
        let inventory = build(drafts: [draft])
        XCTAssertTrue(inventory.isEmpty, "a healthy bound+committed draft surfaces nowhere")
    }

    func testCommittedButUnboundDraftWithNoMembersIsOmitted() {
        // lastCommittedAt set but opportunityId nil → not an abandoned capture; omit.
        let draft = draftSnap(clientId: "c1", opportunityId: nil, lastCommittedAt: base)
        let inventory = build(drafts: [draft])
        XCTAssertTrue(inventory.drafts.isEmpty)
        XCTAssertTrue(inventory.isEmpty)
    }

    func testBoundDraftUncommittedWithNoMembersIsOmitted() {
        // opportunityId set but never committed → still not a drafts-section item.
        let draft = draftSnap(clientId: "c1", opportunityId: "opp1", lastCommittedAt: nil)
        let inventory = build(drafts: [draft])
        XCTAssertTrue(inventory.drafts.isEmpty)
        XCTAssertTrue(inventory.isEmpty)
    }

    // MARK: - Loose op placement by tone

    func testLooseParkedOpGoesToAttention() {
        let inventory = build(ops: [opSnap(entityId: "x", status: "parked", lastError: "23514 check")])
        let loose = looseOps(inventory.attention)
        XCTAssertEqual(loose.count, 1)
        XCTAssertEqual(loose.first?.1, .parked)
        XCTAssertTrue(inventory.sending.isEmpty)
    }

    func testLooseFailedOpGoesToAttention() {
        let inventory = build(ops: [opSnap(entityId: "x", status: "failed")])
        XCTAssertEqual(looseOps(inventory.attention).first?.1, .attention)
    }

    func testLoosePendingAndInProgressOpsGoToSending() {
        let inventory = build(ops: [
            opSnap(entityId: "p", status: "pending"),
            opSnap(entityId: "i", status: "inProgress")
        ])
        XCTAssertEqual(looseOps(inventory.sending).count, 2)
        XCTAssertTrue(inventory.attention.isEmpty)
        XCTAssertTrue(looseOps(inventory.sending).allSatisfy { $0.1 == .waiting })
    }

    func testCompletedOpIsIgnoredEntirely() {
        let inventory = build(ops: [opSnap(entityId: "done", status: "completed")])
        XCTAssertTrue(inventory.isEmpty)
    }

    // MARK: - Loose autocreate placement

    func testLooseAutocreatePlacementByState() {
        let inventory = build(autocreates: [
            autocreateSnap(clientId: "waiting", attempts: 0),                         // waiting → sending
            autocreateSnap(clientId: "retrying", attempts: 2, lastAttemptAt: base),   // attention → attention
            autocreateSnap(clientId: "parked", isParked: true)                        // parked → attention
        ])
        let sendingTones = looseAutocreates(inventory.sending).map { ($0.0.clientId, $0.1) }
        XCTAssertEqual(sendingTones.map { $0.0 }, ["waiting"])
        XCTAssertEqual(sendingTones.first?.1, .waiting)

        let attentionIds = Set(looseAutocreates(inventory.attention).map { $0.0.clientId })
        XCTAssertEqual(attentionIds, ["retrying", "parked"])
    }

    // MARK: - Photo grouping

    func testLoosePhotosGroupedByEntityIdWithToneByFailure() {
        let inventory = build(photos: [
            photoSnap(id: "a", entityId: "e1", status: "local"),
            photoSnap(id: "b", entityId: "e1", status: "failed"),
            photoSnap(id: "c", entityId: "e2", status: "local")
        ])
        // e1 has a failed member → attention; e2 all local → sending.
        let attentionGroups = loosePhotos(inventory.attention)
        XCTAssertEqual(attentionGroups.count, 1)
        XCTAssertEqual(Set(attentionGroups[0].0.map(\.id)), ["a", "b"])
        XCTAssertEqual(attentionGroups[0].1, .attention)

        let sendingGroups = loosePhotos(inventory.sending)
        XCTAssertEqual(sendingGroups.count, 1)
        XCTAssertEqual(sendingGroups[0].0.map(\.id), ["c"])
        XCTAssertEqual(sendingGroups[0].1, .waiting)

        // Stable id for a photos row is "photos:<entityId>".
        XCTAssertEqual(inventory.attention.first { if case .photos = $0 { return true } else { return false } }?.id, "photos:e1")
    }

    // MARK: - Orphan ordering

    func testOrphansSortNewestFirstInUnlinked() {
        let old = orphanSnap(id: "old", createdAt: base)
        let mid = orphanSnap(id: "mid", createdAt: base.addingTimeInterval(100))
        let new = orphanSnap(id: "new", createdAt: base.addingTimeInterval(200))
        let inventory = build(orphans: [old, new, mid])
        XCTAssertEqual(orphanItems(inventory.unlinked).map(\.id), ["new", "mid", "old"])
        // Orphans never count as active work.
        XCTAssertEqual(inventory.totalActive, 0)
    }

    // MARK: - Section ordering (oldest-first)

    func testLooseSectionsSortOldestFirst() {
        let inventory = build(ops: [
            opSnap(entityId: "late", status: "pending", createdAt: base.addingTimeInterval(30)),
            opSnap(entityId: "early", status: "pending", createdAt: base.addingTimeInterval(10)),
            opSnap(entityId: "mid", status: "pending", createdAt: base.addingTimeInterval(20))
        ])
        XCTAssertEqual(looseOps(inventory.sending).map { $0.0.entityId }, ["early", "mid", "late"])
    }

    // MARK: - Counts & empty

    func testCountsExcludeDraftsAndOrphansFromTotalActive() {
        let draft = draftSnap(clientId: nil, opportunityId: nil, lastCommittedAt: nil)
        let inventory = build(
            ops: [
                opSnap(entityId: "parked", status: "parked"),   // attention
                opSnap(entityId: "pending", status: "pending")  // sending
            ],
            drafts: [draft],
            orphans: [orphanSnap(id: "o1"), orphanSnap(id: "o2")]
        )
        XCTAssertEqual(inventory.attentionCount, 1)
        XCTAssertEqual(inventory.totalActive, 2)          // attention + sending only
        XCTAssertEqual(inventory.drafts.count, 1)
        XCTAssertEqual(inventory.unlinked.count, 2)
        XCTAssertFalse(inventory.isEmpty)
    }

    func testIsEmptyWhenNothingPending() {
        XCTAssertTrue(build().isEmpty)
    }

    // MARK: - nextEligibleAt — SyncOperation backoff (min(2^retryCount, 60))

    func testOpNextEligibleAtFutureWindow() {
        // retryCount 6 → window min(64,60)=60s; lastAttempted = now-10 → eligible now+50.
        let lastAttempted = now.addingTimeInterval(-10)
        let inventory = build(ops: [
            opSnap(entityId: "p", status: "pending", retryCount: 6, lastAttemptedAt: lastAttempted)
        ])
        guard let op = looseOps(inventory.sending).first else { return XCTFail("expected a loose op") }
        XCTAssertEqual(op.2, lastAttempted.addingTimeInterval(60))
    }

    func testOpNextEligibleAtNilWhenWindowElapsed() {
        // retryCount 2 → window min(4,60)=4s; lastAttempted = now-10 → eligible now-6 (past) → nil.
        let inventory = build(ops: [
            opSnap(entityId: "p", status: "pending", retryCount: 2, lastAttemptedAt: now.addingTimeInterval(-10))
        ])
        guard let op = looseOps(inventory.sending).first else { return XCTFail("expected a loose op") }
        XCTAssertNil(op.2)
    }

    func testFailedAndParkedOpsHaveNilNextEligibleAt() {
        let inventory = build(ops: [
            opSnap(entityId: "f", status: "failed", retryCount: 3, lastAttemptedAt: now.addingTimeInterval(-1)),
            opSnap(entityId: "k", status: "parked", retryCount: 3, lastAttemptedAt: now.addingTimeInterval(-1))
        ])
        for (_, _, next) in looseOps(inventory.attention) {
            XCTAssertNil(next, "failed/parked ops never schedule a timed retry")
        }
    }

    func testOpNextEligibleAtNilWhenNeverAttempted() {
        let inventory = build(ops: [opSnap(entityId: "p", status: "pending", retryCount: 0, lastAttemptedAt: nil)])
        guard let op = looseOps(inventory.sending).first else { return XCTFail("expected a loose op") }
        XCTAssertNil(op.2)
    }

    // MARK: - nextEligibleAt — autocreate backoff (ClientLeadAutocreateQueue)

    func testAutocreateNextEligibleAtFutureWindow() {
        // attempts 1 → window min(60*2^1, 900)=120s; lastAttempt = now-10 → eligible now+110.
        let lastAttempt = now.addingTimeInterval(-10)
        let inventory = build(autocreates: [
            autocreateSnap(clientId: "c", attempts: 1, lastAttemptAt: lastAttempt)
        ])
        // attempts>0 → attention section.
        guard let auto = looseAutocreates(inventory.attention).first else { return XCTFail("expected a loose autocreate") }
        XCTAssertEqual(auto.2, lastAttempt.addingTimeInterval(120))
        // Matches the live source-of-truth formula exactly.
        XCTAssertEqual(auto.2, lastAttempt.addingTimeInterval(ClientLeadAutocreateQueue.backoffInterval(attempts: 1)))
    }

    func testAutocreateNextEligibleAtNilWhenElapsedOrParkedOrUntried() {
        let inventory = build(autocreates: [
            autocreateSnap(clientId: "elapsed", attempts: 1, lastAttemptAt: now.addingTimeInterval(-1000)),
            autocreateSnap(clientId: "parked", lastAttemptAt: now.addingTimeInterval(-5), isParked: true),
            autocreateSnap(clientId: "untried", attempts: 0, lastAttemptAt: nil)
        ])
        let all = looseAutocreates(inventory.attention) + looseAutocreates(inventory.sending)
        for (_, _, next) in all {
            XCTAssertNil(next)
        }
    }

    // MARK: - Determinism / order independence

    func testOutputIsOrderIndependentForFixedNow() {
        let draft = draftSnap(siteVisitId: "v1", clientId: "c1", opportunityId: "opp1")
        let ops = [
            opSnap(entityType: "client", entityId: "c1", status: "failed", createdAt: base.addingTimeInterval(5)),
            opSnap(entityType: "deckDesign", entityId: "d1", status: "pending", createdAt: base.addingTimeInterval(6)),
            opSnap(entityId: "loose1", status: "parked", createdAt: base.addingTimeInterval(1)),
            opSnap(entityId: "loose2", status: "pending", createdAt: base.addingTimeInterval(2))
        ]
        let autos = [
            autocreateSnap(clientId: "c1"),
            autocreateSnap(clientId: "solo", attempts: 3, lastAttemptAt: base)
        ]
        let photos = [
            photoSnap(id: "p1", entityId: "opp1", status: "failed"),
            photoSnap(id: "p2", entityId: "loose-ent", status: "local")
        ]
        let artifacts = [artifactSnap(siteVisitId: "v1", deckDesignId: "d1")]
        let orphans = [orphanSnap(id: "o1", createdAt: base), orphanSnap(id: "o2", createdAt: base.addingTimeInterval(50))]

        let forward = RecoveryInventory.build(
            ops: ops, autocreates: autos, photos: photos, drafts: [draft],
            artifacts: artifacts, orphans: orphans, now: now
        )
        let reversed = RecoveryInventory.build(
            ops: ops.reversed(), autocreates: autos.reversed(), photos: photos.reversed(),
            drafts: [draft], artifacts: artifacts.reversed(), orphans: orphans.reversed(), now: now
        )
        XCTAssertEqual(forward, reversed, "a fixed `now` must yield identical output regardless of input order")
    }

    func testRepeatedBuildIsIdentical() {
        let ops = [opSnap(entityId: "a", status: "parked"), opSnap(entityId: "b", status: "pending")]
        XCTAssertEqual(build(ops: ops), build(ops: ops))
    }
}
