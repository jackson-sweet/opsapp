//
//  FeedbackCatalogTests.swift
//  OPSTests
//
//  Guards the Feedback catalog's voice contract: every event label is "// "-
//  prefixed and UPPERCASE, and the generic helpers format correctly.
//

import XCTest
@testable import OPS

final class FeedbackCatalogTests: XCTestCase {

    func testEveryLabelFollowsVoiceContract() {
        for toast in Feedback.all {
            XCTAssertTrue(toast.label.hasPrefix("// "), "missing // prefix: \(toast.label)")
            let body = toast.label
                .replacingOccurrences(of: "//", with: "")
                .trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(body, body.uppercased(), "label not uppercase: \(toast.label)")
            XCTAssertFalse(body.isEmpty, "empty label body in: \(toast.label)")
        }
    }

    func testEveryErrorLabelFollowsVoiceContract() {
        for label in Feedback.Err.all {
            XCTAssertTrue(label.hasPrefix("// "), "missing // prefix: \(label)")
            let body = label
                .replacingOccurrences(of: "//", with: "")
                .trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(body, body.uppercased(), "error label not uppercase: \(label)")
            XCTAssertFalse(body.isEmpty, "empty error label")
        }
    }

    func testGenericHelpersFormatCorrectly() {
        XCTAssertEqual(Feedback.saved("invoice").label, "// INVOICE SAVED")
        XCTAssertEqual(Feedback.deleted("tag").label, "// TAG DELETED")
        XCTAssertEqual(Feedback.created("client").label, "// CLIENT CREATED")
        XCTAssertEqual(Feedback.updated("role").label, "// ROLE UPDATED")
    }
}
