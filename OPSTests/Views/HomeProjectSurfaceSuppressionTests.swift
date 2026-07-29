//
//  HomeProjectSurfaceSuppressionTests.swift
//  OPSTests
//
//  Bug de9099d6 — the Home supporting cards (billable rollup + needs-tasks
//  strip) stayed on screen behind the map's project pin card, the stacked-group
//  sheet, and the project details surface. They sit in a layer ABOVE the map,
//  so a presented project surface read as "cards floating over a sheet".
//
//  The existing suppressor, `isInProjectMode`, is deliberately FALSE while a
//  project is merely being VIEWED (`isViewingDetailsOnly`), which is exactly
//  the state every one of those surfaces is presented in — hence a second,
//  narrower signal: `isProjectSurfacePresented`.
//

import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class HomeProjectSurfaceSuppressionTests: XCTestCase {

    // MARK: - The AppState signal

    func testNoProjectSurfaceIsPresentedOnAFreshState() {
        let state = AppState()
        XCTAssertFalse(state.isProjectSurfacePresented)
    }

    /// The map pin card / stacked-group sheet raise the flag. The map
    /// coordinator is a private `@StateObject` inside `OPSMapContainer`, so the
    /// container mirrors its card visibility onto AppState — this is the seam
    /// Home observes.
    func testMapProjectCardPresentsAProjectSurface() {
        let state = AppState()
        state.isMapProjectSurfacePresented = true
        XCTAssertTrue(state.isProjectSurfacePresented)
    }

    /// The project details surface counts too, and it is the case
    /// `isInProjectMode` misses: viewing details sets `isViewingDetailsOnly`,
    /// which makes `isInProjectMode` false.
    func testProjectDetailsPresentsAProjectSurfaceEvenThoughProjectModeIsFalse() {
        let state = AppState()
        state.isViewingDetailsOnly = true
        state.activeProjectID = "project-1"
        state.showProjectDetails = true

        XCTAssertFalse(state.isInProjectMode, "viewing details is not project mode — the old suppressor's blind spot")
        XCTAssertTrue(state.isProjectSurfacePresented)
    }

    /// Tapping DETAILS on the pin card closes the card and *then* raises the
    /// details surface a runloop later (`showProjectDetailsAfterResetById`
    /// arms `isViewingDetailsOnly` + `activeProjectID` synchronously and flips
    /// `showProjectDetails` after a 0.1s hop). If the signal only read
    /// `showProjectDetails`, the cards would fade back in during that gap and
    /// immediately back out — a visible flicker on the most common path into
    /// details. The arming window counts as presented.
    func testDetailsArmingWindowCountsAsPresented() {
        let state = AppState()
        state.isMapProjectSurfacePresented = true

        // The pin card closes first…
        state.isMapProjectSurfacePresented = false
        // …and the details request arms synchronously, sheet still to come.
        state.isViewingDetailsOnly = true
        state.activeProjectID = "project-1"
        XCTAssertFalse(state.showProjectDetails, "the sheet has not raised yet — this is the gap")

        XCTAssertTrue(
            state.isProjectSurfacePresented,
            "the cards must not flash back in between the pin card closing and details opening"
        )
    }

    /// Dismissing the map card restores the cards — the flag must not latch.
    /// (`OPSMapCoordinator.deselectAll()` clears the card, the container
    /// mirrors the clear across.)
    func testDismissingEveryProjectSurfaceRestoresTheCards() {
        let state = AppState()
        state.isMapProjectSurfacePresented = true
        state.showProjectDetails = true
        XCTAssertTrue(state.isProjectSurfacePresented)

        state.isMapProjectSurfacePresented = false
        XCTAssertTrue(state.isProjectSurfacePresented, "details is still up")

        state.showProjectDetails = false
        XCTAssertFalse(state.isProjectSurfacePresented)
    }

    /// Details dismissal runs through `dismissProjectDetails()` in the product
    /// path, not a raw property write — prove that clears the signal too.
    func testDismissProjectDetailsClearsTheSignal() {
        let state = AppState()
        state.isViewingDetailsOnly = true
        state.activeProjectID = "project-1"
        state.showProjectDetails = true
        XCTAssertTrue(state.isProjectSurfacePresented)

        state.dismissProjectDetails()
        XCTAssertFalse(state.isProjectSurfacePresented)
    }

    /// Logout resets it — a stale true would hide the cards for the next user.
    func testLogoutResetClearsTheSignal() {
        let state = AppState()
        state.isMapProjectSurfacePresented = true
        state.showProjectDetails = true

        state.resetForLogout()
        XCTAssertFalse(state.isProjectSurfacePresented)
    }

    // MARK: - What Home does with it

    /// The supporting cards yield the screen to any presented project surface,
    /// and to project mode as before.
    func testSupportingCardsYieldToAPresentedProjectSurface() {
        XCTAssertTrue(
            HomeContentView.supportingCardsVisible(isInProjectMode: false, isProjectSurfacePresented: false),
            "plain browsing map — the cards are the whole point"
        )
        XCTAssertFalse(
            HomeContentView.supportingCardsVisible(isInProjectMode: false, isProjectSurfacePresented: true),
            "a pin card / stacked group / details surface owns the screen"
        )
        XCTAssertFalse(
            HomeContentView.supportingCardsVisible(isInProjectMode: true, isProjectSurfacePresented: false),
            "project mode still suppresses them, unchanged"
        )
        XCTAssertFalse(
            HomeContentView.supportingCardsVisible(isInProjectMode: true, isProjectSurfacePresented: true)
        )
    }

    // MARK: - Visual proof
    //
    // Renders the REAL supporting cards in the REAL slot order (filter chips →
    // billable → needs-tasks → Spacer, exactly as `contentOverlay` stacks
    // them), gated by the REAL `supportingCardsVisible` predicate reading a
    // REAL AppState, over the REAL `ProjectPinCard`. Captured at both a
    // standard and an SE-class width so the "does the filter row hop when the
    // cards leave?" question is answerable from the pixels.

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-home-project-surface-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeContainer() throws -> (ModelContainer, Project) {
        // The full relationship closure reachable from Project — SwiftData
        // rejects a container whose schema omits a related model.
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let project = Project(id: "p-1", title: "6836 Mark Ln", status: .inProgress)
        project.companyId = "co-1"
        project.address = "6836 Mark Ln, Victoria"
        context.insert(project)
        return (container, project)
    }

    private var billableRollup: HomeBillableThisWeekRollup {
        HomeBillableThisWeekRollup(
            weekStart: Date(timeIntervalSince1970: 1_780_000_000),
            weekEnd: Date(timeIntervalSince1970: 1_780_500_000),
            closingThisWeek: [
                HomeBillableProjectCandidate(
                    id: "closing-c1", projectId: "c1", title: "972 Lyall St",
                    section: .closingThisWeek, taskCount: 3, amount: 8_400,
                    invoiceId: "inv-c1", estimateId: nil, latestTaskEnd: nil
                )
            ],
            readyToBill: []
        )
    }

    /// The supporting-card slot as `contentOverlay` composes it, with a
    /// stand-in for the map underneath and the pin card over the top.
    private struct HomeSlotHarness: View {
        @ObservedObject var appState: AppState
        let rollup: HomeBillableThisWeekRollup
        let project: Project
        @State private var filterMode: MapFilterMode = .today

        var body: some View {
            ZStack {
                OPSStyle.Colors.background

                VStack(spacing: 0) {
                    MapFilterChips(filterMode: $filterMode)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing1)

                    if HomeContentView.supportingCardsVisible(
                        isInProjectMode: appState.isInProjectMode,
                        isProjectSurfacePresented: appState.isProjectSurfacePresented
                    ) {
                        HomeBillableThisWeekCard(rollup: rollup, onSelect: { _ in })
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing1)

                        HomeNeedsTasksStrip(count: 3, onOpen: {})
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing1)
                    }

                    Spacer()
                }

                if appState.isMapProjectSurfacePresented {
                    VStack {
                        Spacer()
                        ProjectPinCard(
                            project: project,
                            todaysTasks: [],
                            teamMembers: [],
                            onNavigate: {},
                            onDetails: {},
                            onDismiss: {}
                        )
                        .padding(.bottom, 90)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func capture(_ name: String, size: CGSize, appState: AppState, project: Project) {
        let host = UIHostingController(rootView:
            HomeSlotHarness(appState: appState, rollup: billableRollup, project: project)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        host.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@\(Int(image.scale))x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    /// iPhone 17 (standard) and iPhone SE (the tightest supported height) —
    /// the SE frame is where a card that refuses to yield collides with the
    /// pin card, and where a filter-row hop would be most visible.
    func testRenderSupportingCardsBesideAndBehindTheProjectPinCard() throws {
        let (_, project) = try makeContainer()

        for (label, size) in [
            ("standard", CGSize(width: 393, height: 852)),
            ("se", CGSize(width: 375, height: 667))
        ] {
            let browsing = AppState()
            capture("home_cards_visible_\(label)", size: size, appState: browsing, project: project)

            let presenting = AppState()
            presenting.isMapProjectSurfacePresented = true
            capture("home_cards_hidden_behind_pin_card_\(label)", size: size, appState: presenting, project: project)
        }
    }
}
