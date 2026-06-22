//
//  CalendarViewModel+SuggestedEvents.swift
//  OPS
//
//  Phase-C "Suggested events" behaviour for the calendar (item 63144953).
//  Loads detected commitments via the SECURITY DEFINER RPC, confirms them onto
//  the calendar (creating a personal CalendarUserEvent that the mirror pushes to
//  the iPhone Calendar), and resolves the source commitment so it isn't
//  re-offered. Dormant by contract: an empty list is the normal state and no
//  error is ever surfaced — the app never depends on the Phase C engine.
//

import Foundation
import SwiftData

extension CalendarViewModel {

    /// Stamped on a created event so it reads clearly weeks later — on the OPS
    /// schedule and on the mirrored iPhone Calendar event.
    static let suggestionProvenanceNote = "OPS caught this in your messages."

    // MARK: - Load

    /// Fetch the company's detected commitments and publish the ones worth
    /// offering. Any failure → empty list, no error surfaced. Dedups against the
    /// user's existing calendar events so nothing already on the calendar is
    /// re-offered ("not already in the calendar").
    @MainActor
    func loadSuggestedEvents() async {
        let fetched = await SuggestedCalendarEventRepository().fetchSuggestedEvents()
        guard !fetched.isEmpty else {
            if !suggestedEvents.isEmpty { suggestedEvents = [] }
            return
        }
        let existing = existingUserEventKeys()
        var offered: [SuggestedCalendarEventDTO] = []
        var alreadyOnCalendar: [SuggestedCalendarEventDTO] = []
        for dto in fetched {
            if existing.contains(Self.dedupKey(title: dto.content, day: dto.dueDate)) {
                alreadyOnCalendar.append(dto)
            } else {
                offered.append(dto)
            }
        }
        suggestedEvents = offered

        // A commitment that's already on the calendar yet still came back
        // unresolved means an earlier resolve() didn't land (e.g. offline at
        // confirm time). Re-resolve it so the server stops returning it and we
        // stop leaning on the client-side dedup backstop. Best-effort.
        if !alreadyOnCalendar.isEmpty {
            let ids = alreadyOnCalendar.map { $0.id }
            Task {
                let repo = SuggestedCalendarEventRepository()
                for id in ids { await repo.resolve(id) }
            }
        }
    }

    // MARK: - Confirm / dismiss

    /// Confirm a suggestion onto the calendar. Creates a personal
    /// CalendarUserEvent (which the mirror pushes to the iPhone Calendar), marks
    /// the source commitment resolved, and removes it from the offer list.
    /// Returns true when the local event was created.
    @MainActor
    @discardableResult
    func addSuggestedEvent(_ dto: SuggestedCalendarEventDTO) async -> Bool {
        guard let dataController,
              let context = dataController.modelContext,
              let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else {
            return false
        }

        let timing = Self.eventTiming(for: dto.dueDate)
        let title = Self.eventTitle(from: dto.content)

        // Local-first insert so the schedule reflects it immediately — mirrors
        // the UserEventSheet create path.
        let event = CalendarUserEvent(
            userId: userId,
            companyId: companyId,
            type: .personal,
            title: title,
            startDate: timing.start,
            endDate: timing.end,
            allDay: timing.allDay,
            notes: Self.suggestionProvenanceNote
        )
        event.needsSync = true
        context.insert(event)
        try? context.save()

        // Optimistically clear from the offer list and refresh the day view.
        suggestedEvents.removeAll { $0.id == dto.id }
        loadUserEvents()

        // Push to Supabase + mirror + resolve, off the interaction path.
        let memoryId = dto.id
        Task { @MainActor in
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()
            let createDTO = CreateCalendarUserEventDTO(
                userId: userId,
                companyId: companyId,
                type: CalendarUserEventType.personal.rawValue,
                title: title,
                startDate: iso.string(from: timing.start),
                endDate: iso.string(from: timing.end),
                allDay: timing.allDay,
                notes: Self.suggestionProvenanceNote,
                status: CalendarUserEventStatus.none.rawValue
            )
            if let saved = try? await repo.create(createDTO) {
                event.id = saved.id
                event.needsSync = false
                event.lastSyncedAt = Date()
                try? context.save()
                // create() fires the mirror with the server id before the local
                // row carries it; fire once more now the ids line up so the event
                // lands on the phone immediately rather than waiting for reconcile.
                await CalendarMirrorService.shared.mirrorEvent(opsId: saved.id, source: .calendarUserEvent)
            }
            // Resolve the source commitment so it isn't re-offered. Best-effort —
            // the title+day dedup is the backstop if this doesn't land.
            await SuggestedCalendarEventRepository().resolve(memoryId)
            NotificationCenter.default.post(name: Notification.Name("CalendarUserEventsDidChange"), object: nil)
        }

        return true
    }

    /// Decline a suggestion. Resolves the source commitment so it isn't
    /// re-offered, and removes it from the list. Creates nothing.
    @MainActor
    func dismissSuggestedEvent(_ dto: SuggestedCalendarEventDTO) async {
        suggestedEvents.removeAll { $0.id == dto.id }
        let memoryId = dto.id
        Task { await SuggestedCalendarEventRepository().resolve(memoryId) }
    }

    // MARK: - Mapping helpers

    /// Maps a detected due date to event timing. Phase C stores deadline-style
    /// commitments at an end-of-day boundary in **UTC** (00:00 or 23:59), so the
    /// boundary is detected against UTC components — that classifies a deadline
    /// the same way on a device in any timezone (a 23:59Z deadline reads as
    /// 16:59 locally in North America and must still be all-day, not a late-
    /// afternoon block). A genuine time-of-day becomes a 30-minute block. The
    /// all-day event is anchored to the local day of the instant, which is the
    /// day the user sees and the day the dedup key is built from.
    static func eventTiming(for dueDate: Date) -> (start: Date, end: Date, allDay: Bool) {
        let localCal = Calendar.current
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0) ?? localCal.timeZone
        let utc = utcCal.dateComponents([.hour, .minute], from: dueDate)
        let h = utc.hour ?? 0
        let m = utc.minute ?? 0
        let isDayBoundary = (h == 0 && m == 0) || (h == 23 && m >= 59)
        if isDayBoundary {
            let dayStart = localCal.startOfDay(for: dueDate)
            return (dayStart, dayStart, true)
        }
        let end = localCal.date(byAdding: .minute, value: 30, to: dueDate) ?? dueDate
        return (dueDate, end, false)
    }

    /// A clean single-line title from the detected commitment text, capped so the
    /// calendar row stays tidy. The full text also rides along in the event notes.
    static func eventTitle(from content: String) -> String {
        let oneLine = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 80
        guard oneLine.count > limit else { return oneLine }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: limit)
        return String(oneLine[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Dedup

    /// Title+day key used to skip suggestions already on the calendar.
    static func dedupKey(title: String, day: Date) -> String {
        let normalizedTitle = eventTitle(from: title).lowercased()
        let dayKey = Self.dedupDayFormatter.string(from: day)
        return "\(dayKey)|\(normalizedTitle)"
    }

    private static let dedupDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Keys for the user's existing, non-deleted events (title + start day).
    @MainActor
    private func existingUserEventKeys() -> Set<String> {
        guard let dataController,
              let context = dataController.modelContext,
              let userId = dataController.currentUser?.id else { return [] }
        let descriptor = FetchDescriptor<CalendarUserEvent>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }
        )
        let events = (try? context.fetch(descriptor)) ?? []
        return Set(events.map { Self.dedupKey(title: $0.title, day: $0.startDate) })
    }
}
