//
//  AppointmentReviewPresentationTests.swift
//  OPSTests
//
//  Bug 74bbb5b7 — "APPOINTMENT NEEDS REVIEW / Confirm the appointment details
//  before booking." named nobody and offered only the lead. These tests pin the
//  copy/action mapping: who the row is about, what it is honest enough to claim
//  about the gap, and that the action only exists when a lead does.
//

import XCTest
@testable import OPS

final class AppointmentReviewPresentationTests: XCTestCase {

    private let leadId = "9c137fe0-a1e1-4945-b248-00141ce89fc8"
    private let handoffId = "83ede0eb-62b4-4691-af08-4657a7d6826f"

    /// The founder's own row, verified in prod on 2026-09-09.
    private func reviewRow(
        body: String = "Confirm the appointment details before booking.",
        actionUrl: String? = nil,
        isRead: Bool = false
    ) -> NotificationDTO {
        NotificationDTO(
            id: "6f67484a-53b2-4115-9273-5d9b09411914",
            userId: "user-1",
            companyId: "company-1",
            type: "phase_c_appointment_review",
            title: "Appointment needs review",
            body: body,
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "lead",
            actionUrl: actionUrl ?? "/pipeline?opportunityId=\(leadId)",
            actionLabel: "REVIEW",
            persistent: true,
            dedupeKey: "phase-c-bilateral:v1:\(handoffId):review",
            resolvedAt: nil,
            resolvedBy: nil,
            resolutionReason: nil,
            isRead: isRead,
            createdAt: "2026-09-08T15:45:19.243188+00:00"
        )
    }

    // MARK: - Claiming the row

    func testClaimsOnlyTheAppointmentReviewType() {
        XCTAssertTrue(AppointmentReviewPresentation.applies(to: reviewRow()))

        let other = NotificationDTO(
            id: "x", userId: "u", companyId: "c", type: "phase_c_appointment_booked",
            title: "Appointment booked", body: "Booked.", projectId: nil, noteId: nil,
            expenseId: nil, batchId: nil, deepLinkType: "lead",
            actionUrl: "/pipeline?opportunityId=\(leadId)", actionLabel: nil,
            persistent: false, dedupeKey: nil, resolvedAt: nil, resolvedBy: nil,
            resolutionReason: nil, isRead: false, createdAt: "2026-09-08T15:45:19Z"
        )
        XCTAssertFalse(AppointmentReviewPresentation.applies(to: other))
        XCTAssertNil(AppointmentReviewPresentation.opportunityId(for: other))
    }

    func testLeadIdComesFromTheActionUrlOnly() {
        XCTAssertEqual(AppointmentReviewPresentation.opportunityId(for: reviewRow()), leadId)

        // The dedupe key holds the HANDOFF id, never an opportunity — a row
        // with no query parameter must not mistake it for a lead.
        XCTAssertNil(
            AppointmentReviewPresentation.opportunityId(for: reviewRow(actionUrl: "/pipeline"))
        )
    }

    // MARK: - What the row is allowed to claim

    func testGapSplitsOnTheOnlySignalTheServerGives() {
        // Verified 1:1 in prod: the "time" body is emitted only for
        // review_reason = event_time_unresolved.
        XCTAssertEqual(
            AppointmentReviewPresentation.gap(serverBody: "Confirm the appointment time before booking."),
            .time
        )
        // Everything else — including the founder's event_date_or_time_unresolved
        // row — arrives as the generic body and is reported as unconfirmed.
        XCTAssertEqual(
            AppointmentReviewPresentation.gap(serverBody: "Confirm the appointment details before booking."),
            .unconfirmed
        )
        XCTAssertEqual(AppointmentReviewPresentation.gap(serverBody: nil), .unconfirmed)
        XCTAssertEqual(AppointmentReviewPresentation.gap(serverBody: ""), .unconfirmed)
    }

    func testCopyNamesTheCustomerAndTheGap() {
        let timed = AppointmentReviewPresentation.copy(
            serverBody: "Confirm the appointment time before booking.",
            leadName: "Angela Wall"
        )
        XCTAssertEqual(timed.headline, "Angela Wall — no time set.")
        XCTAssertEqual(
            timed.detail,
            "OPS read an email about an appointment with Angela Wall but couldn't tell when."
        )
        XCTAssertEqual(timed.actionLabel, "SET THE TIME")

        let unconfirmed = AppointmentReviewPresentation.copy(
            serverBody: "Confirm the appointment details before booking.",
            leadName: "Angela Wall"
        )
        XCTAssertEqual(unconfirmed.headline, "Angela Wall — appointment unconfirmed.")
        XCTAssertEqual(
            unconfirmed.detail,
            "OPS read an email about an appointment with Angela Wall but couldn't confirm it."
        )
    }

    func testCopyDropsTheNameRatherThanInventingOne() {
        for name in [nil, "", "   "] as [String?] {
            let copy = AppointmentReviewPresentation.copy(
                serverBody: "Confirm the appointment details before booking.",
                leadName: name
            )
            XCTAssertEqual(copy.headline, "Appointment unconfirmed.")
            XCTAssertEqual(
                copy.detail,
                "OPS read an email about an appointment but couldn't confirm it."
            )
            XCTAssertFalse(copy.headline.contains("—"), "no dangling separator when there is no name")
        }

        let timed = AppointmentReviewPresentation.copy(
            serverBody: "Confirm the appointment time before booking.",
            leadName: nil
        )
        XCTAssertEqual(timed.headline, "No time set.")
        XCTAssertEqual(timed.detail, "OPS read an email about an appointment but couldn't tell when.")
    }

    func testCopyKeepsTheOPSRegister() {
        let copy = AppointmentReviewPresentation.copy(
            serverBody: "Confirm the appointment details before booking.",
            leadName: "Angela Wall"
        )
        for line in [copy.headline, copy.detail] {
            XCTAssertFalse(line.contains("!"))
            XCTAssertFalse(line.lowercased().contains("oops"))
            XCTAssertFalse(line.lowercased().contains("site visit"),
                           "iOS cannot read event_kind — it must not claim one")
        }
        XCTAssertEqual(copy.actionLabel, copy.actionLabel.uppercased())
    }

    // MARK: - Routing

    func testBookingRelayNameIsTheOneMainTabViewListensFor() {
        XCTAssertEqual(
            AppointmentReviewPresentation.bookingRelayName,
            Notification.Name("BookSiteVisitForLead")
        )
    }
}
