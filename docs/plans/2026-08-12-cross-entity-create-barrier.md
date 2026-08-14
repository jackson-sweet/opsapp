# Cross-Entity Create Barrier — Implementation Plan (bug 06f68200)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. TDD is mandatory.

**Goal:** An outbound sync op whose payload references an entity whose own `create` op hasn't synced yet must be HELD (never attempted, never parked), and ops already mis-parked by this race must self-heal once the blocking create completes.

**Architecture:** New shared pure module `SyncCrossEntityDependency` (mirrors the `TaskTypeMutationSync` / `SiteVisitOutboundSync` barrier pattern) wired identically into BOTH outbound paths (`OutboundProcessor` + `DataActor`) at three points: (1) the eligibility filter — hold any op whose payload FK references an entity with a non-completed local `create` op; (2) the drain-continuation ready sets — so a create completing mid-drain releases held work in the same drain; (3) a pass-start release step — a `parked` op whose `lastError` is an RLS/FK rejection and whose blocking create completed AFTER the op's last attempt is provably a mis-park → release to `pending` once (loop-safe: the re-attempt stamps `lastAttemptedAt` past `completedAt`, so a second park never re-releases).

**Decision record — why fix (1), not fix (2):** Reclassifying RLS rejections as retryable-when-a-create-is-pending would (a) waste the network attempt, (b) burn the 20-retry budget against a dependency with arbitrary latency, (c) make `SyncErrorClassifier` context-dependent, violating its by-design purity (see its header: born from the 2026-07-22 outage; permanent = park immediately, never auto-retry), and (d) reopen the retry-storm failure mode that discipline exists to prevent. The queue architecture already solves ordering with barriers at the eligibility filter — this is the same pattern, cross-entity.

**Tech Stack:** Swift / SwiftData, XCTest. No server changes. No UI.

**Design System:** N/A (no UI).

**Required Skills:** superpowers:test-driven-development, superpowers:verification-before-completion.

**Hard constraints (from CLAUDE.md + memory):**
- Both outbound paths must get byte-equivalent wiring (allowlist-drift gotcha).
- `UUID().uuidString` is uppercase; Postgres ids lowercase — all id comparisons lowercased.
- Never `#Predicate`-fetch `SyncOperation` against a possibly-empty table in new code paths (uncatchable trap) — the module is pure (takes `[SyncOperation]` arrays), no fetches.
- CRLF: new files LF; edited files preserve existing endings.
- Worktree builds: copy `Secrets.xcconfig`, pass `-clonedSourcePackagesDirPath .spm-local`.
- Verify via xcresult, not xcodebuild stdout.

---

### Facts established during recon (do not re-derive)

- Parked repro: deckDesign `update` payload `{updated_at, project_id}` → RLS `assigned_lead_scope_update` WITH CHECK calls `private.current_user_can_edit_deck_design(company_id, opportunity_id, project_id, …)` → unresolvable project → 42501 → `SyncErrorClassifier` (correctly, context-free) says `.permanent` → parked forever, even though the create landed the same day.
- `DeckDesignRepository.updateFields` is `.update().eq("id").execute()` — no `.single()`; a PATCH to values the server already has succeeds silently once RLS passes. The stale-replay case needs no code change, only the release.
- The generic claim gate (`ProjectNoteMentionEditSync.claimForExecution`, used for ALL ops) stamps `lastAttemptedAt = now` on every claim → every parked op has a non-nil `lastAttemptedAt` — the loop-safe release comparison is sound.
- Test harness pattern: `OPSTests/Sync/DeckDesignLinkSyncTests.swift` (in-memory `ModelContainer` with `Schema([DeckDesign.self, SyncOperation.self, PhotoAnnotation.self])`, `makeOp` builder, drives the REAL `OutboundProcessor`). DataActor's mirrored copies are private/unreachable from tests — shared logic proven at module level + wiring enforced identical by review (established precedent, see that file's header).
- Integration points in `OutboundProcessor.swift`: eligibility filter ~line 128–173, drain loop ~34–88, pass start ~100. Mirrors in `DataActor.swift`: filter ~4744–4786, drain loop ~4650–4713, pass start ~4716.

---

### Task 1: Failing tests (RED)

**Files:**
- Create: `OPSTests/Sync/SyncCrossEntityDependencyTests.swift`

Two groups:

**A. Pure module** (compile-RED — module doesn't exist yet):
1. `update` op with payload `project_id` = X blocked while a `project` create for X is `pending` / `inProgress` / `failed` / `parked`; NOT blocked when `completed` or absent.
2. Id comparison is case-insensitive (uppercase payload value vs lowercase create entityId).
3. Non-mapped keys (`opportunity_id`, arbitrary `*_id`) never block; non-string FK values never block; a create of a DIFFERENT entityType with the same id never blocks.
4. `readyPendingOperationIds`: pending-not-blocked ∪ releasable-parked; completing the create grows the set (drives `shouldContinueDrain` semantics `!after.isEmpty && after != before`).
5. Release rule: parked op with RLS lastError (`row-level security`) or FK lastError (`violates foreign key constraint`), `lastAttemptedAt` BEFORE the blocking create's `completedAt` → releasable. NOT releasable when: lastError is anything else; `lastAttemptedAt` ≥ `completedAt` (loop guard); `lastAttemptedAt` nil; create not completed.

**B. Wiring (behavioral-RED against today's `OutboundProcessor`):**
6. Hold: seed project create for X in backoff (`retryCount 3`, `lastAttemptedAt = now`) + pending deckDesign update whose payload carries `project_id` X. Run `processPendingOperations`. Assert the update is untouched: `status == "pending"`, `lastAttemptedAt == nil`, `retryCount == 0`. (Today it attempts the push and mutates state → fails.)
7. Release: seed parked deckDesign update (RLS lastError, `lastAttemptedAt = t0`) + completed project create (`completedAt = t1 > t0`) + give the parked op a `dependsOnId` pointing at a nonexistent op UUID (so after release the eligibility filter skips it — no network in tests). Run `processPendingOperations`. Assert `status == "pending"` (was `parked`).

**Step 2:** `xcodebuild build-for-testing` → expect compile failure naming `SyncCrossEntityDependency` (group A) — that is the expected RED for A; comment group A out and run group B to watch it fail behaviorally, or accept compile-RED for A and behavioral-RED for B in one run once the module skeleton exists. Simplest honest sequence: write group B first, watch it FAIL at runtime; then add group A, watch compile fail; then implement.

### Task 2: Minimal implementation (GREEN)

**Files:**
- Create: `OPS/Network/Sync/SyncCrossEntityDependency.swift`
- Modify: `OPS/Network/Sync/OutboundProcessor.swift` (filter + pass-start release + drain ready sets)
- Modify: `OPS/Utilities/DataActor.swift` (identical wiring, actor style: `modelContext.transaction`, `rollback()` before ready-set fetches)

Module (pure, no fetches, no side effects except caller-owned mutation helpers):

```swift
enum SyncCrossEntityDependency {
    /// payload FK key → SyncEntityType raw value whose local create must resolve first
    static let payloadReferenceKeys: [String: String] = [
        "project_id": SyncEntityType.project.rawValue,
        "client_id": SyncEntityType.client.rawValue,
        "company_id": SyncEntityType.company.rawValue,
        "task_type_id": SyncEntityType.taskType.rawValue
    ]
    static func isBlockedByUnresolvedCreate(_ op: SyncOperation, in all: [SyncOperation]) -> Bool
    static func readyOperationIds(in operations: [SyncOperation]) -> Set<UUID>   // pending-not-blocked ∪ releasable-parked
    static func shouldContinueDrain(readyBeforePass: Set<UUID>, readyAfterPass: Set<UUID>) -> Bool
    static func parkedOperationsReleasableByCompletedCreates(in operations: [SyncOperation]) -> [SyncOperation]
}
```

Blocking rule: another op `c` in `all` with `c.operationType == "create"`, `c.entityType == mapped type`, `c.entityId.lowercased() == value.lowercased()`, `c.status != "completed"`, `c.id != op.id`. Payload decoded once per op via `JSONSerialization`; String values only.

Release action (caller, inside its transaction): `status = "pending"`, `retryCount = 0` (matches user-Retry semantics). Leave `lastAttemptedAt`/`lastError` — the next claim overwrites the stamp; the error stays visible until the op resolves.

Wiring per path: (a) pass start — release before the pending fetch so released ops join the same pass; (b) filter — hold + log line matching sibling barrier style; (c) drain loop — before/after `readyOperationIds` snapshots + `shouldContinueDrain` OR-ed in.

**Steps:** implement → run full `OPSTests/Sync` suite → all green including prior suites (coalescer, retry policy, site-visit drains must not regress).

---

## OUTCOME (2026-08-13) — shipped

**Executed as planned; fix (1) implemented, fix (2) rejected for the reasons in the decision record.**

TDD record:
- **RED 1 (compile).** Test target failed with `cannot find 'SyncCrossEntityDependency' in scope` × 21 sites.
- **RED 2 (behavioral, stub module).** 22 failed / 1 passed. Both wiring tests failed for the *right* reason and reproduced the production bug exactly: the held edit was claimed and pushed (`status == "completed"`, `lastAttemptedAt` stamped) instead of held, and the mis-parked op stayed `parked` with `retryCount == 2`.
- **Harness defect found mid-cycle.** Every module test died at `context.insert` with an uncatchable `EXC_BREAKPOINT` inside SwiftData (0.000 s, fresh process each) — confirmed from the crash report, not inferred. Cause: `makeContext()` returned `makeContainer().mainContext`, letting the container deallocate; a `ModelContext` does not keep its container alive. Fixed by retaining containers for the test case's lifetime. **No assertion was changed.** (New gotcha — worth adding to CLAUDE.md.)
- **RED 3 (honest, post-harness-fix).** 13 passed / 10 failed against a stubbed module. The 10 are the positive assertions (must-hold, must-release); the 13 that pass are negative assertions a do-nothing stub satisfies vacuously — they earn their place by having to stay green against real logic (they do).
- **GREEN.** 111 passed / 0 failed / 0 skipped, `TEST EXECUTE SUCCEEDED`, across `SyncCrossEntityDependencyTests` + 5 existing sync suites (`DeckDesignLinkSyncTests`, `OutboundRetryPolicyTests`, `SyncErrorClassifierTests`, `SiteVisitOutboundSyncTests`, `RecoveryInventoryTests`) — counts read from the `.xcresult`, not stdout.

Deviations from plan, and why:
1. **`ConnectivityManager` is no longer `final`** (one word + a 5-line doc comment). `state` is `private(set)` and driven only by `NWPathMonitor`, and `recordRequestResult` can only push quality *down* — so there was no way to deterministically force `shouldAttemptSync == true`. Without the seam, the hold test passes vacuously on an offline host and the release test can never pass (the release step lives behind that guard). Tests subclass and override the decision helper.
2. **`quarantined` added to the unresolved-create status set** (plan listed only pending/inProgress/failed/parked) — a quarantined create is equally absent server-side.
3. **Stale-replay resilience needed no code.** Verified `DeckDesignRepository.updateFields` is `.update().eq("id").execute()` with no `.single()`, so a PATCH to values the server already holds succeeds silently once RLS passes. The parked ops on the device are exactly this case.

Environment note (not caused by this work): the test host hit `mkstemp: No space left on device` mid-run — the data volume is 97 % full (86 GB CoreSimulator devices, 21 GB DerivedData). No stale clones or unavailable devices to sweep; flagged rather than deleted.

### Task 3: Verification + docs + commit

1. Device-target build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build` → BUILD SUCCEEDED (grep the log, not the exit code).
2. Test suite via simulator destination; parse `.xcresult` for pass/fail counts (never trust stdout SUCCEEDED alone).
3. Bible: append the barrier + release mechanism to `ops-software-bible/07_SPECIALIZED_FEATURES.md` §34 (sync recovery) — same session.
4. Conventional commits on the worktree branch, then fast-forward/merge into local `main`. NO push. No AI attribution.
