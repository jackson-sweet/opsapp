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

/// Owns the current hover target so stale `dropExited` callbacks from a previous
/// cell cannot clear the day currently under the operator's finger.
enum ScheduleDragHoverSource: Equatable {
    case dayCell(Date)
    case weekRowEdge(CalendarWeekRowEdgeDirection)

    static func dayCell(for day: Date, calendar: Calendar = .current) -> ScheduleDragHoverSource {
        .dayCell(calendar.startOfDay(for: day))
    }
}

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
    var hoverSource: ScheduleDragHoverSource?
    /// A pending three-way prompt, staged by the coordinator after a clash drop and
    /// presented centrally by ScheduleView.
    var pendingPrompt: ReschedulePrompt?
    @ObservationIgnored
    private var deferredEndTask: Task<Void, Never>?

    /// Mark the start of a drag. Idempotent for the same item so a re-evaluated drag
    /// preview closure can't wipe `hoveredDate` mid-drag and break the highlight.
    func begin(_ payload: RescheduleDragPayload) {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        guard active?.id != payload.id else { return }
        active = payload
        hoveredDate = nil
        hoverSource = nil
    }

    /// Re-arm the visual drag state from the drop payload while a target is still
    /// hovered. This covers SwiftUI tearing down the drag preview before the drop
    /// delegate commits; the drop can still work, but highlights need `active`.
    func restoreActive(_ payload: RescheduleDragPayload, whileHovering source: ScheduleDragHoverSource) {
        guard hoverSource == source else { return }
        deferredEndTask?.cancel()
        deferredEndTask = nil
        active = payload
    }

    func updateHover(day: Date, source: ScheduleDragHoverSource) {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        hoverSource = source
        hoveredDate = day
    }

    @discardableResult
    func refreshHover(day: Date, source: ScheduleDragHoverSource, calendar: Calendar = .current) -> Bool {
        let changed = hoveredDate.map { !calendar.isDate($0, inSameDayAs: day) } ?? true
        updateHover(day: day, source: source)
        return changed
    }

    func clearHover(source: ScheduleDragHoverSource) {
        guard hoverSource == source else { return }
        hoverSource = nil
        hoveredDate = nil
        endWhenOffGrid(after: .milliseconds(500))
    }

    /// Clear all in-flight drag state (called on a committed drop).
    func end() {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        active = nil
        hoveredDate = nil
        hoverSource = nil
    }

    /// `.draggable` preview teardown can fire before the native drop delegate
    /// finishes. Defer clearing so a live target can keep highlights and edge paging
    /// armed; clear shortly after only if the drag is truly off-grid.
    func endWhenOffGrid(after delay: Duration = .milliseconds(500)) {
        let activeId = active?.id
        deferredEndTask?.cancel()
        deferredEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard
                let self,
                self.hoverSource == nil,
                self.active?.id == activeId
            else {
                return
            }
            self.end()
        }
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
    /// Plain-language "why" lines naming the crew + the follow-on tasks that will
    /// shift — what the user reads before deciding. Derived from the actual changes
    /// so the explanation always matches what commits.
    let explanationLines: [String]
    let primaryLabel: String
}
