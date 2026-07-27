# Schedule Sheet Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Load `ops-design` (reads DESIGN.md + MOBILE.md), `animation-studio:ios-animations`, and finish with `custom-skills:audit-design-system`. All new user-facing copy in this plan is final (written under `ops-copywriter`) — do not improvise strings.

**Goal:** Rebuild `CalendarSchedulerSheet` so a user picking dates sees availability, conflicts, sequencing, and proximity *before* committing — on one non-scrolling screen whose only scrolling region is a continuous Apple-Calendar-style month list — with a sticky CLEAR/SAVE bar.

**Architecture:** The sheet becomes fixed chrome (nav → identity → range strip → [push row] → pinned weekday/month header → **scrolling month list** → day panel → footer bar). A new pure-logic `SchedulerDayContext` engine computes per-day signals (crew-busy, crew time-off, this-project, dependency floor, other-events density, distances) and plain-language day interpretations; the view layer only renders it. Long-press on any day opens a half-sheet day inspector. Public init of `CalendarSchedulerSheet` is **unchanged** — all 14 call sites compile untouched.

**Tech stack:** SwiftUI (iOS 17.6 floor — no iOS-18-only scroll APIs; month-scroll tracking uses the `PreferenceKey` approach proven in `MonthGridView`), SwiftData via `DataController`, `SchedulingEngine`/`AutoScheduleManager` for floor + suggestion, `CLLocation` for distance.

**Design system:** `ops-design-system/project/DESIGN.md` + `ops-design-system/project/mobile/MOBILE.md`; iOS tokens `OPS/Styles/OPSStyle.swift`. Zero hardcoded color/spacing/radius/font values — every value below is named by token; verify each token exists in `OPSStyle.swift` before use (all listed ones appear in the current sheet or MonthGridView).

**Required skills for executor:** `custom-skills:executing-plans`, `ops-design`, `animation-studio:ios-animations`, `custom-skills:audit-design-system`.

**Reference files to read before Task 1 (in order):**
1. `OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift` — current sheet (the API contract + cascade/quick-push logic that must survive verbatim)
2. `OPS/Views/Calendar Tab/MonthGridView.swift` — month scroll pattern (`monthsToDisplay` ±12, `datesForMonth` nil-padding, `updateVisibleMonth` PreferenceKey threshold, `MonthJumpPicker` at :1082)
3. `OPS/Utilities/AutoScheduleManager.swift` — `calculateDependencyFloor` (private; Task 2 exposes it)
4. `OPS/Utilities/SchedulingEngine.swift` — `pushByDays` / weekend skip
5. `OPS/DataModels/Supabase/CalendarUserEvent.swift` — time-off model (`type`, `status`, `userId`, `teamMemberIds`)
6. Whatever populates the month grid's user events (search `userevent:` in `MonthGridView.swift` → `MonthGridCache`) — copy its fetch predicate semantics exactly in Task 1
7. `OPS/Styles/OPSStyle.swift` — token names

---

## Non-negotiable product rules (from Jackson, 2026-07-27)

1. **Never hard-block a date.** Every signal — conflict, time off, dependency floor — is a visual guide + named explanation. Any day is always selectable and SAVE always commits a valid range.
2. **Dependency floor is a soft guide:** days strictly before (latest scheduled prerequisite end) render dimmed; selecting them adds an amber note, nothing more. No prerequisites scheduled → no dimming anywhere.
3. **Long-press a day → half-sheet inspector:** plain-language interpretation line **in the header**, day's events below, one state-aware action button.
4. Conflict rows must name **project + client + crew member + distance** — never a bare task-type name.
5. One commit point: sticky footer **SAVE** (steel-blue primary). Nav bar has **Cancel only**. Footer **CLEAR** resets the in-sheet selection and never unschedules; unscheduling is an explicit `UNSCHEDULE` control visible only when the item has persisted dates.

---

## Final copy table (ops-copywriter — do not improvise)

| Surface | String |
|---|---|
| Nav title | `SCHEDULE TASK` / `SCHEDULE PROJECT` (existing `itemType.displayName`, uppercased) |
| Identity row | `// {TASK TITLE}` + ` · {PROJECT TITLE}` (omit project clause when nil) |
| Unschedule control | `UNSCHEDULE` |
| Range strip labels | `START` / `END` / `DAYS`; empty values `—` |
| Suggestion chip | `SUGGESTED` + `AFTER {PREREQ TITLE} · {EEE MMM d}` (uppercase) |
| Footer primary states | `SELECT START DATE` → `SELECT END DATE` → `SAVE · {N} DAY`/`SAVE · {N} DAYS` |
| Footer secondary | `CLEAR` |
| Panel, nothing selected | `[ TAP A START DATE ]` |
| Panel day headline | `{EEE MMM d}` uppercase |
| Panel range headline | `{MMM d} – {MMM d}` uppercase; right side `{N} CONFLICT`/`{N} CONFLICTS` (tan) or `NO CONFLICTS` (tertiary) |
| Panel empty day | `// NO JOBS · CREW CLEAR` (crew context) / `// NO JOBS` (none) |
| Dependency note row | `BEFORE {PREREQ TITLE} ENDS · {MMM d}` (uppercase, tan) |
| Row line 2 metadata | `{EEE MMM d}` + ` · {D.D} KM` (1 decimal < 10 km, else integer; omit when either coordinate missing) |
| Crew attribution chip | `{FIRST NAME}` (one member) / `{N} CREW` (2+) |
| Same-project chip | `THIS PROJECT` |
| Time-off row | line 1 `{First name} · Time off`, chip `OFF` |
| Elsewhere group / overflow | `// ELSEWHERE` · `+ {N} MORE` |
| Day sheet header label | `// {EEE MMM d}` |
| Day sheet interpretation (priority order, join max 2 with ` · `) | time-off: `{NAME} OFF` / `{NAME} + {N} OFF` → crew busy: `{NAME} ON {PROJECT}` / `{N} CREW ON OTHER JOBS` → floor: `BEFORE {PREREQ} ENDS · {MMM d}` → same project: `{TASK} · THIS PROJECT` → clear: `CREW CLEAR` |
| Day sheet action | `USE AS START` / `USE AS END` |

All uppercase strings render in existing mono/label tokens (`OPSStyle.Typography.category` / `.metadata`); names and titles in Mohave body tokens (`.cardSubtitle` / `.body`). Numbers always mono (`.dataValue`), formatted, `—` when empty.

---

## Visual spec (tokens only)

**Layout (390×844 budget):** nav 52pt · identity 32pt · range strip 56pt · quick-push row 44pt (reschedule only) · suggestion chip 32pt (unscheduled-with-floor only) · pinned month/weekday header ~44pt · **calendar flex ≥300pt** · day panel 150pt fixed (internal scroll, top/bottom fade) · footer 52pt + bottom safe area. Verify on a 667pt-class simulator too: panel may compress to 120pt.

**Day cell (~44–48pt tall, 7 columns, no out-of-month ghost days — months are nil-padded like `datesForMonth`):**
- Day number: `OPSStyle.Typography.dataValue`, top-left, `primaryText`; today = `primaryAccent` number + hairline `primaryAccent` ring (match `MonthDayCell`'s today treatment exactly — read it first).
- Signal bars (bottom, 3pt tall, `progressBarRadius`, stacked max 3): this-project → `primaryText`; crew-busy → `warningStatus`; crew time-off → `warningStatus` at reduced opacity **plus** a hatch overlay (45° repeating stripes — second non-color cue, Airbnb pattern). Other-company-events density → single `Indicator.dotSM` dot in `tertiaryText`.
- Dependency-dimming: pre-floor days render number + bars at 0.35 opacity. Still tappable.
- Selection: start/end caps = `primaryText` fill, `invertedText` number, `cardCornerRadius` on outer corners only (`UnevenRoundedRectangle`); interior range = `Colors` white 8% fill (use the existing pressed/active surface token). Selection chrome draws above signals.
- Touch target: full cell width × cell height ≥ 44pt.

**Panel rows:** 3pt leading stripe (`warningStatus` conflict / `primaryText` this-project / `cardBorder` neutral) · line 1 Mohave title + secondary project · line 2 mono metadata · trailing chip (tan outline attribution / white `THIS PROJECT`). Row background `background.opacity(0.6)`, `smallCornerRadius`.

**Footer bar:** glass-dense surface pinned above home indicator, top hairline. CLEAR = Default button style (`surfaceInput` fill, `cardBorder` border, `primaryText`), 30% width. Primary = 52pt height: disabled states `surfaceInput` fill + `tertiaryText` label; enabled `SAVE` = **`primaryAccent` fill, `invertedText`(black) label** — the screen's single accent element.

**Day sheet:** system half sheet, `.presentationDetents([.medium])`, drag handle visible, glass-dense background. Header: mono date label + Mohave interpretation line. Rows as panel rows. Action button = Default style (never accent — accent stays on SAVE).

**Motion (single curve, `OPSStyle.Animation` tokens only; reduced-motion → opacity-only):** cell selection `.faster` + light impact (existing); panel content crossfade `.fast`; range completion with ≥1 conflict → warning notification haptic once; SAVE tap medium impact + success per `emitsSuccessFeedbackOnConfirm` contract (unchanged); suggestion chip fade-in `.fast`; long-press 0.35s + light impact on sheet open. No spring, no bounce.

**Removed outright:** filter chips (`THIS PROJECT`/`MY CREW`), `N SHOWN` counter, legend strip, chevron month paging, in-scroll action buttons, nav-bar Clear. The grid now always encodes crew+project signals; the panel and day sheet carry the full truth (relevant first, `// ELSEWHERE` for the rest).

---

## Behavior spec

**Selection state machine** (`enum SchedulerSelection { case none, start(Date), range(Date, Date) }`):
- Open: persisted dates → `.range(current)` (grid shows them; SAVE immediately valid). No dates → `.none`.
- Tap day: `.none → .start(d)`; `.start(a) → .range(min, max)` (same day twice = single-day range); `.range → .start(d)` (restart).
- CLEAR → `.none` (light impact). Never calls `onClearDates`. Sheet stays open.
- UNSCHEDULE (visible only when `currentStartDate != nil || currentEndDate != nil`): warning haptic → `onClearDates?()` → dismiss (today's semantics, now behind an explicit, honestly-named control).
- SAVE (enabled only in `.range`): `onScheduleUpdate(start, end)` → dismiss. Haptics per `emitsSuccessFeedbackOnConfirm`.
- Tutorial mode: Cancel disabled exactly as today; no other coupling exists (verified — wizard targets live in MonthGridView only).

**Signals (`SchedulerDayContext`, pure, built once per data change — preserve the O(tasks) day-index optimization from the current sheet, including the sync-republish freeze rationale):**
- Inputs: scheduled tasks ±3 months (existing `getScheduledTasks(in:)`), **new** user-events range fetch, item crew (`preselectedTeamMemberIds` ?? item's), item projectId, item coordinates, dependency floor, self-exclusion (task's own id).
- Crew-busy day: any other task on that day whose crew intersects item crew. Time-off day: any user event on that day of type `time_off` **or** `personal` whose `userId`/`teamMemberIds` intersect item crew and whose status is `approved` or `none` (pending/denied never block — mirror the schedule tab's treatment; confirm against `MonthGridCache`).
- Floor: latest `endDate` among this project's non-deleted, non-cancelled tasks whose `taskTypeId` ∈ item's `effectiveDependencies` targets; floor day = that end + 1 day. Expose `AutoScheduleManager.calculateDependencyFloor` (private→internal) if its signature fits; otherwise implement in the engine with the same semantics and a test pinning agreement.
- Suggestion: only when item unscheduled AND floor exists → start = floor advanced past weekends via `SchedulingEngine.pushByDays` semantics (respect `currentCompanySkipsWeekends`); tap = `.start(suggested)`.
- Conflicts (range mode): overlapping events sorted conflicts-first; attribution = overlapping crew first names.
- Distance: haversine via `CLLocation.distance(from:)` between item project coordinate and event project coordinate; nil-safe.

**Month scroll:** `LazyVStack` of months −12…+12 around anchor; anchor month = persisted start ?? suggestion ?? today; `ScrollViewReader` jump on appear (non-animated); inline month captions `// JULY 2026`; pinned header shows visible month via the `MonthGridView` PreferenceKey/threshold pattern + `MonthJumpPicker` (Task 3 extracts it to a shared file, unchanged).

**Quick-push + cascade:** logic moves verbatim (`handleQuickPush`, `cascadeAffectedCount`, `quickPushDates`, `CascadePreviewSheet` wiring, `showCascadePreview` pref). Restyle container only.

---

## Tasks

> TDD throughout: each task = failing test → run (expect FAIL) → implement → run (expect PASS) → commit. Test target runs on the simulator destination (`platform=iOS Simulator,name=iPhone 17,OS=26.5`); device-target build check is `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`. Before ANY xcodebuild: `ps aux | grep xcodebuild` / `lsof` for sibling sessions. Preserve CRLF line endings on edited files.

### Task 1 — User-events range fetch on DataController
**Files:** Modify `OPS/Utilities/DataController.swift` (near `getUserEvent(id:)` :4392); Test `OPSTests/Scheduling/SchedulerDayContextTests.swift` (new file, first test).
Add `getUserEvents(in range: ClosedRange<Date>) -> [CalendarUserEvent]`: company-scoped, `deletedAt == nil`, overlapping range, statuses `approved`/`none` only — copy the month-grid cache's predicate semantics. Test with an in-memory `ModelContext`: seed one approved time-off, one denied, one deleted; assert only the approved returns. Commit: `feat(scheduling): add ranged user-event fetch for scheduler availability`.

### Task 2 — SchedulerDayContext engine
**Files:** Create `OPS/Views/Components/Scheduling/SchedulerDayContext.swift`; Modify `OPS/Utilities/AutoScheduleManager.swift` (floor access); Test `OPSTests/Scheduling/SchedulerDayContextTests.swift`.
Pure struct built from inputs above exposing: `signals(for day: Date) -> DaySignals` (thisProject, crewBusy, crewTimeOff, otherCount, isPreFloor), `events(on day:)` split relevant/elsewhere, `rangeReview(start:end:) -> RangeReview` (rows conflicts-first, conflict count, floor violation), `interpretation(for day:) -> String` (priority composition per copy table), `suggestion() -> Date?`, `distanceKM(to event:) -> Double?` + formatting.
Tests (each its own TDD cycle): floor from latest scheduled prereq only; unscheduled prereqs → no floor, no pre-floor days; time-off marks busy, denied/pending don't; attribution `MARCUS` vs `2 CREW`; interpretation priority (time-off beats crew-busy beats floor; max 2 clauses); suggestion skips weekend when company skips weekends; distance format `2.1 KM`/`12 KM`/nil; self-task excluded everywhere; single-source-of-truth day index (one pass over tasks). Commit: `feat(scheduling): day-context engine — availability, time off, dependency floor, proximity, day interpretation`.

### Task 3 — Extract MonthJumpPicker
**Files:** Create `OPS/Views/Calendar Tab/Components/MonthJumpPicker.swift` (move struct from `MonthGridView.swift:1082` unchanged, drop `private`); Modify `MonthGridView.swift`. Build both call sites clean (device-target). Commit: `refactor(calendar): extract MonthJumpPicker for reuse by the schedule sheet`.

### Task 4 — SchedulerMonthScroll + redesigned SchedulerDayCell
**Files:** Create `OPS/Views/Components/Scheduling/SchedulerMonthScroll.swift`, `OPS/Views/Components/Scheduling/SchedulerDayCell.swift`; Test `OPSTests/Scheduling/SchedulerSelectionTests.swift` (selection machine as a testable reducer) + snapshot render smoke via `UIHostingController` + `drawHierarchy` (asset colors render correctly this way — never `ImageRenderer`).
Continuous month list per behavior spec; cell per visual spec (signals, dimming, selection chrome, today ring parity with `MonthDayCell`); tap callback; long-press (0.35s, light impact) callback. Selection reducer tests: none→start→range auto-sort, same-day single-day, range→restart, prefill-from-persisted. Commit: `feat(scheduling): continuous month scroll with availability-signal day cells`.

### Task 5 — Sheet rebuild (fixed chrome, panel, footer)
**Files:** Rewrite `OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift` (public init byte-identical); Create `OPS/Views/Components/Scheduling/SchedulerFooterBar.swift`.
Assemble per layout budget: nav (Cancel-only + title), identity row (+`UNSCHEDULE` when persisted dates), range strip, quick-push row (verbatim logic), suggestion chip, pinned month/weekday header + `MonthJumpPicker`, month scroll, day panel (`[ TAP A START DATE ]` / day rows / range review with conflict count + floor note), footer (CLEAR + three-state primary). Wire haptics + motion per spec. Delete filter chips, legend, chevrons, old action buttons, old nav Clear. Device-target build + full `OPSTests` pass (all call sites compile untouched — grep to confirm zero caller edits). Commit: `feat(scheduling): rebuild schedule sheet — one-screen layout, sticky save bar, named conflicts`.

### Task 6 — Long-press day sheet
**Files:** Create `OPS/Views/Components/Scheduling/SchedulerDaySheet.swift`; Modify sheet to present it.
Half sheet per visual spec: header interpretation, relevant rows, `// ELSEWHERE` group, `USE AS START`/`USE AS END` action (applies reducer transition, light impact, dismiss). Test: interpretation string already covered (Task 2); add reducer test for use-as-start-while-range (restarts at day). Commit: `feat(scheduling): long-press day inspector with plain-language day interpretation`.

### Task 7 — Proof, audit, bible
1. Run full `OPSTests` on simulator — green, capture summary.
2. Device-target build — clean.
3. Simulator walkthrough with screenshots (scratchpad, then delivered): empty state, start-picked with suggestion chip, range with named conflict + distance, pre-floor dimming, long-press day sheet, reschedule mode (push row + UNSCHEDULE), 667pt-class device fit.
4. Run `custom-skills:audit-design-system` over changed files — zero hardcoded values.
5. Update `ops-software-bible` scheduling/calendar section (find the schedule-sheet subsection; describe new signals, day sheet, save model) — commit in bible repo: `docs(bible): schedule sheet redesign — availability signals, day inspector, single save point`.
6. Deliver proof to Jackson: screenshots + plain-language summary. **No push** — local commits only; push is Jackson's call.

**Failure protocol:** any gnarly build/test surprise (e.g. stale-`.o` JobBoardView-style latent breaks) → clean DerivedData for this scheme only after confirming no sibling xcodebuild is live. Simulator login: reuse an already-signed-in simulator; repeated failed sign-ins trip Firebase throttling.
