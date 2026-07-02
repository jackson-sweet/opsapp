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
}
