//
//  TaskTypeSettingsSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the compact Task Types settings overhaul. Renders the
//  production index, create sheet, and usage manager at an iPhone 390×844
//  viewport through UIHostingController + UIWindow + drawHierarchy so asset
//  colors and SwiftUI lifecycle work match the running app.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/TaskTypeSettingsSnapshotTests
//
//  Shots land in NSTemporaryDirectory()/ops-task-type-settings-shots/.
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class TaskTypeSettingsSnapshotTests: XCTestCase {

    private let deviceSize = CGSize(width: 390, height: 844)
    private let companyId = "company-task-type-snapshot"

    private struct TypeSpec {
        let id: String
        let display: String
        let color: String
        let isDefault: Bool
    }

    private struct Fixture {
        let container: ModelContainer
        let dataController: DataController
        let taskTypes: [TaskType]
    }

    private var outDir: URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-task-type-settings-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private var typeSpecs: [TypeSpec] {
        [
            TypeSpec(
                id: "tt-cleanup",
                display: "Cleanup",
                color: "#979CA0",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-electrical",
                display: "Electrical",
                color: "#8595AA",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-framing",
                display: "Framing",
                color: "#7A6455",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-materials",
                display: "Materials",
                color: "#A79473",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-punch-list",
                display: "Punch List",
                color: "#748284",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-service",
                display: "Service",
                color: "#6F9587",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-site-prep",
                display: "Site Prep",
                color: "#8B534E",
                isDefault: false
            ),
            TypeSpec(
                id: "tt-installation",
                display: "Installation",
                color: "#5D8CAE",
                isDefault: true
            ),
            TypeSpec(
                id: "tt-quote",
                display: "Quote",
                color: "#89729E",
                isDefault: true
            ),
        ]
    }

    private func makeFixture(taskCounts: [Int]) throws -> Fixture {
        XCTAssertEqual(
            taskCounts.count,
            typeSpecs.count,
            "Every task type fixture needs an explicit count"
        )

        let schema = Schema(versionedSchema: OPSSchemaV19.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext

        let user = User(
            id: "user-task-type-snapshot",
            firstName: "Jackson",
            lastName: "Sweet",
            role: .admin,
            companyId: companyId
        )
        context.insert(user)

        let clients = [
            Client(
                id: "client-mollberg",
                name: "Mollberg Residence",
                companyId: companyId
            ),
            Client(
                id: "client-harmon",
                name: "Harmon Builders",
                companyId: companyId
            ),
            Client(
                id: "client-calloway",
                name: "Calloway Properties",
                companyId: companyId
            ),
            Client(
                id: "client-ridge",
                name: "Ridge Contracting",
                companyId: companyId
            ),
        ]
        clients.forEach { context.insert($0) }

        let projectTitles = [
            "6836 Mark Lane",
            "45 Bayview",
            "Oak Street Retrofit",
            "Ridge Road Service",
        ]
        let projects = zip(projectTitles.indices, projectTitles).map { index, title in
            let project = Project(
                id: "project-\(index + 1)",
                title: title,
                status: .inProgress
            )
            project.companyId = companyId
            project.clientId = clients[index].id
            project.client = clients[index]
            context.insert(project)
            return project
        }

        let taskTitles = [
            "Final site cleanup",
            "Remove protection",
            "Load waste bin",
            "Sweep main level",
            "Haul surplus material",
            "Vacuum millwork",
            "Clean exterior access",
            "Close deficiency list",
        ]
        let statuses: [TaskStatus] = [.active, .active, .completed, .cancelled]

        var taskTypes: [TaskType] = []
        for (typeIndex, spec) in typeSpecs.enumerated() {
            let taskType = TaskType(
                id: spec.id,
                display: spec.display,
                color: spec.color,
                companyId: companyId,
                isDefault: spec.isDefault
            )
            taskType.displayOrder = typeIndex
            context.insert(taskType)
            taskTypes.append(taskType)

            for taskIndex in 0..<taskCounts[typeIndex] {
                let project = projects[taskIndex % projects.count]
                let task = ProjectTask(
                    id: "task-\(typeIndex)-\(taskIndex)",
                    projectId: project.id,
                    taskTypeId: taskType.id,
                    companyId: companyId,
                    status: statuses[taskIndex % statuses.count],
                    taskColor: taskType.color
                )
                task.customTitle = typeIndex == 0
                    ? taskTitles[taskIndex % taskTitles.count]
                    : "\(taskType.display) \(taskIndex + 1)"
                task.taskType = taskType
                task.project = project
                context.insert(task)
            }
        }

        try context.save()

        let dataController = DataController()
        dataController.currentUser = user

        return Fixture(
            container: container,
            dataController: dataController,
            taskTypes: taskTypes
        )
    }

    func testTaskTypeIndexCompactDensityAndBothAddActions() throws {
        // Mirrors the live aggregate: 294 non-deleted tasks across a dense,
        // mixed custom/default list. Nine rows leave the terminal add row
        // visible in the same 390×844 frame as the header add control.
        let counts = [101, 52, 39, 31, 24, 18, 15, 9, 5]
        let fixture = try makeFixture(taskCounts: counts)
        let context = fixture.container.mainContext

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<TaskType>()),
            typeSpecs.count
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ProjectTask>()),
            294
        )

        snapshot("task-type-settings-index") {
            TaskSettingsView()
                .environmentObject(fixture.dataController)
                .modelContainer(fixture.container)
        }
    }

    func testTaskTypeCreateSheetCompactForm() throws {
        let fixture = try makeFixture(
            taskCounts: Array(repeating: 0, count: typeSpecs.count)
        )

        snapshot("task-type-create-sheet") {
            TaskTypeSheet(mode: .create(onSave: { _ in }))
                .environmentObject(fixture.dataController)
                .modelContainer(fixture.container)
        }
    }

    func testTaskTypeUsageSheetShowsCompactTaskContext() throws {
        let fixture = try makeFixture(
            taskCounts: [24, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        let source = try XCTUnwrap(
            fixture.taskTypes.first(where: { $0.id == "tt-cleanup" })
        )

        snapshot("task-type-usage-sheet") {
            TaskTypeUsageSheet(
                source: source,
                allCompanyTypes: fixture.taskTypes
            )
            .environmentObject(fixture.dataController)
            .modelContainer(fixture.container)
        }
    }

    private func snapshot<V: View>(
        _ name: String,
        settle: TimeInterval = 0.5,
        @ViewBuilder content: () -> V
    ) {
        let root = content()
            .frame(width: deviceSize.width, height: deviceSize.height)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: deviceSize)
        host.view.backgroundColor = .black

        let window: UIWindow
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        if let scene = scenes.first(where: {
            $0.activationState == .foregroundActive
        }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: deviceSize)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: deviceSize))
        }

        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(
            bounds: window.bounds,
            format: format
        ).image { _ in
            window.drawHierarchy(
                in: window.bounds,
                afterScreenUpdates: true
            )
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }

        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)

        do {
            try data.write(
                to: outDir.appendingPathComponent("\(name)@3x.png"),
                options: .atomic
            )
        } catch {
            XCTFail("Failed to write \(name): \(error)")
        }

        XCTAssertEqual(image.size, deviceSize)
        XCTAssertGreaterThan(
            data.count,
            1_000,
            "\(name): rendered PNG is unexpectedly sparse"
        )
        print(
            "📸 SNAPSHOT \(name) "
                + "(\(Int(image.size.width))×\(Int(image.size.height))pt)"
        )
    }
}
#endif
