# Leads Auto-Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task (the OPS-tuned executor — NOT `superpowers:executing-plans`).

**Goal:** Leads in the iOS app update automatically — live while the LEADS tab is open, on return from background, and via pull-to-refresh — instead of only when the tab remounts.

**Architecture:** Keep the existing direct-fetch model (PipelineViewModel → OpportunityRepository → REST). Add three freshness triggers that all funnel into one debounced, coalesced, merge-based reload: (1) Supabase Realtime subscriptions for `opportunities`, `activities`, `follow_ups` that post a NotificationCenter event (mirroring the existing `expenses` pattern — no SwiftData merge, no sync-engine integration); (2) a foreground-resume listener; (3) `.refreshable`. The reload merges server rows **into the existing `Opportunity` instances by id** (reference types) so the pushed `LeadDetailView` updates in place and list identity stays stable.

**Tech Stack:** SwiftUI (iOS 17.6 target), Supabase Swift Realtime V2, XCTest. No new dependencies.

**Design System:** No new visual elements. Pull-to-refresh uses the system control; all existing styling untouched. `OPS/Styles/OPSStyle.swift` is the token source if anything visual comes up. No user-facing copy is added (no ops-copywriter pass needed).

**Required Skills:** `custom-skills:executing-plans`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `superpowers:systematic-debugging` (on any failure). UI impact is nil-to-trivial; if any visual judgment call arises, load `custom-skills:mobile-ux-design` + `ops-design` before deciding.

---

## Context — root cause this plan fixes (verified 2026-07-03)

Bug record: `bug_reports` row `0b7e9b17-8ded-43d8-9c40-01d85dc5a4bf` (Supabase project `ijeekuhbatykdomumfjx`).

`opportunities` participates in **no** automatic freshness mechanism:
- Not a `SyncEntityType` (`OPS/Network/Sync/SyncTypes.swift`) → excluded from full/delta/background sync. **This plan deliberately keeps it that way.**
- Not subscribed in `RealtimeProcessor` → no live events, even though the server side is fully ready (verified in prod: `opportunities`, `activities`, `follow_ups` are ALL in the `supabase_realtime` publication, ALL `REPLICA IDENTITY FULL`, ALL have `company_id`).
- Foreground resume (`performActiveChecks` in `OPS/OPSApp.swift:480`) never reloads leads; `LeadsTabView`'s `.task` does not refire on resume because the view hierarchy survives backgrounding.
- No `.refreshable` anywhere under `OPS/Views/Leads/`.

Leads load only when `MainTabView`'s `.id(selectedTab)` remounts `LeadsTabView` (`.task` → `PipelineViewModel.loadData()`) or after a same-device mutation (the nine `Lead*Success` NotificationCenter listeners).

Triage buckets (`PipelineViewModel.triageBuckets`) derive **entirely** from denormalized fields on the opportunities row (`nextFollowUpAt`, `lastMessageDirection`, `stage`, `lastActivityAt`…). Subscribing `activities` + `follow_ups` too costs nothing (same debounced reload) and covers any web write path that touches a child table without bumping the parent row.

## Non-goals (do NOT do these)

- Do NOT add `opportunity` to `SyncEntityType` / `InboundProcessor.syncOrder` / SwiftData persistence. The direct-fetch model stays.
- Do NOT change the nine existing `Lead*Success` listener semantics beyond what the merge-based `loadData` inherently improves.
- Do NOT pop or dismiss `activeSheet` on remote changes (a user mid-edit keeps their sheet; server conflict handling is out of scope).
- Do NOT touch `stage_transitions` subscriptions — the reload refetches transitions anyway.

## Hard constraints (read before any edit)

1. **Sibling-session WIP in the working tree.** `OPS/OPSApp.swift`, `OPS.xcodeproj/project.pbxproj`, `OPSTests/Views/TabBarSnapshotTests.swift`, and `.DS_Store` have pre-existing uncommitted changes that are NOT yours. Never edit, stage, stash, or revert them. Stage your commits **by explicit file path only** — never `git add -A` / `git add .`.
2. **Line endings.** `OPS/Network/Sync/RealtimeProcessor.swift` has MIXED CRLF/LF line terminators. Make surgical `Edit`-tool string replacements only; never rewrite the file wholesale; match the exact bytes of the surrounding context. `LeadsTabView.swift` and `PipelineViewModel.swift` are plain LF.
3. **New files need no pbxproj edit.** The project uses file-system-synchronized groups (verified) — create Swift files in place and the target picks them up. Do not open/edit `project.pbxproj`.
4. **Build/test etiquette.** Before any `xcodebuild`, run `ps aux | grep xcodebuild | grep -v grep`. If another build is running, pass a session-local `-derivedDataPath` (e.g. `.dd-leads-refresh`, and add it to nothing — it's throwaway; delete it when done). Build verification: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build`. Tests: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
5. **Commits on `main`, atomic, conventional style, no AI attribution, NO PUSH** (pushing requires Jackson's explicit go).
6. **RealtimeProcessor warning is law:** every table subscribed client-side MUST be in the `supabase_realtime` publication or the whole channel fails. All three tables here are verified present (2026-07-03). Do not add any other table.

---

### Task 1: Merge-based reload + debounced refresh funnel in PipelineViewModel (TDD)

**Files:**
- Modify: `OPS/ViewModels/PipelineViewModel.swift`
- Modify: `OPS/DataModels/Supabase/Opportunity.swift` (add `apply(_:)`)
- Create: `OPSTests/PipelineViewModelMergeTests.swift`

**Step 1: Write the failing tests**

Create `OPSTests/PipelineViewModelMergeTests.swift`. Build test opportunities with the real `Opportunity` initializer (read `OPS/DataModels/Supabase/Opportunity.swift` for the memberwise init the model actually has — construct instances the same way `toModel()` does; if the init is long, add a small local factory helper in the test file). Cover, at minimum:

```swift
import XCTest
@testable import OPS

final class PipelineViewModelMergeTests: XCTestCase {

    // 1. Existing id → SAME instance survives (===) with fields updated.
    func testMergeUpdatesExistingInstanceInPlace() {
        let current = makeOpportunity(id: "a", stage: .newLead, contactName: "Old Name")
        let fresh   = makeOpportunity(id: "a", stage: .quoted,  contactName: "New Name")
        let merged  = PipelineViewModel.merge(existing: [current], incoming: [fresh])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0] === current)          // identity preserved
        XCTAssertEqual(merged[0].stage, .quoted)      // field applied
        XCTAssertEqual(merged[0].contactName, "New Name")
    }

    // 2. New id → appended as the incoming instance.
    func testMergeInsertsNewLead() { /* incoming id "b" not in existing → present in result */ }

    // 3. Missing id → dropped from result (server-deleted/merged lead disappears).
    func testMergeDropsRemovedLead() { /* existing id "gone" absent from incoming → absent from result */ }

    // 4. Result preserves INCOMING order (server sort = created_at desc).
    func testMergePreservesIncomingOrder() { }

    // 5. apply(_:) copies every triage-critical field.
    func testApplyCopiesTriageFields() {
        // stage, stageEnteredAt, nextFollowUpAt, lastActivityAt, lastMessageDirection,
        // correspondenceCount, inboundCount, outboundCount, lastInboundAt, lastOutboundAt,
        // estimatedValue, actualValue, projectId, archivedAt, deletedAt, updatedAt,
        // contactName/Email/Phone, title, assignedTo, expectedCloseDate, actualCloseDate,
        // lostReason, lostNotes, tags, winProbabilityOverride, stageManuallySet, priority,
        // source, quoteDeliveryMethod, descriptionText, address, clientId, sourceEmailId, createdAt
        // Assert a representative spread — EVERY stored property listed in Opportunity.swift
        // must be assigned in apply(); the test asserts the high-risk ones individually.
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/PipelineViewModelMergeTests 2>&1 | tail -20`
Expected: FAIL — `merge`/`apply` don't exist yet. (If simulator OS differs, list available with `xcrun simctl list devices available` and use the installed iPhone 17 runtime.)

**Step 3: Implement `Opportunity.apply(_:)`**

In `OPS/DataModels/Supabase/Opportunity.swift`, add below the computed-property section:

```swift
    // MARK: - Field copy (realtime refresh)

    /// Copies every stored property from `other` onto self. Used by the LEADS
    /// reload merge so the SAME instance survives a refresh — the pushed
    /// detail screen observes these writes and re-renders in place.
    /// Keep in lockstep with the stored-property list above: a field missed
    /// here silently never refreshes.
    func apply(_ other: Opportunity) {
        companyId = other.companyId
        title = other.title
        contactName = other.contactName
        // … EVERY stored property in declaration order (id excluded) …
        updatedAt = other.updatedAt
    }
```

Write the complete assignment list — every stored property in the class except `id`, in declaration order, none skipped.

**Step 4: Implement `merge` + refresh funnel in PipelineViewModel**

Add to `PipelineViewModel`:

```swift
    // MARK: - Remote-change refresh (debounced, coalesced, merge-based)

    /// True once the initial `.task` load has populated the surface. Remote/
    /// foreground triggers before that are no-ops — the initial load owns cold start.
    private(set) var hasLoadedOnce = false
    private var pendingRefreshTask: Task<Void, Never>?
    private var isLoadInFlight = false
    private var needsFollowUpLoad = false

    /// Single funnel for every automatic trigger (realtime burst, foreground).
    /// Trailing debounce collapses event storms into one fetch; the in-flight
    /// coalescer guarantees a fetch STARTED before the last event completes
    /// re-runs once more so no change is missed.
    func scheduleRefresh(debounce: Duration = .milliseconds(1500)) {
        guard hasLoadedOnce else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.refreshCoalesced()
        }
    }

    private func refreshCoalesced() async {
        if isLoadInFlight { needsFollowUpLoad = true; return }
        isLoadInFlight = true
        await loadData(silent: true)
        isLoadInFlight = false
        if needsFollowUpLoad {
            needsFollowUpLoad = false
            await refreshCoalesced()
        }
    }

    /// Identity-preserving merge. Existing instances are mutated via `apply`
    /// (reference semantics keep the pushed detail screen live); order follows
    /// `incoming` (server sort); ids absent from `incoming` drop out.
    static func merge(existing: [Opportunity], incoming: [Opportunity]) -> [Opportunity] {
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return incoming.map { fresh in
            if let current = byId[fresh.id] {
                current.apply(fresh)
                return current
            }
            return fresh
        }
    }
```

Change `loadData()` to `loadData(silent: Bool = false)`:
- `silent == false` (initial `.task` load and the nine `Lead*Success` listeners — unchanged call sites): current behavior, `isLoading` flips.
- `silent == true`: skip both `isLoading` writes (no skeleton/spinner flash over live content) but still record `loadError`.
- Replace `allOpportunities = oppDtos.map { $0.toModel() }` with `allOpportunities = Self.merge(existing: allOpportunities, incoming: oppDtos.map { $0.toModel() })` — the reassignment fires `@Published` so the list recomputes; the merged-in-place instances keep the detail screen live.
- `allStageTransitions` keeps wholesale replacement.
- Set `hasLoadedOnce = true` on success.
- Cancel `pendingRefreshTask` in `deinit`.

Then verify where `isLoading` is read (grep `viewModel.isLoading` under `OPS/Views/Leads/`) and confirm silent refreshes cannot regress those states.

**Step 5: Run tests to verify they pass**

Run: same command as Step 2. Expected: PASS (all merge tests green).

**Step 6: Commit**

```bash
git add OPSTests/PipelineViewModelMergeTests.swift OPS/ViewModels/PipelineViewModel.swift OPS/DataModels/Supabase/Opportunity.swift
git commit -m "feat(leads): identity-preserving merge reload + debounced refresh funnel"
```

---

### Task 2: Realtime subscriptions for opportunities / activities / follow_ups

**Files:**
- Modify: `OPS/Network/Sync/RealtimeProcessor.swift` (MIXED line endings — surgical edits only)
- Modify: wherever `Notification.Name.expenseUpdated` is declared (grep `static let expenseUpdated` — add the new name beside it)

**Step 1: Declare the notification name**

Next to the existing realtime notification names:

```swift
    /// Posted by RealtimeProcessor on any opportunities / activities / follow_ups
    /// change. LEADS surfaces respond with a debounced re-fetch (PipelineViewModel
    /// .scheduleRefresh) — leads are deliberately outside the SwiftData sync engine.
    static let opsLeadsDidChange = Notification.Name("opsLeadsDidChange")
```

**Step 2: Subscribe the three tables**

In `companyFilteredTables` (`RealtimeProcessor.swift` ~line 204), append after `"deck_designs"` (all three verified in the `supabase_realtime` publication + REPLICA IDENTITY FULL + `company_id` column, 2026-07-03 — satisfying this file's publication warning):

```swift
        // LEADS live updates (2026-07-03, bug 0b7e9b17). Publication + REPLICA
        // IDENTITY FULL verified for all three. These are notification-only
        // tables — no SwiftData merge; LeadsTabView re-fetches via REST.
        "opportunities",
        "activities",
        "follow_ups"
```

**Step 3: Route events — every `switch table` in the file**

Run `grep -n "switch table" OPS/Network/Sync/RealtimeProcessor.swift` and add the SAME case to **every** switch it returns (expected: legacy `handleUpsert` ~line 922, legacy `handleDelete` ~line 1073, `dispatchUpsertToActor` ~line 1198, and the delete-side actor dispatch if one exists — cover them all; miss one and events on that path fall into `default:` and vanish). Place it beside the `case "expenses", "expense_batches":` idiom:

```swift
            case "opportunities", "activities", "follow_ups":
                NotificationCenter.default.post(name: .opsLeadsDidChange, object: nil)
```

These are notification-only (no DTO decode, no actor dispatch) exactly like expenses — confirm the actor-path comment ("Non-merge tables … bypass the actor entirely") stays accurate, and extend that comment to name the leads tables.

**Step 4: Build to verify**

Run: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED` (check for parallel xcodebuild first per constraint 4).

**Step 5: Commit**

```bash
git add OPS/Network/Sync/RealtimeProcessor.swift <file-declaring-notification-name>
git commit -m "feat(sync): realtime subscriptions for opportunities, activities, follow_ups"
```

---

### Task 3: Wire the triggers in LeadsTabView (realtime + foreground + pull-to-refresh)

**Files:**
- Modify: `OPS/Views/Leads/LeadsTabView.swift`

**Step 1: Add the two listeners**

After the existing `LeadDeletedSuccess` listener (~line 220):

```swift
        .onReceive(NotificationCenter.default.publisher(for: .opsLeadsDidChange)) { _ in
            viewModel.scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Catch-up on resume: realtime stops ~30s after backgrounding (OPSApp
            // scenePhase), so events during background are lost — this re-fetch
            // is the recovery path. Short debounce; the coalescer + hasLoadedOnce
            // guard make it a no-op on cold launch where .task owns the first load.
            viewModel.scheduleRefresh(debounce: .milliseconds(300))
        }
```

Add `import UIKit` if `UIApplication` doesn't resolve.

**Step 2: Pull-to-refresh**

On the `ScrollView` (~line 113), after `.scrollIndicators(.hidden)`:

```swift
                    .refreshable {
                        await viewModel.loadData(silent: true)
                    }
```

(System refresh control — no custom styling, no copy. iOS 17.6 target supports `.refreshable` on ScrollView.)

**Step 3: Handle a server-removed lead that's open in detail**

The merge drops leads deleted/merged/archived elsewhere; if one is open in `detailLead`, pop it rather than strand a dead screen:

```swift
        .onChange(of: viewModel.allOpportunities) { _, opportunities in
            if let open = detailLead, !opportunities.contains(where: { $0.id == open.id }) {
                detailLead = nil
            }
        }
```

If `onChange` on `[Opportunity]` needs `Equatable`, compare id sets instead (e.g. observe `viewModel.allOpportunities.map(\.id)` via a computed, or perform the check inside the `.onReceive(.opsLeadsDidChange)` flow after refresh completes — pick the cleanest compiling variant, do NOT add a broad `Equatable` conformance to the @Model class).

Leave `activeSheet` alone (mid-edit sheets stay; per non-goals).

**Step 4: Build**

Run: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

**Step 5: Full test suite (regression)**

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tail -30`
Expected: all green, including the new merge tests. If pre-existing failures unrelated to this change appear, record them verbatim in the final report — do not fix, do not hide.

**Step 6: Commit**

```bash
git add OPS/Views/Leads/LeadsTabView.swift
git commit -m "feat(leads): live refresh — realtime events, foreground catch-up, pull-to-refresh"
```

---

### Task 4: End-to-end proof against prod realtime

**Goal:** evidence, not hope. The realtime path must be observed working.

**Step 1: Boot the app in the simulator** (any signed-in dev/demo account whose company has leads). Navigate to LEADS. Capture the visible lead list (screenshot via `xcrun simctl io booted screenshot`).

**Step 2: Mutate a lead server-side** — with Supabase MCP `execute_sql` against project `ijeekuhbatykdomumfjx`, update a clearly visible field of a lead in the signed-in company (e.g. bump `contact_name` to `<name> LIVE-TEST` — ROLLBACK-SAFE: reuse the same statement to restore the exact original value afterward, and confirm restoration with a SELECT).

**Step 3: Observe** — within ~2s (debounce) the row updates WITHOUT touching the app. Screenshot the changed row. Console shows `[RealtimeProcessor] Event received - table=opportunities`.

**Step 4: Foreground catch-up** — background the app >35s (realtime torn down), mutate again server-side, foreground: row updates within ~1s. Screenshot.

**Step 5: Pull-to-refresh** — drag down, list refreshes without visual glitches under the pinned section header.

**Step 6: Restore the test data** (verify with SELECT) and save screenshots to `docs/artifacts/leads-refresh-proof-2026-07-03/` (NOT the repo root). If simulator sign-in is impossible (Firebase throttling — see CLAUDE.md gotcha), say so plainly in the report and downgrade the claim to "build + tests + code-trace verified; live realtime unobserved" — never claim observed behavior you didn't observe.

---

### Task 5: Bible + bug record

**Files:**
- Modify: `ops-software-bible/06_TECHNICAL_ARCHITECTURE.md` — RealtimeProcessor entry (~line 185) says "(9 entity types)": update the count and enumerate the leads tables + the notification-only pattern; update the PipelineViewModel line (~202) to mention merge-based auto-refresh.
- Modify: any other bible file `grep -ril "companyFilteredTables\|RealtimeProcessor" ops-software-bible/` surfaces with a stale table list (07_SPECIALIZED_FEATURES.md documents pipeline/realtime — check it).
- Update Supabase `bug_reports` row `0b7e9b17-8ded-43d8-9c40-01d85dc5a4bf`: on start set `status='in_progress'`, `claimed_at=now()`; when verified set `status='resolved'`, `resolved_at=now()`, `fixed_at=now()`, `fix_commit=<sha of Task 3 commit>`, `fix_notes`/`resolution_notes` = one-paragraph summary + proof pointer.

**Commit (bible repo is part of the OPS root — commit wherever the file lives per that directory's convention):**

```bash
git add 06_TECHNICAL_ARCHITECTURE.md [others]
git commit -m "docs(bible): leads realtime subscriptions + merge-based refresh model"
```

---

### Final report requirements (back to the orchestrator)

1. Commit SHAs + one-line description each.
2. Test output tail (new tests + full suite) verbatim.
3. Build result line.
4. The Task 4 evidence: screenshots paths + what each shows, or the explicit downgraded claim.
5. Any pre-existing failures/oddities encountered, verbatim.
6. Confirmation the sibling WIP files were never staged (`git status --porcelain` snapshot at end).
