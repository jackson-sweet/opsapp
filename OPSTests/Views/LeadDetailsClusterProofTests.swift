//
//  LeadDetailsClusterProofTests.swift
//  OPSTests
//
//  Visual proof pack for the WS-C lead-details cluster. A rendering harness,
//  not an assertion suite — the assertions live in `LeadDetailScrollTests`,
//  `LeadLossReasonTests`, `LeadArchiveFeedbackTests`, and
//  `EmailBodyCleanerTests`. These PNGs are what a human looks at:
//
//    73f7381b  lead_detail_pinned_title_scrolled   — title still on screen mid-scroll
//    e13be3bb  lead_detail_width_default / _xl     — nothing past the right edge
//    f5c67513  lost_reason_chips                   — DROPPED THE BALL / NEVER FOLLOWED UP
//    e0c8084f  lead_archive_sheet                  — one-tap ARCHIVE, optional reason + note
//    183f7ec9  activity_feed_directional           — who each message was between
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadDetailsClusterProofTests
//  Shots are attached to the xcresult (export with `xcresulttool export
//  attachments`) — the simulator CLONE that runs the suite is deleted with the
//  run, so a file written inside it does not survive.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class LeadDetailsClusterProofTests: XCTestCase {

    private let deviceWidth: CGFloat = 393
    private let deviceHeight: CGFloat = 852

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-ws-c-proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 73f7381b + e13be3bb — the dossier itself

    func testProofPinnedTitleSurvivesScroll() throws {
        try renderDossier(
            "lead_detail_pinned_title_scrolled",
            sizeCategory: .large,
            scrollFraction: 0.5
        )
    }

    func testProofDossierAtRest() throws {
        try renderDossier("lead_detail_width_default", sizeCategory: .large, scrollFraction: 0)
    }

    func testProofDossierAtAccessibilityExtraLarge() throws {
        try renderDossier(
            "lead_detail_width_xl",
            sizeCategory: .accessibilityExtraLarge,
            scrollFraction: 0.35
        )
    }

    // MARK: - f5c67513 — lost-reason chips

    func testProofLostReasonChips() {
        snapshot("lost_reason_chips", height: 260) {
            LeadField(label: "REASON") {
                LeadChipPicker(
                    selection: .constant(LossReason.droppedBall.rawValue),
                    options: LostReasonSheet.options
                )
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - e0c8084f — archive sheet

    func testProofArchiveSheet() {
        snapshot("lead_archive_sheet", height: 560) {
            LeadArchiveSheet(opportunity: leadFixture(), onArchive: { _, _ in true })
        }
    }

    // MARK: - 183f7ec9 — directional activity feed

    func testProofActivityFeedIsDirectional() {
        snapshot("activity_feed_directional", height: 420) {
            ActivityTimeline(
                activities: emailThreadFixture(),
                transitions: [],
                onViewAll: {}
            )
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Fixtures

    private func leadFixture() -> Opportunity {
        let opp = Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off and full re-deck, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        opp.contactPhone = "(555) 123-4567"
        opp.contactEmail = "helen.calloway@callowayhomes.example"
        opp.address = "1240 Maple Avenue, Victoria, British Columbia"
        opp.source = "referral"
        return opp
    }

    /// Four messages of ONE thread — the exact shape that used to render as four
    /// identical rows, because every message shares the subject.
    private func emailThreadFixture() -> [Activity] {
        let subject = "Re: Roof tear-off quote"
        let base = Date(timeIntervalSince1970: 1_785_000_000)

        func message(
            _ offset: TimeInterval,
            direction: String,
            from: String,
            to: [String],
            body: String
        ) -> Activity {
            let a = Activity(
                id: UUID().uuidString.lowercased(),
                opportunityId: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
                companyId: "preview-company",
                type: .email,
                createdAt: base.addingTimeInterval(offset)
            )
            a.subject = subject
            a.bodyText = body
            a.direction = direction
            a.fromEmail = from
            a.toEmails = to
            a.emailThreadId = "thread-1"
            a.emailMessageId = UUID().uuidString.lowercased()
            return a
        }

        return [
            message(
                -10_800,
                direction: "inbound",
                from: "helen.calloway@callowayhomes.example",
                to: ["jackson.sweet@opsapp.example"],
                body: """
                Can you get me a price on the tear-off by Thursday?

                Thanks,
                Helen
                """
            ),
            message(
                -7_200,
                direction: "outbound",
                from: "jackson.sweet@opsapp.example",
                to: ["helen.calloway@callowayhomes.example"],
                body: """
                Quote is attached — 28 squares, tear-off and re-deck included.

                On Mon, Jan 15, 2026 at 3:45 PM Helen Calloway <helen@x.com> wrote:
                > Can you get me a price on the tear-off by Thursday?
                """
            ),
            message(
                -3_600,
                direction: "inbound",
                from: "helen.calloway@callowayhomes.example",
                to: ["jackson.sweet@opsapp.example"],
                body: """
                Numbers look right. Friday at 9 works for the walkthrough.

                --
                Helen Calloway
                Calloway Homes
                555-0142
                """
            ),
            message(
                -600,
                direction: "outbound",
                from: "jackson.sweet@opsapp.example",
                to: ["helen.calloway@callowayhomes.example"],
                body: "See you Friday at 9."
            ),
        ]
    }

    // MARK: - Rendering

    /// Hosts the REAL `LeadDetailView` in the app host's window, drives the
    /// scroll, and captures. Drawing the hosted view inside the app's own window
    /// is mandatory — a test-created window renders blank mid-suite.
    private func renderDossier(
        _ name: String,
        sizeCategory: ContentSizeCategory,
        scrollFraction: CGFloat
    ) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OPSSchemaV22.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let permissions = PermissionStore()
        permissions.permissions = ["leads.edit": "all", "leads.convert": "all"]

        let root = NavigationStack {
            LeadDetailView(opportunity: leadFixture())
                .environmentObject(DataController())
                .environmentObject(permissions)
        }
        .modelContainer(container)
        .environment(\.sizeCategory, sizeCategory)
        .environment(\.colorScheme, .dark)
        .frame(width: deviceWidth, height: deviceHeight)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: deviceHeight)

        let window = try AppHostWindow.acquire()
        let previous = window.rootViewController
        defer {
            window.rootViewController = previous
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        if scrollFraction > 0, let scrollView = findScrollView(host.view) {
            scrollView.setContentOffset(
                CGPoint(x: 0, y: scrollView.contentSize.height * scrollFraction),
                animated: false
            )
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        }

        write(capture(window, bounds: host.view.bounds), name: name)
    }

    /// Component-level capture — hosts the view inside the app's window at a
    /// fixed box, same reason as above.
    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(rootView:
            ZStack(alignment: .topLeading) {
                OPSStyle.Colors.background
                content()
                    .frame(width: size.width, alignment: .leading)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // The host's view fills the WINDOW (852pt), not the box above, so
            // without this the content centres itself vertically and a short
            // capture region photographs empty canvas.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        guard let window = try? AppHostWindow.acquire() else {
            XCTFail("no app host window for \(name)")
            return
        }
        let previous = window.rootViewController
        defer {
            window.rootViewController = previous
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))

        write(capture(window, bounds: CGRect(origin: .zero, size: size)), name: name)
    }

    private func capture(_ window: UIWindow, bounds: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func write(_ image: UIImage, name: String) {
        guard let data = image.pngData() else {
            XCTFail("failed to encode \(name)")
            return
        }

        // Attachments land in the xcresult on the HOST, which is the only
        // durable destination: `xcodebuild test` runs in an ephemeral simulator
        // CLONE, so anything written to the simulator's own filesystem is
        // deleted with the clone the moment the run finishes.
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also drop a copy in the simulator's tmp for interactive runs.
        let url = outDir.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("WS-C PROOF: \(name)")
    }

    private func findScrollView(_ view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(sub) { return found }
        }
        return nil
    }
}
#endif
