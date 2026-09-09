//
//  UnlinkedInboxRowSnapshotTests.swift
//  OPSTests
//
//  Visual proof for bug 589e3b1e — the one row that replaces a wall of
//  identical "Reply waiting, no owner" notifications that all dead-tapped.
//  Rendered through the AppHostWindow-backed FixedSizeSnapshot harness (dark,
//  390pt), so a blank window cannot pass as a snapshot.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class UnlinkedInboxRowSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 390

    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat,
        @ViewBuilder content: () -> V
    ) throws {
        let image = try FixedSizeSnapshot.render(
            content()
                .frame(width: deviceWidth, alignment: .top)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: height)
        )
        guard let data = image.pngData() else {
            return XCTFail("Failed to render \(name)")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SNAPSHOT \(name) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
    }

    /// The production pile: 85 persistent "Reply waiting, no owner" rows whose
    /// threads carry no lead. Every member is persistent, so the row offers no
    /// MARK READ — it states the truth, names what it replaced, and points at
    /// the surface that can act on it.
    private var productionGroup: UnlinkedInboxGroup {
        UnlinkedInboxGroup(
            memberIds: (1...85).map { "n\($0)" },
            newestCreatedAt: "2026-09-09T00:44:37.303224+00:00",
            unreadCount: 85,
            isMarkReadPermitted: false,
            sources: [.init(title: "Reply waiting, no owner", count: 85)]
        )
    }

    /// A mixed, clearable pile — the state-aware branch: two distinct sources
    /// in the readout, and no persistent member, so MARK READ is honest.
    private var mixedClearableGroup: UnlinkedInboxGroup {
        UnlinkedInboxGroup(
            memberIds: (1...9).map { "n\($0)" },
            newestCreatedAt: "2026-09-09T00:44:37.303224+00:00",
            unreadCount: 9,
            isMarkReadPermitted: true,
            sources: [
                .init(title: "Reply waiting, no owner", count: 6),
                .init(title: "Email files need review", count: 3)
            ]
        )
    }

    private func row(_ group: UnlinkedInboxGroup, expanded: Bool) -> some View {
        UnlinkedInboxRow(
            group: group,
            timestamp: "2h",
            isExpanded: expanded,
            onToggle: {},
            onMarkRead: {}
        )
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    func testGroupedRowCollapsed() throws {
        try snapshot("unlinked-inbox-row-collapsed", height: 120) {
            row(productionGroup, expanded: false)
        }
    }

    func testGroupedRowExpanded() throws {
        try snapshot("unlinked-inbox-row-expanded", height: 210) {
            row(productionGroup, expanded: true)
        }
    }

    func testGroupedRowExpandedWithBreakdownAndMarkRead() throws {
        try snapshot("unlinked-inbox-row-expanded-mixed", height: 320) {
            row(mixedClearableGroup, expanded: true)
        }
    }

    /// The before/after the founder actually saw: five identical dead-tapping
    /// rows versus the single row that replaces them.
    func testRailBeforeAndAfter() throws {
        try snapshot("unlinked-inbox-rail-before", height: 420) {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    NotificationRowChrome(
                        title: "Reply waiting, no owner",
                        bodyText: Text("OPS did not draft this customer reply because no one is assigned to the lead.")
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundStyle(OPSStyle.Colors.secondaryText),
                        bodyAccessibilityLabel: "",
                        timestamp: "2h",
                        isRead: false,
                        isExpanded: false,
                        onToggle: {},
                        icon: {
                            NotificationIconBadge(
                                systemName: "arrowshape.turn.up.left",
                                tint: OPSStyle.Colors.warningStatus
                            )
                        },
                        detail: { EmptyView() }
                    )
                }
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }

        try snapshot("unlinked-inbox-rail-after", height: 120) {
            row(productionGroup, expanded: false)
        }
    }
}
#endif
