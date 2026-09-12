#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SiteVisitSingleChoiceControlTests: XCTestCase {
    private final class State: ObservableObject {
        let answer: SiteVisitChecklistAnswer
        @Published var value: SiteVisitChecklistValue
        init(answer: SiteVisitChecklistAnswer) { self.answer = answer; value = answer.answerValue }
        func update(_ value: SiteVisitChecklistValue) {
            answer.answerValue = value
            self.value = answer.answerValue
        }
    }

    private struct CaptureHarness: View {
        @ObservedObject var state: State
        var body: some View {
            ScrollView {
                SiteVisitChecklistAnswerRow(answer: state.answer, value: state.value,
                    onUpdate: state.update, onFlush: {}, onStartDeckDesign: {})
                    .padding(OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background)
        }
    }

    func testActualCaptureControlSelectsAndClearsThroughAccessibilityAtNarrowWidth() throws {
        let snapshot = SiteVisitSingleChoice(options: [.init(label: "Cedar"), .init(label: "Composite boards with concealed fasteners")])
        let answer = SiteVisitChecklistAnswer(siteVisitId: UUID().uuidString, companyId: UUID().uuidString,
            opportunityId: nil, siteVisitTypeId: nil, fieldId: "material", label: "Deck material", kind: .shortText,
            required: true, sortOrder: 0, answerValue: .init(text: "Original handwritten material", choiceSnapshot: snapshot))
        let state = State(answer: answer)
        try withHost(CaptureHarness(state: state).environment(\.sizeCategory, .accessibilityExtraLarge), width: 320) { host in
            XCTAssertTrue(waitUntil(host) { self.button("Cedar", in: host.view) != nil })
            XCTAssertTrue(nodes(host.view).contains { $0.accessibilityLabel == "Original handwritten material" })
            try capture(host, name: "single-choice-capture-legacy-text")
            let cedar = try XCTUnwrap(button("Cedar", in: host.view))
            try requireVisibleTarget(cedar, in: host.view)
            XCTAssertTrue(cedar.accessibilityActivate(), "The real control must expose an accessible action")
            XCTAssertTrue(waitUntil(host) { state.value.selectedOption?.id == snapshot.options[0].id })
            let selected = try XCTUnwrap(button("Cedar", in: host.view))
            XCTAssertTrue(selected.accessibilityTraits.contains(.selected))
            XCTAssertTrue(answer.isAnswered)
            try capture(host, name: "single-choice-capture-selected")
            let clear = try XCTUnwrap(button("CLEAR ANSWER", in: host.view))
            try requireVisibleTarget(clear, in: host.view)
            XCTAssertTrue(clear.accessibilityActivate())
            XCTAssertTrue(waitUntil(host) { !state.value.hasContent && self.button("CLEAR ANSWER", in: host.view) == nil })
            XCTAssertEqual(state.value.choiceSnapshot, snapshot)
            XCTAssertFalse(answer.isAnswered)
            XCTAssertFalse(try XCTUnwrap(button("Cedar", in: host.view)).accessibilityTraits.contains(.selected))
            try capture(host, name: "single-choice-capture-cleared")
        }
    }

    func testActualSettingsEditorRendersEditableOptionsAndAddsOneThroughAccessibility() throws {
        let snapshot = SiteVisitSingleChoice(options: [.init(label: "Cedar"), .init(label: "Composite")])
        let draft = SiteVisitTypeDraft(id: nil, slug: nil, name: "Deck survey", descriptionText: "Record site materials",
            isSystemTemplate: false, isDefault: false, fields: [
                .init(label: "Deck material", kind: .shortText, sortOrder: 0, singleChoice: snapshot)
            ])
        let controller = DataController()
        let view = SiteVisitTypeEditorView(draft: draft).environmentObject(controller)
        try withHost(view, width: 390) { host in
            XCTAssertTrue(waitUntil(host) { self.textFields(host.view).contains { $0.text == "Cedar" } })
            let scroll = try XCTUnwrap(scrollViews(host.view).first { $0.contentSize.height > $0.bounds.height })
            scroll.setContentOffset(CGPoint(x: -scroll.adjustedContentInset.left,
                y: max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            XCTAssertTrue(waitUntil(host) { self.button("ADD OPTION", in: host.view) != nil })
            let add = try XCTUnwrap(button("ADD OPTION", in: host.view))
            try requireVisibleTarget(add, in: host.view)
            for (label, enabled) in [
                ("Move option 1 up", false), ("Move option 1 down", true), ("Remove option 1", false),
                ("Move option 2 up", true), ("Move option 2 down", false), ("Remove option 2", false)
            ] {
                let target = try XCTUnwrap(button(label, in: host.view), label)
                try requireVisibleTarget(target, in: host.view, expectsEnabled: enabled)
            }
            try capture(host, name: "single-choice-settings-options")
            XCTAssertTrue(add.accessibilityActivate())
            XCTAssertTrue(waitUntil(host) { self.textFields(host.view).filter { $0.placeholder == "Option label" }.count == 3 })
            let fields = textFields(host.view).filter { $0.placeholder == "Option label" }
            XCTAssertEqual(fields.filter { $0.text == "Cedar" }.count, 1)
            XCTAssertEqual(fields.filter { $0.text == "Composite" }.count, 1)
            XCTAssertEqual(fields.filter { ($0.text ?? "").isEmpty }.count, 1)
        }
    }

    private func withHost<V: View>(_ content: V, width: CGFloat,
                                  _ assertions: (UIHostingController<AnyView>) throws -> Void) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let host = UIHostingController(rootView: AnyView(content.environment(\.colorScheme, .dark)))
        host.safeAreaRegions = []
        host.view.backgroundColor = UIColor(OPSStyle.Colors.background)
        let container = UIViewController()
        container.addChild(host); container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: width),
            host.view.heightAnchor.constraint(equalTo: container.view.heightAnchor)
        ])
        host.didMove(toParent: container)
        window.rootViewController = container
        var failure: Error?
        do {
            window.layoutIfNeeded(); host.view.layoutIfNeeded()
            XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)
            try assertions(host)
        } catch { failure = error }
        host.view.endEditing(true)
        window.rootViewController = originalRoot
        window.layoutIfNeeded()
        if let failure { throw failure }
    }

    private func button(_ label: String, in view: UIView) -> NSObject? {
        nodes(view).first { $0.accessibilityTraits.contains(.button) && $0.accessibilityLabel == label }
    }

    private func nodes(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(node)).inserted else { return }
            if node.isAccessibilityElement { result.append(node) }
            for case let child as NSObject in node.accessibilityElements ?? [] { visit(child, depth: depth + 1) }
            let count = node.accessibilityElementCount()
            if count != NSNotFound, count > 0, count < 500 {
                for index in 0..<count {
                    if let child = node.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                }
            }
            if let view = node as? UIView { view.subviews.forEach { visit($0, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return result
    }

    private func textFields(_ view: UIView) -> [UITextField] {
        ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
    }
    private func scrollViews(_ view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    private func waitUntil(_ host: UIHostingController<AnyView>, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 4)
        var previous = "", stableSince: Date?
        while Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.view.layoutIfNeeded()
            let fingerprint = nodes(host.view).map {
                "\($0.accessibilityLabel ?? "")|\($0.accessibilityFrame)|\($0.accessibilityTraits.rawValue)"
            }.joined(separator: ";")
            if condition(), fingerprint == previous {
                if stableSince == nil { stableSince = Date() }
                if Date().timeIntervalSince(stableSince!) >= 0.25 { return true }
            } else { stableSince = nil }
            previous = fingerprint
        }
        return false
    }

    private func requireVisibleTarget(_ node: NSObject, in view: UIView, expectsEnabled: Bool = true) throws {
        let viewport = UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
        XCTAssertGreaterThanOrEqual(node.accessibilityFrame.width, OPSStyle.Layout.touchTargetMin)
        XCTAssertGreaterThanOrEqual(node.accessibilityFrame.height, OPSStyle.Layout.touchTargetMin)
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(node.accessibilityFrame), "Target must be visible in the real viewport")
        XCTAssertEqual(node.accessibilityTraits.contains(.notEnabled), !expectsEnabled)
        XCTAssertNotNil(view.window)
    }

    private func capture(_ host: UIHostingController<AnyView>, name: String) throws {
        let view = host.view!
        XCTAssertTrue(waitUntil(host) { !self.nodes(view).isEmpty })
        let viewport = UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
        for node in nodes(view) where node.accessibilityFrame.intersects(viewport) {
            XCTAssertGreaterThanOrEqual(node.accessibilityFrame.minX, viewport.minX - 0.5)
            XCTAssertLessThanOrEqual(node.accessibilityFrame.maxX, viewport.maxX + 0.5)
        }
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let geometry = XCTAttachment(string: nodes(view).map { "\($0.accessibilityLabel ?? ""): \($0.accessibilityFrame) traits=\($0.accessibilityTraits.rawValue)" }.joined(separator: "\n"))
        geometry.name = name + "-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let bright = stride(from: 0, to: pixels.count, by: 4).filter { max(pixels[$0], max(pixels[$0 + 1], pixels[$0 + 2])) > 90 }.count
        XCTAssertGreaterThan(bright, 100, "The hosted view must draw actual visible content")
    }
}
#endif
