//
//  HomeBillableThisWeekRollupTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class HomeBillableThisWeekRollupTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func testRollupSeparatesClosingThisWeekFromReadyToBill() {
        let today = date(2026, 5, 25) // Monday
        let closing = makeProject(id: "closing", title: "Smith deck", status: .inProgress)
        makeTask(id: "closing-active", project: closing, status: .active, end: date(2026, 5, 29))

        let ready = makeProject(id: "ready", title: "Jones rail", status: .completed)
        makeTask(id: "ready-complete", project: ready, status: .completed, end: date(2026, 5, 26))

        let draftInvoice = makeInvoice(id: "inv-closing", projectId: closing.id, status: .draft, total: 8_400)
        let signedEstimate = makeEstimate(id: "est-ready", projectId: ready.id, status: .approved, total: 2_600)

        let rollup = HomeBillableThisWeekRollupEngine.compute(
            projects: [ready, closing],
            invoices: [draftInvoice],
            estimates: [signedEstimate],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(rollup.closingThisWeek.map(\.projectId), ["closing"])
        XCTAssertEqual(rollup.readyToBill.map(\.projectId), ["ready"])
        XCTAssertEqual(rollup.totalKnownAmount, 11_000, accuracy: 0.001)
        XCTAssertEqual(rollup.projectCount, 2)
        XCTAssertEqual(rollup.closingThisWeek.first?.invoiceId, "inv-closing")
        XCTAssertEqual(rollup.readyToBill.first?.estimateId, "est-ready")
    }

    func testPostedInvoiceExcludesProjectFromRollup() {
        let today = date(2026, 5, 25)
        let project = makeProject(id: "posted", title: "Posted", status: .completed)
        makeTask(id: "complete", project: project, status: .completed, end: date(2026, 5, 25))
        let sentInvoice = makeInvoice(id: "inv-posted", projectId: project.id, status: .sent, total: 4_200)

        let rollup = HomeBillableThisWeekRollupEngine.compute(
            projects: [project],
            invoices: [sentInvoice],
            estimates: [],
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(rollup.closingThisWeek.isEmpty)
        XCTAssertTrue(rollup.readyToBill.isEmpty)
        XCTAssertEqual(rollup.projectCount, 0)
        XCTAssertEqual(rollup.totalKnownAmount, 0)
    }

    func testDraftInvoiceOutranksEstimateAndCancelledTasksAreIgnored() {
        let today = date(2026, 5, 25)
        let project = makeProject(id: "draft-priority", title: "Draft priority", status: .inProgress)
        makeTask(id: "complete", project: project, status: .completed, end: date(2026, 5, 25))
        makeTask(id: "cancelled", project: project, status: .cancelled, end: date(2026, 6, 8))
        let draftInvoice = makeInvoice(id: "inv-draft", projectId: project.id, status: .draft, total: 7_500)
        let estimate = makeEstimate(id: "est-approved", projectId: project.id, status: .approved, total: 9_000)

        let rollup = HomeBillableThisWeekRollupEngine.compute(
            projects: [project],
            invoices: [draftInvoice],
            estimates: [estimate],
            today: today,
            calendar: calendar
        )

        let item = rollup.readyToBill.first
        XCTAssertEqual(item?.amount, 7_500)
        XCTAssertEqual(item?.invoiceId, "inv-draft")
        XCTAssertNil(item?.estimateId)
        XCTAssertEqual(item?.taskCount, 1)
    }

    func testUnscheduledActiveTaskIsNotClosingThisWeek() {
        let today = date(2026, 5, 25)
        let project = makeProject(id: "unscheduled", title: "Unscheduled", status: .inProgress)
        makeTask(id: "active", project: project, status: .active, end: nil)

        let rollup = HomeBillableThisWeekRollupEngine.compute(
            projects: [project],
            invoices: [],
            estimates: [],
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(rollup.closingThisWeek.isEmpty)
        XCTAssertTrue(rollup.readyToBill.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeProject(id: String, title: String, status: Status) -> Project {
        let project = Project(id: id, title: title, status: status)
        project.companyId = "company-1"
        return project
    }

    @discardableResult
    private func makeTask(
        id: String,
        project: Project,
        status: TaskStatus,
        end: Date?
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
        project.tasks.append(task)
        return task
    }

    private func makeInvoice(id: String, projectId: String, status: InvoiceStatus, total: Double) -> Invoice {
        let invoice = Invoice(id: id, companyId: "company-1", invoiceNumber: id, status: status)
        invoice.projectId = projectId
        invoice.total = total
        invoice.balanceDue = total
        return invoice
    }

    private func makeEstimate(id: String, projectId: String, status: EstimateStatus, total: Double) -> Estimate {
        let estimate = Estimate(id: id, companyId: "company-1", estimateNumber: id, status: status)
        estimate.projectId = projectId
        estimate.total = total
        return estimate
    }
}
