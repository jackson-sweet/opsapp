//
//  SiteVisitTypeSettingsInputTests.swift
//  OPSTests
//
//  Description geometry and keyboard regressions reported in site-visit settings.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SiteVisitTypeSettingsInputTests: XCTestCase {
    private final class Draft: ObservableObject {
        @Published var text = ""
        @Published var isEditable = true
        @Published var unrelatedChange = false
    }

    private struct EditorHarness: View {
        @ObservedObject var draft: Draft

        var body: some View {
            VStack {
                FormTextEditor(
                    title: draft.unrelatedChange ? "DESCRIPTION UPDATED" : "DESCRIPTION",
                    placeholder: "What this visit is for",
                    text: $draft.text,
                    isEditable: draft.isEditable,
                    height: OPSStyle.Layout.inputHeight * 2
                )
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background)
        }
    }

    func testDescriptionCaretAndPlaceholderShareTokenizedInsets() throws {
        try withEditor { _, host, textView in
            let inset = OPSStyle.Layout.spacing3
            XCTAssertEqual(textView.textContainerInset, UIEdgeInsets(
                top: inset, left: inset, bottom: inset, right: inset
            ))
            XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
            XCTAssertEqual(textView.font, OPSStyle.Typography.uiBody)
            XCTAssertEqual(textView.backgroundColor, .clear)
            XCTAssertEqual(textView.accessibilityLabel, "DESCRIPTION")

            let placeholder = try XCTUnwrap(
                descendants(of: UILabel.self, in: textView).first {
                    $0.text == "What this visit is for"
                }
            )
            host.view.layoutIfNeeded()
            textView.layoutIfNeeded()
            XCTAssertFalse(placeholder.isHidden)
            XCTAssertFalse(placeholder.isAccessibilityElement)
            XCTAssertEqual(placeholder.font, textView.font)
            XCTAssertEqual(placeholder.frame.minX, inset, accuracy: 0.5)
            XCTAssertEqual(placeholder.frame.minY, inset, accuracy: 0.5)
            XCTAssertEqual(
                textView.caretRect(for: textView.beginningOfDocument).minX,
                placeholder.frame.minX,
                accuracy: 0.5
            )
            XCTAssertEqual(textView.bounds.height, OPSStyle.Layout.inputHeight * 2, accuracy: 0.5)
            XCTAssertTrue(textView.isScrollEnabled)
        }
    }

    func testPreparedDoneDismissesDescriptionWithoutLosingMultilineDraft() throws {
        try withEditor { draft, host, textView in
            XCTAssertFalse(textView.isFirstResponder)
            let accessory = try XCTUnwrap(
                textView.inputAccessoryView as? OPSKeyboardDoneAccessoryView,
                "The description must own DONE before the first focus notification"
            )
            XCTAssertTrue(textView.becomeFirstResponder())
            XCTAssertTrue(waitUntil { textView.isFirstResponder })

            let description = "Measure deck.\nCheck access and framing."
            textView.insertText(description)
            XCTAssertTrue(waitUntil { draft.text == description })
            let selection = NSRange(location: 8, length: 0)
            textView.selectedRange = selection
            draft.unrelatedChange = true
            XCTAssertTrue(waitUntil { textView.accessibilityLabel == "DESCRIPTION UPDATED" })
            host.view.layoutIfNeeded()
            XCTAssertTrue(textView.isFirstResponder)
            XCTAssertEqual(textView.selectedRange, selection)
            XCTAssertTrue(textView.inputAccessoryView === accessory)

            accessory.doneButton.sendActions(for: .touchUpInside)
            XCTAssertTrue(waitUntil { !textView.isFirstResponder })
            XCTAssertEqual(draft.text, description)
            XCTAssertNotNil(host.view.window, "DONE must leave the editor open")

            XCTAssertTrue(textView.becomeFirstResponder())
            XCTAssertTrue(textView.inputAccessoryView === accessory)
            textView.resignFirstResponder()
        }
    }

    func testDescriptionBindingChangesUpdateTextAndPlaceholder() throws {
        try withEditor { draft, _, textView in
            let placeholder = try XCTUnwrap(descendants(of: UILabel.self, in: textView).first)
            draft.text = "Measure deck\nCheck access"
            XCTAssertTrue(waitUntil { textView.text == draft.text })
            XCTAssertTrue(placeholder.isHidden)

            textView.selectedRange = NSRange(location: (draft.text as NSString).length, length: 0)
            draft.text = "Short"
            XCTAssertTrue(waitUntil { textView.text == "Short" })
            XCTAssertLessThanOrEqual(NSMaxRange(textView.selectedRange), 5)

            draft.text = ""
            XCTAssertTrue(waitUntil { textView.text.isEmpty && !placeholder.isHidden })
        }
    }

    func testDescriptionKeepsMarkedTextDuringSurroundingViewUpdates() throws {
        try withEditor { draft, _, textView in
            XCTAssertTrue(textView.becomeFirstResponder())
            textView.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
            XCTAssertNotNil(textView.markedTextRange)
            let composingText = textView.text

            draft.unrelatedChange = true
            XCTAssertTrue(waitUntil { textView.accessibilityLabel == "DESCRIPTION UPDATED" })
            XCTAssertEqual(textView.text, composingText)
            XCTAssertNotNil(textView.markedTextRange)
            XCTAssertTrue(textView.isFirstResponder)

            textView.unmarkText()
            textView.insertText("語")
            XCTAssertTrue(waitUntil { draft.text == textView.text })
            textView.resignFirstResponder()
        }
    }

    func testLongDescriptionKeepsRequestedHeightAndScrollsInsideTheField() throws {
        try withEditor { draft, host, textView in
            draft.text = Array(repeating: "Measure every section of the deck.", count: 30)
                .joined(separator: "\n")
            XCTAssertTrue(waitUntil { textView.text == draft.text })
            host.view.layoutIfNeeded()
            textView.layoutIfNeeded()
            XCTAssertEqual(textView.bounds.height, OPSStyle.Layout.inputHeight * 2, accuracy: 0.5)
            XCTAssertTrue(textView.isScrollEnabled)
            XCTAssertTrue(waitUntil { textView.contentSize.height > textView.bounds.height })
        }
    }

    func testBuiltInDescriptionDoesNotExposeAnEditableInput() throws {
        try withEditor { draft, host, textView in
            draft.text = "Built-in visit description"
            XCTAssertTrue(waitUntil { textView.text == draft.text })
            draft.isEditable = false
            XCTAssertTrue(waitUntil { descendants(of: UITextView.self, in: host.view).isEmpty })
            XCTAssertEqual(draft.text, "Built-in visit description")
        }
    }

    private func withEditor(
        _ assertions: (Draft, UIHostingController<EditorHarness>, UITextView) throws -> Void
    ) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let draft = Draft()
        let host = UIHostingController(rootView: EditorHarness(draft: draft))
        window.rootViewController = host
        defer {
            host.view.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        XCTAssertTrue(waitUntil { !descendants(of: UITextView.self, in: host.view).isEmpty })
        let textView = try XCTUnwrap(descendants(of: UITextView.self, in: host.view).first)
        try assertions(draft, host, textView)
    }

    private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }
}
#endif
