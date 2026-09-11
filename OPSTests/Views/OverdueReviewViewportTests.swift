//
//  OverdueReviewViewportTests.swift
//  OPSTests
//
//  070a36d4: overdue review must remain a vertical document, including long
//  project/task names on narrow iPhones and at accessibility Dynamic Type.
//  Measures the actual queried view, not OverdueReviewPresentation's decisions.
//  PNGs are proof attachments, not golden-image comparisons or device proof.
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class OverdueReviewViewportTests: XCTestCase {
    private struct Viewport {
        let name: String
        let size: CGSize
        let topInset: CGFloat
        let bottomInset: CGFloat
        let dynamicType: DynamicTypeSize

        // iPhone SE's supported 375pt width and compact height; safe areas are
        // fixture inputs so the result does not depend on the runner's model.
        static let narrow = Viewport(
            name: "375-standard", size: CGSize(width: 375, height: 667),
            topInset: 20, bottomInset: 0, dynamicType: .large
        )
        static let reference = Viewport(
            name: "390-standard", size: CGSize(width: 390, height: 844),
            topInset: 59, bottomInset: 34, dynamicType: .large
        )
        static let accessibility = Viewport(
            name: "375-accessibility5", size: CGSize(width: 375, height: 667),
            topInset: 20, bottomInset: 0, dynamicType: .accessibility5
        )
    }

    private struct Fixture {
        // ModelContext does not retain ModelContainer. Keep this owner alive
        // until every hosted query, layout pass and capture has finished.
        let container: ModelContainer
        let controller: DataController
        let tasks: [ProjectTask]

        var actionLabels: Set<String> {
            Set(tasks.map { "MARK DONE: \($0.displayTitle)" })
        }
    }

    func testLongRowsStayWithinNarrowViewport() throws {
        try assertVerticalReview(in: .narrow)
    }

    func testLongRowsStayWithinReferenceViewport() throws {
        try assertVerticalReview(in: .reference)
    }

    func testLongRowsStayWithinNarrowViewportAtLargestAccessibilityType() throws {
        try assertVerticalReview(in: .accessibility)
    }

    /// Kept separate from the scroll/pixel tests: a simulator without AX
    /// bridging must not silently skip the horizontal-overflow regression.
    func testEveryCompletionActionIsReachableAtStandardAndAccessibilityType() throws {
        try requireAccessibilityBridging()
        for viewport in [Viewport.narrow, .accessibility] {
            try withReview(in: viewport) { host, fixture in
                var reached = Set<String>()
                try visitDocument(in: host.view, includingAccessibility: true) { scroll, _ in
                    let screenViewport = UIAccessibility.convertToScreenCoordinates(
                        host.view.bounds, in: host.view
                    )
                    let scrollViewport = UIAccessibility.convertToScreenCoordinates(
                        scroll.bounds, in: scroll
                    )
                    let nodes = accessibilityNodes(in: host.view)
                    let actions = nodes.filter { fixture.actionLabels.contains($0.label) }

                    for action in actions where verticallyIntersects(action.frame, scrollViewport) {
                        assertHorizontalContainment(
                            action.frame, in: scrollViewport, message: action.label
                        )
                        if action.frame.minY >= scrollViewport.minY - tolerance,
                           action.frame.maxY <= scrollViewport.maxY + tolerance {
                            reached.insert(action.label)
                            XCTAssertGreaterThanOrEqual(
                                action.frame.width, OPSStyle.Layout.touchTargetMin - tolerance,
                                "\(action.label) must keep its field touch target"
                            )
                            XCTAssertGreaterThanOrEqual(
                                action.frame.height, OPSStyle.Layout.touchTargetMin - tolerance,
                                "\(action.label) must keep its field touch target"
                            )
                        }
                    }

                    // Also inspect visible title/metadata nodes: a narrow
                    // scroll content size alone cannot detect clipped labels.
                    for node in nodes where verticallyIntersects(node.frame, scrollViewport) {
                        assertHorizontalContainment(
                            node.frame, in: screenViewport, message: node.label
                        )
                    }

                    let later = try XCTUnwrap(
                        nodes.first { $0.label == "Later" },
                        "The persistent Later action must remain measurable"
                    )
                    assertHorizontalContainment(later.frame, in: screenViewport, message: "Later")
                    XCTAssertGreaterThanOrEqual(later.frame.minY, scrollViewport.maxY - tolerance)
                    XCTAssertLessThanOrEqual(later.frame.maxY, screenViewport.maxY + tolerance)
                }
                XCTAssertEqual(
                    reached, fixture.actionLabels,
                    "Every completion action must fit fully on screen during vertical review"
                )
            }
        }
    }

    private let tolerance: CGFloat = 0.5

    private func assertVerticalReview(in viewport: Viewport) throws {
        try withReview(in: viewport) { host, _ in
            try visitDocument(in: host.view) { scroll, position in
                if position == "top" || position == "bottom" {
                    try capture(
                        host.view, scroll: scroll,
                        name: "overdue-review-\(viewport.name)-\(position)"
                    )
                }
            }
        }
    }

    /// Visits overlapping vertical slices so every lazy row is materialized.
    /// The bottom offset is recomputed after each settle: LazyVStack can revise
    /// its height estimate as long rows come into view.
    private func visitDocument(
        in view: UIView,
        includingAccessibility: Bool = false,
        inspect: (UIScrollView, String) throws -> Void
    ) throws {
        try settle(view, includingAccessibility: includingAccessibility) {
            scrollViews(in: view).contains {
                $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height
            }
        }
        let scroll = try XCTUnwrap(scrollViews(in: view).first)
        let initialY = -scroll.adjustedContentInset.top
        scroll.setContentOffset(CGPoint(x: -scroll.adjustedContentInset.left, y: initialY), animated: false)
        try settle(view, includingAccessibility: includingAccessibility)

        var reachedBottom = false
        for step in 0..<100 {
            let allScrolls = scrollViews(in: view)
            XCTAssertEqual(allScrolls.count, 1, "Overdue review must have one vertical scroll owner")
            for candidate in allScrolls {
                let horizontalRange = max(
                    0,
                    candidate.contentSize.width + candidate.adjustedContentInset.left
                        + candidate.adjustedContentInset.right - candidate.bounds.width
                )
                XCTAssertLessThanOrEqual(horizontalRange, tolerance, "Review content can pan sideways")
                XCTAssertFalse(candidate.alwaysBounceHorizontal, "Review must not invite a horizontal gesture")
                XCTAssertEqual(
                    candidate.contentOffset.x, -candidate.adjustedContentInset.left,
                    accuracy: tolerance, "Vertical review must not drift sideways"
                )
                assertHorizontalContainment(
                    candidate.convert(candidate.bounds, to: view), in: view.bounds,
                    message: "Review scroll viewport"
                )
            }

            let bottom = max(
                initialY,
                scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            )
            reachedBottom = abs(scroll.contentOffset.y - bottom) <= tolerance
            try inspect(scroll, step == 0 ? "top" : reachedBottom ? "bottom" : "middle")
            if reachedBottom { break }

            let nextY = min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.45)
            XCTAssertGreaterThan(nextY, scroll.contentOffset.y, "Review must make vertical progress")
            scroll.setContentOffset(
                CGPoint(x: -scroll.adjustedContentInset.left, y: nextY), animated: false
            )
            try settle(view, includingAccessibility: includingAccessibility)
        }
        XCTAssertTrue(reachedBottom, "Every overdue row must be reachable within the bounded traversal")
        XCTAssertGreaterThan(scroll.contentOffset.y, initialY + tolerance, "Fixture must exercise real vertical scrolling")
    }

    private func withReview(
        in viewport: Viewport,
        perform: (UIHostingController<AnyView>, Fixture) throws -> Void
    ) throws {
        let fixture = try makeFixture()
        defer { withExtendedLifetime(fixture) {} }

        let host = UIHostingController(rootView: AnyView(
            OverdueTasksPromptView()
                .environmentObject(fixture.controller)
                .modelContainer(fixture.container)
                .environment(\.dynamicTypeSize, viewport.dynamicType)
                .environment(\.colorScheme, .dark)
                // Reserve the target phone's system safe areas. UIKit's own
                // safe-area passthrough is disabled below to avoid adding the
                // runner phone's different insets on top of these fixtures.
                .padding(.top, viewport.topInset)
                .padding(.bottom, viewport.bottomInset)
                .background(OPSStyle.Colors.background)
        ))
        host.overrideUserInterfaceStyle = .dark
        host.safeAreaRegions = []

        let container = UIViewController()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: viewport.size.width),
            host.view.heightAnchor.constraint(equalToConstant: viewport.size.height)
        ])
        host.didMove(toParent: container)

        let window = try AppHostWindow.acquire()
        let previousRoot = window.rootViewController
        defer {
            window.rootViewController = previousRoot
            window.layoutIfNeeded()
        }
        window.rootViewController = container
        window.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.size, viewport.size)
        try perform(host, fixture)
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OPSSchemaCurrent.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let user = User(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            firstName: "Review", lastName: "Operator", role: .admin,
            companyId: companyId
        )
        context.insert(user)
        let controller = DataController()
        controller.currentUser = user

        let today = Calendar.current.startOfDay(for: Date())
        var tasks: [ProjectTask] = []
        for index in 0..<8 {
            let project = Project(
                id: String(format: "cccccccc-cccc-4ccc-8ccc-%012d", index),
                title: "\(index + 1) — North Shore Community Centre exterior rehabilitation and weatherproofing",
                status: .inProgress
            )
            project.companyId = companyId
            context.insert(project)
            let task = ProjectTask(
                id: String(format: "dddddddd-dddd-4ddd-8ddd-%012d", index),
                projectId: project.id, taskTypeId: "viewport-task-type",
                companyId: companyId
            )
            // Alternate natural wrapping and a long unbroken field value.
            task.customTitle = index.isMultiple(of: 2)
                ? "\(index + 1) — Remove damaged flashing, replace the waterproof membrane and inspect every balcony connection before closing the access scaffolding"
                : "\(index + 1) — Inspect \(String(repeating: "WESTBALCONY", count: 6)) and complete the documented punch list"
            task.endDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: index - 30, to: today))
            task.setTeamMemberIds([user.id])
            task.project = project
            context.insert(task)
            project.tasks = [task]
            tasks.append(task)
        }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectTask>()), tasks.count)
        XCTAssertTrue(tasks.allSatisfy { $0.isOverdue && $0.getTeamMemberIds().contains(user.id) })
        return Fixture(container: container, controller: controller, tasks: tasks)
    }

    // MARK: - Geometry and accessibility

    /// A ready predicate prevents quiescence in an empty @Query state from
    /// passing. Subsequent waits include scroll offsets, content sizes and the
    /// entire laid-out view tree. AX cases additionally wait for published
    /// labels/frames to stop changing after each scroll, since that pipeline
    /// can trail UIKit layout. No fixed pre-assertion sleep is used.
    private func settle(
        _ view: UIView,
        includingAccessibility: Bool = false,
        ready: () -> Bool = { true }
    ) throws {
        var previous = ""
        var stablePolls = 0
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            view.window?.layoutIfNeeded()
            view.layoutIfNeeded()
            var current = fingerprint(view)
            if includingAccessibility {
                current += "|AX|" + accessibilityNodes(in: view)
                    .map { "\($0.label)|\($0.frame)" }
                    .sorted()
                    .joined(separator: ";")
            }
            stablePolls = ready() && current == previous ? stablePolls + 1 : 0
            if stablePolls >= 3 { return }
            previous = current
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTFail("Overdue review did not reach ready, stable geometry within three seconds")
        throw HarnessError.unsettled
    }

    private enum HarnessError: Error { case unsettled }

    private func fingerprint(_ view: UIView) -> String {
        var value = "\(view.frame)|\(view.bounds)|\(view.isHidden)|\(view.alpha)"
        if let scroll = view as? UIScrollView {
            value += "|\(scroll.contentSize)|\(scroll.contentOffset)|\(scroll.adjustedContentInset)"
        }
        return value + view.subviews.map { fingerprint($0) }.joined(separator: ";")
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private struct AXNode {
        let label: String
        let frame: CGRect
    }

    private func accessibilityNodes(in view: UIView) -> [AXNode] {
        var seen = Set<ObjectIdentifier>()
        var result: [AXNode] = []
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement, let label = object.accessibilityLabel,
               !label.isEmpty, !object.accessibilityFrame.isEmpty {
                result.append(AXNode(label: label, frame: object.accessibilityFrame))
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count {
                    if let element = object.accessibilityElement(at: index) as? NSObject { visit(element) }
                }
            }
            if let childView = object as? UIView { childView.subviews.forEach { visit($0) } }
        }
        visit(view)
        return result
    }

    private func requireAccessibilityBridging() throws {
        let window = try AppHostWindow.acquire()
        let previousRoot = window.rootViewController
        defer {
            window.rootViewController = previousRoot
            window.layoutIfNeeded()
        }
        let probe = UIHostingController(rootView: Button("overdue-ax-probe") {})
        window.rootViewController = probe
        window.layoutIfNeeded()
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            if accessibilityNodes(in: probe.view).contains(where: { $0.label == "overdue-ax-probe" }) {
                try settle(probe.view, includingAccessibility: true)
                return
            }
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        throw XCTSkip(
            "SwiftUI AX bridging is unavailable. Enable AccessibilityEnabled and ApplicationAccessibilityEnabled in com.apple.Accessibility for this simulator, then reboot. Scroll/pixel tests remain independently runnable."
        )
    }

    private func verticallyIntersects(_ frame: CGRect, _ viewport: CGRect) -> Bool {
        frame.maxY > viewport.minY && frame.minY < viewport.maxY
    }

    private func assertHorizontalContainment(_ frame: CGRect, in viewport: CGRect, message: String) {
        XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - tolerance, "\(message) extends past the leading edge")
        XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + tolerance, "\(message) extends past the trailing edge")
    }

    // MARK: - Screenshot proof

    private func capture(_ view: UIView, scroll: UIScrollView, name: String) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            rendered = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "The app-hosted view must draw successfully")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let geometry = XCTAttachment(string: """
            host: \(view.bounds)
            scroll viewport: \(scroll.convert(scroll.bounds, to: view))
            content: \(scroll.contentSize)
            insets: \(scroll.adjustedContentInset)
            offset: \(scroll.contentOffset)
            """)
        geometry.name = "\(name)-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)

        // Exclude the fixed title/footer: a blank task ledger must not pass
        // merely because OVERDUE and Later produced some nonblack pixels.
        let ledger = scroll.convert(scroll.bounds, to: view).intersection(view.bounds)
        let pixels = try XCTUnwrap(image.cgImage?.cropping(to: ledger.integral))
        var luma = [UInt8](repeating: 0, count: pixels.width * pixels.height)
        try luma.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bytesPerRow: pixels.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        }
        XCTAssertGreaterThan(luma.filter { $0 > 90 }.count, 100, "The task ledger rendered blank")
    }
}
#endif
