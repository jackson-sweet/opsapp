//
//  SiteVisitCancellation.swift
//  OPS
//
//  Cancelling a booked visit, in ONE place.
//
//  The booking sheet has owned this since the booking flow shipped
//  (2026-08-14). The lead dossier's visit banner now offers the same verb
//  without making the operator open a booking form to reach it (bug 52cc8dae)
//  — and a destructive server write with two implementations is exactly how
//  two entry points end up disagreeing about what they did. The RPC, the local
//  mirror, the calendar unmirror, the success haptic and the one notification
//  every visit affordance listens to all live here; the callers own only their
//  own chrome (a sheet dismisses itself, a banner raises a toast).
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum SiteVisitCancellation {

    /// The confirm, worded once. Cancelling is not undoable from the app, so
    /// the dialog names both halves of what happens: the calendar loses the
    /// appointment, the lead keeps its history.
    static func confirm(onConfirm: @escaping () -> Void) -> OPSConfirmConfig {
        OPSConfirmConfig(
            title: "CANCEL VISIT?",
            message: "The appointment comes off every calendar. The lead keeps its record.",
            verb: "CANCEL VISIT",
            isDestructive: true,
            onConfirm: onConfirm
        )
    }

    /// Runs the cancel end to end.
    ///
    /// - Returns: `nil` on success, or the message to show the operator. The
    ///   caller decides where that message goes — booking is RPC-only, so a
    ///   failure here means the appointment is STILL BOOKED and the affordance
    ///   the operator pressed must still be there when they look back.
    @discardableResult
    static func cancel(
        siteVisitId: String,
        leadId: String,
        service: SiteVisitBookingService,
        modelContext: ModelContext?
    ) async -> String? {
        do {
            _ = try await service.cancel(siteVisitId: siteVisitId)
            markCancelledLocally(siteVisitId, in: modelContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Every surface holding this lead's visit re-resolves on this —
            // the dossier banner, the NEXT TOUCH cell, the appointment sheet.
            NotificationCenter.default.post(
                name: Notification.Name("SiteVisitBookingChanged"),
                object: nil,
                userInfo: ["leadId": leadId]
            )
            return nil
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return (error as? SiteVisitBookingError)?.errorDescription
                ?? SiteVisitBookingError.server(detail: "\(error)").errorDescription
        }
    }

    /// Server truth, applied immediately so the banner clears without waiting
    /// on the realtime echo.
    static func markCancelledLocally(_ visitId: String, in context: ModelContext?) {
        guard let context, let visit = fetchLocalVisit(id: visitId, in: context) else { return }
        visit.status = .cancelled
        try? context.save()
        // The personal-calendar mirror is self-healing — book, reschedule and
        // cancel all resolve through the same call (cancel unmirrors via
        // eligibility).
        Task {
            await CalendarMirrorService.shared.mirrorEvent(opsId: visitId, source: .siteVisit)
        }
    }

    private static func fetchLocalVisit(id: String, in context: ModelContext) -> SiteVisit? {
        let lower = id.lowercased()
        var descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.id == lower }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
