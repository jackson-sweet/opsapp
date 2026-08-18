//
//  ReviewThresholdServiceTests.swift
//  OPSTests
//
//  The review-stack rail notifications must cross the narrow server RPC
//  (`sync_review_stack_notification`), never a direct `notifications` insert —
//  the 2026-07-15 notification-creation hardening revoked app-role INSERT, so
//  the legacy client-side insert path 42501'd on every launch and the rail
//  went silently dead (bug filed 2026-08-17).
//
//  What these tests pin:
//    1. Every evaluation reports ALL THREE stacks to the syncer with the
//       store-derived counts — including counts of zero. The threshold and the
//       below-threshold auto-clear are SERVER-owned now; a client that gates
//       on a local threshold would leave stale rail rows standing when a stack
//       empties while the app is foregrounded.
//    2. One stack's transport failure must not starve the remaining stacks.
//    3. The counts handed to the syncer are exactly what the review queries
//       produce from the local store (wiring proof over a populated store; the
//       queries' own row-level behavior is pinned by TaskReviewQueryParityTests).
//    4. No resolved operator -> no sync calls at all.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ReviewThresholdServiceTests: XCTestCase {

    // MARK: - Spy

    /// Records every (stack, count) the service reports. Optionally fails
    /// selected stacks to prove per-stack error isolation. The service syncs
    /// stacks sequentially, so plain storage is race-free.
    private final class ReviewStackSyncSpy: ReviewStackSyncing {
        struct Call: Equatable {
            let stack: String
            let count: Int
        }

        private(set) var calls: [Call] = []
        var failingStacks: Set<String> = []

        func syncReviewStack(stack: String, count: Int) async throws -> String {
            calls.append(Call(stack: stack, count: count))
            if failingStacks.contains(stack) {
                throw URLError(.notConnectedToInternet)
            }
            return "created"
        }
    }

    // MARK: - Permission bookkeeping

    /// The review queries read `PermissionStore.shared` directly; save and
    /// restore whatever a previous suite left behind.
    private var savedPermissions: [String: String] = [:]
    private var savedBlockedByFlags: Set<String> = []
    private var savedDisabledFlags: Set<String> = []

    override func setUp() {
        super.setUp()
        savedPermissions = PermissionStore.shared.permissions
        savedBlockedByFlags = PermissionStore.shared.blockedByFlags
        savedDisabledFlags = PermissionStore.shared.disabledFlags
        PermissionStore.shared.blockedByFlags = []
        PermissionStore.shared.disabledFlags = []
        PermissionStore.shared.permissions = [
            "tasks.view": "all",
            "tasks.edit": "all",
            "tasks.assign": "all",
            "tasks.change_status": "all",
            "calendar.edit": "all",
            "projects.edit": "all",
        ]
    }

    override func tearDown() {
        PermissionStore.shared.permissions = savedPermissions
        PermissionStore.shared.blockedByFlags = savedBlockedByFlags
        PermissionStore.shared.disabledFlags = savedDisabledFlags
        super.tearDown()
    }

    // MARK: - 1. All three stacks, verbatim counts, zero included

    func test_syncAllReportsAllThreeStacksWithVerbatimCounts() async {
        let spy = ReviewStackSyncSpy()

        await ReviewThresholdService.syncAll(
            taskReviewCount: 7,
            paymentReviewCount: 0,
            unscheduledReviewCount: 12,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [
                .init(stack: "task_review_stack", count: 7),
                .init(stack: "payment_review_stack", count: 0),
                .init(stack: "unscheduled_review_stack", count: 12),
            ],
            "Every stack reports every evaluation — zero included, so the server can clear a drained stack"
        )
    }

    // MARK: - 2. Per-stack failure isolation

    func test_syncAllContinuesPastAFailingStack() async {
        let spy = ReviewStackSyncSpy()
        spy.failingStacks = ["task_review_stack"]

        await ReviewThresholdService.syncAll(
            taskReviewCount: 9,
            paymentReviewCount: 6,
            unscheduledReviewCount: 5,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls.map(\.stack),
            ["task_review_stack", "payment_review_stack", "unscheduled_review_stack"],
            "A transport failure on one stack must not starve the remaining stacks"
        )
    }

    // MARK: - 3. Store-derived counts flow to the syncer

    func test_evaluateFeedsStoreCountsToTheSyncer() async throws {
        let fixture = try makeFixture()
        let spy = ReviewStackSyncSpy()

        let expectedTask = TaskReviewQuery.overdueReviewTasks(dataController: fixture.dataController).count
        let expectedPayment = ProjectReviewQuery.snapshot(dataController: fixture.dataController).count
        let expectedUnscheduled = TaskReviewQuery.unscheduledReviewTasks(dataController: fixture.dataController).count

        // The wiring proof must not pass over an empty store.
        XCTAssertGreaterThan(expectedTask, 0, "fixture must produce overdue review tasks")
        XCTAssertGreaterThan(expectedUnscheduled, 0, "fixture must produce unscheduled review tasks")

        let syncTask = ReviewThresholdService.evaluate(
            dataController: fixture.dataController,
            syncer: spy
        )
        await syncTask?.value

        XCTAssertEqual(
            spy.calls,
            [
                .init(stack: "task_review_stack", count: expectedTask),
                .init(stack: "payment_review_stack", count: expectedPayment),
                .init(stack: "unscheduled_review_stack", count: expectedUnscheduled),
            ],
            "The syncer receives exactly the counts the review queries derive from the store"
        )
    }

    // MARK: - 4. No operator, no calls

    func test_evaluateWithoutOperatorMakesNoCalls() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)
        // `DataController.init` fires `checkExistingAuth()`, which clears
        // `currentUser` when no credentials are stored — exactly the state
        // this test needs. Wait for it to settle rather than racing it.
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertNil(dataController.currentUser)

        let spy = ReviewStackSyncSpy()
        let syncTask = ReviewThresholdService.evaluate(
            dataController: dataController,
            syncer: spy
        )
        await syncTask?.value

        XCTAssertNil(syncTask, "No operator -> no sync task at all")
        XCTAssertTrue(spy.calls.isEmpty, "No operator -> nothing reported")
    }

    // MARK: - Fixture

    private struct Fixture {
        let context: ModelContext
        let dataController: DataController
    }

    /// A compact populated store: one operator, one active project carrying
    /// overdue + unscheduled tasks, one completed project for the payment
    /// stack. Counts are asserted through the queries themselves (the parity
    /// suite pins those row-by-row); this fixture only has to make the task
    /// and unscheduled stacks provably nonzero.
    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let operatorID = "user-review-1"
        let companyID = "co-review"

        let company = Company(id: companyID, name: "Norcut")
        context.insert(company)

        let user = User(
            id: operatorID,
            firstName: "Marcus",
            lastName: "Hale",
            role: .crew,
            companyId: companyID
        )
        context.insert(user)

        let active = Project(id: "p-active", title: "South deck rebuild", status: .inProgress)
        active.companyId = companyID
        context.insert(active)

        let completed = Project(id: "p-completed", title: "Fence line", status: .completed)
        completed.companyId = companyID
        completed.completedAt = Date(timeIntervalSinceNow: -40 * 86_400)
        context.insert(completed)

        let day: TimeInterval = 86_400
        /// id, scheduled days ago (nil = unscheduled), crew
        let tasks: [(String, Double?, [String])] = [
            ("t-overdue-a", 3, [operatorID]),
            ("t-overdue-b", 6, [operatorID]),
            ("t-unscheduled-nocrew", nil, []),
            ("t-future", -5, [operatorID]),
        ]
        for (id, daysAgo, crew) in tasks {
            let task = ProjectTask(
                id: id,
                projectId: active.id,
                taskTypeId: "task-type-1",
                companyId: companyID,
                status: .active
            )
            if let daysAgo {
                let scheduled = Date(timeIntervalSinceNow: -daysAgo * day)
                task.startDate = scheduled
                task.endDate = scheduled
            }
            task.setTeamMemberIds(crew)
            task.project = active
            context.insert(task)
        }
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        // Outlast the init-time `checkExistingAuth()` clear — same dance as
        // TaskReviewQueryParityTests.
        dataController.currentUser = user
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        dataController.currentUser = user

        return Fixture(context: context, dataController: dataController)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
        ])
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
