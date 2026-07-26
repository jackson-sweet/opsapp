//
//  TaskDetailPopupSheetTests.swift
//  OPSTests
//
//  Regression coverage for the Project Details task sheet description area.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class TaskDetailPopupSheetTests: XCTestCase {

    func testMeaningfulDescriptionIsTrimmedAndPreserved() {
        let presentation = TaskDetailDescriptionPresentation(
            notes: "  Protect the finished fascia before fastening the rail.  "
        )

        XCTAssertEqual(
            presentation.text,
            "Protect the finished fascia before fastening the rail."
        )
        XCTAssertFalse(presentation.isEmpty)
    }

    func testMissingDescriptionUsesEmDash() {
        for notes in [nil, "", "   \n\t"] as [String?] {
            let presentation = TaskDetailDescriptionPresentation(notes: notes)

            XCTAssertEqual(presentation.text, "—")
            XCTAssertTrue(presentation.isEmpty)
        }
    }

    func testRenderExpandedSheetWithDescription() {
        snapshot(
            "task_detail_expanded_with_description",
            notes: """
            Protect finished fascia before fastening the rail. Confirm every \
            post is plumb, keep the gate opening clear, and photograph the \
            completed run before leaving site.
            """
        )
    }

    func testRenderExpandedSheetWithoutDescription() {
        snapshot("task_detail_expanded_without_description", notes: nil)
    }

    private func snapshot(_ name: String, notes: String?) {
        let task = ProjectTask(
            id: "task-detail-sheet-\(name)",
            projectId: "project-task-detail-sheet",
            taskTypeId: "task-type-vinyl-install",
            companyId: "company-task-detail-sheet",
            status: .active,
            taskColor: "#6F94B0"
        )
        task.customTitle = "VINYL INSTALL"
        task.taskNotes = notes
        task.startDate = Date(timeIntervalSince1970: 1_782_345_600)
        task.endDate = Date(timeIntervalSince1970: 1_782_345_600)

        let size = CGSize(width: 393, height: 852)
        let host = UIHostingController(
            rootView: TaskDetailSheetSnapshotHarness(task: task)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black

        let window: UIWindow
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }

        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }

        XCTAssertGreaterThan(data.count, 1_000)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}

private struct TaskDetailSheetSnapshotHarness: View {
    let task: ProjectTask

    @State private var selectedTeamMemberIds: Set<String> = []

    var body: some View {
        TaskDetailPopupSheet(
            task: task,
            onSelect: { _ in },
            onComplete: { _ in },
            onReschedule: { _ in },
            onCancel: { _ in },
            onScheduleTap: nil,
            selectedTeamMemberIds: $selectedTeamMemberIds,
            allTeamMembers: []
        )
    }
}
#endif
