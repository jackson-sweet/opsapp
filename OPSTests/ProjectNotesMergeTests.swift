//
//  ProjectNotesMergeTests.swift
//  OPSTests
//
//  loadNotes() ran one FetchDescriptor per DTO on the main context at screen
//  open. The merge now does a single project-scoped fetch; these tests pin
//  insert + update behavior.
//

import XCTest
import SwiftData
@testable import OPS

final class ProjectNotesMergeTests: XCTestCase {

    @MainActor
    func testMergeInsertsNewAndUpdatesExisting() throws {
        let container = try ModelContainer(
            for: ProjectNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let existing = ProjectNote(
            id: "n1", projectId: "p1", companyId: "c1",
            authorId: "u1", content: "old"
        )
        context.insert(existing)
        try context.save()

        let json = """
        [
          {"id":"n1","project_id":"p1","company_id":"c1","author_id":"u1","content":"new","created_at":"2026-07-01T00:00:00Z"},
          {"id":"n2","project_id":"p1","company_id":"c1","author_id":"u2","content":"fresh","created_at":"2026-07-01T01:00:00Z"}
        ]
        """.data(using: .utf8)!
        let dtos = try JSONDecoder().decode([ProjectNoteDTO].self, from: json)

        ProjectNotesViewModel.mergeFetchedNotes(dtos, projectId: "p1", context: context)

        let all = try context.fetch(FetchDescriptor<ProjectNote>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.id == "n1" })?.content, "new")
        XCTAssertEqual(all.first(where: { $0.id == "n2" })?.content, "fresh")
        XCTAssertEqual(all.first(where: { $0.id == "n1" })?.needsSync, false)
    }

    /// Bug f9e00eb9 — a locally-deleted note whose tombstone hasn't pushed yet
    /// (needsSync == true) must NOT be resurrected by a fetch that still
    /// carries the live server row. Pending local truth wins until synced.
    @MainActor
    func testMergeSkipsRowsWithPendingLocalChanges() throws {
        let container = try ModelContainer(
            for: ProjectNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let tombstoned = ProjectNote(
            id: "n1", projectId: "p1", companyId: "c1",
            authorId: "u1", content: "delete me"
        )
        tombstoned.deletedAt = Date()
        tombstoned.needsSync = true
        context.insert(tombstoned)
        try context.save()

        // Server still has the live (undeleted) row — a stale snapshot.
        let json = """
        [
          {"id":"n1","project_id":"p1","company_id":"c1","author_id":"u1","content":"delete me","created_at":"2026-07-01T00:00:00Z"}
        ]
        """.data(using: .utf8)!
        let dtos = try JSONDecoder().decode([ProjectNoteDTO].self, from: json)

        ProjectNotesViewModel.mergeFetchedNotes(dtos, projectId: "p1", context: context)

        let row = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProjectNote>()).first(where: { $0.id == "n1" })
        )
        XCTAssertNotNil(row.deletedAt, "pending tombstone must survive a stale live-row merge")
        XCTAssertTrue(row.needsSync, "pending flag must survive until the delete op pushes")
    }

    /// A tombstone arriving FROM the server (cross-device delete) still applies
    /// to a clean local row.
    @MainActor
    func testMergeAppliesServerTombstoneToCleanRow() throws {
        let container = try ModelContainer(
            for: ProjectNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let clean = ProjectNote(
            id: "n1", projectId: "p1", companyId: "c1",
            authorId: "u1", content: "hello"
        )
        context.insert(clean)
        try context.save()

        let json = """
        [
          {"id":"n1","project_id":"p1","company_id":"c1","author_id":"u1","content":"hello","created_at":"2026-07-01T00:00:00Z","deleted_at":"2026-07-02T00:00:00Z"}
        ]
        """.data(using: .utf8)!
        let dtos = try JSONDecoder().decode([ProjectNoteDTO].self, from: json)

        ProjectNotesViewModel.mergeFetchedNotes(dtos, projectId: "p1", context: context)

        let row = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProjectNote>()).first(where: { $0.id == "n1" })
        )
        XCTAssertNotNil(row.deletedAt, "server tombstone must apply to a clean local row")
    }

    /// event_kind + content_metadata (live columns) ride the DTO into the model
    /// so system entries (status changes, site-visit packets) can render as
    /// first-class feed cards.
    @MainActor
    func testMergeCarriesEventKindAndContentMetadata() throws {
        let container = try ModelContainer(
            for: ProjectNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let json = """
        [
          {"id":"n3","project_id":"p1","company_id":"c1","author_id":"u1","content":"Status changed","event_kind":"status_change","content_metadata":{"from":"estimated","to":"archived"},"created_at":"2026-07-01T00:00:00Z"}
        ]
        """.data(using: .utf8)!
        let dtos = try JSONDecoder().decode([ProjectNoteDTO].self, from: json)

        ProjectNotesViewModel.mergeFetchedNotes(dtos, projectId: "p1", context: context)

        let row = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProjectNote>()).first(where: { $0.id == "n3" })
        )
        XCTAssertEqual(row.eventKind, "status_change")
        let metadataJSON = try XCTUnwrap(row.contentMetadataJSON)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadataJSON.utf8)) as? [String: String]
        )
        XCTAssertEqual(decoded["from"], "estimated")
        XCTAssertEqual(decoded["to"], "archived")
    }
}
