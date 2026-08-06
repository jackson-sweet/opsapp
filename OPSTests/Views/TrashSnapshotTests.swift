//
//  TrashSnapshotTests.swift
//  OPSTests
//
//  Visual proof harness for the recovery ledger at compact, standard, and
//  accessibility widths. The production ledger content is rendered directly
//  from hand-built descriptors so the screenshots exercise the same segment,
//  row, thumbnail, dependency, and quick-view components used by TrashView.
//

#if DEBUG
import SwiftUI
import XCTest
@testable import OPS

@MainActor
final class TrashSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecoveryLedgerAtCompactAndStandardWidths() {
        let fixture = makeFixture()

        attach(
            "trash-ledger-320",
            image: render(width: 320, height: 700) {
                TrashRecoveryLedgerContent(
                    descriptors: fixture,
                    selectedSegment: .constant(.projects),
                    restoringID: nil,
                    onSelect: { _ in },
                    onRestore: { _ in }
                )
            }
        )

        attach(
            "trash-ledger-390",
            image: render(width: 390, height: 760) {
                TrashRecoveryLedgerContent(
                    descriptors: fixture,
                    selectedSegment: .constant(.projects),
                    restoringID: nil,
                    onSelect: { _ in },
                    onRestore: { _ in }
                )
            }
        )
    }

    func testRecoveryLedgerAtAccessibilityType() {
        let fixture = makeFixture()
        let image = render(width: 390, height: 844, dynamicType: .accessibility3) {
            TrashRecoveryLedgerContent(
                descriptors: fixture,
                selectedSegment: .constant(.tasks),
                restoringID: nil,
                onSelect: { _ in },
                onRestore: { _ in }
            )
        }

        attach("trash-ledger-accessibility", image: image)
    }

    func testParentRequiredQuickViewNamesCombinedRestore() {
        let descriptor = try! XCTUnwrap(makeFixture().first { $0.kind == .task })
        let image = render(width: 390, height: 520) {
            TrashRecoveryQuickView(
                descriptor: descriptor,
                isRestoring: false,
                errorMessage: nil,
                onRestore: {}
            )
        }

        attach("trash-parent-required-quick-view", image: image)
    }

    // MARK: - Fixture

    private func makeFixture() -> [TrashRecoveryRowDescriptor] {
        let client = Client(
            id: "client-1",
            name: "Morgan Lee With A Long Field Name",
            email: "morgan@example.com",
            phoneNumber: "250-555-0101",
            address: "101 Cedar Street, Victoria",
            companyId: "company-1"
        )
        client.profileImageURL = "https://example.com/morgan.jpg"
        client.deletedAt = now.addingTimeInterval(-172_800)

        let project = Project(id: "project-1", title: "Cedar deck and railing rebuild", status: .accepted)
        project.companyId = "company-1"
        project.address = "101 Cedar Street, Victoria"
        project.client = client
        project.clientId = client.id
        project.deletedAt = now.addingTimeInterval(-86_400)
        project.setProjectImageURLs(["https://example.com/cedar.jpg"])

        let task = ProjectTask(
            id: "task-1",
            projectId: project.id,
            taskTypeId: "type-1",
            companyId: "company-1"
        )
        task.customTitle = "Install guardrail posts and blocking"
        task.project = project
        task.deletedAt = now.addingTimeInterval(-3_600)

        return [
            .project(project, syncedPhotos: [], now: now),
            .client(client, now: now),
            .task(task, projects: [project], syncedPhotos: [], now: now),
        ]
    }

    // MARK: - Render harness

    private func render<V: View>(
        width: CGFloat,
        height: CGFloat,
        dynamicType: DynamicTypeSize = .large,
        @ViewBuilder content: () -> V
    ) -> UIImage {
        let root = content()
            .frame(width: width, height: height)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, dynamicType)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        host.view.backgroundColor = .black

        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    private func attach(_ name: String, image: UIImage) {
        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(nonBlackPixelCount(image), 0, "\(name) rendered blank")
    }

    private func nonBlackPixelCount(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        var index = 0
        while index + 2 < pixels.count {
            if pixels[index] > 24 || pixels[index + 1] > 24 || pixels[index + 2] > 24 {
                count += 1
            }
            index += 4
        }
        return count
    }
}
#endif
