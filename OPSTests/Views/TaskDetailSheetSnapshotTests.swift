//
//  TaskDetailSheetSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the project-details task sheet (`TaskDetailPopupSheet`).
//  Renders the real production view against a seeded in-memory store in every
//  shape an operator can actually land on:
//
//    1. active + fully populated  — no custom title, so ONE name (with the
//                                   task's colour carried beside it as a dot),
//                                   dates, three assignees, notes
//    2. active + custom title     — the only shape where the type badge earns
//                                   its place: badge = type, title = the
//                                   operator's own name for this instance
//    3. active + sparse           — nothing filled in, schedule grant HELD:
//                                   SET DATES + ASSIGN TEAM chips, `—` notes
//    4. active + sparse, no grant — the same task for a viewer who cannot
//                                   schedule: `—` where the chip was
//    5. completed                 — faded identity, REOPEN TASK as the single
//                                   primary, no SELECT and no CANCEL
//    6. cancelled                 — the terminal shape, same single way back
//    7. active on a COMPLETED project — `isProjectCompleted: true`
//    8. inline team picker expanded   — SKIPPED on iOS 26.5 (see below)
//    9. the shipping team-picker panel — rendered directly (see below)
//
//  These renders are NOT pass/fail design assertions: they write PNGs for
//  inspection. The one thing this class does assert is that each render
//  produced real pixels, and — for the picker — that the TEAM row could be
//  activated at all.
//
//  Rendered via `FixedSizeSnapshot` — hosted in the APP'S OWN window at a fixed
//  logical size, so asset-catalog colors resolve, `onAppear` runs, and the
//  capture is identical on any runner device (`ImageRenderer` is banned: asset
//  colors come out yellow; test-created windows render blank in degraded
//  full-suite runs — see AppHostWindow.swift).
//
//  PERMISSIONS. The DATES row is the one field whose *shape* depends on the
//  viewer: scheduling is gated on `calendar.edit` (scope-aware on the task's
//  assignees), and the document's rule is that an empty field offers a chip to
//  a viewer who can fill it and prints `—` to one who cannot. That answer is
//  now read while the row renders, not only inside its action closure, so these
//  renders swap `PermissionStore.shared` — a process-global singleton — and put
//  the ambient grants back afterwards. Production gating is untouched: the test
//  supplies a viewer, it does not widen the rules.
//
//  THE TEAM PICKER. `showTeamPicker` is private `@State` inside the production
//  view, so it cannot be set from a test and MUST NOT be given a production
//  hook just to be photographed. The only honest way in is the TEAM row's own
//  control, activated through the accessibility action the button publishes
//  (`accessibilityActivate`, the same entry point VoiceOver uses), which runs
//  the row's real action closure. `renderActivatingTeamRow` repeats
//  `FixedSizeSnapshot.render`'s pattern exactly — same `AppHostWindow`, same
//  fixed-size host, same layer-tree quiescence settle, same
//  `drawHierarchy(afterScreenUpdates:)` — with the activation spliced between
//  two settles (the shared helper vends no handle to the hosting controller,
//  and is deliberately left untouched).
//
//  On iOS 26.5 that route is closed: SwiftUI never materializes its
//  accessibility tree in a unit-test host, so the row cannot be activated and
//  the render SKIPS rather than faking the state. Details on the test. What is
//  captured instead is `TaskTeamPickerPanel` — the SHIPPING panel the sheet
//  composes, rendered directly at the sheet's own width. That is the production
//  view, not a rebuild of it; only its host differs.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/TaskDetailSheetSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class TaskDetailSheetSnapshotTests: XCTestCase {

    /// iPhone 17 logical width.
    private let sheetWidth: CGFloat = 393

    /// Height of the sheet's content at the `.large` detent on iPhone 17
    /// (852pt screen less the ~52pt the presentation leaves above the sheet).
    /// `.opsSheet` offers `[.medium, .large]`, so this is the taller of the two
    /// resting positions and the one where the whole sheet is legible at once.
    private let sheetHeight: CGFloat = 800

    /// The expanded team picker adds a commit row plus a roster, which is
    /// taller than the `.large` detent — in the app the sheet scrolls. The
    /// capture is given the extra room so the whole expanded state is visible
    /// in one frame rather than being clipped by the canvas.
    private let expandedPickerHeight: CGFloat = 1080

    /// The panel on its own — commit row plus five crew rows.
    private let pickerPanelHeight: CGFloat = 320

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-task-sheet-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attach(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }
        XCTAssertGreaterThan(data.count, 1_000, "\(name) rendered empty")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) → \(outDir.appendingPathComponent("\(name).png").path)")
    }

    private func snapshot<V: View>(_ name: String, view: V, height: CGFloat) {
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(view, size: CGSize(width: sheetWidth, height: height))
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
        }
        attach(image, named: name)
    }

    // MARK: - Permission seam

    /// Runs `body` with the process-global permission store swapped for
    /// `grants`, then puts the ambient state back.
    private func withPermissions(_ grants: [String: String], _ body: () -> Void) {
        let store = PermissionStore.shared
        let savedPermissions = store.permissions
        let savedDisabled = store.disabledFlags
        let savedBlocked = store.blockedByFlags
        store.permissions = grants
        store.disabledFlags = []
        store.blockedByFlags = []
        defer {
            store.permissions = savedPermissions
            store.disabledFlags = savedDisabled
            store.blockedByFlags = savedBlocked
            // The assigned-scope renders set a preview operator identity on the
            // shared store. It is process-global like the grants are, and a
            // leaked identity silently changes what a LATER test's scoped grant
            // resolves to. `currentUserId` is private, so it is cleared rather
            // than restored — production sets it from the keychain cache, which
            // no test host runs.
            store.setPreviewOperatorId(nil)
        }
        body()
    }

    /// A viewer who may move this task on the calendar. `calendar.edit: "all"`
    /// short-circuits `PermissionStore.canEditSchedule` before it reaches the
    /// assignee check, so it grants the row regardless of who is on the task.
    private var schedulerGrants: [String: String] {
        [
            "projects.view": "all",
            "tasks.view": "all",
            "tasks.edit": "all",
            "calendar.edit": "all"
        ]
    }

    /// The same viewer with the schedule grant withdrawn — crew, who may change
    /// a task's status but never its dates.
    private var noScheduleGrants: [String: String] {
        var grants = schedulerGrants
        grants.removeValue(forKey: "calendar.edit")
        return grants
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let task: ProjectTask
        /// Company roster the picker lists — built the way the production
        /// caller builds it (`TeamMember.fromUser` over the store's `User`
        /// rows), not hand-rolled.
        let roster: [TeamMember]
    }

    /// The full relationship closure `ProjectTask` can reach. SwiftData wants
    /// every related type in the schema, not just the rows a test seeds.
    private var snapshotSchema: Schema {
        Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectVinylOrderMarker.self,
            DeckDesign.self
        ])
    }

    /// Crew ids are written lowercase on purpose: `UUID().uuidString` is
    /// UPPERCASE, Postgres `uuid` columns are lowercase, and
    /// `ProjectTask.setTeamMemberIds` canonicalizes to lowercase — a fixture
    /// seeded uppercase would silently fail the CSV lookup.
    private static let crewSeed: [(id: String, first: String, last: String, role: UserRole)] = [
        ("11111111-1111-1111-1111-111111111111", "Marcus", "Bell", .crew),
        ("22222222-2222-2222-2222-222222222222", "Dana", "Whitfield", .crew),
        ("33333333-3333-3333-3333-333333333333", "Ray", "Okafor", .crew),
        ("44444444-4444-4444-4444-444444444444", "Priya", "Nandakumar", .office),
        ("55555555-5555-5555-5555-555555555555", "Bert", "Colwell", .crew)
    ]

    /// Fixed timestamp so the capture is deterministic — no TODAY / TOMORROW
    /// drift between runs.
    private let anchor = Date(timeIntervalSince1970: 1_784_601_600)

    private func makeFixture(
        status: TaskStatus,
        notes: String?,
        scheduled: Bool,
        assignedCount: Int,
        customTitle: String? = nil
    ) throws -> Fixture {
        let configuration = ModelConfiguration(
            schema: snapshotSchema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: snapshotSchema, configurations: [configuration])
        let context = ModelContext(container)

        let users = Self.crewSeed.map {
            User(id: $0.id, firstName: $0.first, lastName: $0.last, role: $0.role, companyId: "co-1")
        }
        users.forEach { context.insert($0) }

        let project = Project(id: "p-task-sheet", title: "Beckwith deck rebuild", status: .inProgress)
        project.companyId = "co-1"
        context.insert(project)

        let taskType = TaskType(id: "tt-railing", display: "Railing", color: "#C4A868", companyId: "co-1")
        context.insert(taskType)

        let task = ProjectTask(
            id: "task-sheet-\(status.rawValue)-\(assignedCount)-\(scheduled)-\(notes == nil ? "bare" : "noted")-\(customTitle ?? "typed")",
            projectId: project.id,
            taskTypeId: taskType.id,
            companyId: "co-1",
            status: status,
            taskColor: taskType.color
        )
        task.taskType = taskType
        task.taskNotes = notes
        task.customTitle = customTitle
        if scheduled {
            task.startDate = anchor
            task.endDate = anchor.addingTimeInterval(2 * 86_400)
        }
        // Nothing to seed for completion: `ProjectTask.completionDate` is a
        // computed alias for `endDate`, not a stored field.
        // Assignment resolves from the CSV, not from the relationship — seed
        // the CSV, which is what both the sheet's caller and the sheet read.
        task.setTeamMemberIds(users.prefix(assignedCount).map { $0.id })
        context.insert(task)
        project.tasks.append(task)

        try context.save()

        return Fixture(
            container: container,
            task: task,
            roster: users.map { TeamMember.fromUser($0) }
        )
    }

    // MARK: - Host

    /// Mirrors the production caller (`ProjectDetailsView`): the selection
    /// binding is seeded from the task's own CSV, the roster is the company's
    /// `TeamMember` list, and every callback is inert.
    private struct SheetHost: View {
        let task: ProjectTask
        let roster: [TeamMember]
        let isProjectCompleted: Bool

        @State private var selectedTeamMemberIds: Set<String>

        init(task: ProjectTask, roster: [TeamMember], isProjectCompleted: Bool) {
            self.task = task
            self.roster = roster
            self.isProjectCompleted = isProjectCompleted
            _selectedTeamMemberIds = State(initialValue: Set(task.getTeamMemberIds()))
        }

        var body: some View {
            TaskDetailPopupSheet(
                task: task,
                onSelect: { _ in },
                onComplete: { _ in },
                onReschedule: { _ in },
                onCancel: { _ in },
                onScheduleTap: { _ in },
                selectedTeamMemberIds: $selectedTeamMemberIds,
                allTeamMembers: roster,
                isProjectCompleted: isProjectCompleted,
                onCommitTeam: { _ in }
            )
        }
    }

    /// The sheet's type picker reads `DataController` from the environment.
    /// SwiftUI TRAPS on a missing `@EnvironmentObject` rather than degrading,
    /// so every host has to inject it — the same failure mode that crashed
    /// `ActivityFeedSnapshotTests` when a view gained a `PermissionStore`.
    @ViewBuilder
    private func hosted(_ fixture: Fixture, isProjectCompleted: Bool = false) -> some View {
        SheetHost(
            task: fixture.task,
            roster: fixture.roster,
            isProjectCompleted: isProjectCompleted
        )
        .frame(width: sheetWidth)
        .modelContainer(fixture.container)
        .environmentObject(DataController())
    }

    private let populatedNotes = """
        Protect the finished fascia before fastening the rail. Confirm every \
        post is plumb, keep the gate opening clear, and photograph the \
        completed run before leaving site.
        """

    // MARK: - Renders

    /// Everything the sheet can carry at once for the COMMON task — the one
    /// with no custom title. The name appears exactly ONCE (it used to print in
    /// the type badge and again as the title, because `displayTitle` falls back
    /// to the type), with the task's colour carried beside it as a dot. Below:
    /// the document card — DATES with a real span, TEAM as three overlapping
    /// initials, NOTES — then the action ladder.
    func testRenderActiveFullyPopulated() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 3
        )
        withPermissions(schedulerGrants) {
            snapshot("task_sheet_active_full", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// The one shape where the type badge earns its place: the operator named
    /// this instance themselves, so the badge (RAILING) and the title (WEST
    /// ELEVATION RAIL) carry different facts and the colour rides in the badge.
    func testRenderActiveWithCustomTitle() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 3,
            customTitle: "West elevation rail"
        )
        withPermissions(schedulerGrants) {
            snapshot("task_sheet_custom_title", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// The bare task an operator gets from a quick add, seen by someone who can
    /// fill it in: every empty field offers its way in at the same x — SET
    /// DATES, ASSIGN TEAM — and NOTES, which this sheet does not author, prints
    /// the document's `—`.
    func testRenderActiveSparse() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: nil,
            scheduled: false,
            assignedCount: 0
        )
        withPermissions(schedulerGrants) {
            snapshot("task_sheet_active_sparse", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// The same bare task seen by crew, who may change a task's status but
    /// never its dates. DATES prints `—` exactly where SET DATES sat for the
    /// scheduler — same column, same line — and offers nothing that would not
    /// work. Assigning crew is not schedule-gated, so ASSIGN TEAM stays.
    func testRenderSparseWithoutScheduleGrant() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: nil,
            scheduled: false,
            assignedCount: 0
        )
        withPermissions(noScheduleGrants) {
            snapshot("task_sheet_sparse_no_grant", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// Completed: badge and title fade, the primary action becomes REOPEN TASK,
    /// and neither SELECT nor CANCEL is offered. There is no COMPLETED row —
    /// `completionDate` IS `endDate`, so it could only restate the span.
    func testRenderCompleted() throws {
        let fixture = try makeFixture(
            status: .completed,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 3
        )
        withPermissions(schedulerGrants) {
            snapshot("task_sheet_completed", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// Cancelled: terminal, and it comes back through the SAME single REOPEN
    /// TASK primary the completed task uses — the old sheet spelled that action
    /// two different ways in two different places.
    func testRenderCancelled() throws {
        let fixture = try makeFixture(
            status: .cancelled,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 2
        )
        withPermissions(schedulerGrants) {
            snapshot("task_sheet_cancelled", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// An active task on a project that has already been closed out. The only
    /// difference from the fully populated render is that CANCEL TASK is gone.
    func testRenderActiveOnCompletedProject() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 3
        )
        withPermissions(schedulerGrants) {
            snapshot(
                "task_sheet_completed_project",
                view: hosted(fixture, isProjectCompleted: true),
                height: sheetHeight
            )
        }
    }

    /// The whole sheet with the inline picker open — the document card, then
    /// the picker panel full width directly beneath it.
    ///
    /// SKIPS on iOS 26.5. `showTeamPicker` is private `@State`, so the only
    /// honest way in is the row's own control, and in a unit-test host SwiftUI
    /// never materializes its accessibility tree: `_UIHostingView` answers 0
    /// for both `accessibilityElements` and `accessibilityElementCount()`, and
    /// the whole hierarchy under it is six unlabeled platform containers
    /// (verified by dumping the tree, 2026-07-30). SwiftUI builds that tree
    /// lazily and only once an assistive-technology client attaches to the
    /// process; there is no public API to force it from XCTest. The composed
    /// state is therefore left uncaptured rather than reached by adding a
    /// production hook or by rebuilding the expanded layout in the test —
    /// either would photograph something other than the shipping view. The
    /// panel itself IS captured, on its own, by the next test. If a future
    /// SwiftUI starts publishing the tree, this test resumes producing the PNG
    /// on its own with no edit.
    func testRenderTeamPickerExpanded() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 2
        )
        // `withPermissions` takes a non-throwing body, so the render's error is
        // carried back out rather than swallowed: an unreachable TEAM row is a
        // SKIP, but a failure to acquire the app host window is a real failure
        // and must not be disguised as one.
        var image: UIImage?
        var failure: Error?
        withPermissions(schedulerGrants) {
            do {
                image = try renderActivatingTeamRow(
                    hosted(fixture),
                    size: CGSize(width: sheetWidth, height: expandedPickerHeight)
                )
            } catch {
                failure = error
            }
        }
        if let pickerError = failure as? TeamPickerRenderError {
            throw XCTSkip(pickerError.description)
        }
        if let failure {
            XCTFail("Could not render the expanded team picker: \(failure)")
            return
        }
        guard let image else {
            XCTFail("The team picker render produced no image")
            return
        }
        attach(image, named: "task_sheet_team_picker_expanded")
    }

    /// The SHIPPING picker panel (`TaskTeamPickerPanel`) at the sheet's own
    /// width: CANCEL / DONE at the top so the way out is never behind the
    /// roster (bug 53552d03), then the company roster with the task's current
    /// assignees checked. DONE is drawn in its committed (undirty) state
    /// because the draft here matches what is on the task — exactly what the
    /// operator sees the instant the picker opens.
    func testRenderTeamPickerPanel() throws {
        let fixture = try makeFixture(
            status: .active,
            notes: populatedNotes,
            scheduled: true,
            assignedCount: 2
        )
        let committed = Set(fixture.task.getTeamMemberIds())
        snapshot(
            "task_sheet_team_picker_panel",
            view: PickerPanelHost(roster: fixture.roster, committed: committed)
                .frame(width: sheetWidth)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
                .modelContainer(fixture.container),
            height: pickerPanelHeight
        )
    }

    // MARK: - Permission gates (bug 10b66fce)
    //
    // The visual half of the gate rules. Every mutating control on this sheet
    // reads the grant that governs it, scope-aware on the task's crew, and a
    // control the operator cannot use must be ABSENT — not present and
    // refusing. These captures are what "absent" actually looks like.

    /// Full access: TYPE is tappable, NOTES invites an edit, the crew row
    /// opens, the status ladder is complete.
    func testRenderGatesWithFullAccess() throws {
        let fixture = try makeFixture(status: .active, notes: populatedNotes, scheduled: true, assignedCount: 3)
        withPermissions(fullGrants) {
            snapshot("gates-full-access", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// Crew who may move their own job's status but may not retype it, reassign
    /// it, or reschedule it. No TYPE chevron, no NOTES affordance, no crew
    /// picker — the status ladder survives alone.
    func testRenderGatesAsCrewWithStatusRightsOnly() throws {
        let fixture = try makeFixture(status: .active, notes: populatedNotes, scheduled: true, assignedCount: 3)
        fixture.task.setTeamMemberIds([Self.crewSeed[0].id])
        withPermissions(["tasks.change_status": "assigned"]) {
            PermissionStore.shared.setPreviewOperatorId(Self.crewSeed[0].id)
            snapshot("gates-crew-status-only", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// No grants at all — a pure readout. Every mutating affordance is gone and
    /// only SELECT THIS TASK, which changes nothing about the task, remains.
    func testRenderGatesWithNoGrantsIsAPureReadout() throws {
        let fixture = try makeFixture(status: .active, notes: populatedNotes, scheduled: true, assignedCount: 3)
        withPermissions([:]) {
            snapshot("gates-read-only", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// Assigned-scope edit rights on somebody ELSE's task read as no rights.
    func testRenderGatesWithAssignedScopeOnAnotherOperatorsTask() throws {
        let fixture = try makeFixture(status: .active, notes: populatedNotes, scheduled: true, assignedCount: 1)
        withPermissions(["tasks.edit": "assigned"]) {
            PermissionStore.shared.setPreviewOperatorId(Self.crewSeed[1].id)
            snapshot("gates-assigned-scope-other-task", view: hosted(fixture), height: sheetHeight)
        }
    }

    /// An empty NOTES field invites an edit only when the viewer may write it;
    /// otherwise it prints the document's blank (bug b6adebf43).
    func testRenderEmptyNotesInvitesEditingOnlyWhenPermitted() throws {
        let editable = try makeFixture(status: .active, notes: nil, scheduled: true, assignedCount: 2)
        withPermissions(fullGrants) {
            snapshot("gates-empty-notes-editable", view: hosted(editable), height: sheetHeight)
        }

        let readOnly = try makeFixture(status: .active, notes: nil, scheduled: true, assignedCount: 2)
        withPermissions([:]) {
            snapshot("gates-empty-notes-read-only", view: hosted(readOnly), height: sheetHeight)
        }
    }

    // MARK: - Gate wiring (pass/fail)

    /// The sheet's gates must read the task's permission properties, not a
    /// hardcoded truth. Proven against the shared store the sheet consults.
    func testGatePropertiesTrackTheSharedPermissionStore() throws {
        let fixture = try makeFixture(status: .active, notes: populatedNotes, scheduled: true, assignedCount: 1)
        let task = fixture.task

        withPermissions([:]) {
            XCTAssertFalse(task.canEditFields)
            XCTAssertFalse(task.canAssignCrew)
            XCTAssertFalse(task.canChangeStatus)
            XCTAssertFalse(task.canEditSchedule)
        }

        withPermissions(fullGrants) {
            XCTAssertTrue(task.canEditFields)
            XCTAssertTrue(task.canAssignCrew)
            XCTAssertTrue(task.canChangeStatus)
            XCTAssertTrue(task.canEditSchedule)
        }
    }

    /// Every grant this sheet consults, at company scope.
    private var fullGrants: [String: String] {
        [
            "projects.view": "all",
            "tasks.view": "all",
            "tasks.edit": "all",
            "tasks.assign": "all",
            "tasks.change_status": "all",
            "calendar.edit": "all"
        ]
    }

    /// Hosts the production panel with the sheet's own draft semantics: the
    /// draft is seeded from the committed selection, which is what
    /// `TaskDetailPopupSheet` does the moment the picker expands.
    private struct PickerPanelHost: View {
        let roster: [TeamMember]
        let committed: Set<String>

        @State private var draft: Set<String>

        init(roster: [TeamMember], committed: Set<String>) {
            self.roster = roster
            self.committed = committed
            _draft = State(initialValue: committed)
        }

        var body: some View {
            TaskTeamPickerPanel(
                members: roster,
                committed: committed,
                draft: $draft,
                onCancel: {},
                onCommit: { _ in }
            )
        }
    }

    // MARK: - Render with the TEAM row activated

    private enum TeamPickerRenderError: Error, CustomStringConvertible {
        case teamRowNotReachable

        var description: String {
            """
            The TEAM row published no activatable accessibility element — \
            SwiftUI does not build an accessibility tree in a unit-test host — \
            so the inline picker could not be opened without touching \
            production code. The shipping panel is captured on its own by \
            testRenderTeamPickerPanel instead.
            """
        }
    }

    /// `FixedSizeSnapshot.render`'s pattern, verbatim, with one extra step:
    /// after the first settle the TEAM row is activated through the
    /// accessibility action the production button already exposes, then the
    /// view is settled again so the expand animation finishes before the draw.
    private func renderActivatingTeamRow<V: View>(_ view: V, size: CGSize) throws -> UIImage {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        let container = UIViewController()
        container.overrideUserInterfaceStyle = .dark
        container.view.backgroundColor = .black
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: size.width),
            host.view.heightAnchor.constraint(equalToConstant: size.height),
        ])
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()

        settle(host.view)
        guard activateTeamRow(in: host.view) else {
            throw TeamPickerRenderError.teamRowNotReachable
        }
        settle(host.view)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            host.view.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }
    }

    /// Geometry quiescence — three consecutive stable layer-tree polls, never a
    /// fixed sleep. Bounded so a perpetually animating view still captures.
    private func settle(_ view: UIView) {
        var stable = 0
        var lastFingerprint = ""
        let deadline = Date(timeIntervalSinceNow: 2)
        while stable < 3, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let fingerprint = Self.fingerprint(of: view.layer)
            if fingerprint == lastFingerprint {
                stable += 1
            } else {
                stable = 0
                lastFingerprint = fingerprint
            }
        }
    }

    private static func fingerprint(of layer: CALayer, depth: Int = 0) -> String {
        var parts = ["\(layer.frame.integral)"]
        if depth < 12, let sublayers = layer.sublayers {
            parts.append("\(sublayers.count)")
            for sublayer in sublayers {
                parts.append(fingerprint(of: sublayer, depth: depth + 1))
            }
        }
        return parts.joined(separator: "|")
    }

    /// Fires the TEAM row's real action closure via the accessibility
    /// activation the row already publishes. Nothing is added to production for
    /// this — if the element is not there, the render fails rather than faking
    /// the state.
    private func activateTeamRow(in root: UIView) -> Bool {
        for element in Self.accessibilityTree(of: root) {
            let label = (element.accessibilityLabel ?? "").uppercased()
            guard label.contains("TEAM"),
                  element.accessibilityTraits.contains(.button) else { continue }
            if element.accessibilityActivate() { return true }
        }
        return false
    }

    /// Flattens the accessibility hierarchy: container elements first (SwiftUI
    /// publishes its controls there), then the UIKit subview tree.
    private static func accessibilityTree(of root: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 40 else { return [] }
        var nodes: [NSObject] = [root]

        // Both container routes, not either/or: SwiftUI's hosting view can
        // vend a non-nil but EMPTY `accessibilityElements` while still
        // answering the lazy `accessibilityElementCount()` protocol.
        var seen = Set<ObjectIdentifier>()
        for case let child as NSObject in (root.accessibilityElements ?? []) {
            guard seen.insert(ObjectIdentifier(child)).inserted else { continue }
            nodes.append(contentsOf: accessibilityTree(of: child, depth: depth + 1))
        }
        let count = root.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            for index in 0..<count {
                guard let child = root.accessibilityElement(at: index) as? NSObject,
                      seen.insert(ObjectIdentifier(child)).inserted else { continue }
                nodes.append(contentsOf: accessibilityTree(of: child, depth: depth + 1))
            }
        }

        if let view = root as? UIView {
            for subview in view.subviews {
                nodes.append(contentsOf: accessibilityTree(of: subview, depth: depth + 1))
            }
        }

        return nodes
    }
}
#endif
