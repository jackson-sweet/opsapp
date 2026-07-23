# Lead One-Tap Follow-Up Implementation Plan

> **For implementation:** Use `custom-skills:executing-plans` and complete each task test-first.

**Goal:** Ship a true one-tap, provider-threaded lead follow-up that advances lead ownership only after confirmed delivery.

**Architecture:** A new authenticated OPS Web route resolves every transport fact server-side, then reuses the durable email-send intent pipeline. Reconciliation invokes an idempotent Supabase follow-up outcome transition. OPS iOS exposes that command through the existing chase strip and applies only the canonical opportunity returned by the server.

**Stack:** SwiftUI / Firebase Auth / URLSession, Next.js 15 / TypeScript / Vitest, Supabase Postgres.

---

### Task 1: Lock the database outcome contract

**Files:**
- Add: `ops-web/supabase/migrations/20260723233000_operator_one_tap_lead_follow_up.sql`
- Modify: `ops-web/src/lib/types/database.types.ts`
- Add: `ops-web/tests/unit/supabase/operator-one-tap-lead-follow-up-migration.test.ts`

1. Add a failing migration-contract test for the new intent receipt fields, service-role-only RPC, template-default upgrade, lifecycle counter update, handled/comeback update, notification dedupe, and system-handoff exclusion.
2. Run the focused test and confirm it fails because the migration is absent.
3. Add the additive migration and database type entries.
4. Run the focused test and `git diff --check`.
5. Commit the database contract.

### Task 2: Integrate follow-up outcome with send reconciliation

**Files:**
- Modify: `ops-web/src/lib/api/services/email-send-reconciliation-service.ts`
- Modify: `ops-web/src/lib/api/services/email-send-intent-service.ts`
- Modify: `ops-web/tests/unit/email/email-send-intent-service.test.ts`
- Modify: `ops-web/tests/unit/email/email-send-reconciliation-service.test.ts`

1. Add failing tests proving a template follow-up calls the idempotent outcome RPC and returns the comeback date, while an ordinary send does not.
2. Run the focused tests and confirm the new assertions fail.
3. Add typed intent fields and the outcome RPC call after correspondence persistence.
4. Return the authoritative opportunity and comeback metadata.
5. Run the focused tests and commit.

### Task 3: Add the server-authoritative follow-up resolver and route

**Files:**
- Add: `ops-web/src/lib/api/services/lead-follow-up-send-service.ts`
- Add: `ops-web/src/app/api/leads/[opportunityId]/follow-up/route.ts`
- Add: `ops-web/tests/unit/email/lead-follow-up-send-service.test.ts`
- Add: `ops-web/tests/unit/api/lead-follow-up-route.test.ts`
- Modify: `ops-web/src/lib/email/opportunity-lifecycle-evaluator.ts`
- Modify: affected lifecycle-template tests

1. Add failing service tests for canonical thread selection, latest-provider-message direction, participant validation, template rendering, open-draft reuse, safe draft creation, and stale/ambiguous rejection.
2. Add failing route tests for auth, idempotency input, permission denial, provider-confirmed success, provider rejection, reconciliation pending, and delivery unknown.
3. Run the focused tests and confirm the failure boundary.
4. Implement the resolver and thin route using the existing delivery, signature, mailbox-lock, and reconciliation services.
5. Update the default follow-up copy and affected tests.
6. Run focused backend tests, type-check, and `git diff --check`.
7. Commit the backend route.

### Task 4: Add the iOS transport and durable tap key

**Files:**
- Add: `ops-ios/OPS/Services/LeadFollowUpService.swift`
- Add: `ops-ios/OPSTests/Pipeline/LeadFollowUpServiceTests.swift`
- Modify: `ops-ios/OPS/ViewModels/PipelineViewModel.swift`

1. Add failing tests for request encoding, Firebase bearer auth, canonical opportunity decoding, same-key retry, definitive-rejection key clearing, and pending/unknown key retention.
2. Run the focused tests and confirm they fail because the service does not exist.
3. Implement the protocol-backed transport, error mapping, and durable per-lead request-key store.
4. Add `PipelineViewModel.sendFollowUp` and apply only the returned authoritative opportunity.
5. Run the focused tests and commit.

### Task 5: Wire the one-tap chase action across every lead host

**Files:**
- Modify: `ops-ios/OPS/Views/Leads/Components/LeadChaseStrip.swift`
- Modify: `ops-ios/OPS/Views/Leads/LeadsTabView.swift`
- Modify: `ops-ios/OPS/Views/Leads/PipelineStageListView.swift`
- Modify: `ops-ios/OPS/Views/Leads/LeadDetailView.swift`
- Modify: `ops-ios/OPS/Views/Leads/Triage/LeadTriageCard.swift`
- Modify: `ops-ios/OPSTests/Pipeline/LeadChaseEngineTests.swift`
- Modify: `ops-ios/OPSTests/Views/MoneyLeadsRedesignSnapshotTests.swift`

1. Add failing state-derivation tests for `SEND FOLLOW-UP`, loading, fallback `HANDLED`, and accessibility copy.
2. Update the chase strip to expose the new action only for editable due/overdue leads with email and no session-level unavailability.
3. Wire one shared action through list, stage, card, and detail hosts.
4. Add success, pending, unknown, unavailable, and rejected toasts using OPS copy.
5. Run focused behavior and snapshot tests.
6. Run the generic-device iOS build with a worktree-local SPM cache.
7. Audit the changed UI against `OPSStyle` and commit.

### Task 6: Update the Software Bible and complete verification

**Files:**
- Modify: `ops-software-bible/04_API_AND_INTEGRATION.md`
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Modify: `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

1. Document the authenticated route, durable intent semantics, provider-thread safety checks, one-tap iOS behavior, lifecycle outcome transition, and notification.
2. Run the focused backend suite, `npm run type-check`, and the relevant migration tests.
3. Run focused iOS tests plus the generic-device build.
4. Run `git diff --check` in all three worktrees and inspect all diffs.
5. Request a read-only code review, address every real finding, and rerun affected checks.
6. Commit the Bible update and report branch/commit/live-state boundaries. Do not push or deploy.
