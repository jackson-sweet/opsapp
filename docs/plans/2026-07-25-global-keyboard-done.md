# Global Keyboard Done Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Guarantee one canonical `DONE` action on every software keyboard in OPS iOS.

**Architecture:** Install a UIKit input-accessory coordinator once from `AppDelegate`, at the common `UITextField` / `UITextView` boundary beneath SwiftUI presentations. Remove generic per-view keyboard toolbars and preserve their local edit behavior at focus-loss boundaries.

**Tech Stack:** Swift 5, SwiftUI, UIKit, NotificationCenter, XCTest.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

---

## Intent checkpoint

- **Human:** A field operator entering data one-handed in glare and distraction.
- **Task:** Leave any keyboard and continue the current screen without lost data.
- **Feel:** Native, predictable, and invisible until needed.
- **Domain:** Field entry, forms, keyboard focus, continuity, confidence.
- **Color world:** Existing black OPS canvas, system keyboard surface, primary
  text, steel-blue reserved elsewhere for primary CTA/focus only.
- **Signature:** One trailing uppercase OPS `DONE` action everywhere.
- **Rejected defaults:** Return-key dependence, tap-outside-only dismissal, and
  screen-by-screen toolbar opt-in.
- **Palette:** Existing `OPSStyle.Colors.primaryText`.
- **Depth:** Native UIKit input-accessory surface.
- **Typography:** Existing Cake Mono button-label role through a UIKit token.
- **Spacing:** Native 44-point keyboard accessory row; no local spacing value.

### Task 1: Prove the missing global behavior

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`

**Files:**
- Modify: `OPSTests/IOSBugReportRegressionTests.swift`

**Design tokens:** No new visual value.

**Step 1: Write the focused tests**

Create real `UITextField` and `UITextView` instances and assert:

1. editing activation automatically attaches a canonical accessory;
2. repeated activation retains exactly one canonical accessory;
3. invoking its `DONE` action resigns a real first responder.

Replace the old Convert-to-Project body-composition assertion, because a
screen-owned SwiftUI toolbar is no longer the correct architecture.

**Step 2: Run only the new tests and verify RED**

```bash
xcodebuild test \
  -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:OPSTests/IOSBugReportRegressionTests \
  -derivedDataPath .derived-data-convert-keyboard \
  -clonedSourcePackagesDirPath .spm-local
```

Expected: compilation or assertions fail because no app-wide input-accessory
coordinator exists.

### Task 2: Install the global coordinator

**Skills:** `custom-skills:executing-plans`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Create: `OPS/Styles/Components/OPSKeyboardDoneAccessory.swift`
- Modify: `OPS/AppDelegate.swift`
- Modify: `OPS/Styles/OPSStyle.swift`

**Design tokens:** `OPSStyle.Colors.primaryText`,
`OPSStyle.Typography.uiButtonLabel`, `OPSStyle.Layout.touchTargetMin`.

**Step 1: Implement the accessory**

Create a canonical UIKit toolbar with a flexible spacer and trailing `DONE`
button. Give it stable internal identity so repeated activation is idempotent.
Retain the owning input weakly and resign that exact responder when the action
fires, so dismissal remains deterministic across multiple windows.

**Step 2: Implement the coordinator**

Observe `UITextField.textDidBeginEditingNotification` and
`UITextView.textDidBeginEditingNotification`, install the accessory on the
activated control, and reload input views only when installation changes.
Make `start()` idempotent.

**Step 3: Start the coordinator**

Call the coordinator once during app launch before returning from
`application(_:didFinishLaunchingWithOptions:)`.

### Task 3: Remove duplicate local toolbars and preserve form semantics

**Skills:** `custom-skills:executing-plans`, `custom-skills:mobile-ux-design`

**Files:**
- Modify: `OPS/Styles/Components/StandardSheetToolbar.swift`
- Modify: `OPS/Views/MainTabView.swift`
- Modify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift`
- Modify: `OPS/Onboarding/Screens/EmergencyContactScreen.swift`
- Modify: `OPS/Onboarding/Screens/CompanySetupScreen.swift`
- Modify: `OPS/Onboarding/Screens/ProfileScreen.swift`
- Modify: `OPS/Views/Inventory/QuantityAdjustmentSheet.swift`
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift`
- Modify: `OPS/Views/JobBoard/ProjectFormSheet.swift`
- Modify: `OPS/Views/JobBoard/TaskFormSheet.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureView.swift`

**Design tokens:** No new visual value.

**Step 1: Remove generic local keyboard toolbars**

Delete `.opsKeyboardDoneToolbar()` and every
`ToolbarItemGroup(placement: .keyboard)` generic dismissal implementation.

**Step 2: Preserve focus-loss behavior**

- Finish quantity edit mode when its field loses focus.
- Commit task-note drafts when note focus ends; preserve explicit cancel.
- Autosave the site-visit note when note focus ends.

### Task 4: Verify and land

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/05_DESIGN_SYSTEM.md`

**Step 1: Run focused GREEN verification**

Run the same focused XCTest class using the existing worktree cache. Confirm
zero test failures.

**Step 2: Audit the repository invariant**

Confirm production sources contain no
`ToolbarItemGroup(placement: .keyboard)` or `.opsKeyboardDoneToolbar()` call.
Confirm the global coordinator handles both UIKit text-input primitives.

**Step 3: Audit design-system compliance**

Confirm the new accessory uses only OPS tokens for text color, typography, and
touch sizing, with no hardcoded visual value in the component.

**Step 4: Update the Bible**

Replace the screen-boundary guidance with the app-lifetime UIKit
input-accessory guarantee and document that local generic keyboard toolbars are
forbidden.

**Step 5: Commit and land locally**

Stage only the keyboard policy, regressions, design spec, and plan. Commit the
Bible separately. Cherry-pick the detached iOS commit onto local `main`,
preserving unrelated dirty state. Do not push.

**Step 6: Resolve the exact live report**

Guard the update by bug ID, `status = 'in_progress'`, and
`assigned_to = 'Codex'`. Store the landed commit, require human review, read the
row back, and stop for manual verification.
