//
//  AppointmentReviewPresentation.swift
//  OPS
//
//  Rewrites the `phase_c_appointment_review` rail row into something an
//  operator on a roof can act on.
//
//  Bug 74bbb5b7 — the founder got "APPOINTMENT NEEDS REVIEW / Confirm the
//  appointment details before booking." with an OPEN LEAD button, and reported
//  it as "Angela Wall has no site visit". Both halves of his confusion are in
//  that row: it never says WHO, and the only thing it offers is the lead, where
//  there is nothing marked as needing a time.
//
//  Source of truth (verified in prod 2026-09-09): the row is generated from
//  `phase_c_bilateral_event_handoffs`, whose id sits in the dedupe key
//  (`phase-c-bilateral:v1:<handoff>:review`). That table is granted to
//  `postgres` and `service_role` ONLY — no `anon`, no `authenticated` — so the
//  app cannot read `review_reason`, `event_kind`, or `starts_at`. The generator
//  half (a body that names neither the customer nor the actual gap) is filed to
//  the web session as bug f0b39d3d.
//
//  What iOS CAN know, and therefore all it is allowed to say:
//    • The lead, from `action_url=/pipeline?opportunityId=<id>` — resolved to a
//      name against the local store.
//    • Which of two bodies the server sent. Verified 1:1 against the handoff
//      rows: "Confirm the appointment TIME before booking." is emitted only for
//      `review_reason = event_time_unresolved` (2/2), and every other reason
//      emits the "details" body. So "no time set" is provable; anything more
//      specific than "unconfirmed" for the details variant would be a guess.
//
//  The action is the operator's real remedy on a phone: open this lead's
//  booking sheet and put a time on the calendar. It is offered only when the
//  row actually carries a lead id.
//

import Foundation

enum AppointmentReviewPresentation {

    /// The server `type` this presentation claims.
    static let notificationType = "phase_c_appointment_review"

    /// Relay posted when the operator takes the action. MainTabView enforces
    /// pipeline access and hands the id to the leads tab, which owns the sheet.
    static let bookingRelayName = Notification.Name("BookSiteVisitForLead")

    /// What the server told us is missing. Two states, because two is all the
    /// server's copy distinguishes.
    enum Gap: Equatable {
        /// The date is known, the time is not.
        case time
        /// Something else about the appointment did not check out. The app
        /// cannot see which, so it does not pretend to.
        case unconfirmed
    }

    struct Copy: Equatable {
        /// The scan line — who, and what is missing.
        let headline: String
        /// The reason the row exists, spelled out once the row is open.
        let detail: String
        let actionLabel: String
    }

    static let actionLabel = "SET THE TIME"

    static func applies(to notification: NotificationDTO) -> Bool {
        notification.type.trimmingCharacters(in: .whitespacesAndNewlines) == notificationType
    }

    /// The lead this review is about. Only the action url carries it — the
    /// dedupe key holds the handoff id, not an opportunity.
    static func opportunityId(for notification: NotificationDTO) -> String? {
        guard applies(to: notification) else { return nil }
        return LeadNotificationRouteParser.opportunityId(fromActionUrl: notification.actionUrl)
    }

    /// `event_time_unresolved` is the one reason the server names outright.
    /// Everything else — including the founder's own row — arrives as the
    /// generic "details" body and is reported as unconfirmed.
    static func gap(serverBody: String?) -> Gap {
        let body = (serverBody ?? "").lowercased()
        return body.contains("appointment time") ? .time : .unconfirmed
    }

    static func copy(serverBody: String?, leadName: String?) -> Copy {
        let name = leadName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (name?.isEmpty == false) ? name : nil

        switch gap(serverBody: serverBody) {
        case .time:
            return Copy(
                headline: named.map { "\($0) — no time set." } ?? "No time set.",
                detail: named.map {
                    "OPS read an email about an appointment with \($0) but couldn't tell when."
                } ?? "OPS read an email about an appointment but couldn't tell when.",
                actionLabel: actionLabel
            )
        case .unconfirmed:
            return Copy(
                headline: named.map { "\($0) — appointment unconfirmed." } ?? "Appointment unconfirmed.",
                detail: named.map {
                    "OPS read an email about an appointment with \($0) but couldn't confirm it."
                } ?? "OPS read an email about an appointment but couldn't confirm it.",
                actionLabel: actionLabel
            )
        }
    }
}
