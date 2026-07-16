//
//  CameraUnificationSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for bug 56c37df2: the project action-bar
//  camera now presents the standardized CameraBatchView (site-visit
//  camera), and lens stops are labeled with user-facing magnification
//  instead of raw zoom factors.
//
//  Two proofs:
//  1. Lens-stop truth table — for each real hardware class, the row the
//     selector used to show (raw factors) beside the row it shows now
//     (planner output, the code under test), selected stop = launch state.
//  2. The standardized camera HUD itself (CameraBatchView) as it presents
//     from the project action bar — on the simulator the preview is black
//     (no capture hardware) but the HUD chrome renders exactly as shipped.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/CameraUnificationSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-camera-unification-shots.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class CameraUnificationSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-camera-unification-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UIHostingController + UIWindow + drawHierarchy — the Books-harness
    /// pattern (ImageRenderer skips onAppear and UIKit-representable
    /// content; the live window layer captures both).
    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat = 852,
        settle: TimeInterval = 0.4,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(
            rootView: content()
                .frame(width: deviceWidth)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
        )
        host.view.backgroundColor = .black

        // The window MUST adopt the app host's scene — an unsceened window
        // is never picked up by the render server, so drawHierarchy would
        // silently produce a blank white image.
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

        RunLoop.main.run(until: Date().addingTimeInterval(settle))

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

    // MARK: - Hardware profiles

    /// Raw AVFoundation values per device class. Virtual devices anchor
    /// raw factor 1.0 to their widest lens; the wide "1x" lens engages at
    /// the first switch-over factor.
    private struct HardwareProfile {
        let name: String
        let detail: String
        let minZoom: CGFloat
        let switchOvers: [CGFloat]
        let wideLens: CGFloat
        /// Labels the OLD planner produced (raw factors labeled verbatim,
        /// raw ceiling 8) and the stop the OLD launch state highlighted
        /// (raw 1.0 — the ultra-wide frame on multi-lens hardware).
        let beforeLabels: [String]
        let beforeSelected: String
    }

    private let profiles: [HardwareProfile] = [
        .init(
            name: "TRIPLE CAMERA",
            detail: "ultra-wide + wide + 3x tele (iPhone Pro)",
            minZoom: 1, switchOvers: [2, 6], wideLens: 2,
            beforeLabels: ["1x", "2x", "3x", "6x"], beforeSelected: "1x"
        ),
        .init(
            name: "DUAL WIDE CAMERA",
            detail: "ultra-wide + wide (iPhone base)",
            minZoom: 1, switchOvers: [2], wideLens: 2,
            beforeLabels: ["1x", "2x", "3x"], beforeSelected: "1x"
        ),
        .init(
            name: "5X TELE CAMERA",
            detail: "ultra-wide + wide + 5x tele (iPhone Pro Max)",
            minZoom: 1, switchOvers: [2, 10], wideLens: 2,
            beforeLabels: ["1x", "2x", "3x"], beforeSelected: "1x"
        ),
        .init(
            name: "SINGLE LENS",
            detail: "wide only (iPhone SE)",
            minZoom: 1, switchOvers: [], wideLens: 1,
            beforeLabels: ["1x", "2x", "3x"], beforeSelected: "1x"
        )
    ]

    // MARK: - Proof 1: lens-stop truth table

    func testLensStopLabelsBeforeAfterPerDeviceClass() {
        snapshot("01_lens_stop_labels_before_after", height: 900, settle: 0.5) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("// CAMERA LENS STOPS")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("Selected pill = what the camera opens on")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                ForEach(self.profiles, id: \.name) { profile in
                    self.profileRow(profile)
                }
            }
            .padding(OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: HardwareProfile) -> some View {
        // AFTER row renders the REAL planner output — the code under test.
        let after = CameraLensOptionPlanner.options(
            minZoom: profile.minZoom,
            maxZoom: 8 * profile.wideLens,
            switchOverZoomFactors: profile.switchOvers,
            wideLensZoomFactor: profile.wideLens
        )
        // Launch state now anchors to the wide lens (raw = wideLens).
        let afterSelected = after.min {
            abs($0.zoomFactor - profile.wideLens) < abs($1.zoomFactor - profile.wideLens)
        }?.label

        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(profile.detail)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing3) {
                Text("BEFORE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(width: 52, alignment: .leading)
                lensRow(labels: profile.beforeLabels, selected: profile.beforeSelected)
                Spacer(minLength: 0)
            }

            HStack(spacing: OPSStyle.Layout.spacing3) {
                Text("AFTER")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .frame(width: 52, alignment: .leading)
                lensRow(labels: after.map(\.label), selected: afterSelected)
                Spacer(minLength: 0)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
    }

    /// Mirrors the shipped lens-selector visual: dark capsule strip,
    /// JetBrains Mono stops, active pill highlighted.
    private func lensRow(labels: [String], selected: String?) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(
                        label == selected
                            ? OPSStyle.Colors.text
                            : OPSStyle.Colors.text3
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .fill(label == selected
                                ? OPSStyle.Colors.surfaceActive
                                : Color.clear)
                    )
            }
        }
        .padding(OPSStyle.Layout.spacing1)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Proof 2: the standardized camera HUD

    /// The exact component the project action bar now presents — the same
    /// CameraBatchView site-visit capture uses. Simulator has no capture
    /// hardware so the preview is black, but the HUD (CANCEL / DONE,
    /// shutter, library button) is the shipped chrome.
    func testStandardizedCameraHUDPresents() {
        snapshot("02_standardized_camera_hud", height: 852, settle: 0.8) {
            CameraBatchView { _ in }
        }
    }
}
#endif
