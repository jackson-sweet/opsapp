//
//  AppStateNotificationRPCTests.swift
//  OPSTests
//
//  AppState's two remaining notification-creating surfaces — the throttled
//  periodic review reminders and the overdue-invoice rail — must cross the
//  narrow server RPCs, never a direct `notifications` insert. The 2026-07-15
//  notification-creation hardening revoked app-role INSERT, so both surfaces
//  42501'd silently: the rail went dead while the companion push kept firing.
//
//  What these tests pin:
//    1. `checkStaleEstimates` reports the `stale_estimate_review` kind with the
//       store-derived stale count AND the company's configured threshold — the
//       threshold is the dimension the server interpolates into its copy, so
//       dropping it would render "0+ days without follow-up".
//    2. `checkProjectsNeedingTasks` reports the `projects_needing_tasks` kind
//       with the store-derived count.
//    3. The UserDefaults throttle still gates the RPC, not just the old insert —
//       a second call inside the frequency window reaches the server zero times.
//    4. An empty queue reports nothing at all. These reminders are one-shot
//       nudges, not the auto-clearing review stacks: there is no zero-count
//       "clear" semantic to preserve here.
//    5. `checkOverdueInvoices` collapses the old lookup + per-recipient insert
//       loop into exactly ONE server call, and survives an empty recipient list
//       (the server deduped everyone away inside its own 24h window).
//
//  Copy and recipients are server-owned now — there is deliberately nothing
//  here asserting title/body strings. OneSignal push targeting is out of scope:
//  the service is a singleton with no seam, and in the test process its
//  Firebase ID-token fetch throws before any request is built.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class AppStateNotificationRPCTests: XCTestCase {

    // MARK: - Spies

    /// Records every review reminder reported to the server. The reminders are
    /// reported sequentially from a single task, so plain storage is race-free.
    private final class ReviewReminderSyncSpy: ReviewReminderSyncing {
        struct Call: Equatable {
            let kind: String
            let count: Int
            let thresholdDays: Int?
        }

        private(set) var calls: [Call] = []
        /// The server's verdict. `created` is the production-realistic answer
        /// and exercises the badge-refresh branch.
        var result: String = "created"

        func syncReviewReminder(kind: String, count: Int, thresholdDays: Int?) async throws -> String {
            calls.append(Call(kind: kind, count: count, thresholdDays: thresholdDays))
            return result
        }
    }

    /// Records how many times the overdue-invoice rail crossed the server, and
    /// hands back a configurable "these ids got NEW rows" list.
    private final class OverdueInvoiceSyncSpy: OverdueInvoiceSyncing {
        private(set) var callCount = 0
        var createdRecipients: [String] = []

        func syncOverdueInvoiceNotifications() async throws -> [String] {
            callCount += 1
            return createdRecipients
        }
    }

    // MARK: - Global-state bookkeeping

    /// Both surfaces throttle through `UserDefaults`, which survives across
    /// tests AND across runs on the same machine. Left dirty, a passing suite
    /// would silently stop exercising the RPC at all.
    private static let throttleKeys = [
        "lastStaleEstimateInAppNotification",
        "lastProjectsNeedingTasksInAppNotification",
        "lastOverdueInvoiceCheck",
    ]

    /// `refreshUnreadCount()` — reached on a `created` verdict — fetches the
    /// live unread count over the network when `user_id` is set. Clear it so
    /// the badge refresh short-circuits deterministically instead of reaching
    /// Supabase from a unit test; restore whatever a previous suite left.
    private var savedUserIdDefault: String?

    /// SwiftData containers must outlive the contexts vended from them — a
    /// released container traps the next `insert` inside SwiftData.
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        savedUserIdDefault = UserDefaults.standard.string(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_id")
        Self.throttleKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        Self.throttleKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        if let savedUserIdDefault {
            UserDefaults.standard.set(savedUserIdDefault, forKey: "user_id")
        } else {
            UserDefaults.standard.removeObject(forKey: "user_id")
        }
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - 1. Stale estimates: kind + store count + threshold

    func test_checkStaleEstimatesReportsKindCountAndThreshold() async throws {
        let fixture = try makeFixture(staleEstimateThresholdDays: 45)
        seedEstimates(fixture)

        // The wiring proof must not pass over an empty store.
        let expectedCount = StaleEstimateDetector.staleEstimatedProjects(
            from: fixture.dataController.getProjects(),
            thresholdDays: 45
        ).count
        XCTAssertEqual(expectedCount, 2, "fixture must produce exactly the two projects past the 45-day threshold")

        let spy = ReviewReminderSyncSpy()
        let syncTask = fixture.appState.checkStaleEstimates(
            dataController: fixture.dataController,
            frequencyDays: 7,
            syncer: spy
        )
        await syncTask?.value

        XCTAssertEqual(
            spy.calls,
            [.init(kind: "stale_estimate_review", count: expectedCount, thresholdDays: 45)],
            "The stale-estimate reminder reports its kind, the store-derived count, and the company's configured threshold"
        )
    }

    // MARK: - 2. Projects needing tasks: kind + store count, no threshold

    func test_checkProjectsNeedingTasksReportsKindAndCount() async throws {
        let fixture = try makeFixture()
        seedProjectsNeedingTasks(fixture)

        let expectedCount = ProjectsWithoutTasksDetector.projectsWithoutTasks(
            from: fixture.dataController.getProjects()
        ).count
        XCTAssertEqual(expectedCount, 3, "fixture must produce exactly the three committed projects with zero tasks")

        let spy = ReviewReminderSyncSpy()
        let syncTask = fixture.appState.checkProjectsNeedingTasks(
            dataController: fixture.dataController,
            frequencyDays: 7,
            syncer: spy
        )
        await syncTask?.value

        XCTAssertEqual(
            spy.calls,
            [.init(kind: "projects_needing_tasks", count: expectedCount, thresholdDays: nil)],
            "The tasks-missing reminder carries no threshold dimension — its copy has none to interpolate"
        )
    }

    // MARK: - 3. Throttle gates the RPC, not just the retired insert

    func test_secondReminderInsideFrequencyWindowNeverReachesTheServer() async throws {
        let fixture = try makeFixture(staleEstimateThresholdDays: 45)
        seedEstimates(fixture)

        let spy = ReviewReminderSyncSpy()

        let first = fixture.appState.checkStaleEstimates(
            dataController: fixture.dataController,
            frequencyDays: 7,
            syncer: spy
        )
        await first?.value
        XCTAssertEqual(spy.calls.count, 1, "the first call inside a clean window reports once")

        let second = fixture.appState.checkStaleEstimates(
            dataController: fixture.dataController,
            frequencyDays: 7,
            syncer: spy
        )
        await second?.value

        XCTAssertNil(second, "a throttled reminder produces no task at all")
        XCTAssertEqual(
            spy.calls.count,
            1,
            "a second call inside the frequency window must not reach the server"
        )
    }

    // MARK: - 4. Nothing stale, nothing reported

    func test_noStaleEstimatesReportsNothing() async throws {
        let fixture = try makeFixture(staleEstimateThresholdDays: 45)

        // An estimate that exists but is fresh — proves the zero case comes
        // from the staleness filter, not from an empty store.
        let fresh = Project(id: "p-fresh-estimate", title: "Cedar privacy screen", status: .estimated)
        fresh.companyId = fixture.companyID
        fresh.lastSyncedAt = Date(timeIntervalSinceNow: -2 * 86_400)
        fixture.context.insert(fresh)
        try fixture.context.save()

        XCTAssertEqual(fixture.dataController.getProjects().count, 1, "the store is populated")
        XCTAssertEqual(
            StaleEstimateDetector.staleEstimatedProjects(
                from: fixture.dataController.getProjects(),
                thresholdDays: 45
            ).count,
            0,
            "and nothing in it is stale"
        )

        let spy = ReviewReminderSyncSpy()
        let syncTask = fixture.appState.checkStaleEstimates(
            dataController: fixture.dataController,
            frequencyDays: 7,
            syncer: spy
        )
        await syncTask?.value

        XCTAssertNil(syncTask, "nothing stale -> no task")
        XCTAssertTrue(spy.calls.isEmpty, "nothing stale -> nothing reported")
    }

    // MARK: - 5. Overdue invoices cross the server exactly once

    func test_checkOverdueInvoicesMakesExactlyOneServerCall() async throws {
        let fixture = try makeFixture()
        seedInvoices(fixture)

        let spy = OverdueInvoiceSyncSpy()
        spy.createdRecipients = ["user-payer-1"]

        let notifyTask = fixture.appState.checkOverdueInvoices(
            dataController: fixture.dataController,
            invoiceSyncer: spy
        )
        await notifyTask?.value

        XCTAssertNotNil(notifyTask, "overdue invoices in the store -> the rail is reported")
        XCTAssertEqual(
            spy.callCount,
            1,
            "one RPC replaces the old recipient lookup plus per-recipient insert loop"
        )
    }

    func test_checkOverdueInvoicesSurvivesAnEmptyRecipientList() async throws {
        let fixture = try makeFixture()
        seedInvoices(fixture)

        let spy = OverdueInvoiceSyncSpy()
        spy.createdRecipients = []

        let notifyTask = fixture.appState.checkOverdueInvoices(
            dataController: fixture.dataController,
            invoiceSyncer: spy
        )
        await notifyTask?.value

        XCTAssertEqual(
            spy.callCount,
            1,
            "the server is still asked — it owns the dedupe decision, not the client"
        )
    }

    func test_noOverdueInvoicesNeverReachesTheServer() async throws {
        let fixture = try makeFixture()

        // Paid in full: a due date in the past is not enough — `isOverdue`
        // also requires an outstanding balance.
        let settled = Invoice(id: "inv-settled", companyId: fixture.companyID, status: .paid)
        settled.dueDate = Date(timeIntervalSinceNow: -30 * 86_400)
        settled.balanceDue = 0
        fixture.context.insert(settled)
        try fixture.context.save()

        let spy = OverdueInvoiceSyncSpy()
        let notifyTask = fixture.appState.checkOverdueInvoices(
            dataController: fixture.dataController,
            invoiceSyncer: spy
        )
        await notifyTask?.value

        XCTAssertNil(notifyTask, "nothing overdue -> no task")
        XCTAssertEqual(spy.callCount, 0, "nothing overdue -> the server is never asked")
    }

    // MARK: - Fixture

    private struct Fixture {
        let context: ModelContext
        let dataController: DataController
        let appState: AppState
        let companyID: String
    }

    /// One operator, one company, an empty project/invoice store. Each test
    /// seeds only the rows its surface reads.
    private func makeFixture(staleEstimateThresholdDays: Int = 30) throws -> Fixture {
        let container = try makeInMemoryContainer()
        retainedContainers.append(container)
        let context = ModelContext(container)

        let operatorID = "user-notif-1"
        let companyID = "co-notif"

        let company = Company(id: companyID, name: "Norcut")
        company.staleEstimateThresholdDays = staleEstimateThresholdDays
        context.insert(company)

        let user = User(
            id: operatorID,
            firstName: "Marcus",
            lastName: "Hale",
            role: .admin,
            companyId: companyID
        )
        context.insert(user)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        // `DataController.init` fires `checkExistingAuth()`, which clears
        // `currentUser` when no credentials are stored. Outlast that clear
        // rather than racing it — same dance as ReviewThresholdServiceTests.
        dataController.currentUser = user
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        dataController.currentUser = user

        return Fixture(
            context: context,
            dataController: dataController,
            appState: AppState(),
            companyID: companyID
        )
    }

    /// Two estimates past the 45-day threshold, plus two decoys: a fresh
    /// estimate and an old project in the wrong status.
    private func seedEstimates(_ fixture: Fixture) {
        let day: TimeInterval = 86_400
        /// id, status, days since last sync
        let rows: [(String, Status, Double)] = [
            ("p-stale-a", .estimated, 60),
            ("p-stale-b", .estimated, 90),
            ("p-fresh", .estimated, 3),
            ("p-old-accepted", .accepted, 120),
        ]
        for (id, status, daysAgo) in rows {
            let project = Project(id: id, title: "Deck \(id)", status: status)
            project.companyId = fixture.companyID
            project.lastSyncedAt = Date(timeIntervalSinceNow: -daysAgo * day)
            fixture.context.insert(project)
        }
        try? fixture.context.save()
    }

    /// Three committed projects with zero tasks, plus two decoys: a committed
    /// project that already has a task, and a completed project with none.
    private func seedProjectsNeedingTasks(_ fixture: Fixture) {
        /// id, status, task count
        let rows: [(String, Status, Int)] = [
            ("p-bare-a", .accepted, 0),
            ("p-bare-b", .accepted, 0),
            ("p-bare-c", .inProgress, 0),
            ("p-planned", .accepted, 1),
            ("p-done", .completed, 0),
        ]
        for (id, status, taskCount) in rows {
            let project = Project(id: id, title: "Deck \(id)", status: status)
            project.companyId = fixture.companyID
            fixture.context.insert(project)

            for index in 0..<taskCount {
                let task = ProjectTask(
                    id: "\(id)-task-\(index)",
                    projectId: project.id,
                    taskTypeId: "task-type-1",
                    companyId: fixture.companyID,
                    status: .active
                )
                task.project = project
                fixture.context.insert(task)
            }
        }
        try? fixture.context.save()
    }

    /// Two invoices that satisfy `isOverdue` (past due date, balance
    /// outstanding, not voided) plus two that do not.
    private func seedInvoices(_ fixture: Fixture) {
        let day: TimeInterval = 86_400

        let overdueA = Invoice(id: "inv-overdue-a", companyId: fixture.companyID, status: .sent)
        overdueA.dueDate = Date(timeIntervalSinceNow: -12 * day)
        overdueA.balanceDue = 2_400

        let overdueB = Invoice(id: "inv-overdue-b", companyId: fixture.companyID, status: .partiallyPaid)
        overdueB.dueDate = Date(timeIntervalSinceNow: -3 * day)
        overdueB.balanceDue = 850.50

        // Voided: past due with a balance, but explicitly excluded.
        let voided = Invoice(id: "inv-void", companyId: fixture.companyID, status: .void)
        voided.dueDate = Date(timeIntervalSinceNow: -40 * day)
        voided.balanceDue = 5_000

        // Not yet due.
        let upcoming = Invoice(id: "inv-upcoming", companyId: fixture.companyID, status: .sent)
        upcoming.dueDate = Date(timeIntervalSinceNow: 10 * day)
        upcoming.balanceDue = 1_200

        [overdueA, overdueB, voided, upcoming].forEach { fixture.context.insert($0) }
        try? fixture.context.save()
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
            Invoice.self,
        ])
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
