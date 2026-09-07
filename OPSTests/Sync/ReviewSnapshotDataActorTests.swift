import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ReviewSnapshotDataActorTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var directories: [URL] = []
    private var oldPermissions: [String: String] = [:]
    private var oldBlocked = Set<String>()
    private var oldAdmin = false
    private var oldActorFlag: Any?

    override func setUp() {
        super.setUp()
        oldPermissions = PermissionStore.shared.permissions
        oldBlocked = PermissionStore.shared.blockedByFlags
        oldAdmin = PermissionStore.shared.isAdmin
        oldActorFlag = UserDefaults.standard.object(forKey: "feature.useDataActor")
        PermissionStore.shared.setPreviewAdminAuthority(false)
        PermissionStore.shared.blockedByFlags = []
        PermissionStore.shared.permissions = ["tasks.view": "all", "tasks.edit": "all", "tasks.assign": "all",
            "tasks.change_status": "all", "calendar.edit": "all", "projects.edit": "all"]
    }

    override func tearDown() {
        PermissionStore.shared.permissions = oldPermissions
        PermissionStore.shared.blockedByFlags = oldBlocked
        PermissionStore.shared.setPreviewAdminAuthority(oldAdmin)
        if let oldActorFlag { UserDefaults.standard.set(oldActorFlag, forKey: "feature.useDataActor") }
        else { UserDefaults.standard.removeObject(forKey: "feature.useDataActor") }
        containers.removeAll()
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories.removeAll()
        super.tearDown()
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let controller: DataController
        let project: Project
        let task: ProjectTask
    }

    private func fixture(onDisk: Bool = false) throws -> Fixture {
        let schema = Schema([Project.self, ProjectTask.self, TaskType.self, TaskTypeReminder.self,
            TaskReminder.self, User.self, Client.self, SubClient.self, ProjectPhoto.self, SyncOperation.self, Company.self])
        let configuration: ModelConfiguration
        if onDisk {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-snapshot-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            directories.append(directory)
            configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("store.sqlite"))
        } else { configuration = ModelConfiguration(isStoredInMemoryOnly: true) }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        containers.append(container)
        let context = container.mainContext
        context.autosaveEnabled = false
        let company = Company(id: "company", name: "Review test")
        context.insert(company)
        let user = User(id: "operator", firstName: "Test", lastName: "Operator", role: .crew, companyId: company.id)
        context.insert(user)
        let project = Project(id: "active", title: "Active work", status: .inProgress)
        project.companyId = company.id
        project.setTeamMemberIds([user.id])
        context.insert(project)
        let task = ProjectTask(id: "task", projectId: project.id, taskTypeId: "type", companyId: company.id)
        task.startDate = Date(timeIntervalSinceNow: -3 * 86_400)
        task.endDate = task.startDate
        task.setTeamMemberIds([user.id])
        task.project = project
        context.insert(task)
        try context.save()
        // This fixture needs no authenticated startup, router, or network work.
        let controller = DataController()
        controller.modelContext = context
        controller.currentUser = user
        return Fixture(container: container, context: context, controller: controller, project: project, task: task)
    }

    private func request(_ fixture: Fixture, now: Date = Date(), calendar: Calendar = .current) throws -> ReviewSnapshotRequest {
        try XCTUnwrap(ReviewSnapshotRequest.capture(dataController: fixture.controller,
            permissionStore: .shared, now: now, calendar: calendar))
    }

    func testActorSnapshotMatchesSheetAndReminderMembershipAcrossPermissions() async throws {
        let fixture = try fixture()
        let closed = Project(id: "closed", title: "Closed work", status: .closed)
        closed.companyId = "company"
        fixture.context.insert(closed)
        let completed = Project(id: "completed", title: "Completed work", status: .completed)
        completed.companyId = "company"
        completed.completedAt = Date(timeIntervalSinceNow: -40 * 86_400)
        fixture.context.insert(completed)
        let completedTask = ProjectTask(id: "completed-task", projectId: completed.id, taskTypeId: "type",
            companyId: "company", status: .completed)
        completedTask.setTeamMemberIds(["OPERATOR"])
        completedTask.project = completed
        fixture.context.insert(completedTask)
        let estimate = Project(id: "estimate", title: "Stale quote", status: .estimated)
        estimate.companyId = "company"
        estimate.lastSyncedAt = Date(timeIntervalSinceNow: -60 * 86_400)
        fixture.context.insert(estimate)
        let bare = Project(id: "bare", title: "Unplanned work", status: .accepted)
        bare.companyId = "company"
        fixture.context.insert(bare)
        let unscheduled = ProjectTask(id: "unscheduled", projectId: fixture.project.id,
            taskTypeId: "type", companyId: "company")
        unscheduled.project = fixture.project
        fixture.context.insert(unscheduled)
        let deleted = ProjectTask(id: "deleted", projectId: fixture.project.id,
            taskTypeId: "type", companyId: "company", status: .completed)
        deleted.deletedAt = Date()
        fixture.context.insert(deleted)
        try fixture.context.save()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: fixture.container)
        for permissions in [PermissionStore.shared.permissions,
            ["tasks.edit": "assigned", "tasks.change_status": "assigned", "projects.edit": "assigned"],
            ["tasks.view": "all"]] {
            PermissionStore.shared.permissions = permissions
            let request = try request(fixture)
            let snapshot = try await actor.reviewSnapshot(for: request)
            let payment = ProjectReviewQuery.snapshot(dataController: fixture.controller)
            let projects = fixture.controller.getProjects()
            XCTAssertEqual(snapshot.counts.taskReviewCount, TaskReviewQuery.overdueReviewTasks(dataController: fixture.controller).count)
            XCTAssertEqual(snapshot.counts.unscheduledReviewCount, TaskReviewQuery.unscheduledReviewTasks(dataController: fixture.controller).count)
            XCTAssertEqual(snapshot.counts.paymentReviewCount, payment.count)
            XCTAssertEqual(snapshot.counts.overduePaymentCount, payment.overdueProjects.count)
            XCTAssertEqual(snapshot.counts.staleEstimateCount, StaleEstimateDetector.staleEstimatedProjects(from: projects).count)
            XCTAssertEqual(snapshot.counts.projectsWithoutTasksCount, ProjectsWithoutTasksDetector.projectsWithoutTasks(from: projects).count)
            XCTAssertEqual(snapshot.counts.completedTaskCount, 1)
            XCTAssertEqual(snapshot.counts.completedProjectCount, 2)
            XCTAssertTrue(snapshot.isTaskReviewLocked)
            XCTAssertTrue(snapshot.isPaymentReviewLocked)
            XCTAssertEqual(snapshot.taskBadgeCount, 0)
            XCTAssertEqual(snapshot.paymentBadgeCount, 0)
        }
    }

    /// Real persisted store + already registered actor rows: a throwaway
    /// verification context would conceal the stale-model failure being tested.
    func testActorReadEditReadReflectsMainContextTaskAndProjectSaves() async throws {
        let fixture = try fixture(onDisk: true)
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: fixture.container)
        let request = try request(fixture)
        let before = try await actor.reviewSnapshotWithThreadProbe(request)
        XCTAssertFalse(before.isMainThread, "Production actor must enumerate off the UI thread")
        XCTAssertEqual(before.snapshot.counts.taskReviewCount, 1)
        XCTAssertEqual(before.snapshot.counts.paymentReviewCount, 0)
        fixture.task.status = .completed
        fixture.project.status = .completed
        fixture.project.completedAt = Date(timeIntervalSinceNow: -40 * 86_400)
        try fixture.context.save()
        let after = try await actor.reviewSnapshot(for: request)
        XCTAssertEqual(after.counts.taskReviewCount, 0)
        XCTAssertEqual(after.counts.completedTaskCount, 1)
        XCTAssertEqual(after.counts.paymentReviewCount, 1)
        XCTAssertEqual(after.counts.overduePaymentCount, 1)
        fixture.task.deletedAt = Date()
        fixture.project.deletedAt = Date()
        try fixture.context.save()
        let deleted = try await actor.reviewSnapshot(for: request)
        XCTAssertEqual(deleted.counts.completedTaskCount, 0)
        XCTAssertEqual(deleted.counts.paymentReviewCount, 0)
        XCTAssertEqual(deleted.counts.projectCount, 0)
    }

    func testForeignCompanyRowsCannotChangeAnyReviewCountOrUnlock() async throws {
        let fixture = try fixture()
        let foreign = Project(id: "foreign", title: "Foreign work", status: .completed)
        foreign.companyId = "other-company"
        foreign.completedAt = Date(timeIntervalSinceNow: -40 * 86_400)
        fixture.context.insert(foreign)
        for index in 0..<6 {
            let task = ProjectTask(id: "foreign-\(index)", projectId: foreign.id, taskTypeId: "type",
                companyId: foreign.companyId, status: .completed)
            task.project = foreign
            fixture.context.insert(task)
        }
        let foreignActive = ProjectTask(id: "foreign-active", projectId: foreign.id,
            taskTypeId: "type", companyId: foreign.companyId)
        foreignActive.project = foreign
        foreignActive.startDate = Date(timeIntervalSinceNow: -2 * 86_400)
        fixture.context.insert(foreignActive)
        try fixture.context.save()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: fixture.container)
        let snapshot = try await actor.reviewSnapshot(for: request(fixture))
        let rows = TaskReviewQuery.overdueReviewTasks(dataController: fixture.controller)
        XCTAssertEqual(rows.map(\.id), [fixture.task.id])
        XCTAssertEqual(snapshot.counts.taskReviewCount, rows.count)
        XCTAssertEqual(snapshot.counts.completedTaskCount, 0)
        XCTAssertEqual(snapshot.counts.completedProjectCount, 0)
        XCTAssertEqual(snapshot.counts.paymentReviewCount, 0)
        XCTAssertTrue(snapshot.isTaskReviewLocked)
        XCTAssertTrue(snapshot.isPaymentReviewLocked)
        XCTAssertEqual(fixture.controller.getAllTasks().count, 8, "The general getter is unchanged")
    }

    func testFlagOffUsesExistingContextAndProducesRealCounts() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let fixture = try fixture()
        XCTAssertNil(fixture.controller.dataActor)
        let store = ReviewSnapshotStore()
        store.bind(dataController: fixture.controller)
        let snapshot = await store.value()
        XCTAssertEqual(snapshot?.counts.taskReviewCount, 1)
        XCTAssertEqual(snapshot?.scope.usesDataActor, false)
        XCTAssertFalse(store.isUnavailable)
        XCTAssertNil(fixture.controller.dataActor, "Rollback must not construct an independent actor")
    }

    func testSameDayElapsedThresholdExpiryAndInclusiveBoundary() throws {
        let fixture = try fixture()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 10))!
        let expiry = calendar.date(byAdding: .hour, value: 3, to: now)!
        fixture.project.status = .completed
        fixture.project.completedAt = calendar.date(byAdding: .day, value: -14, to: expiry)
        let estimate = Project(id: "estimate", title: "Quote", status: .estimated)
        estimate.companyId = "company"
        estimate.lastSyncedAt = calendar.date(byAdding: .day, value: -30, to: expiry)
        fixture.context.insert(estimate)
        try fixture.context.save()
        let beforeRequest = try request(fixture, now: now, calendar: calendar)
        let before = ReviewSnapshotCalculator.compute(tasks: [fixture.task], projects: [fixture.project, estimate], request: beforeRequest)
        XCTAssertEqual(before.counts.overduePaymentCount, 0)
        XCTAssertEqual(before.counts.staleEstimateCount, 0)
        XCTAssertEqual(before.nextEligibilityChangeAt, expiry)
        let atRequest = try request(fixture, now: expiry, calendar: calendar)
        let at = ReviewSnapshotCalculator.compute(tasks: [fixture.task], projects: [fixture.project, estimate], request: atRequest)
        XCTAssertEqual(before.scope, at.scope)
        XCTAssertEqual(at.counts.overduePaymentCount, 1)
        XCTAssertEqual(at.counts.staleEstimateCount, 1)
        XCTAssertEqual(at.nextEligibilityChangeAt, atRequest.endOfToday)
    }

    func testTaskDateBoundaryAndUnlockThresholdsAreIndependentOfRailCounts() throws {
        let fixture = try fixture()
        let request = try request(fixture)
        fixture.task.startDate = request.endOfToday
        fixture.task.endDate = nil
        var result = ReviewSnapshotCalculator.compute(tasks: [fixture.task], projects: [fixture.project], request: request)
        XCTAssertEqual(result.counts.taskReviewCount, 0, "Tomorrow is excluded")
        fixture.task.startDate = request.endOfToday.addingTimeInterval(-1)
        result = ReviewSnapshotCalculator.compute(tasks: [fixture.task], projects: [fixture.project], request: request)
        XCTAssertEqual(result.counts.taskReviewCount, 1, "The last second of today is included")
        XCTAssertEqual(result.taskBadgeCount, 0, "Rail membership does not unlock the review entry")
        result = ReviewSnapshot(scope: request.scope, counts: .init(completedTaskCount: 5, completedProjectCount: 5,
            taskReviewCount: 3, unscheduledReviewCount: 2, paymentReviewCount: 4), computedAt: request.now)
        XCTAssertFalse(result.isTaskReviewLocked)
        XCTAssertFalse(result.isPaymentReviewLocked)
        XCTAssertEqual(result.totalBadgeCount, 9)
    }
}

private extension DataActor {
    func reviewSnapshotWithThreadProbe(_ request: ReviewSnapshotRequest) throws -> (snapshot: ReviewSnapshot, isMainThread: Bool) {
        (try reviewSnapshot(for: request), Thread.isMainThread)
    }
}
