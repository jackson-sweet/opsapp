//
//  ScheduleDragSession.swift
//  OPS
//
//  Drag-and-drop reschedule on the Schedule. A long-press + drag lifts an event;
//  dropping it on a day cell (month grid) or week-strip day moves its start there
//  while preserving its span. This file holds the shared, observable drag state plus
//  the Transferable payload that round-trips through the system drag session.
//
//  The actual drop handling, highlight rendering, and cascade prompt live in
//  RescheduleDrop.swift; this file is the dependency-free foundation both surfaces
//  (MonthGridView, CalendarDaySelector) and ScheduleView share.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Private drag type so only the Schedule's day cells accept reschedule drags.
    /// System text/image drags are ignored, and our payload never leaks to other
    /// apps (no public conformance).
    static let opsRescheduleItem = UTType(exportedAs: "com.ops.reschedule-item")
}

/// Which calendar entity is being dragged.
enum RescheduleItemKind: String, Codable { case task, userEvent }

/// The payload carried by a reschedule drag. Small + Codable so it survives the
/// system drag round-trip; the id resolves back to the live SwiftData model on drop.
/// `durationDays` and `startEpoch` are captured at lift so the highlight can project
/// the span and the drop can preserve the original time-of-day without another fetch.
struct RescheduleDragPayload: Codable, Transferable {
    let id: String
    let kind: RescheduleItemKind
    let title: String              // shown in the drag preview chip
    let durationDays: Int          // span length for the live highlight (>= 1)
    let startEpoch: TimeInterval   // original start, to preserve time-of-day on drop

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .opsRescheduleItem)
    }
}

/// Shared, observable state for an in-flight reschedule drag. One instance is owned
/// by ScheduleView and injected into both calendar surfaces via `.environment`.
@MainActor
@Observable
final class ScheduleDragSession {
    /// The item currently lifted (nil when no drag is active).
    var active: RescheduleDragPayload?
    /// The day the finger is currently over (projected start day); nil when off-grid.
    var hoveredDate: Date?
    /// A pending three-way prompt, staged by the coordinator after a clash drop and
    /// presented centrally by ScheduleView.
    var pendingPrompt: ReschedulePrompt?

    /// Mark the start of a drag. Idempotent for the same item so a re-evaluated drag
    /// preview closure can't wipe `hoveredDate` mid-drag and break the highlight.
    func begin(_ payload: RescheduleDragPayload) {
        guard active?.id != payload.id else { return }
        active = payload
        hoveredDate = nil
    }

    /// Clear all in-flight drag state (called on a committed drop).
    func end() {
        active = nil
        hoveredDate = nil
    }

    /// Whether `day` falls within the projected span `[hovered, hovered + duration-1]`.
    /// `weekClamp`, when supplied, limits the highlight to the visible week strip
    /// (the strip shows one week, so a longer span is clamped to what's visible).
    func isInProjectedSpan(_ day: Date, weekClamp: ClosedRange<Date>? = nil) -> Bool {
        guard let start = hoveredDate, let payload = active else { return false }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        guard let e = cal.date(byAdding: .day, value: max(payload.durationDays - 1, 0), to: s) else { return false }
        let d = cal.startOfDay(for: day)
        var inSpan = d >= s && d <= e
        if let clamp = weekClamp {
            inSpan = inSpan
                && d >= cal.startOfDay(for: clamp.lowerBound)
                && d <= cal.startOfDay(for: clamp.upperBound)
        }
        return inSpan
    }
}

/// Data for the three-way crew/dependency prompt, surfaced centrally by ScheduleView
/// after a forward drop that would shift other crew or dependent jobs.
struct ReschedulePrompt: Identifiable {
    let id = UUID()
    let taskId: String
    let taskName: String
    let oldStart: Date?
    let newStart: Date
    let newEnd: Date
    let changes: [SchedulingEngine.CascadeResult.TaskDateChange]
    let contextLine: String
    let primaryLabel: String
}
