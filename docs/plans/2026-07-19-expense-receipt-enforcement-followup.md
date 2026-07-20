# Expense Receipt Enforcement Follow-up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task by task.

**Goal:** Make company receipt and project rules fail closed, preserve every captured receipt through retry, and prevent stale exception metadata or batch totals after an expense is edited.

**Architecture:** Keep policy resolution and submission decisions in small testable domain types. Upload a receipt to a server-derived, user-owned deterministic object key before any database write. Commit the complete expense snapshot through one authenticated, idempotent Postgres RPC with strict validation, compare-and-swap protection, allocation replacement, placement, and envelope-total recalculation in one transaction. Retain the exact command and local image only for an ambiguous response; a definitive rejection unlocks correction and cleans the staged objects.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Supabase Swift, PostgreSQL/PLpgSQL, Next.js upload routes, Vitest.

**Design System:** OPSStyle only; no hardcoded styling.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `ops-copywriter:ops-copywriter`, `custom-skills:mobile-ux-design`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`.

---

## Task 1: Lock the missing rules with failing tests

**Files:**
- Modify: `OPSTests/ExpenseSubmissionGateTests.swift`
- Modify: `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift`
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift`

1. Add tests proving an unresolved company policy blocks submission but never blocks a draft save.
2. Add tests proving absent settings resolve to the database defaults: receipt required, project optional.
3. Add encoding tests proving receipt, project-exception, and batch fields emit JSON `null` when cleared.
4. Add a pure completion decision test proving any required persistence stage keeps the sheet open for retry.
5. Run only `ExpenseSubmissionGateTests` and record the expected RED result before production changes.

## Task 2: Resolve policy before allowing submission

**Files:**
- Modify: `OPS/ViewModels/ExpenseViewModel.swift`
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift`
- Modify: `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift`

1. Add a settings-load state and a defaulted `ExpenseSubmissionRequirements` value.
2. Reset policy state when the company changes and make settings loading return a result.
3. Preload policy on form appearance, retry it at save time, and block only submission when policy cannot be verified.
4. Present a terse inline connection error and leave the form open.
5. Run the focused tests and confirm the policy tests are GREEN.

## Task 3: Make expense persistence atomic and idempotent

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/ExpenseDTOs.swift`
- Modify: `OPS/Network/Supabase/Repositories/ExpenseRepository.swift`
- Modify: `OPS/ViewModels/ExpenseViewModel.swift`
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift`

1. Encode one full `ExpenseAtomicSaveCommand`, including explicit nulls, a stable request ID, and expected status/`updated_at` CAS values.
2. Add `save_expense_atomic` with strict JSON/type/business validation, permissions matching live RLS, policy defaults, and a hash-only 90-day idempotency ledger.
3. Replace allocations, submit/refile placement, and source/destination total recalculation inside one transaction; fail the whole command on any stage error.
4. Make `expenses.updated_at` non-null and strictly monotonic for every insert/update, including legacy allocation-only changes; lock allocation rows before the parent to preserve shipped-client lock order.
5. Rebuild every success/replay response from the current live row, reject deleted/completed replay resurrection, and reconcile a lost response by authoritative readback.
6. Run focused tests and live rollback scenarios covering create, replay, stale CAS, explicit clears, policy rejection, malformed payloads, rollback, and totals.

## Task 4: Make receipt objects retry-safe and user-owned

**Files:**
- Modify: `OPS/Network/PresignedURLUploadService.swift`
- Modify: `ops-web/src/app/api/uploads/presign/route.ts`
- Modify: `ops-web/src/app/api/uploads/delete/route.ts`
- Modify: `ops-web/tests/integration/uploads-presign-s3.test.ts`
- Add: `ops-web/tests/integration/uploads-delete.test.ts`

1. Extend presign with `purpose=expense_receipt`, validated expense/upload UUIDs, and a `full|thumbnail` variant.
2. Derive `expenses/{companyId}/{userId}/{expenseId}/{uploadId}-{variant}.jpg` server-side; ignore client folder/filename for this purpose and use Supabase `upsert` on rollback storage.
3. Require the authenticated OPS user segment when deleting deterministic receipts. For legacy keys, resolve the exact receipt/profile/logo/lead/project resource and enforce its real ownership or edit permission; deny unknown namespaces instead of falling back to a company-path match.
4. Retry an ambiguous thumbnail PUT once against the exact key, then best-effort clean it before falling back to the full image.
5. Prove same-input/same-key, tuple separation, malformed rejection, cross-user isolation, legacy randomness, exact delete keys, and repeated delete.

## Task 5: Make the recovery state visible and safe

**Files:**
- Modify: `OPS/Views/Expenses/ExpenseFormSheet.swift`
- Modify: `OPS/Styles/Components/Feedback.swift`

1. Show the persisted receipt when editing, and label a new capture as a replacement.
2. Show the existing no-receipt reason/note and provide a direct way to change it.
3. On receipt failure, keep the sheet and image open, show `RETRY RECEIPT`, and explain that the user's changes are still present.
4. On an ambiguous database/transport result, lock the exact intent and show `RETRY SAVE`; on a definitive rejection, clear the retry command, unlock correction, clean staged objects, and show an actionable reason.
5. Disable cancel and interactive dismissal while saving so an in-flight submission cannot finish behind a dismissed sheet.
6. Audit all new UI against `OPSStyle`, outdoor readability, touch targets, VoiceOver labels, and Dynamic Type.

## Task 6: Prove and document the completed bug

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md`
- Modify: Supabase `public.bug_reports` row `07b7a1b3-d8bc-4446-a292-4bb21855737a`

1. Run the focused receipt suite and related expense tests.
2. Run the OPS-Web presign/delete integration suites and typecheck.
3. Build for a generic iOS device with an isolated DerivedData path.
4. Run independent, read-only Swift, web, and SQL reviews and fix every material finding.
5. Apply the migration through Supabase, run rollback-wrapped live scenarios, verify function grants/triggers, and run security/performance advisors.
6. Update the Financial System/Data Architecture Bible sections with the atomic save and user-owned storage contracts.
7. Commit isolated iOS, web-main, and Bible changes without pushing.
8. Keep the live bug `in_progress`, record exact commits/proof, and require Jackson's human verification.
