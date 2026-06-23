# Drag-and-Drop Reschedule — iOS Schedule

**Date:** 2026-06-22
**Branch:** `feat/ios-drag-reschedule` (worktree off `main`)
**Author:** Jackson (requested) / implementation by Claude
**Status:** Approved design → implementation

---

## 1. Summary

Add direct-manipulation drag-and-drop rescheduling to the OPS iOS Schedule. A user
long-presses a job/event, drags it, and drops it on a day — the event's start moves to
that day and its duration/span is preserved. While dragging a multi-day event, every day
it will occupy lights up live. When dropping a job onto days where the **same crew** is
already booked, the user is prompted to cascade-shift that crew's other work (reusing the
existing scheduling-cascade engine), move only this job (overlap allowed), or cancel.

This is a **new interaction layer over existing write/cascade paths** — it does **not**
introduce a new scheduler. The cascade engine, write paths, permission gate, haptics,
and tokens all already exist; this feature wires them to a native drag-and-drop gesture
plus a live multi-day highlight.

---

## 2. Surfaces

Day cells only exist on two surfaces, so drag-to-reschedule lives on both:

| Surface | Draggable item | Drop targets | Notes |
|---------|----------------|--------------|-------|
| **Month grid** (`MonthGridView`) | `EventBar` badge | `MonthDayCell` day cells | Native drag auto-scrolls the vertical month list to other months. |
| **Week view** (`CalendarDaySelector` + `DayCanvasView`) | `CalendarEventCard` in the day list | `WeekDayCell` in the week strip | Per Jackson: drag a card from the day list **up to the week strip**. |

The week/day pager itself is one-day-at-a-time and keeps its existing swipe-nudge and
time-of-day drag (`TimelineView`). It is not a drop surface.

---

## 3. Interaction model

### 3.1 Lift (long-press)
- Long-press **alone** still opens the existing quick menu (month badge `.contextMenu`;
  day-list card converted from `confirmationDialog` to `.contextMenu` with the same
  actions). Long-press **+ movement** initiates the drag. This is iOS's native
  `.draggable` + `.contextMenu` coexistence — exactly the requested behavior, and it
  gives free drag-session auto-scroll.
- On lift: selection/`.light` haptic; the system renders the drag preview (a spring-based
  lift, the one place CLAUDE.md allows spring physics).

### 3.2 Drag (live multi-day highlight)
- A shared `@Observable ScheduleDragSession` (injected via `.environment`) carries the
  active item, its `durationDays`, and the currently-hovered target day.
- Each day cell is a `.dropDestination`; when targeted it sets
  `session.hoveredDate = cellDate`. Every day cell reads the session and highlights itself
  when it falls in `[hoveredDate, hoveredDate + durationDays - 1]` (clamped to the visible
  week on the week strip). Highlight animates on the OPS curve (`OPSStyle.Animation.curve`,
  already reduce-motion-aware) — no pulsing/breathing under Reduce Motion.
- A small floating date pill (JetBrains Mono) follows the drag showing the target start
  date.
- Haptic: `UISelectionFeedbackGenerator.selectionChanged()` **only when the target day
  changes** (no haptic spam). Generators pre-warmed on lift.

### 3.3 Drop (commit)
Target start day `D` is the dropped cell's date with the original time-of-day preserved.
New span: `targetStart = D + timeOffset(originalStart)`,
`targetEnd = targetStart + (originalEnd − originalStart)` (calendar days — preserves span
exactly, including weekends, matching how `duration` is stored).

- **Same day / outside any cell:** snap back, no write, no haptic (or soft).
- **Different day, no crew/dependency clash:** commit single move; `.medium` impact then
  `.success` 200ms later (two-beat commit); success toast.
- **Different day, crew/dependency clash (forward move):** `.medium` impact, present the
  three-way prompt (§5). Success haptic + toast fire after the chosen action commits.

### 3.4 Permission gate (defense in depth)
- `.draggable` is attached **only when** `task.canEditSchedule` (→
  `PermissionStore.canEditSchedule(assigneeIds:)`, key `calendar.edit`, scope-aware). Crew
  without the grant can view but not drag. "own"/"assigned" users can only drag jobs they
  are assigned to.
- The gate is **re-checked** in the commit path before any write.

---

## 4. Cascade reuse (no new scheduler)

The drop reschedules to **explicit target dates**, so it cannot route through
`planCascade(byDays:)` (which weekend-normalizes the pushed task via `pushByDays`). Two
thin DataController methods reuse the existing engine functions directly:

```swift
// Same as planCascade, minus the pushByDays step — explicit target dates.
@MainActor
func planDropReschedule(for task: ProjectTask, targetStart: Date, targetEnd: Date) -> CascadePlan?
// → SchedulingEngine.calculateCrewConsolidation(...) (forward-only, only when moving later)
//   + SchedulingEngine.calculateCascade(...) seeded with crew dates
//   merged into CascadePlan (same shape planCascade returns)

@MainActor @discardableResult
func commitDropReschedule(_ task: ProjectTask, targetStart: Date, targetEnd: Date,
                          cascade: Bool) async throws -> SchedulingEngine.CascadeResult
// cascade == false → updateTaskSchedule(task, targetStart, targetEnd)  (single move)
// cascade == true  → updateTaskSchedule(pushed) + updateTaskSchedule(each change, manualEdit:false)
```

Both reuse `updateTaskSchedule` (which already handles local save, `recordOperation`
outbound sync, iPhone Calendar mirror, and the schedule-change push/in-app notification to
affected crew). `scheduleLocked` (user-pinned) tasks are never auto-shifted — the engine
already enforces this.

**Forward-only:** `calculateCrewConsolidation` and `calculateCascade` only push work
**later** (pulling earlier can break commitments). So crew-cascade applies to forward
drags. A backward/earlier drag reschedules the single job (overlap allowed) with no
cascade — which is the "Move only this" outcome anyway. This matches the existing app.

---

## 5. Crew-cascade prompt (three-way)

Reuse `CascadePreviewSheet`, extended with an **optional** third action and context line
(all existing callers pass `nil` → unchanged). It already previews changes grouped into
"Same crew" / "Dependent tasks".

- Trigger: after a forward drop, compute `planDropReschedule`. If `cascade.changes` is
  non-empty **and** the user's `showCascadePreview` pref is on → present the sheet. If the
  pref is off → apply the full cascade directly (consistent with the pref's meaning). If
  the plan has no changes → commit the single move silently.
- Header: `SCHEDULE CHANGES` (unchanged).
- Context line (new, optional): crew present → `This crew has other work on these days.`;
  dependents only → `Other jobs follow this one.`
- Buttons (OPS voice, sentence/UPPERCASE per design system):
  - Primary (accent, full width): crew → `PUSH THEIR WORK`; dependents-only → `MOVE ALL`
    → `commitDropReschedule(cascade: true)`
  - Secondary (nested card): `MOVE ONLY THIS` → `commitDropReschedule(cascade: false)`
  - Tertiary (text): `CANCEL` → snap back, no write

Success toast: single move reuses `Feedback.Task.scheduledFor(start:end:)`; cascade shows
a concise `Schedule updated — N jobs moved` style toast via `ToastCenter`.

---

## 6. Event kinds

| Kind | Drag? | Cascade? | Write path | Weekend |
|------|-------|----------|------------|---------|
| `ProjectTask` (crew job) | yes (gated `canEditSchedule`) | yes (forward) | `commitDropReschedule` → `updateTaskSchedule` | allowed |
| `CalendarUserEvent`, non-recurring | yes (owner) | no | `CalendarUserEventRepository.updateEvent` (mirror the existing edit path's status handling) | allowed |
| `CalendarUserEvent`, recurring | **no drag** | — | keeps existing tap-to-edit + `RecurringEventEditScopeSheet` | — |

Recurring user events are the one deliberate gap: a drag has no way to ask "this / future /
all," so they keep the explicit scope picker rather than silently rewriting a series.

---

## 7. New / modified files

**New**
- `OPS/Views/Calendar Tab/Components/ScheduleDragSession.swift` — `@Observable` drag
  session + `RescheduleDragPayload: Codable, Transferable` (custom `UTType.opsRescheduleItem`)
  + shared highlight/haptic helpers + the drop-commit coordinator (resolves item, plans,
  presents prompt, commits).
- `OPS/Views/Calendar Tab/Components/RescheduleDayHighlight.swift` (or a `ViewModifier`) —
  the day-cell highlight + `.dropDestination` wrapper reused by month and week cells, and
  the floating target-date pill.

**Modified**
- `DataController.swift` — add `planDropReschedule` + `commitDropReschedule` (reuse engine
  + `updateTaskSchedule`); add `commitUserEventReschedule` helper for non-recurring user
  events.
- `MonthGridView.swift` — `EventBar` gets `.draggable` (gated); `MonthDayCell` gets the
  drop/highlight wrapper; grid gets the named coordinate space + session env; present the
  extended `CascadePreviewSheet`.
- `CalendarDaySelector.swift` — `WeekDayCell`s get the drop/highlight wrapper; week-strip
  edge-dwell paging during a drag (advance week after a brief dwell at an end cell); inject
  session.
- `CalendarEventCard.swift` — `.onLongPressGesture`→`confirmationDialog` converted to
  `.contextMenu` (same actions); add `.draggable` (gated); present prompt/commit.
- `DayCanvasView.swift` — thread the session; ensure the day list's card drags reach the
  strip.
- `ScheduleView.swift` — own the `ScheduleDragSession`, inject via `.environment`, host the
  shared prompt sheet + toast.
- `CascadePreviewSheet.swift` — optional `contextLine`, `primaryLabel`, and
  `onMoveOnly: (() -> Void)?` (renders the third button only when provided).
- `Feedback.swift` (or wherever `Feedback.Task` lives) — add the cascade toast string if
  not already present.
- Register `UTType.opsRescheduleItem` (Info.plist exported type or a code-only
  `UTType(exportedAs:)`).

---

## 8. States

- **Lift:** source dims to a placeholder; system drag preview lifts (spring); selection/light haptic.
- **Dragging · valid target:** span cells highlight (accent fill + hairline); date pill follows; selection tick on each new day.
- **Dragging · no/invalid target (outside, or same day):** no highlight; no commit on release.
- **Drop · no clash:** single move; two-beat commit haptic; success toast.
- **Drop · clash (forward):** prompt; commit on chosen action; success haptic + toast.
- **Drop · same day / cancel:** snap back; no write.
- **Permission denied:** no drag affordance; non-editors keep tap + quick menu.
- **Offline:** writes queue via the existing `recordOperation` sync path (no special UI).

---

## 9. Motion & haptics (from animation-architect → ios-animations)

- **Tier 1 SwiftUI Native.** Native drag-and-drop for lift/drop (system spring; the allowed
  drag-drop exception). Highlights animate via `OPSStyle.Animation.curve(...)`
  (cubic-bezier 0.22,1,0.36,1; reduce-motion-aware). No bounce; controlled springs only.
- **Haptics:** lift = `.selection`/`.light`; target change = `.selection` (on change only);
  commit = `.medium` impact + `.success` notification +200ms (two-beat). Generators
  pre-warmed on lift. Reduce Motion changes visuals only — haptics still fire.
- **ProMotion-safe:** SwiftUI animations adapt automatically.

---

## 10. Tokens (no hardcoded values)

- Accent / valid highlight: `OPSStyle.Colors.opsAccent` (steel blue) + `glassBorder` hairline.
- Surfaces: `.glassSurface()` / `.glassDense()`; radii `panelRadius`/`cardRadius`/`chipRadius`.
- Spacing: `OPSStyle.Layout.spacing*`. Touch targets: full day cells (≥44pt).
- Numbers (date pill): JetBrains Mono via `OPSStyle.Typography`, tabular/slashed-zero.
- Animation: `OPSStyle.Animation.curve` / `.panel`. Reduce motion: built into the tokens.

---

## 11. Out of scope (explicit)

- Drag inside the week/day pager itself (it is single-day; keeps swipe + time-drag).
- Recurring user-event drag (keeps the scope picker).
- A "pull earlier" cascade (engine is forward-only by design).
- Schema changes — **none.** All writes use existing columns/paths.

---

## 12. Verification

- `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO build` (worktree-local DerivedData; Secrets.xcconfig copied in).
- Manual: month drag across months (auto-scroll); week list→strip drag; multi-day highlight; crew-clash prompt all three branches; permission gate (non-editor can't drag, own-scope limited to own jobs); user-event drag; Reduce Motion; offline write queues.
