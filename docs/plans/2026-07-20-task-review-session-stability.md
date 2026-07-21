# Task Review Session Stability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make every Task Review swipe immediate and deterministic while keeping the session total and card order stable as live task eligibility changes underneath the sheet.

**Architecture:** Capture the ordered review tasks once when either review sheet opens and keep ID-based progress inside a small testable session value. The shared swipe stack consumes that frozen session, follows the finger without implicit animation, and advances from the OPS 150 ms commit animation's completion callback instead of a timer. Project-photo disk reads, decode, and downsampling run outside the main UI actor. Parent Job Board and FAB counts remain live, so the outstanding badge reflects completed, cancelled, assigned, or rescheduled tasks without rewriting an open stack.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Xcode 26 / iOS 17.6 deployment target

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; production tokens live in `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `custom-skills:ui-ux-pro-max`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `custom-skills:audit-design-system`, `custom-skills:wizard-audit`, `superpowers:verification-before-completion`

---

### Task 1: Lock the regression down with session-state tests

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`

**Files:**
- Create: `OPSTests/Views/Review/TaskReviewSessionTests.swift`
- Create after the RED proof: `OPS/Views/Review/TaskReviewSession.swift`

**Design tokens:** N/A — pure state logic only.

**Step 1: Write the failing tests**

Cover these contracts:

- A session opened with A/B/C retains A/B/C in the same order after the live eligible array becomes B/C.
- Reviewing A exactly once does not skip B and does not complete the session early.
- Duplicate completion callbacks for the same task are idempotent.
- An unknown task ID cannot advance progress.
- The session completes only after every task in the opening snapshot has been reviewed.

**Step 2: Run tests to verify RED**

Run:

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .dd-task-review-red -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/TaskReviewSessionTests
```

Expected: FAIL because `TaskReviewSession` does not exist.

**Step 3: Implement only the session value needed by the tests**

Create an internal `TaskReviewSession` that snapshots unique `ProjectTask` references in source order, retains the allowed ID set, records reviewed IDs idempotently, and exposes fixed total, reviewed, remaining, and completion state.

**Step 4: Run tests to verify GREEN**

Run the same focused command. Expected: all `TaskReviewSessionTests` pass.

### Task 2: Make the open review sheet consume the frozen session

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:wizard-audit`

**Files:**
- Modify: `OPS/Views/Review/TaskCompletionReviewView.swift`
- Test: `OPSTests/Views/Review/TaskReviewSessionTests.swift`

**Design tokens:** Preserve existing `OPSStyle.Colors`, `OPSStyle.Typography`, and `OPSStyle.Layout` usage; introduce no raw visual values.

**Step 1: Add a failing progress/interactive-dismiss regression if implementation exposes a gap**

Verify that finishing a task and then receiving a duplicate sheet-dismiss callback still records one review, and that the fixed total never follows a shrunken live queue.

**Step 2: Replace the live `tasks` input as body state**

Initialize `@State` with `TaskReviewSession(tasks:)` when the sheet first appears. Drive the stack, header total, reviewed counter, wizard prerequisite count, empty state, and completion decision exclusively from that snapshot.

**Step 3: Centralize exactly-once review completion**

Route right/left swipes, reschedule success/cancel/interactive dismissal, and cancel-alert outcomes through one idempotent `finishReview` function. Preserve existing writes, permissions, notifications, retry toasts, and haptics.

**Step 4: Run the focused session tests**

Expected: PASS.

### Task 3: Remove swipe lag and timer/identity races

**Skills:** `animation-studio:animation-architect`, `animation-studio:ios-animations`, `custom-skills:ops-design`

**Files:**
- Modify: `OPS/Views/Review/TaskReviewCardStack.swift`
- Test: `OPSTests/Views/Review/TaskReviewSessionTests.swift`

**Design tokens:** `OPSStyle.Animation.hover` for the 150 ms swipe commit/snap, `OPSStyle.Animation.panel` for the 200 ms stack shift. No spring, bounce, or hardcoded timing.

**Step 1: Preserve direct manipulation**

Remove the implicit animation bound to `dragOffset`; live drag updates must follow the finger directly.

**Step 2: Replace the fixed dispatch delay**

Capture the outgoing task before animating, run the fly-away with `OPSStyle.Animation.hover`, and advance `currentIndex` from the animation completion callback. Keep the existing commit lock until that callback completes.

**Step 3: Keep the stack transition deterministic**

Use `OPSStyle.Animation.panel` for the next-card shift and reset transient drag state without queuing a second animation.

**Step 4: Run focused tests and build**

Run the session tests, then:

```bash
xcodebuild -quiet -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath .dd-task-review-build -clonedSourcePackagesDirPath .spm-local build
```

Expected: tests pass and `BUILD SUCCEEDED`.

### Task 4: Stabilize the shared unscheduled review and photo pipeline

**Skills:** `custom-skills:mobile-ux-design`, `animation-studio:ios-animations`, `superpowers:systematic-debugging`

**Files:**
- Modify: `OPS/Views/Review/UnscheduledTaskReviewView.swift`
- Modify: `OPS/Views/Review/TaskSwipeCardView.swift`
- Test: `OPSTests/Views/Review/TaskReviewSessionTests.swift`
- Test: `OPSTests/ImageDownsamplerTests.swift`

**Design tokens:** Reuse the same session invariants and OPS motion tokens. Reduce Motion replaces committed fly-away/stack transforms with opacity.

**Step 1: Freeze the second shared review queue**

Drive unscheduled/unassigned cards, totals, hints, and exactly-once completion from `TaskReviewSession` so live assignment/schedule/status updates cannot skip the next card.

**Step 2: Remove photo work from the main UI actor**

Keep model snapshot and UI publication on MainActor, but move file reads, decode, and 2048 px downsampling into cancellable detached tasks before publishing immutable images back to the card.

**Step 3: Verify focused state and image regressions**

Run `TaskReviewSessionTests`, `JobBoardListBehaviorTests`, and `ImageDownsamplerTests` together. Expected: 16 tests pass.

### Task 5: Audit, document, and close the two live reports

**Skills:** `custom-skills:audit-design-system`, `custom-skills:wizard-audit`, `superpowers:verification-before-completion`, `supabase:supabase`

**Files:**
- Modify if behavior documentation needs correction: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

**Design tokens:** Verify modified UI code contains no new hardcoded color, font, spacing, radius, or animation values.

**Step 1: Run focused regression tests plus device build**

Record exact passing counts and build result.

**Step 2: Review the final diff and wizard flow**

Confirm both review queues remain stable, progress is exactly once, direct finger tracking and 150 ms tokenized commit motion are preserved, Reduce Motion removes transform animation, photo decoding is off-main, interactive reschedule dismissal is idempotent, and parent badges remain live.

**Step 3: Commit atomically**

Stage only the Task Review implementation, tests, and any directly required bible note. Commit with `fix(review): stabilize task review swipe sessions`.

**Step 4: Update Supabase**

Mark primary bug `3e71f5d8-e197-433f-a978-ef374c433c1b` fixed with commit/test/build evidence. Mark `9bbec4b7-d6ec-46ce-826e-10a34a07bd25` as the proven duplicate resolved by the same commit.

**Step 5: Stop for Jackson verification**

Do not start another bug.
