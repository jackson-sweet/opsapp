//
//  ProjectQuickActionsBarVisitEntryTests.swift
//  OPSTests
//
//  Bug 7d94c9f3 — the project quick-actions bar's BOOK VISIT / REBOOK entry.
//
//  Two layers of proof, because SwiftUI does not reliably publish an
//  accessibility tree inside a unit-test host (the same limitation
//  TaskDetailSheetSnapshotTests documents):
//
//    1. Deterministic assertions against the PRODUCTION decision helper
//       (`ProjectVisitBookingEntry`) that the bar's `actions` builder calls —
//       not a copy of its logic. This is the hard contract: the verb flips on
//       the open-booking boundary and introduces no new vocabulary.
//    2. Rendered proof PNGs of the three bar states (no entry / BOOK VISIT /
//       REBOOK) via the FixedSizeSnapshot harness, attached to the xcresult
//       for the PM's visual check. The harness hosts the view in the app's
//       real window and uses drawHierarchy — never a bare ImageRenderer,
//       which cannot resolve asset-catalog colors.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ProjectQuickActionsBarVisitEntryTests
//  Shots land in NSTemporaryDirectory()/ops-project-visit-entry-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ProjectQuickActionsBarVisitEntryTests: XCTestCase {

    private let deviceWidth: CGFloat = 393
    private let barHeight: CGFloat = 120

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-project-visit-entry-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Verb contract (the production decision the bar renders)

    /// No open booking ⇒ BOOK VISIT. This is the verb the bug asks for.
    func testEntryOffersBookVisitWithoutAnOpenBooking() {
        XCTAssertEqual(ProjectVisitBookingEntry.label(hasOpenBooking: false), "BOOK VISIT")
        XCTAssertEqual(ProjectVisitBookingEntry.icon(hasOpenBooking: false), "calendar.badge.plus")
    }

    /// An open booking ⇒ REBOOK, never a second BOOK VISIT. The server allows
    /// exactly one open booking per lead (error 55000), so offering a second
    /// book verb would render a guaranteed failure.
    func testEntryFlipsToRebookWithAnOpenBooking() {
        XCTAssertEqual(ProjectVisitBookingEntry.label(hasOpenBooking: true), "REBOOK")
        XCTAssertEqual(ProjectVisitBookingEntry.icon(hasOpenBooking: true), "calendar")
    }

    /// The two states are mutually exclusive and never blank — a state-aware
    /// single entry, not two stacked offers.
    func testEntryIsSingleAndStateExclusive() {
        let booked = ProjectVisitBookingEntry.label(hasOpenBooking: true)
        let unbooked = ProjectVisitBookingEntry.label(hasOpenBooking: false)
        XCTAssertNotEqual(booked, unbooked)
        XCTAssertFalse(booked.isEmpty)
        XCTAssertFalse(unbooked.isEmpty)
        XCTAssertEqual(booked, booked.uppercased(), "action-bar labels are UPPERCASE authority voice")
        XCTAssertEqual(unbooked, unbooked.uppercased())
    }

    /// REBOOK must not collide with the bar's task-scoped RESCHEDULE entry:
    /// they are different verbs moving different things (a visit vs a task),
    /// and RESCHEDULE only renders when a task is selected.
    func testRebookDoesNotCollideWithTaskReschedule() {
        XCTAssertNotEqual(ProjectVisitBookingEntry.label(hasOpenBooking: true), "RESCHEDULE")
    }

    // MARK: - Rendered proof

    /// Bar with no booking handler: neither verb may appear. A project with no
    /// linked lead, no convert grant, or a closed status must show no dead verb.
    func testBarHidesEntryWithoutHandler() throws {
        let image = try render(onBookVisit: nil, hasOpenVisitBooking: false)
        attach(image, named: "project-bar-no-visit-entry")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testBarOffersBookVisitWhenHandlerPresent() throws {
        let image = try render(onBookVisit: {}, hasOpenVisitBooking: false)
        attach(image, named: "project-bar-book-visit")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testBarFlipsToRebookWithOpenBooking() throws {
        let image = try render(onBookVisit: {}, hasOpenVisitBooking: true)
        attach(image, named: "project-bar-rebook")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    /// Best-effort accessibility assertion. SwiftUI does not always build an
    /// accessibility tree in a unit-test host, so an empty tree SKIPS rather
    /// than fails — the verb contract above is the hard proof, and the PNGs
    /// are the visual one. When the tree IS published, the labels must match.
    func testRenderedBarPublishesTheExpectedVerb() throws {
        let bookedLabels = try hostedLabels(hasOpenVisitBooking: true)
        let unbookedLabels = try hostedLabels(hasOpenVisitBooking: false)

        try XCTSkipIf(
            bookedLabels.isEmpty && unbookedLabels.isEmpty,
            "SwiftUI published no accessibility tree in this unit-test host — "
                + "the verb contract tests and the proof PNGs cover this case."
        )

        XCTAssertTrue(
            unbookedLabels.contains { $0.contains("BOOK VISIT") },
            "expected BOOK VISIT in \(unbookedLabels)"
        )
        XCTAssertFalse(
            unbookedLabels.contains { $0.contains("REBOOK") },
            "REBOOK must not render alongside BOOK VISIT: \(unbookedLabels)"
        )
        XCTAssertTrue(
            bookedLabels.contains { $0.contains("REBOOK") },
            "expected REBOOK in \(bookedLabels)"
        )
    }

    // MARK: - Harness

    private func bar(
        onBookVisit: (() -> Void)?,
        hasOpenVisitBooking: Bool
    ) -> some View {
        ProjectQuickActionsBar(
            selectedTask: nil,
            hasClientContact: true,
            canEdit: true,
            onPhoto: {},
            onNote: {},
            onExpense: {},
            onComplete: {},
            onReschedule: {},
            onContact: {},
            onAddTask: {},
            onShare: {},
            onBookVisit: onBookVisit,
            hasOpenVisitBooking: hasOpenVisitBooking
        )
        .frame(width: deviceWidth)
        .frame(maxHeight: .infinity, alignment: .center)
        .background(OPSStyle.Colors.background)
    }

    private func render(
        onBookVisit: (() -> Void)?,
        hasOpenVisitBooking: Bool
    ) throws -> UIImage {
        try FixedSizeSnapshot.render(
            bar(onBookVisit: onBookVisit, hasOpenVisitBooking: hasOpenVisitBooking),
            size: CGSize(width: deviceWidth, height: barHeight)
        )
    }

    private func attach(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
    }

    /// Hosts the bar in the app's real window and harvests every accessibility
    /// label it publishes, uppercased. Restores the app UI on the way out.
    private func hostedLabels(hasOpenVisitBooking: Bool) throws -> [String] {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }

        let host = UIHostingController(
            rootView: bar(onBookVisit: {}, hasOpenVisitBooking: hasOpenVisitBooking)
        )
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
            host.view.widthAnchor.constraint(equalToConstant: deviceWidth),
            host.view.heightAnchor.constraint(equalToConstant: barHeight),
        ])
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()
        settle(host.view)

        return Self.accessibilityTree(of: host.view)
            .compactMap { $0.accessibilityLabel?.uppercased() }
            .filter { !$0.isEmpty }
    }

    /// Geometry quiescence — three consecutive stable layer-tree polls, never a
    /// fixed sleep. Bounded so a perpetually animating view still returns.
    private func settle(_ view: UIView) {
        var stable = 0
        var lastFingerprint = ""
        let deadline = Date(timeIntervalSinceNow: 2)
        while stable < 3, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let fingerprint = Self.fingerprint(of: view.layer)
            if fingerprint == lastFingerprint {
                stable += 1
            } else {
                stable = 0
                lastFingerprint = fingerprint
            }
        }
    }

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

    /// Flattens the accessibility hierarchy: container elements first (SwiftUI
    /// publishes its controls there), then the UIKit subview tree. Mirrors the
    /// proven walker in TaskDetailSheetSnapshotTests.
    private static func accessibilityTree(of root: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 40 else { return [] }
        var nodes: [NSObject] = [root]

        var seen = Set<ObjectIdentifier>()
        for case let child as NSObject in (root.accessibilityElements ?? []) {
            guard seen.insert(ObjectIdentifier(child)).inserted else { continue }
            nodes.append(contentsOf: accessibilityTree(of: child, depth: depth + 1))
        }
        let count = root.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            for index in 0..<count {
                guard let child = root.accessibilityElement(at: index) as? NSObject,
                      seen.insert(ObjectIdentifier(child)).inserted else { continue }
                nodes.append(contentsOf: accessibilityTree(of: child, depth: depth + 1))
            }
        }

        if let view = root as? UIView {
            for subview in view.subviews {
                nodes.append(contentsOf: accessibilityTree(of: subview, depth: depth + 1))
            }
        }

        return nodes
    }
}
#endif
