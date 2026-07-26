# Task Detail Description Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Make the expanded Project Details task sheet reveal a complete, permanent description area.

**Architecture:** Keep the existing scrollable medium/large sheet. Normalize the optional `task_notes` value through a small presentation policy, remove the truncated header preview, and render one tokenized glass description card between task metadata and actions.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SwiftData model fixtures

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

---

### Task 1: Lock the description contract with a failing focused test

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/Views/TaskDetailPopupSheetTests.swift`
- Modify: none

**Design tokens:** N/A

**Steps:**

1. Write tests for a `TaskDetailDescriptionPresentation` contract:
   - meaningful prose is trimmed and preserved;
   - nil, empty, and whitespace-only prose becomes `—`.
2. Add a rendering harness that hosts the real `TaskDetailPopupSheet` at an expanded phone height with long prose and with no prose.
3. Run:
   `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-task-detail-description-derived -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/TaskDetailPopupSheetTests`
4. Confirm the focused target fails because `TaskDetailDescriptionPresentation` does not exist.

### Task 2: Add the progressive description card

**Skills:** `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/Views/Components/Task/TaskDetailPopupSheet.swift`

**Design tokens:** `OPSStyle.Typography.smallCaption`, `OPSStyle.Typography.body`, `OPSStyle.Colors.primaryText`, `OPSStyle.Colors.tertiaryText`, `OPSStyle.Layout.spacing2`, `OPSStyle.Layout.spacing3`, `.glassSurface()`

**Steps:**

1. Add the minimal presentation policy required by the failing tests.
2. Remove the optional three-line header preview.
3. Add an always-present `DESCRIPTION` card after `infoCard` and before `actionButtons`.
4. Render the full normalized prose without a line limit; render `—` in the tertiary role when empty.
5. Give the area a stable accessibility identifier for UI verification.

### Task 3: Verify behavior and visual output once

**Skills:** `superpowers:verification-before-completion`, `custom-skills:audit-design-system`

**Files:**
- Inspect: `OPS/Views/Components/Task/TaskDetailPopupSheet.swift`
- Inspect: generated PNGs under the test process temporary directory

**Steps:**

1. Re-run the exact focused test command once.
2. Confirm all focused tests pass with zero failures.
3. Inspect both rendered PNGs and confirm:
   - the description card is present;
   - long text is not truncated;
   - empty text renders `—`;
   - actions remain below the description;
   - the expanded layout has no overlap or horizontal clipping.
4. Scan the production diff for hardcoded colors, spacing, radii, and fonts.

### Task 4: Update the source of truth and land atomically

**Skills:** `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

**Steps:**

1. Document the Project Details task-sheet progressive description behavior in the Bible.
2. Commit the iOS implementation, focused tests, design, and plan as one atomic bug-fix commit.
3. Merge locally into `main` after checking that the primary checkout still contains only the unrelated Xcode project-file edit.
4. Re-run the focused test only if merge provenance changed the tested source.
5. Update bug `381a1e58-54e2-4a31-8dbf-a135917f7910` to `resolved`, attach the exact local-main commit, require human review, and read the row back.
