# iOS performance investigation and repairs

The investigation confirmed several causes of lag and continuity problems. All reviewed repairs are implemented on local iOS main at `a2e0e55f`, with the same app and test source that passed final verification. The signed optimized build succeeded with zero errors; its signature and matching debug symbols are verified. It reports 199 compiler warnings, including existing Swift 6 migration notices, so this is not a warning-free build. Nothing has been pushed or released through the App Store.

The remaining question is how much smoother the complete site-visit workflow feels on the phone. That requires a controlled recording of the final optimized build; the tests alone cannot establish a speed percentage or that all lag is gone.

## What caused the lag

The strongest new evidence is from the actual phone: a known optimized build recorded **five UI-thread stalls lasting 253–384 milliseconds**, with normal thermal conditions. Database queue processing and photo-sync bookkeeping were running on the thread responsible for drawing the screen. The supposed background worker was still using that thread. A simple detached-constructor change failed its mechanism test; the accepted repair explicitly controls the worker's executor and waits for startup readiness.

The trace also showed repeated task/project reads for review counts. Those counts now share one background snapshot across the action menu, Job Board header and notifications. Passive screen rendering no longer enumerates those tables.

Earlier source investigation found costly work concentrated in visits: broad queue rebuilding after small edits, repeated historical recovery during ordinary uploads, image processing and storage scans, and duplicate work when returning from the deck editor. Airplane mode reduces several online triggers, which fits the observation. It does not account for all of these paths.

The database was healthy on inspection. Its size alone was not the diagnosis, and a reset was not needed.

## Improvements implemented

| Area | Resulting behavior |
|---|---|
| Typing and saving visits | Checklist edits are buffered, unchanged writes are skipped, and saves prepare the affected visit's work instead of rebuilding all dirty visits. |
| Background sync | Database transactions run on an explicit background executor. Ordinary upload wakes avoid broad historical recovery; startup and account changes have defined ownership. |
| Taking photos | Original captures become durable before acceptance. Bounded previews and background image preparation reduce memory and UI work; interrupted or failed captures remain recoverable. |
| Photo storage and thumbnails | Incremental storage accounting replaces repeated cache scans. Thumbnails load asynchronously with bounded decoding, remote fallback and refresh when cached images arrive. |
| Deck editor | Exit avoids duplicate drawing encoding and prepares thumbnails off the UI thread. Durable autosaves remain protected while the editor is active. |
| Opening and searching | Cached clients appear before the network response. Visit/deck queries use scoped candidates and exact identities. Obsolete responses cannot replace current edits. |
| Review and sync indicators | Shared background summaries drive passive counts and status. Stale, failed or retired reads do not become false empty results. |
| Data continuity | Editing one visit preserves other unsaved edits and stopped uploads. Checklist-only and identity-only drafts survive re-entry; explicitly starting a new visit remains distinct from resuming one. |
| Save and completion UX | A durable local save is acknowledged independently of stage delivery. Incomplete work can be preserved while completion respects required answers. |
| Database upgrades | Released database shapes stay frozen; V26 adds the deck merge base through an explicit upgrade. Opening failures preserve the store and expose recovery. |

Additional corrections prevent old image/network callbacks from changing retired data, stop cancelled syncs from leaving a permanent busy state, and preserve new Spotlight changes while an earlier batch is suspended. Existing nonblank client notes and contact/draft linkage are also preserved during resume and import.

The original thirteen ranked findings, source evidence and broader observations remain in [REPORT.md](REPORT.md).

## What is verified

- **Final runtime checks:** 168 tests passed, zero failed or skipped. They cover real background transactions, startup, incoming updates, cancellation/logout, photos, Spotlight and shared review counts. A separate 38-test run passed with Core Data threading assertions independently confirmed active. An earlier reporting failure was corrected; its original assertion and four new deterministic regression tests passed.
- **Earlier repair checks:** storage, visit persistence/recovery, media, deck and search tests passed their final focused runs. The actual contact-import/cancel screens passed two UI tests, with screenshots inspected. Counts overlap across runs; they are not a cumulative total.
- **Actual phone upgrade and custody:** V25 upgraded to V26 and opened successfully. All original visit, artifact, answer, draft, deck, photo and outbox identities were retained. All 153 original deck drawings were unchanged. Ten queued operations completed through ordinary online sync, while the deliberately parked operation kept its original payload and status. Both protected recovery files were copied after unlock.
- **Approved server update:** the exact reviewed stage-delivery migration is applied. Independent catalog/dependency readback and anonymous route-denial checks passed. Local server tests passed 34/34. This does not establish authenticated provider delivery.

Exact revisions and test scope are recorded in [PM-STATUS.md](PM-STATUS.md), [REPAIR-ACCEPTANCE.md](REPAIR-ACCEPTANCE.md) and the [runtime evidence](executor-mechanism-summary.json). Signed candidate evidence: [build and signature](runtime-signed-build-summary.json). Phone evidence: [startup recording](physical-startup-profile-summary.json), [upgrade](physical-upgrade-summary.json), [custody](physical-custody-summary.json).

## Remaining phone validation

Another Xcode run replaced the first optimized phone build with a different Debug build. Its warm recording is excluded from comparisons. Phone ownership must be coordinated before replacing it.

A separate task merged a header-layout repair after this candidate was built. That work is preserved on main and is outside this candidate's verification. Coordinate the next phone build with that task so both repairs are included.

Once the phone is available and connected by USB, record the same visit → checklist → photos → notes → deck → return → save/reopen workflow online, offline and after reconnect using the final optimized build. A read-only stage snapshot through the actual signed-in session also remains unverified.

Private app-data copies and traces remain protected outside the repositories while device diagnosis is active. The authorized server update is applied; no push or App Store release has occurred.
