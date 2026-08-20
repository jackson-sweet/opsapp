import XCTest
import UIKit
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

    func testDeckQuickActionOpensExistingAttachedDesignBeforeCreating() {
        let projectId = UUID().uuidString
        let attached = DeckDesign(
            companyId: UUID().uuidString,
            projectId: projectId,
            title: "Existing attached deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        attached.updatedAt = Date(timeIntervalSince1970: 1_000)

        let standalone = DeckDesign(
            companyId: UUID().uuidString,
            projectId: nil,
            title: "Standalone deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        standalone.updatedAt = Date(timeIntervalSince1970: 2_000)

        let decision = ProjectDeckActionResolver.resolve(
            designs: [standalone, attached],
            forProjectId: projectId
        )

        XCTAssertEqual(decision, .open(attached))
    }

    func testDeckQuickActionCreatesWhenNoAttachedDesignExists() {
        let projectId = UUID().uuidString
        let deletedAttached = DeckDesign(
            companyId: UUID().uuidString,
            projectId: projectId,
            title: "Deleted attached deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        deletedAttached.deletedAt = Date()

        let decision = ProjectDeckActionResolver.resolve(
            designs: [deletedAttached],
            forProjectId: projectId
        )

        XCTAssertEqual(decision, .create)
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

    func testUniversalSearchKeepsCompletedProjectsWithActiveResults() {
        let completed = makeProject(id: "completed", status: .completed, teamIds: [])
        let closed = makeProject(id: "closed", status: .closed, teamIds: [])
        let archived = makeProject(id: "archived", status: .archived, teamIds: [])

        XCTAssertFalse(UniversalSearchVisibilityPolicy.isInactiveProject(completed))
        XCTAssertTrue(UniversalSearchVisibilityPolicy.isInactiveProject(closed))
        XCTAssertTrue(UniversalSearchVisibilityPolicy.isInactiveProject(archived))
    }

    @MainActor
    func testGlobalKeyboardDoneAccessoryInstallsForTextFieldsAndTextViews() {
        let notificationCenter = NotificationCenter()
        let coordinator = OPSKeyboardDoneAccessoryCoordinator(
            notificationCenter: notificationCenter
        )
        coordinator.start()
        defer { coordinator.stop() }

        let textField = UITextField()
        notificationCenter.post(
            name: UITextField.textDidBeginEditingNotification,
            object: textField
        )

        let textView = UITextView()
        notificationCenter.post(
            name: UITextView.textDidBeginEditingNotification,
            object: textView
        )

        XCTAssertTrue(textField.inputAccessoryView is OPSKeyboardDoneAccessoryView)
        XCTAssertTrue(textView.inputAccessoryView is OPSKeyboardDoneAccessoryView)
    }

    @MainActor
    func testGlobalKeyboardDoneAccessoryInsetsButtonBorderFromKeyboardAndCentersLabel() throws {
        let textField = UITextField()
        let accessory = OPSKeyboardDoneAccessoryView(editingResponder: textField)
        accessory.frame = CGRect(
            x: .zero,
            y: .zero,
            width: 320,
            height: OPSStyle.Layout.keyboardAccessoryHeight
        )

        // iOS 26.5: UIToolbar only mounts bar-item custom views once it joins
        // a window — a detached host leaves the done button at a 0pt frame, so
        // the geometry must be proven inside the app host's real window.
        let window = try AppHostWindow.acquire()
        let host = UIView(frame: accessory.bounds)
        host.addSubview(accessory)
        window.addSubview(host)
        defer { host.removeFromSuperview() }
        host.layoutIfNeeded()
        accessory.layoutIfNeeded()

        let doneFrame = accessory.doneButton.convert(
            accessory.doneButton.bounds,
            to: accessory
        )
        let labelFrame = accessory.doneLabel.convert(
            accessory.doneLabel.bounds,
            to: accessory
        )
        // The bug this guards (026891c5): the predecessor test measured the
        // LABEL's clearance, which an inner top padding satisfies while the
        // BUTTON — the element whose border the user actually sees — still
        // spanned the whole band and sat flush on the keyboard. Measure the
        // button's own edges against the band, and the label against the
        // button. Nothing here is satisfiable by nudging the label alone.
        let borderToKeyboardSeparation = accessory.bounds.maxY - doneFrame.maxY
        let borderToTopSeparation = doneFrame.minY - accessory.bounds.minY

        XCTAssertEqual(
            accessory.intrinsicContentSize.height,
            OPSStyle.Layout.keyboardAccessoryHeight
        )

        // The band grew only enough to gutter a full-size target, and stays
        // compact — an earlier build was rejected for being too tall.
        XCTAssertGreaterThan(
            OPSStyle.Layout.keyboardAccessoryHeight,
            OPSStyle.Layout.touchTargetMin
        )
        XCTAssertLessThanOrEqual(
            OPSStyle.Layout.keyboardAccessoryHeight,
            OPSStyle.Layout.bottomCTAHeight
        )

        // Touch target is never traded away to buy the gap.
        XCTAssertGreaterThanOrEqual(doneFrame.height, OPSStyle.Layout.touchTargetMin)
        XCTAssertGreaterThanOrEqual(doneFrame.width, OPSStyle.Layout.touchTargetMin)

        // The visible border is inset from the keyboard edge, and from the top.
        XCTAssertGreaterThanOrEqual(
            borderToKeyboardSeparation,
            OPSStyle.Layout.spacing1,
            "DONE button's bottom border must clear the keyboard's top edge"
        )
        XCTAssertGreaterThanOrEqual(
            borderToTopSeparation,
            OPSStyle.Layout.spacing1,
            "DONE button's top border must clear the top of the accessory band"
        )

        // "DONE" sits centred in the button, not floating off its top. The
        // label's box is nudged by a sub-point cap-height offset so the glyph
        // INK lands dead centre; exact optical centring is asserted against
        // rendered pixels in KeyboardDoneAccessorySnapshotTests.
        XCTAssertEqual(
            labelFrame.midY,
            doneFrame.midY,
            accuracy: 4.0,
            "DONE label must be vertically centred within the button"
        )
        XCTAssertLessThan(labelFrame.height, doneFrame.height)

        XCTAssertEqual(accessory.doneButton.accessibilityIdentifier, "ops.keyboard.done")
        XCTAssertTrue(accessory.doneButton.isUserInteractionEnabled)
    }

    @MainActor
    func testGlobalKeyboardDoneAccessoryDoesNotStackOnRepeatedEditing() {
        let notificationCenter = NotificationCenter()
        let coordinator = OPSKeyboardDoneAccessoryCoordinator(
            notificationCenter: notificationCenter
        )
        coordinator.start()
        defer { coordinator.stop() }

        let textField = UITextField()
        notificationCenter.post(
            name: UITextField.textDidBeginEditingNotification,
            object: textField
        )
        let firstAccessory = textField.inputAccessoryView

        notificationCenter.post(
            name: UITextField.textDidBeginEditingNotification,
            object: textField
        )

        XCTAssertNotNil(firstAccessory)
        XCTAssertTrue(textField.inputAccessoryView === firstAccessory)
    }

    @MainActor
    func testPreparedTextViewKeepsAccessoryWithoutReloadingOnFocus() throws {
        let notificationCenter = NotificationCenter()
        let coordinator = OPSKeyboardDoneAccessoryCoordinator(
            notificationCenter: notificationCenter
        )
        coordinator.start()
        defer { coordinator.stop() }

        let textView = ReloadTrackingTextView()
        coordinator.prepare(textView)

        let accessory = try XCTUnwrap(
            textView.inputAccessoryView as? OPSKeyboardDoneAccessoryView
        )
        XCTAssertEqual(
            accessory.intrinsicContentSize.height,
            OPSStyle.Layout.keyboardAccessoryHeight
        )

        notificationCenter.post(
            name: UITextView.textDidBeginEditingNotification,
            object: textView
        )

        XCTAssertTrue(textView.inputAccessoryView === accessory)
        XCTAssertEqual(textView.reloadInputViewsCallCount, 0)
    }

    @MainActor
    func testGlobalKeyboardDoneAccessoryResignsTheRealFirstResponder() throws {
        let notificationCenter = NotificationCenter()
        let coordinator = OPSKeyboardDoneAccessoryCoordinator(
            notificationCenter: notificationCenter
        )
        coordinator.start()
        defer { coordinator.stop() }

        let host = UIViewController()
        let textField = UITextField(frame: CGRect(x: 20, y: 20, width: 200, height: 48))
        host.view.addSubview(textField)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        XCTAssertTrue(textField.becomeFirstResponder())
        notificationCenter.post(
            name: UITextField.textDidBeginEditingNotification,
            object: textField
        )

        let accessory = try XCTUnwrap(
            textField.inputAccessoryView as? OPSKeyboardDoneAccessoryView
        )
        // DONE is a direct subview rather than a bar item (iOS 26 wraps bar
        // items in a glass platter that cannot be positioned) — route through
        // the button's own target/action.
        let target = try XCTUnwrap(accessory.doneButton.allTargets.first)
        let action = try XCTUnwrap(
            accessory.doneButton.actions(forTarget: target, forControlEvent: .touchUpInside)?.first
        )

        XCTAssertTrue(
            UIApplication.shared.sendAction(
                NSSelectorFromString(action),
                to: target,
                from: accessory.doneButton,
                for: nil
            )
        )
        XCTAssertFalse(textField.isFirstResponder)
    }

    @MainActor
    private final class ReloadTrackingTextView: UITextView {
        private(set) var reloadInputViewsCallCount = 0

        override func reloadInputViews() {
            reloadInputViewsCallCount += 1
            super.reloadInputViews()
        }
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
