//
//  TaskDetailSheetSnapshotTests.swift
//  OPSTests
//
//  Bug 10b66fce — the expanded task sheet's header and its permission gates.
//
//  The header used to sit two 9pt mono pills alone on a full-width row above a
//  22pt title. Task type is now a colored eyebrow directly above the title and
//  status is one right-aligned pill on the title line; both detents are
//  captured because the sheet opens at `.medium` and expands to `.large`.
//
//  The gate captures are the visual half of TaskEditPermissionGateTests: the
//  same three grants, seen as the operator sees them. A control the operator
//  cannot use must be absent, not present-and-refusing.
//
//  Rendered via FixedSizeSnapshot: hosted in the APP'S OWN window at a fixed
//  logical size, so asset-catalog colors resolve, onAppear runs, and the
//  capture is identical on any runner device (see AppHostWindow.swift).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/TaskDetailSheetSnapshotTests
//

#if DEBUG
import SwiftUI
import SwiftData
import UIKit
import XCTest
@testable import OPS

@MainActor
final class TaskDetailSheetSnapshotTests: XCTestCase {

    /// iPhone 17 width. The two heights are the sheet's two detents: `.medium`
    /// is roughly half the 852pt screen, `.large` the rest of it.
    private let sheetWidth: CGFloat = 393
    private let mediumHeight: CGFloat = 426
    private let largeHeight: CGFloat = 800

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-task-detail-sheet-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var savedPermissions: [String: String] = [:]
    private var savedBlockedByFlags: Set<String> = []

    override func setUp() {
        super.setUp()
        savedPermissions = PermissionStore.shared.permissions
        savedBlockedByFlags = PermissionStore.shared.blockedByFlags
    }

    override func tearDown() {
        PermissionStore.shared.permissions = savedPermissions
        PermissionStore.shared.blockedByFlags = savedBlockedByFlags
        super.tearDown()
    }

    // MARK: - Header, both detents

    func testHeaderRendersAtBothDetents() throws {
        grant(["tasks.edit": "all", "tasks.assign": "all", "tasks.change_status": "all", "calendar.edit": "all"])
        let task = makeTask()

        snapshot("header-medium-detent", view: sheet(for: task), height: mediumHeight)
        snapshot("header-large-detent", view: sheet(for: task), height: largeHeight)
    }

    /// A long title must wrap without ever squeezing the status pill — the
    /// job's state is the one thing that has to stay readable.
    func testHeaderWithALongTitleKeepsTheStatusPillIntact() throws {
        grant(["tasks.edit": "all", "tasks.change_status": "all"])
        let task = makeTask()
        task.customTitle = "Rear elevation deck rebuild and rail replacement"

        snapshot("header-long-title", view: sheet(for: task), height: mediumHeight)
    }

    func testHeaderOnACompletedTask() throws {
        grant(["tasks.edit": "all", "tasks.change_status": "all"])
        let task = makeTask()
        task.status = .completed

        snapshot("header-completed", view: sheet(for: task), height: mediumHeight)
    }

    // MARK: - Permission states

    /// Full access: type eyebrow is tappable, crew row opens, status buttons show.
    func testSheetWithFullAccess() throws {
        grant(["tasks.edit": "all", "tasks.assign": "all", "tasks.change_status": "all", "calendar.edit": "all"])
        snapshot("gates-full-access", view: sheet(for: makeTask()), height: largeHeight)
    }

    /// Crew: may act on their own job's status, may not retype it, may not
    /// reassign the crew, may not reschedule. No chevrons, no type affordance.
    func testSheetAsCrewWithStatusRightsOnly() throws {
        grant(["tasks.change_status": "assigned"])
        PermissionStore.shared.setPreviewOperatorId("user-1")
        snapshot("gates-crew-status-only", view: sheet(for: makeTask()), height: largeHeight)
    }

    /// No grants at all — a pure readout. Every mutating affordance is gone.
    func testSheetWithNoGrantsIsAPureReadout() throws {
        grant([:])
        snapshot("gates-read-only", view: sheet(for: makeTask()), height: largeHeight)
    }

    /// Assigned-scope edit rights on someone else's task read as no rights.
    func testSheetWithAssignedEditRightsOnAnotherOperatorsTask() throws {
        grant(["tasks.edit": "assigned"])
        PermissionStore.shared.setPreviewOperatorId("user-1")
        let task = makeTask()
        task.teamMemberIdsString = "user-2"
        snapshot("gates-assigned-scope-other-task", view: sheet(for: task), height: largeHeight)
    }

    // MARK: - Description

    func testEmptyDescriptionInvitesEditingOnlyWhenPermitted() throws {
        grant(["tasks.edit": "all"])
        let editable = makeTask()
        editable.taskNotes = nil
        snapshot("description-empty-editable", view: sheet(for: editable), height: mediumHeight)

        grant([:])
        let readOnly = makeTask()
        readOnly.taskNotes = nil
        snapshot("description-empty-read-only", view: sheet(for: readOnly), height: mediumHeight)
    }

    // MARK: - Gate wiring (pass/fail)

    /// The sheet's gates must read the task's permission properties, not a
    /// hardcoded truth. Proven against the shared store the sheet consults.
    func testGatePropertiesTrackTheSharedPermissionStore() {
        let task = makeTask()

        grant([:])
        XCTAssertFalse(task.canEditFields)
        XCTAssertFalse(task.canAssignCrew)
        XCTAssertFalse(task.canChangeStatus)
        XCTAssertFalse(task.canEditSchedule)

        grant(["tasks.edit": "all", "tasks.assign": "all", "tasks.change_status": "all", "calendar.edit": "all"])
        XCTAssertTrue(task.canEditFields)
        XCTAssertTrue(task.canAssignCrew)
        XCTAssertTrue(task.canChangeStatus)
        XCTAssertTrue(task.canEditSchedule)
    }

    // MARK: - Helpers

    private func grant(_ permissions: [String: String]) {
        PermissionStore.shared.permissions = permissions
        PermissionStore.shared.blockedByFlags = []
    }

    private func makeTask() -> ProjectTask {
        let taskType = TaskType(
            id: "tt-install",
            display: "Installation",
            color: "#9DB582",
            companyId: "co"
        )
        let task = ProjectTask(
            id: "task-1",
            projectId: "proj-1",
            taskTypeId: taskType.id,
            companyId: "co"
        )
        task.taskType = taskType
        task.customTitle = "South deck rebuild"
        task.taskNotes = "Strip the old boards, check joist spacing, replace anything soft before decking goes down."
        task.startDate = Date()
        task.endDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())
        task.teamMemberIdsString = "user-1"
        return task
    }

    private func sheet(for task: ProjectTask) -> some View {
        let members = [
            TeamMember(id: "user-1", firstName: "Marcus", lastName: "Hale", role: "Crew"),
            TeamMember(id: "user-2", firstName: "Dana", lastName: "Reyes", role: "Crew")
        ]
        return TaskDetailPopupSheetHost(task: task, members: members)
            .environmentObject(DataController())
    }
}

/// Owns the `selectedTeamMemberIds` binding the sheet requires.
private struct TaskDetailPopupSheetHost: View {
    let task: ProjectTask
    let members: [TeamMember]

    @State private var selectedTeamMemberIds: Set<String> = ["user-1"]

    var body: some View {
        TaskDetailPopupSheet(
            task: task,
            onSelect: { _ in },
            onComplete: { _ in },
            onReschedule: { _ in },
            onCancel: { _ in },
            onScheduleTap: { _ in },
            selectedTeamMemberIds: $selectedTeamMemberIds,
            allTeamMembers: members
        )
    }
}

private extension TaskDetailSheetSnapshotTests {

    func snapshot<V: View>(_ name: String, view: V, height: CGFloat) {
        let size = CGSize(width: sheetWidth, height: height)
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(view, size: size)
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("SNAPSHOT \(name)")
    }
}
#endif
