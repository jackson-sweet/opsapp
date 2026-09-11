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
        }

        func stop() { NotificationCenter.default.removeObserver(self) }

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
        defer {
            window.endEditing(true)
            state.editorDraft = nil
            state.destination = nil
            host.dismiss(animated: false)
            XCTAssertTrue(waitUntil { host.presentedViewController == nil })
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
            keyboard.stop()
        }
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
        try require(responder.becomeFirstResponder(), "The real editor must accept UIKit focus")
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
        try require(false, "Keyboard and the same editor sheet did not finish settling; software keyboard must be enabled")
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
        let button = accessory.doneButton
        guard let window = button.window, window.screen === session.window.screen,
              button.isEnabled, button.accessibilityIdentifier == "ops.keyboard.done" else { return false }
        let frame = screenFrame(button)
        let screen = window.screen.bounds
        let keyboard = session.keyboard.frame.intersection(screen)
        guard frame.width >= OPSStyle.Layout.touchTargetMin - tolerance,
              frame.height >= OPSStyle.Layout.touchTargetMin - tolerance,
              screen.contains(frame), screenFrame(window).contains(frame),
              keyboard.height > accessory.bounds.height + OPSStyle.Layout.touchTargetMin,
              frame.minY >= keyboard.minY - tolerance, frame.maxY <= keyboard.maxY + tolerance else { return false }

        var effectiveAlpha: Float = 1
        var next: UIView? = button
        while let current = next {
            guard !current.isHidden, current.alpha > 0.01, !current.layer.isHidden,
                  current.layer.opacity > 0.01 else { return false }
            effectiveAlpha *= current.layer.presentation()?.opacity ?? current.layer.opacity
            if let presentation = current.layer.presentation() {
                guard !presentation.isHidden, presentation.opacity > 0.01,
                      abs(presentation.frame.minX - current.layer.frame.minX) <= tolerance,
                      abs(presentation.frame.minY - current.layer.frame.minY) <= tolerance,
                      abs(presentation.frame.width - current.layer.frame.width) <= tolerance,
                      abs(presentation.frame.height - current.layer.frame.height) <= tolerance else { return false }
            }
            if current.clipsToBounds && !screenFrame(current).insetBy(dx: -tolerance, dy: -tolerance).contains(frame) {
                return false
            }
            next = current.superview
        }
        guard effectiveAlpha > 0.01 else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let point = window.convert(center, from: window.screen.coordinateSpace)
        guard let hit = window.hitTest(point, with: nil) else { return false }
        return hit === button || hit.isDescendant(of: button)
    }

    private func screenFrame(_ view: UIView) -> CGRect {
        UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
    }

    /// Full screen-sized context drawn from the real windows' hosted views,
    /// never UIWindow.drawHierarchy and never a cropped accessory-only canvas.
    /// System keyboard pixels may live in a separate window. Compose both in
    /// screen coordinates and fail explicitly if its key area cannot render.
    private func captureContext(
        _ session: Session, accessory: OPSKeyboardDoneAccessoryView? = nil, name: String
    ) throws {
        let responder = descendants(of: UITextField.self, in: session.sheet.view).first { $0.isFirstResponder } as UIView?
            ?? descendants(of: UITextView.self, in: session.sheet.view).first { $0.isFirstResponder }
        try settle(session, tracking: responder)
        if let accessory { try require(doneIsVisible(accessory, in: session), "The captured DONE must be visible") }
        let screen = session.window.screen.bounds
        var windows = session.window.windowScene?.windows ?? [session.window]
        if let keyboardWindow = accessory?.window ?? session.keyboard.accessoryWindow,
           !windows.contains(where: { $0 === keyboardWindow }) { windows.append(keyboardWindow) }
        windows = windows.enumerated().sorted {
            if $0.element.windowLevel == $1.element.windowLevel { return $0.offset < $1.offset }
            return $0.element.windowLevel < $1.element.windowLevel
        }.map(\.element)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Validate keyboard pixels on a separate transparent canvas first.
        // Editor text beneath an unrenderable remote keyboard must never make
        // the keyboard's key-region check pass in the combined image.
        let keyboardImage = try accessory.map {
            try captureKeyboard($0, in: session, screen: screen, format: format, name: name)
        }
        var drawingSucceeded = true
        let image = UIGraphicsImageRenderer(bounds: screen, format: format).image { context in
            UIColor(OPSStyle.Colors.background).setFill()
            context.fill(screen)
            for window in windows where !window.isHidden && window.alpha > 0.01 {
                for hostedView in window.subviews where !hostedView.isHidden && hostedView.alpha > 0.01 {
                    let frame = screenFrame(hostedView)
                    guard frame.intersects(screen) else { continue }
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: frame.minX, y: frame.minY)
                    drawingSucceeded = hostedView.drawHierarchy(
                        in: CGRect(origin: .zero, size: frame.size), afterScreenUpdates: true
                    ) && drawingSucceeded
                    context.cgContext.restoreGState()
                }
            }
            keyboardImage?.draw(in: screen)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let geometry = XCTAttachment(string: """
        Route scope: fixture settings cover -> fixture type list sheet -> actual SiteVisitTypeEditorView
        Screen: \(screen)
        Sheet: \(screenFrame(session.sheet.view))
        Keyboard completed frame: \(session.keyboard.frame)
        DONE: \(accessory.map { screenFrame($0.doneButton) } ?? .zero)
        \(presentationFingerprint(session, tracking: responder))
        """)
        geometry.name = "\(name)-screen-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        try require(drawingSucceeded, "The app and keyboard hosted views must render successfully")

        var editorRegion = screenFrame(session.sheet.view).intersection(screen)
        if accessory != nil { editorRegion.size.height = max(0, min(editorRegion.maxY, session.keyboard.frame.minY) - editorRegion.minY) }
        try assertNonblank(image, region: editorRegion, message: "The editor context rendered blank")
    }

    private func captureKeyboard(
        _ accessory: OPSKeyboardDoneAccessoryView, in session: Session,
        screen: CGRect, format: UIGraphicsImageRendererFormat, name: String
    ) throws -> UIImage {
        let window = try XCTUnwrap(accessory.window)
        let hostedViews: [UIView]
        if window !== session.window {
            hostedViews = window.subviews
        } else {
            // Find a keyboard branch independent of the editor. No private
            // UIKit class-name assumptions: reject a shared app-root subtree.
            var branch: UIView = accessory
            while let parent = branch.superview, parent !== window,
                  !session.sheet.view.isDescendant(of: parent),
                  !parent.isDescendant(of: session.sheet.view) {
                branch = parent
            }
            try require(
                branch !== accessory && !session.sheet.view.isDescendant(of: branch)
                    && !branch.isDescendant(of: session.sheet.view),
                "An independent keyboard hosted view is unavailable; full keyboard capture cannot be claimed"
            )
            hostedViews = [branch]
        }
        var rendered = true
        let image = UIGraphicsImageRenderer(bounds: screen, format: format).image { context in
            context.cgContext.clear(screen)
            for view in hostedViews where !view.isHidden && view.alpha > 0.01 {
                let frame = screenFrame(view)
                guard frame.intersects(screen) else { continue }
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: frame.minX, y: frame.minY)
                rendered = view.drawHierarchy(
                    in: CGRect(origin: .zero, size: frame.size), afterScreenUpdates: true
                ) && rendered
                context.cgContext.restoreGState()
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name)-keyboard-only"
        attachment.lifetime = .keepAlways
        add(attachment)
        try require(rendered, "The independent keyboard hosted view must render successfully")
        let keyboard = session.keyboard.frame.intersection(screen)
        let keyTop = max(keyboard.minY, screenFrame(accessory).maxY)
        let keys = CGRect(x: keyboard.minX, y: keyTop, width: keyboard.width, height: max(0, keyboard.maxY - keyTop))
        try assertNonblank(image, region: keys, message: "System keyboard keys did not render independently; this is not full keyboard proof")
        return image
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
