//
//  BugReportPickFixture.swift
//  OPSTests
//
//  Shared stage for the POINT AT IT hosted tests and proof snapshots
//  (bug 14e5a792): a representative screen built from real house components,
//  hosted full-window in the app host's own window, plus the plumbing to read
//  what a pick session sees there.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

// MARK: - The representative screen

/// A scrolling screen of the kind operators actually file bugs on: a plain
/// section header (no component — text only), a glass card holding a form
/// field and a house button, and the lead dossier's site-visit banner with its
/// hand-built verbs.
struct BugReportPickRepresentativeScreen: View {
    @State private var clientName = "Jane Doe"

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    Text("// THIS WEEK")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("DECK REBUILD · 14 ELM ST")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.text2)

                        FormField(title: "Client name", text: $clientName)

                        Button("START JOB") {}
                            .buttonStyle(OPSButtonStyle.Primary())
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .glassSurface()
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                    LeadSiteVisitBanner(
                        state: .booked(token: "TODAY 2:00PM", windowOpen: true),
                        canManage: true,
                        onDetails: {}
                    )
                }
                .padding(.top, OPSStyle.Layout.spacing4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Hosting

/// Hosts SwiftUI content full-window in the app host's REAL window
/// (`AppHostWindow.acquire()`), swapping the root controller and restoring it
/// afterwards — never a test-created window (see CLAUDE.md, iOS Gotchas).
@MainActor
final class BugReportPickStage {
    let window: UIWindow
    let container: UIViewController
    private let originalRoot: UIViewController?
    private var overlays: [UIViewController] = []

    init<V: View>(_ content: V) throws {
        window = try AppHostWindow.acquire()
        originalRoot = window.rootViewController

        let host = UIHostingController(rootView: content.environment(\.colorScheme, .dark))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black

        container = UIViewController()
        container.overrideUserInterfaceStyle = .dark
        container.view.backgroundColor = .black
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(host.view)
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()
    }

    /// Lays a second SwiftUI layer over the whole stage — how the proofs put
    /// the pick layer on top of the screen, as the overlay window does live.
    func overlay<V: View>(_ content: V) {
        let host = UIHostingController(rootView: content.environment(\.colorScheme, .dark))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .clear
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        overlays.append(host)
    }

    /// Settle on layer-tree quiescence (bounded), never a bare sleep. Async,
    /// so the main actor is yielded between polls: SwiftUI's updates and the
    /// session's Vision hop both need the main queue to drain, which a nested
    /// run-loop spin inside an async test does not guarantee.
    func settle(minimum: TimeInterval = 0.2, deadline: TimeInterval = 3) async {
        try? await Task.sleep(nanoseconds: UInt64(minimum * 1_000_000_000))
        var stable = 0
        var last = ""
        let end = Date(timeIntervalSinceNow: deadline)
        while stable < 3, Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let print = Self.fingerprint(window.layer)
            if print == last { stable += 1 } else { stable = 0; last = print }
        }
    }

    /// The stage drawn from its root view — which fills the app window at
    /// its origin, so the image is measured in app-window points.
    func render() -> UIImage {
        let bounds = container.view.bounds
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            container.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    func tearDown() {
        if container.presentedViewController != nil {
            container.dismiss(animated: false)
        }
        for overlay in overlays {
            overlay.willMove(toParent: nil)
            overlay.view.removeFromSuperview()
            overlay.removeFromParent()
        }
        overlays.removeAll()
        window.rootViewController = originalRoot
        window.layoutIfNeeded()
    }

    private static func fingerprint(_ layer: CALayer, depth: Int = 0) -> String {
        var parts = ["\(layer.frame.integral)\(layer.opacity)"]
        if depth < 14, let sublayers = layer.sublayers {
            parts.append("\(sublayers.count)")
            for sublayer in sublayers {
                parts.append(fingerprint(sublayer, depth: depth + 1))
            }
        }
        return parts.joined(separator: "|")
    }
}

// MARK: - Reading what a session sees

@MainActor
enum BugReportPickProbeReadout {

    /// Every registered probe in `window`, measured at its own centre.
    static func probes(in window: UIWindow) -> [BugReportProbeView] {
        BugReportPickMode.shared.registeredProbes.filter { $0.window === window }
    }

    static func frame(of probe: UIView, in window: UIWindow) -> CGRect {
        probe.convert(probe.bounds, to: window)
    }

    static func centre(of probe: UIView, in window: UIWindow) -> CGPoint {
        let frame = frame(of: probe, in: window)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// A readable dump for the test log — the on-simulator evidence for the
    /// ordering and visibility assumptions.
    static func log(_ label: String, _ candidates: [BugReportProbeCandidate]) {
        print("PICK PROBES @ \(label)")
        for candidate in candidates {
            print(
                "  \(candidate.role.rawValue) '\(candidate.label ?? "—")' "
                + "frame=\(candidate.frame.integral) depth=\(candidate.depth) "
                + "alpha=\(String(format: "%.2f", candidate.cumulativeAlpha)) "
                + "hidden=\(candidate.isHiddenInHierarchy) "
                + "front=\(candidate.isInFrontmostPresentation) "
                + "clip=\(candidate.clipRect.map { "\($0.integral)" } ?? "none")"
            )
        }
    }

    /// Waits (bounded) for the session's Vision pass to finish.
    static func awaitText(_ session: BugReportPickSession, limit: TimeInterval = 15) async {
        let end = Date(timeIntervalSinceNow: limit)
        while !session.linesReady, Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
#endif
