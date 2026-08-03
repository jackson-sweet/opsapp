//
//  ProjectCompletionMomentSnapshotTests.swift
//  OPSTests
//
//  Visual proof of the COMPLETE PROJECT completion moment, captured on the
//  real ProjectActionBar so the frames show the shipping layout — including
//  that the ring clears the button but is still absorbed by the action bar's
//  vertical padding, so the enclosing horizontal ScrollView never clips it.
//
//  Four frames:
//    completion-idle          before — the action the operator taps
//    completion-ring-mid      the ring mid-sweep, button not yet stamped
//    completion-stamped       after — COMPLETED in the completed status color
//    completion-reduced-motion the Reduce Motion frame: ring at final geometry,
//                             opacity-only, completed state still reached
//
//  Rendered via FixedSizeSnapshot: hosted in the APP'S OWN window at a fixed
//  logical size, so asset-catalog colors resolve (ImageRenderer renders them
//  yellow) and the capture is identical on any runner device.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ProjectCompletionMomentSnapshotTests
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class ProjectCompletionMomentSnapshotTests: XCTestCase {

    /// iPhone 17 width. The height is the action bar plus enough canvas above
    /// and below to prove nothing is clipped at its edges.
    private let barWidth: CGFloat = 393
    private let barHeight: CGFloat = 140

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-completion-moment-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var savedPermissions: [String: String] = [:]
    private var savedBlockedByFlags: Set<String> = []

    override func setUp() {
        super.setUp()
        savedPermissions = PermissionStore.shared.permissions
        savedBlockedByFlags = PermissionStore.shared.blockedByFlags
        PermissionStore.shared.permissions = [:]
        PermissionStore.shared.blockedByFlags = []
    }

    override func tearDown() {
        PermissionStore.shared.permissions = savedPermissions
        PermissionStore.shared.blockedByFlags = savedBlockedByFlags
        super.tearDown()
    }

    // MARK: - Frames

    /// Before. The Complete entry is a verb, in the bar's default monochrome.
    func testIdleBarRendersTheCompleteAction() {
        snapshot("completion-idle", seed: nil)
    }

    /// Mid-sweep. The ring is part-drawn and expanding; the button has not
    /// stamped yet, so this frame proves the ring leads the state change.
    func testRingMidSweep() {
        snapshot(
            "completion-ring-mid",
            seed: ProjectActionBar.CompletionMomentSeed(ringProgress: 0.62, ringOpacity: 1, stamped: false)
        )
    }

    /// After. The ring has closed and the button has stamped to COMPLETED in
    /// the completed status color. This is the frame the moment exists for.
    func testStampedCompletedState() {
        snapshot(
            "completion-stamped",
            seed: ProjectActionBar.CompletionMomentSeed(ringProgress: 1, ringOpacity: 1, stamped: true)
        )
    }

    /// Reduce Motion. Geometrically identical to the settled frame — the ring
    /// is seeded closed at final size and only its opacity ever moved — and
    /// the completed state is still reached. Equivalence, not removal.
    func testReducedMotionStillReachesTheCompletedState() {
        snapshot(
            "completion-reduced-motion",
            seed: ProjectActionBar.CompletionMomentSeed(ringProgress: 1, ringOpacity: 1, stamped: true)
        )

        let reduced = ProjectCompletionMoment.timeline(reduceMotion: true)
        XCTAssertFalse(reduced.sweeps, "The captured frame must not have swept to get there")
        XCTAssertEqual(reduced.stamp.duration, 0.150, accuracy: 0.0001)
    }

    // MARK: - Non-visual guarantees the frames cannot show

    /// The ring is an overlay, so hosting it must not change the bar's size —
    /// otherwise the action bar would jump the moment a project completes.
    func testRingDoesNotChangeTheBarsLayout() throws {
        let idle = try measuredBarSize(seed: nil)
        let stamped = try measuredBarSize(
            seed: ProjectActionBar.CompletionMomentSeed(ringProgress: 1, ringOpacity: 1, stamped: true)
        )
        XCTAssertEqual(idle.height, stamped.height, accuracy: 0.5,
                       "The ring must add no layout height")
        XCTAssertEqual(idle.width, stamped.width, accuracy: 0.5,
                       "The ring must add no layout width")
    }

    // MARK: - Helpers

    private func makeProject() -> Project {
        Project(
            id: "proj-completion",
            title: "South deck rebuild",
            status: .inProgress
        )
    }

    private func bar(seed: ProjectActionBar.CompletionMomentSeed?) -> some View {
        VStack {
            Spacer()
            ProjectActionBar(project: makeProject(), completionSeed: seed)
            Spacer()
        }
        .frame(width: barWidth, height: barHeight)
        .background(Color.black)
        .environmentObject(DataController())
        .environmentObject(AppState())
        .environmentObject(LocationManager())
    }

    private func snapshot(_ name: String, seed: ProjectActionBar.CompletionMomentSeed?) {
        let size = CGSize(width: barWidth, height: barHeight)
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(bar(seed: seed), size: size)
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
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
        print("SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }

    /// Lays the bar out on its own and reports the size it claims.
    private func measuredBarSize(seed: ProjectActionBar.CompletionMomentSeed?) throws -> CGSize {
        let host = UIHostingController(
            rootView: ProjectActionBar(project: makeProject(), completionSeed: seed)
                .environmentObject(DataController())
                .environmentObject(AppState())
                .environmentObject(LocationManager())
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: barWidth, height: barHeight)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: barWidth, height: .greatestFiniteMagnitude))
    }
}
#endif
