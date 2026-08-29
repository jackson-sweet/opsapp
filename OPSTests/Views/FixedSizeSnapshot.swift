//
//  FixedSizeSnapshot.swift
//  OPSTests
//
//  Renders a SwiftUI view to a UIImage at a FIXED logical size, hosted inside
//  the app host's real window (AppHostWindow.acquire()) — never a test-created
//  window, which iOS 26.5 full-suite runs can render blank once the host drops
//  out of the foreground pipeline (see AppHostWindow.swift). The fixed size
//  makes the capture device-agnostic: content lays out identically on any
//  runner device, including capture sizes taller than the device screen.
//
//  Safe-area passthrough is disabled (safeAreaRegions = []) so device-specific
//  insets (Dynamic Island et al.) never shift content between runner devices.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest

@MainActor
enum FixedSizeSnapshot {

    /// Hosts `view` at exactly `size` in the app host's window, waits for
    /// layout quiescence (bounded), draws it, restores the app's UI, and
    /// returns the image.
    ///
    /// `minimumSettle` runs the run loop for at least that long BEFORE the
    /// quiescence polls begin — required for views that load a view-model in an
    /// async `.task`, because a placeholder spinner animates on the presentation
    /// layer while the model-layer frames (all the fingerprint sees) sit
    /// perfectly still, so quiescence alone would capture the spinner.
    /// `settleDeadline` bounds the quiescence phase that follows.
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        minimumSettle: TimeInterval = 0,
        settleDeadline: TimeInterval = 2
    ) throws -> UIImage {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        let container = UIViewController()
        container.overrideUserInterfaceStyle = .dark
        container.view.backgroundColor = .black
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: size.width),
            host.view.heightAnchor.constraint(equalToConstant: size.height),
        ])
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()

        // Async view-model floor first (see the doc comment), then settle on
        // geometry quiescence — three consecutive stable layer-tree polls —
        // never an unbounded wait. Bounded so a perpetually animating view
        // still captures instead of hanging the suite.
        if minimumSettle > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: minimumSettle))
        }
        var stable = 0
        var lastFingerprint = ""
        let deadline = Date(timeIntervalSinceNow: settleDeadline)
        while stable < 3, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let fingerprint = Self.fingerprint(of: host.view.layer)
            if fingerprint == lastFingerprint {
                stable += 1
            } else {
                stable = 0
                lastFingerprint = fingerprint
            }
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            host.view.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }
    }

    /// Frame-fold of the layer tree — a cheap change detector for quiescence.
    private static func fingerprint(of layer: CALayer, depth: Int = 0) -> String {
        var parts = ["\(layer.frame.integral)"]
        if depth < 12, let sublayers = layer.sublayers {
            parts.append("\(sublayers.count)")
            for sublayer in sublayers {
                parts.append(fingerprint(of: sublayer, depth: depth + 1))
            }
        }
        return parts.joined(separator: "|")
    }
}
#endif
