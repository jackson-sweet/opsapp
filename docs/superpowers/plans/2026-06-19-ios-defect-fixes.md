# iOS Active-Defect Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Before editing any complex file, READ the cited line ranges first — several tasks intentionally anchor to current code rather than restating whole files.

**Goal:** Resolve the 8 active iOS defects in the OPS `bug_reports` table (Supabase project `ijeekuhbatykdomumfjx`, `platform = ios`), grounded in verified root causes from the live tree at `ops-ios/OPS/`.

**Architecture:** SwiftUI + SwiftData app. Calendars plot tasks by `task.start_date`; a Combine `@Published` (`scheduledTasksDidChange`) drives calendar refreshes. Permissions live-sync via `PermissionStore` (`@ObservedObject`). Sync is a local-first queue (`SyncEngine` / `SyncOperation`) with an inbound merge gate that can resurrect locally-changed rows when no pending op protects the field. The app executes as the anon Postgres role, so RLS must permit anon.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, Combine, Supabase (PostgREST), XCTest. Build per `ops-ios/CLAUDE.md` (see commands below).

---

## Defect status summary (verified against live tree)

| # | Bug ID | Screen | Root cause (verified) | Verdict |
|---|--------|--------|------------------------|---------|
| 1 | `3911ed80` | Books | Divergent `ARAgingDetailView.swift` is **dead** (worktree-only). Live `ARCard.swift` is the sole bucket source and already reconciles to the hero. | Verify + optional relabel |
| 2 | `d5c899e6` | ProjectDetails (DECK tab) | Fail-closed-on-transient-RBAC-error stripped flags mid-session. **Already fixed** at `PermissionStore.swift:239-257`. | Verify + close |
| 3 | `588b3e19` | Home | `totalKnownAmount` coerces nil→0 (`HomeBillableThisWeekRollupEngine.swift:48`); "no value" renders as `$0`. | Fix (TDD) |
| 4 | `f9e00eb9` | ProjectDetails (notes) | Optimistic soft-delete enqueues **no** `SyncOperation`; inbound merge resurrects `deletedAt`→nil. | Fix |
| 5 | `759530e1` | Calendar day sheet | Month-view `DayDetailsSheet` re-resolves task IDs via `getTask(id:)` and drops nils, while grid bars render straight from the cache. | Fix |
| 6 | `dc74f393` | Universal search | Client/Invoice/Estimate deep links use **sibling `.sheet` modifiers** on MainTabView; SwiftUI presents only one. | Fix (also closes Invoice/Estimate) |
| 7 | `70087050` | Global (shake-to-report) | `.onReceive(.deviceDidShake)` lives in the conditional `MainTabView` subtree; it detaches when AppMessage/Lockout replaces the tree and never re-arms. | Fix |
| 8 | `b954065e` | ProjectDetails → schedule | One date edit toggles a global `@Published` ≥2×, fanning out to 3 calendar views that each do unindexed full-table `ProjectTask` fetches + rebuilds on the main thread. | Fix (perf refactor) |

**Sequence rationale:** verifications first (1, 2 — cheap, close tickets), then self-contained fixes in ascending complexity (3 → 4 → 5 → 6 → 7), then the perf refactor (8) last because it touches the most observers.

---

## Build & verification commands (from `ops-ios/CLAUDE.md`)

- **Device-target build verify (use for every code task):**
  `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
- **Test compile:**
  `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
- **Run tests:**
  `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test`
- **If executing in a git worktree** (recommended to avoid colliding with parallel sessions): copy secrets and pin SPM cache locally:
  `cp OPS/Utilities/Secrets.xcconfig <worktree>/OPS/Utilities/Secrets.xcconfig`
  append `-clonedSourcePackagesDirPath .spm-local` to xcodebuild.
- **Before any xcodebuild:** check `ps aux | grep xcodebuild` / `lsof` — a sibling session may be writing the shared DerivedData.
- **Runtime walkthrough caveat:** iOS auth is Firebase; repeated failed logins throttle to a generic error. Use a clean simulator, don't relaunch mid-login, prefer Continue-with-Google if throttled.
- **Many Swift files are CRLF/mixed line endings** — preserve them; do not let an editor normalize EOLs (it produces huge whitespace-only diffs that collide with parallel sessions).

---

## Files touched

- Modify: `OPS/Services/HomeBillableThisWeekRollupEngine.swift` (Task 3)
- Modify: `OPS/Views/Home/HomeContentView.swift` (Task 3)
- Modify: `OPS/Services/.../HomeBillableThisWeekNotificationDispatcher.swift` (Task 3)
- Modify: `OPSTests/.../HomeBillableThisWeekRollupTests.swift` (Task 3)
- Modify: `OPS/ViewModels/ProjectNotesViewModel.swift` (Task 4)
- Modify: `OPS/Network/Sync/InboundProcessor.swift` (Task 4)
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift` (Task 5)
- Modify: `OPS/Views/MainTabView.swift`, `OPS/AppState.swift`, `OPS/Views/JobBoard/UniversalSearchSheet.swift` (Task 6)
- Modify: `OPS/ContentView.swift` (Task 7)
- Modify: `OPS/DataController.swift`, `OPS/ViewModels/CalendarViewModel.swift`, `OPS/Views/Calendar Tab/MonthGridView.swift`, `OPS/Views/.../ScheduleView.swift` (Task 8)
- Modify (optional, copy): `OPS/Views/Books/Cards/ARCard.swift` (Task 1 relabel)

---

## Task 1: Verify AR-aging reconciliation; retire the dead divergent view (`3911ed80`)

**Files:**
- Verify: `OPS/Views/Books/Cards/ARCard.swift:31-57` (sole live bucket source)
- Verify: `OPS/Views/Books/Cards/ARDetailSheet.swift` (live drill-down; embeds `ARCard`, no own buckets)
- Investigate: `.worktrees/ios-design-system-pass/OPS/Views/Books/ARAgingDetailView.swift` + `.worktrees/ios-ds-pass/...` (dead copies)

**Root cause (verified):** `ARCard.swift:41` buckets with `case ..<31`, so not-yet-due invoices land in 0–30d; `:55-57` `totalOutstanding` sums all `outstandingInvoiceBreakdown` (no due-date filter) → card buckets reconcile to the hero. The ticket's second computation lives only in `ARAgingDetailView.swift`, which has **zero references in the live tree**. The shipping drill-down (`ARDetailSheet`) embeds `ARCard`, so it reconciles by construction.

- [ ] **Step 1: Confirm no live divergence**

Run: `grep -rn "ARAgingDetailView" ops-ios/OPS --include=*.swift` (expect: no hits under `ops-ios/OPS/`, only `.worktrees/...`).
Run: `grep -rn "if days < 0" ops-ios/OPS/Views/Books` (expect: no hits — that guard only exists in the dead file).

- [ ] **Step 2: Runtime-verify the drill-down reconciles**

Build + run, open Books → AR card, tap into the TOP-CHASE drill-down (`ARDetailSheet`). Confirm the sum of buckets shown equals the card's TOTAL OUTSTANDING hero (including any not-yet-due invoice). Expected: equal.

- [ ] **Step 3 (optional honesty relabel — gated on ops-copywriter):**

`ARCard.swift:48` labels the youngest bucket `"0–30d"` but it holds not-yet-due + 0–30d-overdue. Because the hero is TOTAL OUTSTANDING (not "overdue"), a clearer label is `"CURRENT"` or `"≤30d"`. **This is user-facing copy → invoke `ops-copywriter` before changing the string.** If approved, change only the label in the `Bucket(id: 0, label: …)` literal. If copywriter says keep it, do nothing.

- [ ] **Step 4: Dead-file disposition**

Do **not** delete the `.worktrees/*` copies from this session — they belong to other worktrees and deleting cross-worktree files can collide with parallel sessions (see `ops-ios/CLAUDE.md`). Instead, leave a note in the ticket that `ARAgingDetailView.swift` is orphaned and should be removed by whoever owns `ios-design-system-pass` before that branch merges, or it will reintroduce the divergence.

- [ ] **Step 5: Mark the bug**

Update `bug_reports` row `3911ed80` (standing authorization for bug rows): set `fix_notes` = "Closed-by-supersession: live ARCard is the sole bucket source and reconciles to the hero; divergent ARAgingDetailView is dead (worktree-only). Verified 2026-06-19." Set `status = 'resolved'` only after Step 2 passes on a build. No commit (verification only, unless Step 3 relabel was approved → `git add OPS/Views/Books/Cards/ARCard.swift && git commit -m "fix(books): relabel AR youngest aging bucket for accuracy"`).

**Blast radius:** None (verification). Optional relabel touches one string in one card.

---

## Task 2: Verify DECK-tab permission fix; close (`d5c899e6`)

**Files:**
- Verify: `OPS/Utilities/PermissionStore.swift:236-258` (catch block)
- Verify: `OPS/Views/Components/Project/ProjectDetailsView.swift:648-654` (`visibleTabs` gate)

**Root cause (verified, already fixed):** `visibleTabs` is a computed property reading `@ObservedObject PermissionStore.shared`, so SwiftUI re-derives it on every publish — the gating architecture is correct. The defect was in `fetchPermissions`'s catch block: a transient RBAC fetch error used to overwrite flags with `failClosedResult()`, stripping `deck_builder` (and pipeline/estimates/accounting) mid-session. `PermissionStore.swift:239-257` now only falls back to cache when `!initialized`, with a comment naming this exact symptom.

- [ ] **Step 1: Confirm the guard is present**

Run: `grep -n "if !self.initialized" ops-ios/OPS/Utilities/PermissionStore.swift` (expect a hit at ~254).
Read `:236-258` and confirm the catch block does NOT call `failClosedResult()` when `initialized == true`.

- [ ] **Step 2: Runtime-verify**

As a user who HAS `deck_builder.view`, open a project, confirm the DECK tab is present, then force a transient RBAC blip (background/foreground the app a few times, or toggle connectivity) and confirm DECK does not vanish.

- [ ] **Step 3: Close the ticket**

Update `bug_reports` row `d5c899e6`: `fix_notes` = "Already fixed at PermissionStore.swift:239-257 (transient-RBAC-error no longer fail-closes flags once initialized). Verified live 2026-06-19." `status = 'resolved'` after Step 2 (pending App Store ship). No code commit.

**Blast radius:** None.

---

## Task 3: Billable rollup — distinguish null from $0 (`588b3e19`)

**Files:**
- Modify: `OPS/Services/HomeBillableThisWeekRollupEngine.swift:46-50`
- Modify: `OPS/Views/Home/HomeContentView.swift:605-608` (header render)
- Modify: `OPS/Services/.../HomeBillableThisWeekNotificationDispatcher.swift:139` (guard)
- Test: `OPSTests/.../HomeBillableThisWeekRollupTests.swift:62`

**Root cause (verified):** `totalKnownAmount` (`:46-50`) does `partial + (item.amount ?? 0)`, returning non-optional `Double`. `amountSource` (`:165-190`) returns `amount: nil` when a project has no draft invoice (`total > 0`) and no rankable estimate (`total > 0`). So "no value attached anywhere" and a genuine `$0` both render `$0`. (A real `$0` cannot occur today — both amount sources require `total > 0` — so `nil` cleanly means "no value.")

- [ ] **Step 1: Update the existing test to assert the corrected behavior**

`OPSTests/.../HomeBillableThisWeekRollupTests.swift:62` currently asserts the bug. Read the test, then change the unknown-value assertion:

```swift
// was: XCTAssertEqual(rollup.totalKnownAmount, 0)
XCTAssertNil(rollup.totalKnownAmount, "A project with no draft invoice and no rankable estimate must yield nil, not 0")
```

Add a sibling test asserting a known value still sums:

```swift
func test_totalKnownAmount_sumsOnlyKnownAmounts() {
    // Build a rollup with one candidate amount == 1200 and one amount == nil (no source).
    // Expect totalKnownAmount == 1200 (nil is excluded, not coerced to 0).
    XCTAssertEqual(rollup.totalKnownAmount, 1200)
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/HomeBillableThisWeekRollupTests`
Expected: FAIL (current `totalKnownAmount` is non-optional / returns 0).

- [ ] **Step 3: Make `totalKnownAmount` optional**

`HomeBillableThisWeekRollupEngine.swift:46-50`:

```swift
/// nil when NO candidate carries an amount (no value attached anywhere) —
/// distinct from a genuine 0. Renders as the em-dash empty state.
var totalKnownAmount: Double? {
    let known = allItems.compactMap(\.amount)
    return known.isEmpty ? nil : known.reduce(0, +)
}
```

- [ ] **Step 4: Render the em-dash empty state**

`HomeContentView.swift:605` — replace the unconditional `currency(...)` with the optional map (keep the existing `dataValueLg` / `monospacedDigit()` JetBrains-Mono treatment):

```swift
Text(rollup.totalKnownAmount.map(currency) ?? "—")
    .font(OPSStyle.Typography.dataValueLg)
    .foregroundColor(OPSStyle.Colors.text)
    .monospacedDigit()
```

(`"—"` is the OPS empty-state token. Per-row display at `:672-677` already does `if let amount = item.amount` and is correct — leave it.)

- [ ] **Step 5: Fix the notification dispatcher guard**

`HomeBillableThisWeekNotificationDispatcher.swift:139` — unwrap before comparing so null suppresses the amount subtitle:

```swift
guard let amount = rollup.totalKnownAmount, amount > 0 else { /* suppress amount line */ }
```

(Apply to the `:142` usage too — use the unwrapped `amount`.)

- [ ] **Step 6: Run tests + build**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/HomeBillableThisWeekRollupTests` → Expected: PASS.
Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add OPS/Services/HomeBillableThisWeekRollupEngine.swift OPS/Views/Home/HomeContentView.swift OPS/Services/Home/HomeBillableThisWeekNotificationDispatcher.swift OPSTests/Home/HomeBillableThisWeekRollupTests.swift
git commit -m "fix(home): treat billable-this-week with no attached value as null, not \$0"
```
(Confirm the exact dispatcher/test paths with `git status` before staging.)

**Blast radius:** `totalKnownAmount` has 3 consumers — header (fixed), dispatcher (fixed), and the card-visibility gate at `HomeContentView.swift:264-266` keys on `hasItems` (project count), NOT amount, so the card still shows when projects exist but none has a value — now with `—` instead of a misleading `$0`. That is the intended outcome.

---

## Task 4: Note delete must persist through the sync queue (`f9e00eb9`)

**Files:**
- Modify: `OPS/ViewModels/ProjectNotesViewModel.swift:400-439` (`deleteNote`)
- Modify: `OPS/Network/Sync/InboundProcessor.swift:1296-1342` (`mergeProjectNote`) and `:521-557` (`acceptableFields`)
- Reference (read first): `OPS/DataController.swift` `recordOperation(...)` / the `SyncOperation` enqueue API used by `updateProjectFields`

**Root cause (verified):** `deleteNote` sets `note.deletedAt = Date()`, saves locally, and calls `repo.softDelete` fire-and-forget — it enqueues **no** `SyncOperation`. The inbound merge gate (`acceptableFields`) only protects fields named on a pending op; with none, the next inbound sync overwrites local `deletedAt` back to `nil` (`InboundProcessor.swift:1327`) and the note reappears. RLS is NOT the cause (`company_isolation ON project_notes FOR ALL TO public` covers anon). Secondary: the gate keys on the Swift name `"deletedAt"` while pending ops store wire names (`"deleted_at"`) — same class as the prior projects bug `209281ba`.

- [ ] **Step 1: Read the enqueue API**

Read `DataController.swift` around `recordOperation` and how `updateProjectFields` enqueues a `SyncOperation` (entity, id, changed fields as **wire** names). Note the exact signature so Step 2 mirrors it.

- [ ] **Step 2: Route the soft-delete through the durable queue**

`ProjectNotesViewModel.swift:400-439` — after setting `note.deletedAt` and saving locally, enqueue a durable op for the `deleted_at` field instead of (or in addition to) the direct `repo.softDelete`, so it retries until the server confirms AND the inbound gate protects the local tombstone:

```swift
note.deletedAt = Date()
note.needsSync = true
if let context = modelContext { try? context.save() }
loadNotesFromLocal()
// Durable, gate-protected soft-delete (mirror updateProjectFields' enqueue):
syncEngine.recordOperation(entity: .projectNote, id: note.id, changedFields: ["deleted_at"])
```
(Use the exact `recordOperation` signature found in Step 1. Keep the immediate `repo.softDelete` only if the queue does not itself perform the PostgREST write — otherwise the queue is the single writer.)

- [ ] **Step 3: Align the merge-gate field name + never resurrect a tombstone**

`InboundProcessor.swift` — in `acceptableFields` (`:521-557`) ensure the protected field name matches the wire name `"deleted_at"` (mirror the `209281ba` fix). In `mergeProjectNote` (`:1296-1342`), refuse to clear a locally-set tombstone:

```swift
// Never resurrect a row the client tombstoned locally.
if existing.deletedAt != nil && dto.deletedAt == nil { /* keep existing.deletedAt */ }
else { existing.deletedAt = dto.deletedAt }
```

- [ ] **Step 4: Exclude soft-deleted rows in the full fetch**

Confirm `fetchAll` (`ProjectNoteRepository`) excludes `deleted_at IS NOT NULL` the way `fetchForProject` already does, so a tombstoned note is never re-pulled.

- [ ] **Step 5: Verify**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → BUILD SUCCEEDED.
Runtime: create a note, delete it, force a sync (background/foreground), confirm it stays gone; repeat offline → delete → reconnect → confirm it syncs the deletion and does not reappear.

- [ ] **Step 6: Commit**

```bash
git add OPS/ViewModels/ProjectNotesViewModel.swift OPS/Network/Sync/InboundProcessor.swift
git commit -m "fix(project-notes): persist note soft-delete via sync queue so it survives inbound merge"
```

**Blast radius:** `mergeProjectNote` + `acceptableFields` are shared by all inbound note merges; the tombstone-guard is conservative (only blocks nil-resurrection). Verify other note flows (create/edit) still merge.

---

## Task 5: Day sheet picks up month-view events (`759530e1`)

**Files:**
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift` — `MonthGridCache` (`:65-224`) and `DayDetailsSheet` (`:1494-1681`, esp. `:1502-1515`)

**Root cause (verified):** Grid bars render straight from `cache.events(for: date)` (`:478`), but the month `DayDetailsSheet` takes the same previews and re-resolves each via `dataController.getTask(id:)` (`:1512`), dropping every nil. `getTask` is a fresh `FetchDescriptor` requiring an exact id match + live `modelContext`; the cache was built by `getAllScheduledTasks` (company/permission-filtered), so the unguarded per-id re-fetch can return nil → empty sheet despite visible badges. (Week mode is handed already-resolved `[ProjectTask]`, so it works.)

- [ ] **Step 1: Have the cache retain resolved tasks**

In `MonthGridCache`, when building the per-day previews, also retain the resolved `ProjectTask` references (or a map `eventId -> ProjectTask`). Expose:

```swift
func tasks(for date: Date) -> [ProjectTask] // returns the SAME resolved tasks that produced the badges
```
Key it with the existing local `yyyy-MM-dd` formatter (`:219-223`) — do not introduce a second date key.

- [ ] **Step 2: Make the sheet read from the cache, not re-fetch**

`MonthGridView.swift:1506-1515` — replace the `compactMap { dataController.getTask(id:) }` resolution with the cache's resolved set:

```swift
private var scheduledTasks: [ProjectTask] { cache.tasks(for: date) }
```

- [ ] **Step 3: Add a debug assertion to catch future drops**

Where the sheet computes its task list, assert parity with the previews in DEBUG:

```swift
#if DEBUG
assert(!(eventPreviews.count > 0 && scheduledTasks.isEmpty),
       "Day sheet dropped events that the grid rendered — cache/resolve mismatch")
#endif
```

- [ ] **Step 4: Verify**

Build (`generic/platform=iOS`) → BUILD SUCCEEDED. Runtime: Calendar → Month view on a day that shows badges → open the day sheet → confirm the same events appear (count matches the badges). Cross-check Week mode still works.

- [ ] **Step 5: Commit**

```bash
git add "OPS/Views/Calendar Tab/MonthGridView.swift"
git commit -m "fix(calendar): day sheet reads resolved tasks from month cache so month-view events appear"
```

**Blast radius:** `MonthGridCache` is month-view-only; retaining task refs raises its memory footprint marginally. No change to week/day modes.

---

## Task 6: Search deep links — collapse sibling sheets (`dc74f393`)

**Files (READ all cited ranges before editing):**
- Modify: `OPS/Views/MainTabView.swift:451-509` (four sibling `.sheet` modifiers)
- Modify: `OPS/AppState.swift:60-190` (deep-link publishers; the `pendingRailDeepLink` baton pattern at `:67-73`)
- Modify: `OPS/Views/JobBoard/UniversalSearchSheet.swift:1154-1188` (navigate funcs)

**Root cause (verified):** `MainTabView` hangs four `.sheet` modifiers off the same view — `showingUniversalSearch` (`:451`), `showClientDetails` (`:465`), `showInvoiceDetails` (`:475`), `showEstimateDetails` (`:491`). SwiftUI reliably presents only ONE sheet per presenter; the later siblings are silently dropped. Project/Task escape this because they route via `NotificationCenter` + `activeProjectID`, not a sibling sheet. So **Client, Invoice, and Estimate are all broken** (the ticket only noticed Client). The `DispatchQueue.main.asyncAfter(0.4)` in the navigate funcs is also a race, not a guarantee. (Commit `5c5da9f7` moved the collision to the root rather than removing it.)

- [ ] **Step 1: Define one deep-link enum + single state**

In `AppState.swift`, add:

```swift
enum RootDeepLink: Identifiable {
    case client(id: String)
    case invoice(id: String)
    case estimate(id: String)
    var id: String {
        switch self {
        case .client(let id):   return "client-\(id)"
        case .invoice(let id):  return "invoice-\(id)"
        case .estimate(let id): return "estimate-\(id)"
        }
    }
}
@Published var rootDeepLink: RootDeepLink?
```
Keep the existing `viewClientDetailsById` / invoice / estimate entry points but have them set `rootDeepLink = .client(id:)` etc. (route through one path).

- [ ] **Step 2: Replace the three sibling sheets with one `.sheet(item:)`**

`MainTabView.swift:465-509` — delete the three separate `.sheet(isPresented:)` for client/invoice/estimate and present one item-driven sheet (leave the universal-search sheet at `:451` as-is, it's the source):

```swift
.sheet(item: $appState.rootDeepLink) { link in
    switch link {
    case .client(let id):   ContactDetailView(clientId: id)
    case .invoice(let id):  InvoiceDetailView(invoiceId: id)
    case .estimate(let id): EstimateDetailView(estimateId: id)
    }
}
```
(Match the real initializer signatures of the existing detail views — read `:465-509` for how each is currently constructed, e.g. `ContactDetailView(client:project:)`, and adapt the cases to fetch-by-id or pass the resolved model exactly as today.)

- [ ] **Step 3: Hand off deterministically (kill the 0.4s race)**

`UniversalSearchSheet.swift:1154-1188` — the navigate funcs currently `dismiss()` then `asyncAfter(0.4)`. Replace the timer with the search sheet's `onDismiss` baton (mirror `AppState.pendingRailDeepLink`, `:67-73`): on tap, set a `pendingRootDeepLink`, call `dismiss()`, and in the universal-search sheet's `.sheet(onDismiss:)` flush `pendingRootDeepLink` into `appState.rootDeepLink`. This presents the target only AFTER the search sheet is fully gone — no sibling collision, no timing guess.

- [ ] **Step 4: Verify each entity route**

Build (`generic/platform=iOS`) → BUILD SUCCEEDED. Runtime: open universal search; tap a Client, an Invoice, an Estimate, a Project, and a Task result in turn — confirm each opens its detail. Confirm Team/Inventory/Catalog (the in-search enum sheet) still work.

- [ ] **Step 5: Commit**

```bash
git add OPS/AppState.swift OPS/Views/MainTabView.swift OPS/Views/JobBoard/UniversalSearchSheet.swift
git commit -m "fix(search): route client/invoice/estimate deep links through one item-sheet to stop sibling-sheet drops"
```

**Blast radius:** Touches root presentation in MainTabView — exercise every other root sheet (notification-rail deep links, etc.) to confirm none regressed. This intentionally also fixes Invoice + Estimate deep links (same defect); note that in the ticket.

---

## Task 7: Shake-to-report must stay armed (`70087050`)

**Files:**
- Modify: `OPS/ContentView.swift:655-700` (the `Group` that swaps MainTabView / AppMessageView / SubscriptionLockoutView) and `:985-987` / `:1049-1057` (the `.onReceive(.deviceDidShake)` + gating)
- Reference: `OPS/Services/BugReport/ShakeDetection.swift:14-25`, `BugReportPresenter.swift` (presentation side is already robust)

**Root cause (verified):** `UIWindow.motionEnded` always posts `.deviceDidShake`. But the SwiftUI `.onReceive(.deviceDidShake)` observer is attached inside the conditional `MainTabView` subtree (`ContentView.swift:985`, within the `Group` at `:657`). When `activeAppMessage`/`shouldShowLockout` flip and the `Group` swaps to `AppMessageView`/`SubscriptionLockoutView`, the MainTabView subtree — and its observer — leaves the hierarchy, so shakes post into the void and never re-arm. Secondary gates: `guard dataController.isAuthenticated` (`:1057`) and `if appState.shouldRestartTutorial` (`:1049`).

- [ ] **Step 1: Move the observer to an always-present root**

Attach `.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake))` to the **outermost** always-rendered container in `ContentView` (outside the `Group` that swaps subtrees), so it stays mounted regardless of app-message/lockout state. Keep `handleShake()` as the handler.

- [ ] **Step 2: Keep gating correct at handler level**

Within `handleShake()`, retain the auth/tutorial guards but ensure they don't permanently disarm: they should skip presentation for the current shake only (they already early-return per-call, which is fine once the observer itself is always mounted). Confirm no path sets a flag that suppresses future shakes.

- [ ] **Step 3 (defensive): re-arm on foreground**

`ContentView.swift:684` (`didBecomeActiveNotification`) currently only resets wizard tracking. No re-subscribe is needed once Step 1 makes the observer permanent, but verify there is no second motion-handling path tied to a view that gets covered by the `CustomTabBar` ZStack overlay (the tab bar is a manual overlay ~100pt; it must not swallow the global motion event — it doesn't today, but confirm).

- [ ] **Step 4: Verify**

Build (`generic/platform=iOS`) → BUILD SUCCEEDED. Runtime: shake → reporter appears. Then trigger an app-message/lockout state and dismiss it (or simulate a subscription-state change), use the app a while, shake again → reporter still appears.

- [ ] **Step 5: Commit**

```bash
git add OPS/ContentView.swift
git commit -m "fix(bug-report): mount shake observer at always-present root so it survives app-message/lockout swaps"
```

**Blast radius:** Moving one `.onReceive` up the tree; presentation side (`BugReportPresenter`) unchanged and already guarded.

---

## Task 8: Scheduling perf — stop the render storm (`b954065e`)

**Files (READ all cited ranges before editing):**
- Modify: `OPS/DataController.swift:3852-3957` (`updateTaskSchedule`), `:4257-4310` (`recalculateTaskIndices`), `:2394-2410` (`getAllScheduledTasks`)
- Modify: `OPS/ViewModels/CalendarViewModel.swift:420-480` (full-table fetch + `objectWillChange.send()`)
- Modify: `OPS/Views/Calendar Tab/MonthGridView.swift:71-110` (`loadEvents`) and observer at `:832`
- Modify: `OPS/Views/.../ScheduleView.swift:172` (observer)
- Reference: `OPS/.../DataActor.swift` (existing background `ModelActor`)

**Root cause (verified):** One date edit in `updateTaskSchedule` toggles the global `@Published scheduledTasksDidChange` at `:3882` and again inside `recalculateTaskIndices` (`:4257`, which also does a second `modelContext.save()` over every task). Each toggle fans out to ≥3 always-subscribed views — `ScheduleView` (`:172`), `MonthGridView` (`:832`), `CalendarDaySelector` (`:132`) — each running an **unindexed** `context.fetch(FetchDescriptor<ProjectTask>())` over the entire task table plus an O(days) rebuild, all on the main thread, even while ProjectDetails covers the calendar tab. On a real company's task volume this is repeated multi-hundred-ms main-thread stalls → "glitches out and slows down."

- [ ] **Step 1: Coalesce the refresh signal to once per logical change**

In `updateTaskSchedule`, remove the mid-operation toggle at `:3882`; fire `scheduledTasksDidChange` exactly once at the end (after `recalculateTaskIndices`). Remove the duplicate toggle inside `recalculateTaskIndices`. Add a debounce on the publisher (e.g. `.debounce(for: .milliseconds(150), scheduler: RunLoop.main)`) at the subscription sites so a save + index recalc collapses to one refresh.

- [ ] **Step 2: Narrow the fetches with a predicate**

`getAllScheduledTasks` (`:2394`) and `CalendarViewModel.rebuildWeekCache` (`:460`) must fetch with a `#Predicate<ProjectTask>` bounded by `startDate != nil`, the visible date window, and `companyId`, instead of fetching the whole table and `.filter`-ing in memory. Push the filter into the `FetchDescriptor`.

- [ ] **Step 3: Move the fetch + rebuild off the main thread**

Run the windowed fetch + cache rebuild on the existing background `ModelActor` (`DataActor`), returning only the lightweight `ScheduledTaskPreview`/id arrays to the main actor. Keep `CalendarMirrorService.mirrorEvent` and the notification/OneSignal fan-out (`:3904-3945`) off the save's critical section (they already use `Task {}` — ensure they don't block the toggle).

- [ ] **Step 4: Replace the broad `objectWillChange.send()`**

`CalendarViewModel.swift:446` `self.objectWillChange.send()` invalidates everything bound to the VM. Publish only the changed cache slice (e.g. update an `@Published` keyed cache) so SwiftUI invalidates the affected day cells, not the whole VM.

- [ ] **Step 5: Gate observers by visibility**

The `.onChange(of: scheduledTasksDidChange)` handlers in `ScheduleView`/`MonthGridView` fire even when ProjectDetails covers the calendar tab. Mark caches dirty on the signal and reload on `.onAppear` instead of eagerly reloading off-screen.

- [ ] **Step 6: Verify (build + manual perf)**

Build (`generic/platform=iOS`) → BUILD SUCCEEDED. Runtime on a seeded company with many tasks: schedule a job from ProjectDetails and confirm no main-thread stall/jank; the calendar reflects the change after returning to it. If Instruments is available, confirm the all-tasks `fetch` no longer fires on the schedule action.

- [ ] **Step 7: Commit**

```bash
git add OPS/DataController.swift OPS/ViewModels/CalendarViewModel.swift "OPS/Views/Calendar Tab/MonthGridView.swift" OPS/Views/Calendar/ScheduleView.swift
git commit -m "perf(calendar): coalesce schedule refresh, scope task fetch, and move rebuild off main thread"
```
(Confirm exact ScheduleView path with `git status` before staging.)

**Blast radius:** Highest of the set — `scheduledTasksDidChange` and `getAllScheduledTasks` are shared by every calendar surface (Schedule tab, month grid, day selector, job board). Regression-test all calendar views after this change: events still appear, week/month/day all refresh after a schedule edit, and the job board reflects scheduling. Do this task LAST and in isolation.

---

## Self-Review

**Spec coverage:** All 8 active iOS `bug_reports` rows are addressed — `3911ed80` (T1), `d5c899e6` (T2), `588b3e19` (T3), `f9e00eb9` (T4), `759530e1` (T5), `dc74f393` (T6, +Invoice/Estimate), `70087050` (T7), `b954065e` (T8). No gaps.

**Placeholder scan:** No TODO/"handle later" steps. Two tasks (T6, T8) intentionally instruct "read cited ranges before editing" because their final code must match live initializer/observer signatures I have not fully read — these are precise change-specs with current-code anchors and verified root causes, not placeholders. Flagged explicitly so the executor reads first rather than guesses.

**Type consistency:** `totalKnownAmount` is `Double?` everywhere after T3 (engine, header render, dispatcher, tests). `RootDeepLink` (T6) is defined once in `AppState` and consumed in `MainTabView`. `cache.tasks(for:)` (T5) is the new symbol used by `DayDetailsSheet`. Soft-delete protected field name is the wire name `"deleted_at"` in both the enqueue (T4 Step 2) and the gate (T4 Step 3).

**Honesty notes:** T1 and T2 are verifications (already correct/fixed in the live tree) — no fabricated fix work. iOS UI bugs without a unit-test seam (T5–T8) use simulator build + runtime walkthrough for verification; only T3 has a true TDD loop (an existing test asserts the bug). "Resolved" status changes are gated on runtime verification and App Store ship lag.

---

## Execution Handoff

Plan saved to `ops-ios/docs/superpowers/plans/2026-06-19-ios-defect-fixes.md`.
