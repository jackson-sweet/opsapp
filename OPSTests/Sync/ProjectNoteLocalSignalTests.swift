//
//  ProjectNoteLocalSignalTests.swift
//  OPSTests
//
//  Bug 0969bc8a — a vinyl ORDERED record reached the server but never appeared
//  in an already-mounted project Activity tab. The feed's view model reloads
//  only on `.projectNoteReceived`, which RealtimeProcessor posts for OTHER
//  devices' writes; a local write through `DataController.createProjectNote`
//  (the door the vinyl recorder and the site-visit packet both use) announced
//  nothing, so the mounted feed stayed on its stale snapshot until the project
//  was closed and reopened.
//
//  What these pin:
//    1. `createProjectNote` posts the local change signal for the note's
//       project — the bridge that makes a mounted feed reload.
//    2. The degenerate "marker only" vinyl record still renders an honest
//       activity line, which is what a job with no resolvable deck materials
//       now writes from both plain MARK ORDERED paths.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class ProjectNoteLocalSignalTests: XCTestCase {

    // MARK: - Local write announces itself

    func testCreateProjectNotePostsChangeSignal() throws {
        let context = try makeContext()
        let controller = DataController()
        // The full wiring, not a bare `modelContext` assignment: it is what
        // gives the controller a real `syncEngine`, which createProjectNote
        // records its outbound operation through.
        controller.setModelContext(context)

        let note = ProjectNote(
            projectId: "project-signal-1",
            companyId: "company-1",
            authorId: "operator-1",
            content: "Vinyl marked ordered.",
            createdAt: Date()
        )

        // ProjectNoteChangeSignal hops to the main queue, so the post lands
        // after createProjectNote returns — hence an expectation, not a
        // synchronous assertion.
        let signalled = expectation(forNotification: .projectNoteReceived, object: nil) { notification in
            (notification.userInfo?["projectId"] as? String) == "project-signal-1"
        }

        controller.createProjectNote(note: note)

        wait(for: [signalled], timeout: 2)
    }

    // MARK: - The marker-only record still says something honest

    func testVinylPlainRecordBuildsMarkedOrderedLine() {
        let supplier = VinylOrderActivityNote.build(
            VinylOrderActivityNote.Record(
                disposition: .supplier,
                vinylLines: [],
                consumables: [],
                orderedAt: Date()
            )
        )
        XCTAssertEqual(supplier?.content, "Vinyl marked ordered.")

        let shop = VinylOrderActivityNote.build(
            VinylOrderActivityNote.Record(
                disposition: .shop,
                vinylLines: [],
                consumables: [],
                orderedAt: Date()
            )
        )
        XCTAssertEqual(shop?.content, "Vinyl pulled from shop. Nothing ordered.")
    }

    // MARK: - Fixtures

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
        let container = try makeContainer()
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// Every container seeds one inert SyncOperation. A `#Predicate` fetch of
    /// SyncOperation TRAPS (uncatchable EXC_BREAKPOINT, not a thrown error)
    /// against a table that has never held a row, so no test here is green by
    /// luck of ordering.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
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
}
