//
//  DeckDesignLinkSyncTests.swift
//  OPSTests
//
//  SYNC RECOVERY · T4 — deck→lead link durability (RC3).
//
//  Before this work every deck create/update stripped opportunity_id, so a deck
//  drawn on a lead reached the server as an orphan (opportunity_id NULL) that the
//  reparent guard trigger then blocked from ever being PATCHed. The fix:
//    - creates carry opportunity_id inline (a legal linked INSERT),
//    - updates NEVER carry opportunity_id (the guard rejects a PATCH → 42501),
//    - a NULL→lead link travels via a dedicated, server-guarded "linkOpportunity"
//      op that calls link_deck_design_to_opportunity_guarded,
//    - the coalescer is link-aware so a link is merged INTO a create but never
//      into an all-updates survivor (which would lose the link or the edit),
//    - a one-time backfill sweep heals designs already orphaned server-side.
//
//  These tests drive the REAL coalescer (OutboundProcessor.coalesceOperations),
//  the REAL recorder (DeckBuilderViewModel.enqueueDeckDesignSync via save()), the
//  REAL routing (OutboundProcessor.executeOperation), and the REAL backfill sweep
//  (SyncEngine.enqueueDeckDesignLinkBackfillOnce). DataActor mirrors the coalescer
//  + handler verbatim (its copies are private and unreachable from tests); the
//  shared logic is proven here and enforced identical by review.
//

import SwiftData
import Supabase
import XCTest
@testable import OPS

@MainActor
final class DeckDesignLinkSyncTests: XCTestCase {

    private let backfillFlagKey = "deckDesignLinkBackfill.v1"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let oppId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    override func setUp() {
        super.setUp()
        // Gate the backfill OFF for every non-backfill test so a stray push cycle
        // can't enqueue heal ops that pollute op counts. Backfill tests clear it.
        UserDefaults.standard.set(true, forKey: backfillFlagKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: backfillFlagKey)
        super.tearDown()
    }

    // MARK: - Recorder (create keeps opportunity_id, update strips + emits link op)

    /// A deck born on a lead (never synced) ships opportunity_id INLINE on its
    /// create — a legal linked INSERT (the reparent guard fires on UPDATE only).
    func test_recorder_createCarriesOpportunityIdInline() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let design = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: companyId,
            opportunityId: oppId,           // drawn on a lead
            title: "Lead deck",
            drawingDataJSON: DeckDrawingData().toJSON()   // empty → not auto-enqueued at init
        )
        // lastSyncedAt nil → hasEnqueuedCreate false → save() emits a CREATE.
        context.insert(design)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())
        let vm = DeckBuilderViewModel(deckDesign: design, modelContext: context, syncEngine: syncEngine)
        vm.save()

        let ops = try deckOps(context)
        XCTAssertEqual(ops.count, 1, "a fresh linked deck emits exactly one op — the create")
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.operationType, "create")
        let payload = try decoded(op.payload)
        XCTAssertEqual(
            payload["opportunity_id"] as? String, oppId,
            "the create must carry opportunity_id inline so the linked INSERT lands the lead link"
        )
    }

    /// An already-synced linked deck: the update op must NOT carry opportunity_id
    /// (a PATCH of it is rejected by the guard trigger, 42501), and the link must
    /// instead travel as a SEPARATE guarded linkOpportunity op.
    func test_recorder_updateStripsOpportunityId_andEmitsLinkOp() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let design = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: companyId,
            opportunityId: oppId,
            title: "Lead deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        design.lastSyncedAt = Date()        // already synced → save() emits an UPDATE
        context.insert(design)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())
        let vm = DeckBuilderViewModel(deckDesign: design, modelContext: context, syncEngine: syncEngine)
        vm.save()

        let ops = try deckOps(context)
        XCTAssertEqual(ops.count, 2, "a link-bearing update emits the update PLUS a separate linkOpportunity op")

        let update = try XCTUnwrap(ops.first { $0.operationType == "update" })
        let updatePayload = try decoded(update.payload)
        XCTAssertNil(
            updatePayload["opportunity_id"],
            "the update payload must NOT carry opportunity_id — a PATCH of it is rejected by the reparent guard (42501)"
        )
        XCTAssertNotNil(updatePayload["updated_at"], "the update still carries its normal fields")

        let link = try XCTUnwrap(ops.first { $0.operationType == "linkOpportunity" })
        let linkPayload = try decoded(link.payload)
        XCTAssertEqual(
            linkPayload["opportunity_id"] as? String, oppId,
            "the lead link travels via the dedicated linkOpportunity op"
        )
    }

    // MARK: - Coalescing (the critical correctness cases)

    /// create + link → ONE create carrying opportunity_id. The link merges INTO
    /// the create payload (a linked INSERT is legal), and is marked completed.
    func test_coalesce_createAbsorbsLink_intoOneCreateCarryingOpportunityId() {
        let processor = OutboundProcessor()
        let designId = "11111111-1111-4111-8111-111111111111"

        let create = makeOp(
            operationType: "create",
            designId: designId,
            payload: ["id": designId, "company_id": companyId, "title": "Deck"],
            changedFields: ["id", "company_id", "title"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let link = makeOp(
            operationType: "linkOpportunity",
            designId: designId,
            payload: ["opportunity_id": oppId],
            changedFields: ["opportunity_id"],
            createdAt: Date(timeIntervalSince1970: 2)
        )

        let coalesced = processor.coalesceOperations([create, link])

        XCTAssertEqual(coalesced.count, 1, "create absorbs the link — one op survives")
        let survivor = coalesced[0]
        XCTAssertEqual(survivor.operationType, "create")
        let payload = (try? decoded(survivor.payload)) ?? [:]
        XCTAssertEqual(
            payload["opportunity_id"] as? String, oppId,
            "the link's opportunity_id merges INTO the create payload for the linked INSERT"
        )
        XCTAssertTrue(link.isCompleted, "the absorbed link op is marked completed")
    }

    /// create + update + link → still ONE create, carrying BOTH the edit fields
    /// and opportunity_id.
    func test_coalesce_createUpdateLink_intoOneCreateWithAllFields() {
        let processor = OutboundProcessor()
        let designId = "22222222-2222-4222-8222-222222222222"

        let create = makeOp(
            operationType: "create",
            designId: designId,
            payload: ["id": designId, "company_id": companyId, "title": "Deck"],
            changedFields: ["id", "company_id", "title"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let update = makeOp(
            operationType: "update",
            designId: designId,
            payload: ["title": "Renamed", "version": 3],
            changedFields: ["title", "version"],
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let link = makeOp(
            operationType: "linkOpportunity",
            designId: designId,
            payload: ["opportunity_id": oppId],
            changedFields: ["opportunity_id"],
            createdAt: Date(timeIntervalSince1970: 3)
        )

        let coalesced = processor.coalesceOperations([create, update, link])

        XCTAssertEqual(coalesced.count, 1)
        let survivor = coalesced[0]
        XCTAssertEqual(survivor.operationType, "create")
        let payload = (try? decoded(survivor.payload)) ?? [:]
        XCTAssertEqual(payload["opportunity_id"] as? String, oppId)
        XCTAssertEqual(payload["title"] as? String, "Renamed", "later edit fields also merge into the create")
        XCTAssertEqual(payload["version"] as? Int, 3)
        XCTAssertTrue(update.isCompleted)
        XCTAssertTrue(link.isCompleted)
    }

    /// update + link with NO create → BOTH survive as separate ops. Merging them
    /// would either strip the link (lost link) or drop the edit (lost edit).
    func test_coalesce_updatePlusLink_noCreate_bothSurviveSeparately() {
        let processor = OutboundProcessor()
        let designId = "33333333-3333-4333-8333-333333333333"

        let update = makeOp(
            operationType: "update",
            designId: designId,
            payload: ["title": "Renamed", "drawing_data": ["scaleFactor": 1], "updated_at": "2026-07-22T00:00:00Z"],
            changedFields: ["title", "drawing_data", "updated_at"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let link = makeOp(
            operationType: "linkOpportunity",
            designId: designId,
            payload: ["opportunity_id": oppId],
            changedFields: ["opportunity_id"],
            createdAt: Date(timeIntervalSince1970: 2)
        )

        let coalesced = processor.coalesceOperations([update, link])

        XCTAssertEqual(coalesced.count, 2, "with no create, the link never merges into the update — both survive")

        guard let survivingUpdate = coalesced.first(where: { $0.operationType == "update" }),
              let survivingLink = coalesced.first(where: { $0.operationType == "linkOpportunity" }) else {
            return XCTFail("both an update and a linkOpportunity op must survive")
        }

        let updatePayload = (try? decoded(survivingUpdate.payload)) ?? [:]
        XCTAssertNil(
            updatePayload["opportunity_id"],
            "the surviving update must not have absorbed the link's opportunity_id (the update path would strip it → lost link)"
        )
        XCTAssertEqual(updatePayload["title"] as? String, "Renamed", "the edit fields survive intact")

        let linkPayload = (try? decoded(survivingLink.payload)) ?? [:]
        XCTAssertEqual(linkPayload["opportunity_id"] as? String, oppId)

        XCTAssertFalse(update.isCompleted, "neither op is superseded")
        XCTAssertFalse(link.isCompleted)
    }

    /// A lone link op passes through untouched.
    func test_coalesce_lonelinkSurvives() {
        let processor = OutboundProcessor()
        let designId = "44444444-4444-4444-8444-444444444444"

        let link = makeOp(
            operationType: "linkOpportunity",
            designId: designId,
            payload: ["opportunity_id": oppId],
            changedFields: ["opportunity_id"],
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let coalesced = processor.coalesceOperations([link])

        XCTAssertEqual(coalesced.count, 1)
        XCTAssertEqual(coalesced[0].operationType, "linkOpportunity")
        let payload = (try? decoded(coalesced[0].payload)) ?? [:]
        XCTAssertEqual(payload["opportunity_id"] as? String, oppId)
    }

    /// delete wins over a link on the same design — a design being deleted needs
    /// no lead link. The link is superseded (completed), only the delete survives.
    func test_coalesce_deleteWinsOverLink() {
        let processor = OutboundProcessor()
        let designId = "55555555-5555-4555-8555-555555555555"

        let link = makeOp(
            operationType: "linkOpportunity",
            designId: designId,
            payload: ["opportunity_id": oppId],
            changedFields: ["opportunity_id"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let delete = makeOp(
            operationType: "delete",
            designId: designId,
            payload: [:],
            changedFields: [],
            createdAt: Date(timeIntervalSince1970: 2)
        )

        let coalesced = processor.coalesceOperations([link, delete])

        XCTAssertEqual(coalesced.count, 1)
        XCTAssertEqual(coalesced[0].operationType, "delete")
        XCTAssertTrue(link.isCompleted, "the link is moot for a deleted design")
    }

    /// A second design in the same batch must not be affected by another design's
    /// link peel-off (grouping is per entity id).
    func test_coalesce_linkPeelOff_isScopedPerDesign() {
        let processor = OutboundProcessor()
        let designA = "66666666-6666-4666-8666-666666666666"
        let designB = "77777777-7777-4777-8777-777777777777"

        let updateA = makeOp(operationType: "update", designId: designA,
                             payload: ["title": "A"], changedFields: ["title"],
                             createdAt: Date(timeIntervalSince1970: 1))
        let linkA = makeOp(operationType: "linkOpportunity", designId: designA,
                           payload: ["opportunity_id": oppId], changedFields: ["opportunity_id"],
                           createdAt: Date(timeIntervalSince1970: 2))
        let createB = makeOp(operationType: "create", designId: designB,
                            payload: ["id": designB, "company_id": companyId, "title": "B"],
                            changedFields: ["id", "company_id", "title"],
                            createdAt: Date(timeIntervalSince1970: 3))

        let coalesced = processor.coalesceOperations([updateA, linkA, createB])

        // designA → update + link (2), designB → create (1) = 3 survivors.
        XCTAssertEqual(coalesced.count, 3)
        XCTAssertEqual(coalesced.filter { $0.entityId == designA }.count, 2)
        XCTAssertEqual(coalesced.filter { $0.entityId == designB && $0.operationType == "create" }.count, 1)
    }

    // MARK: - Handler routing (malformed link payload → park)

    /// A linkOpportunity op with no opportunity_id can't be fixed by retry, so the
    /// handler throws encodingFailed → the classifier parks it (permanent). This
    /// also proves routing reaches handleDeckDesign's linkOpportunity case (the
    /// guard fires there, before any network call).
    func test_linkOpportunityHandler_parksOnMalformedPayload() async throws {
        let processor = OutboundProcessor()
        let op = makeOp(
            operationType: "linkOpportunity",
            designId: "88888888-8888-4888-8888-888888888888",
            payload: [:],                       // missing opportunity_id
            changedFields: [],
            createdAt: Date()
        )

        // executeOperation claims ops from the persisted store (pending → inProgress
        // linearization) — the op must be inserted and saved or the claim refuses it.
        let context = try makeContext()
        context.insert(op)
        try context.save()

        do {
            try await processor.executeOperation(op, context: context)
            XCTFail("a malformed linkOpportunity op must throw, not silently succeed")
        } catch {
            XCTAssertTrue(
                op.isParked,
                "a malformed linkOpportunity payload parks (permanent) rather than burning the retry budget"
            )
        }
    }

    // MARK: - Backfill sweep (one-time server-orphan heal)

    /// The sweep records exactly one linkOpportunity op per locally-linked design,
    /// then flips its UserDefaults flag so a second call is a no-op.
    func test_backfill_enqueuesLinkOpOncePerLinkedDesign_thenGatesOnFlag() throws {
        UserDefaults.standard.removeObject(forKey: backfillFlagKey)   // arm the sweep

        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let linked = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: companyId,
            opportunityId: oppId,
            title: "Orphaned lead deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        context.insert(linked)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        syncEngine.enqueueDeckDesignLinkBackfillOnce()

        var links = try deckOps(context).filter { $0.operationType == "linkOpportunity" }
        XCTAssertEqual(links.count, 1, "one link op recorded for the locally-linked design")
        XCTAssertEqual(links.first?.entityId, linked.id)
        let payload = try decoded(try XCTUnwrap(links.first).payload)
        XCTAssertEqual(payload["opportunity_id"] as? String, oppId)
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: backfillFlagKey),
            "the one-time flag flips true after a clean pass"
        )

        // Second call is gated by the flag — no duplicate op.
        syncEngine.enqueueDeckDesignLinkBackfillOnce()
        links = try deckOps(context).filter { $0.operationType == "linkOpportunity" }
        XCTAssertEqual(links.count, 1, "the flag makes the sweep run at most once per device")
    }

    /// A design that already has an open (pending) linkOpportunity op is skipped —
    /// the sweep must not stack a duplicate on the recorder's (or a prior sweep's)
    /// in-flight link op.
    func test_backfill_skipsDesignWithOpenLinkOp() throws {
        UserDefaults.standard.removeObject(forKey: backfillFlagKey)

        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let linked = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: companyId,
            opportunityId: oppId,
            title: "Already-enqueued deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        context.insert(linked)

        // An existing pending link op for this design.
        let existing = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: linked.id,
            operationType: "linkOpportunity",
            payload: try JSONSerialization.data(withJSONObject: ["opportunity_id": oppId]),
            changedFields: ["opportunity_id"]
        )
        existing.status = "pending"
        context.insert(existing)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        syncEngine.enqueueDeckDesignLinkBackfillOnce()

        let links = try deckOps(context).filter { $0.operationType == "linkOpportunity" }
        XCTAssertEqual(links.count, 1, "the pre-existing open link op suppresses a duplicate backfill op")
    }

    /// Deleted designs and unlinked (opportunityId nil) designs are never backfilled.
    func test_backfill_skipsDeletedAndUnlinkedDesigns() throws {
        UserDefaults.standard.removeObject(forKey: backfillFlagKey)

        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let deletedLinked = DeckDesign(
            id: "11111111-1111-4111-8111-111111111111",
            companyId: companyId,
            opportunityId: oppId,
            title: "Deleted lead deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        deletedLinked.deletedAt = Date()

        let unlinked = DeckDesign(
            id: "22222222-2222-4222-8222-222222222222",
            companyId: companyId,
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Project-only deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )   // opportunityId nil

        context.insert(deletedLinked)
        context.insert(unlinked)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        syncEngine.enqueueDeckDesignLinkBackfillOnce()

        let links = try deckOps(context).filter { $0.operationType == "linkOpportunity" }
        XCTAssertTrue(links.isEmpty, "deleted and unlinked designs are never backfilled")
    }

    // MARK: - Helpers

    private func deckOps(_ context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
    }

    private func makeOp(
        operationType: String,
        designId: String,
        payload: [String: Any],
        changedFields: [String],
        createdAt: Date,
        priority: Int = 1
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: designId,
            operationType: operationType,
            payload: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8),
            changedFields: changedFields,
            priority: priority
        )
        op.createdAt = createdAt
        return op
    }

    private func decoded(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Expected the sync payload to decode as a JSON object."
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SyncOperation.self, configurations: configuration)
        return ModelContext(container)
    }

    private func makeSyncOperationContainer() throws -> ModelContainer {
        // PhotoAnnotation is included because SyncEngine.refreshPendingCount counts
        // pending dimensioned annotations alongside SyncOperation rows.
        let schema = Schema([DeckDesign.self, SyncOperation.self, PhotoAnnotation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
