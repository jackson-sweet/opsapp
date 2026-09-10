//
//  BugReportPickProbe.swift
//  OPS
//
//  The component side of POINT AT IT (bug 14e5a792).
//
//  SwiftUI content is not UIViews, so a live hit-test of the app window names
//  rendering containers, never "the START button". Instead the house
//  components describe themselves: `.bugReportPickable(.button)` inside
//  `OPSButtonStyle`, `.bugReportPickable(.field, label: title)` inside
//  `FormField`, and so on. While — and only while — a pick session is
//  running, each one mounts a probe: a transparent, non-interactive UIView
//  sized to the element, which registers itself (weakly) while it is in a
//  window. At the pick point the collector measures every registered probe
//  and the resolver keeps the one the operator can actually see.
//
//  Outside a pick session the modifier adds nothing — no GeometryReader, no
//  representable, no UIView. `BugReportPickableTests` holds that line.
//

import SwiftUI
import UIKit

// MARK: - Pick mode

/// Whether a pick session is running, plus the probes it mounted.
///
/// A singleton on purpose: the report's overlay window, the app window, every
/// sheet and every UIKit-hosted SwiftUI root must agree on one switch, and an
/// environment value would have to be threaded into each of them. `isActive`
/// is the only observed property, so flipping it re-renders exactly the views
/// that read it — the pickable modifiers — and nothing else.
@MainActor
@Observable
final class BugReportPickMode {
    static let shared = BugReportPickMode()

    private(set) var isActive = false

    @ObservationIgnored
    private let probes = NSHashTable<BugReportProbeView>.weakObjects()

    init() {}

    func activate() {
        isActive = true
    }

    /// Ends the session. Probes unmount on the next render; the registry is
    /// cleared now so nothing stale can be measured in between.
    func deactivate() {
        isActive = false
        probes.removeAllObjects()
    }

    /// Every probe currently mounted in a window.
    var registeredProbes: [BugReportProbeView] {
        probes.allObjects.filter { $0.window != nil }
    }

    fileprivate func register(_ probe: BugReportProbeView) {
        guard isActive else { return }
        probes.add(probe)
    }

    fileprivate func unregister(_ probe: BugReportProbeView) {
        probes.remove(probe)
    }
}

// MARK: - The probe

/// A transparent stand-in for one house component, alive only during a pick
/// session. It never draws, never takes a touch, and never joins the
/// accessibility tree.
final class BugReportProbeView: UIView {
    var role: BugReportPickRole = .card
    var label: String?
    var component: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            BugReportPickMode.shared.register(self)
        } else {
            BugReportPickMode.shared.unregister(self)
        }
    }
}

private struct BugReportProbe: UIViewRepresentable {
    let role: BugReportPickRole
    let label: String?
    let component: String

    func makeUIView(context: Context) -> BugReportProbeView {
        let view = BugReportProbeView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateUIView(_ view: BugReportProbeView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: BugReportProbeView) {
        view.role = role
        view.label = label
        view.component = component
    }
}

// MARK: - The modifier

struct BugReportPickableModifier: ViewModifier {
    let role: BugReportPickRole
    let label: String?
    let component: String

    /// A parked keep-alive tab mounts nothing: it is on no one's screen.
    @Environment(\.isActiveTab) private var isActiveTab

    func body(content: Content) -> some View {
        // The probe rides in a background so the content's identity — and
        // every piece of @State beneath it — is untouched when a session
        // starts or ends. An `if` around `content` would rebuild the whole
        // subtree on each flip. With pick mode off, the background holds an
        // empty conditional: no view, no representable, no UIView.
        content.background {
            if BugReportPickMode.shared.isActive && isActiveTab {
                BugReportProbe(role: role, label: label, component: component)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Name this element for POINT AT IT. House components call it inside
    /// themselves, so screens built from them are pickable with no call-site
    /// changes.
    ///
    /// - Parameters:
    ///   - role: What the element is.
    ///   - label: What a person would call it — a field's title, a row's
    ///     name. Omit when the element's visible text says it; the pick reads
    ///     that text off the screen.
    ///   - fileID: Supplied by the compiler. Recorded as the component that
    ///     mounted the probe (`ButtonStyles`, `FormInputs`, …).
    func bugReportPickable(
        _ role: BugReportPickRole,
        label: String? = nil,
        fileID: String = #fileID
    ) -> some View {
        modifier(
            BugReportPickableModifier(
                role: role,
                label: label,
                component: BugReportProbeCollector.componentName(fromFileID: fileID)
            )
        )
    }
}

// MARK: - Measuring probes on the live screen

@MainActor
enum BugReportProbeCollector {

    /// `OPS/Styles/Components/ButtonStyles.swift` → `ButtonStyles`.
    nonisolated static func componentName(fromFileID fileID: String) -> String {
        let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        if let dot = file.lastIndex(of: ".") {
            return String(file[..<dot])
        }
        return file
    }

    /// Every probe, measured at `point` (app-window points), with the facts
    /// the resolver's rules need.
    static func candidates(
        at point: CGPoint,
        in appWindow: UIWindow,
        probes: [BugReportProbeView]
    ) -> [BugReportProbeCandidate] {
        let root = frontmostPresentationRoot(at: point, in: appWindow)
        return probes.map { measure($0, in: appWindow, presentationRoot: root) }
    }

    /// The root view of whatever is frontmost at `point`.
    ///
    /// The window is hit-tested for the view on top; walking up its responder
    /// chain reaches the controller that owns it — a presented sheet or cover,
    /// or the window's root. Only probes inside that controller's view can be
    /// what the finger is on. A point on a sheet's dimmed surround hits no
    /// controller at all; the frontmost presented controller owns it then,
    /// because the content beneath is not reachable while a sheet is up.
    static func frontmostPresentationRoot(at point: CGPoint, in window: UIWindow) -> UIView {
        var responder: UIResponder? = window.hitTest(point, with: nil)
        while let current = responder {
            if let controller = current as? UIViewController,
               controller.parent == nil,
               controller.presentingViewController != nil || controller === window.rootViewController,
               let view = controller.viewIfLoaded {
                return view
            }
            if current === window { break }
            responder = current.next
        }

        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top?.viewIfLoaded ?? window
    }

    /// Frame, clip, visibility and depth, read along the LAYER chain rather
    /// than the view chain: SwiftUI applies opacity and clipping to rendering
    /// layers that have no UIView of their own.
    static func measure(
        _ probe: BugReportProbeView,
        in window: UIWindow,
        presentationRoot: UIView
    ) -> BugReportProbeCandidate {
        let windowLayer = window.layer
        var hidden = probe.isHidden || probe.layer.isHidden
        var alpha = CGFloat(probe.layer.opacity)
        var clip: CGRect?
        var depth = 0

        var ancestor = probe.layer.superlayer
        while let layer = ancestor {
            depth += 1
            if layer.isHidden { hidden = true }
            alpha *= CGFloat(layer.opacity)
            if layer.masksToBounds {
                let bounds = layer.convert(layer.bounds, to: windowLayer)
                clip = clip.map { $0.intersection(bounds) } ?? bounds
            }
            if layer === windowLayer { break }
            ancestor = layer.superlayer
        }

        return BugReportProbeCandidate(
            frame: probe.convert(probe.bounds, to: window),
            clipRect: clip,
            depth: depth,
            isHiddenInHierarchy: hidden,
            cumulativeAlpha: alpha,
            isInAppWindow: probe.window === window,
            isInFrontmostPresentation: probe.isDescendant(of: presentationRoot),
            role: probe.role,
            label: probe.label,
            component: probe.component
        )
    }
}
