# Lead Card Top-Left Status Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make the lead stage the literal top-left scan anchor on every `LeadTriageCard` while preserving value, menu behavior, terminal behavior, and the card's remaining information.

**Architecture:** Introduce a tiny ordered header-row model and render the card header from that sequence. This makes the approved hierarchy directly regression-testable: status/value first, contact second, job third. Remove the stage tag from the lower metadata row, which retains stage progress and source.

**Tech Stack:** Swift 5, SwiftUI, XCTest, existing `LeadStatusMenu`, `StageTag`, `OPSStyle`, and the existing hosted snapshot harness.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` plus `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; implementation tokens remain in `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

---

## Intent checkpoint

- **Human:** A trades owner scanning leads quickly between field work.
- **Task:** Identify pipeline stage before deciding which lead needs attention.
- **Feel:** Tactical and immediate; hierarchy does the work without extra decoration.
- **Domain:** Pipeline, stage, chase state, handoff, quote, field follow-up.
- **Color world:** Black canvas, glass/hairline neutrals, steel action accent, olive/tan/rose semantic stage tones.
- **Signature:** The text-labelled earth-tone `StageTag` paired with the six-segment pipeline track.
- **Rejected defaults:** A conventional trailing badge hides state; an overlay makes the card fragile; an inline badge/name row crowds real customer names.
- **Palette:** Existing `OPSStyle.Colors` only.
- **Depth:** Existing `.commandCard()` border/glass treatment only.
- **Typography:** Existing `StageTag`, `bodyBold`, and mono value roles only.
- **Spacing:** Existing `OPSStyle.Layout.spacing*` tokens only.

### Task 1: Add the failing header-order regression

**Skills:** `superpowers:test-driven-development`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`

**Files:**
- Create: `OPSTests/Views/LeadTriageCardHeaderLayoutTests.swift`
- Test: `OPSTests/Views/MoneyLeadsRedesignSnapshotTests.swift`

**Design tokens:** No styling in this task.

**Step 1: Write the focused test**

Create a test that expects:

```swift
XCTAssertEqual(
    LeadTriageCardHeaderLayout.rows,
    [.statusAndValue, .contact, .job]
)
```

The production card will render those exact rows through `ForEach`, so this assertion owns the real header sequence rather than a parallel description.

**Step 2: Run only the new test and verify RED**

Run:

```bash
xcodebuild test \
  -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:OPSTests/LeadTriageCardHeaderLayoutTests \
  -derivedDataPath .derived-data-lead-card-status \
  -clonedSourcePackagesDirPath .spm-local
```

Expected: compilation fails because `LeadTriageCardHeaderLayout` does not yet exist.

### Task 2: Render the approved hierarchy

**Skills:** `custom-skills:executing-plans`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`

**Files:**
- Modify: `OPS/Views/Leads/Triage/LeadTriageCard.swift:1-450`

**Design tokens:** `OPSStyle.Layout.spacing2_5`; existing `StageTag`, `LeadStatusMenu`, `OPSStyle.Typography.bodyBold`, `OPSStyle.Colors.text`, and existing mono value treatment. No new value is permitted.

**Step 1: Add the ordered header model**

Add an internal hashable row enum and canonical sequence:

```swift
enum LeadTriageCardHeaderRow: Hashable {
    case statusAndValue
    case contact
    case job
}

enum LeadTriageCardHeaderLayout {
    static let rows: [LeadTriageCardHeaderRow] = [
        .statusAndValue,
        .contact,
        .job,
    ]
}
```

**Step 2: Render that sequence**

Replace the current contact/value plus optional job block with:

```swift
ForEach(LeadTriageCardHeaderLayout.rows, id: \.self) { row in
    headerRow(row)
}
```

The `statusAndValue` row hosts the existing interactive `LeadStatusMenu` for open leads and plain `StageTag` for terminal leads, then the existing value on the trailing edge. `contact` renders the full-width contact name. `job` renders only when `jobLine` exists and keeps its existing typography/truncation.

**Step 3: Simplify the lower metadata row**

Remove the status/menu branch from `metaRow`. Keep only the six-segment stage track, elastic space, and optional source.

**Step 4: Preserve behavior**

Do not change menu permissions, callbacks, haptics, swipe mechanics, card tap handling, accessibility labels, terminal outcome behavior, copy, or motion.

### Task 3: Verify behavior and visual output

**Skills:** `superpowers:verification-before-completion`, `custom-skills:ops-design`, `custom-skills:audit-design-system`

**Files:**
- Test: `OPSTests/Views/LeadTriageCardHeaderLayoutTests.swift`
- Test: `OPSTests/Views/MoneyLeadsRedesignSnapshotTests.swift`

**Step 1: Run the focused regression and the two existing card snapshots together**

Run:

```bash
xcodebuild test \
  -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:OPSTests/LeadTriageCardHeaderLayoutTests \
  -only-testing:OPSTests/MoneyLeadsRedesignSnapshotTests/testRenderLeadTriageCards \
  -only-testing:OPSTests/MoneyLeadsRedesignSnapshotTests/testRenderLeadTriageCardsTerminal \
  -derivedDataPath .derived-data-lead-card-status \
  -clonedSourcePackagesDirPath .spm-local
```

Expected: all selected tests pass and both PNG attachments render.

**Step 2: Inspect the attachments**

Confirm:

- stage badge is the first visible element at top-left;
- value remains top-right;
- contact and job text no longer compete with the badge;
- stage progress and source remain in the lower metadata row;
- open and terminal cards use the same hierarchy;
- no clipping or horizontal overflow appears at 393pt.

**Step 3: Audit the diff**

Scan added lines for hardcoded colors, fonts, spacing, radius, border width, or animation values. Expected: zero new hardcoded visual values.

### Task 4: Document and land the correction

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/05_DESIGN_SYSTEM.md`

**Step 1: Update the Bible**

Record that the current iOS `LeadTriageCard` uses stage/value as its header row, followed by contact/job, while the lower metadata row contains stage progress and source.

**Step 2: Commit the code**

Stage only:

```text
OPS/Views/Leads/Triage/LeadTriageCard.swift
OPSTests/Views/LeadTriageCardHeaderLayoutTests.swift
docs/plans/2026-07-25-lead-card-top-left-status.md
docs/superpowers/specs/2026-07-25-lead-card-top-left-status-design.md
```

Commit:

```bash
git commit -m "fix(leads): move card status to top left"
```

**Step 3: Land on local main**

Cherry-pick the detached implementation commit into local `ops-ios/main`, preserving the unrelated `OPS.xcodeproj/project.pbxproj` edit. Do not push.

**Step 4: Resolve only the claimed bug**

Guard the update by exact ID, `status = 'in_progress'`, and `assigned_to = 'Codex'`. Store the landed iOS commit, require human review, read the row back, and stop for Jackson's verification.
