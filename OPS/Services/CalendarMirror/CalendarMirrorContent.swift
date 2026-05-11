//
//  CalendarMirrorContent.swift
//  OPS
//
//  Pure functions: convert CalendarUserEvent / ProjectTask into the
//  title, body, URL, all-day flag, and stable canonical hash used by
//  the mirror writer + reconciler.
//

import Foundation
import CryptoKit

struct MirroredEventPayload: Equatable {
    let opsId: String
    let source: MirrorSource
    let title: String
    let body: String
    let url: URL
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date

    /// Stable hash of all user-visible fields. Used to dedup writes and
    /// to detect drift (user-edited the EKEvent in iOS Calendar).
    var canonicalHash: String {
        let canonical = "\(title)|\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)|\(body)|\(isAllDay ? "1" : "0")"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum CalendarMirrorContent {

    // MARK: - CalendarUserEvent

    static func payload(for event: CalendarUserEvent) -> MirroredEventPayload {
        let title = title(for: event)
        let body = body(address: event.address, notes: event.notes)
        let url = URL(string: "ops://event/\(event.id)")!
        return MirroredEventPayload(
            opsId: event.id,
            source: .calendarUserEvent,
            title: title,
            body: body,
            url: url,
            isAllDay: event.allDay,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }

    private static func title(for event: CalendarUserEvent) -> String {
        let raw = event.title.isEmpty ? "(Untitled)" : event.title
        switch event.eventType {
        case .personal:
            return raw
        case .timeOff:
            switch event.eventStatus {
            case .approved, .none:
                return "Time Off — \(raw)"
            case .pending:
                return "[Pending] \(raw)"
            case .denied:
                return "[Denied] \(raw)"
            }
        }
    }

    // MARK: - ProjectTask

    /// `projectDisplayName`, `taskTypeDisplay`, and `address` are resolved by
    /// the caller from the model context so this remains a pure function.
    static func payload(
        for task: ProjectTask,
        projectDisplayName: String,
        taskTypeDisplay: String,
        address: String?
    ) -> MirroredEventPayload? {
        guard let start = task.startDate, let end = task.endDate else { return nil }

        let title = "\(projectDisplayName) — \(taskTypeDisplay)"
        let body = body(address: address, notes: task.taskNotes)
        let url = URL(string: "ops://projects/\(task.projectId)/tasks/\(task.id)")!

        let isAllDay = task.duration > 1
        let (resolvedStart, resolvedEnd) = resolveTaskDates(task: task, isAllDay: isAllDay, start: start, end: end)

        return MirroredEventPayload(
            opsId: task.id,
            source: .projectTask,
            title: title,
            body: body,
            url: url,
            isAllDay: isAllDay,
            startDate: resolvedStart,
            endDate: resolvedEnd
        )
    }

    private static func resolveTaskDates(task: ProjectTask, isAllDay: Bool, start: Date, end: Date) -> (Date, Date) {
        if isAllDay { return (start, end) }
        // Single-day task: combine startDate with startTime / endTime
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let dayComps = cal.dateComponents([.year, .month, .day], from: start)
        let startTimeComps = cal.dateComponents([.hour, .minute], from: task.startTime)
        let endTimeComps = cal.dateComponents([.hour, .minute], from: task.endTime)
        var combinedStart = DateComponents()
        combinedStart.year = dayComps.year
        combinedStart.month = dayComps.month
        combinedStart.day = dayComps.day
        combinedStart.hour = startTimeComps.hour
        combinedStart.minute = startTimeComps.minute
        var combinedEnd = combinedStart
        combinedEnd.hour = endTimeComps.hour
        combinedEnd.minute = endTimeComps.minute
        return (cal.date(from: combinedStart) ?? start, cal.date(from: combinedEnd) ?? end)
    }

    // MARK: - Body

    private static func body(address: String?, notes: String?) -> String {
        var lines: [String] = []
        if let a = address, !a.isEmpty { lines.append(a) }
        if let n = notes, !n.isEmpty { lines.append(n) }
        lines.append("// OPS · view in app")
        return lines.joined(separator: "\n")
    }
}
