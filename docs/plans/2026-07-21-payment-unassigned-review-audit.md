# Payment and Unassigned Review End-to-End Audit Plan

> **For implementation:** Use `custom-skills:executing-plans` task by task. Keep both queues deterministic, every action truthful, and every failed write recoverable.

**Goal:** Bring the remaining Payment Review and Unassigned Task Review swipe flows to the same deterministic, production-safe standard as Task Completion Review.

**Architecture:** Freeze each opened review into a de-duplicated ID-based session. Separate swipe presentation from action policy so eligibility, permissions, success, retry, and progress are testable. Reuse one off-main, downsampled project-photo pipeline and one tokenized card-stack interaction model. Drive every launch badge from the same canonical query as the sheet. Financial actions must resolve eligible invoices before they appear and must only report success after the authoritative write or approval-queue request succeeds.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Supabase/Postgres, Next.js only where the existing payment-reminder approval service needs a narrow authenticated bridge.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`.

---

### Task 1: Lock the review contracts in failing tests

**Files:**
- Create: `OPSTests/Views/Review/ProjectReviewSessionTests.swift`
- Create: `OPSTests/Views/Review/ProjectPaymentReviewPolicyTests.swift`
- Modify: `OPSTests/Views/Review/AutoScheduleFailureRecoveryTests.swift`

Cover de-duplication and overdue-first ordering, fixed totals under live mutation, exactly-once progress, unique badge counts, invoice/action eligibility, permission-correct directions, and recovery outcomes for cancel, assignment, and scheduling failures. Run the focused suite and retain the RED proof before production edits.

### Task 2: Stabilize Payment Review presentation

**Files:**
- Create: `OPS/Views/Review/ProjectReviewSession.swift`
- Modify: `OPS/Views/Review/ProjectPaymentReviewView.swift`
- Modify: `OPS/Views/Review/ProjectReviewCardStack.swift`
- Modify: `OPS/Views/Review/SwipeCardView.swift`

Snapshot one unique queue with overdue projects first and remaining completed projects second. Route progress through an idempotent session. Make drag follow the finger directly, lock duplicate commits, capture the outgoing project before motion, use OPS motion tokens, and remove transforms under Reduce Motion. Move file access, decode, and downsampling off the main actor.

### Task 3: Make payment actions authoritative

**Files:**
- Modify: `OPS/Views/Review/ProjectPaymentReviewView.swift`
- Modify only if required by the existing approval architecture: the narrow authenticated payment-reminder endpoint/service in `ops-web`
- Add only if required for transactionality: a focused Supabase migration/RPC

Close through the canonical project write and expose a persistent retry on failure. Offer reminders only for a real overdue outstanding invoice and queue the existing approval-first reminder action; never claim that an email was sent. Offer write-off only with invoice-edit authority and an outstanding balance; make project close plus invoice write-off atomic, and advance only after success or an explicit operator skip.

### Task 4: Preserve recovery in Unassigned Task Review

**Files:**
- Modify: `OPS/Views/Review/UnscheduledTaskReviewView.swift`
- Modify: `OPSTests/Views/Review/AutoScheduleFailureRecoveryTests.swift`

Keep the shared stable TaskReview session/card/image infrastructure. Do not swallow assignment, auto-schedule, manual-schedule, completion, or cancellation failures. Each failure keeps an explicit retry or manual recovery path; each successful assignment-only outcome is acknowledged accurately; progress remains exactly once.

### Task 5: Align launch surfaces, permissions, and refresh

**Files:**
- Modify the Job Board header/FAB/review-threshold query owners identified by the audit
- Modify the canonical project update signal if required

Build the same unique project queue for the sheet, badge, rail, and threshold. Require project edit for close, invoice view for financial context, and invoice edit for write-off. Emit the shared review-refresh signal after local project mutations so counts update without waiting for realtime.

### Task 6: Verify and document

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

Run focused tests, relevant regression suites, static design/accessibility checks, and a clean generic-device build from isolated package and DerivedData paths. Independently review the final diff for false-success, double-commit, count drift, permission mismatch, and Reduce Motion regressions. Commit atomically, preserve unrelated work, and stop for manual verification.
