//
//  SiteVisitTypeSettingsKeyboardTests.swift
//  OPSTests
//
//  The real settings sheet's SwiftUI text fields must receive the app-wide
//  UIKit DONE accessory. These tests deliberately do not install or start it.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SiteVisitTypeSettingsKeyboardTests: XCTestCase {
    @MainActor
    private final class SheetState: ObservableObject {
        @Published var isPresented = false
        let dataController = DataController()
        let draft = SiteVisitTypeDraft(
            id: nil,
            slug: nil,
            name: "",
            descriptionText: "",
            isSystemTemplate: false,
            isDefault: false,
            fields: [SiteVisitTypeFieldDefinition(
                label: "",
                kind: .shortText,
                sortOrder: 10
            )]
        )
    }

    private struct SheetHarness: View {
        @ObservedObject var state: SheetState

        var body: some View {
            OPSStyle.Colors.background
                .ignoresSafeArea()
                .sheet(isPresented: $state.isPresented) {
                    NavigationStack {
                        SiteVisitTypeEditorView(draft: state.draft)
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

    func testVisitNameReceivesVisibleDoneInTheRealEditorSheet() throws {
        try withEditorSheet { sheet, inputs in
            let accessory = try focus(inputs.name)
            inputs.name.insertText("Exterior survey")
            XCTAssertTrue(waitUntil { inputs.name.text == "Exterior survey" })
            try attachVisibleAccessory(accessory, name: "site-visit-type-name-done")

            accessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !inputs.name.isFirstResponder })
            XCTAssertNotNil(sheet.presentingViewController, "DONE must leave the settings editor open")

            _ = try focus(inputs.description)
            inputs.description.insertText("Check access.")
            _ = try focus(inputs.name)
            XCTAssertEqual(inputs.name.text, "Exterior survey", "The name draft must survive another field's update")
        }
    }

    func testChecklistFieldLabelReceivesVisibleDoneInTheRealEditorSheet() throws {
        try withEditorSheet { sheet, inputs in
            let accessory = try focus(inputs.fieldLabel)
            inputs.fieldLabel.insertText("Access width")
            XCTAssertTrue(waitUntil { inputs.fieldLabel.text == "Access width" })
            try attachVisibleAccessory(accessory, name: "site-visit-checklist-field-label-done")

            accessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !inputs.fieldLabel.isFirstResponder })
            XCTAssertNotNil(sheet.presentingViewController, "DONE must leave the settings editor open")

            _ = try focus(inputs.name)
            inputs.name.insertText("Exterior survey")
            _ = try focus(inputs.fieldLabel)
            XCTAssertEqual(inputs.fieldLabel.text, "Access width", "The field-label draft must survive another field's update")
        }
    }

    func testDoneFollowsFocusBetweenAllThreeSettingsInputsWithoutLosingDrafts() throws {
        try withEditorSheet { sheet, inputs in
            let nameAccessory = try focus(inputs.name)
            inputs.name.insertText("Exterior survey")

            let descriptionAccessory = try focus(inputs.description)
            inputs.description.insertText("Measure opening.\nCheck access.")
            XCTAssertFalse(inputs.name.isFirstResponder)
            XCTAssertFalse(descriptionAccessory === nameAccessory)

            let labelAccessory = try focus(inputs.fieldLabel)
            inputs.fieldLabel.insertText("Access width")
            XCTAssertFalse(inputs.description.isFirstResponder)
            XCTAssertFalse(labelAccessory === descriptionAccessory)
            XCTAssertFalse(labelAccessory === nameAccessory)

            labelAccessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !inputs.fieldLabel.isFirstResponder })
            XCTAssertFalse(inputs.name.isFirstResponder)
            XCTAssertFalse(inputs.description.isFirstResponder)
            XCTAssertNotNil(sheet.presentingViewController)

            let refocusedNameAccessory = try focus(inputs.name)
            XCTAssertTrue(refocusedNameAccessory === nameAccessory)
            inputs.name.selectedTextRange = inputs.name.textRange(
                from: inputs.name.endOfDocument,
                to: inputs.name.endOfDocument
            )
            inputs.name.insertText(" final")
            refocusedNameAccessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !inputs.name.isFirstResponder })

            _ = try focus(inputs.description)
            XCTAssertEqual(inputs.description.text, "Measure opening.\nCheck access.")
            XCTAssertEqual(inputs.name.text, "Exterior survey final")
            XCTAssertEqual(inputs.fieldLabel.text, "Access width")
            descriptionAccessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !inputs.description.isFirstResponder })
        }
    }

    private func withEditorSheet(
        _ assertions: (UIViewController, Inputs) throws -> Void
    ) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let state = SheetState()
        let host = UIHostingController(rootView: SheetHarness(state: state))
        window.rootViewController = host
        defer {
            state.isPresented = false
            host.presentedViewController?.view.endEditing(true)
            host.dismiss(animated: false)
            XCTAssertTrue(waitUntil { host.presentedViewController == nil })
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        state.isPresented = true

        XCTAssertTrue(waitUntil {
            guard let sheet = host.presentedViewController else { return false }
            return sheet.view.window != nil
                && descendants(of: UITextField.self, in: sheet.view).count == 2
                && descendants(of: UITextView.self, in: sheet.view).count == 1
        }, "The real Site Visit Type editor must present its name, description and custom field label")
        let sheet = try XCTUnwrap(host.presentedViewController)
        let fields = descendants(of: UITextField.self, in: sheet.view)
        let inputs = try Inputs(
            name: XCTUnwrap(fields.first { $0.placeholder == "Visit type name" }),
            description: XCTUnwrap(descendants(of: UITextView.self, in: sheet.view).first {
                $0.accessibilityLabel == "DESCRIPTION"
            }),
            fieldLabel: XCTUnwrap(fields.first { $0.placeholder == "Field label" })
        )
        try assertions(sheet, inputs)
    }

    private func focus(_ field: UITextField) throws -> OPSKeyboardDoneAccessoryView {
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertTrue(waitUntil {
            field.isFirstResponder && field.inputAccessoryView is OPSKeyboardDoneAccessoryView
        }, "The app's real editing observer must install DONE on the SwiftUI text field")
        return try visibleAccessory(field.inputAccessoryView)
    }

    private func focus(_ textView: UITextView) throws -> OPSKeyboardDoneAccessoryView {
        XCTAssertTrue(textView.becomeFirstResponder())
        XCTAssertTrue(waitUntil { textView.isFirstResponder })
        return try visibleAccessory(textView.inputAccessoryView)
    }

    private func visibleAccessory(_ view: UIView?) throws -> OPSKeyboardDoneAccessoryView {
        let accessory = try XCTUnwrap(view as? OPSKeyboardDoneAccessoryView)
        let isVisible = waitUntil {
            guard let window = accessory.window else { return false }
            let frame = accessory.doneButton.convert(accessory.doneButton.bounds, to: window)
            return !window.isHidden && !accessory.isHidden && !accessory.doneButton.isHidden
                && accessory.alpha > 0 && accessory.doneButton.alpha > 0
                && frame.width >= OPSStyle.Layout.touchTargetMin
                && frame.height >= OPSStyle.Layout.touchTargetMin
                && window.bounds.contains(frame)
        }
        _ = try XCTUnwrap(
            isVisible ? accessory : nil,
            "DONE must be attached and visible with a full touch target; run with the simulator software keyboard enabled"
        )
        XCTAssertEqual(accessory.doneButton.accessibilityIdentifier, "ops.keyboard.done")
        XCTAssertTrue(accessory.doneButton.isEnabled)
        return accessory
    }

    private func attachVisibleAccessory(_ accessory: OPSKeyboardDoneAccessoryView, name: String) throws {
        accessory.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: accessory.bounds).image { _ in
            XCTAssertTrue(accessory.drawHierarchy(in: accessory.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }
}
#endif
