//
//  DetailsTabSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the project Details tab. Renders the real `DetailsTabView`
//  against a seeded in-memory store in three permission shapes — the office
//  viewer who sees every section, the read-only viewer who sees the same rows
//  with no edit affordance on any of them, and the crew viewer whose client row
//  stays but whose team roster, vinyl ordering, and edit affordances are scoped
//  away — plus the sparse project in both editable and read-only form. It also
//  renders `ClientPickerSheet` at the two moments its create-a-client row has
//  to be findable — an empty client list, and a search that returns nothing —
//  and once while browsing a populated list, where that row has to stay quiet.
//  Those renders are NOT pass/fail: they write PNGs for inspection.
//
//  The two LEAD states render too — the row sits between CLIENT and ADDRESS
//  inside the same document card, in the same label-column grammar (bug
//  a3c4e216). LEAD is the one row that leaves the card on emptiness; the
//  permission renders below are all in that default `.hidden` shape.
//
//  `leads_details_document_reference` renders the lead dossier
//  (`LeadDetailsDocument`) through the SAME capture path, at the same width, so
//  the two documents can be laid side by side. That comparison is the
//  acceptance test for "the project card matches the lead formatting".
//
//  The class DOES carry pass/fail assertions for three things a snapshot cannot
//  reach on its own:
//    • `InfoRowEdit` — the single gate the CLIENT, ADDRESS and NOTES rows
//      share (a context menu cannot be opened from a test).
//    • every project-info label clears the label column by a real margin, so
//      no label can wrap mid-word the way DESCRIPTION once did.
//    • `DocRow`'s default column is still 58 — the lead dossier passes no
//      width, and the project card now passes that same 58.
//
//  Rendered via FixedSizeSnapshot — hosted in the APP'S OWN window at a fixed
//  logical size, so asset-catalog colors resolve, onAppear runs, and the
//  capture is identical on any runner device (ImageRenderer is banned: asset
//  colors come out yellow; test-created windows render blank in degraded
//  full-suite runs — see AppHostWindow.swift).
//
//  `PermissionStore.shared` is a process-global singleton and `DetailsTabView`
//  reads it directly, so every render restores the ambient grants afterwards.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DetailsTabSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DetailsTabSnapshotTests: XCTestCase {

    private let tabWidth: CGFloat = 393  // iPhone 17

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-details-tab-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, view: V, height: CGFloat) {
        let size = CGSize(width: tabWidth, height: height)
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
        print("📸 SNAPSHOT \(name) → \(outDir.appendingPathComponent("\(name).png").path)")
    }

    // MARK: - Permission seam

    /// Runs `body` with the process-global permission store swapped for
    /// `grants`, then puts the ambient state back. Production gating is
    /// untouched — the test supplies a viewer, it does not widen the rules.
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
        }
        body()
    }

    /// Office/owner: every Details section visible, every edit affordance on.
    private var officeGrants: [String: String] {
        [
            "projects.view": "all",
            "projects.edit": "all",
            "tasks.view": "all",
            "tasks.create": "all",
            "clients.view": "all",
            "team.view": "all",
            "catalog.orders.view": "all",
            "deck_builder.view": "all"
        ]
    }

    /// Office grants with `projects.edit` withdrawn: every section still
    /// renders, and not one of them offers a way in. This is the viewer that
    /// proves long-press editing is permission-scoped — CLIENT, ADDRESS and
    /// DESCRIPTION must show their values with no menu, no chip, no ADD.
    private var readOnlyGrants: [String: String] {
        var grants = officeGrants
        grants.removeValue(forKey: "projects.edit")
        return grants
    }

    /// Exact preset Crew grants (Supabase `role_permissions`, verified
    /// 2026-07-04): client contact stays, team roster and vinyl ordering do
    /// not, and nothing is editable.
    private var crewGrants: [String: String] {
        [
            "projects.view": "assigned",
            "tasks.view": "assigned",
            "clients.view": "assigned",
            "deck_builder.view": "assigned"
        ]
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let project: Project
    }

    /// Every model the Details tab, the client picker, or the lead dossier
    /// reference render can reach. SwiftData wants the whole relationship
    /// closure, not just the rows a test seeds.
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

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: snapshotSchema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: snapshotSchema, configurations: [configuration])
    }

    /// One project with everything the tab can show: a client with both
    /// contact channels, an address, a two-line description, five tasks in
    /// mixed states (so the progress bar lands at a partial fill and the
    /// computed start/end dates resolve), and a three-person crew resolved
    /// through `teamMemberIdsString` against the store's `User` rows.
    private func makeFixture(
        withClient: Bool = true,
        address: String? = "1841 Beckwith Ave, Burnaby BC",
        description: String? = "Two-level cedar deck off the kitchen, 320 sq ft.\nCustomer wants the vinyl wrap matched to the existing sunroom.",
        withTasks: Bool = true,
        withTeam: Bool = true
    ) throws -> Fixture {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Crew — ids are lowercase because `UUID().uuidString` is uppercase and
        // the CSV lookup is case-sensitive.
        let crew = [
            User(id: "11111111-1111-1111-1111-111111111111", firstName: "Marcus", lastName: "Bell", role: .crew, companyId: "co-1"),
            User(id: "22222222-2222-2222-2222-222222222222", firstName: "Dana", lastName: "Whitfield", role: .crew, companyId: "co-1"),
            User(id: "33333333-3333-3333-3333-333333333333", firstName: "Ray", lastName: "Okafor", role: .crew, companyId: "co-1")
        ]
        crew.forEach { context.insert($0) }

        let project = Project(id: "p-details-1", title: "Beckwith deck rebuild", status: .inProgress)
        project.companyId = "co-1"
        project.address = address
        project.projectDescription = description
        context.insert(project)

        if withClient {
            let client = Client(
                id: "c-1",
                name: "Sam Rivera",
                email: "sam.rivera@example.com",
                phoneNumber: "604-555-0142",
                address: address,
                companyId: "co-1"
            )
            context.insert(client)
            project.client = client
            project.clientId = client.id
        }

        if withTeam {
            project.setTeamMemberIds(crew.map { $0.id })
        }

        if withTasks {
            // Fixed timestamps keep the capture deterministic — no TODAY /
            // TOMORROW drift between runs.
            let anchor = Date(timeIntervalSince1970: 1_784_601_600)
            let day: TimeInterval = 86_400

            let types = [
                TaskType(id: "tt-framing", display: "Framing", color: "#6F94B0", companyId: "co-1"),
                TaskType(id: "tt-decking", display: "Decking", color: "#9DB582", companyId: "co-1"),
                TaskType(id: "tt-railing", display: "Railing", color: "#C4A868", companyId: "co-1"),
                TaskType(id: "tt-vinyl", display: "Vinyl Install", color: "#B58289", companyId: "co-1"),
                TaskType(id: "tt-punch", display: "Punch List", color: "#8A8A8A", companyId: "co-1")
            ]
            types.forEach { context.insert($0) }

            let seeds: [(String, TaskType, TaskStatus, Double, Double, Int)] = [
                ("task-1", types[0], .completed, 0, 2, 0),
                ("task-2", types[1], .completed, 3, 4, 1),
                ("task-3", types[2], .active, 5, 6, 2),
                ("task-4", types[3], .active, 8, 10, 3),
                ("task-5", types[4], .cancelled, 12, 13, 4)
            ]

            for (id, type, status, startOffset, endOffset, order) in seeds {
                let task = ProjectTask(
                    id: id,
                    projectId: project.id,
                    taskTypeId: type.id,
                    companyId: "co-1",
                    status: status,
                    taskColor: type.color
                )
                task.taskType = type
                task.startDate = anchor.addingTimeInterval(startOffset * day)
                task.endDate = anchor.addingTimeInterval(endOffset * day)
                task.displayOrder = order
                task.setTeamMemberIds([crew[order % crew.count].id])
                context.insert(task)
                project.tasks.append(task)
            }
        }

        try context.save()
        return Fixture(container: container, project: project)
    }

    // MARK: - Host

    /// `onClientLongPress` is wired here exactly as `ProjectDetailsView` wires
    /// it (it opens the client picker). Without it the CLIENT row would have no
    /// action to offer and would honestly print `—` instead of its chip, and
    /// the empty-state alignment render would be proving the wrong thing.
    ///
    /// `lead` defaults to `.hidden` — the shape most projects are in, and the
    /// one the permission renders below are about. The lead renders pass it
    /// explicitly.
    @ViewBuilder
    private func hosted(
        _ fixture: Fixture,
        lead: ProjectLeadRow.Presentation = .hidden
    ) -> some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            DetailsTabView(
                project: fixture.project,
                viewModel: ProjectDetailsViewModel(project: fixture.project),
                onClientTap: {},
                onTeamMemberTap: { _ in },
                onTaskTap: { _ in },
                onAddTask: {},
                onClientLongPress: {},
                onChangeStatus: {},
                leadRowPresentation: lead,
                onOpenLead: {},
                onMatchLead: {}
            )
        }
        .frame(width: tabWidth)
        .modelContainer(fixture.container)
        .environmentObject(DataController())
    }

    /// A container of clients for the picker, with no project attached — the
    /// picker only ever reads `Client` rows for the company.
    private func makeClientPickerFixture(names: [String]) throws -> ModelContainer {
        let container = try makeContainer()
        let context = ModelContext(container)
        for (index, name) in names.enumerated() {
            context.insert(
                Client(
                    id: "picker-client-\(index)",
                    name: name,
                    email: nil,
                    phoneNumber: nil,
                    address: nil,
                    companyId: "co-1"
                )
            )
        }
        try context.save()
        return container
    }

    /// `searchText` is seeded through the picker's own initialiser, so the
    /// no-results moment renders without driving a keyboard. The device
    /// address book stays out of it: Contacts access is undetermined in the
    /// simulator, and `prepare()` only runs on a keystroke that never happens.
    @ViewBuilder
    private func hostedClientPicker(_ container: ModelContainer, searchText: String) -> some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ClientPickerSheet(
                currentClientId: nil,
                companyId: "co-1",
                searchText: searchText,
                onSelect: { _ in }
            )
        }
        .frame(width: tabWidth)
        .modelContainer(container)
        .environmentObject(DataController())
    }

    // MARK: - Renders

    /// The full tab as an owner/office viewer sees it: every section, every
    /// edit affordance.
    func testRenderDetailsTabOfficeViewer() throws {
        let fixture = try makeFixture()
        withPermissions(officeGrants) {
            snapshot("details_tab_office", view: hosted(fixture), height: 1500)
        }
    }

    /// The same project, same rows, viewer without `projects.edit`. CLIENT,
    /// ADDRESS and DESCRIPTION carry their values and nothing else — no chip,
    /// and no long-press menu is attached at all, so the gesture cannot
    /// surface an action this viewer may not take.
    func testRenderDetailsTabReadOnlyViewer() throws {
        let fixture = try makeFixture()
        withPermissions(readOnlyGrants) {
            snapshot("details_tab_read_only", view: hosted(fixture), height: 1400)
        }
    }

    /// The same project through crew grants — client contact stays, the team
    /// roster and vinyl ordering are scoped away, and nothing is editable.
    /// Proves the gated rows drop out without leaving a stray separator.
    func testRenderDetailsTabCrewViewer() throws {
        let fixture = try makeFixture()
        withPermissions(crewGrants) {
            snapshot("details_tab_crew", view: hosted(fixture), height: 1200)
        }
    }

    /// The project that came from a won lead (bug a3c4e216). LEAD sits between
    /// CLIENT and ADDRESS — provenance reads straight after who the job is for,
    /// with one hairline above it and one below, never two meeting.
    func testRenderDetailsTabLeadLinked() throws {
        let fixture = try makeFixture()
        withPermissions(officeGrants) {
            snapshot(
                "details_tab_lead_linked",
                view: hosted(fixture, lead: .linked(label: "Beckwith deck rebuild")),
                height: 1500
            )
        }
    }

    /// Unlinked, with won leads at this address waiting to be matched — the
    /// once-ever action, sized as a row in the card rather than a card of its own.
    func testRenderDetailsTabLeadMatch() throws {
        let fixture = try makeFixture()
        withPermissions(officeGrants) {
            snapshot(
                "details_tab_lead_match",
                view: hosted(fixture, lead: .match(candidateCount: 2)),
                height: 1500
            )
        }
    }

    /// The sparse project: no client, no address, no description, no tasks —
    /// every empty state at once, with edit permission so the invitations are
    /// the ones that render.
    ///
    /// THIS is the founder's second complaint made visible. ASSIGN CLIENT, ADD
    /// ADDRESS and ADD DESCRIPTION all start at the same x — directly right of
    /// their labels, at the head of the content region — and TIMELINE and TEAM
    /// print `—` at that identical x. Five rows, one column, one place to look.
    func testRenderDetailsTabEmptyStates() throws {
        let fixture = try makeFixture(
            withClient: false,
            address: nil,
            description: nil,
            withTasks: false,
            withTeam: false
        )
        withPermissions(officeGrants) {
            snapshot("details_tab_empty_states", view: hosted(fixture), height: 900)
        }
    }

    /// The sparse project without edit permission — the harder empty case.
    /// No invitations render; every one of the five rows still renders, each
    /// printing `—` at the same x the chips occupied above. The card's shape is
    /// a property of the viewer, never of how much has been filled in.
    func testRenderDetailsTabEmptyStatesReadOnly() throws {
        let fixture = try makeFixture(
            withClient: false,
            address: nil,
            description: nil,
            withTasks: false,
            withTeam: false
        )
        withPermissions(readOnlyGrants) {
            snapshot("details_tab_empty_states_read_only", view: hosted(fixture), height: 700)
        }
    }

    // MARK: - The reference document

    /// The lead dossier, captured through the same path at the same width — the
    /// document the project info card was reformatted to match. Lay this beside
    /// `details_tab_office` / `details_tab_empty_states`: same `// DETAILS`
    /// header, same solid card, same mono label column, same value line + meta
    /// line row anatomy, same chip, same `—`.
    func testRenderLeadDetailsDocumentReference() throws {
        let container = try makeContainer()

        let lead = Opportunity.preview(
            title: "Roof tear-off, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        lead.contactPhone = "(555) 123-4567"
        lead.contactEmail = "helen@example.com"

        let client = Client(id: "lead-c-1", name: "Calloway Homes")
        let estimate = Estimate(id: "lead-e-1", companyId: "co-1", estimateNumber: "EST-0142")
        estimate.title = "Roof tear-off"
        estimate.total = 14_200
        let attachment = LeadAttachment(
            id: "lead-a-1",
            filename: "roof-photos.pdf",
            mimeType: "application/pdf",
            sourceUrl: nil,
            fromEmail: "helen@example.com",
            ingestStatus: "stored",
            occurredAt: "2026-07-14T10:00:00Z",
            createdAt: "2026-07-14T10:00:00Z"
        )

        let view = ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            LeadDetailsDocument(
                lead: lead,
                client: client,
                rosterState: .onFile,
                canEdit: true,
                projectName: "Calloway roof tear-off",
                attachments: [attachment],
                estimates: [estimate]
            )
            .padding(.top, OPSStyle.Layout.spacing3)
        }
        .frame(width: tabWidth)
        .modelContainer(container)
        .environmentObject(PermissionStore.previewWithFullAccess())

        snapshot("leads_details_document_reference", view: view, height: 800)
    }

    // MARK: - Label column (pass/fail)

    /// The label column has to hold every project-info label on one line.
    ///
    /// This assertion previously demanded the column be "no wider than it has
    /// to be", and passed at 68pt while the real render wrapped DESCRIPTION to
    /// DESCRIPTIO / N: UIKit's `size(withAttributes:)` is close to, but not the
    /// same as, SwiftUI laying `Text` out inside a fixed frame, so a hairline
    /// fit measured green and shipped broken. It now demands the opposite —
    /// real slack — and the labels were shortened to earn it.
    func testLabelColumnHoldsEveryProjectInfoLabelOnOneLine() throws {
        let font = try XCTUnwrap(
            UIFont(name: "JetBrainsMono-Medium", size: 8.5),
            "JetBrainsMono-Medium must be registered in the app bundle"
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.9]

        // Every label clears the column by a real margin. 6pt is the guard band
        // that a measured-fits/renders-wrapped label would have failed.
        let slack: CGFloat = 6
        for label in ProjectInfoDoc.labels {
            let width = (label as NSString).size(withAttributes: attributes).width
            XCTAssertLessThanOrEqual(
                width,
                ProjectInfoDoc.labelColumnWidth - slack,
                "\(label) renders \(width)pt wide — too close to the \(ProjectInfoDoc.labelColumnWidth)pt column to trust it will not wrap"
            )
        }

        // The card shares the lead dossier's column exactly. If a future label
        // cannot live inside it, shorten the label — do not widen the column
        // and re-open the drift this document exists to close.
        XCTAssertEqual(
            ProjectInfoDoc.labelColumnWidth,
            58,
            "the project info card should share the lead dossier's own column"
        )
    }

    /// `DocRow`'s default column is still 58pt, so every existing caller — the
    /// whole lead dossier — renders exactly as it did before the project card
    /// started passing its own width.
    func testDocRowDefaultColumnIsUnchangedForTheLeadDossier() {
        let row = DocRow(label: "CLIENT") { EmptyView() }
        XCTAssertEqual(row.labelWidth, 58)
    }

    // MARK: - Client picker

    /// The client picker with nothing in it — the first moment the create row
    /// has to be findable. Nothing to browse, so the way forward is the only
    /// thing on offer.
    func testRenderClientPickerEmptyList() throws {
        let container = try makeClientPickerFixture(names: [])
        snapshot(
            "client_picker_empty_list",
            view: hostedClientPicker(container, searchText: ""),
            height: 700
        )
    }

    /// The second moment: a search that matches nobody. The typed name rides
    /// into the create row, so the user never types it twice.
    func testRenderClientPickerNoSearchResults() throws {
        let container = try makeClientPickerFixture(
            names: ["Sam Rivera", "Priya Nandakumar", "Bert Colwell"]
        )
        snapshot(
            "client_picker_no_search_results",
            view: hostedClientPicker(container, searchText: "Dave Chen"),
            height: 700
        )
    }

    /// The browse case, for contrast: a populated list where the create row is
    /// the quiet last rung rather than the headline.
    func testRenderClientPickerBrowsing() throws {
        let container = try makeClientPickerFixture(
            names: ["Sam Rivera", "Priya Nandakumar", "Bert Colwell"]
        )
        snapshot(
            "client_picker_browsing",
            view: hostedClientPicker(container, searchText: ""),
            height: 700
        )
    }

    // MARK: - Long-press edit gating (pass/fail)

    /// A context menu cannot be opened from a test, so the rule the three
    /// editable rows share is asserted where it is decided. Both conditions are
    /// load-bearing: the viewer must hold `projects.edit`, and the field must
    /// already hold a value — an empty field shows an explicit chip instead,
    /// because a long press on nothing is undiscoverable.
    func testLongPressEditIsOfferedOnlyToEditorsOfFilledFields() {
        XCTAssertTrue(InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: true))

        // Read-only viewer: no menu at all, in either field state.
        XCTAssertFalse(InfoRowEdit.offersLongPressEdit(canEdit: false, hasValue: true))
        XCTAssertFalse(InfoRowEdit.offersLongPressEdit(canEdit: false, hasValue: false))

        // Editor, empty field: the visible invitation owns it.
        XCTAssertFalse(InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: false))
    }

    /// A field already open for inline editing offers nothing further — the
    /// focused field and its SAVE / CANCEL are the whole interaction.
    func testLongPressEditIsWithdrawnWhileFieldIsBeingEdited() {
        XCTAssertFalse(
            InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: true, isEditing: true)
        )
        XCTAssertTrue(
            InfoRowEdit.offersLongPressEdit(canEdit: true, hasValue: true, isEditing: false)
        )
    }
}
#endif
