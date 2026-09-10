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
        var layoutDirection: LayoutDirection = .leftToRight
        var placeholder = "What this visit is for"
    }

    private struct EditorHarness: View {
        @ObservedObject var draft: Draft

        var body: some View {
            VStack {
                FormTextEditor(
                    title: draft.unrelatedChange ? "DESCRIPTION UPDATED" : "DESCRIPTION",
                    placeholder: draft.placeholder,
                    text: $draft.text,
                    isEditable: draft.isEditable,
                    height: OPSStyle.Layout.inputHeight * 2
                )
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background)
            .environment(\.layoutDirection, draft.layoutDirection)
        }
    }

    func testDescriptionCaretAndPlaceholderShareTokenizedInsets() throws {
        try withEditor { _, host, textView in
            let inset = OPSStyle.Layout.spacing3
            XCTAssertEqual(textView.textContainerInset, UIEdgeInsets(
                top: inset, left: inset, bottom: inset, right: inset
            ))
            XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
            let font = try XCTUnwrap(textView.font)
            XCTAssertEqual(font.fontName, OPSStyle.Typography.uiBody.fontName)
            XCTAssertEqual(font.pointSize, OPSStyle.Typography.uiBody.pointSize, accuracy: 0.01)
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

    func testDescriptionStartsAtTheCurrentAccessibilityTextSize() throws {
        try withEditor(contentSizeCategory: .accessibilityExtraLarge) { _, _, textView in
            let font = try XCTUnwrap(textView.font)
            let placeholder = try XCTUnwrap(descendants(of: UILabel.self, in: textView).first)
            XCTAssertEqual(textView.traitCollection.preferredContentSizeCategory, .accessibilityExtraLarge)
            XCTAssertEqual(font.fontName, OPSStyle.Typography.uiBody.fontName)
            XCTAssertGreaterThan(font.pointSize, OPSStyle.Typography.uiBody.pointSize)
            XCTAssertEqual(placeholder.font, font)
            XCTAssertFalse(placeholder.isHidden)
            XCTAssertEqual(textView.bounds.height, OPSStyle.Layout.inputHeight * 2, accuracy: 0.5)
            XCTAssertTrue(textView.isScrollEnabled)
        }
    }

    func testDescriptionTextSizeChangesPreserveDraftSelectionAndFocus() throws {
        try withEditor { draft, host, textView in
            let initialFont = try XCTUnwrap(textView.font)
            let placeholder = try XCTUnwrap(descendants(of: UILabel.self, in: textView).first)
            XCTAssertTrue(textView.becomeFirstResponder())
            let description = "Measure deck.\nCheck access and framing."
            textView.insertText(description)
            XCTAssertTrue(waitUntil { draft.text == description })
            let selection = NSRange(location: 8, length: 4)
            textView.selectedRange = selection

            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            XCTAssertTrue(waitUntil {
                textView.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge
                    && (textView.font?.pointSize ?? 0) > initialFont.pointSize
                    && placeholder.font == textView.font
            })
            XCTAssertEqual(draft.text, description)
            XCTAssertEqual(textView.text, description)
            XCTAssertEqual(textView.selectedRange, selection)
            XCTAssertTrue(textView.isFirstResponder)

            host.traitOverrides.preferredContentSizeCategory = .medium
            XCTAssertTrue(waitUntil {
                textView.traitCollection.preferredContentSizeCategory == .medium
                    && (textView.font?.pointSize ?? initialFont.pointSize) < initialFont.pointSize
                    && placeholder.font == textView.font
            })
            XCTAssertEqual(draft.text, description)
            XCTAssertEqual(textView.selectedRange, selection)
            XCTAssertTrue(textView.isFirstResponder)

            textView.selectedRange = NSRange(location: 0, length: (description as NSString).length)
            textView.insertText("")
            XCTAssertTrue(waitUntil { draft.text.isEmpty && !placeholder.isHidden })
            XCTAssertEqual(placeholder.font, textView.font)
            textView.resignFirstResponder()
        }
    }

    func testPreferredFontFallbackUsesInitialTraitsAndRendersPlaceholder() throws {
        try withFallbackTextView(contentSizeCategory: .accessibilityExtraLarge) { _, textView in
            let expected = UIFont.preferredFont(forTextStyle: .body, compatibleWith: textView.traitCollection)
            let font = try XCTUnwrap(textView.font)
            XCTAssertEqual(font.fontName, expected.fontName)
            XCTAssertEqual(font.pointSize, expected.pointSize, accuracy: 0.01)
            XCTAssertEqual(textView.placeholderLabel.font, font)
            XCTAssertFalse(textView.placeholderLabel.isHidden)
            try assertRenderedText(in: textView, name: "system-font-placeholder-accessibility")
        }
    }

    func testPreferredFontFallbackResizesDuringEditingAndRendersDraft() throws {
        try withFallbackTextView(contentSizeCategory: .large) { host, textView in
            XCTAssertTrue(textView.becomeFirstResponder())
            let description = "Measure deck.\nCheck access."
            textView.insertText(description)
            textView.updatePlaceholder()
            let selection = NSRange(location: 8, length: 4)
            textView.selectedRange = selection

            for category in [UIContentSizeCategory.accessibilityExtraExtraLarge, .small] {
                host.traitOverrides.preferredContentSizeCategory = category
                XCTAssertTrue(waitUntil {
                    let expected = UIFont.preferredFont(
                        forTextStyle: .body,
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
                    )
                    return textView.traitCollection.preferredContentSizeCategory == category
                        && abs((textView.font?.pointSize ?? 0) - expected.pointSize) < 0.01
                        && textView.placeholderLabel.font == textView.font
                })
                XCTAssertEqual(textView.text, description)
                XCTAssertEqual(textView.selectedRange, selection)
                XCTAssertTrue(textView.isFirstResponder)
            }

            textView.resignFirstResponder()
            XCTAssertTrue(textView.placeholderLabel.isHidden)
            try assertRenderedText(in: textView, name: "system-font-draft-after-resize")
        }
    }

    func testRightToLeftDescriptionAlignsCaretAndPlaceholderAtTheLeadingInset() throws {
        try withEditor(layoutDirection: .rightToLeft, placeholder: "وصف الزيارة") { draft, _, textView in
            let placeholder = try XCTUnwrap(descendants(of: UILabel.self, in: textView).first)
            XCTAssertTrue(textView.becomeFirstResponder())
            textView.layoutIfNeeded()
            XCTAssertEqual(textView.effectiveUserInterfaceLayoutDirection, .rightToLeft)
            XCTAssertEqual(textView.textAlignment, .right)
            XCTAssertEqual(placeholder.textAlignment, .right)
            XCTAssertEqual(placeholder.font, textView.font)
            XCTAssertEqual(
                placeholder.frame.maxX,
                textView.bounds.width - OPSStyle.Layout.spacing3,
                accuracy: 0.5
            )
            XCTAssertEqual(
                textView.caretRect(for: textView.beginningOfDocument).maxX,
                placeholder.frame.maxX,
                accuracy: 2
            )

            textView.insertText("قياس سطح المنزل")
            XCTAssertTrue(waitUntil { draft.text == "قياس سطح المنزل" })
            XCTAssertEqual(
                textView.caretRect(for: textView.beginningOfDocument).maxX,
                placeholder.frame.maxX,
                accuracy: 2
            )
            XCTAssertTrue(placeholder.isHidden)
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
        contentSizeCategory: UIContentSizeCategory = .large,
        layoutDirection: LayoutDirection = .leftToRight,
        placeholder: String = "What this visit is for",
        _ assertions: (Draft, UIHostingController<EditorHarness>, UITextView) throws -> Void
    ) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let draft = Draft()
        draft.layoutDirection = layoutDirection
        draft.placeholder = placeholder
        let host = UIHostingController(rootView: EditorHarness(draft: draft))
        host.traitOverrides.preferredContentSizeCategory = contentSizeCategory
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

    private func withFallbackTextView(
        contentSizeCategory: UIContentSizeCategory,
        _ assertions: (UIViewController, FormMultilineTextView) throws -> Void
    ) throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let host = UIViewController()
        host.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        host.view.backgroundColor = UIColor(OPSStyle.Colors.background)
        // Exercise the uiBody fallback without unregistering shared app fonts.
        // Its original size deliberately differs from the receiving view's traits.
        let fallback = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        let textView = FormMultilineTextView(
            frame: CGRect(x: 0, y: 0, width: 320, height: OPSStyle.Layout.inputHeight * 2),
            textContainer: nil,
            bodyFont: fallback
        )
        textView.placeholderLabel.text = "Description"
        textView.updatePlaceholder()
        host.view.addSubview(textView)
        window.rootViewController = host
        defer {
            host.view.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        XCTAssertTrue(waitUntil {
            textView.traitCollection.preferredContentSizeCategory == contentSizeCategory
        })
        try assertions(host, textView)
    }

    private func assertRenderedText(in textView: UITextView, name: String) throws {
        textView.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: textView.bounds).image { context in
            UIColor(OPSStyle.Colors.background).setFill()
            context.fill(textView.bounds)
            XCTAssertTrue(textView.drawHierarchy(in: textView.bounds, afterScreenUpdates: true))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        XCTAssertGreaterThan(pixels.filter { $0 > 64 }.count, 20, "The rendered editor must contain visible text")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
