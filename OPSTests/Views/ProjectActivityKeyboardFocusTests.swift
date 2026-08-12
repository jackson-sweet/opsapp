//
//  ProjectActivityKeyboardFocusTests.swift
//  OPSTests
//
//  Regression coverage for the UIKit-backed Activity note composer. SwiftUI
//  observes the editor's focus so Project Details can hide its quick actions,
//  but a transient observer reset must never dismiss the real first responder.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ProjectActivityKeyboardFocusTests: XCTestCase {
    private final class FocusModel: ObservableObject {
        @Published var isFocused = false
    }

    private struct ComposerHarness: View {
        @ObservedObject var focusModel: FocusModel
        @State private var text = ""
        @State private var selectedRange = NSRange(location: 0, length: 0)
        @State private var mentionSpans: [ProjectNoteMentionSpan] = []

        var body: some View {
            ProjectNoteMentionComposerField(
                text: $text,
                selectedRange: $selectedRange,
                mentionSpans: $mentionSpans,
                isFocused: $focusModel.isFocused,
                placeholder: "Write a note...",
                onSubmit: {}
            )
            .padding()
        }
    }

    func testComposerFocusSurvivesObserverResetUntilUIKitEndsEditing() throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        let focusModel = FocusModel()
        let host = UIHostingController(
            rootView: ComposerHarness(focusModel: focusModel)
        )
        window.rootViewController = host
        window.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(in: host.view))

        focusModel.isFocused = true
        XCTAssertTrue(
            waitUntil { textView.isFirstResponder },
            "The Activity composer must accept an explicit focus request"
        )

        // The binding also observes UIKit focus for surrounding SwiftUI. It is
        // not dismissal authority: FocusState and parent-view transactions can
        // briefly publish false while this UITextView remains the active editor.
        focusModel.isFocused = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(
            textView.isFirstResponder,
            "A passive SwiftUI focus reset must not make the keyboard jump away"
        )

        textView.resignFirstResponder()
        XCTAssertTrue(
            waitUntil { !textView.isFirstResponder },
            "UIKit dismissal must still end editing normally"
        )
    }

    private func findTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let match = findTextView(in: subview) { return match }
        }
        return nil
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }
}
#endif
