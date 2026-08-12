//
//  ProjectDetailsLocalFirstTests.swift
//  OPSTests
//
//  Opening a project's details used to run a WHOLE-APP sync: `refreshSingleClient`
//  was literally `syncEngine.triggerSync()` — push + pull over all 40
//  SyncEntityTypes, orphan sweeps, photo prefetch — on every open of every
//  project, plus a network-first note load that held the activity feed behind a
//  round-trip. The screen is now local-first: one client row is fetched, the
//  notes paint from disk before the network is consulted.
//
//  Three contracts are pinned here.
//
//  1. `syncClientNow` is NOT a sync pass. `triggerSync()` writes `statusText` on
//     every path it can take — "Syncing…" when it runs, "Offline — changes
//     queued" when it can't — so an untouched `statusText` after a client
//     refresh is direct evidence that the freight train did not leave the
//     station. The merge half is exercised separately against a DTO, through
//     the same `mergeClient` the pull and realtime paths use.
//
//  2. The activity feed paints local rows BEFORE the fetch resolves. Asserted
//     against a fetch held open on a gate, so the ordering is observed rather
//     than raced.
//
//  3. `getAllProjects()` drops tombstones in the fetch predicate, matching the
//     in-memory filter its callers used to apply for themselves (the pattern
//     TaskReviewQueryParityTests established for `getAllTasks` / `getProjects`).
//

import SwiftData
import UIKit
import XCTest
@testable import OPS

final class ProjectDetailsLocalFirstTests: XCTestCase {

    // MARK: - 1a. A client refresh is not a sync pass

    /// `triggerSync()` announces itself to the operator on every path. A
    /// targeted client fetch must not: it is a one-row read behind a screen
    /// open, not a sync the operator asked for.
    @MainActor
    func test_syncClientNowNeverPresentsItselfAsASyncPass() async {
        let engine = SyncEngine()

        await engine.syncClientNow(clientId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

        XCTAssertEqual(
            engine.statusText,
            "",
            "A details-screen client refresh must leave the sync status untouched"
        )
        XCTAssertFalse(engine.isSyncing)
    }

    /// The discriminator for the assertion above: the call this replaced writes
    /// `statusText` even when it does nothing at all, so an untouched status is
    /// only meaningful because `triggerSync()` would have changed it.
    @MainActor
    func test_triggerSyncDoesAnnounceItself() async {
        let engine = SyncEngine()

        await engine.triggerSync()

        XCTAssertEqual(
            engine.statusText,
            "Offline — changes queued",
            "Precondition: triggerSync writes status on every path, which is what makes the test above a proof"
        )
    }

    /// An empty id must not reach the network at all — and must still not look
    /// like a sync.
    @MainActor
    func test_syncClientNowWithoutAnIdDoesNothing() async {
        let engine = SyncEngine()

        await engine.syncClientNow(clientId: "")

        XCTAssertEqual(engine.statusText, "")
        XCTAssertFalse(engine.isSyncing)
    }

    // MARK: - 1b. The merge half

    func test_mergeClientSnapshotInsertsAServerRowAndAnnouncesIt() async throws {
        let container = try makeContainer()
        let clientId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let merged = expectation(forNotification: .inboundDataMerged, object: nil) { note in
            let names = note.userInfo?[InboundChangeSignal.entityNamesKey] as? [String]
            return names == ["Client"]
        }

        try await actor.mergeClientSnapshot(clientDTO(id: clientId, name: "Norcut Fencing"))

        await fulfillment(of: [merged], timeout: 2)

        let check = ModelContext(container)
        let clients = try check.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        )
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients.first?.name, "Norcut Fencing")
        XCTAssertEqual(clients.first?.needsSync, false)
    }

    /// The targeted fetch routes through the shared `mergeClient`, so an
    /// existing local row is updated in place — not duplicated. Client.id
    /// carries no uniqueness attribute; a second insert would show up in the
    /// UI as two of the same customer.
    func test_mergeClientSnapshotUpdatesInPlaceRatherThanDuplicating() async throws {
        let container = try makeContainer()
        let clientId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

        let seed = ModelContext(container)
        let existing = Client(id: clientId, name: "Stale name", companyId: "company-1")
        existing.lastSyncedAt = Date(timeIntervalSinceNow: -3600)
        seed.insert(existing)
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()
        try await actor.mergeClientSnapshot(clientDTO(id: clientId, name: "Fresh name"))

        let check = ModelContext(container)
        let clients = try check.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        )
        XCTAssertEqual(clients.count, 1, "The server row must merge onto the local identity")
        XCTAssertEqual(clients.first?.name, "Fresh name")
    }

    // MARK: - 2. Local-first notes

    /// The activity feed is already on disk. Painting it only after a network
    /// round-trip is the screen feeling slow for no reason — and offline it
    /// meant a spinner until the request gave up.
    @MainActor
    func test_loadNotesPaintsLocalRowsBeforeTheFetchResolves() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectId = "11111111-1111-4111-8111-111111111111"

        let local = ProjectNote(
            id: "local-1",
            projectId: projectId,
            companyId: "company-1",
            authorId: "user-1",
            content: "Rebar delivered",
            createdAt: Date(timeIntervalSinceNow: -600)
        )
        local.lastSyncedAt = Date()
        context.insert(local)
        try context.save()

        let fetchStarted = expectation(description: "the server fetch was reached")
        let fetcher = GatedNoteFetcher(
            dtos: [try noteDTO(id: "server-1", projectId: projectId)],
            started: fetchStarted
        )

        let viewModel = ProjectNotesViewModel(projectId: projectId)
        viewModel.setup(
            companyId: "company-1",
            currentUserId: "user-1",
            teamMembers: [],
            modelContext: context,
            dataController: nil,
            noteFetcher: fetcher
        )
        XCTAssertTrue(viewModel.notes.isEmpty, "Precondition: nothing painted before the load")

        let load = Task { await viewModel.loadNotes() }
        await fulfillment(of: [fetchStarted], timeout: 2)

        XCTAssertEqual(
            viewModel.notes.map(\.id),
            ["local-1"],
            "Local rows must be on screen while the server fetch is still in flight"
        )
        XCTAssertFalse(
            viewModel.isLoading && viewModel.notes.isEmpty && viewModel.annotations.isEmpty,
            "ActivityTabView's spinner condition must already be false — the feed is painted"
        )

        await fetcher.open()
        await load.value

        XCTAssertEqual(
            Set(viewModel.notes.map(\.id)),
            ["local-1", "server-1"],
            "The server merge still lands on top of the local paint"
        )
        XCTAssertFalse(viewModel.isLoading)
    }

    /// Offline (and before setup), the feed still paints. The old order made the
    /// local read unreachable whenever the repository was missing.
    @MainActor
    func test_loadNotesPaintsLocalRowsEvenWithNoFetcher() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projectId = "22222222-2222-4222-8222-222222222222"

        let local = ProjectNote(
            id: "local-only",
            projectId: projectId,
            companyId: "company-1",
            authorId: "user-1",
            content: "Poured footings"
        )
        context.insert(local)
        try context.save()

        let failing = FailingNoteFetcher()
        let viewModel = ProjectNotesViewModel(projectId: projectId)
        viewModel.setup(
            companyId: "company-1",
            currentUserId: "user-1",
            teamMembers: [],
            modelContext: context,
            dataController: nil,
            noteFetcher: failing
        )

        await viewModel.loadNotes()

        XCTAssertEqual(viewModel.notes.map(\.id), ["local-only"])
    }

    // MARK: - 2b. The composite renderer's generation guard

    /// A render suspended on a download can resume after a LATER render (started
    /// because the annotation changed) already persisted its result. Without a
    /// generation guard the stale render overwrites the fresh composite — and
    /// because the write refreshes the file's mtime, the freshness check then
    /// keeps serving those pre-edit pixels until the next edit.
    ///
    /// A is held open on a gate across B's whole render, exactly as a slow
    /// base-image fetch would hold it.
    func test_aRenderSupersededMidFlightNeverOverwritesTheNewerComposite() async throws {
        let renderer = PhotoCompositeRenderer()
        let cacheKey = "https://example.com/ops-generation-guard-\(UUID().uuidString).jpg"
        defer { ImageFileManager.shared.deleteCompositedImage(forURL: cacheKey) }

        // Distinguishable payloads: whichever composite is on disk at the end is
        // identifiable by its pixel dimensions alone.
        let stale = try XCTUnwrap(Self.jpeg(side: 8))
        let fresh = try XCTUnwrap(Self.jpeg(side: 16))

        let gate = ContinuationGate()
        let aClaimed = expectation(description: "render A claimed the key")

        // Render A: claims the key, then suspends mid-flight.
        let renderA = Task { () -> PhotoCompositeRenderer.PersistOutcome in
            let token = await renderer.beginRender(for: cacheKey)
            aClaimed.fulfill()
            await gate.wait()
            return await renderer.persistIfCurrent(jpeg: stale, cacheKey: cacheKey, token: token)
        }
        await fulfillment(of: [aClaimed], timeout: 2)

        // Render B: starts after A, runs to completion while A is still parked.
        let tokenB = await renderer.beginRender(for: cacheKey)
        let outcomeB = await renderer.persistIfCurrent(jpeg: fresh, cacheKey: cacheKey, token: tokenB)
        XCTAssertEqual(outcomeB, .written)

        await gate.open()
        let outcomeA = await renderA.value

        XCTAssertEqual(
            outcomeA,
            .superseded,
            "A newer render owns the key — the stale render's write must be dropped"
        )
        let persisted = try XCTUnwrap(ImageFileManager.shared.loadCompositedImage(forURL: cacheKey))
        XCTAssertEqual(
            persisted.size,
            CGSize(width: 16, height: 16),
            "The composite on disk must be B's, not the stale render's"
        )
    }

    /// The guard is per key: a slow render of one photo must not be cancelled by
    /// a render of a different photo.
    func test_theGenerationGuardIsScopedToOneCompositeKey() async throws {
        let renderer = PhotoCompositeRenderer()
        let keyA = "https://example.com/ops-guard-a-\(UUID().uuidString).jpg"
        let keyB = "https://example.com/ops-guard-b-\(UUID().uuidString).jpg"
        defer {
            ImageFileManager.shared.deleteCompositedImage(forURL: keyA)
            ImageFileManager.shared.deleteCompositedImage(forURL: keyB)
        }

        let jpeg = try XCTUnwrap(Self.jpeg(side: 8))
        let tokenA = await renderer.beginRender(for: keyA)
        _ = await renderer.beginRender(for: keyB)

        let outcomeA = await renderer.persistIfCurrent(jpeg: jpeg, cacheKey: keyA, token: tokenA)
        XCTAssertEqual(
            outcomeA,
            .written,
            "Another photo's render must not supersede this one"
        )
    }

    /// A solid opaque square, encoded as JPEG. Size is the identity.
    private static func jpeg(side: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        ).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: - 3. getAllProjects drops tombstones

    @MainActor
    func test_getAllProjectsReturnsExactlyWhatTheInMemoryFilterReturned() throws {
        let fixture = try makeProjectFixture()

        let everyRow = try fixture.context.fetch(FetchDescriptor<Project>())
        // The pre-predicate call sites' own filter, verbatim.
        let filteredInMemory = everyRow.filter { $0.deletedAt == nil }

        XCTAssertTrue(
            everyRow.contains { $0.deletedAt != nil },
            "Precondition: the store has to hold tombstones for this to mean anything"
        )
        XCTAssertEqual(
            fixture.dataController.getAllProjects().map(\.id),
            filteredInMemory.map(\.id),
            "The fetch predicate must return the same rows in the same order as the filter it replaced"
        )
    }

    /// The job board resolves a task's project through `getAllProjects()`. A
    /// deleted job must not be resolvable — it is not on the board.
    @MainActor
    func test_getAllProjectsNeverResolvesATombstonedJob() throws {
        let fixture = try makeProjectFixture()

        let ids = Set(fixture.dataController.getAllProjects().map(\.id))
        XCTAssertEqual(ids, ["p-live", "p-live-2"])
        XCTAssertTrue(ids.isDisjoint(with: ["p-deleted"]))
    }

    // MARK: - Fixtures

    private struct ProjectFixture {
        let context: ModelContext
        let dataController: DataController
    }

    @MainActor
    private func makeProjectFixture() throws -> ProjectFixture {
        let container = try makeContainer()
        let context = ModelContext(container)

        for (id, title, deleted) in [
            ("p-live", "South deck rebuild", false),
            ("p-live-2", "Cedar rail swap", false),
            ("p-deleted", "Cancelled patio", true),
        ] {
            let project = Project(id: id, title: title, status: .inProgress)
            project.companyId = "company-1"
            if deleted {
                project.deletedAt = Date(timeIntervalSinceNow: -86_400)
            }
            context.insert(project)
        }
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        return ProjectFixture(context: context, dataController: dataController)
    }

    /// Every container seeds one inert SyncOperation. A `#Predicate` fetch of
    /// SyncOperation TRAPS (uncatchable EXC_BREAKPOINT, not a thrown error)
    /// against a table that has never held a row, and the client merge reaches
    /// exactly such a fetch through `hasRecentLocalWrite` / `acceptableFields`.
    /// Seeding here rather than per test means no test is green by luck of
    /// ordering. Same remedy as CatalogMergeDiffGateTests.makeContainer.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV19.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let warmUp = ModelContext(container)
        warmUp.insert(SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: "sync-operation-warm-up",
            operationType: "update",
            payload: Data(),
            changedFields: ["id"]
        ))
        try warmUp.save()

        return container
    }

    private func clientDTO(id: String, name: String) -> SupabaseClientDTO {
        SupabaseClientDTO(
            id: id,
            bubbleId: nil,
            companyId: "company-1",
            name: name,
            email: nil,
            phoneNumber: nil,
            address: nil,
            latitude: nil,
            longitude: nil,
            notes: nil,
            profileImageUrl: nil,
            deletedAt: nil
        )
    }

    private func noteDTO(id: String, projectId: String) throws -> ProjectNoteDTO {
        let json = """
        {
          "id": "\(id)",
          "project_id": "\(projectId)",
          "company_id": "company-1",
          "author_id": "user-2",
          "content": "Inspector booked",
          "created_at": "2026-08-10T17:00:00Z"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(ProjectNoteDTO.self, from: json)
    }
}

// MARK: - Note fetch doubles

/// Holds the server fetch open so the local paint can be observed while it is
/// still in flight — the ordering this change is about.
private final class GatedNoteFetcher: ProjectNoteFetching, @unchecked Sendable {
    private let dtos: [ProjectNoteDTO]
    private let started: XCTestExpectation
    private let gate = ContinuationGate()

    init(dtos: [ProjectNoteDTO], started: XCTestExpectation) {
        self.dtos = dtos
        self.started = started
    }

    func fetchForProject(_ projectId: String) async throws -> [ProjectNoteDTO] {
        started.fulfill()
        await gate.wait()
        return dtos
    }

    func open() async {
        await gate.open()
    }
}

/// Stands in for an unreachable server.
private final class FailingNoteFetcher: ProjectNoteFetching, @unchecked Sendable {
    struct Offline: Error {}

    func fetchForProject(_ projectId: String) async throws -> [ProjectNoteDTO] {
        throw Offline()
    }
}

private actor ContinuationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
