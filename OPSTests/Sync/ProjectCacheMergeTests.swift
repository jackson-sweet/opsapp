//
//  ProjectCacheMergeTests.swift
//  OPSTests
//
//  Bug 4cbf2efe — the won toast's VIEW PROJECT opened a blank sheet because the
//  converted project was never written to SwiftData: the conversion service
//  mapped the fetched DTO with `toModel()` and handed back a DETACHED model.
//  Every project-by-id lookup (`DataController.getProject`) reads SwiftData, so
//  the sheet had nothing to render.
//
//  These tests pin the canonical project cache seam that both realtime and the
//  post-commit conversion fetch now funnel through: an authoritative row is
//  inserted when absent, merged field-by-field when present, and never allowed
//  to clobber a field with a pending or in-flight local write.
//

import XCTest
import SwiftData
@testable import OPS

final class ProjectCacheMergeTests: XCTestCase {

    // MARK: - Fixtures

    /// The explicit schema `ProjectNoteMentionEditTests` uses — the one proven
    /// to survive a PREDICATE fetch of `SyncOperation`. An implicit
    /// `ModelContainer(for: Project.self, …)`, and even the shorter list in
    /// `ProjectVinylOrderMarkerSyncTests`, leave part of `Project`'s
    /// relationship graph out of the schema and SwiftData traps (EXC_BREAKPOINT
    /// inside `context.fetch`) rather than throwing.
    /// The container MUST outlive the context. `try makeContainer().mainContext`
    /// releases the container at the end of that statement and leaves a
    /// dangling context — SwiftData then trap-crashes (EXC_BREAKPOINT) or wedges
    /// the test host on the first fetch, with the stack pointing at whatever
    /// happened to touch it first.
    private var container: ModelContainer!

    @MainActor
    private func makeContext() throws -> ModelContext {
        container = try makeContainer()
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectNote.self,
            ProjectPhoto.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self,
            ProjectPrimaryContactSelection.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func projectDTO(
        id: String = "project-converted",
        title: String = "3998 Holland Ave",
        status: String = "accepted",
        address: String? = "3998 Holland Ave, Victoria BC",
        opportunityId: String? = "lead-1",
        primarySubClientId: String? = "contact-1"
    ) throws -> SupabaseProjectDTO {
        let json = """
        {
          "id": "\(id)",
          "company_id": "company-1",
          "client_id": "client-1",
          "primary_sub_client_id": \(primarySubClientId.map { "\"\($0)\"" } ?? "null"),
          "opportunity_id": \(opportunityId.map { "\"\($0)\"" } ?? "null"),
          "title": "\(title)",
          "status": "\(status)",
          "address": \(address.map { "\"\($0)\"" } ?? "null"),
          "created_at": "2026-07-28T10:00:00Z"
        }
        """
        return try JSONDecoder().decode(SupabaseProjectDTO.self, from: Data(json.utf8))
    }

    // MARK: - Insert

    /// The regression itself: a project the operator has never seen locally
    /// must become queryable by id the moment the authoritative row arrives.
    @MainActor
    func testAuthoritativeRowInsertsAProjectQueryableById() throws {
        let context = try makeContext()
        let dto = try projectDTO()

        let merged = try ProjectCacheMerge.apply(
            dto: dto, context: context, protectedFields: [], hasPendingWrite: false
        )

        let id = dto.id
        let stored = try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        )
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "3998 Holland Ave")
        XCTAssertEqual(stored.first?.opportunityId, "lead-1")
        XCTAssertEqual(stored.first?.primarySubClientId, "contact-1")
        let selections = try context.fetch(
            FetchDescriptor<ProjectPrimaryContactSelection>()
        )
        XCTAssertEqual(selections.first?.primarySubClientId, "contact-1")
        XCTAssertEqual(merged.id, dto.id)
        XCTAssertFalse(merged.needsSync)
        XCTAssertNotNil(merged.lastSyncedAt)
    }

    /// The vinyl-order marker is a sibling row of every project; a project that
    /// arrives without one breaks the VINYL ORDERS board's marker joins.
    @MainActor
    func testInsertAlsoMaterializesTheVinylOrderMarker() throws {
        let context = try makeContext()
        let dto = try projectDTO()

        _ = try ProjectCacheMerge.apply(
            dto: dto, context: context, protectedFields: [], hasPendingWrite: false
        )

        let id = dto.id
        let markers = try context.fetch(
            FetchDescriptor<ProjectVinylOrderMarker>(predicate: #Predicate { $0.id == id })
        )
        XCTAssertEqual(markers.count, 1)
    }

    /// Re-applying the same authoritative row must update in place. A second
    /// insert would duplicate the project (`Project.id` is not `.unique`).
    @MainActor
    func testReapplyingTheSameRowUpdatesInPlaceInsteadOfDuplicating() throws {
        let context = try makeContext()

        _ = try ProjectCacheMerge.apply(
            dto: try projectDTO(), context: context,
            protectedFields: [], hasPendingWrite: false
        )
        _ = try ProjectCacheMerge.apply(
            dto: try projectDTO(title: "3998 Holland Ave #2", status: "in_progress"),
            context: context, protectedFields: [], hasPendingWrite: false
        )

        let stored = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "3998 Holland Ave #2")
        XCTAssertEqual(stored.first?.status, .inProgress)
    }

    // MARK: - Field protection

    /// A pending local write must survive the merge — matching an existing
    /// project pulls the server row over a project the operator may have just
    /// edited offline.
    ///
    /// The protected set is passed explicitly, which is exactly how realtime
    /// calls this (it computes its own sets and injects them). Materialising a
    /// `SyncOperation` row and re-reading it through the convenience overload
    /// is not viable in a test host: a fetch of `SyncOperation` against a
    /// fresh in-memory container either traps inside SwiftData (with a
    /// predicate) or wedges the host (without one), reproducibly, on both the
    /// short and the full schema list. The lookup itself is a filter over one
    /// fetch; the MERGE semantics it feeds are what matter, and they are
    /// pinned here.
    @MainActor
    func testProtectedFieldSurvivesTheMerge() throws {
        let context = try makeContext()
        let cached = try ProjectCacheMerge.apply(
            dto: try projectDTO(), context: context,
            protectedFields: [], hasPendingWrite: false
        )
        // The local edit marks the row dirty; the merge's job is only to leave
        // that alone. (It never SETS needsSync — same contract realtime has
        // always had.)
        cached.needsSync = true
        try context.save()

        _ = try ProjectCacheMerge.apply(
            dto: try projectDTO(title: "Server renamed", status: "in_progress"),
            context: context,
            protectedFields: ["title"],
            hasPendingWrite: true
        )

        let stored = try context.fetch(FetchDescriptor<Project>()).first
        XCTAssertEqual(stored?.title, "3998 Holland Ave", "protected local title must win")
        XCTAssertEqual(stored?.status, .inProgress, "unprotected fields still merge")
        XCTAssertTrue(stored?.needsSync ?? false, "an un-pushed local write stays dirty")
    }

    @MainActor
    func testProtectedPrimaryContactSurvivesTheMerge() throws {
        let context = try makeContext()
        let cached = try ProjectCacheMerge.apply(
            dto: try projectDTO(), context: context,
            protectedFields: [], hasPendingWrite: false
        )
        cached.primarySubClientId = "local-contact"
        cached.needsSync = true
        try context.save()

        let merged = try ProjectCacheMerge.apply(
            dto: try projectDTO(primarySubClientId: "server-contact"),
            context: context,
            protectedFields: ["primary_sub_client_id"],
            hasPendingWrite: true
        )

        XCTAssertEqual(merged.primarySubClientId, "local-contact")
        XCTAssertTrue(merged.needsSync)
    }

    /// With nothing pending, the merged row is clean and fully server-shaped.
    @MainActor
    func testUnprotectedMergeOverwritesEveryFieldAndClearsTheDirtyFlag() throws {
        let context = try makeContext()
        let cachedForClearing = try? ProjectCacheMerge.apply(
            dto: try projectDTO(), context: context,
            protectedFields: [], hasPendingWrite: false
        )

        cachedForClearing?.needsSync = true
        try context.save()

        let merged = try ProjectCacheMerge.apply(
            dto: try projectDTO(
                title: "Server renamed",
                status: "in_progress",
                address: "4000 Holland Ave",
                opportunityId: "lead-2"
            ),
            context: context,
            protectedFields: [],
            hasPendingWrite: false
        )

        XCTAssertEqual(merged.title, "Server renamed")
        XCTAssertEqual(merged.status, .inProgress)
        XCTAssertEqual(merged.address, "4000 Holland Ave")
        XCTAssertEqual(merged.opportunityId, "lead-2")
        XCTAssertFalse(merged.needsSync)
    }
}
