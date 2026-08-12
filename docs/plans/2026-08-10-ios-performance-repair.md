# iOS Performance Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven execution) to implement this plan task-by-task.

**Goal:** Eliminate the four verified root causes of app-wide UI lag: tab-switch full teardown, full-table rescans on every data change, permanent 2-second main-thread polling, and per-item saves in batch flows.

**Architecture:** All fixes preserve existing behavior and visuals exactly — they change *when* and *how much* work runs, not what the user sees. Fixes 1–5 are independent, small, and land first (atomic commits each). Fix 6 (keep-alive tabs) is the largest and lands last.

**Tech Stack:** SwiftUI, SwiftData (@ModelActor background writes via DataActor), Supabase sync. iOS deployment target **17.6** — no iOS-18-only APIs without `#available` gates.

**Design System:** `OPS/Styles/OPSStyle.swift` tokens only. Motion: `OPSStyle.Animation.standard` (the one sanctioned curve), no springs, no bounce. Honor `accessibilityReduceMotion`.

**Required Skills:** `animation-studio:ios-animations` for Task 6 (the tab-slide rework — the architect brief is baked into that task). No copy changes anywhere (no ops-copywriter needed). No new UI (no design-system audit delta expected; run `custom-skills:audit-design-system` mentally on Task 6's container — it introduces zero new style values).

**Hard rules for every task:**
- Many Swift files are CRLF or mixed — preserve existing line endings; never normalize a file.
- Sibling sessions exist (`.worktrees/` has ~20 entries, one dated today). Work ONLY in the primary checkout `/Users/jacksonsweet/Projects/OPS/ops-ios`. Stage by name, never `git add -A`. If `git status` shows files you didn't touch, do not stage them.
- Commit messages: conventional commits, no AI attribution of any kind.
- Build verification: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (never simulator for plain build). Tests: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`. Check `ps aux | grep xcodebuild` first; if a parallel build is running, wait.
- `xcodebuild` can print SUCCEEDED while running 0 tests — when running tests, confirm the xcresult actually executed the tests you added.
- UUID gotcha: any new entity ids must be lowercased at generation.
- Behavior parity is the acceptance bar: every count, badge, list, and visual must be identical before/after. Only timing/frequency of work changes.

---

## Task 1: Batch flows — one save instead of N (cascade delete + task reorder)

**Why:** `SyncEngine.recordOperation` does insert + `modelContext.save()` + full pending-queue re-fetch + optional push spawn *per call* (SyncEngine.swift:408–500). Project cascade delete calls it once per task with no `deferPush` (DataController.swift:3357–3370) → deleting an N-task project = N+1 main-thread saves + N push spawns. Task reorder (DataController.swift:~4790–4820) loops it per task (deferPush only skips the push, not the save). The bulk API `recordOperations(_ specs: [BulkOperationSpec])` already exists (SyncEngine.swift:964–1005) — one save for the whole batch, push deferred to caller. The codebase's own comment (SyncEngine.swift:959–963) says the per-op pattern caused a main-thread hang.

**Files:**
- Modify: `OPS/Utilities/DataController.swift` — `deleteProject(_:)` (~line 3340) and the task-index reorder function (~line 4790; find the enclosing func, it ends with the loop shown at 4805–4818)
- Read first: `OPS/Network/Sync/SyncEngine.swift:900–1010` — `BulkOperationSpec` shape and `recordOperations` semantics
- Test: find the existing sync-engine test target under `OPSTests/` (there are SyncEngine/outbound tests — e.g. the executeOperation claim-gate tests). Add to the closest-fitting file or create `OPSTests/Sync/BulkRecordFlowsTests.swift`.

**Step 1: Read both call sites fully** (the whole `deleteProject` including what happens after the task loop — it also records the project's own delete op — and the whole reorder function). Map every `recordOperation` call in each.

**Step 2: Write the failing test.** In-memory ModelContainer + SyncEngine configured with it (mirror existing test setup patterns in the sync tests). Test A: after `deleteProject` on a project with 5 tasks, exactly 6 delete SyncOperations exist (5 tasks + 1 project) — and observe `ModelContext.didSave` notification count during the call is ≤ 2. Test B: reorder path with 4 moved tasks records 4 update ops with ≤ 1 save. If DataController is too entangled to construct in tests, test `recordOperations` semantics directly and cover the call sites via Step 5's manual verification — but attempt the DataController-level test first.

**Step 3: Implement.**
- `deleteProject`: inside the task loop, collect `BulkOperationSpec(entityType: .projectTask, entityId: task.id, operationType: "delete", changedFields: ["deleted_at": formatter.string(from: deletionDate)])` into an array instead of calling `recordOperation`. After the loop (and after the project's own model mutation), call `syncEngine.recordOperations(specs)` once. The project's own delete op: convert it into the same specs array so the whole cascade is one batch. `recordOperations` saves the shared main context — the model mutations (`deletedAt`, `needsSync`) ride the same save; delete the now-redundant standalone `try modelContext.save()` if and only if `recordOperations` is guaranteed to run (guard the empty-specs case: a project with zero live tasks still needs its own op in the array, so specs is never empty). Then trigger exactly one `Task { await syncEngine.pushPending() }` (matching the old immediate-push behavior since the old calls did not pass deferPush).
- Reorder: same conversion — build specs in the loop, one `recordOperations`, then `if !deferPush { Task { await pushPending() } }` to preserve the parameter's contract. Keep the existing "nothing moved" early-return guard untouched.
- Do NOT change `recordOperation` itself — other callers depend on its semantics.

**Step 4: Run the tests; run the full sync test suite** to catch regressions (confirm in the xcresult that tests actually executed).

**Step 5: Build** (`generic/platform=iOS`).

**Step 6: Commit** — `perf(sync): batch cascade-delete and reorder ops through recordOperations`

---

## Task 2: Kill the 2-second polling loop (SyncStatusIndicator + RecoveryInventory + PendingWorkView)

**Why:** `SyncStatusIndicator` (`OPS/Views/Components/Sync/SyncStatusIndicator.swift:89–108`) runs `Timer.publish(every: 2, on: .main, in: .common)` forever — `.common` mode fires during scroll tracking; the `.onReceive` sits on the always-present `Group`, so it polls even when the pill is invisible (the normal state). Every tick runs `RecoveryInventory.load` (`OPS/Network/Sync/RecoveryInventory.swift:1023–1110`) on the main context: 6 fetches, two of which (`SiteVisitCaptureArtifact`, `SiteVisitChecklistAnswer`) are whole-live-table scans filtered in memory — and these tables grow forever. `.opsLeadsDidChange` also triggers the full load un-debounced per realtime row. `PendingWorkView` stacks a second 2s timer while open.

**Files:**
- Modify: `OPS/Network/Sync/RecoveryInventory.swift` (load, ~1023–1110)
- Modify: `OPS/Views/Components/Sync/SyncStatusIndicator.swift`
- Modify: `OPS/Views/.../PendingWorkView.swift` (locate via `grep -rn "Timer" OPS/Views --include="*.swift" | grep -i pending`; the 2s timers are at ~382, 401, 448)
- Test: `OPSTests/` — find existing RecoveryInventory tests (SYNC RECOVERY shipped with tests); add cases there.

**Step 1: Write failing test for the load short-circuit.** `RecoveryInventory.load` with a store containing artifacts/answers but zero drafts and zero site-visit ops must return empty artifact/answer snapshots WITHOUT scanning (assert correctness; structure the code so the skip is provable — see Step 2).

**Step 2: Narrow `RecoveryInventory.load`.** `visitIds` is computed *before* the artifact fetch. Add: `if visitIds.isEmpty { /* skip both artifact and answer fetches entirely — no pending site-visit work means neither can contribute */ }` producing empty arrays. When non-empty, keep the existing fetch + in-memory filter (predicate-side `contains` over a lowercased Set vs stored casing is risky — do not attempt; the empty-guard removes the steady-state cost, which is the verified problem). Preserve the existing header comment's honesty: update it to describe the guard.

**Step 3: Replace the indicator's timer with events + slow fallback.**
In `SyncStatusIndicator`:
- Delete the 2s `refreshTimer`.
- Add a debounced event-driven refresh: subscribe (Combine, `.receive(on: DispatchQueue.main)`, `.debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)`) to a merged publisher of: `NotificationCenter` `.dataActorDidSave` (posted on main after every background sync save — see DataActor.swift:25–32), `ModelContext.didSave` (main context — covers SyncEngine's outbound-op saves and local mutations), and `.opsLeadsDidChange` (this replaces the existing un-debounced onReceive at line 109). One `refreshAttention()` per debounced burst.
- Keep `.onAppear(perform: refreshAttention)`.
- Add a fallback timer at **60 seconds** in `.default` runloop mode (NOT `.common` — must not fire during scroll tracking) to self-heal anything event coverage misses (e.g. vault quarantine mutations from odd paths). `Timer.publish(every: 60, on: .main, in: .default).autoconnect()`.
- The pill's pending/syncing states already come free via `dataController` published properties — untouched.
- SwiftUI structural note: keep the subscriptions as view-level `.onReceive` on merged publishers or a small `@StateObject` monitor — whichever matches house style; no new global singletons.

**Step 4: Same surgery on PendingWorkView's timers** — while the screen is open a **5-second** `.default`-mode timer is acceptable (user is actively watching a live recovery screen; events + 5s floor keeps it live without scroll-hitching), plus the same debounced event subscription. Read the file first; preserve its exact refresh semantics.

**Step 5: Manual verification in simulator** (this is UI-behavioral): boot the app, confirm (a) pill appears during a sync pass, (b) pill updates after a lead change, (c) no visible behavior change otherwise. Screenshot the pill in its syncing state for the proof pack.

**Step 6: Run RecoveryInventory tests + build. Commit** — `perf(sync): event-driven sync pill; short-circuit recovery inventory scans`

---

## Task 3: FAB badge counts — fetch once, reuse, debounce

**Why:** `FloatingActionMenu.refreshReviewCounts()` (FloatingActionMenu.swift:941–958) runs on appear, on `DataSyncCompleted`, and on every `scheduledTasksDidChange` toggle — from EVERY tab (the FAB is always mounted: MainTabView.swift:486–489). Each run: `getAllTasks()` (unpredicated full fetch, DataController.swift:2446–2455) + `getProjects()` + `TaskReviewQuery.scopedTasks` (another `getAllTasks()`) + `TaskReviewQuery.editableTasks` (another) + `ProjectReviewQuery.snapshot` (another `getProjects()`) — ~5 full-table fetches + relationship graph walks per event, on the main thread.

**Files:**
- Modify: `OPS/Utilities/TaskReviewQuery.swift`, `OPS/Utilities/ProjectReviewQuery.swift`, `OPS/Views/Components/FloatingActionMenu.swift`, `OPS/Utilities/DataController.swift` (`getAllTasks`)
- Test: add `OPSTests/.../TaskReviewQueryParityTests.swift` (or extend existing review-query tests if present — grep first)

**Step 1: Predicate `getAllTasks()`.** Change the fetch to `FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.deletedAt == nil })` and drop the in-memory `.filter`. CHECK the `ProjectTask` model first: `deletedAt` must be a stored optional Date property (it is used in #Predicate elsewhere — confirm by grepping `#Predicate<ProjectTask>`). Behavior identical; deleted rows no longer materialize.

**Step 2: Add pass-through overloads.** `TaskReviewQuery.scopedTasks(tasks:dataController:)`, `editableTasks(tasks:dataController:)`, `overdueReviewTasks(tasks:dataController:)`, `unscheduledReviewTasks(tasks:dataController:)` — same logic, operating on a supplied `[ProjectTask]` instead of calling `getAllTasks()` internally. Keep the existing signatures as one-line delegates that fetch then call the overload (AppState + ReviewThresholdService + JobBoard callers stay untouched and correct). `ProjectReviewQuery` already has the projects-taking overload (snapshot(projects:thresholdDays:accessPolicy:)) — expose the threshold/policy assembly so FloatingActionMenu can call it with pre-fetched projects: add `snapshot(projects:dataController:permissionStore:)`.

**Step 3: Failing parity test.** Seed an in-memory store with a mixed task set (deleted/completed/unscheduled/assigned variants); assert each new overload returns identical results to the original entry point.

**Step 4: Rewire `refreshReviewCounts()`.** One `dataController.getAllTasks()` + one `dataController.getProjects()` at the top; pass into the overloads for all five cached values. Counts must be bit-identical.

**Step 5: Debounce the triggers.** The three triggers (onAppear / `DataSyncCompleted` / `scheduledTasksDidChange`) frequently fire together. Coalesce: route all three into a single `scheduleReviewCountRefresh()` that debounces 300ms (DispatchWorkItem or Task-sleep pattern, main actor). onAppear may run immediately (first paint needs counts).

**Step 6: Tests + build. Commit** — `perf(fab): single-fetch review counts with debounced refresh`

---

## Task 4: Calendar + JobBoard fetch predication

**Why:** The week-cache rebuild fetches EVERY ProjectTask unpredicated on the main context (CalendarViewModel.swift:~510 `context.fetch(FetchDescriptor<ProjectTask>())`) then filters in memory — on every inbound-change toggle while Schedule is mounted. MonthGridView and JobBoardView run sibling full-scan passes (MonthGridView.swift:~1006, JobBoardView.swift:~239, ~511).

**Files:**
- Modify: `OPS/ViewModels/CalendarViewModel.swift` (week rebuild ~495–560)
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift` (~1006 region), `OPS/Views/JobBoard/JobBoardView.swift` (~239, ~511 regions), and `DataController.getAllScheduledTasks(from:)` if it is unpredicated (read it)
- Test: none practical beyond parity assertions where cheap; rely on existing calendar tests + manual verification

**Step 1:** In the week rebuild, replace the unpredicated fetch with `FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.deletedAt == nil && $0.startDate != nil })` (both checked in the current in-memory filter's first lines — remove those two lines from the filter, keep everything else: company/scope/permission filters stay in memory because they walk relationships). Verify `startDate` is a stored property on the model, not computed — if computed, predicate only on `deletedAt` and keep the startDate line in memory.
**Step 2:** Same treatment for MonthGridView's year fetch and JobBoardView's compute passes: push `deletedAt == nil` (+ stored-property date bounds where the model allows) into predicates. Read each call's downstream logic first; parity is the bar.
**Step 3:** Run calendar/schedule test suites (memory: `InboundChangeRouterTests`, calendar tests exist). Build.
**Step 4: Commit** — `perf(calendar): predicate task fetches in week cache, month grid, job board`

---

## Task 5: DataActor catalog merges — diff-gate writes

**Why:** Seven catalog-family syncs run on EVERY delta pass (cursor seeded epoch — SyncEngine.swift:1784–1791) and dirty every local row unconditionally (`existing.lastSyncedAt = Date()`; variantOptionValues does wipe+reinsert) — DataActor.swift:2356–2486, 2937, 2978. Result: every sync pass commits saves + fires `.dataActorDidSave` → main-context merges + @Query invalidation even when nothing changed. `syncInventoryItemTags` (DataActor.swift:3183–3207) already shows the correct pattern: `guard serverTagIds != localTagIds else { continue }`.

**Files:**
- Modify: `OPS/Utilities/DataActor.swift` — `syncCatalogOptions` (~2369), `syncCatalogOptionValues` (~2406), `syncCatalogVariantOptionValues` (~2432), `syncCatalogItemTags` (~2457), `syncProductMaterials` (~2937), `syncProductBundleItems` (~2978)
- Test: if a DataActor test harness exists (grep `OPSTests` for DataActor), add: same-DTO second pass produces zero inserted/updated identifiers in the didSave rebroadcast. Otherwise verify via sync logging in the simulator (Step 3).

**Step 1:** For each of the six: field-by-field compare before assign; only touch `lastSyncedAt` when a real field changed; for `syncCatalogVariantOptionValues` replace delete-all+reinsert with keyed diff (delete missing, insert new, leave identical untouched) mirroring `syncInventoryItemTags`. Transactions that end up with zero changes must not save (check how `transaction {}` behaves — if it saves unconditionally, guard entry: skip the transaction when the diff is empty).
**Step 2:** Run catalog/sync tests. Build.
**Step 3:** Simulator proof: trigger two consecutive syncs with no server changes; capture console — second pass must log no catalog saves (or the didSave rebroadcast must be absent). Save the log excerpt to the session scratchpad for the proof pack.
**Step 4: Commit** — `perf(sync): diff-gate catalog merges so unchanged rows never dirty the store`

---

## Task 6: Keep-alive tab container (the big one — last)

**Why:** `MainTabView.tabContent` is a branch-per-tab `if/else` wrapped in `.id(selectedTab)` (MainTabView.swift:384–433). Every tab switch destroys the outgoing subtree (Mapbox map torn down, view models deallocated, @State lost) and cold-builds the incoming one (map re-created — OPSMapView.swift makeUIView builds a new MapView; Leads/Books re-fetch from network with visible spinners; Home re-runs full-table fetches). Tab switching is the primary navigation.

**Animation brief (from animation-architect):** Transition beat — spatial continuity, camera-move-not-cut. Directional slide preserved exactly: outgoing and incoming slide as complete units, direction from index comparison (same as current `slideTransition`, MainTabView.swift:300–305). One curve: `OPSStyle.Animation.standard`. Reduce-motion alternative: crossfade (opacity only), same duration. No new haptics (CustomTabBar already owns tab-tap feedback).

**Files:**
- Modify: `OPS/Views/MainTabView.swift` (router + body, ~380–433; `previousTab` state at 26; `slideTransition` at 300)
- Create: `OPS/Views/Components/TabActivationKey.swift` (EnvironmentKey `isActiveTab: Bool`)
- Modify (activation migration): `OPS/Views/Home/HomeView.swift`, `OPS/Views/Leads/LeadsTabView.swift`, `OPS/Views/Books/BooksTabView.swift` (paths approximate — locate each), `OPS/Views/JobBoard/JobBoardView.swift`, `OPS/Views/Catalog/CatalogView.swift`, `OPS/Views/Calendar Tab/ScheduleView.swift`, `OPS/Views/Settings/SettingsView.swift`
- Test: existing snapshot/UI harness (`AppHostWindow.acquire()` pattern per OPSTests) for a tab-switch state-retention test if feasible; otherwise simulator proof pack

**Step 1: Container.** Replace `Group { tabContent }.id(selectedTab).transition(slideTransition)` with a keep-alive ZStack:

```swift
@State private var mountedTabs: Set<Int> = []   // seeded with initial tab in onAppear

ZStack {
    ForEach(Array(mountedTabs).sorted(), id: \.self) { idx in
        tabRoot(for: idx)                       // the existing if/else body, parameterized by idx
            .offset(x: xOffset(for: idx))       // selected: 0; idx < selected: -width; idx > selected: +width
            .opacity(reduceMotion ? (idx == selectedTab ? 1 : 0) : 1)
            .allowsHitTesting(idx == selectedTab)
            .accessibilityHidden(idx != selectedTab)
            .environment(\.isActiveTab, idx == selectedTab)
    }
}
.animation(reduceMotion ? OPSStyle.Animation.standard : OPSStyle.Animation.standard, value: selectedTab)
```

- Width source: `containerRelativeFrame` is iOS 17 — fine — or a single `GeometryReader` at the container level (one, not per row). Offscreen tabs sit at exactly ±container width so the outgoing view visibly slides out while the incoming slides in — matching today's two-view slide.
- `reduceMotion` (`@Environment(\.accessibilityReduceMotion)`): offset stays pinned at 0 for all, crossfade via opacity — same beat, no lateral motion.
- Mount on first visit: `.onChange(of: selectedTab) { mountedTabs.insert($0) }` + seed initial tab. Never remove (keep-alive). `booksAutoSkipDestination` stays inside the Books slot unchanged.
- The container keeps: `.environment(\.tabBarVisibility, tabBarVisibility)`, `.onPreferenceChange(AppHeaderHeightKey.self)`, `.frame(maxWidth:.infinity, maxHeight:.infinity)`, `.ignoresSafeArea(.all, edges: .bottom)` — verify each still attaches at the right level (preference must flow from the ACTIVE tab; all mounted tabs emit it, so gate the preference emission or accept last-writer — check AppHeaderHeightKey's reduce semantics and ensure the active tab's header wins; if ambiguous, only the active slot gets `.environment(\.tabBarVisibility)`-driven header... resolve by reading AppHeaderHeightKey and testing).
- Delete `previousTab`/`slideTransition` if now unused.

**Step 2: Activation audit — every tab root.** For each of the seven tabs, read its `onAppear`/`.task`/`.onReceive` handlers and classify each side effect:
- **Mount-once** (data first-load, service wiring): stays where it is (fires once now — that's the win).
- **Per-visit** (analytics screen-view, wizard notifications, data freshness refresh): move to `.onChange(of: isActiveTab) { _, active in if active { … } }`. Also fire once on initial mount (onAppear runs then too — dedupe so the first visit doesn't double-fire).
- **Signal-driven recompute** (e.g. JobBoard's `scheduledTasksDidChange` handlers, Schedule's reload): gate while hidden — `if isActiveTab { refresh() } else { needsRefresh = true }`, and on activation `if needsRefresh { needsRefresh = false; refresh() }`. This prevents keep-alive from turning hidden tabs into background CPU consumers.

Known specifics:
- **HomeView** (:141–162): analytics per-visit → activation; `loadTodaysProjects()` → mount-once + activation-with-staleness (refresh on activation, it is now the only refresh path since teardown is gone); route-refresh timer start/stop must key off activation, not appear/disappear. Also predicate the billable-rollup Invoice/Estimate fetches (HomeView.swift:348–365) with `companyId` in the #Predicate if stored (else leave).
- **LeadsTabView** (:280–288): `.task` fetchAll with visible spinner → mount-once full load; on activation run the view model's silent refresh path (identity-preserving merge exists — no spinner when data present).
- **BooksTabView** (:260–266): five-VM `refreshAll()` → mount-once; activation → refresh WITHOUT resetting published state to loading (verify each VM's load sets a spinner flag only when empty).
- **ScheduleView** (:193–208, 226–228): reload on activation + keep its `scheduledTasksDidChange` observer active-gated with needsRefresh deferral.
- **JobBoardView** (:511–531 .task recomputes): active-gated + deferred.
- **CatalogView / SettingsView**: audit and apply the same classification; Settings is cheap — likely untouched.
- **Wizard/tutorial**: grep each tab root for `Wizard`/`Tutorial` notification posts tied to appear — these are per-visit semantics → activation.

**Step 3: Memory tradeoff (accepted, documented).** All visited tabs stay resident (one Mapbox map + retained VMs). This is the deliberate trade: RAM for responsiveness. Do NOT build eviction. Add a code comment on `mountedTabs` stating this is intentional and why.

**Step 4: Verification (simulator, mandatory proof pack):**
1. Build + run in the iOS Simulator.
2. Switch through all tabs twice in both directions — capture screenshots: slide direction correct both ways, headers aligned, tab bar/FAB overlays intact.
3. Home → JobBoard → Home: map camera position retained (no re-style flash). Screenshot both visits.
4. Leads → elsewhere → Leads: NO loading spinner on return (data retained). Screenshot.
5. Scroll JobBoard list, leave, return: scroll position retained.
6. Sheets: open a sheet from Books, background the app, return — sheet intact (the FAB's always-render rationale, now extended to tabs).
7. Reduce Motion ON (simulator setting): tab switch crossfades, no slide.
8. Run the full test suite; confirm via xcresult that suites executed.

**Step 5: Commit** — `perf(tabs): keep-alive tab container — slide preserved, teardown eliminated`

---

## Task 7: Bible update + final sweep

1. Update `ops-software-bible/` (the iOS architecture section — likely `02` or the specialized-features file; locate the sync/UI architecture docs) with: keep-alive tab container semantics + activation protocol, event-driven sync pill, bulk-record pattern as the required pattern for batch flows, diff-gated merges as the required pattern for full-fetch syncs.
2. Full build + full test suite, one last pass.
3. Assemble the proof pack (screenshots + log excerpts from Tasks 2/5/6) in the session scratchpad for the final report. Nothing lands in the repo root.
4. Commit bible — `docs(bible): performance repair — keep-alive tabs, event-driven pill, batch-save patterns`
