# iOS performance repair acceptance

Current state September7,2026: initial thirteen local repairs are integrated on main; additional measured executor/review/lifetime repairs at integration993ca641 passed168/168 focused tests,0skips. A separate38/38 concurrency run passed with assertions independently confirmed active. The final signed optimized build is in progress. Actual phoneV25→V26 upgrade and original data custody passed. Equivalent-workflow physical speed remains unmeasured, and a different Debug build from another task must not be replaced until ownership is coordinated. The approved server migration20260907001000 is applied and independently verified. Push and App Store release remain unapproved.

| Audit finding | Repair / invariant | Verification coverage |
|---|---|---|
| 1 Database compatibility | Frozen released schemas; V26 nullable merge base; recoverable same-store bootstrap | VERIFIED68 storage tests pass,1optional skipped; separate real phone upgrade/custody also passed |
| 2 Visit edit cost | Buffered checklist, unchanged guards, exact owned-context entity/outbox transaction | Coordinator/Continuity suites; pre-existing unsaved B remains pending and unchanged on disk after A success/failure; counts include unsaved-heavy graph |
| 3 Stopped work revived | A edit cannot revive B parked/declined work | Coordinator,OrphanRecovery,CommandRecovery and stage tests |
| 4 Main-thread recovery on every push | Ordinary upload wake separated from controlled background discovery and scoped repair | SyncRecoveryScheduling,RecoveryStoreQueries,OrphanRecovery; synthetic2636operations return11unresolved off main |
| 5 Capture memory/dismissal/durability | Bank original before acceptance; typed exact-owner handoff; retry same stable ID; release only after durable destination | DurableCaptureStore,CameraCaptureSession,LeadImageStager; final nonvisit destinations/draft tests; corruption/failure/relaunch |
| 6 Partial drafts lost | Shared content rules, no automatic uncertain deletion, fresh vs deliberate resume | Continuity,CapturePacket,LeadCapture; checklist-only and identity-only drafts |
| 7 Repeated cache scans | One reconcile then incremental reservations/write/delete ledger, all writers accounted | PhotoCacheLedger including concurrent reservation/protected original/direct PhotoProcessor writer |
| 8 Deck exit | One JSON encode, durable autosave held in both drivers, independent off-main thumbnail render | DeckExitResponsiveness,DeckEditingSession,DeckBuilderRegression,merge/retry tests |
| 9 Expensive status pill | Background compact equatable summary; details on demand; unknown vault not empty | RecoveryAttentionSummary,RecoveryVaultHeader,inventory parity and quarantine |
| 10 Local search latency | Local clients immediate, independently bounded remote search; obsolete response ignored | SiteVisitSearchSource including delayed/mismatched account responses |
| 11 Broad entry scans | Exact deck lookup; open owner/company visit candidates; compute draft metadata once | Continuity/entry tests and source review; predicate must compile on actual target |
| 12 Thumbnail work/fallback | Async downsampling with bounded concurrency, composite precedence, remote fallback, arrival updates | PhotoThumbnailLoader:pixel bound,orientation,fallback,cachearrival,cancellation |
| 13 Save/stage/required fields | Draft save immediate; completion checks applicable requirements; immutable original stage decision/outbox | Continuity,StageDelivery,StageDefault,CommandRecovery; server34/34verified locally; production RPC applied with exact catalog/ledger and anonymous route-denial proof |

Cross-review amendments were included in verified local completion: caller shared-context WIP must never be committed/rolled back by another visit, direct corrupt-manifest recovery must surface uncertainty, every production camera entry needs recoverable custody, project-create interruption needs durable parent command and stale-save tombstone, and stage default/queue condition must use the same snapshot the operator reviewed.

## Combined local proof

The parent executed one isolated build/test stream. Core01/core02 compile failures were corrected. Core03:292total/287passed/5failed. Core04:309total/306passed/3failed; all five prior visit failures passed. Core05:127total/127passed/0failed/0skipped, closing all three remaining fixtures without weakening production behavior assertions. These runs overlap and are not a cumulative unique count.

The final failed-case corrections use fresh exact-ID durable reads plus a real queue-to-open-VM notification test, keep the reset→awaited cancellation check without reopening a destroyed container, and keep local mention fixtures offline with explicit pending state and persisted dependency assertions before actor refresh. No production code changed after the successful optimized source build.

The existing hermetic SiteVisitContactImportUITests executed2cases with0failures/0skips; parent inspected after-import/cancel screenshots. The generic iPhone Release build succeeded with signing disabled,0errors and204warnings. No claim of warning-free code or physical-device speed is made.

The optional copied-V25 test executed1pass/0failures/0skips against the privately exported phone database, upgrading toV26 and independently reopening. Counts and per-run-keyed content/custody digests matched across16groups, including ProjectPhoto and full outbox state; dirty deck merge bases stayed unknown/unsent. Referenced asset bytes were not read. Original export bytes stayed unchanged during proof; task-created private export/proof copies were removed afterward. The old optional V15 test remains distinct and unchanged. Sanitized result:private-store-upgrade-summary.json.

Verified source is on local iOS main622010a0; software Bible current contracts updated in940c24c. The clean server dependency remains in P1-5's private checkout, preserving unrelated web WIP. Subsequent explicit approval enabled the exact production migration and in-place optimized phone installation; both are complete. No push or App Store release occurred.

## Physical performance proof and release sequence

Jackson approved the exact server migration, optimized phone installation, and online/offline measurements. Migration, initial optimized installation and actual first-launch upgrade/custody are complete. A valid startup recording exposed the additional executor defect now repaired locally. USB/manual workflow readiness and ownership coordination for the different Debug build remain pending. Push and App Store release remain unapproved. A production RPC must be applied and independently verified before a dependent client ships. Local-only tests cannot prove production notification/provider fan-out.

For the authorized device follow-through, use the same representative sequence and record source/build/store shape and network condition: new visit → type checklist →10photos → note/dictation → create/edit deck → return → save → reopen. Repeat Wi-Fi,cellular,high latency/loss,offline,reconnect with queue; include long-lived completed history and exact stopped work. Record signposted local save/recovery attention/discovery, Time Profiler/SwiftUI hitches, allocations and first-frame return. Compare optimized builds, not a debug-vs-release pair. No latency improvement percentage until measured.

Acceptance: every acknowledged photo/answer survives termination/reopen; failed saves preserve recoverable work; other visits' stopped edits stay stopped; stage replay cannot overwrite later choices; tap acknowledgement target100ms; no sustained storage/image work blocks typing/gestures; memory settles across repeated cycles. These targets remain unmeasured physical-device requirements.


Final evidence: combined-core03/04/05-summary.json,contact-ui-summary.json,device-release-summary.json,private-store-upgrade-summary.json. Full general test/build bundles remain in the integration checkout; private proof diagnostics were removed.


## Additional runtime acceptance — September 7

| Runtime finding | Accepted correction | Evidence |
|---|---|---|
| Database actor jobs still on main | Explicit serial executor, awaited configured startup, no early legacy fallback | Actual production transaction affinity,16concurrent writes,persist/reopen and startup tests; concurrency assertions active |
| Repeated passive review scans | Shared scoped scalar snapshot, coalesced refresh, timer/permission/account invalidation | Persisted warm-context edit/delete freshness; exact counts and report behavior |
| Stale work during replacement | Retired readers throw, inbound post-await scope checks, queue drain before wipe, revoked image/realtime ownership | Held-response/cancellation/replacement tests preserve queues and prevent obsolete writes |
| Interrupted sync and Spotlight | Cycle-owned busy cleanup; validity inside avatar/submission; batch-owned tracker cleanup | Exact peer review plus deterministic cancellation/avatar/overlapping-batch tests |
| Reporting intent lost at startup | Same-owner progress preserves one-shot reports; stable failure stops; account replacement stays isolated | Original failed2/1/1assertion unchanged and passing;4new gated tests |

Final combined runtime-final-13 at993ca641:168executed/168passed/0failed/0skipped. Runtime-concurrency-12 ate80350dd:38/38passed, assertions independently confirmed enabled; subsequent source changes were limited to review reporting and tests. These counts overlap. Sanitized provenance: executor-mechanism-summary.json. Final build result and source integration are maintained in PM-STATUS.md.
