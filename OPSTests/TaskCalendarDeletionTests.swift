import SwiftData
import XCTest
@testable import OPS

@MainActor
final class TaskCalendarDeletionTests: XCTestCase {
    private final class OfflineConnectivity: ConnectivityManager {
        override var shouldAttemptSync: Bool { false }
    }
    private var offline = OfflineConnectivity()
    private var savedActorFlag: Any?
    override func setUp() {
        super.setUp()
        savedActorFlag = UserDefaults.standard.object(forKey: "feature.useDataActor")
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
    }
    override func tearDown() async throws {
        // ModelContext does not own its container. Keep every fixture store
        // alive through cancellation of queued controller/engine callbacks.
        for controller in controllers { controller.syncEngine.stopForLogoutSync() }
        for controller in controllers { await controller.syncEngine.stopForLogoutAsync() }
        controllers.removeAll()
        containers.removeAll()
        UserDefaults.standard.set(savedActorFlag, forKey: "feature.useDataActor")
        try await super.tearDown()
    }
    private var containers: [ModelContainer] = []
    private var controllers: [DataController] = []
    private let companyID = "11111111-1111-4111-8111-111111111111"
    private let taskID = "22aaaaaa-2222-4222-8222-222222222222"
    private let date = Date(timeIntervalSince1970: 1_789_023_600)

    func testDeletedTaskCannotBeScheduledOrQueued() async throws {
        let (controller, context, task) = try fixture()
        task.deletedAt = date.addingTimeInterval(-86_400)
        try context.save()
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
            XCTFail("A deleted task must reject a schedule edit before changing local dates")
        } catch {}
        XCTAssertNil(task.startDate)
        XCTAssertNil(task.endDate)
        XCTAssertFalse(task.scheduleLocked)
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testDeletedTaskHasNoOrdinaryMutationAffordances() {
        let store = PermissionStore.shared
        let saved = store.permissions
        let blocked = store.blockedByFlags
        defer { store.permissions = saved; store.blockedByFlags = blocked }
        store.permissions = ["tasks.edit": "all", "tasks.assign": "all", "tasks.change_status": "all", "calendar.edit": "all"]
        store.blockedByFlags = []
        let task = ProjectTask(id: taskID, projectId: "p", taskTypeId: "t", companyId: companyID)
        task.deletedAt = date
        XCTAssertFalse(task.canEditFields)
        XCTAssertFalse(task.canAssignCrew)
        XCTAssertFalse(task.canEditSchedule)
        XCTAssertFalse(task.canChangeStatus)
    }

    func testRejectedScheduleOnDeletedTaskRemainsRecoverable() throws {
        let (_, context, task) = try fixture()
        task.deletedAt = date.addingTimeInterval(-86_400)
        task.startDate = date
        task.needsSync = true
        let operation = SyncOperation(entityType: "projectTask", entityId: task.id,
            operationType: "update", payload: Data("{\"start_date\":\"2026-09-10T07:00:00Z\"}".utf8),
            changedFields: ["start_date"])
        operation.status = "parked"
        operation.lastError = SyncError.serverRowMissingMarker
        context.insert(operation)
        try context.save()
        _ = try DeletedProjectTaskOperationSettlement.sweep(in: context, activeCompanyId: companyID)
        XCTAssertEqual(operation.status, "parked", "A rejected schedule is operator work, not an obsolete reorder")
        XCTAssertNil(operation.completedAt)
        XCTAssertNil(operation.serverConfirmedAt)
        XCTAssertEqual(task.startDate, date)
        XCTAssertTrue(task.needsSync)
    }

    func testZeroRowTaskUpdateEntersReconciliation() {
        XCTAssertEqual(SyncOperationReconcilers.kind(operationType: "update", entityType: "projectTask",
            errorDescription: SyncError.serverRowMissing(table: "project_tasks", id: taskID).localizedDescription),
            .taskTombstone)
    }

    func testScheduleWaitsBehindRestoreEvenWhenRestoreIsParked() {
        let restore = operation(fields: ["deleted_at": NSNull()])
        restore.createdAt = date
        restore.status = "parked"
        let schedule = operation(fields: ["start_date": "2026-09-10T07:00:00Z"])
        schedule.createdAt = date.addingTimeInterval(1)
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(schedule, in: [restore, schedule]))
        restore.status = "completed"
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(schedule, in: [restore, schedule]))
    }

    func testOfflineDeleteRestoreAndScheduleAreNotCollapsedToDelete() {
        let deletion = operation(fields: ["id": taskID])
        deletion.operationType = "delete"
        deletion.createdAt = date
        let restore = operation(fields: ["deleted_at": NSNull()])
        restore.createdAt = date.addingTimeInterval(1)
        let schedule = operation(fields: ["start_date": "2026-09-10T07:00:00Z"])
        schedule.createdAt = date.addingTimeInterval(2)
        let result = OutboundProcessor().coalesceOperations([deletion, restore, schedule])
        XCTAssertEqual(result.map(\.id), [deletion.id, restore.id, schedule.id])
        XCTAssertTrue([deletion, restore, schedule].allSatisfy { $0.status == "pending" })
    }

    func testTaskListKeepsLiveTerminalTasksButRejectsDeletedAndStaleRelationships() throws {
        let (_, context, task) = try fixture()
        let project = Project(id: task.projectId, title: "Schedule fixture", status: .inProgress)
        project.companyId = companyID
        context.insert(project)
        task.project = project
        let complete = ProjectTask(id: "complete", projectId: project.id, taskTypeId: "tt", companyId: companyID, status: .completed)
        let cancelled = ProjectTask(id: "cancelled", projectId: project.id, taskTypeId: "tt", companyId: companyID, status: .cancelled)
        let deleted = ProjectTask(id: "deleted", projectId: project.id, taskTypeId: "tt", companyId: companyID)
        deleted.deletedAt = date
        let foreign = ProjectTask(id: "foreign", projectId: project.id, taskTypeId: "tt", companyId: "other-company")
        let wrongProject = ProjectTask(id: "wrong-project", projectId: "other-project", taskTypeId: "tt", companyId: companyID)
        for row in [complete, cancelled, deleted, foreign, wrongProject] { context.insert(row) }
        project.tasks = [task, complete, cancelled, deleted, foreign, wrongProject]
        XCTAssertEqual(project.liveTasks.map(\.id), [taskID, "complete", "cancelled"])
        let section = TaskListSection(tasks: project.tasks, selectedTask: nil, project: project,
            canEdit: false, canDuplicate: false, userById: [:], onTaskTap: { _ in }, onAddTask: {})
        XCTAssertEqual(section.visibleTasks.map(\.id), [taskID, "complete", "cancelled"])
    }

    func testLiveDuplicateCannotExposeOrScheduleATombstonedIdentity() async throws {
        let (controller, context, task) = try fixture()
        let twin = ProjectTask(id: task.id.uppercased(), projectId: task.projectId, taskTypeId: "tt", companyId: companyID)
        twin.deletedAt = date
        context.insert(twin)
        try context.save()
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
            XCTFail("A stale live twin must not bypass the exact identity tombstone")
        } catch {
            XCTAssertEqual(error as? DataController.DurableSyncMutationError, .taskUnavailable)
        }
        XCTAssertNil(task.startDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testScheduleTransactionRollsBackWhenOutboxStagingFails() async throws {
        let (controller, context, task) = try fixture()
        let oldDate = date.addingTimeInterval(-86_400)
        task.startDate = oldDate
        task.endDate = oldDate
        try context.save()
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date,
                stagingOperationsWith: { _, _ in throw CocoaError(.fileWriteUnknown) })
            XCTFail("A schedule must not save without its outbox entry")
        } catch {
            XCTAssertEqual(error as? DataController.DurableSyncMutationError, .syncQueueFailed)
        }
        XCTAssertEqual(task.startDate, oldDate)
        XCTAssertFalse(task.scheduleLocked)
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testActiveAndTerminalSchedulesRemainLocalUntilConfirmed() async throws {
        for status in [TaskStatus.active, .completed, .cancelled] {
            let (controller, context, task) = try fixture()
            task.status = status
            try context.save()
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
            let operations = try context.fetch(FetchDescriptor<SyncOperation>())
            let update = try XCTUnwrap(operations.first { $0.getChangedFields().contains("start_date") })
            XCTAssertEqual(task.startDate, date)
            XCTAssertTrue(task.needsSync)
            XCTAssertEqual(update.status, "pending")
            XCTAssertNil(update.serverConfirmedAt)
        }
    }

    func testExplicitRestoreThenScheduleRetainsBothIntents() async throws {
        let (controller, context, task) = try fixture()
        let project = Project(id: task.projectId, title: "Restore fixture", status: .inProgress)
        project.companyId = companyID
        context.insert(project)
        task.project = project
        task.deletedAt = date.addingTimeInterval(-86_400)
        try context.save()
        let plan = TrashRecoveryPolicy.plan(for: task, projects: [project])
        _ = try await controller.restoreTrash(plan)
        try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let restore = try XCTUnwrap(operations.first(where: TaskLifecycleSync.isRestore))
        let schedule = try XCTUnwrap(operations.first(where: TaskLifecycleSync.carriesSchedule))
        XCTAssertNil(task.deletedAt)
        XCTAssertEqual(task.startDate, date)
        XCTAssertTrue(SyncCrossEntityDependency.isHeld(schedule, in: operations))
        restore.status = "completed"
        XCTAssertFalse(SyncCrossEntityDependency.isHeld(schedule, in: operations))
    }

    func testUnreadableServerRowNeverCompletesOrDeletesLocalWork() throws {
        let (_, context, task) = try fixture()
        task.startDate = date
        task.needsSync = true
        let update = operation(fields: ["start_date": "2026-09-10T07:00:00Z"])
        update.status = "parked"
        update.lastError = "task_not_found"
        context.insert(update)
        try context.save()
        let payload = update.payload
        XCTAssertFalse(try SyncOperationReconcilers.reconcileTaskUpdate(update, server: nil,
            companyId: companyID, in: context))
        XCTAssertEqual(update.status, "parked")
        XCTAssertNil(update.completedAt)
        XCTAssertEqual(update.payload, payload)
        XCTAssertEqual(task.startDate, date)
        XCTAssertNil(task.deletedAt)
        XCTAssertTrue(task.needsSync)
    }

    func testPendingRestoreAndForeignTombstoneAreNeverApplied() throws {
        let (_, context, task) = try fixture()
        let update = operation(fields: ["status": "completed"])
        update.status = "parked"
        let restore = operation(fields: ["deleted_at": NSNull()])
        context.insert(update)
        context.insert(restore)
        try context.save()
        let row = SyncOperationReconcilers.ServerTaskRow(id: taskID, company_id: companyID,
            deleted_at: "2026-08-13T21:54:33Z")
        XCTAssertFalse(try SyncOperationReconcilers.reconcileTaskUpdate(update, server: row, companyId: companyID, in: context))
        XCTAssertNil(task.deletedAt)
        restore.status = "completed"
        let foreign = SyncOperationReconcilers.ServerTaskRow(id: taskID, company_id: "other-company", deleted_at: row.deleted_at)
        XCTAssertFalse(try SyncOperationReconcilers.reconcileTaskUpdate(update, server: foreign, companyId: companyID, in: context))
        XCTAssertNil(task.deletedAt)
        XCTAssertEqual(update.status, "parked")
    }

    func testConfirmedScheduleClearsDirtyFlagOnlyAfterLastPendingEdit() throws {
        let (_, context, task) = try fixture()
        task.needsSync = true
        let first = operation(fields: ["start_date": "2026-09-10T07:00:00Z"])
        first.status = "completed"
        let later = operation(fields: ["start_date": "2026-09-11T07:00:00Z"])
        context.insert(first)
        context.insert(later)
        try context.save()
        try TaskLifecycleSync.clearNeedsSyncAfterConfirmation(first, companyId: companyID, in: context)
        XCTAssertTrue(task.needsSync)
        later.status = "completed"
        try TaskLifecycleSync.clearNeedsSyncAfterConfirmation(later, companyId: companyID, in: context)
        XCTAssertFalse(task.needsSync)
    }

    func testClearingFinalTaskClearsLocalTaskAndParentCacheWithOneDurableOperation() async throws {
        let (controller, context, task) = try fixture()
        let project = attachProject(to: task, in: context)
        task.startDate = date
        task.endDate = date
        project.startDate = date
        project.endDate = date
        try context.save()
        try await controller.updateTaskFields(taskId: task.id,
            fields: ["start_date": .null, "end_date": .null, "duration": .integer(0)])
        XCTAssertNil(task.startDate)
        XCTAssertNil(task.endDate)
        XCTAssertEqual(task.duration, 0)
        XCTAssertTrue(task.needsSync)
        XCTAssertNil(project.startDate)
        XCTAssertNil(project.endDate)
        XCTAssertFalse(project.needsSync, "Derived display cache must not require a project-edit grant")
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        let operation = try XCTUnwrap(operations.first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: operation.payload) as? [String: Any])
        XCTAssertTrue(payload["start_date"] is NSNull)
        XCTAssertTrue(payload["end_date"] is NSNull)
        XCTAssertEqual(operation.status, "pending")
        XCTAssertNil(operation.serverConfirmedAt)
    }

    func testFailedClearRestoresTaskAndParentCache() async throws {
        let (controller, context, task) = try fixture()
        let project = attachProject(to: task, in: context)
        task.startDate = date
        task.endDate = date
        project.startDate = date
        project.endDate = date
        try context.save()
        do {
            try await controller.updateTaskFields(taskId: task.id,
                fields: ["start_date": .null, "end_date": .null, "duration": .integer(0)],
                stagingOperationsWith: { _, _ in throw CocoaError(.fileWriteUnknown) })
            XCTFail("Clear must roll back when its durable operation cannot be staged")
        } catch {
            XCTAssertEqual(error as? DataController.DurableSyncMutationError, .syncQueueFailed)
        }
        // Re-materialize both models after SwiftData rolls back the transaction.
        _ = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(task.startDate, date)
        XCTAssertEqual(task.endDate, date)
        XCTAssertEqual(project.startDate, date)
        XCTAssertEqual(project.endDate, date)
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testScheduleMovesParentSpanAndExcludesDeletedDates() async throws {
        let (controller, context, task) = try fixture()
        let project = attachProject(to: task, in: context)
        let deleted = ProjectTask(id: "deleted", projectId: project.id, taskTypeId: "tt", companyId: companyID)
        context.insert(deleted)
        deleted.deletedAt = date
        deleted.startDate = date.addingTimeInterval(-86_400)
        deleted.endDate = date.addingTimeInterval(86_400 * 7)
        project.tasks = [task, deleted]
        try context.save()
        XCTAssertNil(project.computedStartDate)
        XCTAssertNil(project.computedEndDate)
        try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
        XCTAssertEqual(project.startDate, date)
        XCTAssertEqual(project.endDate, date)
        let later = date.addingTimeInterval(86_400)
        try await controller.updateTaskSchedule(task: task, startDate: later, endDate: later)
        XCTAssertEqual(project.startDate, later)
        XCTAssertEqual(project.endDate, later)
    }

    func testParentDeletionAndStaleTypeChangeRejectWithoutMutation() async throws {
        let (controller, context, task) = try fixture()
        let project = attachProject(to: task, in: context)
        project.deletedAt = date
        try context.save()
        do {
            try await controller.updateTaskFields(taskId: task.id,
                fields: ["task_type_id": .string("other-type"), "task_color": .string("#000000")])
            XCTFail("A retained edit may not mutate a deleted project's task")
        } catch {
            XCTAssertEqual(error as? DataController.DurableSyncMutationError, .taskUnavailable)
        }
        XCTAssertEqual(task.taskTypeId, "tt")
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testUnresolvedLocalCreateCannotBeSettledByATombstone() throws {
        let (_, context, task) = try fixture()
        let create = operation(fields: ["id": task.id])
        create.operationType = "create"
        let update = operation(fields: ["task_notes": "Local notes"])
        update.status = "parked"
        context.insert(create)
        context.insert(update)
        try context.save()
        let row = SyncOperationReconcilers.ServerTaskRow(id: taskID, company_id: companyID,
            deleted_at: "2026-08-13T21:54:33Z")
        XCTAssertFalse(try SyncOperationReconcilers.reconcileTaskUpdate(update, server: row,
            companyId: companyID, in: context))
        XCTAssertNil(task.deletedAt)
        XCTAssertEqual(update.status, "parked")
    }

    func testConfirmationDoesNotClearAnotherCompanysDirtyTask() throws {
        let (_, context, task) = try fixture()
        task.needsSync = true
        let foreign = ProjectTask(id: task.id.uppercased(), projectId: "foreign", taskTypeId: "tt", companyId: "foreign")
        foreign.needsSync = true
        context.insert(foreign)
        let confirmed = operation(fields: ["task_notes": "Saved"])
        confirmed.status = "completed"
        context.insert(confirmed)
        try context.save()
        try TaskLifecycleSync.clearNeedsSyncAfterConfirmation(confirmed, companyId: companyID, in: context)
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(foreign.needsSync)
    }

    func testStaleProjectRefreshCannotResurrectAClearedTaskSchedule() async throws {
        let (controller, context, task) = try fixture()
        let project = attachProject(to: task, in: context)
        task.startDate = date
        task.endDate = date
        project.startDate = date
        project.endDate = date
        try context.save()
        try await controller.updateTaskFields(taskId: task.id,
            fields: ["start_date": .null, "end_date": .null, "duration": .integer(0)])
        let wire: [String: Any] = ["id": project.id, "company_id": companyID,
            "title": project.title, "status": "in_progress", "created_at": "2026-08-01T00:00:00Z",
            "start_date": "2026-09-10T07:00:00Z", "end_date": "2026-09-10T07:00:00Z"]
        let dto = try JSONDecoder().decode(SupabaseProjectDTO.self,
            from: JSONSerialization.data(withJSONObject: wire))
        let refreshed = try ProjectCacheMerge.apply(dto: dto, context: context)
        XCTAssertNotNil(refreshed.startDate, "The stale server cache was actually replayed")
        XCTAssertNil(refreshed.computedStartDate)
        XCTAssertNil(refreshed.computedEndDate)
        XCTAssertEqual(JobBoardProjectCardModel.make(project: refreshed, currentUserId: nil,
            hasFullProjectView: true).dateText, "—")
        XCTAssertTrue(task.needsSync)
    }

    private func attachProject(to task: ProjectTask, in context: ModelContext) -> Project {
        let project = Project(id: task.projectId, title: "Schedule fixture", status: .inProgress)
        project.companyId = companyID
        context.insert(project)
        task.project = project
        project.tasks = [task]
        return project
    }

    private func operation(fields: [String: Any]) -> SyncOperation {
        SyncOperation(entityType: "projectTask", entityId: taskID,
            operationType: "update", payload: try! JSONSerialization.data(withJSONObject: fields),
            changedFields: Array(fields.keys))
    }

    private func fixture() throws -> (DataController, ModelContext, ProjectTask) {
        let schema = Schema([Project.self, ProjectTask.self, TaskType.self, TaskTypeReminder.self,
            TaskReminder.self, User.self, Client.self, SubClient.self, ProjectPhoto.self,
            SyncOperation.self, ProjectVinylOrderMarker.self, ProjectPrimaryContactSelection.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        let context = container.mainContext
        let controller = DataController()
        controllers.append(controller)
        controller.setModelContext(context)
        controller.syncEngine.configure(modelContext: context, connectivity: offline)
        let task = ProjectTask(id: taskID, projectId: "33333333-3333-4333-8333-333333333333", taskTypeId: "tt", companyId: companyID)
        context.insert(task)
        try context.save()
        return (controller, context, task)
    }
}
