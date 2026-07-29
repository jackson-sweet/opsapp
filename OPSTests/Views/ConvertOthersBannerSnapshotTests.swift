//
//  ConvertOthersBannerSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the CLIENT-HAS-OTHERS banner on the
//  convert-lead-to-project sheet (bug 4e11e121 — the header line wrapped
//  onto multiple lines). Renders the banner at real device widths with
//  fixture counts, replicating the sheet's scroll-content padding, so the
//  single-line header is provable at the smallest supported width and at
//  large counts. drawHierarchy harness — a rendering harness, not an
//  assertion test.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ConvertOthersBannerSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-convert-banner-shots.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class ConvertOthersBannerSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-convert-banner-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UIHostingController + UIWindow + drawHierarchy — the Books-harness
    /// pattern (ImageRenderer skips onAppear and leaves scroll content blank).
    /// Width is parameterized: 393 is the design frame, 375 the smallest
    /// supported iPhone.
    private func snapshot<V: View>(
        _ name: String,
        width: CGFloat = 393,
        height: CGFloat = 320,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: width, height: height)
        let host = UIHostingController(
            rootView: content()
                .frame(width: width)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
                // A UIWindow inherits the device safe-area insets whatever its
                // frame — without this the content renders displaced and
                // bottom-clipped (same correction as DaySheetRowSnapshotTests).
                .ignoresSafeArea()
        )
        host.view.backgroundColor = .black

        // The window MUST adopt the app host's scene — an unsceened window is
        // never picked up by the render server and drawHierarchy renders blank.
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
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        window.isHidden = true
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Fixtures

    /// Related-project refs shaped like real preflight output: a couple of
    /// likely-duplicate candidates first, then the rest of the client's book.
    private func refs(
        _ count: Int,
        unavailableMatchId: String? = nil,
        linkedElsewhere: Bool = false
    ) -> [ConvertToProjectSheet.RelatedProjectRef] {
        let titles = [
            "1240 Maple Ave", "Calloway rear deck", "1240 Maple Ave garage",
            "Glass rail retrofit", "Front porch rebuild", "Cedar pergola",
            "Dock replacement", "1244 Maple Ave", "Shop mezzanine",
            "Stair stringer swap", "Hot tub surround", "Fence line north"
        ]
        let statuses: [Status?] = [.inProgress, .accepted, .completed, .estimated, nil]
        return (0..<count).map { i in
            let linkState: ConvertToProjectSheet.RelatedProjectLinkState
            if i >= 2 {
                linkState = .reviewOnly
            } else if "ref-\(i)" == unavailableMatchId {
                linkState = .unavailable
            } else if linkedElsewhere {
                linkState = .linkedElsewhere
            } else {
                linkState = .matchable
            }
            return ConvertToProjectSheet.RelatedProjectRef(
                id: "ref-\(i)",
                title: titles[i % titles.count],
                address: nil,
                status: statuses[i % statuses.count],
                linkState: linkState
            )
        }
    }

    /// Banner in its real context — the exact scroll subtree the sheet builds
    /// (ScrollView → leading VStack → `spacing3_5` horizontal padding), so the
    /// header's line-breaking behaves as it does in the app.
    private func banner(
        _ count: Int,
        selectedProjectId: String? = nil,
        unavailableMatchId: String? = nil,
        linkedElsewhere: Bool = false,
        notice: String? = nil
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ConvertToProjectSheet.ClientOthersBanner(
                    projects: refs(
                        count,
                        unavailableMatchId: unavailableMatchId,
                        linkedElsewhere: linkedElsewhere
                    ),
                    selectedProjectId: selectedProjectId,
                    onPeek: { _ in },
                    onMatch: { _ in },
                    notice: notice
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Proof renders

    /// Plural, realistic large count, design-frame width.
    func testRenderBannerTwelveOthers() {
        snapshot("convert_banner_12", width: 393, height: 340) { banner(12) }
    }

    /// Smallest supported iPhone width — the strictest single-line proof.
    func testRenderBannerTwelveOthersNarrow() {
        // 440pt canvas: at 375pt width the chip grid wraps taller than the
        // 393pt-wide variant — 340pt cut the last chip row off the canvas.
        snapshot("convert_banner_12_narrow375", width: 375, height: 440) { banner(12) }
    }

    /// Singular copy path.
    func testRenderBannerOneOther() {
        snapshot("convert_banner_01", width: 393, height: 200) { banner(1) }
    }

    /// A selected duplicate must read as a committed choice before the final
    /// MATCH PROJECT action is tapped.
    func testRenderBannerSelectedMatch() {
        snapshot("convert_banner_selected", width: 393, height: 240) {
            banner(3, selectedProjectId: "ref-0")
        }
    }

    /// A row rejected by the locked RPC remains visible for review but cannot
    /// immediately return as an actionable MATCH candidate.
    func testRenderBannerRejectedMatch() {
        snapshot("convert_banner_rejected", width: 393, height: 240) {
            banner(3, unavailableMatchId: "ref-0")
        }
    }

    /// Bug 5468b3c6 \u{2014} every same-address match already belongs to another
    /// lead. The sheet used to synthesize an admin-review blocker here and
    /// disable everything; the chips now read LINKED, stay peek-able, and the
    /// notice says plainly what is in the way.
    func testRenderBannerEveryMatchLinkedElsewhere() {
        snapshot("convert_banner_all_linked", width: 393, height: 280) {
            banner(
                3,
                linkedElsewhere: true,
                notice: "EVERY MATCH IS LINKED TO ANOTHER LEAD"
            )
        }
    }

    /// The candidate link re-read failed on its own. The preflight's answer
    /// still stands; the chips just cannot claim to be matchable.
    func testRenderBannerLinkCheckUnverified() {
        snapshot("convert_banner_unverified", width: 393, height: 280) {
            banner(
                3,
                notice: "COULD NOT CHECK PROJECT LINKS \u{2014} RETRY"
            )
        }
    }

    /// Defensive ceiling — a 3-digit count must still hold one line.
    func testRenderBannerHundredsOthers() {
        // 440pt canvas: same narrow-width wrap as convert_banner_12_narrow375.
        snapshot("convert_banner_120", width: 375, height: 440) { banner(120) }
    }
}
#endif
