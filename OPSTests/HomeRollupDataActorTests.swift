//
//  HomeRollupDataActorTests.swift
//  OPSTests
//
//  Locks the parity between Home's billable-this-week rollup as it was
//  computed on the main thread (HomeView.computeBillableRollup) and the
//  DataActor path that replaces it. The actor may move the work off the
//  render thread; it may not change a single value the card shows.
//

import XCTest
import SwiftData
@testable import OPS

final class HomeRollupDataActorTests: XCTestCase {

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Parity

    /// The lock: same store, same ids, same day — the actor's snapshot must be
    /// indistinguishable from the main-thread computation it replaces, down to
    /// the amount source of every candidate.
    func testActorRollupMatchesMainThreadComputationExactly() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())

        // Closing this week: work still open, all of it landing inside the week.
        let closing = makeProject(id: "closing", title: "Smith deck", status: .inProgress, in: context)
        makeTask(id: "closing-active", project: closing, status: .active, end: today, in: context)
        makeInvoice(id: "inv-closing", projectId: "closing", status: .draft, total: 8_400, in: context)

        // Ready to bill: finished yesterday, priced by an approved estimate.
        let ready = makeProject(id: "ready", title: "Jones rail", status: .completed, in: context)
        makeTask(id: "ready-complete", project: ready, status: .completed, end: day(today, -1), in: context)
        makeEstimate(id: "est-ready", projectId: "ready", status: .approved, total: 2_600, in: context)
        // Another company's draft invoice against the same project. If the
        // company gate were dropped, draft-invoice priority would override the
        // estimate and `ready` would report 7_777 instead of 2_600.
        makeInvoice(
            id: "inv-foreign-company",
            projectId: "ready",
            status: .draft,
            total: 7_777,
            companyId: "company-2",
            in: context
        )

        // Finished long enough ago that it belongs in Books, not on this card.
        let stale = makeProject(id: "stale", title: "Finished last winter", status: .completed, in: context)
        makeTask(id: "stale-complete", project: stale, status: .completed, end: day(today, -60), in: context)

        // Soft-deleted, but its id IS passed in — the engine drops it on both paths.
        let tombstone = makeProject(id: "tombstone", title: "Deleted job", status: .inProgress, in: context)
        tombstone.deletedAt = Date()
        makeTask(id: "tombstone-active", project: tombstone, status: .active, end: today, in: context)

        // Same company, would qualify loudly — but its id is NOT passed in. The
        // actor fetches exactly the ids it is given and never re-derives
        // visibility, so the card can never disagree with the map.
        let foreign = makeProject(id: "foreign-visible", title: "Not on the map", status: .inProgress, in: context)
        makeTask(id: "foreign-active", project: foreign, status: .active, end: today, in: context)
        makeInvoice(id: "inv-foreign", projectId: "foreign-visible", status: .draft, total: 9_999, in: context)

        // Committed work nobody broke into tasks.
        makeProject(id: "needs-tasks", title: "No plan yet", status: .accepted, in: context)

        try context.save()

        let projectIds = ["closing", "ready", "stale", "tombstone", "needs-tasks"]

        // Expected: the retired main-thread path, computed on a main-style
        // context exactly as HomeView.computeBillableRollup did.
        let mainContext = ModelContext(container)
        let expectedProjects = try fetchProjects(ids: projectIds, in: mainContext)
        let expectedInvoices = try mainContext.fetch(
            FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { $0.deletedAt == nil && $0.companyId == "company-1" }
            )
        )
        let expectedEstimates = try mainContext.fetch(
            FetchDescriptor<Estimate>(
                predicate: #Predicate<Estimate> { $0.deletedAt == nil && $0.companyId == "company-1" }
            )
        )
        let expected = HomeBillableThisWeekRollupEngine.compute(
            projects: expectedProjects,
            invoices: expectedInvoices,
            estimates: expectedEstimates,
            today: today
        )
        let expectedNeedsTasks = ProjectsWithoutTasksDetector
            .projectsWithoutTasks(from: expectedProjects)
            .count

        // Actual: the actor path.
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let snapshot = await actor.computeHomeRollup(
            projectIds: projectIds,
            companyId: "company-1",
            today: today
        )

        // Concrete content first — a parity assertion alone would pass if both
        // paths were identically wrong.
        XCTAssertEqual(snapshot.rollup.closingThisWeek.map(\.projectId), ["closing"])
        XCTAssertEqual(snapshot.rollup.readyToBill.map(\.projectId), ["ready"])
        XCTAssertEqual(expected.closingThisWeek.map(\.projectId), ["closing"])
        XCTAssertEqual(expected.readyToBill.map(\.projectId), ["ready"])

        XCTAssertEqual(
            snapshot.rollup.closingThisWeek.map(\.projectId),
            expected.closingThisWeek.map(\.projectId)
        )
        XCTAssertEqual(
            snapshot.rollup.readyToBill.map(\.projectId),
            expected.readyToBill.map(\.projectId)
        )

        assertCandidatesMatch(snapshot.rollup.closingThisWeek, expected.closingThisWeek)
        assertCandidatesMatch(snapshot.rollup.readyToBill, expected.readyToBill)

        // The company gate is what keeps `ready` priced by its own estimate.
        XCTAssertEqual(snapshot.rollup.readyToBill.first?.amount, 2_600)
        XCTAssertEqual(snapshot.rollup.readyToBill.first?.estimateId, "est-ready")
        XCTAssertNil(snapshot.rollup.readyToBill.first?.invoiceId)
        XCTAssertEqual(snapshot.rollup.closingThisWeek.first?.invoiceId, "inv-closing")
        XCTAssertEqual(snapshot.rollup.closingThisWeek.first?.amount, 8_400)

        XCTAssertEqual(snapshot.rollup.weekStart, expected.weekStart)
        XCTAssertEqual(snapshot.rollup.weekEnd, expected.weekEnd)
        XCTAssertEqual(snapshot.rollup.totalKnownAmount, expected.totalKnownAmount, accuracy: 0.001)
        XCTAssertEqual(snapshot.rollup.totalKnownAmount, 11_000, accuracy: 0.001)

        XCTAssertEqual(snapshot.projectsNeedingTasksCount, expectedNeedsTasks)
        XCTAssertEqual(snapshot.projectsNeedingTasksCount, 1)
    }

    /// The review-sheet-dismiss recompute takes the count-only method; it must
    /// answer exactly what the detector answers over the same ids.
    func testNeedsTasksCountMethodMatchesDetector() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        makeProject(id: "bare-1", title: "Bare one", status: .accepted, in: context)
        makeProject(id: "bare-2", title: "Bare two", status: .accepted, in: context)

        let planned = makeProject(id: "planned", title: "Planned", status: .inProgress, in: context)
        makeTask(id: "planned-task", project: planned, status: .active, end: Date(), in: context)

        // Task-less and actionable, but out of scope — never passed in.
        makeProject(id: "bare-unscoped", title: "Someone else's", status: .accepted, in: context)

        try context.save()

        let ids = ["bare-1", "bare-2", "planned"]
        let mainContext = ModelContext(container)
        let detectorCount = ProjectsWithoutTasksDetector
            .projectsWithoutTasks(from: try fetchProjects(ids: ids, in: mainContext))
            .count

        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let actorCount = await actor.projectsNeedingTasksCount(projectIds: ids)

        XCTAssertEqual(actorCount, 2)
        XCTAssertEqual(actorCount, detectorCount)
    }

    /// Evidence, not an assertion: what the main thread used to pay on every
    /// Home load at founder-device scale (261 live projects), against the
    /// round-trip latency of the actor call that replaces it. Timing is never
    /// asserted — only that both paths complete and agree.
    func testMainThreadCostEvidence() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())

        let projectCount = 261
        var projectIds: [String] = []
        projectIds.reserveCapacity(projectCount)

        for index in 0..<projectCount {
            let status: Status = index % 3 == 0 ? .completed : .inProgress
            let id = "p-\(index)"
            projectIds.append(id)
            let project = makeProject(id: id, title: "Job \(index)", status: status, in: context)

            for taskIndex in 0..<5 {
                let taskStatus: TaskStatus = (index % 3 == 0 || taskIndex < 3) ? .completed : .active
                makeTask(
                    id: "\(id)-t\(taskIndex)",
                    project: project,
                    status: taskStatus,
                    end: day(today, -(index % 90) + taskIndex),
                    in: context
                )
            }

            if index % 5 == 0 {
                makeInvoice(id: "inv-\(index)", projectId: id, status: .draft, total: Double(1_000 + index), in: context)
            }
            if index % 5 == 1 {
                makeEstimate(id: "est-\(index)", projectId: id, status: .approved, total: Double(2_000 + index), in: context)
            }
        }
        try context.save()

        // (a) The old cost: a cold main-thread pass — fresh context so the
        // relationship faults actually fire, mirroring a Home load.
        let coldContext = ModelContext(container)
        let clock = ContinuousClock()
        var mainThreadRollup: HomeBillableThisWeekRollup = .empty
        var mainThreadNeedsTasks = 0
        let mainThreadDuration = try clock.measure {
            let projects = try fetchProjects(ids: projectIds, in: coldContext)
            let invoices = try coldContext.fetch(
                FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { $0.deletedAt == nil && $0.companyId == "company-1" }
                )
            )
            let estimates = try coldContext.fetch(
                FetchDescriptor<Estimate>(
                    predicate: #Predicate<Estimate> { $0.deletedAt == nil && $0.companyId == "company-1" }
                )
            )
            mainThreadRollup = HomeBillableThisWeekRollupEngine.compute(
                projects: projects,
                invoices: invoices,
                estimates: estimates,
                today: today
            )
            mainThreadNeedsTasks = ProjectsWithoutTasksDetector.projectsWithoutTasks(from: projects).count
        }

        // (b) The new cost from the caller's side: wall time of the awaited
        // actor call. This is latency, not main-thread time — the caller
        // suspends, it does not block.
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        var snapshot = HomeRollupSnapshot(rollup: .empty, projectsNeedingTasksCount: 0)
        let actorDuration = await clock.measure {
            snapshot = await actor.computeHomeRollup(
                projectIds: projectIds,
                companyId: "company-1",
                today: today
            )
        }

        let mainMilliseconds = milliseconds(mainThreadDuration)
        let actorMilliseconds = milliseconds(actorDuration)
        print(String(
            format: "[PERF-EVIDENCE] %d projects x 5 tasks — old main-thread compute: %.1fms; "
                + "actor round-trip: %.1fms; main-thread work after refactor: ~0 (suspension)",
            projectCount,
            mainMilliseconds,
            actorMilliseconds
        ))

        XCTAssertEqual(snapshot.rollup.projectCount, mainThreadRollup.projectCount)
        XCTAssertEqual(snapshot.projectsNeedingTasksCount, mainThreadNeedsTasks)
    }

    // MARK: - Assertions

    private func assertCandidatesMatch(
        _ actual: [HomeBillableProjectCandidate],
        _ expected: [HomeBillableProjectCandidate],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualItem, expectedItem) in zip(actual, expected) {
            XCTAssertEqual(actualItem.id, expectedItem.id, file: file, line: line)
            XCTAssertEqual(actualItem.projectId, expectedItem.projectId, file: file, line: line)
            XCTAssertEqual(actualItem.title, expectedItem.title, file: file, line: line)
            XCTAssertEqual(actualItem.section, expectedItem.section, file: file, line: line)
            XCTAssertEqual(actualItem.taskCount, expectedItem.taskCount, file: file, line: line)
            XCTAssertEqual(actualItem.amount, expectedItem.amount, file: file, line: line)
            XCTAssertEqual(actualItem.invoiceId, expectedItem.invoiceId, file: file, line: line)
            XCTAssertEqual(actualItem.estimateId, expectedItem.estimateId, file: file, line: line)
            XCTAssertEqual(actualItem.latestTaskEnd, expectedItem.latestTaskEnd, file: file, line: line)
        }
    }

    // MARK: - Fixtures

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private func day(_ from: Date, _ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: from) ?? from
    }

    private func fetchProjects(ids: [String], in context: ModelContext) throws -> [Project] {
        try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate<Project> { ids.contains($0.id) })
        )
    }

    @discardableResult
    private func makeProject(
        id: String,
        title: String,
        status: Status,
        in context: ModelContext
    ) -> Project {
        let project = Project(id: id, title: title, status: status)
        project.companyId = "company-1"
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        id: String,
        project: Project,
        status: TaskStatus,
        end: Date?,
        in context: ModelContext
    ) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: project.id,
            taskTypeId: "task-type",
            companyId: project.companyId
        )
        task.status = status
        task.endDate = end
        task.project = project
        context.insert(task)
        return task
    }

    @discardableResult
    private func makeInvoice(
        id: String,
        projectId: String,
        status: InvoiceStatus,
        total: Double,
        companyId: String = "company-1",
        in context: ModelContext
    ) -> Invoice {
        let invoice = Invoice(id: id, companyId: companyId, invoiceNumber: id, status: status)
        invoice.projectId = projectId
        invoice.total = total
        invoice.balanceDue = total
        context.insert(invoice)
        return invoice
    }

    @discardableResult
    private func makeEstimate(
        id: String,
        projectId: String,
        status: EstimateStatus,
        total: Double,
        companyId: String = "company-1",
        in context: ModelContext
    ) -> Estimate {
        let estimate = Estimate(id: id, companyId: companyId, estimateNumber: id, status: status)
        estimate.projectId = projectId
        estimate.total = total
        context.insert(estimate)
        return estimate
    }

    private func makeContainer() throws -> ModelContainer {
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
            Invoice.self,
            Estimate.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container
    }
}
