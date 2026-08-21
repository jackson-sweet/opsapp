# Historical Site-Visit Settlement Implementation Plan

**Goal:** Give the five audited pre-incident site visits a narrow, approval-controlled exit from the phone queue without replaying a completed visit or weakening normal sync safety.

## 1. Freeze the recovery scope

- Represent every authorized visit in an exact manifest containing its visit id, expected server status, expected server `updated_at`, and permitted outcome.
- Derive the target opportunity only from the retained phone row plus its matching unresolved queue envelopes. Never accept a replacement target from the operator or server.
- Reject missing, extra, foreign-company, malformed, duplicated, in-flight, deleted, already-linked, conflicting-child, or stale-server evidence.

## 2. Separate planning from approval

- Build a deterministic plan from the manifest, the complete matching phone packet, current row-scoped capability, and a freshly fetched server bundle.
- Fingerprint the plan. Execution requires a separately-created approval naming the exact fingerprint, actor, company, visit, target, and outcome.
- Keep the mechanism outside `SyncEngine`; it has no launch sweep, reconnect hook, timer, Retry All entry, or bulk API.

## 3. Recover active relationships narrowly

- For `scheduled` and `in_progress`, update only `site_visits.opportunity_id` with compare-and-set filters for exact id, company, status, prior `updated_at`, `deleted_at IS NULL`, and `opportunity_id IS NULL`.
- Let the existing database relationship guard/child propagation and RLS remain authoritative.
- Re-fetch and validate the full server relationship graph before re-arming only the exact packet operations captured by the plan.

## 4. Settle completed history locally

- Require the server visit to remain completed and unlinked, and require an exact normalized content fingerprint match between the retained phone packet and the server bundle.
- Never call any server mutation path. Clear the rejected local relationship intent, mark the exact packet rows synced, and settle only the exact captured operations with `serverConfirmedAt = nil`.
- Write an encrypted/file-protected prepared/applied audit receipt around execution so replay is idempotent and a crash cannot erase the accounting trail.

## 5. Proof and handoff

- Add focused synthetic tests for valid active recovery, valid completed accounting, idempotent replay, stale/conflicting/capability failures, incomplete content proof, and immunity to unrelated operations.
- Run only the focused suite in isolated DerivedData after confirming no Xcode/Swift build is active.
- Update the Software Bible, commit iOS then Bible atomically, and return the separate approval-controlled live procedure. Do not execute it against the five live visits.
