//
//  CalendarFetchPredicationTests.swift
//  OPSTests
//
//  Every inbound data change toggles `DataController.scheduledTasksDidChange`.
//  With the Schedule tab mounted that reaches `reloadCalendarData()`, which
//  clears `cachedWeekStart` on purpose and forces a week rebuild — and the
//  rebuild used to fetch EVERY ProjectTask on the main context, then walk the
//  result faulting `teamMembers` and `project` per row. The month grid did the
//  same through `getAllScheduledTasks(from:)`. Both fetches are now predicated,
//  so rows that could never draw are excluded by the store instead of being
//  materialized and dropped.
//
//  Moving a filter from memory into a `#Predicate` is a change of MECHANISM,
//  and SwiftData's predicate translation is the part that can silently
//  disagree: an unsupported expression throws at fetch time, and both call
//  sites swallow that into an empty result. So each test here reconstructs the
//  filter it replaced VERBATIM over the same store and asserts row-for-row
//  equality, with an explicit non-empty precondition — a translation failure
//  fails loudly rather than passing over two empty arrays. This is the pattern
//  `TaskReviewQueryParityTests` uses for `getAllTasks()`.
//
//  One deliberate exception to parity is pinned rather than assumed:
//  `getAllScheduledTasks(from:)` never gated `deletedAt`, so a tombstoned task
//  kept a month-grid badge. That row is now dropped, and the test names both
//  halves — what the old filter returned, and what the new fetch returns.
//
//  `PermissionStore.shared` is a process-wide singleton these paths read
//  directly, so each fixture saves and restores it.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class CalendarFetchPredicationTests: XCTestCase {

    private let companyID = "co-alpha"
    private let operatorID = "user-1"

    // MARK: - Week cache (CalendarViewModel.rebuildWeekCache)

    /// The week canvas, day by day across the whole cached window, against the
    /// scope filter it replaced run verbatim over the same store.
    func test_weekCacheMatchesTheInMemoryFilterItReplaced() throws {
        let fixture = try makeFixture()
        defer { fixture.restorePermissions() }

        fixture.viewModel.loadProjectsForDate(fixture.today)

        let oracle = try weekCacheOracle(fixture)
        XCTAssertTrue(
            oracle.values.contains { !$0.isEmpty },
            "Precondition: the oracle has to place tasks somewhere in the window"
        )

        for day in windowDays(around: fixture.today) {
            XCTAssertEqual(
                fixture.viewModel.scheduledTasks(for: day).map(\.id),
                oracle[dayKey(day)] ?? [],
                "Week cache diverged from the pre-predicate filter on \(dayKey(day))"
            )
        }
    }

    /// The reason the fetch carries no date bound. The per-day filter admits a
    /// task by overlap, so work that STARTED before the window still belongs to
    /// it whenever its endDate reaches in. A lower bound on `startDate` — the
    /// obvious narrowing — would have dropped this row off the canvas.
    func test_weekCacheKeepsWorkThatStartedLongBeforeTheWindow() throws {
        let fixture = try makeFixture()
        defer { fixture.restorePermissions() }

        fixture.viewModel.loadProjectsForDate(fixture.today)

        XCTAssertTrue(
            fixture.viewModel.scheduledTasks(for: fixture.today).map(\.id).contains("t-long-running"),
            """
            A 60-day task that began outside the window still covers today. \
            Any startDate lower bound on the fetch would erase it.
            """
        )
    }

    func test_weekCacheDropsTombstonedAndUndatedRows() throws {
        let fixture = try makeFixture()
        defer { fixture.restorePermissions() }

        let everyRow = try fixture.context.fetch(FetchDescriptor<ProjectTask>())
        XCTAssertTrue(
            everyRow.contains { $0.deletedAt != nil && $0.startDate != nil },
            "Precondition: the store needs a dated tombstone for this to mean anything"
        )
        XCTAssertTrue(
            everyRow.contains { $0.startDate == nil },
            "Precondition: the store needs an undated row"
        )

        fixture.viewModel.loadProjectsForDate(fixture.today)

        let drawn = Set(windowDays(around: fixture.today).flatMap {
            fixture.viewModel.scheduledTasks(for: $0).map(\.id)
        })
        XCTAssertFalse(drawn.isEmpty, "The canvas has to be drawing something")
        XCTAssertTrue(
            drawn.isDisjoint(with: ["t-deleted-today", "t-undated", "t-beta-today"]),
            "Tombstoned, undated, and other-company rows must not reach the week canvas"
        )
    }

    // MARK: - Month grid (DataController.getAllScheduledTasks)

    /// Same rows, same order, as the in-memory filter — minus the tombstone the
    /// old filter had no gate for. Both halves are named so the one intended
    /// behavior change cannot hide inside a parity assertion.
    func test_getAllScheduledTasksMatchesTheInMemoryFilterExceptForTombstones() throws {
        let fixture = try makeFixture()
        defer { fixture.restorePermissions() }

        let cutoff = fixture.today.addingTimeInterval(-30 * day)
        let oracle = try monthGridOracle(fixture, from: cutoff)

        XCTAssertTrue(
            oracle.contains("t-deleted-today"),
            """
            Precondition: the filter this replaced returned tombstoned rows — \
            that is the bug the predicate closes, and it has to be reproduced \
            here or the assertion below proves nothing.
            """
        )

        let fetched = fixture.dataController.getAllScheduledTasks(from: cutoff)
        XCTAssertFalse(
            fetched.isEmpty,
            """
            An unsupported #Predicate throws at fetch time and getAllScheduledTasks \
            swallows it into []. A non-empty result is what proves the predicate \
            actually translated.
            """
        )
        XCTAssertEqual(
            fetched.map(\.id),
            oracle.filter { $0 != "t-deleted-today" },
            "Same rows in the same order as the pre-predicate filter, tombstone aside"
        )
    }

    /// The from-date bound moved into the predicate as a nil-coalesced
    /// comparison. This is the assertion that proves SwiftData translated it
    /// rather than quietly returning everything or nothing.
    func test_getAllScheduledTasksHonorsTheFromDateBound() throws {
        let fixture = try makeFixture()
        defer { fixture.restorePermissions() }

        let cutoff = fixture.today.addingTimeInterval(-30 * day)
        let ids = Set(fixture.dataController.getAllScheduledTasks(from: cutoff).map(\.id))

        XCTAssertTrue(ids.contains("t-today"), "A row inside the bound must survive it")
        XCTAssertFalse(
            ids.contains("t-ancient"),
            "A row scheduled 400 days back is outside the bound"
        )
        XCTAssertFalse(
            ids.contains("t-long-running"),
            """
            The month grid bounds on startDate, not on overlap — this 60-day \
            task starts outside the cutoff, and did under the old filter too.
            """
        )
        XCTAssertFalse(ids.contains("t-undated"), "An undated row is not scheduled")
    }

    // MARK: - Oracles

    /// `rebuildWeekCache` as it stood before the predicate: every task fetched,
    /// then gated in memory.
    ///
    /// Exactly what is and is not independent here: the soft-delete, dated, and
    /// SCOPE gates are reproduced verbatim rather than reached through the view
    /// model's private helpers — scope is `.all` with the team-member filter
    /// available, so that branch is the company test. The type/client/status
    /// pass is NOT independent: it calls production `applyTaskFilters(to:)`,
    /// which is a pass-through on this fixture (no filters selected, no
    /// archived projects). It is shared to keep the oracle honest about the
    /// stage under test, not because that stage is verified here.
    private func weekCacheOracle(_ fixture: Fixture) throws -> [String: [String]] {
        let everyRow = try fixture.context.fetch(FetchDescriptor<ProjectTask>())
        let scoped = everyRow.filter { task in
            guard task.deletedAt == nil else { return false }
            guard task.startDate != nil else { return false }
            return task.companyId == self.companyID
        }
        let filtered = fixture.viewModel.applyTaskFilters(to: scoped)

        let cal = Calendar.current
        var byDay: [String: [String]] = [:]
        for date in windowDays(around: fixture.today) {
            let dayStart = cal.startOfDay(for: date)
            byDay[dayKey(date)] = filtered
                .filter { task in
                    let start = cal.startOfDay(for: task.startDate!)
                    let end = cal.startOfDay(for: task.endDate ?? task.startDate!)
                    return start <= dayStart && end >= dayStart
                }
                .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
                .map(\.id)
        }
        return byDay
    }

    /// `getAllScheduledTasks(from:)` as it stood before the predicate — note the
    /// absence of any `deletedAt` gate, which is the point.
    private func monthGridOracle(_ fixture: Fixture, from cutoff: Date) throws -> [String] {
        let everyRow = try fixture.context.fetch(FetchDescriptor<ProjectTask>())
        return everyRow
            .filter { task in
                guard let taskStartDate = task.startDate else { return false }
                if taskStartDate < cutoff { return false }
                return task.companyId == self.companyID
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map(\.id)
    }

    // MARK: - Window helpers

    /// The days `rebuildWeekCache` populates: the Monday-anchored week around
    /// the center date, minus one week and plus two.
    ///
    /// Silently coupled to production's `-7..<14` span and Monday anchor. If
    /// that window shrinks and this is not updated, the extra days fall to
    /// `scheduledTasks(for:)`'s cache-miss branch and these tests quietly start
    /// asserting against the fallback fetch instead of the rebuild.
    private func windowDays(around centerDate: Date) -> [Date] {
        var weekCal = Calendar.current
        weekCal.firstWeekday = 2
        guard let weekStart = weekCal.dateInterval(of: .weekOfYear, for: centerDate)?.start else {
            return []
        }
        let cal = Calendar.current
        return (-7..<14).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dayKey(_ date: Date) -> String { Self.keyFormatter.string(from: date) }

    // MARK: - Fixture

    private let day: TimeInterval = 86_400

    private struct Fixture {
        let context: ModelContext
        let dataController: DataController
        let viewModel: CalendarViewModel
        let today: Date
        let restorePermissions: () -> Void
    }

    /// A store covering every branch the two fetches read: dated and undated,
    /// tombstoned and live, inside the window and far outside it, one company
    /// and another — plus a task that begins two months before the window and
    /// runs through it, which is the case that rules out a date bound.
    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let previousPermissions = PermissionStore.shared.permissions
        let previousBlocked = PermissionStore.shared.blockedByFlags
        let previousDisabled = PermissionStore.shared.disabledFlags
        // calendar.view=all puts the view model on the `.all` scope's company
        // branch; tasks.view=all puts getAllScheduledTasks on its full-access
        // branch. Both are then the same company test, which the oracles mirror.
        PermissionStore.shared.permissions = ["tasks.view": "all", "calendar.view": "all"]
        PermissionStore.shared.blockedByFlags = []
        PermissionStore.shared.disabledFlags = []

        let dataController = DataController()
        dataController.setModelContext(context)

        let user = User(
            id: operatorID, firstName: "Marcus", lastName: "Hale",
            role: .crew, companyId: companyID
        )
        context.insert(user)

        let today = Calendar.current.startOfDay(for: Date())

        let project = Project(id: "p-live", title: "South deck rebuild", status: .inProgress)
        project.companyId = companyID
        let betaProject = Project(id: "p-beta", title: "Other company's job", status: .inProgress)
        betaProject.companyId = "co-beta"
        context.insert(project)
        context.insert(betaProject)

        /// id, days from today the task starts, span in days (nil start =
        /// unscheduled), tombstoned, company.
        let rows: [(String, Double?, Double, Bool, String)] = [
            ("t-today", 0, 0, false, companyID),
            ("t-tomorrow", 1, 0, false, companyID),
            ("t-last-week", -4, 0, false, companyID),
            ("t-next-week", 9, 0, false, companyID),
            // Starts two months back, still running through today.
            ("t-long-running", -60, 70, false, companyID),
            // Dated, inside the window, and tombstoned: the row the month grid
            // used to keep drawing.
            ("t-deleted-today", 0, 0, true, companyID),
            ("t-undated", nil, 0, false, companyID),
            ("t-ancient", -400, 0, false, companyID),
            ("t-far-future", 200, 0, false, companyID),
            ("t-beta-today", 0, 0, false, "co-beta"),
        ]

        for (id, offset, span, isDeleted, company) in rows {
            let task = ProjectTask(
                id: id,
                projectId: company == companyID ? project.id : betaProject.id,
                taskTypeId: "task-type-1",
                companyId: company
            )
            if let offset {
                let start = today.addingTimeInterval(offset * day)
                task.startDate = start
                task.endDate = start.addingTimeInterval(span * day)
            }
            task.setTeamMemberIds([operatorID])
            if isDeleted { task.deletedAt = Date(timeIntervalSinceNow: -day) }
            task.project = company == companyID ? project : betaProject
            context.insert(task)
        }
        try context.save()

        // `DataController.init` fires a one-shot `checkExistingAuth()`; with no
        // stored credentials it calls `clearAuthentication()`, which nils
        // `currentUser`. Seed the operator, wait for that clear to land, then
        // seed again — otherwise it arrives mid-test and every guarded fetch
        // silently returns []. Waiting on the observed event, not a fixed sleep.
        dataController.currentUser = user
        let authSettled = Date(timeIntervalSinceNow: 5)
        while dataController.currentUser != nil, Date() < authSettled {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        dataController.currentUser = user

        let viewModel = CalendarViewModel()
        viewModel.dataController = dataController
        viewModel.selectedDate = today

        return Fixture(
            context: context,
            dataController: dataController,
            viewModel: viewModel,
            today: today,
            restorePermissions: {
                PermissionStore.shared.permissions = previousPermissions
                PermissionStore.shared.blockedByFlags = previousBlocked
                PermissionStore.shared.disabledFlags = previousDisabled
            }
        )
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
            SyncOperation.self,
            Company.self,
            CalendarUserEvent.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
