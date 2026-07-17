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

    private func boardView(container: ModelContainer) -> some View {
        VinylOrdersBoardView()
            .environmentObject(DataController())
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

    func testRenderBoardStates() throws {
        let container = try makeContainer()

        // Both groups, glance state.
        renderToPNG("vinyl-board-groups") {
            boardView(container: container)
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
                makeCommitItems: { [] },
                onBack: {},
                onCommitted: { _, _ in }
            )
            .environmentObject(DataController())
            .background(OPSStyle.Colors.background)
            .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    // MARK: - Harness (UIHostingController + drawHierarchy — never ImageRenderer)

    private func renderToPNG(_ name: String, @ViewBuilder _ make: () -> some View) {
        let host = UIHostingController(rootView: make().frame(width: frameSize.width, height: frameSize.height))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

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
