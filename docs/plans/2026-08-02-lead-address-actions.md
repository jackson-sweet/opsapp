# Lead Address Actions Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make the address on an assigned-user lead card open directions on tap and copy the address on long press without also expanding the card.

**Architecture:** Keep the existing `DaySheetLeadRow.openRoute()` destination contract as the single navigation path. Add one exclusive address gesture that resolves to a small typed action, so route and copy cannot both fire, and keep each effect independently testable.

**Tech Stack:** SwiftUI, UIKit pasteboard/application boundaries, XCTest, Xcode 26.5.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`.

**Required Skills:** `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

---

### Task 1: Prove the missing address-action contract

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/Views/DaySheetLeadAddressActionTests.swift`

**Steps:**
1. Add focused tests proving route dispatch never copies and copy dispatch never routes.
2. Run only those tests and confirm RED because the typed production action does not exist.

### Task 2: Wire the smallest interaction fix

**Skills:** `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/Views/Leads/DaySheet/DaySheetLeadRow.swift`
- Modify: `OPS/Styles/Components/Feedback.swift`

**Design tokens:** `OPSStyle.Layout.touchTargetMin`, `OPSStyle.Animation.longPressHold`, existing lead-row typography and color tokens.

**Steps:**
1. Add the typed route/copy dispatcher.
2. Replace the inert address text with the same visual text and a 44pt overlay interaction target that preserves compact row geometry.
3. Attach one exclusive long-press-before-tap gesture; route through `openRoute()` and copy through `UIPasteboard` plus the existing toast system.
4. Add concise VoiceOver route/copy actions.
5. Run the focused tests and confirm GREEN.

### Task 3: Verify and integrate safely

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`

**Files:**
- Verify only the files above and this plan.

**Steps:**
1. Run the focused test target serially with worktree-local package and DerivedData paths.
2. Run a generic-device OPS build and `git diff --check`.
3. Audit token, touch-target, copy, gesture-conflict, and accessibility compliance.
4. Commit task-owned files with bug `a093d9cc` in the message.
5. Merge only if local `main` can be advanced without touching its unrelated dirty checkout; otherwise preserve the verified branch and record the exact blocker.
