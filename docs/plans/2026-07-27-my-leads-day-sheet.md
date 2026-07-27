# MY LEADS — Delegate Day Sheet · Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task (OPS-tuned; enforces design-system compliance). Delegate code-writing subtasks to `model: "opus"` agents per standing convention.

**Goal:** Assigned-scope users opening the LEADS tab get the day sheet — their leads grouped by whose move it is, expandable rows with contact/photos/deck/summary, and a stage-aware milestone button — instead of the owner console.

**Architecture:** `LeadsTabView` branches on `leadAccessPolicy.scope(for: .view)`. The day sheet consumes the existing `PipelineViewModel` (fetch, realtime debounce, `TriageBucket` cadence) through a new pure presentation transform; no cadence fork. Milestone presses stamp an activity and advance the stage through the existing `move_opportunity_stage` path with a 5-second undo. Offline reads come from a JSON snapshot cache; writes queue and drain on the app's existing connectivity triggers.

**Tech Stack:** SwiftUI (iOS 17.6 target), Supabase repos (no SwiftData for leads), XCTest + the UIWindow/drawHierarchy snapshot harness.

**Design System:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; iOS tokens in `OPS/Styles/OPSStyle.swift`. Zero hardcoded color/spacing/radius/font values.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design` (reference), `animation-studio:animation-architect` + `animation-studio:ios-animations` (Task 10), `ops-copywriter` (copy is LOCKED in spec §8 — do not invent strings), `custom-skills:audit-design-system` (Task 11), `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

**Spec (authoritative):** `docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md`. Mock reference: session board `day-sheet-proof.png` (Jackson-approved). Where this plan and the spec disagree, the spec wins.

---

## Ground rules (read before Task 0)

- Work in a dedicated worktree on branch `feat/my-leads-day-sheet` (large feature ⇒ own branch). Copy `OPS/Utilities/Secrets.xcconfig` in; build with `-clonedSourcePackagesDirPath .spm-local`; isolated `-derivedDataPath .dd-daysheet`. Check `ps aux | grep xcodebuild` before builds — siblings run in parallel.
- Xcode uses file-system-synchronized groups: new `.swift` files auto-include. **Never edit `project.pbxproj`.**
- Preserve CRLF line endings on files that have them.
- `PermissionStore` fails closed before hydration — views read the **injected** `@EnvironmentObject`, never `PermissionStore.shared` (blank-preview trap).
- `ContactDetailView`-class type-checker trap: keep every added section a small computed `@ViewBuilder var`; reference as one token.
- Atomic commits per task, conventional messages, **no AI attribution**. Commit; never push.
- Copy strings come verbatim from spec §8. Numbers mono (`OPSStyle` mono font tokens), `—` for empty, no exclamation points, no emoji.

## Task 0 — Preflight

1. Read the spec top to bottom. Read `DESIGN.md`, `mobile/MOBILE.md`.
2. Read these files fully (they are the reuse surface): `OPS/Utilities/LeadAccessPolicy.swift`, `OPS/ViewModels/PipelineViewModel.swift`, `OPS/Views/Leads/LeadsTabView.swift`, `OPS/Views/Leads/Triage/LeadTriageCard.swift`, `OPS/Services/LeadQuickTouchLogger.swift`, `OPS/Services/LeadImageService.swift`, `OPS/Views/Leads/Components/LeadDeckSection.swift`, `OPS/Views/Leads/Components/LeadStatusMenu.swift`, `OPS/Map/Views/ProjectLocationSnapshotView.swift`, `OPS/ViewModels/ClientLeadsViewModel.swift` (the approved pure-`apply()` + preview-seam pattern), `OPS/DataModels/Supabase/Opportunity.swift`, `OPS/DataModels/Enums/PipelineStage.swift`.
3. Locate the stage-move call path: `grep -rn "move_opportunity_stage" OPS/` — note the repository method and its optimistic-update/echo behavior.
4. Worktree + build sanity: `xcodebuild build-for-testing -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-daysheet` → BUILD SUCCEEDED before any edit.

## Task 1 — `LeadMilestoneEngine` (pure verb map)

**Files:** Create `OPS/Services/LeadMilestoneEngine.swift` · Test `OPSTests/Services/LeadMilestoneEngineTests.swift`

Complete implementation (adjust only if `PipelineStage` API differs on read):

```swift
/// Spec §4 — the next real-world event worth stamping, per stage.
/// A stamp advances the stage as a consequence; it is never a picker.
enum LeadMilestone: Equatable {
    case contacted        // new_lead   -> qualifying
    case siteVisited      // qualifying -> quoting
    case quoteSent        // quoting    -> quoted
    case won              // quoted / follow_up / negotiation -> won flow

    var label: String {
        switch self {
        case .contacted:   return "CONTACTED"
        case .siteVisited: return "SITE VISITED"
        case .quoteSent:   return "QUOTE SENT"
        case .won:         return "WON"
        }
    }

    var confirmationLabel: String {
        switch self {
        case .contacted:   return "CONTACTED ✓"
        case .siteVisited: return "VISITED ✓"
        case .quoteSent:   return "QUOTED ✓"
        case .won:         return "WON"
        }
    }

    /// Stage written on stamp. `nil` = handled by the won flow, not a direct write.
    var targetStage: PipelineStage? {
        switch self {
        case .contacted:   return .qualifying
        case .siteVisited: return .quoting
        case .quoteSent:   return .quoted
        case .won:         return nil
        }
    }

    static func milestone(for stage: PipelineStage) -> LeadMilestone? {
        switch stage {
        case .newLead:      return .contacted
        case .qualifying:   return .siteVisited
        case .quoting:      return .quoteSent
        case .quoted, .followUp, .negotiation: return .won
        case .won, .lost, .discarded: return nil
        }
    }
}
```

**Steps (TDD):**
1. Write tests first: every stage maps to the spec §4 table (9 cases incl. all three terminals → `nil`); labels exact; `targetStage` exact; `.won.targetStage == nil`.
2. `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-daysheet -only-testing:OPSTests/LeadMilestoneEngineTests` → FAIL (type missing) → implement → PASS.
3. Commit: `feat(leads): add LeadMilestoneEngine stage-event verb map`

## Task 2 — `DaySheetViewModel` (pure transform over the console's buckets)

**Files:** Create `OPS/ViewModels/DaySheetViewModel.swift` · Test `OPSTests/ViewModels/DaySheetViewModelTests.swift`

Consume `PipelineViewModel` as the data engine (loadData, realtime, buckets); this VM is presentation only — spec §3.2. Shape:

```swift
@MainActor
final class DaySheetViewModel: ObservableObject {
    struct Row: Identifiable, Equatable { /* id, lead, urgency: Urgency, milestone: LeadMilestone? */ }
    enum Urgency: Equatable { case late(days: Int), today, yourMove, newLead(age: String), waiting(back: String) }
    struct Groups: Equatable { var yourMove: [Row]; var new: [Row]; var waiting: [Row]
                               var total: Int { … } ; var yourMoveCount: Int { … } }

    /// Pure. Inputs: the console's buckets + policy + now. Row-filters with
    /// can(.view, assignedTo:) even though RLS already scopes server-side.
    static func groups(from buckets: PipelineViewModel.TriageBuckets,
                       policy: LeadAccessPolicy,
                       now: Date) -> Groups
}
```

Rules under test (fixture `Opportunity` values, seeded dates):
- Bucket collapse per spec table: overdue+dueToday+waitingOnYou → YOUR MOVE (ordering: most-late → due-today → rest); fresh → NEW (newest first); waitingOnThem → WAITING (soonest comeback first).
- Row filter drops any lead failing `can(.view, assignedTo:)`; terminal/archived/deleted never present (buckets already exclude — assert anyway with a poisoned fixture).
- Urgency tokens: `2D LATE` / `TODAY` / `YOUR MOVE` / `3H AGO`→`2D AGO` / `BACK FRI` (within 6 days) → `BACK AUG 4` (beyond).
- Milestone comes from `LeadMilestoneEngine` and is `nil` when `policy.can(.edit, assignedTo:)` is false.
- Header counts: `total`, `yourMoveCount`.

Steps: failing tests → implement → suite green → commit `feat(leads): day-sheet grouping transform`.

## Task 3 — Collapsed row (`DaySheetLeadRow`)

**Files:** Create `OPS/Views/Leads/DaySheet/DaySheetLeadRow.swift`, `OPS/Views/Leads/DaySheet/LeadThumbView.swift` · Test `OPSTests/Views/DaySheetRowSnapshotTests.swift`

- Anatomy per spec §3.3 (mock A1). L1 glass card via existing card styling components; thumb 56pt r6: first `lead.images` URL (AsyncImage w/ cache) → else map snapshot at coords/address via a 56pt wrapper around `ProjectLocationSnapshotView`'s snapshotter → else neutral fill. Photo-count badge when `images.count >= 2`.
- Chips: neutral stage tag `STAGE · XD` (`lead.stage.displayName`, `lead.daysInStage`, omit under 1); urgency chip variants — rose/tan use the **mobile-lift** tag values from `OPSStyle` (the same treatment `LeadTriageCard`'s status tags use; if no shared component exists, add one to `OPS/Styles/Components/` — tokens only).
- Trailing 44pt CALL (dial via `LeadQuickTouchLogger.touch(.call, …)` semantics — reuse the exact do-and-stamp call path `LeadTriageCard` uses) and ROUTE (Apple Maps: `?daddr=lat,lon`, else address query; `--text-mute` disabled state when no address). Hairline separator. VoiceOver labels per spec §7.
- Row body is a Button (full-row tap → `onExpand`); icons intercept their own taps.
- Snapshot tests (harness pattern from `ClientLeadRow` tests: UIHostingController + scene-attached UIWindow + drawHierarchy; preview seam, no network): late-rose row, today-tan row, map-fallback row, no-address (route disabled).

Commit: `feat(leads): day-sheet collapsed lead row`

## Task 4 — Expanded card (`DaySheetLeadCard`)

**Files:** Create `OPS/Views/Leads/DaySheet/DaySheetLeadCard.swift`, `OPS/Views/Leads/DaySheet/LeadContactBlock.swift`, `OPS/Views/Leads/DaySheet/LeadDeckTile.swift` · Test `OPSTests/Views/DaySheetCardSnapshotTests.swift`

Order per spec §3.4 / mock A2: photos strip (52pt tiles → `LeadPhotoViewer`; `+` tile → the same add-photo flow `LeadPhotosSection` uses via `LeadImageService`, offline-queued) → deck tile (display-candidate via the same resolution `LeadDeckSection` uses; tap → existing fullscreen deck viewer; hidden when none) → summary band (`lead.aiSummary` + `aiSummaryUpdatedAt` age; 2px `--ops-agent` rail; hidden when nil) → contact block (ADDRESS/PHONE/EMAIL rows; omit absent; `.contextMenu` on each: COPY + CALL/TEXT on phone, COPY + MAIL on email; long-press = iOS default) → CALL/TEXT/EMAIL 44pt buttons (hide absent channels; `LeadQuickTouchLogger.touch`) → milestone button (Task 5; only when `milestone != nil`) → `EST $X` metadata line only when `permissionStore.can("finances.view")` and value present → `FULL LEAD →` (push `LeadDetailView`; host a local `LeadsSheet` enum like `ClientLeadsSection` does for edit/lost/convert).

Accordion state lives in the parent (one open id); card renders both states; expansion animation in Task 10.

Snapshot tests: full card (photos+deck+summary+contact+milestone), viewer-only variant (no milestone, no add tile), finances-visible variant (EST line), sparse lead (no photos/deck/summary → blocks absent, not empty).

Commit: `feat(leads): day-sheet expanded lead card`

## Task 5 — Milestone commit + 5s undo

**Files:** Create `OPS/Services/LeadMilestoneCommitter.swift` · Modify `DaySheetLeadCard.swift` · Test `OPSTests/Services/LeadMilestoneCommitterTests.swift`

- Press (non-WON): medium haptic → optimistic stage write through the **existing** `move_opportunity_stage` repository path (same call `LeadStatusMenu`/console uses) → stamp activity (same `ActivityType`/logging table the quick-touch logger writes; subject = verb label) → button morphs to `confirmationLabel` + inline `UNDO` for 5s → after window, notify lead-mutation (existing `.opsLeadsDidChange`-style notification) so the sheet regroups.
- `UNDO` inside window: revert stage to prior value via the same path, delete the stamped activity, cancel regroup. Engine holds `pendingCommit` (leadId, priorStage, activityId, deadline) — pure logic unit-testable with a fake clock; no `Task.sleep` in tests.
- WON press: no undo chip — route to the existing won flow (`LeadsSheet` host: `wonChooser`/`convert` machinery; without `can(.convert)` it stamps won only), per spec §4.
- Offline: press queues (Task 6) and the UI confirms identically (`QUOTED ✓` + queued affordance).
- Owner visibility: after commit, create a notification row per bible §07-14 (standard, `actionUrl` to the lead) so the stamp surfaces on the web rail — follow an existing iOS notification-creation call site for the exact insert shape.

Tests: commit → correct stage+activity pair; undo inside window → full revert; undo after deadline → no-op; edit-scope gate (no committer without `can(.edit)`); WON routes, never writes stage directly.

Commit: `feat(leads): milestone stamp with 5s undo`

## Task 6 — Offline snapshot cache + queued milestone writes

**Files:** Create `OPS/Services/DaySheetCache.swift` · Test `OPSTests/Services/DaySheetCacheTests.swift`

- `DaySheetCache`: Codable snapshot of the last successful fetch (`[OpportunityDTO]`-level, keyed `user+company`, Application Support, atomic write + `lastSync: Date`). Load on launch/offline; render with `SYS :: OFFLINE — LAST SYNC <T>` line (tan, mono) per spec §3.5.
- Milestone queue: persist pending commits (leadId, verb, priorStage, stampedAt) alongside the cache; drain on the app's existing triggers (connectivity restore, 60s timer, app launch — mirror the image-queue drain wiring in `OPSApp` bootstrap). Echo-safe: drained commits re-check current stage; skip+log if the lead moved meanwhile (last-writer honesty, no clobber).
- Thumbnails ride the existing image cache (`PhotoPrefetchService` prefetch of first images on fetch).

Tests: round-trip snapshot; lastSync formatting; queue drain happy path; drain skip-on-conflict.

Commit: `feat(leads): offline day-sheet cache and queued milestones`

## Task 7 — `LeadDaySheetView` + tab branch

**Files:** Create `OPS/Views/Leads/DaySheet/LeadDaySheetView.swift` · Modify `OPS/Views/Leads/LeadsTabView.swift` (branch only) · Test `OPSTests/Views/DaySheetViewTests.swift` + snapshot

- `LeadDaySheetView`: nav title `LEADS` + sub-line `// N LEADS · M YOUR MOVE`; grouped LazyVStack of rows (group headers `// YOUR MOVE · n` etc., empty groups collapse); pull-to-refresh; states per spec §3.5 (`0` + `// NO LEADS ASSIGNED`; skeletons; error+RETRY); `+` nav action iff `canCreate` → `AddLeadSheet`.
- `LeadsTabView.body` becomes a branch: `scope(for: .view) == .assigned` → `LeadDaySheetView(viewModel: viewModel …)`; else existing console body **unchanged** (extract current body to `consoleBody` `@ViewBuilder var`; do not reindent/rewrite it — keep the diff surgical).
- Deep link: reuse the existing `pendingLeadDeepLinkId` drain — on day sheet it expands the target row (scroll + open) instead of pushing detail.
- Unit: branch selection under `.all`/`.assigned`/`nil` policies (env-injected store fixtures). Snapshots: populated sheet (A1 parity), empty.

Commit: `feat(leads): permission-scoped day sheet on the Leads tab`

## Task 8 — Arrival: assignment notification

**Files:** Migration (additive) in Supabase + possible small iOS payload handling. Discovery-first task.

1. Trace one existing end-to-end push (e.g. an expense/notification type): where `NotificationManager.handleDeviceTokenRegistration` stores the token, and what server component sends APNs from a notification row. Record findings in the execution log.
2. Check `ops-web` `feat/lead-assignment` (local branch, tip `a90b7d7b`) for its delivery tables/RPCs. **Decision rule (spec §5):** if that branch's delivery path is shipping imminently, integrate with it; otherwise ship the independent minimal path now: additive migration — trigger on `opportunities` `UPDATE OF assigned_to` (new assignee non-null, changed) → insert notification row (`NEW LEAD — <NAME>`, body `<address> · <job line>`, `actionUrl` deep link to the lead) addressed to the assignee, feeding the existing rail/push pipeline. No role-name filtering — the recipient is exactly `assigned_to`.
3. iOS tap-through: ensure the push/notification payload sets `pendingLeadDeepLinkId` (existing drain). Reassignment-away is already handled by refresh + realtime (Task 7).
4. **Prod migration needs Jackson's explicit go at ship time** (standing low-tenant policy) — stage the SQL in the PR, do not apply silently.

Tests: trigger SQL verified on a sentinel-rollback DO block (the `convert` precedent); iOS payload → deep-link unit test.

Commit: `feat(leads): assignment delivery notification` (+ separate `migrations:` commit)

## Task 9 — States, copy pass

Verify every spec §8 string verbatim across Tasks 3–8 output; empty/loading/offline/error render paths each have a snapshot or unit assertion. `—` never "N/A"; numbers mono. Commit: `fix(leads): day-sheet states + copy conformance` (or fold into prior tasks if zero drift — do not manufacture a commit).

## Task 10 — Motion + haptics

**Skills:** `animation-studio:animation-architect` → `animation-studio:ios-animations` (mandatory before writing animation code).

Expand/collapse 250ms, regroup move 300ms, single easing (`OPSStyle` motion tokens = cubic-bezier(0.22,1,0.36,1)); undo chip fade 150ms; reduced-motion → 150ms opacity everywhere (`@Environment(\.accessibilityReduceMotion)`); haptics: light on expand, medium on milestone, success on WON completion — no others. 60fps: animate transform/opacity only; no layout-thrash animations inside the LazyVStack.

Commit: `feat(leads): day-sheet motion and haptics`

## Task 11 — Verification gate (definition of done)

1. Full suite: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-daysheet` → green (zero pre-existing-failure regressions).
2. Device build: `xcodebuild build -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-daysheet` → BUILD SUCCEEDED.
3. Snapshot proofs exported via `xcresulttool` to `docs/artifacts/my-leads-day-sheet/` (A1 parity, A2 parity, empty, offline) — eyeball against the approved board.
4. `custom-skills:audit-design-system` pass: zero hardcoded color/spacing/radius/font values in every new file.
5. Live sanity in sim with an assigned-scope test user if a credentialed session exists; else state plainly that runtime proof is snapshot-level.
6. Update the bible (pipeline/leads section + notifications §07-14 entry) in the same session.
7. Write the handoff summary for Jackson in plain language with the proof PNGs. Do not push; do not apply the prod migration without his go.

---

**Execution:** separate session (spawned as `MY LEADS - P1-1`), `custom-skills:executing-plans`, worktree `feat/my-leads-day-sheet`, Opus agents for code-writing. Checkpoints: after Tasks 2, 5, 7, and 11 — report progress with evidence, not intent.
