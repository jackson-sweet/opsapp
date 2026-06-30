//
//  TaskTypeDuplicateDedupeTests.swift
//  OPSTests
//
//  Regression coverage for the task-type duplicate bug: a task type created on
//  iOS with an UPPERCASE `UUID().uuidString` id diverges from the lowercase form
//  Postgres stores for the `task_types.id` uuid column. The realtime echo /
//  inbound delta then fails its case-sensitive fetch-by-id, inserts a second
//  local row, and `cleanupDuplicateTaskTypes` (which groups by exact id) never
//  collapses the pair because the two casings live in different groups.
//
//  The fix adds `DataActor.normalizeTaskTypeIdsToLowercase()`, run on launch
//  BEFORE `cleanupDuplicateTaskTypes`, to canonicalize the id (and the
//  `ProjectTask.taskTypeId` strings + taskType `SyncOperation.entityId`s that
//  reference it) so the dedup sees one group and keeps a single row.
//

import SwiftData
import XCTest
@testable import OPS

final class TaskTypeDuplicateDedupeTests: XCTestCase {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            User.self,
            SyncOperation.self,
            CalendarUserEvent.self,
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The production repro: an uppercase "orphan" (the original local insert)
    /// and a lowercase "echo" (re-inserted by the case-sensitive sync layer)
    /// for the SAME underlying uuid. After normalize + dedup exactly one row
    /// must survive, carrying the canonical lowercase id, with the referencing
    /// task + pending sync op repointed onto it.
    func test_normalizeAndDedupe_collapsesCaseVariantDuplicate() async throws {
        let container = try makeInMemoryContainer()
        let seed = ModelContext(container)

        let companyId = "company-1"
        let upperId = "AABBCCDD-1122-3344-5566-7788990011FF"
        let lowerId = upperId.lowercased()
        XCTAssertNotEqual(upperId, lowerId, "Fixture must actually differ by case")

        // Orphan: original local insert (uppercase id).
        let orphan = TaskType(id: upperId, display: "Framing", color: "93A17C", companyId: companyId)
        // Echo: server row re-pulled by the sync layer (lowercase id).
        let echo = TaskType(id: lowerId, display: "Framing", color: "93A17C", companyId: companyId)
        seed.insert(orphan)
        seed.insert(echo)

        // A task that references the orphan by id-string (the column the
        // rewire path resolves against).
        let task = ProjectTask(id: "task-1", projectId: "project-1", taskTypeId: upperId, companyId: companyId)
        seed.insert(task)

        // A pending create op recorded against the uppercase id.
        let op = SyncOperation(
            entityType: SyncEntityType.taskType.rawValue,
            entityId: upperId,
            operationType: "create",
            payload: Data(),
            changedFields: ["display", "color"]
        )
        seed.insert(op)
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        await actor.normalizeTaskTypeIdsToLowercase()
        await actor.cleanupDuplicateTaskTypes()

        // Verify from a fresh context so we read the persisted store, not stale
        // registered objects.
        let check = ModelContext(container)

        let types = try check.fetch(FetchDescriptor<TaskType>())
        XCTAssertEqual(types.count, 1, "Case-variant duplicate must collapse to a single row")
        XCTAssertEqual(types.first?.id, lowerId, "Survivor must carry the canonical lowercase id")

        let tasks = try check.fetch(FetchDescriptor<ProjectTask>())
        XCTAssertEqual(tasks.first?.taskTypeId, lowerId, "Task reference must follow onto the lowercase id")

        let ops = try check.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(ops.first?.entityId, lowerId, "Pending sync op must target the lowercase id")
    }

    /// The 197 existing rows are already lowercase + unique. The launch sweep
    /// runs over ALL of them every cold start, so it must be a no-op on clean
    /// data and idempotent across repeated runs.
    func test_normalizeAndDedupe_leavesCleanLowercaseDataUntouched() async throws {
        let container = try makeInMemoryContainer()
        let seed = ModelContext(container)

        let companyId = "company-1"
        let cleanId = "aabbccdd-1122-3344-5566-7788990011ff"
        let clean = TaskType(id: cleanId, display: "Inspection", color: "748284", companyId: companyId)
        seed.insert(clean)
        let task = ProjectTask(id: "task-1", projectId: "project-1", taskTypeId: cleanId, companyId: companyId)
        seed.insert(task)
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        // Run twice to prove idempotency.
        await actor.normalizeTaskTypeIdsToLowercase()
        await actor.cleanupDuplicateTaskTypes()
        await actor.normalizeTaskTypeIdsToLowercase()
        await actor.cleanupDuplicateTaskTypes()

        let check = ModelContext(container)
        let types = try check.fetch(FetchDescriptor<TaskType>())
        XCTAssertEqual(types.count, 1, "A clean row must not be duplicated or deleted")
        XCTAssertEqual(types.first?.id, cleanId, "A clean lowercase id must be left unchanged")

        let tasks = try check.fetch(FetchDescriptor<ProjectTask>())
        XCTAssertEqual(tasks.first?.taskTypeId, cleanId, "A clean task reference must be left unchanged")
    }
}
