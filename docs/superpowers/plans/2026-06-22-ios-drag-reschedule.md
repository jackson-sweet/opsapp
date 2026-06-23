# Drag-and-Drop Reschedule — Implementation Plan

> **For agentic workers:** Execute phase-by-phase. iOS has no fast unit loop for drag-drop UI; the verification gate is `xcodebuild … build` + manual QA. Commit atomically after each green phase.

**Goal:** Long-press + drag an event on the Schedule and drop it on a day to reschedule it (span preserved), with live multi-day highlight and a three-way crew-cascade prompt that reuses the existing scheduling engine.

**Architecture:** A native SwiftUI drag-and-drop layer (`.draggable` + `.dropDestination`, coexisting with the existing context menus) over the existing write/cascade paths. A shared `@Observable ScheduleDragSession` drives the live highlight; a commit coordinator resolves the dropped item, plans via the existing engine (explicit target dates), and either commits silently or presents the extended `CascadePreviewSheet`.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, `UniformTypeIdentifiers`, existing `SchedulingEngine` / `DataController` / `PermissionStore` / `OPSStyle`.

**Build command (worktree-local DerivedData):**
```
cd .worktrees/ios-drag-reschedule
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO build
```
Grep the log for `BUILD SUCCEEDED` (do not trust background exit codes — see memory `xcodebuild-exit-code-masking`).

---

## Phase 0 — Foundation types

**Files:**
- Create: `OPS/Views/Calendar Tab/Components/ScheduleDragSession.swift`

Contains the Transferable payload, the custom UTType, and the `@Observable` session.

```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Private drag type so only the Schedule's day cells accept reschedule drags
    /// (system text/image drags are ignored, and our payload won't leak to other apps).
    static let opsRescheduleItem = UTType(exportedAs: "com.ops.reschedule-item")
}

/// What kind of calendar entity is being dragged.
enum RescheduleItemKind: String, Codable { case task, userEvent }

/// The payload carried by a reschedule drag. Small + Codable so it round-trips
/// through the system drag session; the id resolves back to the live model on drop.
struct RescheduleDragPayload: Codable, Transferable {
    let id: String
    let kind: RescheduleItemKind
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
    /// The day the finger is currently over (target start day), nil when off-grid.
    var hoveredDate: Date?

    /// A pending three-way prompt, set by the commit coordinator after a clash drop.
    var pendingPrompt: ReschedulePrompt?

    func begin(_ payload: RescheduleDragPayload) {
        active = payload
        hoveredDate = nil
    }

    func end() {
        active = nil
        hoveredDate = nil
    }

    /// Whether `day` falls within the projected span [hovered, hovered + duration - 1].
    /// `weekClamp`, when supplied, limits the highlight to the visible week strip.
    func isInProjectedSpan(_ day: Date, weekClamp: ClosedRange<Date>? = nil) -> Bool {
        guard let start = hoveredDate, let payload = active else { return false }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        guard let e = cal.date(byAdding: .day, value: max(payload.durationDays - 1, 0), to: s) else { return false }
        let d = cal.startOfDay(for: day)
        var inSpan = d >= s && d <= e
        if let clamp = weekClamp {
            inSpan = inSpan && d >= cal.startOfDay(for: clamp.lowerBound) && d <= cal.startOfDay(for: clamp.upperBound)
        }
        return inSpan
    }
}

/// Data for the three-way crew/dependency prompt, surfaced centrally by ScheduleView.
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
```

- [ ] Build-verify, then commit: `feat(schedule): drag-reschedule foundation types (session + transferable)`

---

## Phase 1 — DataController: explicit-date plan + commit

**Files:**
- Modify: `OPS/Utilities/DataController.swift` (add next to `planCascade`/`pushTaskWithCascade`, ~line 4095–4130)

`planDropReschedule` mirrors `planCascade` exactly but uses explicit target dates instead of `pushByDays` (so the dropped task lands precisely on the chosen day; crew/dependency packing of OTHER tasks still honors weekend-skip inside the engine). `commitDropReschedule` reuses `updateTaskSchedule` for every write (sync, mirror, notifications all already handled there).

```swift
/// Plan a cascade for a drop onto explicit target dates. Same engine as
/// `planCascade`, minus the `pushByDays` step — the dropped task lands exactly on
/// `targetStart`. Forward-only: crew consolidation runs only when moving later
/// (the engine never pulls work earlier). Returns nil when the task has no start.
@MainActor
func planDropReschedule(for task: ProjectTask, targetStart: Date, targetEnd: Date) -> CascadePlan? {
    guard let originalStart = task.startDate else { return nil }
    let skip = currentCompanySkipsWeekends
    let movingForward = Calendar.current.startOfDay(for: targetStart) > Calendar.current.startOfDay(for: originalStart)

    let companyTasks = getActiveTasksForCompany()
    let crewChanges: [SchedulingEngine.CascadeResult.TaskDateChange] = movingForward
        ? SchedulingEngine.calculateCrewConsolidation(
            pushedTask: task,
            pushedOriginalStart: originalStart,
            pushedNewStart: targetStart,
            pushedNewEnd: targetEnd,
            allTasks: companyTasks,
            skipWeekends: skip)
        : []

    let crewSeed = Dictionary(
        crewChanges.map { ($0.id, (start: $0.newStartDate, end: $0.newEndDate)) },
        uniquingKeysWith: { current, _ in current })

    let dependency = SchedulingEngine.calculateCascade(
        pushedTaskId: task.id,
        newStartDate: targetStart,
        newEndDate: targetEnd,
        allProjectTasks: getTasksForProject(task.projectId),
        skipWeekends: skip,
        seededDates: crewSeed)

    var changesById: [String: SchedulingEngine.CascadeResult.TaskDateChange] = [:]
    for change in crewChanges { changesById[change.id] = change }
    for change in dependency.changes { changesById[change.id] = change }
    let merged = changesById.values.sorted { $0.newStartDate < $1.newStartDate }

    return CascadePlan(pushedNewStart: targetStart, pushedNewEnd: targetEnd,
                       cascade: SchedulingEngine.CascadeResult(changes: merged))
}

/// Commit a drop reschedule. `cascade == false` moves only the dropped task
/// (overlap allowed); `cascade == true` also applies the planned crew + dependency
/// shifts. Every write goes through `updateTaskSchedule` (local save + outbound sync
/// + iPhone-calendar mirror + crew schedule-change notification).
@MainActor
@discardableResult
func commitDropReschedule(_ task: ProjectTask, targetStart: Date, targetEnd: Date,
                          cascade: Bool) async throws -> SchedulingEngine.CascadeResult {
    if !cascade {
        try await updateTaskSchedule(task: task, startDate: targetStart, endDate: targetEnd)
        return SchedulingEngine.CascadeResult(changes: [])
    }
    guard let plan = planDropReschedule(for: task, targetStart: targetStart, targetEnd: targetEnd) else {
        try await updateTaskSchedule(task: task, startDate: targetStart, endDate: targetEnd)
        return SchedulingEngine.CascadeResult(changes: [])
    }
    let applyLookup = Dictionary(getCompanyTasks().map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
    try await updateTaskSchedule(task: task, startDate: plan.pushedNewStart, endDate: plan.pushedNewEnd)
    for change in plan.cascade.changes {
        if let affected = applyLookup[change.id] {
            try await updateTaskSchedule(task: affected, startDate: change.newStartDate,
                                         endDate: change.newEndDate, manualEdit: false)
        }
    }
    return plan.cascade
}
```

For user events, add a helper that mirrors the existing UserEventSheet edit path (verify in `UserEventSheet`/`updateRecurringEvent` whether editing dates resets `status` for time-off, and replicate it):

```swift
/// Reschedule a single (non-recurring) calendar user event, preserving its
/// duration. Mirrors UserEventSheet's edit-save behavior for status handling.
@MainActor
func commitUserEventReschedule(_ event: CalendarUserEvent, targetStart: Date, targetEnd: Date) async throws {
    // 1. optimistic local mutation (+ needsSync / updatedAt) exactly like the edit sheet
    // 2. CalendarUserEventRepository.updateEvent(event.id, fields: EventFieldUpdate(...))
    // 3. post CalendarUserEventsDidChange so the strip/day-list refresh
}
```

- [ ] Build-verify, then commit: `feat(schedule): explicit-date drop reschedule + cascade on DataController`

---

## Phase 2 — CascadePreviewSheet: optional three-way

**Files:**
- Modify: `OPS/Views/Components/Scheduling/CascadePreviewSheet.swift`

Add optional `contextLine: String?`, `primaryLabel: String` (default `"CONFIRM"`), and `onMoveOnly: (() -> Void)?` (default nil). Render the context line under the header when present, and a `MOVE ONLY THIS` button between CONFIRM and CANCEL only when `onMoveOnly != nil`. All three existing callers (`CalendarSchedulerSheet:170`, `TaskRescheduleSheet:108`, `DayCanvasView:456`) keep working unchanged (defaults).

Button stack (vertical for clear hierarchy on small screens):
```swift
VStack(spacing: OPSStyle.Layout.spacing2_5) {
    Button { onConfirm(); dismiss() } label: { /* primaryLabel, accent, full width */ }
    if let onMoveOnly {
        Button { onMoveOnly(); dismiss() } label: { /* "MOVE ONLY THIS", nestedCard */ }
    }
    Button { onCancel(); dismiss() } label: { /* "CANCEL", text */ }
}
```

- [ ] Build-verify, then commit: `feat(schedule): optional three-way action on CascadePreviewSheet`

---

## Phase 3 — Shared highlight + drop modifier + commit coordinator

**Files:**
- Create: `OPS/Views/Calendar Tab/Components/RescheduleDrop.swift`

Contains: (a) a `dropTarget` ViewModifier reused by `MonthDayCell` and `WeekDayCell` that attaches `.dropDestination(for: RescheduleDragPayload.self)`, drives `session.hoveredDate`, fires the selection haptic on day change, and overlays the accent highlight (OPS curve, reduce-motion aware) when the day is in the projected span; (b) the floating date pill; (c) the commit coordinator.

```swift
@MainActor
enum RescheduleCoordinator {
    /// Resolve the dropped payload, compute target dates (preserve time-of-day + span),
    /// re-check the permission gate, then either commit silently or stage a prompt.
    static func handleDrop(_ payload: RescheduleDragPayload, on day: Date,
                           dataController: DataController, session: ScheduleDragSession) {
        let cal = Calendar.current
        let originalStart = Date(timeIntervalSince1970: payload.startEpoch)
        let timeOffset = originalStart.timeIntervalSince(cal.startOfDay(for: originalStart))
        let targetStart = cal.startOfDay(for: day).addingTimeInterval(timeOffset)

        switch payload.kind {
        case .task:
            guard let task = dataController.getTask(id: payload.id), task.canEditSchedule,
                  let oStart = task.startDate, let oEnd = task.endDate else { return }
            // no-op if same day
            if cal.isDate(oStart, inSameDayAs: targetStart) { return }
            let span = oEnd.timeIntervalSince(oStart)
            let targetEnd = targetStart.addingTimeInterval(span)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            let plan = dataController.planDropReschedule(for: task, targetStart: targetStart, targetEnd: targetEnd)
            let changes = plan?.cascade.changes ?? []
            let showPreviewPref = UserDefaults.standard.object(forKey: "showCascadePreview") as? Bool ?? true

            if !changes.isEmpty && showPreviewPref {
                let crew = changes.contains { $0.reason == .crew }
                session.pendingPrompt = ReschedulePrompt(
                    taskId: task.id, taskName: task.displayTitle,
                    oldStart: task.startDate, newStart: targetStart, newEnd: targetEnd,
                    changes: changes,
                    contextLine: crew ? "This crew has other work on these days."
                                      : "Other jobs follow this one.",
                    primaryLabel: crew ? "PUSH THEIR WORK" : "MOVE ALL")
            } else {
                Task {
                    do {
                        let result = try await dataController.commitDropReschedule(
                            task, targetStart: targetStart, targetEnd: targetEnd, cascade: !changes.isEmpty)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        ToastCenter.shared.present(Feedback.Task.scheduledFor(start: targetStart, end: targetEnd))
                        _ = result
                    } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                }
            }

        case .userEvent:
            guard let event = dataController.getUserEvent(id: payload.id) else { return }   // verify accessor
            if event.isRecurringInstance { return }                                          // recurring → not draggable anyway
            if cal.isDate(event.startDate, inSameDayAs: targetStart) { return }
            let span = event.endDate.timeIntervalSince(event.startDate)
            let targetEnd = targetStart.addingTimeInterval(span)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                do {
                    try await dataController.commitUserEventReschedule(event, targetStart: targetStart, targetEnd: targetEnd)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.Task.scheduledFor(start: targetStart, end: targetEnd))
                } catch { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
        }
    }
}
```

Highlight modifier (token-driven, reduce-motion aware):
```swift
struct RescheduleDropTarget: ViewModifier {
    let day: Date
    let weekClamp: ClosedRange<Date>?
    @Environment(ScheduleDragSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    func body(content: Content) -> some View {
        let highlighted = session.isInProjectedSpan(day, weekClamp: weekClamp)
        content
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.opsAccent.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.opsAccent, lineWidth: 1.5))
                }
            }
            .animation(reduceMotion ? nil : OPSStyle.Animation.curve(OPSStyle.Animation.durationHover), value: highlighted)
            .dropDestination(for: RescheduleDragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                RescheduleCoordinator.handleDrop(payload, on: day, dataController: dataController, session: session)
                session.end()
                return true
            } isTargeted: { targeted in
                if targeted {
                    let cal = Calendar.current
                    if session.hoveredDate.map({ !cal.isDate($0, inSameDayAs: day) }) ?? true {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    session.hoveredDate = day
                }
            }
    }
}
```

(`session.end()` on a successful drop clears highlight; a lingering highlight after a drop on empty space is cleared by ScheduleView's `.onChange(of: scenePhase)`-style safety reset + clearing at the start of the next `begin`.)

- [ ] Build-verify, then commit: `feat(schedule): reschedule drop target, highlight, and commit coordinator`

---

## Phase 4 — ScheduleView host (own session, inject env, present prompt)

**Files:**
- Modify: `OPS/Views/ScheduleView.swift`

- Add `@State private var dragSession = ScheduleDragSession()`.
- `.environment(dragSession)` on the content (so both `CalendarDaySelector` subtrees and the month grid see it).
- Present the prompt centrally:
```swift
.sheet(item: Binding(get: { dragSession.pendingPrompt }, set: { dragSession.pendingPrompt = $0 })) { prompt in
    if let task = dataController.getTask(id: prompt.taskId) {
        CascadePreviewSheet(
            pushedTaskName: prompt.taskName,
            pushedTaskOldStart: prompt.oldStart,
            pushedTaskNewStart: prompt.newStart,
            pushedTaskNewEnd: prompt.newEnd,
            cascadeChanges: prompt.changes,
            contextLine: prompt.contextLine,
            primaryLabel: prompt.primaryLabel,
            onConfirm: {
                Task {
                    _ = try? await dataController.commitDropReschedule(task, targetStart: prompt.newStart, targetEnd: prompt.newEnd, cascade: true)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.Task.scheduleUpdatedCascade(count: prompt.changes.count + 1))
                }
            },
            onMoveOnly: {
                Task {
                    _ = try? await dataController.commitDropReschedule(task, targetStart: prompt.newStart, targetEnd: prompt.newEnd, cascade: false)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.Task.scheduledFor(start: prompt.newStart, end: prompt.newEnd))
                }
            },
            onCancel: { })
        .environmentObject(dataController)
        .presentationDetents([.medium])
    }
}
```
- Add `Feedback.Task.scheduleUpdatedCascade(count:)` → e.g. `"Schedule updated — \(count) jobs moved"` (verify the `Feedback` namespace location; add alongside `scheduledFor`).

- [ ] Build-verify, then commit: `feat(schedule): host drag session + crew-cascade prompt in ScheduleView`

---

## Phase 5 — Month grid wiring

**Files:**
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift`

- `EventBar`: add `.draggable` when the span resolves to a draggable, permitted item. Because `EventBar` is generic over spans (tasks + `userevent:` ids), pass a `dragPayload: RescheduleDragPayload?` computed by the parent (`eventBars(_:dates:dayWidth:)`), and attach `.draggable(payload)` only when non-nil. Keep the existing `.contextMenu` (coexists natively).
  - Payload for a task span: `RescheduleDragPayload(id: task.id, kind: .task, durationDays: max(task.duration,1), startEpoch: task.startDate?.timeIntervalSince1970 ?? 0)` — only when `task.canEditSchedule`.
  - Payload for a non-recurring user event span (`userevent:` id): `kind: .userEvent` — only when owned/editable; nil for recurring.
- `MonthDayCell`: apply `.modifier(RescheduleDropTarget(day: date, weekClamp: nil))`.
- Wrap the scrollable month content in `.coordinateSpace(.named("monthGrid"))` is not required for `.dropDestination` (system handles hit-testing); no manual coordinate math needed.

- [ ] Build-verify, then commit: `feat(schedule): drag jobs/events on the month grid onto day cells`

---

## Phase 6 — Week view wiring (list → strip)

**Files:**
- Modify: `OPS/Views/Calendar Tab/Components/CalendarEventCard.swift`
- Modify: `OPS/Views/Calendar Tab/Components/CalendarDaySelector.swift`

`CalendarEventCard`:
- Replace `.onLongPressGesture(0.5) { showingQuickActions = true }` + `confirmationDialog` with a `.contextMenu` exposing the same actions (Reschedule when `canModify`, else Update Status, plus Cancel is implicit). This is the enabling change for native long-press-menu + drag coexistence.
- Add `.draggable(RescheduleDragPayload(id: task.id, kind: .task, durationDays: max(task.duration,1), startEpoch: task.startDate?.timeIntervalSince1970 ?? 0))` only when `task.canEditSchedule`.

`CalendarDaySelector.weekView`:
- Wrap each `WeekDayCell` with `RescheduleDropTarget(day: date, weekClamp: weekDays.first!...weekDays.last!)` so the highlight clamps to the visible week.
- Edge-dwell paging during a drag: when `session.active != nil` and the leftmost/rightmost cell stays targeted ~0.6s, call `navigateToWeek(offset:)`. Implement with a debounced timer keyed on the targeted edge; cancel on un-target/drop.
- The existing horizontal week-swipe `DragGesture` is inert during a native drag session — no conflict — but verify on device.

- [ ] Build-verify, then commit: `feat(schedule): drag day-list cards up to the week strip to reschedule`

---

## Phase 7 — Full verify + QA + docs

- [ ] Full clean build (command above) → grep `BUILD SUCCEEDED`.
- [ ] Manual QA (simulator/device): month drag across months (auto-scroll); multi-day highlight; week list→strip drag + edge paging; crew-clash prompt all three branches; permission gate (non-editor: no drag; own-scope: only own jobs); user-event drag; Reduce Motion (no pulsing, haptics still fire); offline (write queues, no crash); pinned (`scheduleLocked`) task excluded from cascade.
- [ ] Adversarial review (Workflow): drag-session lifecycle/leaks, gate defense-in-depth, cascade forward-only + scheduleLocked, date/duration/timezone, token conformance, recurring-event gap, week-strip gesture conflict. Fix findings; re-verify.
- [ ] Update `ops-software-bible` Section 14 (notifications) / scheduling section if behavior documented there; note no schema change.
- [ ] Final commit if any QA fixes.

---

## Self-review notes
- **Spec coverage:** surfaces (P5/P6), span preserve (P1/P3), live highlight (P3), crew cascade three-way (P2/P3/P4), gate (P3/P5/P6), both kinds (P3/P5/P6), motion+haptics (P3), tokens (P3), no schema change (all). ✓
- **Type consistency:** `RescheduleDragPayload`, `ScheduleDragSession`, `ReschedulePrompt`, `RescheduleDropTarget`, `RescheduleCoordinator`, `planDropReschedule`, `commitDropReschedule`, `commitUserEventReschedule`, `Feedback.Task.scheduleUpdatedCascade` — used consistently across phases. ✓
- **Impl-time verifications (reuse existing, not placeholders):** `Feedback.Task.scheduledFor` API + `Feedback` location; `ToastCenter.present` API; `dataController.getUserEvent(id:)` accessor (add if missing); UserEventSheet date-edit status handling to mirror; confirm `.draggable`+`.contextMenu` lift behavior on device.
