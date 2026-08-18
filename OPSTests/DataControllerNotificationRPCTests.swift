//
//  DataControllerNotificationRPCTests.swift
//  OPSTests
//
//  The seven task/project lifecycle rails DataController owns — task
//  completion, project completion, reschedule, dependency-ready, task
//  assignment, paired-task spawn, and the bulk auto-schedule summary — must
//  cross narrow server RPCs, never a client-side `notifications` insert. The
//  2026-07-15 notification-creation hardening revoked app-role INSERT, so every
//  one of these loops has 42501'd since: the crew stopped being told a task was
//  done, a job was finished, dates moved, their blocker cleared, they were put
//  on a task, a pair task appeared, or a schedule run touched their week — while
//  the push kept firing, so rail and push disagreed on every surface.
//
//  Only the dispatch step is exercised here. The mutation paths that own these
//  rails (`updateTaskStatus`, `updateProjectStatus`, `updateTaskSchedule`,
//  `updateTaskTeamMembers`, `spawnPairsForPredecessor`, `applySchedulePlan`)
//  write to SwiftData and enqueue sync work first; the extracted dispatch
//  methods are the honest seam — everything the client still decides about the
//  rail row and its push (TimeOffDecisionNotificationTests doctrine).
//
//  What these tests pin:
//    1. Ordering. The server derives recipients and copy from ROWS, so the
//       recorded state must be on the server before the RPC runs. Every
//       dispatch flushes pending sync work first — the flush and the RPC land
//       in one recorded call log, so the order is asserted, not assumed.
//    2. Verbatim ids. Each surface hands the server exactly the id(s) the
//       mutation touched. A mangled or substituted id silently notifies nobody.
//    3. The server owns recipient derivation. An empty local crew, an absent
//       local project row, or a locally-computed member/count map may no longer
//       gate or shape the call — only a genuinely empty unit of work does
//       (no added assignees, no spawned pairs).
//    4. Push targets rail truth. Each dispatch returns exactly the ids (or
//       resolved targets) it fed to the push lane: the ids the SERVER reported
//       NEW rail rows for. An empty server result means no push at all, so rail
//       and push can no longer disagree.
//    5. Transport failures stay contained. The mutation is already persisted by
//       the time a dispatch runs; a failed rail row must never surface to the
//       caller, and must not poison later dispatches.
//
//  OneSignal is a singleton with no injection seam, so the push is not asserted
//  through it — the branch is structural (guarded on a non-empty server list),
//  and the returned target list is what the loop actually pushed. Where a test
//  drives the non-empty branch, the scripted id is the stubbed `currentUserId`,
//  which every OneSignal lane used here self-filters away before any network
//  work (ImageSyncCrewNotificationTests pattern) — the suite stays hermetic.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataControllerNotificationRPCTests: XCTestCase {

    // MARK: - Spy

    /// Records every lifecycle RPC and the pending-work flush that must precede
    /// it, in one ordered log, and plays back scripted server results. The
    /// dispatch methods call sequentially, so plain storage is race-free.
    private final class LifecycleSpy: TaskLifecycleNotifying {
        enum Call: Equatable {
            case flush
            case taskCompleted(taskId: String)
            case projectCompleted(projectId: String)
            case taskRescheduled(taskId: String)
            case dependencyReady(completedTaskId: String)
            case taskAssigned(taskId: String, userIds: [String]?)
            case taskPairSpawned(taskId: String)
            case scheduleRunSummary(taskIds: [String])
        }

        private(set) var calls: [Call] = []

        /// Ids the server reports as having received NEW rail rows.
        var created: [String] = []
        var dependencyEntries: [NotificationRepository.DependencyReadyEntry] = []
        var scheduleEntries: [NotificationRepository.ScheduleRunSummaryEntry] = []
        var failure: Error?

        /// Stands in for `syncEngine.pushPending()` — the step that puts the
        /// mutation's rows on the server before the RPC reads them.
        func recordFlush() {
            calls.append(.flush)
        }

        func notifyTaskCompleted(taskId: String) async throws -> [String] {
            calls.append(.taskCompleted(taskId: taskId))
            if let failure { throw failure }
            return created
        }

        func notifyProjectCompleted(projectId: String) async throws -> [String] {
            calls.append(.projectCompleted(projectId: projectId))
            if let failure { throw failure }
            return created
        }

        func notifyTaskRescheduled(taskId: String) async throws -> [String] {
            calls.append(.taskRescheduled(taskId: taskId))
            if let failure { throw failure }
            return created
        }

        func notifyDependencyReady(
            completedTaskId: String
        ) async throws -> [NotificationRepository.DependencyReadyEntry] {
            calls.append(.dependencyReady(completedTaskId: completedTaskId))
            if let failure { throw failure }
            return dependencyEntries
        }

        func notifyTaskAssigned(taskId: String, userIds: [String]?) async throws -> [String] {
            calls.append(.taskAssigned(taskId: taskId, userIds: userIds))
            if let failure { throw failure }
            return created
        }

        func notifyTaskPairSpawned(taskId: String) async throws -> [String] {
            calls.append(.taskPairSpawned(taskId: taskId))
            if let failure { throw failure }
            return created
        }

        func notifyScheduleRunSummary(
            taskIds: [String]
        ) async throws -> [NotificationRepository.ScheduleRunSummaryEntry] {
            calls.append(.scheduleRunSummary(taskIds: taskIds))
            if let failure { throw failure }
            return scheduleEntries
        }
    }

    // MARK: - Fixture state

    /// Every OneSignal lane these dispatches drive drops recipients equal to
    /// the stored `currentUserId`; stubbing it keeps the push path inert.
    private let operatorID = "operator-self"
    private var savedCurrentUserId: String?

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        savedCurrentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        UserDefaults.standard.set(operatorID, forKey: "currentUserId")
    }

    override func tearDown() {
        if let savedCurrentUserId {
            UserDefaults.standard.set(savedCurrentUserId, forKey: "currentUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - 1. Task completion (notify_task_completed)

    func test_taskCompletionFlushesPendingWorkThenForwardsTheTaskId() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]
        let taskId = "8c31889e-4f2a-4b71-9d33-0a17c5be6d42"

        let pushed = await fixture.controller.dispatchTaskCompletionNotification(
            taskId: taskId,
            push: .init(
                taskName: "Framing",
                projectName: "South deck rebuild",
                projectId: "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3",
                completedByName: "Marcus Hale"
            )
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskCompleted(taskId: taskId)],
            "The completion must be on the server before the RPC reads it — the server refuses a task that isn't recorded completed, so an unflushed queue means nobody is told"
        )
        XCTAssertEqual(
            pushed,
            [operatorID],
            "The push targets exactly the ids the server reported NEW rail rows for — never a locally-assembled crew list"
        )
    }

    func test_taskCompletionStillCallsTheServerWithNoLocalProjectRow() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]

        let pushed = await fixture.controller.dispatchTaskCompletionNotification(
            taskId: "task-no-local-project",
            push: nil
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskCompleted(taskId: "task-no-local-project")],
            "The crew lives in the server's copy of the project — a missing local project row must not silence the rail"
        )
        XCTAssertTrue(
            pushed.isEmpty,
            "No local copy to dress a push with -> rail only. The rail is the server's; the push copy is the client's"
        )
    }

    func test_taskCompletionSkipsThePushWhenTheServerCreatedNothing() async throws {
        let fixture = try makeFixture()
        // No new rail rows: nobody but the actor on the crew, or a repeat inside
        // the server's dedupe window.
        fixture.spy.created = []

        let pushed = await fixture.controller.dispatchTaskCompletionNotification(
            taskId: "task-dedupe",
            push: .init(
                taskName: "Framing",
                projectName: "South deck rebuild",
                projectId: "p-1",
                completedByName: "Marcus Hale"
            )
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskCompleted(taskId: "task-dedupe")],
            "The server is still asked — it is the only thing that knows whether a row is new"
        )
        XCTAssertTrue(pushed.isEmpty, "No new rail rows -> no push. Rail and push can never disagree")
    }

    // MARK: - 2. Project completion (notify_project_completed)

    func test_projectCompletionFlushesPendingWorkThenForwardsTheProjectId() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]
        let projectId = "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58"

        let pushed = await fixture.controller.dispatchProjectCompletionNotification(
            projectId: projectId,
            projectName: "South deck rebuild"
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .projectCompleted(projectId: projectId)],
            "The status write must land before the RPC — the server refuses a project that isn't recorded completed"
        )
        XCTAssertEqual(pushed, [operatorID], "Push targets the server's created list, not the local crew")
    }

    func test_projectCompletionSkipsThePushWhenTheServerCreatedNothing() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = []

        let pushed = await fixture.controller.dispatchProjectCompletionNotification(
            projectId: "p-dedupe",
            projectName: "South deck rebuild"
        )

        XCTAssertEqual(fixture.spy.calls, [.flush, .projectCompleted(projectId: "p-dedupe")])
        XCTAssertTrue(pushed.isEmpty, "No new rail rows -> no push")
    }

    // MARK: - 3. Reschedule (notify_task_rescheduled)

    func test_rescheduleFlushesPendingWorkThenForwardsTheTaskId() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]
        let taskId = "a417a994-2b5e-4d90-8f61-77c0d3ea1b45"

        let pushed = await fixture.controller.dispatchTaskRescheduleNotification(
            taskId: taskId,
            push: .init(taskName: "Framing", projectName: "South deck rebuild", projectId: "p-1")
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskRescheduled(taskId: taskId)],
            "The new dates must be on the server before the RPC renders the copy from them"
        )
        XCTAssertEqual(pushed, [operatorID], "Push targets the server's created list")
    }

    func test_rescheduleStillCallsTheServerWithNoLocalProjectRow() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]

        let pushed = await fixture.controller.dispatchTaskRescheduleNotification(
            taskId: "task-orphan",
            push: nil
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskRescheduled(taskId: "task-orphan")],
            "The task's own crew is derived server-side — a missing local project row must not silence the rail"
        )
        XCTAssertTrue(pushed.isEmpty, "No local copy -> rail only")
    }

    // MARK: - 4. Dependency ready (notify_dependency_ready)

    func test_dependencyReadyMakesOneServerCallAfterFlushingAndNeverPreFilters() async throws {
        let fixture = try makeFixture()
        // Three dependents exist locally, none of them scanned client-side: the
        // server resolves the dependent set from the effective dependency rules.
        seedDependents(in: fixture.context)
        fixture.spy.dependencyEntries = []

        let targets = await fixture.controller.dispatchDependencyReadyNotifications(
            completedTaskId: "completed-task-1",
            completedTaskTitle: "Framing"
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .dependencyReady(completedTaskId: "completed-task-1")],
            "One call for the whole fan-out, after the completion lands — the dependent scan is the server's job now"
        )
        XCTAssertTrue(targets.isEmpty, "Nothing unblocked -> nothing pushed")
    }

    func test_dependencyPushTargetsAreExactlyTheReturnedEntriesResolvedLocally() async throws {
        let fixture = try makeFixture()
        seedDependents(in: fixture.context)
        fixture.spy.dependencyEntries = [
            // Unblocked, with a crew: pushed, titled from the local rows.
            .init(taskId: "dependent-1", userIds: [operatorID]),
            // Unblocked server-side but absent locally: no title to push with.
            .init(taskId: "dependent-unknown", userIds: [operatorID]),
            // Present locally but nobody received a NEW row: nothing to push.
            .init(taskId: "dependent-2", userIds: []),
        ]

        let targets = await fixture.controller.dispatchDependencyReadyNotifications(
            completedTaskId: "completed-task-1",
            completedTaskTitle: "Framing"
        )

        XCTAssertEqual(
            targets,
            [
                DataController.DependencyPushTarget(
                    dependentTaskId: "dependent-1",
                    dependentTaskTitle: "Decking",
                    projectTitle: "South deck rebuild",
                    projectId: "project-dep",
                    recipientUserIds: [operatorID]
                )
            ],
            "One push per task the server actually created rows for, aimed at that entry's ids, titled from the local row — an unresolvable task and an empty crew both drop out"
        )
    }

    // MARK: - 5. Task assignment (notify_task_assigned)

    func test_taskAssignmentForwardsOnlyTheAddedIdsAfterFlushing() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]
        let added = ["crew-added-a", "crew-added-b"]

        let pushed = await fixture.controller.dispatchTaskAssignmentNotifications(
            taskId: "task-assign-1",
            addedMemberIds: added,
            push: .init(taskName: "Framing", projectName: "South deck rebuild", projectId: "p-1")
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskAssigned(taskId: "task-assign-1", userIds: added)],
            "Only the newly added ids cross — the server intersects them with the task row's recorded crew, so the whole roster must never be sent and the members already on the task must not be re-announced"
        )
        XCTAssertEqual(
            pushed,
            [operatorID],
            "Push targets the server's created list, not the added list — a member the server refused (not on the row, inactive, already notified) must not get a push"
        )
    }

    func test_taskAssignmentWithNothingAddedDoesNoWorkAtAll() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]

        let pushed = await fixture.controller.dispatchTaskAssignmentNotifications(
            taskId: "task-assign-noop",
            addedMemberIds: [],
            push: .init(taskName: "Framing", projectName: "South deck rebuild", projectId: "p-1")
        )

        XCTAssertTrue(
            fixture.spy.calls.isEmpty,
            "Nobody was added: no flush, no server call. A crew edit that only REMOVED members announces nothing"
        )
        XCTAssertTrue(pushed.isEmpty, "Nothing added -> nothing pushed")
    }

    func test_taskAssignmentSkipsThePushWhenTheServerCreatedNothing() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = []

        let pushed = await fixture.controller.dispatchTaskAssignmentNotifications(
            taskId: "task-assign-2",
            addedMemberIds: ["crew-added-a"],
            push: .init(taskName: "Framing", projectName: "South deck rebuild", projectId: "p-1")
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskAssigned(taskId: "task-assign-2", userIds: ["crew-added-a"])],
            "The server is still asked — only it knows whether that id is on the row"
        )
        XCTAssertTrue(pushed.isEmpty, "No new rail rows -> no push")
    }

    // MARK: - 6. Paired task spawned (notify_task_pair_spawned)

    func test_pairSpawnFlushesOnceThenAnnouncesEverySpawn() async throws {
        let fixture = try makeFixture()

        await fixture.controller.dispatchTaskPairSpawnedNotifications(
            taskIds: ["spawn-1", "spawn-2"]
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskPairSpawned(taskId: "spawn-1"), .taskPairSpawned(taskId: "spawn-2")],
            "The spawn CREATE ops must land before the RPC reads the new rows — one flush for the batch, then one call per spawned task"
        )
    }

    func test_pairSpawnWithNoSpawnsDoesNoWorkAtAll() async throws {
        let fixture = try makeFixture()

        await fixture.controller.dispatchTaskPairSpawnedNotifications(taskIds: [])

        XCTAssertTrue(
            fixture.spy.calls.isEmpty,
            "Nothing spawned: no flush, no server call"
        )
    }

    // MARK: - 7. Bulk auto-schedule summary (notify_schedule_run_summary)

    func test_scheduleRunForwardsTheMovedTaskIdsVerbatim() async throws {
        let fixture = try makeFixture()
        let movedTaskIds = ["moved-1", "moved-2", "moved-3"]
        fixture.spy.scheduleEntries = [.init(userId: operatorID, movedCount: 3)]

        let pushMap = await fixture.controller.sendScheduleRunSummaries(movedTaskIds: movedTaskIds)

        XCTAssertEqual(
            fixture.spy.calls,
            [.scheduleRunSummary(taskIds: movedTaskIds)],
            "One call carrying every moved id — the per-member counts are the server's to compute. `applySchedulePlan` performs the run's single coalesced push immediately before this, so the drain is not repeated here"
        )
        XCTAssertEqual(
            pushMap,
            [operatorID: 3],
            "The push map is the server's returned entries — the count each member's NEW summary row actually reports"
        )
    }

    func test_scheduleRunPushesNothingWhenTheServerCreatedNothing() async throws {
        let fixture = try makeFixture()
        // Many tasks moved locally, but the server created no summary rows —
        // e.g. only the operator's own tasks moved, or the identical run
        // repeated while the previous summary is still unread.
        fixture.spy.scheduleEntries = []

        let pushMap = await fixture.controller.sendScheduleRunSummaries(
            movedTaskIds: ["moved-1", "moved-2", "moved-3", "moved-4"]
        )

        XCTAssertEqual(fixture.spy.calls, [.scheduleRunSummary(taskIds: ["moved-1", "moved-2", "moved-3", "moved-4"])])
        XCTAssertTrue(
            pushMap.isEmpty,
            "The local member/move-count map no longer reaches the push lane at all — no server row, no push"
        )
    }

    func test_scheduleRunWithNoMovedTasksDoesNoWorkAtAll() async throws {
        let fixture = try makeFixture()

        let pushMap = await fixture.controller.sendScheduleRunSummaries(movedTaskIds: [])

        XCTAssertTrue(fixture.spy.calls.isEmpty, "A run that moved nothing announces nothing")
        XCTAssertTrue(pushMap.isEmpty)
    }

    // MARK: - 8. Transport failures stay contained

    func test_transportFailureIsSwallowedAndLaterDispatchesStillRun() async throws {
        let fixture = try makeFixture()
        fixture.spy.created = [operatorID]
        fixture.spy.failure = URLError(.notConnectedToInternet)

        // No `try` anywhere: the mutation is already persisted by the time these
        // run, so a failed rail row must never be throwable at the caller.
        let failedPush = await fixture.controller.dispatchTaskCompletionNotification(
            taskId: "task-offline",
            push: .init(
                taskName: "Framing",
                projectName: "South deck rebuild",
                projectId: "p-1",
                completedByName: "Marcus Hale"
            )
        )
        XCTAssertTrue(failedPush.isEmpty, "A failed rail row means no push — the two never diverge")

        fixture.spy.failure = nil
        let recoveredPush = await fixture.controller.dispatchProjectCompletionNotification(
            projectId: "project-recovered",
            projectName: "South deck rebuild"
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [
                .flush,
                .taskCompleted(taskId: "task-offline"),
                .flush,
                .projectCompleted(projectId: "project-recovered"),
            ],
            "The throw is swallowed at the seam: execution continues and the next mutation still dispatches"
        )
        XCTAssertEqual(recoveredPush, [operatorID])
    }

    func test_dependencyTransportFailurePushesNothingAndStaysContained() async throws {
        let fixture = try makeFixture()
        seedDependents(in: fixture.context)
        fixture.spy.dependencyEntries = [.init(taskId: "dependent-1", userIds: [operatorID])]
        fixture.spy.failure = URLError(.timedOut)

        let targets = await fixture.controller.dispatchDependencyReadyNotifications(
            completedTaskId: "completed-task-1",
            completedTaskTitle: "Framing"
        )

        XCTAssertTrue(targets.isEmpty, "No fan-out came back — the local rows must not be used to invent one")
        XCTAssertEqual(fixture.spy.calls, [.flush, .dependencyReady(completedTaskId: "completed-task-1")])
    }

    func test_pairSpawnTransportFailureStillAnnouncesTheRemainingSpawns() async throws {
        let fixture = try makeFixture()
        fixture.spy.failure = URLError(.notConnectedToInternet)

        await fixture.controller.dispatchTaskPairSpawnedNotifications(
            taskIds: ["spawn-1", "spawn-2"]
        )

        XCTAssertEqual(
            fixture.spy.calls,
            [.flush, .taskPairSpawned(taskId: "spawn-1"), .taskPairSpawned(taskId: "spawn-2")],
            "One spawn's rail failure must not abandon the rest of the batch"
        )
    }

    // MARK: - Fixture

    private struct Fixture {
        let controller: DataController
        let context: ModelContext
        let spy: LifecycleSpy
    }

    /// A controller wired to an in-memory store, with both seams the rails
    /// cross replaced: the RPC transport and the pending-work flush that must
    /// precede it. The real `syncEngine` is never touched.
    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        let controller = DataController()
        // The full wiring, not a bare `modelContext` assignment: it is what
        // gives the controller a real `syncEngine`, so no auth-driven code path
        // can reach an unconfigured one mid-test.
        controller.setModelContext(context)

        let spy = LifecycleSpy()
        controller.taskLifecycleSyncer = spy
        controller.notificationSyncFlush = { spy.recordFlush() }

        return Fixture(controller: controller, context: context, spy: spy)
    }

    /// Two dependents on one project. `dependent-1` carries the title and
    /// project the push copy must be dressed from; `dependent-2` proves an
    /// entry is dropped for an empty crew, not for being unresolvable.
    private func seedDependents(in context: ModelContext) {
        let project = Project(id: "project-dep", title: "South deck rebuild", status: .inProgress)
        project.companyId = "co-lifecycle"
        context.insert(project)

        for (id, title) in [("dependent-1", "Decking"), ("dependent-2", "Railing")] {
            let task = ProjectTask(
                id: id,
                projectId: project.id,
                taskTypeId: "task-type-1",
                companyId: "co-lifecycle",
                status: .active
            )
            task.customTitle = title
            task.project = project
            context.insert(task)
        }
        try? context.save()
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectPhoto.self,
            SyncOperation.self,
            Company.self,
            TeamMember.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)

        let context = ModelContext(container)
        // A `#Predicate` fetch of `SyncOperation` traps against a table that has
        // never held a row; anything the controller touches may reach one.
        let warmUp = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: "warm-up-never-read",
            operationType: "update",
            payload: Data("{}".utf8),
            changedFields: []
        )
        context.insert(warmUp)
        try? context.save()

        return context
    }
}
