//
//  DataController+RecurringEvents.swift
//  OPS
//
//  Apple-Calendar-style "this / future / all" mutations for recurring
//  CalendarUserEvent rows. Each helper:
//
//  1. Performs the local SwiftData mutation immediately (so the calendar
//     reflects the change before any network round-trip).
//  2. Mirrors the mutation to Supabase asynchronously.
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
        guard let context = modelContext,
              let companyId = currentUser?.companyId else { return }

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

        // ---- Local mutations ----

        switch scope {
        case .thisOnly:
            applyLocalEdit(to: event,
                           payload: payload,
                           start: payload.startDate,
                           end: payload.endDate)
            event.seriesId = nil
            event.needsSync = true

        case .thisAndFuture:
            // Mutate this row + every later sibling.
            event.needsSync = true
            applyLocalEdit(to: event,
                           payload: payload,
                           start: payload.startDate,
                           end: payload.endDate)

            for sibling in localSiblings(seriesId: editedSeriesId,
                                         in: context,
                                         from: editedAnchor) {
                if sibling.id == editedId { continue }
                let newStart = calendar.startOfDay(for: sibling.startDate)
                    .addingTimeInterval(startOffset)
                let newEnd = newStart.addingTimeInterval(durationSeconds)
                applyLocalEdit(to: sibling,
                               payload: payload,
                               start: newStart,
                               end: newEnd)
                sibling.needsSync = true
            }

        case .allEvents:
            event.needsSync = true
            applyLocalEdit(to: event,
                           payload: payload,
                           start: payload.startDate,
                           end: payload.endDate)

            for sibling in localSiblings(seriesId: editedSeriesId,
                                         in: context,
                                         from: nil) {
                if sibling.id == editedId { continue }
                let newStart = calendar.startOfDay(for: sibling.startDate)
                    .addingTimeInterval(startOffset)
                let newEnd = newStart.addingTimeInterval(durationSeconds)
                applyLocalEdit(to: sibling,
                               payload: payload,
                               start: newStart,
                               end: newEnd)
                sibling.needsSync = true
            }
        }

        try? context.save()
        scheduledTasksDidChange.toggle()

        // ---- Remote mutations (fire-and-forget) ----

        let payloadCopy = payload
        Task { [editedSeriesId] in
            await self.syncEditToSupabase(
                eventId: editedId,
                seriesId: editedSeriesId,
                editedAnchor: editedAnchor,
                payload: payloadCopy,
                scope: scope,
                companyId: companyId
            )
        }
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
        guard let context = modelContext,
              let companyId = currentUser?.companyId else { return }

        let editedId = event.id
        let editedSeriesId = event.seriesId
        let editedAnchor = event.startDate
        let now = Date()

        switch scope {
        case .thisOnly:
            event.deletedAt = now
            event.needsSync = true

        case .thisAndFuture:
            event.deletedAt = now
            event.needsSync = true
            for sibling in localSiblings(seriesId: editedSeriesId,
                                         in: context,
                                         from: editedAnchor) {
                if sibling.id == editedId { continue }
                sibling.deletedAt = now
                sibling.needsSync = true
            }

        case .allEvents:
            event.deletedAt = now
            event.needsSync = true
            for sibling in localSiblings(seriesId: editedSeriesId,
                                         in: context,
                                         from: nil) {
                if sibling.id == editedId { continue }
                sibling.deletedAt = now
                sibling.needsSync = true
            }
        }

        try? context.save()
        scheduledTasksDidChange.toggle()

        Task { [editedSeriesId] in
            await self.syncDeleteToSupabase(
                eventId: editedId,
                seriesId: editedSeriesId,
                editedAnchor: editedAnchor,
                scope: scope,
                companyId: companyId
            )
        }
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

    // MARK: - Remote sync

    /// Mirrors `updateRecurringEvent` against Supabase. Two-step for
    /// .thisOnly (detach, then write); single-shot for the series scopes
    /// where we fetch siblings from the server, compute per-row dates, and
    /// update them one at a time.
    private func syncEditToSupabase(
        eventId: String,
        seriesId: String?,
        editedAnchor: Date,
        payload: CalendarUserEventEditPayload,
        scope: RecurringEventScope,
        companyId: String
    ) async {
        let repo = CalendarUserEventRepository(companyId: companyId)
        let iso = ISO8601DateFormatter()
        let calendar = Calendar.current
        let editedDayStart = calendar.startOfDay(for: editedAnchor)
        let startOffset = payload.startDate.timeIntervalSince(editedDayStart)
        let durationSeconds = payload.endDate.timeIntervalSince(payload.startDate)

        switch scope {
        case .thisOnly:
            // Detach first — if the user later runs "edit all" on the
            // remaining series, this row should not be included.
            try? await repo.detachFromSeries(eventId)
            let fields = CalendarUserEventRepository.EventFieldUpdate(
                title: payload.title,
                notes: payload.notes,
                allDay: payload.allDay,
                teamMemberIds: payload.teamMemberIds,
                startDate: iso.string(from: payload.startDate),
                endDate: iso.string(from: payload.endDate),
                updatedAt: iso.string(from: Date())
            )
            try? await repo.updateEvent(eventId, fields: fields)

        case .thisAndFuture, .allEvents:
            guard let seriesId else {
                // Defensive: no seriesId means there are no siblings.
                let fields = CalendarUserEventRepository.EventFieldUpdate(
                    title: payload.title,
                    notes: payload.notes,
                    allDay: payload.allDay,
                    teamMemberIds: payload.teamMemberIds,
                    startDate: iso.string(from: payload.startDate),
                    endDate: iso.string(from: payload.endDate),
                    updatedAt: iso.string(from: Date())
                )
                try? await repo.updateEvent(eventId, fields: fields)
                return
            }

            let siblings: [CalendarUserEventDTO]
            do {
                if scope == .thisAndFuture {
                    siblings = try await repo.fetchSeriesFromDate(seriesId, from: editedAnchor)
                } else {
                    siblings = try await repo.fetchSeries(seriesId)
                }
            } catch {
                return
            }

            for sibling in siblings {
                // Each sibling preserves its own calendar day but adopts
                // the new time-of-day and duration.
                let siblingStart: Date
                let siblingEnd: Date
                if sibling.id == eventId {
                    siblingStart = payload.startDate
                    siblingEnd = payload.endDate
                } else {
                    let day = calendar.startOfDay(for: sibling.startDate)
                    siblingStart = day.addingTimeInterval(startOffset)
                    siblingEnd = siblingStart.addingTimeInterval(durationSeconds)
                }
                let fields = CalendarUserEventRepository.EventFieldUpdate(
                    title: payload.title,
                    notes: payload.notes,
                    allDay: payload.allDay,
                    teamMemberIds: payload.teamMemberIds,
                    startDate: iso.string(from: siblingStart),
                    endDate: iso.string(from: siblingEnd),
                    updatedAt: iso.string(from: Date())
                )
                try? await repo.updateEvent(sibling.id, fields: fields)
            }
        }

        // Mark local rows synced.
        await MainActor.run {
            guard let context = modelContext else { return }
            let predicate: Predicate<CalendarUserEvent>
            if let seriesId, scope != .thisOnly {
                predicate = #Predicate<CalendarUserEvent> { row in
                    row.seriesId == seriesId || row.id == eventId
                }
            } else {
                predicate = #Predicate<CalendarUserEvent> { row in row.id == eventId }
            }
            let descriptor = FetchDescriptor<CalendarUserEvent>(predicate: predicate)
            if let rows = try? context.fetch(descriptor) {
                let now = Date()
                for row in rows {
                    row.needsSync = false
                    row.lastSyncedAt = now
                }
                try? context.save()
            }
        }
    }

    /// Mirrors `deleteRecurringEvent` against Supabase using batched RLS-
    /// scoped soft-deletes. Single row for `.thisOnly`, range delete for
    /// `.thisAndFuture`, full series for `.allEvents`.
    private func syncDeleteToSupabase(
        eventId: String,
        seriesId: String?,
        editedAnchor: Date,
        scope: RecurringEventScope,
        companyId: String
    ) async {
        let repo = CalendarUserEventRepository(companyId: companyId)
        switch scope {
        case .thisOnly:
            try? await repo.softDelete(eventId)

        case .thisAndFuture:
            guard let seriesId else {
                try? await repo.softDelete(eventId)
                return
            }
            try? await repo.softDeleteSeriesFromDate(seriesId, from: editedAnchor)

        case .allEvents:
            guard let seriesId else {
                try? await repo.softDelete(eventId)
                return
            }
            try? await repo.softDeleteSeries(seriesId)
        }

        // Mark local rows synced.
        await MainActor.run {
            guard let context = modelContext else { return }
            let predicate: Predicate<CalendarUserEvent>
            if let seriesId, scope != .thisOnly {
                predicate = #Predicate<CalendarUserEvent> { row in
                    row.seriesId == seriesId || row.id == eventId
                }
            } else {
                predicate = #Predicate<CalendarUserEvent> { row in row.id == eventId }
            }
            let descriptor = FetchDescriptor<CalendarUserEvent>(predicate: predicate)
            if let rows = try? context.fetch(descriptor) {
                let now = Date()
                for row in rows {
                    if row.deletedAt != nil {
                        row.needsSync = false
                        row.lastSyncedAt = now
                    }
                }
                try? context.save()
            }
        }
    }
}
