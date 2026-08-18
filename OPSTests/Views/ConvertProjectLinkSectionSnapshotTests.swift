//
//  ConvertProjectLinkSectionSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the "WHICH PROJECT IS THIS" section on the
//  convert-lead-to-project sheet — the ONE ranked list that replaced three
//  candidate lists with three different selection rules (D1).
//
//  What these renders are proving:
//    - the header holds ONE line at the narrowest supported width (the old
//      "CLIENT HAS 02 OTHER PROJECTS" header fragment-wrapped — bug 4e11e121),
//    - every row reads as selectable, because every row IS selectable,
//    - the evidence badge (SAME ADDRESS / SAME CLIENT) makes the server's
//      ranking legible rather than arbitrary,
//    - a failed candidate read shows a RETRY, never a list the operator can
//      see but not use.
//
//  drawHierarchy harness — a rendering harness, not an assertion test.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ConvertProjectLinkSectionSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-convert-link-shots.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class ConvertProjectLinkSectionSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-convert-link-shots", isDirectory: true)
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

    /// Candidates shaped like real `get_manual_project_link_candidates` output:
    /// the server ranks same-address+same-client first, then same address, then
    /// same client, then everything else by recency.
    private func candidates(_ count: Int) -> [ConvertToProjectSheet.ProjectLinkCandidate] {
        let titles = [
            "1240 Maple Ave", "1240 Maple Ave garage", "Calloway rear deck",
            "Glass rail retrofit", "Front porch rebuild", "Cedar pergola",
            "Dock replacement", "1244 Maple Ave", "Shop mezzanine",
            "Stair stringer swap", "Hot tub surround", "Fence line north"
        ]
        let addresses = [
            "1240 Maple Ave, Victoria BC", "1240 Maple Ave, Victoria BC",
            "88 Calloway Rd, Saanich BC", "12 Douglas St, Victoria BC"
        ]
        let statuses: [Status?] = [.inProgress, .accepted, .completed, .estimated, nil]
        return (0..<count).map { i in
            ConvertToProjectSheet.ProjectLinkCandidate(
                id: "project-\(i)",
                title: titles[i % titles.count],
                address: addresses[i % addresses.count],
                status: statuses[i % statuses.count],
                // Mirrors the server ordering: 0 = address+client, 1 = address,
                // 2 = client, the rest carry no evidence.
                sameAddress: i <= 1,
                sameClient: i == 0 || i == 2
            )
        }
    }

    /// The section in its real context — the exact scroll subtree the sheet
    /// builds (ScrollView → leading VStack → `spacing3_5` horizontal padding),
    /// so the header's line-breaking behaves as it does in the app.
    private func section(
        _ count: Int,
        answer: ConvertToProjectSheet.LinkAnswer = .undecided,
        requiresExplicitAnswer: Bool = true,
        notice: String? = nil,
        loadFailed: Bool = false
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ConvertToProjectSheet.ProjectLinkSection(
                    candidates: candidates(count),
                    answer: answer,
                    inlineLimit: ConvertToProjectSheet.inlineCandidateLimit,
                    requiresExplicitAnswer: requiresExplicitAnswer,
                    notice: notice,
                    loadFailed: loadFailed,
                    isReloading: false,
                    onChoose: { _ in },
                    onCreateNew: {},
                    onPeek: { _ in },
                    onSearchAll: {},
                    onRetry: {}
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Proof renders

    /// The shortlist with the full evidence ladder visible, plus the
    /// create-new peer answer and the search-all door to the rest.
    func testRenderShortlistWithEvidenceLadder() {
        snapshot("convert_link_shortlist", width: 393, height: 480) { section(12) }
    }

    /// Smallest supported iPhone width — the strictest single-line header proof
    /// and the tightest row-truncation case.
    func testRenderShortlistNarrow375() {
        snapshot("convert_link_shortlist_narrow375", width: 375, height: 480) { section(12) }
    }

    /// A chosen project must read as a committed answer before the footer's
    /// MATCH PROJECT action is tapped.
    func testRenderProjectSelected() {
        snapshot("convert_link_selected", width: 393, height: 480) {
            section(12, answer: .link(projectId: "project-1"))
        }
    }

    /// "None of these" is a first-class answer, not a fallthrough.
    func testRenderCreateNewSelected() {
        snapshot("convert_link_create_new", width: 393, height: 480) {
            section(12, answer: .createNew)
        }
    }

    /// No same-address project ⇒ nothing to disambiguate ⇒ CREATE is already
    /// the answer and the header goes quiet.
    func testRenderNoDuplicateRiskIsQuiet() {
        snapshot("convert_link_quiet", width: 393, height: 400) {
            section(3, answer: .createNew, requiresExplicitAnswer: false)
        }
    }

    /// A lead whose address is junk still gets the whole ranked list — the
    /// server just cannot rank any of it by address. UNKNOWN, never blocked.
    func testRenderCreateBlockedStillOffersEveryProject() {
        snapshot("convert_link_address_blocker", width: 393, height: 500) {
            section(12, notice: "ADD AN ADDRESS, OR PICK THE PROJECT ABOVE")
        }
    }

    /// The candidate read failed on its own. It surfaces a RETRY — never a
    /// list the operator can look at but not use (the defect being fixed).
    func testRenderCandidateLoadFailureOffersRetry() {
        snapshot("convert_link_retry", width: 393, height: 260) {
            section(0, loadFailed: true)
        }
    }

    /// Defensive ceiling — the real company carries 231 unlinked projects, so
    /// the count on the search-all row must hold its line.
    func testRenderLargeCatalogCount() {
        snapshot("convert_link_231", width: 375, height: 480) { section(231) }
    }
}
#endif
