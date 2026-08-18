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
///
/// Ownership rule (bug 4baf3104): the *drop session* is the authority on whether a
/// drag is live — never the `.draggable` preview's view lifecycle. SwiftUI creates
/// and tears that preview down on its own schedule, and every teardown used to arm a
/// deferred `end()` that wiped `active` mid-drag. Hover kept updating (so the
/// selection haptic still fired on every day cell) while every visual consumer —
/// the day-cell highlight, the target banner, the month grid's badge hit-testing —
/// read `active == nil` and rendered nothing. Hover now re-arms the visual state
/// synchronously from the retained lift, so a torn-down preview costs nothing.
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

    /// What the last lift put in the operator's hand. Kept for the whole gesture so
    /// a hover arriving after the drag preview was torn down can re-arm `active`
    /// in the same main-actor transaction — no item-provider round trip, no race.
    /// Cleared only by `end()` (a committed drop, or a drag that went off-grid and
    /// stayed there).
    private(set) var lifted: RescheduleDragPayload?

    /// Whether a reschedule drag is live. Consumers that must stand aside for the
    /// drag — the month grid's event badges, which otherwise swallow the drop
    /// hit-test before it reaches the day cell beneath — gate on this rather than
    /// on `active`, so they are not re-enabled mid-drag by a preview teardown.
    var isDragInFlight: Bool { active != nil || hoverSource != nil }

    /// The in-flight deferred end. Exposed (read-only) so a test can await the
    /// exact task instead of sleeping past it and hoping — a fixed wall-clock
    /// window is a race the machine wins under full-suite load. Production never
    /// reads it; it only ever cancels through the mutators below.
    @ObservationIgnored
    private(set) var deferredEndTask: Task<Void, Never>?

    /// How the deferred end waits out its delay. Production sleeps on the real
    /// clock — identical to the shipped behavior. Tests inject a sleeper they
    /// resume by hand, which puts the whole timing of this path under the test's
    /// control and takes the wall clock out of the assertion (bug e0f6915d;
    /// mirrors the clock seam `InboundChangeRouter` took for the same reason).
    @ObservationIgnored
    private let sleep: @MainActor (Duration) async -> Void

    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Mark the start of a drag. Idempotent for the same item so a re-evaluated drag
    /// preview closure can't wipe `hoveredDate` mid-drag and break the highlight.
    func begin(_ payload: RescheduleDragPayload) {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        lifted = payload
        guard active?.id != payload.id else { return }
        active = payload
        hoveredDate = nil
        hoverSource = nil
    }

    /// Take the payload the drop session itself handed us as the truth about what is
    /// in flight. The synchronous re-arm in `updateHover` covers every drag that
    /// armed the session at lift; this is the correction for the case where it never
    /// did (the preview's `onAppear` did not run), and it costs one item-provider
    /// load per target entry — never one per drag-move frame.
    ///
    /// Guarded on *some* target owning hover rather than a specific one: the load is
    /// asynchronous, so the finger has usually moved on by the time it lands, and
    /// adopting is still correct — it is the same drag. Once no target owns hover the
    /// drag is over the grid no longer, and a late adopt must not resurrect it.
    func adoptDraggedPayload(_ payload: RescheduleDragPayload) {
        guard hoverSource != nil else { return }
        deferredEndTask?.cancel()
        deferredEndTask = nil
        lifted = payload
        active = payload
    }

    func updateHover(day: Date, source: ScheduleDragHoverSource) {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        // A hover on one of our private-UTType drop targets is proof a reschedule
        // drag is live — the type never leaves the app. Re-arm from the retained
        // lift so the highlight and the target banner never depend on whether
        // SwiftUI still has the drag preview mounted.
        if active == nil, let lifted { active = lifted }
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

    /// Clear all in-flight drag state, `lifted` included. Called on a committed drop:
    /// the gesture is over and nothing may re-arm from it.
    func end() {
        standDown()
        lifted = nil
    }

    /// Drop the *visual* drag state without forgetting what was lifted. The badges
    /// get their hit-testing back (an abandoned drag must not leave the month grid
    /// inert) while `lifted` stays, so a finger that comes back over the grid inside
    /// the same gesture re-arms the exact span instead of a one-day placeholder.
    private func standDown() {
        deferredEndTask?.cancel()
        deferredEndTask = nil
        active = nil
        hoveredDate = nil
        hoverSource = nil
    }

    /// `.draggable` preview teardown can fire before the native drop delegate
    /// finishes. Defer clearing so a live target can keep highlights and edge paging
    /// armed; stand down shortly after only if the drag is truly off-grid.
    ///
    /// The cancellation check is load-bearing. `try?` swallows the cancellation
    /// error and lets the body run on, so a cancelled deferred end could still
    /// reach the stand-down and wipe a drag that had just been re-lifted onto the
    /// same item — `begin` returns early for a repeat id without touching `active`
    /// or `hoverSource`, which is exactly the state this guard is checking.
    func endWhenOffGrid(after delay: Duration = .milliseconds(500)) {
        let activeId = active?.id
        deferredEndTask?.cancel()
        deferredEndTask = Task { @MainActor [weak self] in
            // The sleeper, not `self`, is held across the suspension — the
            // session stays weakly referenced exactly as it was before.
            guard let sleeper = self?.sleep else { return }
            await sleeper(delay)
            guard
                !Task.isCancelled,
                let self,
                self.hoverSource == nil,
                self.active?.id == activeId
            else {
                return
            }
            self.standDown()
        }
    }

    /// The projected span length in days. Falls back to a single day when the lifted
    /// payload is not (yet) known — a hover proves a drag is live, and a one-day
    /// highlight the moment the finger lands beats no highlight at all while the
    /// item provider is still resolving.
    var projectedSpanDays: Int {
        max(active?.durationDays ?? lifted?.durationDays ?? 1, 1)
    }

    /// Whether `day` falls within the projected span `[hovered, hovered + duration-1]`.
    /// `weekClamp`, when supplied, limits the highlight to the visible week strip
    /// (the strip shows one week, so a longer span is clamped to what's visible).
    ///
    /// Keyed on the hover alone. Requiring `active` here is what made the highlight
    /// vanish while the haptics kept firing (bug 4baf3104) — the haptic only needs
    /// the hover to change, so the two disagreed exactly when `active` was lost.
    func isInProjectedSpan(_ day: Date, weekClamp: ClosedRange<Date>? = nil) -> Bool {
        guard let start = hoveredDate else { return false }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        guard let e = cal.date(byAdding: .day, value: projectedSpanDays - 1, to: s) else { return false }
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
