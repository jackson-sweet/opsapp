//
//  TimeOffRequestNotificationDispatcher.swift
//  OPS
//
//  One dispatch path for both time-off sheets. `UserEventSheet` (book or
//  request) and `TimeOffRequestSheet` (request) used to hand-build one
//  `notifications` row per recipient after looking approvers up client-side —
//  seven direct inserts that have 42501'd since the 2026-07-15 hardening
//  revoked app-role INSERT. The rails went dead while the pushes kept firing,
//  so approvers got a buzz pointing at nothing.
//
//  The server now owns the whole rail. Both sheets write the
//  `calendar_user_events` row first, then hand this dispatcher the event id:
//  `notify_time_off_booked` and `notify_time_off_requested` read that row for
//  the target, the requester (the actor, by definition), and the approver set,
//  render the copy, and dedupe per event. Nothing here computes a recipient.
//
//  What stays client-side is the push, and only the push. Its copy is built by
//  the sheet that knows the wording, and it is aimed at exactly the ids the
//  server reports as having received NEW rows — never at a locally guessed
//  list. When the RPC fails, no push goes out: a buzz with no rail row behind
//  it is the bug this replaced.
//

import Foundation

/// The rail lane. `NotificationRepository` is the only production
/// implementation; tests substitute a spy.
protocol TimeOffRequestNotifying {
    /// Returns the server's verdict for the booking's rail row.
    @discardableResult
    func notifyTimeOffBooked(eventId: String) async throws -> String

    /// Returns the ids that received NEW approver rows, plus whether the
    /// on-behalf target was told.
    @discardableResult
    func notifyTimeOffRequested(
        eventId: String
    ) async throws -> NotificationRepository.TimeOffRequestFanout
}

extension NotificationRepository: TimeOffRequestNotifying {}

/// The push lane, mirroring the two OneSignal entry points this dispatcher
/// uses so tests can observe who got buzzed without a network.
protocol TimeOffRequestPushing {
    func sendToUser(
        userId: String,
        title: String,
        body: String,
        data: [String: Any]?,
        imageUrl: String?
    ) async throws

    func sendToUsers(
        userIds: [String],
        title: String,
        body: String,
        data: [String: Any]?,
        imageUrl: String?
    ) async throws
}

extension OneSignalService: TimeOffRequestPushing {}

enum TimeOffRequestNotificationDispatcher {

    /// The server's verdict when it wrote a new rail row. Anything else means
    /// the row was already there.
    static let createdVerdict = "created"

    /// Push wording, built by the calling sheet. Rail copy is the server's;
    /// this is the phone's lock screen, which has always been client-side.
    struct PushCopy {
        let title: String
        let body: String
        let data: [String: Any]
    }

    // MARK: - Booked

    /// Books time off for someone: the server writes the confirmation row for
    /// the event's own user, then this pushes that person — but only when a
    /// row was actually created, and never when they are the person doing the
    /// booking (they are looking at the schedule they just changed).
    ///
    /// Returns the server's verdict, or `nil` when the call did not land.
    /// Failures are contained: the calendar row is already written by the time
    /// this runs, so the save path must never inherit a notification error.
    @discardableResult
    static func dispatchBooked(
        eventId: String,
        targetUserId: String,
        targetIsSelf: Bool,
        push: PushCopy,
        railSyncer: TimeOffRequestNotifying = NotificationRepository.shared,
        pushSender: TimeOffRequestPushing = OneSignalService.shared
    ) async -> String? {
        let verdict: String
        do {
            verdict = try await railSyncer.notifyTimeOffBooked(eventId: eventId)
        } catch {
            print("[TIME_OFF_REQUEST] Booked rail dispatch failed: \(error)")
            return nil
        }

        guard verdict == createdVerdict, !targetIsSelf else { return verdict }

        do {
            try await pushSender.sendToUser(
                userId: targetUserId,
                title: push.title,
                body: push.body,
                data: push.data,
                imageUrl: nil
            )
        } catch {
            print("[TIME_OFF_REQUEST] Booked push failed: \(error)")
        }

        return verdict
    }

    // MARK: - Requested

    /// Submits a time-off request: the server writes the requester's receipt,
    /// the on-behalf target's row when there is one, and a row for every
    /// approver who did not already have one. This pushes exactly the approvers
    /// it names — no approvers, no push.
    ///
    /// Returns those approver ids so the caller can log what actually went out.
    /// Failures are contained; the request itself is already saved.
    @discardableResult
    static func dispatchRequested(
        eventId: String,
        push: PushCopy,
        railSyncer: TimeOffRequestNotifying = NotificationRepository.shared,
        pushSender: TimeOffRequestPushing = OneSignalService.shared
    ) async -> [String] {
        let fanout: NotificationRepository.TimeOffRequestFanout
        do {
            fanout = try await railSyncer.notifyTimeOffRequested(eventId: eventId)
        } catch {
            print("[TIME_OFF_REQUEST] Request rail dispatch failed: \(error)")
            return []
        }

        let approverIds = fanout.approverUserIds
        guard !approverIds.isEmpty else { return [] }

        do {
            try await pushSender.sendToUsers(
                userIds: approverIds,
                title: push.title,
                body: push.body,
                data: push.data,
                imageUrl: nil
            )
        } catch {
            print("[TIME_OFF_REQUEST] Request push failed: \(error)")
        }

        return approverIds
    }
}
