# Schedule Month Header Toggle Implementation Plan

> **Execution:** Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Restore the Schedule month-grid toggle as a dedicated, one-tap header button while preserving universal search and the mobile two-action limit.

**Architecture:** Add a small, testable placement policy that classifies Month and Search as primary title-band actions and Filters/Scope as secondary header actions. Render Month as a direct 44pt calendar button, keep Filters/Scope in one overflow menu in the existing Schedule context strip, and leave the calendar view model and data flow unchanged.

**Tech Stack:** SwiftUI, XCTest, OPS design tokens.

**Design System:** `../ops-design-system/project/DESIGN.md` and `../ops-design-system/project/mobile/MOBILE.md`

**Required Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:verification-before-completion`

---

### Task 1: Lock the action-placement contract

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`

**Files:**
- Create: `OPSTests/Views/ScheduleHeaderActionPlacementTests.swift`
- Modify: `OPS/Views/Components/Common/AppHeader.swift`

**Design tokens:** `OPSStyle.Layout.touchTargetMin`, `OPSStyle.Layout.spacing2`, `OPSStyle.Layout.spacing3_5`

1. Add a focused test asserting that an available month toggle and universal search occupy the two primary header slots, while Filters and Scope remain in the secondary group.
2. Run the focused test and verify it fails because the placement policy does not exist.
3. Add the minimal placement policy used by `AppHeader`.
4. Run the focused test and verify it passes.

### Task 2: Render the dedicated Month action

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/Views/Components/Common/AppHeader.swift`
- Modify: `OPS/Views/ScheduleView.swift`
- Modify: `OPS/Wizard/Definitions/SchedulingCalendarWizard.swift`

**Design tokens:** `OPSStyle.Icons.calendar`, `OPSStyle.Icons.calendarFill`, `OPSStyle.Colors.fillNeutral`, `OPSStyle.Typography.bodyBold`, `OPSStyle.Layout.touchTargetMin`

1. Add the direct Month trailing action and route it to the existing `onMonthTapped` closure.
2. Pass the current month-expanded state into the header so the icon and accessibility state reflect the active view.
3. Remove Month from the overflow menu; render the remaining Filters/Scope menu at the trailing edge of the Schedule context strip.
4. Move the wizard target to the direct Month button and update its instruction to “Tap the calendar button.”
5. Run the focused action-placement and existing header geometry/layout tests.

### Task 3: Verify, document, and integrate locally

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`

**Files:**
- Modify: `../ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Review: all changed files

**Design tokens:** Existing tokens only; reject any raw color, spacing, radius, font, or icon values.

1. Update the Schedule header behavior in the software bible.
2. Audit the diff for scope, token use, accessibility, and unrelated changes.
3. Run the focused tests and a generic iOS build in isolated DerivedData.
4. Commit the bug fix atomically with bug ID `625d0c58-3ff6-466c-8945-389a8d699740`.
5. Merge the verified commit into local `main` without pushing, then rerun focused verification on the merged result.
