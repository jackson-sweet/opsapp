# Schedule Quick Actions Regression Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Restore Push, Extend, Cascade, and Reschedule everywhere a task appears in Schedule, without breaking drag-to-reschedule.

**Architecture:** Keep each schedule item as the single owner of its long-press menu. Reuse one injected action contract across week/day cards, ongoing spans, month badges, and month day-detail cards. Keep permission checks and mutation paths in the existing scheduling engine/DataController flow, and verify the real SwiftUI context-menu gesture at production month-grid dimensions.

**Tech Stack:** SwiftUI, SwiftData, XCTest/XCUITest, iOS 17.6+

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; production styling remains on `OPSStyle` tokens.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

---

### Task 1: Prove the uncovered regressions

**Skills:** TDD, mobile UX, iOS motion.

**Files:**
- Modify: `OPS/Views/Calendar Tab/ScheduleLongPressQAHost.swift`
- Modify: `OPSUITests/ScheduleLongPressMenuUITests.swift`

**Design tokens:** Existing `OPSStyle.Layout`, `OPSStyle.Typography`, and `OPSStyle.Colors` only. Month fixture uses the production default `cellHeight` and seven-column width.

1. Add QA fixtures for an ongoing week/day card and a month day-detail card using their current production wiring.
2. Tighten the month badge fixture to production dimensions.
3. Add UI assertions that all three surfaces expose Extend and Cascade, plus an action-callback assertion.
4. Run the focused UI suite and capture the expected failures before production code changes.

### Task 2: Restore one complete menu on every task surface

**Skills:** Interface design, mobile UX, iOS motion.

**Files:**
- Modify: `OPS/Views/Calendar Tab/Components/CalendarEventCard.swift`
- Modify: `OPS/Views/Calendar Tab/DayCanvasView.swift`
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift`

**Design tokens:** No new visual values. Existing system context-menu presentation, SF Symbols, `OPSStyle` haptics/colors/spacing.

1. Pass the rich action contract to ongoing cards instead of falling back to Reschedule-only.
2. Add Extend and Cascade handlers to the live month-grid badge path using the same DataController scheduling engine and preview semantics.
3. Inject the rich action contract into new and ongoing cards inside the month day-detail sheet.
4. Keep permission gating scope-aware and preserve status-only behavior for read-only crew.
5. Keep one `.contextMenu` per item and preserve `.reschedulable` drag coexistence.

### Task 3: Make the month interaction field-usable

**Skills:** Mobile UX, OPS design, accessibility.

**Files:**
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift`

**Design tokens:** Mobile minimum interaction target (44pt) from `MOBILE.md`; existing visual badge heights and `OPSStyle` styling remain unchanged.

1. Separate the compact visible badge from its 44pt interaction row.
2. Update month slot allocation so interaction rows do not overlap.
3. Add an explicit accessibility label, button trait, and quick-action hint.

### Task 4: Verify, document, and commit

**Skills:** Design-system audit, verification before completion.

**Files:**
- Modify if required: `../ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`
- Modify: live `public.bug_reports` row `75318af9-827d-4e63-ae6f-9ddcd30dae19`

1. Run the focused XCUITest suite and confirm every long-press/action/drag case passes.
2. Run focused scheduling unit tests and an unsigned generic iOS device build.
3. Audit changed UI for hardcoded styling and accessibility regressions.
4. Update the Bible only if its current Schedule contract is incomplete.
5. Commit only this ticket's files on local `main`; do not push.
6. Record exact commits and proof on the live ticket, leave it `in_progress` with human review required, and stop for Jackson's verification.
