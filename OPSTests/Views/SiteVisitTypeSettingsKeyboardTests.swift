//
//  SiteVisitTypeSettingsKeyboardTests.swift
//  OPSTests
//
//  Real editor, with the production fullScreenCover(item:) -> sheet(item:)
//  presentation structure. The two settings container views are fixtures:
//  Settings routing, template seeding and server refresh are not exercised.
//  AppDelegate and UIKit editing notifications alone install the accessory.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
import CryptoKit
@testable import OPS

@MainActor
final class SiteVisitTypeSettingsKeyboardTests: XCTestCase {
    private enum Destination: String, Identifiable {
        case siteVisitTypes
        var id: String { rawValue }
    }

    @MainActor
    private final class SheetState: ObservableObject {
        @Published var destination: Destination?
        @Published var editorDraft: SiteVisitTypeDraft?

        let dataController = DataController()
        let draft = SiteVisitTypeDraft(
            id: nil, slug: nil, name: "", descriptionText: "",
            isSystemTemplate: false, isDefault: false,
            fields: [SiteVisitTypeFieldDefinition(label: "", kind: .shortText, sortOrder: 10)]
        )
    }

    private struct SettingsContainer: View {
        @ObservedObject var state: SheetState

        var body: some View {
            OPSStyle.Colors.background.ignoresSafeArea()
                .fullScreenCover(item: $state.destination) { _ in
                    NavigationStack {
                        TypesContainer(state: state)
                    }
                }
        }
    }

    private struct TypesContainer: View {
        @ObservedObject var state: SheetState

        var body: some View {
            OPSStyle.Colors.background.ignoresSafeArea()
                .sheet(item: $state.editorDraft) { draft in
                    NavigationStack {
                        SiteVisitTypeEditorView(draft: draft)
                            .environmentObject(state.dataController)
                    }
                }
        }
    }

    private struct Inputs {
        let name: UITextField
        let description: UITextView
        let fieldLabel: UITextField
    }

    private struct Session {
        let window: UIWindow
        let root: UIViewController
        let cover: UIViewController
        let sheet: UIViewController
        let state: SheetState
        let keyboard: KeyboardObservation
    }

    @MainActor
    private final class KeyboardObservation: NSObject {
        private(set) var isVisible = false
        private(set) var frame = CGRect.zero
        private(set) var shownCount = 0
        private(set) var hiddenCount = 0
        private(set) var pending = Set<Notification.Name>()
        private(set) var lastEvent = CACurrentMediaTime()
        private(set) var editingEvents: [String] = []
        private let startedAt = CACurrentMediaTime()
        weak var accessoryWindow: UIWindow?

        override init() {
            super.init()
            for name in [
                UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification,
                UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification
            ] {
                NotificationCenter.default.addObserver(self, selector: #selector(receive(_:)), name: name, object: nil)
            }
            for name in [
                UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification
            ] {
                NotificationCenter.default.addObserver(self, selector: #selector(receiveEditing(_:)), name: name, object: nil)
            }
        }

        func stop() { NotificationCenter.default.removeObserver(self) }

        func recordEditing(_ phase: String, responder: UIView?) {
            let elapsed = CACurrentMediaTime() - startedAt
            editingEvents.append("\(elapsed): \(phase)\n\(Self.describe(responder))")
        }

        static func describe(_ responder: UIView?) -> String {
            guard let responder else { return "responder=nil" }
            func describeView(_ view: UIView?) -> String {
                guard let view else { return "nil" }
                return "\(type(of: view))@\(ObjectIdentifier(view)) frame=\(view.frame) bounds=\(view.bounds) screen=\(UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)) window=\(view.window.map { String(describing: ObjectIdentifier($0)) } ?? "nil") superview=\(view.superview.map { String(describing: type(of: $0)) } ?? "nil")"
            }
            return """
            responder=\(describeView(responder)) firstResponder=\(responder.isFirstResponder)
            accessory=\(describeView(responder.inputAccessoryView)) canonical=\(responder.inputAccessoryView is OPSKeyboardDoneAccessoryView)
            accessoryController=\(responder.inputAccessoryViewController.map { String(describing: type(of: $0)) } ?? "nil")
            """
        }

        @objc private func receiveEditing(_ notification: Notification) {
            guard let responder = notification.object as? UIView else { return }
            let phase = notification.name.rawValue
            recordEditing("\(phase) immediate", responder: responder)
            // Observe UIKit's real notification and the following main-queue
            // turn. Never install an accessory or synthesize an editing event.
            DispatchQueue.main.async { [weak self, weak responder] in
                self?.recordEditing("\(phase) next main-queue turn", responder: responder)
            }
        }

        @objc private func receive(_ notification: Notification) {
            guard notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false else { return }
            lastEvent = CACurrentMediaTime()
            if let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                frame = value.cgRectValue
            }
            switch notification.name {
            case UIResponder.keyboardWillShowNotification:
                pending.insert(UIResponder.keyboardDidShowNotification)
            case UIResponder.keyboardWillHideNotification:
                pending.insert(UIResponder.keyboardDidHideNotification)
            case UIResponder.keyboardWillChangeFrameNotification:
                pending.insert(UIResponder.keyboardDidChangeFrameNotification)
            case UIResponder.keyboardDidShowNotification:
                pending.remove(notification.name)
                shownCount += 1
                isVisible = true
            case UIResponder.keyboardDidHideNotification:
                pending.remove(notification.name)
                hiddenCount += 1
                isVisible = false
            case UIResponder.keyboardDidChangeFrameNotification:
                pending.remove(notification.name)
            default: break
            }
        }
    }

    func testVisitNameReceivesVisibleDoneInTheRealEditorSheet() throws {
        try withEditorSheet { session in
            var inputs = try self.inputs(in: session)
            let accessory = try focus(inputs.name, in: session)
            inputs.name.insertText("Exterior survey")
            try captureContext(session, accessory: accessory, name: "site-visit-type-name-keyboard")
            inputs = try dismissDone(accessory, active: inputs.name, in: session)
            try captureContext(session, name: "site-visit-type-name-after-done")

            _ = try focus(inputs.description, in: session)
            inputs.description.insertText("Check access.")
            _ = try focus(inputs.name, in: session)
            XCTAssertEqual(inputs.name.text, "Exterior survey", "The name draft must survive another field's update")
        }
    }

    func testChecklistFieldLabelReceivesVisibleDoneInTheRealEditorSheet() throws {
        try withEditorSheet { session in
            var inputs = try self.inputs(in: session)
            let accessory = try focus(inputs.fieldLabel, in: session)
            inputs.fieldLabel.insertText("Access width")
            try captureContext(session, accessory: accessory, name: "site-visit-checklist-field-label-keyboard")
            inputs = try dismissDone(accessory, active: inputs.fieldLabel, in: session)
            try captureContext(session, name: "site-visit-checklist-field-label-after-done")

            _ = try focus(inputs.name, in: session)
            inputs.name.insertText("Exterior survey")
            _ = try focus(inputs.fieldLabel, in: session)
            XCTAssertEqual(inputs.fieldLabel.text, "Access width", "The field-label draft must survive another field's update")
        }
    }

    func testDoneFollowsFocusBetweenAllThreeSettingsInputsWithoutLosingDrafts() throws {
        try withEditorSheet { session in
            var inputs = try self.inputs(in: session)
            let nameAccessory = try focus(inputs.name, in: session)
            inputs.name.insertText("Exterior survey")
            let descriptionAccessory = try focus(inputs.description, in: session)
            inputs.description.insertText("Measure opening.\nCheck access.")
            XCTAssertFalse(inputs.name.isFirstResponder)
            XCTAssertFalse(descriptionAccessory === nameAccessory)

            let labelAccessory = try focus(inputs.fieldLabel, in: session)
            inputs.fieldLabel.insertText("Access width")
            XCTAssertFalse(inputs.description.isFirstResponder)
            XCTAssertFalse(labelAccessory === descriptionAccessory)
            XCTAssertFalse(labelAccessory === nameAccessory)
            inputs = try dismissDone(labelAccessory, active: inputs.fieldLabel, in: session)

            let refocusedNameAccessory = try focus(inputs.name, in: session)
            XCTAssertTrue(refocusedNameAccessory === nameAccessory)
            inputs.name.selectedTextRange = inputs.name.textRange(
                from: inputs.name.endOfDocument, to: inputs.name.endOfDocument
            )
            inputs.name.insertText(" final")
            inputs = try dismissDone(refocusedNameAccessory, active: inputs.name, in: session)

            let refocusedDescriptionAccessory = try focus(inputs.description, in: session)
            XCTAssertTrue(refocusedDescriptionAccessory === descriptionAccessory)
            XCTAssertEqual(inputs.description.text, "Measure opening.\nCheck access.")
            XCTAssertEqual(inputs.name.text, "Exterior survey final")
            XCTAssertEqual(inputs.fieldLabel.text, "Access width")
            _ = try dismissDone(refocusedDescriptionAccessory, active: inputs.description, in: session)
        }
    }

    private func withEditorSheet(_ assertions: (Session) throws -> Void) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let keyboard = KeyboardObservation()
        let state = SheetState()
        let host = UIHostingController(rootView: SettingsContainer(state: state))
        window.endEditing(true)
        window.rootViewController = host
        var assertionError: Error?
        do {
            window.layoutIfNeeded()
            state.destination = .siteVisitTypes
            try require(waitUntil {
                guard let cover = host.presentedViewController else { return false }
                return cover.view.window === window && !cover.isBeingPresented && cover.transitionCoordinator == nil
            }, "The settings cover must finish presenting before its editor opens")
            let cover = try XCTUnwrap(host.presentedViewController)
            state.editorDraft = state.draft
            try require(waitUntil { cover.presentedViewController != nil }, "The editor sheet must present from the settings cover")
            let session = try Session(
                window: window, root: host, cover: cover,
                sheet: XCTUnwrap(cover.presentedViewController), state: state, keyboard: keyboard
            )
            try settle(session) { self.hasInputs(in: session.sheet.view) }
            _ = try inputs(in: session)
            try assertions(session)
        } catch {
            assertionError = error
        }

        // Do not pump UIKit's run loop while a Swift error unwinds through a
        // defer. Preserve and rethrow the original error after all cleanup so
        // framework-internal caught errors cannot obscure the failing phase.
        print("SiteVisitKeyboard teardown: keyboard hide")
        window.endEditing(true)
        XCTAssertTrue(waitUntil { keyboard.pending.isEmpty && !keyboard.isVisible })
        // Let SwiftUI dismiss each presentation before changing its parent.
        print("SiteVisitKeyboard teardown: editor sheet")
        state.editorDraft = nil
        XCTAssertTrue(waitUntil {
            guard let cover = host.presentedViewController else { return true }
            return cover.presentedViewController == nil && cover.transitionCoordinator == nil
        })
        print("SiteVisitKeyboard teardown: settings cover")
        state.destination = nil
        XCTAssertTrue(waitUntil {
            host.presentedViewController == nil && host.transitionCoordinator == nil
        })
        print("SiteVisitKeyboard teardown: original root")
        window.rootViewController = originalRoot
        window.layoutIfNeeded()
        keyboard.stop()
        print("SiteVisitKeyboard teardown: complete")
        if let assertionError { throw assertionError }
    }

    private func hasInputs(in view: UIView) -> Bool {
        let fields = descendants(of: UITextField.self, in: view)
        return fields.contains { $0.placeholder == "Visit type name" }
            && fields.contains { $0.placeholder == "Field label" }
            && descendants(of: UITextView.self, in: view).contains { $0.accessibilityLabel == "DESCRIPTION" }
    }

    private func inputs(in session: Session) throws -> Inputs {
        try require(sheetIsPresented(session), "The same editor must remain attached after presentation quiescence")
        let fields = descendants(of: UITextField.self, in: session.sheet.view)
        return try Inputs(
            name: XCTUnwrap(fields.first { $0.placeholder == "Visit type name" }),
            description: XCTUnwrap(descendants(of: UITextView.self, in: session.sheet.view).first {
                $0.accessibilityLabel == "DESCRIPTION"
            }),
            fieldLabel: XCTUnwrap(fields.first { $0.placeholder == "Field label" })
        )
    }

    private func focus(_ responder: UIView, in session: Session) throws -> OPSKeyboardDoneAccessoryView {
        let wasVisible = session.keyboard.isVisible
        let shownCount = session.keyboard.shownCount
        session.keyboard.recordEditing("before becomeFirstResponder", responder: responder)
        let acceptedFocus = responder.becomeFirstResponder()
        session.keyboard.recordEditing("after becomeFirstResponder accepted=\(acceptedFocus)", responder: responder)
        try require(acceptedFocus, "The real editor must accept UIKit focus")
        try settle(session, tracking: responder) {
            guard responder.isFirstResponder,
                  let accessory = responder.inputAccessoryView as? OPSKeyboardDoneAccessoryView else { return false }
            return session.keyboard.isVisible
                && (wasVisible || session.keyboard.shownCount > shownCount)
                && self.doneIsVisible(accessory, in: session)
        }
        let accessory = try XCTUnwrap(responder.inputAccessoryView as? OPSKeyboardDoneAccessoryView)
        session.keyboard.accessoryWindow = accessory.window
        return accessory
    }

    private func dismissDone(
        _ accessory: OPSKeyboardDoneAccessoryView, active: UIView, in session: Session
    ) throws -> Inputs {
        try require(doneIsVisible(accessory, in: session), "Only the visible, hittable DONE may be exercised")
        let hiddenCount = session.keyboard.hiddenCount
        accessory.doneButton.sendActions(for: .touchUpInside)
        try settle(session) {
            !active.isFirstResponder && !session.keyboard.isVisible && session.keyboard.hiddenCount > hiddenCount
        }
        // Re-resolve the actual sheet's current fields after didHide and settled
        // presentation geometry; stale UITextField references prove no retention.
        return try inputs(in: session)
    }

    private func sheetIsPresented(_ session: Session) -> Bool {
        session.state.destination != nil && session.state.editorDraft != nil
            && session.root.presentedViewController === session.cover
            && session.cover.presentedViewController === session.sheet
            && session.sheet.presentingViewController === session.cover
            && session.sheet.view.window === session.window
            && !session.cover.isBeingDismissed && !session.cover.isBeingPresented
            && !session.sheet.isBeingDismissed && !session.sheet.isBeingPresented
            && session.cover.transitionCoordinator == nil && session.sheet.transitionCoordinator == nil
    }

    private let tolerance: CGFloat = 0.5
    private let quietInterval: CFTimeInterval = 0.25

    /// Wait for completed keyboard notifications and continuously unchanged
    /// model/presentation geometry. Do not accept an in-flight sheet dismissal.
    private func settle(
        _ session: Session, tracking view: UIView? = nil, ready: () -> Bool = { true }
    ) throws {
        var previous = ""
        var stableSince = CACurrentMediaTime()
        let deadline = CACurrentMediaTime() + 5
        while CACurrentMediaTime() < deadline {
            session.window.layoutIfNeeded()
            session.sheet.view.layoutIfNeeded()
            view?.inputAccessoryView?.window?.layoutIfNeeded()
            let current = presentationFingerprint(session, tracking: view)
            let now = CACurrentMediaTime()
            let prepared = sheetIsPresented(session) && session.keyboard.pending.isEmpty && ready()
            if !prepared || current != previous { stableSince = now }
            if prepared && now - stableSince >= quietInterval && now - session.keyboard.lastEvent >= quietInterval {
                return
            }
            previous = current
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        let attachment = XCTAttachment(string: presentationFingerprint(session, tracking: view))
        attachment.name = "site-visit-keyboard-unsettled-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        captureFailureDiagnostics(session, tracking: view)
        try require(false, "Keyboard and the same editor sheet did not finish settling; inspect focus diagnostics before classifying the failure")
    }

    private func captureFailureDiagnostics(_ session: Session, tracking view: UIView?) {
        let liveInputs = descendants(of: UITextField.self, in: session.sheet.view).map { $0 as UIView }
            + descendants(of: UITextView.self, in: session.sheet.view).map { $0 as UIView }
        let accessory = view?.inputAccessoryView as? OPSKeyboardDoneAccessoryView
        let diagnostics = """
        App delegate: \(UIApplication.shared.delegate.map { String(describing: type(of: $0)) } ?? "nil")
        Keyboard shown=\(session.keyboard.shownCount) hidden=\(session.keyboard.hiddenCount) pending=\(session.keyboard.pending.map(\.rawValue).sorted())
        Tracked field still in live sheet: \(view.map { tracked in liveInputs.contains { $0 === tracked } } ?? false)
        Tracked: \(KeyboardObservation.describe(view))
        DONE gate: \(accessory.map { doneVisibilityFailure($0, in: session) ?? "visible" } ?? "tracked input has no canonical accessory")
        Live inputs:\n\(liveInputs.map { KeyboardObservation.describe($0) }.joined(separator: "\n"))
        Real editing event timeline:\n\(session.keyboard.editingEvents.joined(separator: "\n"))
        """
        let text = XCTAttachment(string: diagnostics)
        text.name = "site-visit-keyboard-focus-diagnostics"
        text.lifetime = .keepAlways
        add(text)

        // Best-effort failure context, explicitly separate from passing proof.
        // Remote keyboard pixels may be unavailable when its accessory is not
        // attached; no nonblank or visibility claim is made for this attachment.
        let screen = session.window.screen.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var windows = session.window.windowScene?.windows ?? [session.window]
        if let accessoryWindow = view?.inputAccessoryView?.window,
           !windows.contains(where: { $0 === accessoryWindow }) { windows.append(accessoryWindow) }
        windows.sort { $0.windowLevel < $1.windowLevel }
        let image = UIGraphicsImageRenderer(bounds: screen, format: format).image { context in
            UIColor(OPSStyle.Colors.background).setFill()
            context.fill(screen)
            for window in windows where !window.isHidden && window.alpha > 0.01 {
                for hostedView in window.subviews where !hostedView.isHidden && hostedView.alpha > 0.01 {
                    let frame = screenFrame(hostedView)
                    guard frame.intersects(screen) else { continue }
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: frame.minX, y: frame.minY)
                    hostedView.drawHierarchy(in: CGRect(origin: .zero, size: frame.size), afterScreenUpdates: true)
                    context.cgContext.restoreGState()
                }
            }
        }
        let context = XCTAttachment(image: image)
        context.name = "site-visit-keyboard-failure-context-unverified"
        context.lifetime = .keepAlways
        add(context)
    }

    private func presentationFingerprint(_ session: Session, tracking view: UIView?) -> String {
        var value = "sheet=\(sheetIsPresented(session)) keyboard=\(session.keyboard.isVisible)|\(session.keyboard.frame)|\(session.keyboard.pending.map(\.rawValue).sorted())"
        value += visualFingerprint(session.sheet.view)
        value += visualFingerprint(session.cover.view)
        for scroll in descendants(of: UIScrollView.self, in: session.sheet.view) {
            value += "|\(scroll.contentOffset)|\(scroll.contentSize)|\(scroll.adjustedContentInset)"
        }
        if let view {
            value += visualFingerprint(view)
            if let accessory = view.inputAccessoryView { value += visualFingerprint(accessory) }
        }
        return value
    }

    private func visualFingerprint(_ view: UIView) -> String {
        var result = ""
        var next: UIView? = view
        while let current = next {
            result += "|\(screenFrame(current))|\(current.bounds)|\(current.isHidden)|\(current.alpha)|\(current.layer.transform)"
            if let presentation = current.layer.presentation() {
                result += "|presentation=\(presentation.frame)|\(presentation.bounds)|\(presentation.opacity)|\(presentation.transform)"
            }
            next = current.superview
        }
        return result
    }

    private func doneIsVisible(_ accessory: OPSKeyboardDoneAccessoryView, in session: Session) -> Bool {
        doneVisibilityFailure(accessory, in: session) == nil
    }

    private func doneVisibilityFailure(_ accessory: OPSKeyboardDoneAccessoryView, in session: Session) -> String? {
        let button = accessory.doneButton
        guard let window = button.window, window.screen === session.window.screen,
              button.isEnabled, button.accessibilityIdentifier == "ops.keyboard.done" else {
            return "DONE detached, on another screen, disabled, or missing its identifier"
        }
        let frame = screenFrame(button)
        let screen = window.screen.bounds
        let keyboard = session.keyboard.frame.intersection(screen)
        guard frame.width >= OPSStyle.Layout.touchTargetMin - tolerance,
              frame.height >= OPSStyle.Layout.touchTargetMin - tolerance,
              screen.contains(frame), screenFrame(window).contains(frame),
              keyboard.height > accessory.bounds.height + OPSStyle.Layout.touchTargetMin,
              frame.minY >= keyboard.minY - tolerance, frame.maxY <= keyboard.maxY + tolerance else {
            return "DONE geometry invalid: button=\(frame) accessory=\(accessory.bounds) keyboard=\(keyboard) window=\(screenFrame(window))"
        }

        var effectiveAlpha: Float = 1
        var next: UIView? = button
        while let current = next {
            guard !current.isHidden, current.alpha > 0.01, !current.layer.isHidden,
                  current.layer.opacity > 0.01 else { return "Hidden or transparent DONE ancestor: \(type(of: current))" }
            effectiveAlpha *= current.layer.presentation()?.opacity ?? current.layer.opacity
            if let presentation = current.layer.presentation() {
                guard !presentation.isHidden, presentation.opacity > 0.01,
                      abs(presentation.frame.minX - current.layer.frame.minX) <= tolerance,
                      abs(presentation.frame.minY - current.layer.frame.minY) <= tolerance,
                      abs(presentation.frame.width - current.layer.frame.width) <= tolerance,
                      abs(presentation.frame.height - current.layer.frame.height) <= tolerance else {
                    return "Unsettled DONE ancestor: \(type(of: current)) model=\(current.layer.frame) presentation=\(presentation.frame)"
                }
            }
            if current.clipsToBounds && !screenFrame(current).insetBy(dx: -tolerance, dy: -tolerance).contains(frame) {
                return "Clipped DONE ancestor: \(type(of: current)) frame=\(screenFrame(current)) button=\(frame)"
            }
            next = current.superview
        }
        guard effectiveAlpha > 0.01 else { return "DONE combined opacity=\(effectiveAlpha)" }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let point = window.convert(center, from: window.screen.coordinateSpace)
        guard let hit = window.hitTest(point, with: nil) else { return "DONE center hit no view" }
        return hit === button || hit.isDescendant(of: button) ? nil : "DONE center hit \(type(of: hit))"
    }

    private func screenFrame(_ view: UIView) -> CGRect {
        UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
    }

    private struct ScreenCaptureRequest: Encodable {
        let requestID: String
        let name: String
        let bundleID: String
        let simulatorUDID: String
        let requestedAt: TimeInterval
    }

    private struct ScreenCaptureReply: Decodable {
        let requestID: String
        let name: String
        let bundleID: String
        let simulatorUDID: String
        let captureStartedAt: TimeInterval
        let completedAt: TimeInterval
        let sha256: String?
        let error: String?
    }

    /// This visual integration suite requires the documented host-side
    /// capture_keyboard_screens.py launcher. Missing capture fails, never skips.
    private func requestScreenCapture(name: String) throws -> (data: Data, provenance: String) {
        let simulator = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "Keyboard pixel proof requires the dedicated simulator launcher")
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        try require(bundle == "co.opsapp.ops.OPS", "Capture requests must belong to the OPS app host")
        let cache = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
            .appendingPathComponent("OPSKeyboardScreenshotProof", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let request = ScreenCaptureRequest(requestID: id, name: name, bundleID: bundle, simulatorUDID: simulator, requestedAt: Date().timeIntervalSince1970)
        try JSONEncoder().encode(request).write(to: cache.appendingPathComponent("\(id).request.json"), options: .atomic)
        let replyURL = cache.appendingPathComponent("\(id).ack.json")
        try require(waitUntil(timeout: 20) { FileManager.default.fileExists(atPath: replyURL.path) }, "No simulator screenshot acknowledgment within 20 seconds; run capture_keyboard_screens.py before this visual suite")
        let reply = try JSONDecoder().decode(ScreenCaptureReply.self, from: Data(contentsOf: replyURL))
        try require(reply.requestID == id && reply.name == name && reply.bundleID == bundle && reply.simulatorUDID.caseInsensitiveCompare(simulator) == .orderedSame, "The screenshot acknowledgment must match this exact request and simulator")
        try require(reply.error == nil, "Simulator screen capture failed: \(reply.error ?? "unknown")")
        try require(reply.captureStartedAt >= request.requestedAt && reply.completedAt >= reply.captureStartedAt && reply.completedAt <= Date().timeIntervalSince1970 + 1, "The screenshot must be captured after its fresh request")
        let data = try Data(contentsOf: cache.appendingPathComponent("\(id).png"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try require(reply.sha256 == digest, "The raw screenshot must match the acknowledged image bytes")
        return (data, "simctl io screenshot; request=\(id); started=\(reply.captureStartedAt); completed=\(reply.completedAt); sha256=\(digest)")
    }

    /// Capture the device's actual composited screen. Hosted drawHierarchy
    /// omits remote keys, and hosted XCUIScreen is denied UI-testing authority.
    private func captureContext(
        _ session: Session, accessory: OPSKeyboardDoneAccessoryView? = nil, name: String
    ) throws {
        let responder = descendants(of: UITextField.self, in: session.sheet.view).first { $0.isFirstResponder } as UIView?
            ?? descendants(of: UITextView.self, in: session.sheet.view).first { $0.isFirstResponder }
        try settle(session, tracking: responder)
        if let accessory { try require(doneIsVisible(accessory, in: session), "The captured DONE must be visible") }
        let screen = session.window.screen.bounds
        let before = presentationFingerprint(session, tracking: responder)
        let screenshot = try requestScreenCapture(name: name)
        // Preserve the untouched system capture even if validation below fails.
        let attachment = XCTAttachment(data: screenshot.data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let nativeImage = try XCTUnwrap(UIImage(data: screenshot.data), "The simulator must return a PNG screenshot")
        let after = presentationFingerprint(session, tracking: responder)
        let geometry = XCTAttachment(string: """
        Route scope: fixture settings cover -> fixture type list sheet -> actual SiteVisitTypeEditorView
        Capture source: \(screenshot.provenance), no view composition
        Screen: \(screen)
        Native image: \(nativeImage.size) scale=\(nativeImage.scale) orientation=\(nativeImage.imageOrientation.rawValue)
        Sheet: \(screenFrame(session.sheet.view))
        Keyboard completed frame: \(session.keyboard.frame)
        DONE: \(accessory.map { screenFrame($0.doneButton) } ?? .zero)
        Before capture: \(before)
        After capture: \(after)
        """)
        geometry.name = "\(name)-screen-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)

        let horizontalScale = nativeImage.size.width / screen.width
        let verticalScale = nativeImage.size.height / screen.height
        try require(
            horizontalScale.isFinite && verticalScale.isFinite && horizontalScale > 0 && verticalScale > 0
                && abs(horizontalScale - verticalScale) < 0.001,
            "The system screenshot must cover the full screen with a uniform coordinate scale"
        )
        // Normalize only the real screenshot pixels to one pixel per screen
        // point. Nothing from the editor or an accessory view is composited in.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: screen, format: format).image { _ in
            nativeImage.draw(in: screen)
        }

        if let accessory {
            let keyboard = session.keyboard.frame.intersection(screen)
            let pixels = try XCTUnwrap(image.cgImage?.cropping(to: keyboard.integral), "The real screen must contain the keyboard region")
            let crop = XCTAttachment(image: UIImage(cgImage: pixels))
            crop.name = "\(name)-keyboard-only"
            crop.lifetime = .keepAlways
            add(crop)
            let keyTop = max(keyboard.minY, screenFrame(accessory).maxY)
            let keys = CGRect(x: keyboard.minX, y: keyTop, width: keyboard.width, height: max(0, keyboard.maxY - keyTop))
            try assertNonblank(image, region: keys, message: "The system screenshot has no visible keyboard keys; full keyboard proof is unavailable")
            try require(doneIsVisible(accessory, in: session), "DONE must remain visible through the system capture")
        }
        try require(before == after, "The editor and keyboard geometry must stay unchanged during capture")
        try require(session.window.windowScene?.activationState == .foregroundActive, "The captured editor must stay in the foreground scene")
        var editorRegion = screenFrame(session.sheet.view).intersection(screen)
        if accessory != nil { editorRegion.size.height = max(0, min(editorRegion.maxY, session.keyboard.frame.minY) - editorRegion.minY) }
        try assertNonblank(image, region: editorRegion, message: "The editor context rendered blank")
    }

    private func assertNonblank(_ image: UIImage, region: CGRect, message: String) throws {
        let pixels = try XCTUnwrap(image.cgImage?.cropping(to: region.integral), message)
        var luma = [UInt8](repeating: 0, count: pixels.width * pixels.height)
        try luma.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bytesPerRow: pixels.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        }
        try require(luma.filter { $0 > 90 }.count > 100, message)
    }

    private enum HarnessError: Error { case assertion }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            XCTFail(message)
            throw HarnessError.assertion
        }
    }

    private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }
}
#endif
