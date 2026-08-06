# iOS Bug Batch Implementation Plan

> **For the executing agent:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Resolve the thirteen 2026-08-06 iOS reports with durable sync repair, safer recovery actions, deliberate lead lifecycle interactions, responsive Project Details records, selection-aware Deck Designer metrics, and one canonical mobile chrome system.

**Architecture:** Keep authoritative business decisions at the existing Supabase/RPC boundaries while repairing client orchestration and offline reconciliation. Separate pure policies/state from SwiftUI rendering so each reported failure has deterministic unit coverage, then add focused snapshots for presentation and accessibility. Land each report as an atomic commit and do not mutate production customer data.

**Tech Stack:** Swift 6, SwiftUI, UIKit input accessories, SwiftData, Supabase Swift, XCTest, Xcode 26 simulator and generic-device builds.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift` (there is no `.interface-design/system.md` in this repository).

**Required Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:wireframe`, `custom-skills:wizard-audit`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `custom-skills:Elite Animations`, `supabase:supabase`, `superpowers:verification-before-completion`.

---

## Execution rules

- Work only in `.worktrees/ios-bug-batch-p1` or task-specific child worktrees based on its committed head.
- Keep `.spm-local` worktree-local and use a unique DerivedData directory.
- Run the named focused test before implementation and confirm the expected red result.
- Never auto-delete unsent recovery work or tombstone production rows during verification.
- Reconcile the active `site-visit-checklist-settings` and `ws-pill-contrast` work before integrating overlapping capture/header edits.
- Commit after each task; do not push.

### Task 1: Establish a clean, current baseline

**Skills:** `superpowers:using-git-worktrees`, `superpowers:verification-before-completion`.

**Files:**
- Verify: `OPS/Views/Leads/Components/LeadChaseStrip.swift`
- Verify: `OPS.xcodeproj`

**Step 1: Finish the current `origin/main` merge**

Confirm every semantic change from the remote follow-up work is already retained and the only staged delta is the tokenized `LeadChaseStrip` reconciliation.

**Step 2: Run the focused baseline**

```bash
xcodebuild -quiet -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath "$IOS_BUG_DERIVED_DATA" \
  -clonedSourcePackagesDirPath .spm-local \
  -only-testing:OPSTests/LeadChaseEngineTests \
  -only-testing:OPSTests/LeadFollowUpServiceTests \
  -only-testing:OPSTests/PipelineViewModelFollowUpTests test
```

Expected: exit 0.

**Step 3: Commit the merge**

```bash
git commit --no-edit
```

### Task 2: Preserve site-visit errors and reconcile logical checklist duplicates (`fe497fb9`)

**Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `supabase:supabase`.

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/SiteVisitRepository.swift:62-105`
- Modify: `OPS/Network/Sync/SiteVisitServerMerge.swift:486-575, 830-950`
- Modify: `OPS/Network/Sync/SiteVisitSyncOperation.swift:15-45`
- Test: `OPSTests/SiteVisits/SiteVisitRepositoryTests.swift`
- Test: `OPSTests/Sync/SiteVisitServerMergeTests.swift`
- Test: `OPSTests/Sync/SyncErrorClassifierTests.swift`
- Test: `OPSTests/Sync/SiteVisitOutboundSyncTests.swift`

**Step 1: Write the failing error-fidelity tests**

Assert every `SiteVisitRepositoryError` case exposes its associated server detail through `localizedDescription`, and assert SQLSTATE `23505` is a permanent integrity rejection rather than `.transport`.

**Step 2: Run the error tests and confirm red**

Run only `SiteVisitRepositoryTests` and the site-visit rows in `SyncErrorClassifierTests`. Expected: generic Cocoa error text and transient classification fail the new assertions.

**Step 3: Implement typed localized errors**

Conform `SiteVisitRepositoryError` to `LocalizedError`; provide stable OPS context plus the original server message for every case. Classify all SQL class `23` integrity errors as `.dependency`, while keeping `40001`, `40P01`, `55P03`, and `57014` transient in the shared classifier.

**Step 4: Write the failing parent-first reconciliation test**

Create a synced parent, a local unsent checklist answer with ID `L`, a durable operation for `L`, and an incoming server answer with ID `S` but the same active `(siteVisitId, fieldId)`. Assert one active logical answer remains, local answer content wins protected fields, the canonical server ID is adopted, and every unresolved operation envelope/entity ID is migrated to `S` without losing dependency or retry state.

**Step 5: Run the merge test and confirm red**

Expected: current ID-only merge leaves two active answers.

**Step 6: Implement logical reconciliation transactionally**

Add predicate-scoped lookup by `(siteVisitId, fieldId, deletedAt == nil)`. When IDs differ, preserve field guards/local content, migrate matching unresolved operations and their typed payloads, adopt the canonical server ID, and then apply the normal merge. Never use a whole-table fetch. If two independently dirty logical rows cannot be proven equivalent, fail closed with an actionable repository error rather than dropping either.

**Step 7: Add whole-packet retry coverage**

Start with VISIT failed/parked and COMPLETION waiting, apply the canonical child reconciliation, explicitly retry, and assert parent/children settle before the single idempotent completion result.

**Step 8: Run focused site-visit suites**

Expected: all four suites pass and persisted error copy contains the original database/auth detail.

**Step 9: Commit**

```bash
git add OPS/Network/Supabase/Repositories/SiteVisitRepository.swift \
  OPS/Network/Sync/SiteVisitServerMerge.swift \
  OPS/Network/Sync/SiteVisitSyncOperation.swift \
  OPSTests/SiteVisits/SiteVisitRepositoryTests.swift \
  OPSTests/Sync/SiteVisitServerMergeTests.swift \
  OPSTests/Sync/SyncErrorClassifierTests.swift \
  OPSTests/Sync/SiteVisitOutboundSyncTests.swift
git commit -m "fix(sync): reconcile site-visit checklist retries"
```

### Task 3: Make existing-project matching use the linked client address (`967bd985`)

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `supabase:supabase`.

**Files:**
- Modify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift:234-240, 1011-1178, 1532-1597`
- Test: `OPSTests/Pipeline/ConvertSheetPrefillTests.swift`
- Test: `OPSTests/Pipeline/ConvertSheetMatchingTests.swift`
- Create: `OPSTests/Pipeline/ConvertSheetInitialLoadTests.swift`

**Design tokens:** Existing sheet tokens only: `OPSStyle.Layout.spacing*`, `OPSStyle.Typography.*`, `OPSStyle.Colors.*`; no new styling.

**Step 1: Write the failing orchestration test**

Given a blank-address opportunity, a linked client absent from SwiftData but returned by the repository, and a same-address project, assert the initial load hydrates the client, prefills its address, persists/rechecks that address through the existing guarded path, and ends with the project matchable without operator retyping.

**Step 2: Confirm red**

Expected: preflight final state remains `address_required` and repository fallback is never called.

**Step 3: Implement the ordered load**

Make linked-client resolution async: local predicate-scoped lookup first, tenant-scoped `ClientRepository.fetchOne` fallback second. Apply address prefill before authoritative preflight. If the server returns `address_required` for a nonblank client-sourced address, automatically invoke the existing address write-back/recheck exactly once. Keep the server preflight and candidate-link reread authoritative.

**Step 4: Run focused conversion suites**

Expected: blank-client-address, own-address precedence, repository failure, address edit invalidation, candidate-link failure, and existing conversion tests pass.

**Step 5: Commit**

```bash
git add OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift OPSTests/Pipeline
git commit -m "fix(leads): match projects from linked client address"
```

### Task 4: Separate discard reason selection from submission (`887722e1`)

**Skills:** `custom-skills:wizard-audit`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Views/Leads/Sheets/LeadDispositionReasonSheet.swift`
- Modify: `OPS/Views/Leads/Components/LeadDiscardFlow.swift`
- Test: `OPSTests/Pipeline/LeadDispositionFeedbackTests.swift`
- Test: `OPSTests/Pipeline/LeadArchiveFeedbackTests.swift`
- Test: `OPSTests/Views/LeadsDiscardSnapshotTests.swift`

**Design tokens:** `touchTargetMin`, `touchTargetStandard`, `bottomCTAHeight`, `spacing*`, `surfaceInput`, `surfaceActive`, `line`, `rose`, and canonical typography tokens.

**Step 1: Write failing selection-state tests**

Assert tapping a row only selects it, `APPLY REASON` is disabled until selection, submission runs once, failure retains reason/note and exposes inline retry copy, and success dismisses.

**Step 2: Confirm red**

Expected: row tap invokes the async apply closure immediately and failure clears selection.

**Step 3: Implement deliberate commitment**

Render a selected checkmark/state, keep rows tappable while idle, and add one bottom CTA labeled `APPLY REASON`. While working, lock dismissal and show the existing progress state. On failure, preserve selection and note and show `COULD NOT UPDATE LEAD · TRY AGAIN` inside the sheet; keep the global toast only as secondary feedback.

**Step 4: War-game all hosts**

Exercise Leads root, Lead detail, and the nested Lost sheet. Verify swipe-dismiss, offline failure, repeated taps/idempotency, Dynamic Type, keyboard dismissal, and VoiceOver row then CTA order.

**Step 5: Run focused tests and snapshots**

Expected: reason sheet, routing policy, RPC DTO/idempotency, and snapshots pass.

**Step 6: Commit**

```bash
git add OPS/Views/Leads/Sheets/LeadDispositionReasonSheet.swift \
  OPS/Views/Leads/Components/LeadDiscardFlow.swift \
  OPSTests/Pipeline/LeadDispositionFeedbackTests.swift \
  OPSTests/Pipeline/LeadArchiveFeedbackTests.swift \
  OPSTests/Views/LeadsDiscardSnapshotTests.swift
git commit -m "fix(leads): make discard reason selection deliberate"
```

### Task 5: Give the global DONE accessory breathing room (`026891c5`)

**Skills:** `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift:520-555`
- Modify: `OPS/Styles/Components/OPSKeyboardDoneAccessory.swift:15-69`
- Test: `OPSTests/IOSBugReportRegressionTests.swift:149-269`

**Design tokens:** Add a named keyboard-accessory height derived from `touchTargetMin + spacing2`; preserve the 44pt actionable region.

**Step 1: Write the failing geometry test**

Host the real accessory and assert the band is taller than its 44pt tap target, DONE has positive bottom separation from the keyboard edge, and the target remains at least 44pt.

**Step 2: Confirm red**

Expected: the current exact-44pt assertion fails the separation requirement.

**Step 3: Implement tokenized geometry**

Use a custom item view/layout only if UIToolbar centering cannot prove the bottom inset. Keep one DONE item, existing text style, responder weak reference, no stacked accessories, and no keyboard reload regressions.

**Step 4: Run focused tests and commit**

```bash
git add OPS/Styles/OPSStyle.swift OPS/Styles/Components/OPSKeyboardDoneAccessory.swift \
  OPSTests/IOSBugReportRegressionTests.swift
git commit -m "fix(keyboard): add breathing room below done"
```

### Task 6: Put the lead summary before the site-visit checklist (`886f1a02`)

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify after checklist-settings reconciliation: `OPS/Views/SiteVisits/SiteVisitCaptureView.swift:129-165, 413-449, 584-716`
- Test: `OPSTests/Views/SiteVisitFormSnapshotTests.swift`
- Create: `OPSTests/SiteVisits/SiteVisitLeadSummaryTests.swift`

**Design tokens:** Existing `nestedCard`, `spacing*`, `miniLabel`, `smallBody`, `text`, `text2`, `textMute`, `lineSoft`.

**Step 1: Write the failing semantic order test**

For a bound opportunity with a nonblank summary, assert a summary accessibility element exists and precedes `2 · CHECKLIST`. Assert whitespace-only summaries render nothing.

**Step 2: Confirm red**

Expected: no summary element exists.

**Step 3: Implement the compact summary band**

Extract a small conditional `SiteVisitLeadSummaryBand`. Place it after identity and directly before checklist. Use the most recent summary text without adding network work, editing controls, or a second summary source.

**Step 4: Snapshot 320pt, 390pt, and accessibility sizes**

Verify long summary wrapping, outdoor contrast, and no checklist displacement beyond natural content flow.

**Step 5: Commit**

```bash
git add OPS/Views/SiteVisits/SiteVisitCaptureView.swift \
  OPSTests/Views/SiteVisitFormSnapshotTests.swift \
  OPSTests/SiteVisits/SiteVisitLeadSummaryTests.swift
git commit -m "fix(site-visits): show lead summary before checklist"
```

### Task 7: Rebuild Trash as a truthful recovery ledger (`3f5bca5f`)

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Views/Settings/TrashView.swift`
- Modify: `OPS/Utilities/DataController.swift:5710-5775`
- Create: `OPS/Views/Settings/TrashRecoveryPolicy.swift`
- Create: `OPSTests/Views/TrashRecoveryTests.swift`
- Create: `OPSTests/Views/TrashSnapshotTests.swift`

**Design tokens:** `screenHeaderMinHeight`/canonical header, `touchTargetMin`, `spacing*`, `surfaceInput`, `surfaceActive`, `lineSoft`, `text*`, `opsAccent`, semantic success/error tones.

**Step 1: Write failing contrast and restore-policy tests**

Assert selected count ink differs from selected background; rows expose real thumbnail sources; restore policy distinguishes ready, parent-required, and unsupported states; and a failed `ModelContext.save()` prevents queueing/success.

**Step 2: Confirm red**

Expected: selected count is background-on-background and restore helpers swallow save failures.

**Step 3: Implement the recovery ledger**

Use one divider-separated list with compact rows, neutral readable segments, project gallery/client profile thumbnails, task project context, inline 44pt RESTORE, and tap-to-open half-sheet metadata. For parent-required restores, present one explicit combined action naming every restored record.

**Step 4: Make persistence truthful**

Perform local tombstone clearing transactionally; save first; enqueue exact sync operations only after save succeeds. Roll back local changes on failure and propagate the error.

**Step 5: Snapshot and accessibility verification**

Cover all entity/photo combinations, empty state, long titles, 320/390pt widths, accessibility sizes, VoiceOver ordering, and failure copy.

**Step 6: Commit**

```bash
git add OPS/Views/Settings/TrashView.swift OPS/Views/Settings/TrashRecoveryPolicy.swift \
  OPS/Utilities/DataController.swift OPSTests/Views/TrashRecoveryTests.swift \
  OPSTests/Views/TrashSnapshotTests.swift
git commit -m "fix(settings): rebuild trash as recovery ledger"
```

### Task 8: Add capability-aware swipe discard and stale review (`f71113a3`)

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `custom-skills:Elite Animations`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Network/Sync/RecoveryInventory.swift`
- Modify: `OPS/Views/Components/Sync/PendingWorkView.swift`
- Modify: `OPS/Views/Components/Sync/PendingWorkDetailSheet.swift`
- Generalize: `OPS/Views/Books/Ledger/BooksRowActions.swift`
- Test: `OPSTests/Sync/RecoveryInventoryTests.swift`
- Test: `OPSTests/Views/PendingWorkSnapshotTests.swift`
- Test: `OPSTests/Sync/SyncStatusCopyPendingWorkTests.swift`

**Design tokens/motion:** Existing row-action geometry and `OPSStyle.Animation` easing; 80pt trailing action; no destructive full swipe; reduced-motion alternative retained; no spring/bounce.

**Step 1: Write failing capability and retention tests**

Cover every recovery-item type and assert `canDiscard`, `discardReason`, and confirmation scope. Prove 29/30/31-day unsent work remains in inventory and receives `STALE · 30D` classification without deletion.

**Step 2: Confirm red**

Expected: draft/orphan discard is a no-op and age has no safe review state.

**Step 3: Generalize the established row-action component**

Extract the Books-specific naming without changing its behavior. Add trailing DELETE only when the item's capability allows it. Keep tap-to-preview, long-press and VoiceOver parity, confirmation, and `allowsFullSwipe == false` for destructive actions.

**Step 4: Wire real discard outcomes**

Do not present success unless the wrapper confirms the operation. A partially synced visit confirmation must say that its cloud shell and local packet are included; draft/orphan items without implemented deletion never show DELETE.

**Step 5: Run race/offline/snapshot tests**

Cover exactly-once discard, in-progress cancellation decline, server-ack artifact cleanup, offline state, swipe geometry, reduced motion, VoiceOver, and all inventory sections.

**Step 6: Commit**

```bash
git add OPS/Network/Sync/RecoveryInventory.swift OPS/Views/Components/Sync \
  OPS/Views/Books/Ledger/BooksRowActions.swift OPSTests/Sync/RecoveryInventoryTests.swift \
  OPSTests/Views/PendingWorkSnapshotTests.swift OPSTests/Sync/SyncStatusCopyPendingWorkTests.swift
git commit -m "fix(sync): add safe pending-work swipe discard"
```

### Task 9: Add an App Store-safe visible bug-report entry (`b5e15fc1`)

**Skills:** `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Utilities/ShakeDetection.swift`
- Modify: `OPS/ContentView.swift:1020-1065`
- Modify: `OPS/Views/SettingsView.swift`
- Create: `OPS/Utilities/BugReportTriggerCoordinator.swift`
- Create: `OPSTests/BugReportTriggerCoordinatorTests.swift`

**Step 1: Write failing coordinator tests**

Assert source identity, debounce, tutorial/auth guards, screenshot-before-overlay order, presenter latching, and simultaneous sheet/keyboard protection.

**Step 2: Implement one guarded trigger boundary**

Move the existing shake guards into a coordinator. Keep shake behavior unchanged and route Settings `REPORT A BUG` through the same coordinator. Do not observe or mutate system volume and do not use private APIs.

**Step 3: Run tests and commit**

```bash
git add OPS/Utilities/ShakeDetection.swift OPS/Utilities/BugReportTriggerCoordinator.swift \
  OPS/ContentView.swift OPS/Views/SettingsView.swift OPSTests/BugReportTriggerCoordinatorTests.swift
git commit -m "fix(bug-report): add a supported visible trigger"
```

### Task 10: Consolidate header geometry (`f6bf6b38`)

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift`
- Modify: `OPS/Views/Components/Common/OPSScreenHeader.swift`
- Modify: `OPS/Views/Components/Common/AppHeader.swift`
- Modify: `OPS/Views/Settings/Components/SettingsComponents.swift`
- Modify: `OPS/Views/JobBoard/QuickActionSheetHeader.swift`
- Modify: every first-party call site returned by `rg -n 'AppHeader\(|SettingsHeader\(|OPSScreenHeader\(|QuickActionSheetHeader\(' OPS/Views`
- Create: `OPSTests/Views/HeaderGeometryTests.swift`
- Update: `OPSTests/Views/SyncPillHeaderLayoutTests.swift`

**Design tokens:** Named 52pt header band, 44pt action target, 20pt icon, 20pt horizontal inset, Cake Mono screen title, maximum-two-action policy, canonical line/surface tokens.

**Step 1: Inventory every header family and write failing geometry tests**

Assert 52pt nominal band, Dynamic Type growth, left title alignment, 44pt targets, maximum two trailing actions, 320/390pt long-title behavior, and consistent safe-area treatment.

**Step 2: Confirm red across representative root/detail/settings/sheet hosts**

Expected: AppHeader, SettingsHeader, and QuickActionSheetHeader disagree.

**Step 3: Build the canonical action model and compatibility wrappers**

Extend `OPSScreenHeader` into the canonical page header without hardcoded view-specific callbacks. Make SettingsHeader a compatibility wrapper first. Keep sheets semantically distinct while sharing geometry and targets.

**Step 4: Migrate all call sites in bounded groups**

Root tabs first, then settings/detail screens, then custom sheets. Move root subtitles/status into the first content strip. Keep no more than two trailing actions; move overflow/context controls into the content command band.

**Step 5: Visual and accessibility proof**

Capture representative root tabs, settings, detail, and sheet at 390pt plus accessibility size. Verify interactive back navigation, VoiceOver order, sync-pill clearance, tab transitions, reduced motion, and no header/content collisions.

**Step 6: Commit**

```bash
git add OPS/Styles/OPSStyle.swift OPS/Views OPSTests/Views
git commit -m "refactor(navigation): standardize mobile headers"
```

### Task 11: Rebuild the Project Details site-visit record and photo presentation

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/DataModels/SiteVisits/SiteVisitPacketMetadata.swift`
- Modify: `OPS/DataModels/SiteVisits/SiteVisitCaptureArtifact.swift`
- Modify: `OPS/DataModels/SiteVisits/SiteVisitPacketNote.swift`
- Modify: `OPS/DataModels/SiteVisits/SiteVisitRecord.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitRecordView.swift`
- Modify: `OPS/Views/Components/Project/Tabs/SiteVisitPacketEntryView.swift`
- Test: `OPSTests/SiteVisitPacketNoteTests.swift`
- Test: `OPSTests/SiteVisits/SiteVisitCapturePacketTests.swift`
- Test: `OPSTests/Views/SiteVisitRecordSnapshotTests.swift`
- Create: `OPSTests/SiteVisits/SiteVisitRecordChecklistTests.swift`
- Create: `OPSTests/Views/SiteVisitRecordPresentationTests.swift`

**Design tokens:** Existing `spacing*`, `lineSoft`, `nestedCard`, `touchTargetMin`, `cardCornerRadius`, mobile type tokens, and canonical semantic tones. No width, spacing, font, radius, or color literal may be introduced.

**Step 1: Write failing packet and compatibility tests**

Assert a new packet writes structured checklist items with field id/label/value/kind/artifact count while preserving the exact legacy checklist strings and plain-text content. Assert old metadata containing only `checklist: [String]` decodes into the same structured record rows, including long-text and values containing colons.

**Step 2: Confirm red**

Expected: metadata has only raw strings and `SiteVisitRecord.checklist` cannot express field anatomy.

**Step 3: Add the backward-compatible checklist model**

Carry structured checklist items additively from the capture answer into metadata. Keep all existing keys and content unchanged. Make `SiteVisitRecord` prefer structured items and fall back to a defensive legacy parser; malformed legacy lines remain visible as value-only rows rather than being discarded.

**Step 4: Write failing presentation tests**

Assert the record's content width is bounded by its actual sheet width at 320pt/390pt and accessibility sizes, the evidence rail retains all photo URLs without increasing the document's ideal width, every visible thumbnail has a 44pt target, and the active sheet owns the photo viewer presentation state.

**Step 5: Implement the field-document layout**

Use a centered readable column, bounded horizontal evidence rail with a visible next-item peek, and one cohesive divider-separated field document with separate checklist label and answer hierarchy. Present `PhotoCommentViewer` inside a dedicated record-sheet host so a tap opens immediately above the still-present record. Preserve the existing project-scoped viewer and comment behavior, and pass all visit photos into it rather than the capped preview subset.

**Step 6: Run packet, record, snapshot, and presentation suites**

Cover new and legacy packets, photos unavailable locally, one/many photos, long labels/answers, colons, 320/390pt widths, accessibility sizes, VoiceOver order, immediate open, swipe-to-dismiss, and reopening a second photo.

**Step 7: Commit**

```bash
git add OPS/DataModels/SiteVisits OPS/Views/SiteVisits/SiteVisitRecordView.swift \
  OPS/Views/Components/Project/Tabs/SiteVisitPacketEntryView.swift \
  OPSTests/SiteVisitPacketNoteTests.swift OPSTests/SiteVisits OPSTests/Views
git commit -m "fix(projects): rebuild site-visit record sheet"
```

### Task 12: Move project status inside DETAILS

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DetailsTabView.swift`
- Test: `OPSTests/Views/DetailsTabSnapshotTests.swift`
- Create: `OPSTests/Views/ProjectDetailsInfoRowTests.swift`

**Design tokens:** Reuse `DocRow`, `ProjectInfoDoc`, `StatusBadge`, `lineSoft`, `touchTargetMin`, and existing DETAILS card tokens.

**Step 1: Write the failing hierarchy tests**

Assert DETAILS begins with STATUS, contains exactly one status element, preserves the existing status-change action for editors, is read-only for non-editors, and no standalone status section precedes the card.

**Step 2: Confirm red**

Expected: status renders as a separate block outside `projectInfoCard`.

**Step 3: Implement the compact status document row**

Add `.status` as the first fixed `InfoRow`. Render the canonical badge in a `DocRow`; make the full row a minimum-44pt button only when editable and keep the existing status sheet callback. Remove `StatusSection` and its extra separator entirely.

**Step 4: Run snapshots and accessibility checks**

Cover editable/read-only states, every job status, 320/390pt widths, accessibility sizes, VoiceOver value/action, and the status picker route.

**Step 5: Commit**

```bash
git add OPS/Views/Components/Project/Tabs/DetailsTabView.swift \
  OPSTests/Views/DetailsTabSnapshotTests.swift OPSTests/Views/ProjectDetailsInfoRowTests.swift
git commit -m "fix(projects): place status inside details"
```

### Task 13: Make Deck Designer full-bleed and selection-aware

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `animation-studio:animation-architect`, `animation-studio:ios-animations`, `animation-studio:data-visualization`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/DeckBuilder/Views/DeckBuilderView.swift`
- Modify: `OPS/DeckBuilder/Views/DeckCanvasView.swift`
- Modify if needed: `OPS/DeckBuilder/Models/DeckSelectionReadout.swift`
- Create: `OPS/DeckBuilder/Models/DeckBuilderMetricReadout.swift`
- Create: `OPS/DeckBuilder/Models/DeckBuilderViewportPolicy.swift`
- Create: `OPSTests/DeckBuilder/DeckBuilderMetricReadoutTests.swift`
- Create: `OPSTests/DeckBuilder/DeckBuilderViewportPolicyTests.swift`
- Update: `OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`

**Design tokens/motion:** Existing toolbar/card/safe-area/layout tokens and `OPSStyle.Animation.fast`; no new gesture or animation system, no spring/bounce, reduced motion preserved.

**Step 1: Write failing metric-policy tests**

Assert no selection returns whole-design area/perimeter; surface-only selection returns selected area and `—` length; edge-only selection returns `—` area and selected length; mixed selection returns both; vertex-only selection returns `—` / `—` rather than stale totals; deselection restores totals; and unit/config or geometry edits recompute from current drawing data.

**Step 2: Confirm red**

Expected: the metrics pill always reads `viewModel.totalArea` and `viewModel.totalPerimeter`.

**Step 3: Add one pure display reducer**

Build the metrics presentation from `DeckSelectionReadout` whenever any edge, surface, or vertex is selected, otherwise from whole-design totals. Return formatted area/length plus a selection-context flag. Do not cache it; derive it during SwiftUI rendering so selection, undo, geometry, level, and unit changes are live.

**Step 4: Write the failing layout policy test**

Assert the 2D canvas occupies the full container height and the standard toolbar is a bottom safe-area-aware overlay rather than a sibling that subtracts height. Assert measured toolbar-height changes alter the uncovered interaction viewport without changing the pixel canvas frame, and speed-draw, assignment, selection, fitting, constraint, and edge-pan policies all reserve the toolbar zone.

**Step 5: Implement the full-bleed stack**

Make 2D mode one full-height ZStack: canvas at the back, existing floating top controls above it, and the contained `DeckToolbar` overlaid at the bottom with home-indicator spacing. Extend the pixel canvas through all safe areas. Measure the toolbar's dynamic coverage through an iOS-17.6-safe preference and pass one uncovered viewport/inset contract into canvas fitting, centering, constraints, edge-pan, and bottom controls so geometry remains operable rather than merely drawing behind the toolbar.

**Step 6: Render selection metrics live**

Feed the pure readout into the existing metrics pill, render both measurement slots consistently, and expose `Selected` context accessibly. Keep the current whole-design presentation when nothing measurable is selected.

**Step 7: Run focused Deck Builder suites and visual proof**

Cover open/closed designs, no/surface/edge/mixed selection, multi-level geometry, imperial/metric units, toolbar hidden during perimeter speed draw, small/modern iPhones, home indicator, rotation, VoiceOver, and reduced motion.

**Step 8: Commit**

```bash
git add OPS/DeckBuilder/Views/DeckBuilderView.swift OPS/DeckBuilder/Views/DeckCanvasView.swift \
  OPS/DeckBuilder/Models \
  OPSTests/DeckBuilder/DeckBuilderMetricReadoutTests.swift \
  OPSTests/DeckBuilder/DeckBuilderViewportPolicyTests.swift \
  OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift
git commit -m "fix(deck-builder): make canvas and metrics selection-aware"
```

### Task 14: Update the Bible, verify the batch, and reconcile bug metadata

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, `supabase:supabase`.

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/06_TECHNICAL_ARCHITECTURE.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Create proof only under: `docs/artifacts/ios-bug-batch-2026-08-06/`

**Step 1: Update source-of-truth documentation**

Document logical checklist reconciliation/error fidelity, recovery retention/discard capabilities, conversion client-address recheck, structured site-visit record metadata, Project Details status anatomy, Deck Designer overlay/selection metrics, and canonical header/bug-report trigger behavior.

**Step 2: Audit changed UI files**

Scan for hardcoded colors, spacing, radii, font sizes, undersized targets, noncanonical icons, missing accessibility labels, and reduced-motion gaps. Zero unresolved violations are allowed.

**Step 3: Run the complete focused regression set serially**

Run every suite named above against the unique DerivedData directory. Preserve the `.xcresult` path under `docs/artifacts` only if it is useful proof.

**Step 4: Build for a generic device**

```bash
xcodebuild -quiet -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$IOS_BUG_DERIVED_DATA" \
  -clonedSourcePackagesDirPath .spm-local build
```

Expected: `BUILD SUCCEEDED` / exit 0.

**Step 5: Independent code review**

Review the full branch diff for data loss, retry loops, authorization assumptions, UI state races, accessibility, token compliance, and overlap with active worktrees. Fix every finding and rerun affected tests.

**Step 6: Update only proven bug reports**

For each locally verified fix, update `public.bug_reports` with status/priority/assignment and a concise resolution note that distinguishes local source/test proof from device/customer-live proof. Read back every changed row independently. Keep the unsupported hardware chord and any overlap-blocked item open with `requires_human_review = true` until its supported substitute/integration is verified.

**Step 7: Commit iOS proof documentation**

```bash
git add docs
git commit -m "docs(ios): record bug-batch recovery contracts"
```

Commit the Bible update separately in its own repository:

```bash
git -C /Users/jacksonsweet/Projects/OPS/ops-software-bible add \
  06_TECHNICAL_ARCHITECTURE.md 07_SPECIALIZED_FEATURES.md
git -C /Users/jacksonsweet/Projects/OPS/ops-software-bible commit \
  -m "docs(ios): record bug-batch recovery contracts"
```

Do not push, deploy, mutate customer records, or claim App Store/device proof without Jackson's explicit authorization and direct evidence.
