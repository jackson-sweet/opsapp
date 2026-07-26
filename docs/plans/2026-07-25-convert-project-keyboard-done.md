# Convert Project Keyboard Done Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Restore an explicit keyboard-dismiss action to every input in `ConvertToProjectSheet` without changing conversion state or footer behavior.

**Architecture:** Keep `opsKeyboardDoneToolbar()` as the single keyboard accessory implementation and attach it at the conversion sheet root, inside the SwiftUI presentation boundary. Protect the integration with a focused XCTest that evaluates the real sheet body composition and fails if the toolbar modifier is removed.

**Tech Stack:** Swift 5, SwiftUI, XCTest, existing `opsKeyboardDoneToolbar()`, `OPSStyle`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` plus `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; implementation tokens remain in `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

---

## Intent checkpoint

- **Human:** A trades owner converting a won lead from a phone, often one-handed and under time pressure.
- **Task:** Enter or review project details, dismiss the keyboard, and reach the conversion actions without losing state.
- **Feel:** Predictable and native; the control quietly removes the obstruction.
- **Domain:** Lead handoff, project creation, field form, keyboard, commit.
- **Color world:** Existing black canvas and monochrome OPS controls; no new color.
- **Signature:** The canonical uppercase OPS `DONE` action in the native keyboard toolbar.
- **Rejected defaults:** Hiding the keyboard only by scrolling or tapping outside is undiscoverable; adding another sheet button confuses keyboard dismissal with conversion.
- **Palette:** Existing `OPSStyle.Colors.primaryText`.
- **Depth:** Native SwiftUI keyboard-toolbar surface.
- **Typography:** Existing `OPSStyle.Typography.bodyBold`.
- **Spacing:** Native keyboard-toolbar placement; no new spacing value.

### Task 1: Add the failing presentation-boundary regression

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`

**Files:**
- Modify: `OPSTests/IOSBugReportRegressionTests.swift`

**Design tokens:** None added.

**Step 1: Write the focused test**

Instantiate the real `ConvertToProjectSheet` with a fixture opportunity, evaluate its body composition, and assert that the root composition includes a SwiftUI toolbar modifier. The mutation caught is removal of the conversion sheet's own keyboard toolbar at the sheet boundary.

**Step 2: Run only the new test and verify RED**

Run:

```bash
xcodebuild test \
  -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:OPSTests/IOSBugReportRegressionTests/testConvertProjectSheetOwnsKeyboardToolbarInsidePresentationBoundary \
  -derivedDataPath .derived-data-convert-keyboard \
  -clonedSourcePackagesDirPath .spm-local
```

Expected: the assertion fails because the current conversion sheet root has no toolbar modifier.

### Task 2: Attach the shared keyboard toolbar

**Skills:** `custom-skills:executing-plans`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift:160-203`

**Design tokens:** Existing `OPSStyle.Typography.bodyBold` and `OPSStyle.Colors.primaryText` through `opsKeyboardDoneToolbar()`; no new value.

**Step 1: Implement the minimal fix**

Apply `.opsKeyboardDoneToolbar()` to the root view after the existing sheet behavior modifiers. Do not change input components, footer actions, focus state, conversion logic, copy, or motion.

**Step 2: Run the same focused test and verify GREEN**

Expected: the selected test passes with zero failures.

### Task 3: Audit and land

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/05_DESIGN_SYSTEM.md`

**Step 1: Audit the diff**

Confirm the production diff contains only the shared modifier call and introduces no hardcoded visual value or duplicate user-facing copy.

**Step 2: Update the Bible**

Record that form sheets presented beyond the app root must attach the canonical keyboard toolbar inside their own presentation boundary, with `ConvertToProjectSheet` as the corrected Leads example.

**Step 3: Commit locally**

Stage only the conversion sheet, focused regression test, design spec, and plan. Commit the Bible separately in its own repository. Cherry-pick the detached iOS commit onto local `ops-ios/main`, preserving unrelated dirty state. Do not push.

**Step 4: Resolve only the claimed report**

Guard the live update by exact bug ID, `status = 'in_progress'`, and `assigned_to = 'Codex'`. Store the landed commit, require human review, read the row back, and stop for manual verification.
