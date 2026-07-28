//
//  SyncStatusPanelSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the redesigned notifications sync panel (bug dbada8f5).
//  Reconstructs the reporter's exact scenario — one queued "New task" plus two
//  vinyl-order updates stuck for 5 days — and renders the panel to PNGs via the
//  UIHostingController + UIWindow + drawHierarchy harness (dark, 390pt).
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class SyncStatusPanelSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 390

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-sync-panel-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // In-memory container so the seeded @Model operations are safe to mutate/read.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SyncOperation.self, configurations: config)
        return ModelContext(container)
    }

    private func op(
        entityType: String,
        operationType: String,
        fields: [String],
        status: String,
        error: String? = nil,
        retryCount: Int = 0,
        secondsAgo: TimeInterval,
        in context: ModelContext
    ) -> SyncOperation {
        let o = SyncOperation(
            entityType: entityType,
            entityId: UUID().uuidString.lowercased(),
            operationType: operationType,
            payload: Data(),
            changedFields: fields
        )
        o.status = status
        o.lastError = error
        o.retryCount = retryCount
        o.createdAt = Date().addingTimeInterval(-secondsAgo)
        context.insert(o)
        return o
    }

    // The reporter's scenario: 1 queued create + 2 failed vinyl updates (5d).
    private func seedReporterScenario(_ context: ModelContext) -> (pending: [SyncOperation], failed: [SyncOperation]) {
        let pending = op(entityType: "projectTask", operationType: "create",
                         fields: ["id", "task_type_id", "status", "project_id"],
                         status: "pending", secondsAgo: 2 * 3600, in: context)
        let vinyl1 = op(entityType: "project", operationType: "update",
                        fields: ["vinyl_ordered_by", "vinyl_order_status"],
                        status: "failed",
                        error: "Unexpected sync error: insert or update on table \"projects\" violates foreign key constraint",
                        retryCount: 4, secondsAgo: 5 * 86400, in: context)
        let vinyl2 = op(entityType: "project", operationType: "update",
                        fields: ["vinyl_order_id", "vinyl_ordered_by"],
                        status: "failed",
                        error: "Unexpected sync error: insert or update on table \"projects\" violates foreign key constraint",
                        retryCount: 4, secondsAgo: 5 * 86400, in: context)
        return ([pending], [vinyl1, vinyl2])
    }

    func testFixedPanelExpanded() throws {
        let context = try makeContext()
        let seeded = seedReporterScenario(context)
        snapshot("sync-panel-fixed-expanded") {
            SyncStatusPanel(
                pending: seeded.pending, failed: seeded.failed, isSyncing: false,
                isExpanded: .constant(true),
                onRetry: { _ in }, onRetryAll: { _ in }, onDismiss: { _ in }
            )
        }
    }

    func testFixedPanelCollapsed() throws {
        let context = try makeContext()
        let seeded = seedReporterScenario(context)
        snapshot("sync-panel-collapsed") {
            SyncStatusPanel(
                pending: seeded.pending, failed: seeded.failed, isSyncing: false,
                isExpanded: .constant(false),
                onRetry: { _ in }, onRetryAll: { _ in }, onDismiss: { _ in }
            )
        }
    }

    // MARK: - Render harness (drawHierarchy, not ImageRenderer — asset colors)

    private func snapshot<V: View>(_ name: String, @ViewBuilder _ content: () -> V) {
        let root = content()
            .frame(width: deviceWidth)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            // A UIWindow inherits the device safe-area insets whatever its frame —
            // without this the content renders displaced and bottom-clipped
            // (same correction as DaySheetRowSnapshotTests).
            .ignoresSafeArea()

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        let fitting = host.sizeThatFits(in: CGSize(width: deviceWidth, height: .greatestFiniteMagnitude))
        let size = CGSize(width: deviceWidth, height: max(fitting.height, 1) + 8)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = UIColor.black

        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let renderer = UIGraphicsImageRenderer(size: size)
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
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }
}
#endif
