//
//  ActivityFeedSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the Project Details activity-feed / photos workstream (I2):
//  the photo-comment card, the redesigned site-visit packet card, the
//  status-change system line, and the carousel comment badge.
//
//  Uses the UIHostingController + UIWindow + drawHierarchy(afterScreenUpdates:)
//  harness — NOT ImageRenderer, which resolves asset-catalog colors to yellow
//  and skips onAppear. A rendering harness for human/agent inspection, not an
//  assertion test.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ActivityFeedSnapshotTests \
//          -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-local
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class ActivityFeedSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-activity-feed-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Render a view to a PNG via a real window + drawHierarchy so asset-catalog
    /// colors resolve correctly (ImageRenderer renders them yellow).
    private func snapshot<V: View>(_ name: String, width: CGFloat? = nil, @ViewBuilder _ content: () -> V) {
        let w = width ?? deviceWidth
        let root = content()
            .frame(width: w)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        let fitting = host.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude))
        // +8pt headroom so wrapped last-line descenders never clip.
        let size = CGSize(width: w, height: max(fitting.height, 1) + 8)
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
        attachment.name = "\(name)@\(Int(UIScreen.main.scale))x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Seed helpers

    private func note(
        content: String,
        photoURL: String? = nil,
        eventKind: String? = nil,
        metadataJSON: String? = nil,
        minutesAgo: Int = 45
    ) -> ProjectNote {
        let n = ProjectNote(
            projectId: "p1", companyId: "c1", authorId: "u1",
            content: content, photoURL: photoURL,
            createdAt: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo))
        )
        n.eventKind = eventKind
        n.contentMetadataJSON = metadataJSON
        return n
    }

    private func member() -> TeamMember {
        TeamMember(id: "u1", firstName: "Harrison", lastName: "Sweet", role: "Crew")
    }

    // MARK: - Photo comment card

    func testPhotoCommentCard() {
        snapshot("feed_photo_comment_card") {
            ActivityEntryView(
                note: note(content: "Looks tight against the fascia — reroute the downspout left before we close it up.",
                           photoURL: "https://example.com/1782770183522-abcd.jpg"),
                authorName: "Harrison Sweet",
                teamMember: member(),
                isOwnNote: false,
                allTeamMembers: [member()],
                onDelete: { _ in },
                onEdit: { _, _ in true },
                onPhotoTap: { _, _ in }
            )
            .environmentObject(DataController())
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Site-visit packet card

    func testSiteVisitPacketCard() {
        let metadata = """
        {"site_visit_id":"sv-1","photo_count":4,"measurements":[{"label":"Deck width","value":"14 ft 6 in"},{"label":"Rail run","value":"38 ft"}],"notes":["Client wants composite boards"],"checklist":["Power on site — yes"]}
        """
        snapshot("feed_site_visit_packet_card") {
            SiteVisitPacketEntryView(
                note: note(content: "SITE VISIT PACKET\n\n…", eventKind: "site_visit",
                           metadataJSON: metadata, minutesAgo: 60 * 24 * 3),
                authorName: "Jackson Sweet",
                teamMember: member()
            )
            .environmentObject(DataController())
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Status change line

    func testStatusChangeLine() {
        snapshot("feed_status_change_line", width: deviceWidth) {
            StatusChangeEntryView(
                note: note(content: "Status changed", eventKind: "status_change",
                           metadataJSON: #"{"from":"estimated","to":"archived"}"#,
                           minutesAgo: 60 * 24 * 2),
                authorName: "Dana Cole"
            )
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Comment badge

    func testCommentBadge() {
        snapshot("carousel_comment_badge", width: 100) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
                    .frame(width: 72, height: 72)
                PhotoCommentCountBadge_ProxyForSnapshot(count: 3)
                    .offset(x: 4, y: -4)
            }
            .frame(width: 72, height: 72)
            .padding(OPSStyle.Layout.spacing4)
        }
    }
}

/// The production badge is `private` to ActivityTabView; this proxy mirrors its
/// exact layout + tokens so the snapshot proves the visual without loosening
/// the production access level.
private struct PhotoCommentCountBadge_ProxyForSnapshot: View {
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("\(count)")
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(OPSStyle.Colors.primaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.65)))
    }
}
#endif
