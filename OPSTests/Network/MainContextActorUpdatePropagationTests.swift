//
//  MainContextActorUpdatePropagationTests.swift
//  OPSTests
//
//  DIAGNOSTIC PROBE (reschedule-not-surfacing investigation).
//
//  The calendar reads tasks via `dataController.modelContext` — the LONG-LIVED
//  main context (container.mainContext) — into a snapshot cache. When a
//  teammate reschedules a task, the DataActor merges the new dates on ITS OWN
//  context. This probe asks the pivotal question that decides the root cause:
//
//    After the DataActor saves an UPDATE to a task the main context has ALREADY
//    loaded (registered), does a fresh fetch on that SAME main context return
//    the NEW startDate — or the stale one?
//
//  Uses an ON-DISK store (not in-memory) so cross-context merge behaves like
//  production's SQLite-backed container. Existing actor tests all fetch via a
//  throwaway `ModelContext(container)`, which always reads the store fresh and
//  therefore never exercises the registered-object path the calendar uses.
//

import SwiftData
import XCTest
@testable import OPS

final class MainContextActorUpdatePropagationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptr-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("store.sqlite")
    }

    override func tearDownWithError() throws {
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func makeOnDiskContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            User.self,
            SyncOperation.self,
            CalendarUserEvent.self,
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTaskDTO(
        id: String,
        startDate: String?,
        endDate: String?
    ) -> SupabaseProjectTaskDTO {
        SupabaseProjectTaskDTO(
            id: id,
            bubbleId: nil,
            companyId: "company-1",
            projectId: "project-1",
            taskTypeId: nil,
            customTitle: "Footings",
            taskNotes: nil,
            status: "scheduled",
            taskColor: nil,
            displayOrder: 0,
            teamMemberIds: nil,
            sourceLineItemId: nil,
            sourceEstimateId: nil,
            startDate: startDate,
            endDate: endDate,
            duration: 2,
            dependencyOverrides: nil,
            startTime: nil,
            endTime: nil,
            pairedFromTaskId: nil,
            scheduleLocked: nil,
            deletedAt: nil,
            createdAt: nil
        )
    }

    private let taskId = "5f345678-90ab-cdef-0123-456789abcdef"
    private let rescheduledStartISO = "2026-06-20T00:00:00+00:00"

    /// Seeds a task on the main context (so it is registered/realized exactly
    /// like the calendar's loaded copy), then has the DataActor merge a
    /// reschedule on its own context. Returns the main context plus the
    /// immediate (synchronous) and settled re-reads of startDate.
    @MainActor
    private func runReschedule(
        container: ModelContainer
    ) async throws -> (immediate: Date?, settled: Date?, expected: Date) {
        let mainContext = container.mainContext   // == DataController.modelContext
        let originalStart = SupabaseDate.parse("2026-06-10T00:00:00+00:00")!
        let expectedNewStart = SupabaseDate.parse(rescheduledStartISO)!

        let seed = ProjectTask(id: taskId, projectId: "project-1", taskTypeId: "", companyId: "company-1")
        seed.startDate = originalStart
        seed.needsSync = false
        mainContext.insert(seed)
        try mainContext.save()

        // Calendar has already loaded the OLD date.
        let before = try mainContext.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        ).first?.startDate
        XCTAssertEqual(before, originalStart, "precondition: main context holds the OLD date")

        // Teammate reschedules → actor merges on its own context (same container).
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        await actor.handleRealtimeUpdate(
            .task(makeTaskDTO(id: taskId, startDate: rescheduledStartISO, endDate: "2026-06-21T00:00:00+00:00"))
        )

        // Immediate read — mirrors refreshCalendar()'s synchronous re-fetch
        // right after the sync await.
        let immediate = try mainContext.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        ).first?.startDate

        // Settled read — after the run loop turns, in case propagation is merely
        // deferred rather than absent.
        try await Task.sleep(for: .milliseconds(750))
        let settled = try mainContext.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        ).first?.startDate

        return (immediate, settled, expectedNewStart)
    }

    /// CORRECTNESS: the calendar's context must EVENTUALLY reflect the reschedule.
    @MainActor
    func test_onDisk_settled_mainContextReflectsReschedule() async throws {
        let container = try makeOnDiskContainer()
        let r = try await runReschedule(container: container)
        XCTAssertEqual(r.settled, r.expected,
                       "main context never reflected the actor's reschedule of an already-loaded task")
    }

    /// TIMING: does the SYNCHRONOUS re-fetch (the one refreshCalendar performs
    /// immediately after the sync await) already see the new date? If this
    /// fails but the settled test passes, the calendar's immediate repaint is a
    /// race that lands a beat before propagation.
    @MainActor
    func test_onDisk_immediate_mainContextReflectsReschedule() async throws {
        let container = try makeOnDiskContainer()
        let r = try await runReschedule(container: container)
        XCTAssertEqual(r.immediate, r.expected,
                       "synchronous re-fetch after the merge did NOT see the new date (timing race)")
    }
}
