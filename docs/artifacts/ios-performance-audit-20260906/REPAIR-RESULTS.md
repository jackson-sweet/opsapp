# iOS performance repair — phone diagnosis and local repairs

The diagnosis found several overlapping causes of lag: ordinary edits could rebuild broad queues, online upload wakes could run historical recovery on the UI thread, photo capture and cache scans could block interactions, and leaving the deck editor could repeat expensive work. Your exported store contains 2,625 completed sync records and 11 unresolved records; repeatedly inspecting the whole history is unnecessary work even at this ordinary data volume. Airplane mode reduces some triggers, but it is not a complete explanation.

The repair sessions implemented the thirteen initial audit recommendations. Subsequent on-phone profiling found another confirmed issue: the database worker still executes sync work on the UI thread. A focused executor/readiness repair is underway. Verified iOS source is integrated on local main at `622010a0`. The reviewed server migration remains in its clean isolated checkout because the shared web checkout contains unrelated work. With Jackson's subsequent approval, the exact server migration is applied and verified, and the signed optimized development build is installed in place on his iPhone. Nothing has been pushed or released through the App Store. The original audit and its evidence remain in [REPORT.md](REPORT.md).

## Changes prepared

| Area | Resulting behavior |
|---|---|
| Database opening | Previously released database shapes stay frozen; a new V26 upgrade adds the deck merge base. Opening failures get a recoverable screen while preserving the store. |
| Typing and saving | Checklist edits are buffered; unchanged writes are skipped; the transaction builds the visit's affected work instead of rebuilding every dirty visit. |
| Unfinished and stopped work | Saving a visit preserves other screens' unsaved edits and other visits' stopped uploads. Actual host, deck, seed and lead-client entry paths use owned transactions. |
| Online syncing | Upload wakes are separated from controlled background recovery discovery. Session/account changes prevent stale upload callbacks from touching retired data. |
| Taking photos | Original bytes are stored before accepting each capture; bounded previews replace retained full-size batches. Interrupted and partial batches remain recoverable across visit, lead and project flows. |
| Resuming visits | Checklist-only and identity-only work is preserved. Deliberately starting a new visit is distinct from resuming the interrupted visit. |
| Photo storage | One background reconciliation plus incremental byte accounting replaces repeated directory scans for each download. |
| Deck editor | Exit avoids duplicate JSON work, renders thumbnails off the UI thread, and keeps active editor autosaves from being uploaded prematurely. |
| Sync status | A small background summary drives the badge; detailed recovery inventory is loaded when needed. |
| Search and opening | Cached clients appear before remote search; obsolete responses are ignored; visit/deck lookups use scoped candidates and exact identities. |
| Thumbnails | Bounded async downsampling includes local markup precedence, remote fallback and cache-arrival refresh. |
| Completion | Local save acknowledges durable work independently of stage delivery. Required answers govern completion while incomplete work remains savable. |
| Stage delivery | The applied server guard preserves the original operator decision, safely handles retries, and prevents an old command from overwriting a later stage. The server migration is applied and independently verified. |

Additional review repairs preserve nonblank existing client notes when resuming older blank drafts, save client/contact/outbox/draft linkage atomically, and preserve complete lead assignment snapshots. Earlier calendar, retained-tab and deck caching improvements are retained.

## Evidence so far

- Storage: 68 passed, 0 failed, 1 optional old V15 fixture skipped. Released fingerprints, synthetic V16/V25 upgrades, dirty merge-base preservation and recoverable startup behavior passed. The actual exported V25 store also passed its separate upgrade test: 1 executed pass, 0 failures, 0 skips. A disposable copy upgraded to V26 and reopened independently while counts and keyed content/custody digests matched across 16 groups. The exported original remained unchanged during the check. All task-created private database/proof copies were then removed; only the aggregate result remains.
- First combined run:287 passed,5 failed. All35 media cases passed. All five failing visit cases passed on the subsequent run.
- Subsequent focused run:306 passed,3 failed. The three failures were isolated to stale fixture observations, live connectivity interfering with a local test, and a test reopening a deliberately destroyed container. The final corrected rerun passed 127/127, with no skips, including every previously failing case and the real queue-to-open-visit notification path. Those regression failures are closed; the later physical trace identified the additional executor performance defect described above.
- Real screen flow on the task-owned simulator:2 passed,0 failed,0 skipped. Importing a contact retained the visit and populated its details; cancelling retained the intact visit. Screenshots were inspected: [after import](contact-import-preserved.png), [after cancel](contact-cancel-preserved.png).
- Server guard:34 local PostgreSQL cases passed. The approved production migration was applied as ledger20260907001000; independent catalog comparison,23 unchanged dependency functions and anonymous route-denial checks passed. Authenticated snapshot and provider delivery remain separate from this proof.
- Optimized generic iPhone compile passed with signing disabled:arm64, 0 errors. The build reports 204 warnings, including Swift 6 actor-isolation notices; this is not a warning-free build or a completed Swift 6 migration. Subsequent changes were only tests/documentation, verified by source diff. The same optimized source was then signed with existing development profiles, passed deep/strict signature validation, and installed in place on the paired iPhone. No App Store distribution occurred.

These counts overlap across runs and should not be added together. Exact revisions, test selectors and result bundles are recorded in [PM-STATUS.md](PM-STATUS.md) and [REPAIR-ACCEPTANCE.md](REPAIR-ACCEPTANCE.md).

## What the actual phone confirmed

The optimized build opened the real phone database and completed its V25 to V26 upgrade. All original visit, artifact, answer, draft, deck, photo and outbox identities were retained. All 153 original deck drawings were unchanged; the deliberately parked operation kept its exact payload and status. Ten queued operations completed through normal online sync. Both protected recovery files were backed up after the phone was unlocked. Sanitized evidence: [upgrade](physical-upgrade-summary.json), [custody](physical-custody-summary.json).

The first optimized launch recording captured five main-thread stalls lasting 253–384 milliseconds while the phone's thermal state was normal. Database queue processing, claims and media bookkeeping appeared on the thread responsible for drawing the screen. This is direct evidence of another performance defect, beyond the thirteen initial recommendations. The simple proposed detached-constructor fix failed its mechanism test, so it is not accepted. The repair task is checking the executor behavior and the startup ordering that must make the worker ready before sync starts. [Recording summary](physical-startup-profile-summary.json).

A later recording used a different Debug build that another Xcode run had installed. It is excluded from performance comparisons. No speed percentage or claim that the lag is resolved is supported yet.

## Remaining work

Complete and verify the database executor and startup repair, then build the optimized phone version. Coordinate phone ownership before replacing the separate task's Debug build. With the phone connected by USB and the user ready, record the same visit, photo, note and deck workflow online, offline and after reconnect. The earlier first-launch lock requirement has been resolved; the manual workflow and equivalent-build comparison are still outstanding. A read-only stage snapshot through the actual signed-in session also remains unverified.

The approved server update is applied and verified. No git push or App Store release has occurred. Private database copies and traces remain protected outside the repositories while diagnosis is active.
