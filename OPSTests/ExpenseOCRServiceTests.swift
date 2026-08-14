//
//  ExpenseOCRServiceTests.swift
//  OPSTests
//
//  Regression coverage for bug 9dc5d065: receipt scans must surface the
//  purchased items so the expense description can be prefilled.
//

import XCTest
import SwiftUI
import UIKit
@testable import OPS

final class ExpenseOCRServiceTests: XCTestCase {
    func testReceiptParserExtractsPurchasedItemsInReadingOrder() {
        let lines = [
            recognized("HOME HARDWARE", y: 0.94),
            recognized("1087 MAIN STREET", y: 0.88),
            recognized("07/30/2026", y: 0.82),
            recognized("FRAMING HAMMER $24.99", y: 0.68),
            recognized("CEDAR BOARDS", y: 0.60),
            recognized("$38.00", y: 0.55),
            recognized("CARDBOARD SHEET $4.00", y: 0.48),
            recognized("SUBTOTAL $66.99", y: 0.32),
            recognized("GST $3.35", y: 0.26),
            recognized("TOTAL $70.34", y: 0.20),
            recognized("VISA $70.34", y: 0.12),
        ]

        let result = ReceiptParser.parse(
            lines: lines,
            rawText: lines.map(\.text).joined(separator: "\n")
        )

        XCTAssertEqual(
            result.rawDataDict["line_items"],
            "FRAMING HAMMER\nCEDAR BOARDS\nCARDBOARD SHEET"
        )
        XCTAssertEqual(
            result.descriptionSuggestion,
            "FRAMING HAMMER, CEDAR BOARDS, CARDBOARD SHEET"
        )
    }

    func testReceiptParserDoesNotInventItemsFromReceiptMetadata() {
        let lines = [
            recognized("HOME HARDWARE", y: 0.94),
            recognized("1087 MAIN STREET", y: 0.88),
            recognized("07/30/2026", y: 0.82),
            recognized("SUBTOTAL $45.00", y: 0.32),
            recognized("GST $2.25", y: 0.26),
            recognized("TOTAL $47.25", y: 0.20),
            recognized("VISA $47.25", y: 0.12),
        ]

        let result = ReceiptParser.parse(
            lines: lines,
            rawText: lines.map(\.text).joined(separator: "\n")
        )

        XCTAssertNil(result.rawDataDict["line_items"])
    }

    private func recognized(_ text: String, y: CGFloat) -> RecognizedLine {
        RecognizedLine(
            text: text,
            confidence: 0.98,
            boundingBox: CGRect(x: 0.05, y: y, width: 0.90, height: 0.02)
        )
    }
}

final class ExpenseOCRAutofillTests: XCTestCase {
    func testEmptyDescriptionAcceptsReceiptSuggestion() {
        XCTAssertEqual(
            ExpenseOCRAutofill.description(
                current: "  ",
                suggestion: "FRAMING HAMMER, CEDAR BOARDS"
            ),
            "FRAMING HAMMER, CEDAR BOARDS"
        )
    }

    func testExistingDescriptionIsNeverOverwritten() {
        XCTAssertEqual(
            ExpenseOCRAutofill.description(
                current: "Materials for Smith deck",
                suggestion: "FRAMING HAMMER, CEDAR BOARDS"
            ),
            "Materials for Smith deck"
        )
    }
}

@MainActor
final class ExpenseMerchantInputTests: XCTestCase {
    func testMerchantInputUsesBusinessNameSemanticsAndNeverSecureEntry() throws {
        var merchantName = ""
        let host = UIHostingController(
            rootView: ExpenseMerchantTextField(
                text: Binding(
                    get: { merchantName },
                    set: { merchantName = $0 }
                )
            )
            .frame(width: 280, height: 56)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let textField = try XCTUnwrap(findTextField(in: host.view))
        XCTAssertFalse(textField.isSecureTextEntry)
        XCTAssertEqual(textField.textContentType, .organizationName)

        window.isHidden = true
    }

    private func findTextField(in view: UIView) -> UITextField? {
        if let textField = view as? UITextField { return textField }
        for subview in view.subviews {
            if let match = findTextField(in: subview) { return match }
        }
        return nil
    }
}
