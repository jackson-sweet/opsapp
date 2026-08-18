//
//  VinylOrdersBoardSnapshotTests.swift
//  OPSTests
//
//  Visual-proof harness for the VINYL ORDERS board + bulk order wizard.
//  Renders the real views to PNGs via UIHostingController + UIWindow +
//  drawHierarchy (ImageRenderer is banned — asset colors render yellow and
//  the SwiftUI lifecycle never runs). NOT pass/fail: writes images for
//  inspection and the docs/artifacts copy.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/VinylOrdersBoardSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class VinylOrdersBoardSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 852)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-vinyl-orders-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

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
            ProjectVinylOrderMarker.self,
            DeckDesign.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let vinylType = TaskType(id: "tt-vinyl", display: "Vinyl Install", color: "#6F94B0", companyId: "co-1")
        context.insert(vinylType)

        func seedProject(
            id: String,
            title: String,
            status: Status,
            taskStart: Date?,
            ordered: Bool,
            orderedAt: Date? = nil,
            color: String? = nil,
            po: String? = nil,
            address: String? = nil
        ) {
            let project = Project(id: id, title: title, status: status)
            project.companyId = "co-1"
            project.address = address
            context.insert(project)

            let task = ProjectTask(
                id: "task-\(id)",
                projectId: id,
                taskTypeId: "tt-vinyl",
                companyId: "co-1",
                status: .active
            )
            task.startDate = taskStart
            context.insert(task)
            project.tasks.append(task)

            let marker = ProjectVinylOrderMarker(
                projectId: id,
                status: ordered ? .ordered : .notOrdered,
                orderedAt: orderedAt,
                orderedBy: nil,
                vinylColor: color,
                vinylPO: po
            )
            context.insert(marker)
        }

        seedProject(
            id: "p-1", title: "6836 Mark Ln", status: .inProgress,
            taskStart: Date(timeIntervalSince1970: 1_784_600_000),
            ordered: false, address: "6836 Mark Ln, Victoria"
        )
        seedProject(
            id: "p-2", title: "303 Stevens", status: .accepted,
            taskStart: nil,
            ordered: false, address: "303 Stevens Rd"
        )
        seedProject(
            id: "p-3", title: "45 Bayview", status: .inProgress,
            taskStart: Date(timeIntervalSince1970: 1_784_300_000),
            ordered: true, orderedAt: Date(timeIntervalSince1970: 1_784_200_000),
            color: "68mil Cobblestone", po: "PO 45 Bayview",
            address: "45 Bayview Ave"
        )
        seedProject(
            id: "p-4", title: "88 Ridge Rd", status: .accepted,
            taskStart: nil,
            ordered: true, orderedAt: Date(timeIntervalSince1970: 1_784_100_000),
            color: "68mil Slate",
            address: "88 Ridge Rd"
        )

        try context.save()
        return container
    }

    private func grantedPermissions() -> PermissionStore {
        let permissions = PermissionStore()
        permissions.permissions = [
            "projects.edit": "all",
            "deck_builder.view": "assigned"
        ]
        return permissions
    }

    /// The four fixture rows as plain inputs — same facts the container
    /// carries (proven equivalent by testFixtureAssemblesBoardInputs). The
    /// offscreen harness cannot drive @Query, so renders go through the
    /// board's preview seam.
    private func fixtureInputs() -> [VinylBoardRowInput] {
        [
            VinylBoardRowInput(
                projectId: "p-1", title: "6836 Mark Ln", status: .inProgress,
                vinylTaskStartDates: [Date(timeIntervalSince1970: 1_784_600_000)],
                hasIncompleteVinylTask: true, createdAt: nil,
                ordered: false, orderedAt: nil
            ),
            VinylBoardRowInput(
                projectId: "p-2", title: "303 Stevens", status: .accepted,
                vinylTaskStartDates: [nil],
                hasIncompleteVinylTask: true, createdAt: nil,
                ordered: false, orderedAt: nil
            ),
            VinylBoardRowInput(
                projectId: "p-3", title: "45 Bayview", status: .inProgress,
                vinylTaskStartDates: [Date(timeIntervalSince1970: 1_784_300_000)],
                hasIncompleteVinylTask: true, createdAt: nil,
                ordered: true, orderedAt: Date(timeIntervalSince1970: 1_784_200_000)
            ),
            VinylBoardRowInput(
                projectId: "p-4", title: "88 Ridge Rd", status: .accepted,
                vinylTaskStartDates: [nil],
                hasIncompleteVinylTask: true, createdAt: nil,
                ordered: true, orderedAt: Date(timeIntervalSince1970: 1_784_100_000)
            )
        ]
    }

    private func boardView(container: ModelContainer, inputs: [VinylBoardRowInput]) -> some View {
        // The board scopes vinyl task types by the signed-in operator's
        // company — seed one or every fixture project falls out of scope.
        let dataController = DataController()
        dataController.currentUser = User(
            id: "user-1",
            firstName: "Jackson",
            lastName: "Sweet",
            role: .admin,
            companyId: "co-1"
        )
        return VinylOrdersBoardView(fixedInputs: inputs)
            .environmentObject(dataController)
            .environmentObject(grantedPermissions())
            .environmentObject(AppState())
            .modelContainer(container)
            .frame(width: frameSize.width, height: frameSize.height)
    }

    /// A 12'×20' rect vinyl surface — real cut geometry for the wizard page.
    private func rectSurface() -> VinylOrderSurfaceInput {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let ids = ["v1", "v2", "v3", "v4"]
        let dims = [144.0, 240.0, 144.0, 240.0]
        let edges = (0..<4).map { i in
            VinylOrderSurfaceEdge(
                id: "e\(i)", start: p[i], end: p[(i + 1) % 4],
                edgeType: i == 3 ? .houseEdge : .deckEdge, label: nil,
                startVertexId: ids[i], endVertexId: ids[(i + 1) % 4],
                isParapet: false, dimensionInches: dims[i]
            )
        }
        return VinylOrderSurfaceInput(id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0, edges: edges)
    }

    private func wizardContext() -> VinylBulkOrderWizardContext {
        let design = DeckDesign(companyId: "co-1", title: "6836 Mark Ln")
        var drawingData = design.drawingData
        var materialsSettings = drawingData.materialsSettings ?? DeckMaterialsSettings()
        materialsSettings.orderMode = .fullRolls
        materialsSettings.fullRollLengthFeet = 75
        drawingData.materialsSettings = materialsSettings
        design.drawingData = drawingData

        let resolved = DeckMaterialsResolver.Resolved(
            scale: 1.0,
            vinylInputs: [rectSurface()],
            materials: nil
        )
        let job = VinylBulkOrderJob(
            projectId: "p-1",
            title: "6836 Mark Ln",
            design: design,
            resolved: resolved,
            facesByLevel: [],
            taskTypeDisplays: ["Vinyl Install"],
            degenerateReason: nil
        )
        return VinylBulkOrderWizardContext(companyId: "co-1", userId: "user-1", jobs: [job])
    }

    // MARK: - Renders

    /// Container-truth check: the seeded fixture must survive fetch exactly as
    /// the board's assembly reads it — projects, linked vinyl tasks, markers.
    func testFixtureAssemblesBoardInputs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskTypes = try context.fetch(FetchDescriptor<TaskType>())
        let vinylIds = VinylTaskFilter.vinylTaskTypeIds(
            displaysById: Dictionary(taskTypes.map { ($0.id, $0.display) }, uniquingKeysWith: { a, _ in a })
        )
        XCTAssertEqual(vinylIds, ["tt-vinyl"])

        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 4)
        for project in projects {
            XCTAssertEqual(project.tasks.count, 1, "\(project.id) lost its vinyl task link")
        }

        let markers = try context.fetch(FetchDescriptor<ProjectVinylOrderMarker>())
        XCTAssertEqual(markers.count, 4)

        let inputs = projects.map { project in
            let incomplete = project.tasks.filter {
                $0.deletedAt == nil && $0.status != .completed && vinylIds.contains($0.taskTypeId)
            }
            let marker = markers.first { $0.projectId == project.id }
            return VinylBoardRowInput(
                projectId: project.id,
                title: project.title,
                status: project.status,
                vinylTaskStartDates: incomplete.map(\.startDate),
                hasIncompleteVinylTask: !incomplete.isEmpty,
                createdAt: project.createdAt,
                ordered: marker?.isOrdered ?? false,
                orderedAt: marker?.orderedAt
            )
        }
        let rows = VinylOrdersBoardModel.rows(from: inputs)
        XCTAssertEqual(rows.toOrder.map(\.projectId), ["p-1", "p-2"])
        XCTAssertEqual(rows.ordered.map(\.projectId), ["p-3", "p-4"])
    }

    func testRenderBoardStates() throws {
        let container = try makeContainer()

        // Both groups, glance state.
        renderToPNG("vinyl-board-groups") {
            boardView(container: container, inputs: fixtureInputs())
        }

        // Empty board.
        renderToPNG("vinyl-board-empty") {
            boardView(container: container, inputs: [])
        }
    }

    /// Expanded ordered row — the order record with snapshot-first values.
    func testRenderExpandedOrderedRow() {
        let marker = ProjectVinylOrderMarker(
            projectId: "p-3",
            status: .ordered,
            orderedAt: Date(timeIntervalSince1970: 1_784_200_000),
            orderedBy: nil,
            vinylColor: "68mil Cobblestone",
            vinylPO: "PO 45 Bayview"
        )
        let project = Project(id: "p-3", title: "45 Bayview", status: .inProgress)
        project.address = "45 Bayview Ave, Victoria"
        let snapshot = DeckMaterialsSnapshot(
            orderedAt: Date(timeIntervalSince1970: 1_784_200_000),
            orderedBy: "user-1",
            settings: DeckMaterialsSettings(),
            vinylSettings: .default,
            vinylColor: "68mil Cobblestone",
            vinylOrderedSqFt: 412,
            vinylSurfaceAreaSqFt: 388,
            cutGroups: [
                DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 9, lengthInches: 108, rollWidthInches: 72),
                DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 2, lengthInches: 156, rollWidthInches: 72)
            ],
            dripEdgeFeet: 44, dripSticks: 6,
            clipFeet: 44, clipSticks: 5,
            ninetyFeet: 20, ninetySticks: 3,
            glueAreaSqFt: 388, glueBuckets: 1,
            vinylSurfaceCount: 1,
            po: "PO 45 Bayview"
        )

        renderToPNG("vinyl-board-expanded-row") {
            VStack {
                VinylOrderRowDetail(
                    input: self.fixtureInputs()[2],
                    project: project,
                    marker: marker,
                    snapshot: snapshot,
                    onOpenProject: {},
                    onClearOrdered: {}
                )
                Spacer(minLength: 0)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .frame(width: self.frameSize.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }
    }

    func testRenderWizardCutPage() {
        renderToPNG("vinyl-wizard-cut-page") {
            VinylBulkOrderWizardView(context: wizardContext(), onCommitted: { _, _ in })
                .environmentObject(DataController())
                .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    func testRenderSendPage() {
        let sections = [
            VinylBulkOrderSection(
                po: "6836 Mark Ln",
                color: "68mil Cobblestone",
                cutLines: ["-9 @ 9'", "-2 @ 13'"],
                rollsLine: nil
            ),
            VinylBulkOrderSection(
                po: "303 Stevens",
                color: "68mil Hansberry",
                cutLines: ["-2 @ 26'", "-4 @ 13' 6\""],
                rollsLine: nil
            )
        ]
        let needs = [
            VinylConsumableNeed(dripSticks: 24, ninetySticks: 8, clipSticks: 20, glueAreaSqFt: 480, glueCoverageSqFt: 400),
            VinylConsumableNeed(dripSticks: 20, ninetySticks: 4, clipSticks: 20, glueAreaSqFt: 520, glueCoverageSqFt: 400)
        ]

        renderToPNG("vinyl-wizard-send-page") {
            VinylBulkOrderSendPageView(
                context: VinylBulkOrderWizardContext(companyId: "co-1", userId: "user-1", jobs: []),
                sections: sections,
                needs: needs,
                // Takes the operator's FINAL purchased consumable counts, and is
                // called only at COMMIT — which a render never reaches.
                makeCommitItems: { _ in [] },
                onBack: {},
                onCommitted: { _, _ in }
            )
            .environmentObject(DataController())
            .background(OPSStyle.Colors.background)
            .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    // MARK: - Harness (UIHostingController + drawHierarchy — never ImageRenderer)

    private func renderToPNG(_ name: String, settle: TimeInterval = 0.6, @ViewBuilder _ make: () -> some View) {
        // A UIWindow inherits the device safe-area insets whatever its frame —
        // ignoring safe area keeps the board at its natural origin instead of
        // displaced down with the wizard CTAs bottom-clipped
        // (same correction as DaySheetRowSnapshotTests).
        let host = UIHostingController(rootView: make().frame(width: frameSize.width, height: frameSize.height).ignoresSafeArea())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: settle))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
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
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }
}
#endif
