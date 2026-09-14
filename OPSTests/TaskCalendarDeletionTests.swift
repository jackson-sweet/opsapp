import SwiftData
import XCTest
@testable import OPS

@MainActor
final class TaskCalendarDeletionTests: XCTestCase {
    private final class OfflineConnectivity: ConnectivityManager {
        override var shouldAttemptSync: Bool { false }
    }
    private final class FixtureDataController: DataController {
        // Startup callbacks can outlive a single XCTest. The fixture owns its
        // store through those callbacks, and never replaces its offline sync
        // configuration with the app's live connectivity during bootstrap.
        let retainedContainer: ModelContainer
        init(container: ModelContainer) {
            retainedContainer = container
            super.init()
        }
        override func initializeSyncManager() {}
    }
    private final class OfflineNotifications: TaskLifecycleNotifying {
        func notifyTaskCompleted(taskId: String) async throws -> [String] { [] }
        func notifyProjectCompleted(projectId: String) async throws -> [String] { [] }
        func notifyTaskRescheduled(taskId: String) async throws -> [String] { [] }
        func notifyDependencyReady(completedTaskId: String) async throws -> [NotificationRepository.DependencyReadyEntry] { [] }
        func notifyTaskAssigned(taskId: String, userIds: [String]?) async throws -> [String] { [] }
        func notifyTaskPairSpawned(taskId: String) async throws -> [String] { [] }
        func notifyScheduleRunSummary(taskIds: [String]) async throws -> [NotificationRepository.ScheduleRunSummaryEntry] { [] }
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

    func testSchedulingArchivedProjectReopensBeforeItsTaskCanSync() async throws {
        let (controller, context, task) = try fixture()
        let permissions = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = permissions }
        PermissionStore.shared.permissions = ["projects.edit": "all", "calendar.edit": "all"]
        controller.currentUser = User(id: "44444444-4444-4444-8444-444444444444",
            firstName: "Test", lastName: "Operator", role: .admin, companyId: companyID)
        let json = """
        {"id":"33333333-3333-4333-8333-333333333333","company_id":"11111111-1111-4111-8111-111111111111",
         "title":"Archived scheduling fixture","status":"archived","updated_at":"2026-09-12T10:11:12.123456Z"}
        """
        let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: Data(json.utf8))
        let project = dto.toModel()
        context.insert(project)
        task.project = project
        try context.save()
        let future = Date().addingTimeInterval(7 * 86_400)
        try await controller.updateTaskSchedule(task: task, startDate: future, endDate: future)
        XCTAssertEqual(project.status, .accepted)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let reopen = try XCTUnwrap(operations.first { $0.operationType == "reopenForTask" })
        let scheduled = try XCTUnwrap(operations.first { $0.entityType == "projectTask" && $0.getChangedFields().contains("start_date") })
        XCTAssertEqual(scheduled.dependsOnId?.lowercased(), reopen.id.uuidString.lowercased())
        XCTAssertNil(reopen.serverConfirmedAt)
        XCTAssertEqual(reopen.status, "pending")
    }

    func testPastScheduleReopensAsInProgressWithExactRevision() async throws {
        let (controller, context, task, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        let past = Date().addingTimeInterval(-86_400)
        try await controller.updateTaskFields(taskId: task.id,
            fields: ["start_date": .string(SupabaseDate.format(past)), "end_date": .string(SupabaseDate.format(past))])
        XCTAssertEqual(project.status, .inProgress)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let reopen = try XCTUnwrap(operations.first(where: ProjectReopenSync.isReopen))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: reopen.payload) as? [String: String])
        XCTAssertEqual(payload["_expected_updated_at"], "2026-09-12T10:11:12.123456Z")
        XCTAssertEqual(payload["_reopen_command_id"], reopen.id.uuidString)
        _ = try ProjectTaskReopenCommand(projectId: project.id, companyId: companyID,
            fields: AnyJSONBridge.payload(payload))
        let reread = ModelContext(try XCTUnwrap(containers.last))
        let persisted = try reread.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(persisted.first(where: ProjectReopenSync.isReopen)?.payload, reopen.payload)
        XCTAssertEqual(persisted.first(where: { $0.entityType == "projectTask" })?.dependsOnId, reopen.id.uuidString)
    }

    func testArchivedScheduleRequiresProjectEditScopeBeforeAnyMutation() async throws {
        let (controller, context, task, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["calendar.edit": "all"]
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
            XCTFail("Scheduling an archive must not widen calendar permissions into project-edit access")
        } catch { XCTAssertEqual(error as? DataController.DurableSyncMutationError, .archivedProjectPermission) }
        XCTAssertEqual(project.status, .archived)
        XCTAssertNil(task.startDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testArchivedScheduleRequiresServerRevisionWithoutGuessingFromDate() async throws {
        let (controller, context, task, project) = try archivedFixture(cacheRevision: false)
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        project.updatedAt = date
        try context.save()
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
            XCTFail("A rounded model Date cannot authorize a compare-and-swap")
        } catch { XCTAssertEqual(error as? DataController.DurableSyncMutationError, .archivedProjectRefreshRequired) }
        XCTAssertEqual(project.status, .archived)
        XCTAssertNil(task.startDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testIncompleteReopenLedgerRollsBackBothProjectAndTask() async throws {
        let (controller, context, task, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        do {
            try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date,
                stagingOperationsWith: { specs, context in
                    try controller.syncEngine.stageOperationsForTransaction(Array(specs.prefix(1)), in: context)
                })
            XCTFail("A reopen with no dependent schedule must roll back")
        } catch { XCTAssertEqual(error as? DataController.DurableSyncMutationError, .syncQueueFailed) }
        XCTAssertEqual(project.status, .archived)
        XCTAssertFalse(project.needsSync)
        XCTAssertNil(task.startDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func testMetadataNoOpAndTerminalDatesDoNotReopenArchive() async throws {
        let (controller, context, task, project) = try archivedFixture()
        try await controller.updateTaskFields(taskId: task.id, fields: ["task_notes": .string("Crew note")])
        task.startDate = date
        task.endDate = date
        try context.save()
        try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
        task.status = .completed
        try context.save()
        try await controller.updateTaskSchedule(task: task, startDate: date.addingTimeInterval(86_400), endDate: date.addingTimeInterval(86_400))
        try await controller.updateTaskFields(taskId: task.id, fields: ["start_date": .null, "end_date": .null])
        XCTAssertEqual(project.status, .archived)
        XCTAssertFalse(try context.fetch(FetchDescriptor<SyncOperation>()).contains(where: ProjectReopenSync.isReopen))
    }

    func testScheduledCreationAndLaterEditWaitForSameReopen() async throws {
        let (controller, context, task, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        task.startDate = Date().addingTimeInterval(7 * 86_400)
        task.endDate = task.startDate
        try context.save()
        try await controller.createTask(task: task)
        try await controller.updateTaskFields(taskId: task.id, fields: ["task_notes": .string("Keep this edit")])
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let commands = operations.filter(ProjectReopenSync.isReopen)
        XCTAssertEqual(commands.count, 1)
        let command = try XCTUnwrap(commands.first)
        for operation in operations where operation.entityType == "projectTask" {
            XCTAssertEqual(operation.dependsOnId, command.id.uuidString)
        }
        XCTAssertEqual(project.status, .accepted)
    }

    func testBatchReopensProjectOnceUsingEarliestActivePlacement() async throws {
        let (controller, context, task, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        let second = ProjectTask(id: UUID().uuidString.lowercased(), projectId: project.id, taskTypeId: "tt", companyId: companyID)
        context.insert(second)
        second.project = project
        project.tasks = [task, second]
        try context.save()
        let future = Date().addingTimeInterval(7 * 86_400)
        let past = Date().addingTimeInterval(-86_400)
        let plan = SchedulePlan(placements: [
            TaskPlacement(id: task.id, taskTypeId: "tt", startDate: future, endDate: future, startTime: nil, endTime: nil, alternative: nil),
            TaskPlacement(id: second.id, taskTypeId: "tt", startDate: past, endDate: past, startTime: nil, endTime: nil, alternative: nil)
        ], conflicts: [], metadata: .empty)
        let committed = await controller.applySchedulePlan(plan)
        XCTAssertEqual(committed, 2)
        XCTAssertEqual(project.status, .inProgress)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let commands = operations.filter(ProjectReopenSync.isReopen)
        XCTAssertEqual(commands.count, 1)
        let command = try XCTUnwrap(commands.first)
        let schedules = operations.filter { $0.entityType == "projectTask" && $0.getChangedFields().contains("start_date") }
        XCTAssertEqual(schedules.count, 2)
        XCTAssertTrue(schedules.allSatisfy { $0.dependsOnId == command.id.uuidString })
    }

    func testDTOCreationUsesQueuedScheduleAndStatusOverStaleLocalFields() async throws {
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        for serverShouldSchedule in [false, true] {
            let (controller, context, task, project) = try archivedFixture()
            task.startDate = serverShouldSchedule ? nil : Date().addingTimeInterval(7 * 86_400)
            task.endDate = task.startDate
            task.status = serverShouldSchedule ? .completed : .active
            try context.save()
            var object: [String: Any] = ["id": task.id, "company_id": companyID, "project_id": project.id,
                "status": serverShouldSchedule ? "active" : "completed"]
            if serverShouldSchedule {
                object["start_date"] = SupabaseDate.format(Date().addingTimeInterval(7 * 86_400))
                object["end_date"] = object["start_date"]
            }
            let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: JSONSerialization.data(withJSONObject: object))
            _ = try await controller.createTask(dto: dto)
            XCTAssertEqual(project.status, serverShouldSchedule ? .accepted : .archived)
            XCTAssertEqual(task.startDate != nil, serverShouldSchedule)
            XCTAssertEqual(task.status, serverShouldSchedule ? .active : .completed)
        }
    }

    func testReopenRemainsImmutableAndCannotBeDiscardedAheadOfItsTask() async throws {
        let (controller, context, task, _) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = ["projects.edit": "all"]
        try await controller.updateTaskSchedule(task: task, startDate: date, endDate: date)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let reopen = try XCTUnwrap(operations.first(where: ProjectReopenSync.isReopen))
        let payload = reopen.payload
        let child = try XCTUnwrap(operations.first(where: { $0.dependsOnId == reopen.id.uuidString }))
        reopen.status = "failed"
        reopen.lastAttemptedAt = Date()
        try context.save()
        XCTAssertTrue(controller.syncEngine.supersedeProjectStatus(entityID: reopen.entityId, with: "archived"))
        XCTAssertEqual(reopen.payload, payload)
        controller.syncEngine.cancelOperation(reopen)
        let reread = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(reread.contains { $0.id == reopen.id })
        XCTAssertEqual(child.dependsOnId, reopen.id.uuidString)
        XCTAssertEqual(reopen.payload, payload)
    }

    func testDeniedDetachedTaskCreationLeavesNoOrphan() async throws {
        let (controller, context, existing, project) = try archivedFixture()
        let saved = PermissionStore.shared.permissions
        defer { PermissionStore.shared.permissions = saved }
        PermissionStore.shared.permissions = [:]
        let task = ProjectTask(id: UUID().uuidString.lowercased(), projectId: project.id, taskTypeId: "tt", companyId: companyID)
        task.startDate = Date().addingTimeInterval(7 * 86_400)
        task.endDate = task.startDate
        do { try await controller.createTask(task: task); XCTFail("Project authorization must precede insertion") }
        catch { XCTAssertEqual(error as? DataController.DurableSyncMutationError, .archivedProjectPermission) }
        XCTAssertNil(task.modelContext)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProjectTask>()).map(\.id), [existing.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
        XCTAssertEqual(project.status, .archived)
    }

    private func archivedFixture(cacheRevision: Bool = true) throws -> (DataController, ModelContext, ProjectTask, Project) {
        let (controller, context, task) = try fixture()
        let projectId = UUID().uuidString.lowercased()
        var object: [String: Any] = ["id": projectId, "company_id": companyID, "title": "Archived fixture", "status": "archived"]
        if cacheRevision { object["updated_at"] = "2026-09-12T10:11:12.123456Z" }
        let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: JSONSerialization.data(withJSONObject: object))
        let project = dto.toModel()
        context.insert(project)
        task.projectId = projectId
        task.project = project
        project.tasks = [task]
        controller.currentUser = User(id: "44444444-4444-4444-8444-444444444444", firstName: "Test", lastName: "Operator", role: .admin, companyId: companyID)
        try context.save()
        return (controller, context, task, project)
    }

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
        let controller = FixtureDataController(container: container)
        controllers.append(controller)
        controller.setModelContext(context)
        controller.taskLifecycleSyncer = OfflineNotifications()
        controller.syncEngine.configure(modelContext: context, connectivity: offline)
        let task = ProjectTask(id: taskID, projectId: "33333333-3333-4333-8333-333333333333", taskTypeId: "tt", companyId: companyID)
        context.insert(task)
        try context.save()
        return (controller, context, task)
    }
}
