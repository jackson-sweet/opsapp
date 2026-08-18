//
//  DataController+RecurringEvents.swift
//  OPS
//
//  Apple-Calendar-style "this / future / all" mutations for recurring
//  CalendarUserEvent rows. Each helper:
//
//  1. Performs the local SwiftData mutation immediately (so the calendar
//     reflects the change before any network round-trip).
//  2. Queues one DURABLE write per affected row on the outbound sync queue.
//     These used to be fire-and-forget `try?` calls that cleared `needsSync`
//     regardless of outcome — a failed edit reverted on the next pull and a
//     failed delete resurrected the event (bug ef5a69e6). A row now stays
//     dirty, and therefore stays as the operator left it, until the server
//     confirms its own write.
//  3. Notifies any observing views via scheduledTasksDidChange.
//
//  Callers should NOT read or mutate seriesId rows directly — these helpers
//  encapsulate the scope semantics.
//

import Foundation
import SwiftData

extension DataController {

    // MARK: - Edit fields payload

    /// The fields the user can change on a personal event. Address and
    /// status are intentionally excluded — neither is editable from
    /// UserEventSheet today, and silently overwriting them would erase
    /// state set elsewhere (e.g. an admin's status review).
    struct CalendarUserEventEditPayload {
        let title: String
        let notes: String?
        let allDay: Bool
        let startDate: Date
        let endDate: Date
        let teamMemberIds: [String]?
    }

    // MARK: - Update

    /// Apply `payload` to one event with a chosen series scope.
    ///
    /// Scope semantics:
    /// - `.thisOnly` — detach the row from its series (set series_id = nil
    ///   server-side, clear seriesId locally), then write the new fields.
    /// - `.thisAndFuture` — write the new fields to this row + every later
    ///   sibling, preserving each sibling's original calendar day but
    ///   adopting the new time-of-day and duration delta.
    /// - `.allEvents` — same as future but covers every row in the series.
    ///
    /// `payload.startDate` / `payload.endDate` are interpreted as the new
    /// start/end of the row the user actually edited. For sibling rows in
    /// the future/all scopes, the same time-of-day is applied to each
    /// sibling's existing day, and the end is shifted by the same delta as
    /// the edited row's end relative to its start.
    @MainActor
    func updateRecurringEvent(
        _ event: CalendarUserEvent,
        payload: CalendarUserEventEditPayload,
        scope: RecurringEventScope
    ) {
        // The queue is now the delivery mechanism, so it is the precondition:
        // mutating locally with nowhere to send the change is what stranded
        // rows in the first place.
        guard let context = modelContext, let syncEngine else { return }

        let editedId = event.id
        let editedSeriesId = event.seriesId
        let editedAnchor = event.startDate

        // Compute the start/end-time deltas from "midnight on the row's
        // calendar day" so we can re-anchor siblings without changing their
        // dates. The UserEventSheet stores all-day events with start/end at
        // midnight, so deltas collapse to 0 in that case (correct).
        let calendar = Calendar.current
        let editedDayStart = calendar.startOfDay(for: editedAnchor)
        let startOffset = payload.startDate.timeIntervalSince(editedDayStart)
        let durationSeconds = payload.endDate.timeIntervalSince(payload.startDate)

        // Resolve the affected rows BEFORE mutating: an edit re-anchors every
        // sibling's start, so a "from this date forward" fetch run afterwards
        // can no longer see a row the edit moved earlier.
        let affected = rowsInScope(
            event,
            seriesId: editedSeriesId,
            anchor: editedAnchor,
            scope: scope,
            in: context
        )

        // ---- Local mutations ----

        for row in affected {
            if row.id == editedId {
                applyLocalEdit(to: row,
                               payload: payload,
                               start: payload.startDate,
                               end: payload.endDate)
                if scope == .thisOnly { row.seriesId = nil }
            } else {
                let newStart = calendar.startOfDay(for: row.startDate)
                    .addingTimeInterval(startOffset)
                applyLocalEdit(to: row,
                               payload: payload,
                               start: newStart,
                               end: newStart.addingTimeInterval(durationSeconds))
            }
            row.needsSync = true
        }

        try? context.save()
        scheduledTasksDidChange.toggle()

        // ---- Remote mutations (durable) ----
        //
        // One queued write per row the local mutation touched, keyed by that
        // row's own id. The old path fired these and then cleared `needsSync`
        // regardless of the outcome, so a failed edit reported success and
        // reverted on the next pull (bug ef5a69e6). Each row now retries on its
        // own and clears its flag only when the server confirms it.
        for row in affected {
            CalendarUserEventOutboundSync.enqueueUpdate(
                eventId: row.id,
                fields: CalendarUserEventOutboundSync.editColumns(
                    title: row.title,
                    notes: row.notes,
                    allDay: row.allDay,
                    teamMemberIds: row.teamMemberIds,
                    startDate: row.startDate,
                    endDate: row.endDate,
                    // "This only" detaches the row from its series in the SAME
                    // statement. The old path spent a separate round trip on
                    // the detach, and a detach that landed while the edit did
                    // not left the row half-changed.
                    detachFromSeries: scope == .thisOnly && row.id == editedId
                ),
                syncEngine: syncEngine,
                deferPush: true
            )
        }
        CalendarUserEventOutboundSync.pushQueued(syncEngine: syncEngine)
    }

    // MARK: - Delete

    /// Soft-delete with a chosen series scope. Local rows are tombstoned
    /// (`deletedAt = Date()`) immediately so they vanish from the calendar.
    ///
    /// Scope semantics:
    /// - `.thisOnly` — soft-delete only the tapped row.
    /// - `.thisAndFuture` — soft-delete the tapped row + every later sibling.
    /// - `.allEvents` — soft-delete every row in the series.
    @MainActor
    func deleteRecurringEvent(
        _ event: CalendarUserEvent,
        scope: RecurringEventScope
    ) {
        // See `updateRecurringEvent`: no queue, no delivery, no mutation.
        guard let context = modelContext, let syncEngine else { return }

        let now = Date()

        // Resolved before the tombstones land: `localSiblings` skips deleted
        // rows, so a fetch run afterwards would return nothing to queue.
        let affected = rowsInScope(
            event,
            seriesId: event.seriesId,
            anchor: event.startDate,
            scope: scope,
            in: context
        )

        for row in affected {
            row.deletedAt = now
            row.needsSync = true
        }

        try? context.save()
        scheduledTasksDidChange.toggle()

        // Durable per-row tombstones. The old path cleared `needsSync` after a
        // fire-and-forget batch, so a delete that never landed let the event
        // resurrect on the next pull. The rows stay dirty — and therefore stay
        // deleted locally — until each delete is confirmed (bug ef5a69e6).
        for row in affected {
            CalendarUserEventOutboundSync.enqueueDelete(
                eventId: row.id,
                syncEngine: syncEngine,
                deferPush: true
            )
        }
        CalendarUserEventOutboundSync.pushQueued(syncEngine: syncEngine)
    }

    // MARK: - Local helpers

    /// Apply field-level edits to a single SwiftData row. Stays private to
    /// this file so the only entry points remain `updateRecurringEvent` /
    /// `deleteRecurringEvent`.
    private func applyLocalEdit(
        to row: CalendarUserEvent,
        payload: CalendarUserEventEditPayload,
        start: Date,
        end: Date
    ) {
        row.title = payload.title
        row.notes = payload.notes
        row.allDay = payload.allDay
        row.teamMemberIds = payload.teamMemberIds
        row.startDate = start
        row.endDate = end
        row.updatedAt = Date()
    }

    /// Every local row a scoped mutation touches: the tapped row, plus its
    /// siblings for the series scopes. Resolved BEFORE the mutation, because an
    /// edit re-anchors sibling start dates and a delete tombstones them — a
    /// fetch run afterwards can no longer see rows the mutation just moved or
    /// removed.
    ///
    /// The `deletedAt == nil` filter belongs here rather than in the caller:
    /// an already-tombstoned sibling has nothing left to change and its own
    /// delete is already queued.
    private func rowsInScope(
        _ event: CalendarUserEvent,
        seriesId: String?,
        anchor: Date,
        scope: RecurringEventScope,
        in context: ModelContext
    ) -> [CalendarUserEvent] {
        guard scope != .thisOnly, let seriesId else { return [event] }
        let from: Date? = scope == .thisAndFuture ? anchor : nil
        let siblings = localSiblings(seriesId: seriesId, in: context, from: from)
            .filter { $0.id != event.id }
        return [event] + siblings
    }

    /// Fetch sibling rows from SwiftData. `from` filters to siblings whose
    /// startDate is on-or-after the given date (used by the "future"
    /// scope). When `from` is nil, every non-deleted sibling is returned.
    private func localSiblings(
        seriesId: String?,
        in context: ModelContext,
        from: Date?
    ) -> [CalendarUserEvent] {
        guard let seriesId else { return [] }
        let descriptor: FetchDescriptor<CalendarUserEvent>
        if let from {
            descriptor = FetchDescriptor<CalendarUserEvent>(
                predicate: #Predicate { row in
                    row.seriesId == seriesId
                    && row.deletedAt == nil
                    && row.startDate >= from
                }
            )
        } else {
            descriptor = FetchDescriptor<CalendarUserEvent>(
                predicate: #Predicate { row in
                    row.seriesId == seriesId
                    && row.deletedAt == nil
                }
            )
        }
        return (try? context.fetch(descriptor)) ?? []
    }
}
