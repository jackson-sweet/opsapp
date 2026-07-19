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
    private func refs(_ count: Int) -> [ConvertToProjectSheet.RelatedProjectRef] {
        let titles = [
            "1240 Maple Ave", "Calloway rear deck", "1240 Maple Ave garage",
            "Glass rail retrofit", "Front porch rebuild", "Cedar pergola",
            "Dock replacement", "1244 Maple Ave", "Shop mezzanine",
            "Stair stringer swap", "Hot tub surround", "Fence line north"
        ]
        let statuses: [Status?] = [.inProgress, .accepted, .completed, .estimated, nil]
        return (0..<count).map { i in
            ConvertToProjectSheet.RelatedProjectRef(
                id: "ref-\(i)",
                title: titles[i % titles.count],
                address: nil,
                status: statuses[i % statuses.count],
                isLikelyDuplicate: i < 2
            )
        }
    }

    /// Banner in its real context — the exact scroll subtree the sheet builds
    /// (ScrollView → leading VStack → `spacing3_5` horizontal padding), so the
    /// header's line-breaking behaves as it does in the app.
    private func banner(_ count: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ConvertToProjectSheet.ClientOthersBanner(projects: refs(count), onOpen: { _ in })
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
        snapshot("convert_banner_12_narrow375", width: 375, height: 340) { banner(12) }
    }

    /// Singular copy path.
    func testRenderBannerOneOther() {
        snapshot("convert_banner_01", width: 393, height: 200) { banner(1) }
    }

    /// Defensive ceiling — a 3-digit count must still hold one line.
    func testRenderBannerHundredsOthers() {
        snapshot("convert_banner_120", width: 375, height: 340) { banner(120) }
    }
}
#endif
