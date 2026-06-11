import XCTest
@testable import OPS

final class IOSBugReportRegressionTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDeckQuickActionRequiresCreateOrEditPermission() {
        XCTAssertFalse(ProjectQuickActionPermissionGate.canShowDeckAction(
            featureEnabled: true,
            canCreate: false,
            canEdit: false
        ))
        XCTAssertTrue(ProjectQuickActionPermissionGate.canShowDeckAction(
            featureEnabled: true,
            canCreate: true,
            canEdit: false
        ))
        XCTAssertTrue(ProjectQuickActionPermissionGate.canShowDeckAction(
            featureEnabled: true,
            canCreate: false,
            canEdit: true
        ))
        XCTAssertFalse(ProjectQuickActionPermissionGate.canShowDeckAction(
            featureEnabled: false,
            canCreate: true,
            canEdit: true
        ))
    }

    func testFABPaymentAndInvoiceUseInvoicePermissions() {
        XCTAssertTrue(FABPermissionGate.canShowNewPayment { $0 == "invoices.record_payment" })
        XCTAssertFalse(FABPermissionGate.canShowNewPayment { $0 == "expenses.create" })

        XCTAssertTrue(FABPermissionGate.canShowNewInvoice { $0 == "invoices.create" })
        XCTAssertFalse(FABPermissionGate.canShowNewInvoice { $0 == "estimates.create" })
    }

    func testKanbanProjectFilteringAppliesSharedStatusAndTeamFilters() {
        let matching = makeProject(id: "matching", status: .accepted, teamIds: ["crew-a"])
        let wrongStatus = makeProject(id: "wrong-status", status: .rfq, teamIds: ["crew-a"])
        let wrongMember = makeProject(id: "wrong-member", status: .accepted, teamIds: ["crew-b"])
        let closed = makeProject(id: "closed", status: .closed, teamIds: ["crew-a"])

        let result = JobBoardProjectFiltering.kanbanProjects(
            from: [wrongStatus, matching, closed, wrongMember],
            assignedToMe: false,
            currentUserId: nil,
            selectedStatuses: [.accepted],
            selectedTeamMemberIds: ["crew-a"]
        )

        XCTAssertEqual(result.map(\.id), ["matching"])
    }

    func testPushByCalendarWeeksKeepsSameWeekday() {
        let saturday = makeDate(year: 2026, month: 6, day: 6)
        let task = PushMock(
            id: "task",
            taskTypeId: "install",
            startDate: saturday,
            endDate: saturday,
            duration: 1
        )

        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertEqual(daysBetween(saturday, result.newStart), 7)
        XCTAssertEqual(calendar.component(.weekday, from: result.newStart), calendar.component(.weekday, from: saturday))
    }

    func testLeadNotificationTypeIsRecognized() {
        // Lead rows carry a null deep_link_type, so `type` is the dominant signal.
        XCTAssertTrue(LeadNotificationRouteParser.isLeadNotification(type: "leads_waiting", deepLinkType: nil))
        XCTAssertTrue(LeadNotificationRouteParser.isLeadNotification(type: nil, deepLinkType: "opportunity"))
        XCTAssertTrue(LeadNotificationRouteParser.leadRoutingValues.contains("opportunities"))
        XCTAssertFalse(LeadNotificationRouteParser.isLeadNotification(type: "expense_approved", deepLinkType: nil))
    }

    func testLeadNotificationActionUrlParserAcceptsPathAndQueryForms() {
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "ops://leads/lead-path"),
            "lead-path"
        )
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "/opportunities/opportunity-path"),
            "opportunity-path"
        )
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "ops://pipeline?opportunityId=opportunity-query"),
            "opportunity-query"
        )
    }

    private func makeProject(id: String, status: Status, teamIds: [String]) -> Project {
        let project = Project(id: id, title: id, status: status)
        project.setTeamMemberIds(teamIds)
        return project
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    private struct PushMock: SchedulableTask {
        let id: String
        let taskTypeId: String
        let startDate: Date?
        let endDate: Date?
        let duration: Int
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = []
        var schedulingProjectId: String = "project"
    }
}
