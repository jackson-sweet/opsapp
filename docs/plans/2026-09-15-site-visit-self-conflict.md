# Site-visit self-conflict + deck-attachment ordering — fix plan (2026-09-15)

Bugs: `0e110106` (urgent, SITE_VISIT_WRITE_CONFLICT self-conflict), `6271078d` (high, deck artifact 23503 before its deck exists). Device evidence in the bug rows and in `docs/plans/...` history; root cause proven on Jackson's phone store (visit `96090555`).

## What goes wrong

1. A checklist-answer write saves (`write_revision` N) while the operator keeps editing the same field. `SiteVisitVersionedSync.applyReceipt` only advanced `writeState.revision/baseRevision` when a **dependsOn descendant** existed; a same-entity successor queued two seconds later shipped `base_revision` N-1 → server `stale_edit` → parked with copy blaming "another device". RETRY re-sends the frozen command, so it can never clear.
2. The enqueue path (`SiteVisitWriteModels.command` → `beginVersionedEdit`) reads `writeState` from whatever context object the view model holds; a receipt applied on the sibling verification context can be invisible to it, so the successor shipped a stale base **and** wrote the stale state back (Deck Layout answer: base 0 vs server 1).
3. `flushChecklistEdits` restores the write state captured at the first keystroke wholesale, which can overwrite a revision advanced in between.
4. A `deck_design` artifact's create op is sent before the deck's own create op exists (the deck editor holds deck writes until it closes) → `23503 site_visit_artifacts_deck_design_id_fkey`. The cross-entity barrier exempts site-visit ops and the artifact payload carries no deck reference anyway.

## Fix (all TDD, tests first)

A. `applyReceipt`: on a `saved` receipt whose row id matches, advance `revision`/`baseRevision`/`baseRow` even when the local row drifted and no descendant is queued (answer + template branches). Existing template test updated (its `baseRevision 4` assertion encoded the defect).
B. `execute`: before an unattempted, unresolved command is frozen, rebase each row's `base_revision`/`before` onto the highest revision this queue has already seen for that row — receipts of completed ops with outcome `saved`/`resolved`/`superseded`, plus the model's persisted `writeState.revision` read from a fresh context. Conflict receipts never count (they may carry a foreign write).
C. `execute`: a `stale_edit` conflict whose current rows are **exactly** rows this queue delivered (a completed op's `saved` receipt row equals the current row) is a self-conflict → persist a `pending` resolution with `current = receipt.rows` and deliver it in the same pass (one hop). A foreign row still throws `.conflict` and parks for review. `deliverResolution` becomes injectable for tests.
D. `SiteVisitWriteState.restoringCapturedBase(_:)` (pure): the flush restores the captured base only if the persisted revision has not moved past it; otherwise keeps the newer revision and just re-marks the edit.
E. Deck ordering: `SiteVisitSyncOperation.artifact` carries `deck_design_id` in its payload; `SiteVisitOutboundSync.isReady` holds an artifact op while an unresolved `deckDesign` create for that id is queued; `SiteVisitOutboundSync.isHeldBehindUnsyncedDeck(_:context:)` holds it while the local `DeckDesign` has `lastSyncedAt == nil` and no completed create op exists (the editor-open window). Wired into both processors' eligibility filter and claim gate.

## Verification

- New tests in `SiteVisitVersionedSyncTests`, `SiteVisitWriteCommandTests`, `SiteVisitFieldWorkflowTests`, `SiteVisitOutboundSyncTests` — each watched RED before the code lands, then GREEN, counts read from the xcresult.
- Existing site-visit sync suites stay green.
- Device evidence after Jackson's next install: typing through a save no longer parks; PENDING WORK stays empty after a normal visit.

---

# Part 2 — Local until save (Jackson, 2026-09-15: "It should only be uploading when the user saves the site visit. Otherwise, just saving locally on the phone.")

## Why typing lagged

`SiteVisitChecklistAnswerRow`'s TextField binding calls `bufferChecklistAnswer` on every keystroke, which flushes synchronously: `persistSiteVisitChanges` → `SiteVisitPersistenceCoordinator.commit` (a SwiftData transaction on a 95 MB store, change-boundary tracking, a predicate fetch over the 3,000-row SyncOperation table to find/coalesce the answer's op, JSON-encoding the write command) → `reloadChecklistAnswers()` (refetch + re-render every row) → the DataActor's `ModelContext.didSave` observer starts a drain that fetches every SyncOperation again while the next keystroke waits on the store. Same path that produced the self-conflict.

## Behavior

- **Typing writes to the phone only.** Checklist answers, notes, measurements, identity fields, deck attachment and address edits persist locally (`needsSync = true`) with no queue entry. Keystrokes are debounced (400 ms, flush on focus loss) so the store is touched once per pause, not per character; the screen shows the buffer immediately.
- **Saving the visit queues everything dirty for the visit and starts the upload.** Save = DONE, SAVE DRAFT & CLOSE, the review sheet's "save draft" path, and completion. `saveDraft()` = flush buffers → `queueDirtyWork(siteVisitId:)` → `onWorkQueued` (the view wires it to `syncEngine.notifyDurableOperationQueued()`).
- **Going to the background, closing without confirming, opening the deck editor** keep the draft local (`preserveDraft()` only flushes).
- **Unchanged:** the visit row itself is created server-side when the visit starts (children need the parent); photo bytes keep uploading as captured (recommendation pending Jackson's veto); lead binding / reassign / discard / completion keep their immediate server semantics; the launch orphan sweep still delivers any dirty rows it finds.

## Tests first

- `SiteVisitPersistenceCoordinatorTests.test_localOnlyCommitQueuesNothingUntilDirtyWorkIsQueuedForSave`
- `SiteVisitFieldWorkflowTests.testTypingSavesLocallyAndUploadsOnlyWhenTheVisitIsSaved`
- `SiteVisitFieldWorkflowTests.testKeystrokesWaitBeforeTouchingTheStore`
