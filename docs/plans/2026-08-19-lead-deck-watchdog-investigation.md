# Lead Deck Watchdog Investigation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to execute this plan task-by-task.

**Goal:** Reproduce or otherwise measure bug `2fa645a8-71c4-496c-8f53-1347bf8213d4`, identify the exact code holding the main thread, and make a focused test-first repair only if the root cause is proven.

**Architecture:** Treat the device watchdog reports, the SwiftUI deck route, SwiftData fetches, and Supabase Realtime as separate evidence streams. Establish timing and visibility for each boundary, test one hypothesis at a time, and preserve a no-fix outcome if the stall remains unreproduced.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Xcode device tooling, Instruments/sample tooling, Supabase Swift Realtime.

**Design System:** N/A — no visual or copy changes are planned. If the proven fix changes UI, load the OPS iOS design skills before editing.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:using-git-worktrees`, `custom-skills:executing-plans`; conditionally `superpowers:test-driven-development` and `superpowers:verification-before-completion` after root-cause proof.

---

### Task 1: Preserve and classify device evidence

**Skills:** `superpowers:systematic-debugging`

**Files:**
- Read: paired-device `systemCrashLogs`
- Create only if useful: `docs/artifacts/lead-deck-watchdog-2fa645a8/` evidence summaries

**Step 1:** Pull the current OPS crash-report inventory from device `F1B83A71-FF52-5645-BA81-F8B8DB07A44C` without deleting anything.

**Step 2:** Classify every OPS report since 2026-08-12 by termination reason, watchdog subtype, process visibility, and thread-0 owner.

**Step 3:** Independently validate the three named reports before using them: `OPS-2026-08-19-190158`, `OPS-2026-08-14-145455`, and `OPS-2026-08-17-100816`.

**Step 4:** Record which reports can and cannot correspond to a foreground DECK-row tap.

### Task 2: Map the route and its runtime work

**Skills:** `superpowers:systematic-debugging`, `supabase:supabase`

**Files:**
- Read: `OPS/Views/Leads/LeadDetailView.swift`
- Read: `OPS/Views/Leads/Components/LeadDeckScreen.swift`
- Read: `OPS/Views/Components/Project/Tabs/DeckTabView.swift`
- Read: `OPS/DataModels/DeckDesign.swift`
- Read: the exact Realtime subscription implementation reached from lead detail/deck navigation
- Read: the relevant deck/data sections in `../ops-software-bible/`

**Step 1:** Trace the DECK row action through navigation to the first rendered deck surface, with exact file and line references.

**Step 2:** Enumerate synchronous main-actor work performed during the first SwiftUI body/layout passes.

**Step 3:** Inspect the three previous investigation branches and commits only as evidence; revalidate every claim against current `main`.

**Step 4:** Read bug-report row `2fa645a8-71c4-496c-8f53-1347bf8213d4` with SELECT-only Supabase access and independently verify its current state.

### Task 3: Establish a clean, isolated baseline

**Skills:** `superpowers:using-git-worktrees`, `superpowers:systematic-debugging`

**Files:**
- Worktree: `.worktrees/w7-lead-deck-watchdog-2fa645a8`
- Local package cache: `.spm-local/`
- Local build output: `.derived-data/`

**Step 1:** Confirm no other `xcodebuild` process is active before each build.

**Step 2:** Build current `main` for a generic iPhone target using the worktree-local package and DerivedData paths.

**Step 3:** Run the smallest existing deck navigation/performance tests that exercise `LeadDeckScreen` and `DeckTabView`.

**Step 4:** Record pre-existing failures separately; do not attribute them to this investigation.

### Task 4: Reproduce and measure the exact interaction

**Skills:** `superpowers:systematic-debugging`

**Files:**
- Modify temporarily if required: focused debug-only measurement points along the DECK row to stable deck render path
- Test: the narrowest existing `OPSTests` deck/lead test target

**Step 1:** Reproduce the real DECK-row tap on the paired iPhone with the debugger or Instruments attached, using the current founder-visible build path.

**Step 2:** Capture the main-thread stack during any stall rather than waiting only for a watchdog kill.

**Step 3:** Measure route transition, SwiftData fetch count/time, SwiftUI body/layout frequency, and Realtime teardown/subscription time independently.

**Step 4:** Use one blocking `RunLoop.run(until:)` when a run-loop settle is required; do not measure a busy-wait loop.

### Task 5: Test one root-cause hypothesis at a time

**Skills:** `superpowers:systematic-debugging`

**Files:**
- Test: focused diagnostics or regression cases under `OPSTests/`

**Step 1:** State one hypothesis in measurable terms and identify the observation that would falsify it.

**Step 2:** Make the smallest diagnostic change that isolates that variable.

**Step 3:** Re-run the exact interaction and compare timing/stack evidence.

**Step 4:** Remove or retain instrumentation based on evidentiary value before testing the next hypothesis.

### Task 6: Repair only a proven root cause

**Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`

**Files:**
- Test: exact path determined by the proven failing boundary
- Modify: exact production file and line determined by the captured main-thread stack

**Step 1:** Write the smallest regression test or deterministic performance test that fails on unchanged `main` for the proven cause.

**Step 2:** Run the test and preserve the failing output.

**Step 3:** Implement one focused fix at the originating boundary, with no unrelated cleanup.

**Step 4:** Run the regression test and the adjacent suite until both pass.

**Step 5:** Commit only the focused test and repair with a conventional `fix(deck): ...` message.

### Task 7: Verify the App Store blocker outcome

**Skills:** `superpowers:verification-before-completion`

**Files:**
- Update only if behavior or architecture changes: relevant section under `../ops-software-bible/`

**Step 1:** Re-run the exact device interaction across the four named leads when their data is available without copying live business data off-device.

**Step 2:** Confirm the main thread settles and that no matching scene-update watchdog is produced.

**Step 3:** Run the focused tests and a generic iPhone build from the isolated paths.

**Step 4:** Report separately: reproduced root cause, test evidence, local fix state, device proof, and release/push state.

**Step 5:** If the hang is not reproduced, make no speculative fix; report every eliminated cause and the strongest remaining evidence gap.

---

## Investigation outcome (2026-08-19)

- Sixteen device reports were classified: three scene-update watchdogs, seven
  process-exit timeouts, and six non-watchdog crashes. Only one foreground
  scene-update report contains an attributable application boundary.
- `OPS-2026-08-17-100816` proves a Supabase Realtime lock-order deadlock while
  `OPSApp` cancels the socket-status observation on the main actor. Supabase
  fixed that exact production watchdog in 2.54.1. Its upstream stress test
  hangs against OPS's pinned 2.41.1 checkout and passes at the fix commit.
- The two background scene-update watchdogs contain SwiftUI graph/layout work,
  not the Realtime stack. Sampling the lead Deck route under unrelated
  `DeckDesign` store churn localized avoidable main-thread work to two broad
  SwiftData `@Query` properties feeding `DeckTabView` and `LeadDeckScreen`.
- Controlled measurement with the deck route removed fell from roughly
  3,000–3,350 ms to 307–379 ms of main-thread CPU over the same four-second
  churn window. The targeted persistent-identifier feed measures 401–646 ms,
  performs zero drawing serializations, ignores unrelated deck inserts, shows
  a relevant insert, and safely clears a deleted visible model.
- The local repair pins Supabase Swift 2.54.1 and replaces the two lead viewer
  queries with one owner-scoped feed. Background actor saves now cross an
  ordered main-context visibility boundary before that feed fetches, and any
  deck update is re-evaluated so reassignment into or away from the visible
  lead cannot leave a stale selection.
- The final focused simulator suite passes 32 tests. The repeated unrelated
  update test measures 184–304 ms of main-thread CPU over 200 persisted
  updates, performs zero drawing serializations, and the signed generic-device
  build succeeds. Independent code review found no remaining correctness or
  merge-blocking issue.
- The four founder-phone DECK taps remain a separate manual acceptance gate;
  simulator proof cannot claim them.
