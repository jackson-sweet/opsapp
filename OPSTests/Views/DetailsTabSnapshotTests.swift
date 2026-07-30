//
//  DetailsTabSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the project Details tab. Renders the real `DetailsTabView`
//  against a seeded in-memory store in two permission shapes — the office
//  viewer who sees every section, and the crew viewer whose client row stays
//  but whose team roster, vinyl ordering, and edit affordances are scoped away.
//  NOT pass/fail: writes PNGs for inspection.
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
        let schema = Schema([
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
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

    @ViewBuilder
    private func hosted(_ fixture: Fixture) -> some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            DetailsTabView(
                project: fixture.project,
                viewModel: ProjectDetailsViewModel(project: fixture.project),
                onClientTap: {},
                onTeamMemberTap: { _ in },
                onTaskTap: { _ in },
                onAddTask: {},
                onChangeStatus: {}
            )
        }
        .frame(width: tabWidth)
        .modelContainer(fixture.container)
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

    /// The same project through crew grants — client contact stays, the team
    /// roster and vinyl ordering are scoped away, and nothing is editable.
    /// Proves the gated rows drop out without leaving a stray separator.
    func testRenderDetailsTabCrewViewer() throws {
        let fixture = try makeFixture()
        withPermissions(crewGrants) {
            snapshot("details_tab_crew", view: hosted(fixture), height: 1200)
        }
    }

    /// The sparse project: no client, no address, no description, no tasks —
    /// every empty state at once, with edit permission so the invitations
    /// (ASSIGN / ADD DESCRIPTION) are the ones that render.
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
}
#endif
