//
//  LeadQuickTouchLoggerTests.swift
//  OPSTests
//
//  Pure URL-composition coverage for the do-and-stamp quick contact
//  (Leads redesign spec §3): sms sanitation, mailto thread-subject compose,
//  and the Re:-not-doubled rule.
//

import XCTest
@testable import OPS

@MainActor
final class LeadQuickTouchLoggerTests: XCTestCase {
    func testUndoRemainsAvailableAfterReturningFromMessagesOrMail() {
        XCTAssertEqual(LeadQuickTouchLogger.undoToastAutoDismissAfter, 0)
    }

    func testSmsURL() {
        XCTAssertEqual(LeadQuickTouchLogger.smsURLString(phone: "(555) 123-4567"), "sms:5551234567")
    }
    func testMailtoWithThreadSubject() {
        XCTAssertEqual(
            LeadQuickTouchLogger.mailtoURLString(email: "h@x.com", threadSubject: "Roof quote — 1240 Maple Ave"),
            "mailto:h@x.com?subject=Re%3A%20Roof%20quote%20%E2%80%94%201240%20Maple%20Ave")
    }
    func testMailtoNoThread() {
        XCTAssertEqual(LeadQuickTouchLogger.mailtoURLString(email: "h@x.com", threadSubject: nil), "mailto:h@x.com")
    }
    func testReSubjectNotDoubled() {
        XCTAssertEqual(LeadQuickTouchLogger.replySubject(from: "Re: Roof quote"), "Re: Roof quote")
        XCTAssertEqual(LeadQuickTouchLogger.replySubject(from: "Roof quote"), "Re: Roof quote")
    }
}
