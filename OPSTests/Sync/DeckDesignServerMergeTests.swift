//
//  DeckDesignServerMergeTests.swift
//  OPSTests
//
//  The inbound merge behind BOTH deck self-repair fetches (bug 2fa645a8).
//
//  The repair path is reached by the exact gesture the crash report names —
//  DECK tapped on a lead whose deck exists remotely but not locally — and the
//  version it replaced looked up pending work with a `#Predicate` fetch of
//  `SyncOperation`. That fetch TRAPS (uncatchable EXC_BREAKPOINT inside
//  SwiftData, not a thrown error) against a store whose operation table has
//  never held a row: a fresh install, an erased device, a store that has never
//  queued an outbound write. `try?` does not catch it.
//
//  Test 1 is therefore deliberately hostile: its container seeds NO warm-up
//  `SyncOperation`. Against the pre-fix lookup it kills the test process — that
//  IS the regression signal, and it is why nothing here "expects" a thrown
//  error. The remaining two pin the behaviour the dossier's DECK row gained by
//  sharing this merge: a pending local edit survives the repair, and two
//  spellings of one UUID stay one row.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DeckDesignServerMergeTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase and
    // `UUID().uuidString` is uppercase. Only the case-variant test mixes them.
    private let designId = "c0509774-2748-479f-92e7-ee7d5dcff14e"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let opportunityId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    // MARK: - 1. The trap

    /// A first-run store has a `SyncOperation` table that has never held a row.
    /// The merge must complete against it — no seeded warm-up operation, because
    /// seeding one is exactly what would hide the trap.
    func testMergeSurvivesAStoreThatNeverHeldASyncOperation() throws {
        let context = try makeContext()

        try DeckDesignServerMerge.merge(
            [dto(id: designId, title: "Repaired deck", drawing: square())],
            into: context
        )

        let stored = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(stored.count, 1, "the repair fetch must insert the server's design")
        XCTAssertEqual(stored.first?.id, designId)
        XCTAssertEqual(stored.first?.title, "Repaired deck")
        XCTAssertEqual(stored.first?.needsSync, false)
    }

    // MARK: - 2. Pending-field protection

    /// The dossier's repair used to merge without pending-field protection, so a
    /// deck edit still queued for push could be clobbered by the repair fetch.
    /// A field with a pending outbound write is never accepted from the server,
    /// and the row stays dirty so the push still happens.
    func testMergeProtectsPendingLocalFields() throws {
        let context = try makeContext()
        let localUpdatedAt = Date(timeIntervalSince1970: 1_780_000_000)

        var localDrawing = square()
        localDrawing.scaleFactor = 1
        let design = DeckDesign(
            id: designId,
            companyId: companyId,
            opportunityId: opportunityId,
            title: "Local title",
            drawingDataJSON: localDrawing.toJSON()
        )
        design.updatedAt = localUpdatedAt
        design.needsSync = true
        // The drawing itself is already confirmed by the server, so the
        // content-based conflict rule has nothing to protect — which is the
        // point: the ONLY thing that can save the geometry below is the
        // pending-field subtraction under test.
        design.syncedDrawingJSON = design.drawingDataJSON
        context.insert(design)

        let pending = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: designId,
            operationType: "update",
            payload: Data("{}".utf8),
            changedFields: ["drawing_data"]
        )
        context.insert(pending)
        try context.save()

        // Strictly NEWER server row, so the stale-overwrite guard inside
        // `applyServerSnapshot` cannot be what saves the geometry — the only
        // thing protecting it is the pending-field subtraction under test.
        try DeckDesignServerMerge.merge(
            [
                dto(
                    id: designId,
                    title: "Server title",
                    drawing: DeckDrawingData(),
                    updatedAt: localUpdatedAt.addingTimeInterval(600)
                )
            ],
            into: context
        )

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<DeckDesign>()).first)
        XCTAssertEqual(
            stored.drawingData.vertices.count, 4,
            "a pending drawing_data write was overwritten by the repair fetch"
        )
        XCTAssertTrue(
            stored.needsSync,
            "the row must stay dirty while an outbound write is still pending"
        )
        XCTAssertEqual(
            stored.title, "Server title",
            "only the PENDING field is protected — the merge must still land the rest"
        )
    }

    // MARK: - 3. Case-variant identity

    /// `UUID().uuidString` is uppercase; Postgres hands back lowercase. A row
    /// cached under one spelling must be found by the other, or the repair
    /// fetch inserts a second copy of the same deck.
    func testCaseVariantIdDoesNotDuplicate() throws {
        let context = try makeContext()

        let design = DeckDesign(
            id: designId,
            companyId: companyId,
            opportunityId: opportunityId,
            title: "Local title"
        )
        // The initializer canonicalizes to lowercase, so the uppercase spelling
        // has to be written back deliberately — it is the shape a legacy row
        // cached before canonicalization actually has.
        design.id = designId.uppercased()
        context.insert(design)
        try context.save()

        try DeckDesignServerMerge.merge(
            [dto(id: designId, title: "Server title", drawing: square())],
            into: context
        )

        let stored = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(
            stored.count, 1,
            "a case-variant id spelling duplicated the deck instead of matching it"
        )
        XCTAssertEqual(stored.first?.title, "Server title")
    }

    // MARK: - Fixtures

    /// Closed square (4 verts + 4 edges) so the geometry survives the JSON
    /// round-trip — orphan (edgeless) vertices are pruned on decode.
    private func square() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        ]
        drawing.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        drawing.scaleFactor = 1
        return drawing
    }

    private func dto(
        id: String,
        title: String,
        drawing: DeckDrawingData,
        updatedAt: Date? = nil
    ) -> SupabaseDeckDesignDTO {
        SupabaseDeckDesignDTO(
            id: id,
            companyId: companyId,
            projectId: nil,
            opportunityId: opportunityId,
            title: title,
            drawingData: drawing,
            thumbnailUrl: nil,
            version: 2,
            createdBy: nil,
            createdAt: "2026-06-19T19:00:00Z",
            updatedAt: updatedAt.map { ISO8601DateFormatter().string(from: $0) },
            deletedAt: nil
        )
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
        let schema = Schema([DeckDesign.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container.mainContext
    }
}
