# IOS PERFORMANCE — current PM status

Parent: `01a0779e-54bf-72a3-976c-81c692990d23`. Updated September 6, 2026.
Status: IMPLEMENTING / COMBINED VERIFICATION. User authorized diagnosis, private phone export, repair sessions and PM coordination. This file is the current snapshot; earlier chronology is in `PM-HISTORY-through-20260906.md`. Exact task IDs, cursors and commits: `tasks.json`. Scope: `../../plans/2026-09-06-ios-performance-repair.md`; audit: `REPORT.md`.

## Current task state

| Task | Ownership | Current state |
|---|---|---|
| P1-1 | Database compatibility | Source integrated; 68 tests passed, 1 optional fixture skipped. Bounded read-only cross-review of P1-2 coordinator active. |
| P1-2 | Visits / continuity / stage client | Finalizing snapshot/default consistency correction, tests, commits and handoff. No build baton. |
| P1-3 | Photos / cache / camera consumers | Four core commits integrated; remaining nonvisit custody adapters and corrupt-manifest reporting active. No build baton. |
| P1-4 | Sync / deck / status | Source 047a7197,193f7464 and handoff69ee624c integrated. Compile awaits P1-2. Worker idle, no build baton. |
| P1-5 | Stage guard server (ops-web) | Final source26816f355 accepted,34/34 local PostgreSQL tests including already_satisfied. Worker idle. No production changes. |

All worktrees: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-N`; each handoff is `docs/artifacts/ios-performance-p1-N/HANDOFF.md`. All local commits only. Shared iOS main remains at audited baseline94543f955ca8a2ccee4cc148c24c6d33de92cccc. Shared ops-web has substantial unrelated WIP; never touch it.

## Integration and serial build baton

Holder: NONE — core03session27519finished exit65.292tests:287passed,5failed,0skipped. Runtime failures beingrepaired beforefocusedrerun. Parent alone schedules heavy iOS verification after checking live processes/disk. Never run parallel builds. Use concise process names, not full compiler arguments.

Integration: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration`, branch `codex/ios-performance-integration`.
Integrated: P1-1 cbf69ec6,257203c2,5697e384; P1-3 core6fd082ce,cd118089,1e142678,636b388e; P1-4 f5319c32,2d99fb3d,199b9624; P1-2 c3825e12,1947d320.
DerivedData: `/private/tmp/ops-ios-performance-integration-deriveddata`; private cloned packages `.spm-local`; gitignored private Secrets.xcconfig. PM simulator: `1C6A8F09-A337-41F0-AFDD-81C4F3EDFB8A` (OPS performance integration, iPhone17/iOS26.5). Retain for remaining tests. Delete only this owned simulator when finished, never all simulators.
First storage xcodebuild session51270 finished exit0:69total,68passed,0failed,1optional skipped. Schema fingerprint, synthetic V16/V25/widened migration, unsent merge-base custody and bootstrap failure/retry tests passed. Shared summary `storage-repair-test-summary.json`; full result in integration `docs/artifacts/ios-performance-p1-1/storage-tests-01.xcresult`. Combined core01 session43121 finished exit65 before tests: unqualified DeckRendererError. P1-4 correction8e7e2ef1 integrated as6c983568. Core02 session24110 finished exit65 before tests: SiteVisitCaptureViewModel.openVisits predicate typecheck timeout at1467. P1-2 owns correction.31class selectors, same isolated cache/simulator. No other compiler active before restart. P1-2 isolation amendment and P1-3 final adapter/isolation fixes still pending integration.

## Next actions

1. Get P1-2 coherent commits and refreshed handoff; integrate without copying WIP. P1-4 already integrated. Begin combined core compile/tests while P1-3 finishes independent adapters if useful.
2. Review/fix any cross-review findings. Verify P1-2 stale local stage vs fresh snapshot and late snapshot fixtures. Integrate P1-3 final consumers/corrupt-manifest repair.
3. Accept finalized already_satisfied server contract and local SQL proof; confirm exact P1-2 wire handling. Initial server migration remains unapplied.
4. Complete focused tests and generic iOS device-target compile, meaningful bounded performance/custody evidence, all13 findings dispositions and Bible updates. Do not equate source change/simulator success with physical-device speed proof.
5. Integrate authorized local source only when coherent, preserving shared work. Prepare exact deployment/install/release proposal only when all local work is verified. No approval question while necessary local work remains.

## Core ownership and contracts

- P1-1 owns every persistent model/schema. V16–25 frozen released deck shape, V26 nullable merge base, unknown dirty drawing remains unsent. Gated storage bootstrap starts DataController only after successful opening.
- P1-2 owns SiteVisitPersistenceCoordinator, CaptureView/Model, narrow OpportunityRepository stage snapshot/search, SiteVisitSyncOperation/OutboundSync, visit tests. Ordinary commit must scope actual changes, including exclusion of pre-existing UNSAVED unrelated changes in same context. Explicit `recoverOrphanedWrites(siteVisitIds: Set<String>? = nil)` is P1-4 repair boundary. Remove unsafe automatic apparently-empty cleanup; preserve partial answers/identity notes, fresh intent vs explicit resume, drafts always savable; required applicable answers gate actual completion.
- P1-3 owns durable camera journal, cache/thumbnail helpers and five nonvisit consumers: LeadDetailView,DaySheetLeadCard,ProjectDetailsView,ProjectActionBar,ProjectFormSheet. SiteVisit adapters stay P1-2. Exact owner company/user/context; stable item ID becomes model artifact/photo ID. Async Bool custody callback returns true only after durable model/outbox commit; acknowledgement never deletes referenced destination bytes. Original bytes retained until safe exact-account delivery/healing. Approved narrow ImageSyncManager release hook; P1-4 leaves it alone. Project form reserves/reuses exact account-scoped project UUID and supports deliberate resume/discard.
- `DurableCaptureStore.pendingContextIDs(companyID:userID:) async throws -> Set<String>` performs one manifest scan including unprepared originals. Unknown/corrupt cannot mean empty. PM also required direct known-owner recover/failedItems not silently swallow corrupt manifests; preserve valid sibling recovery and bytes, coordinate API changes with P1-2.
- `PhotoThumbnailRequest/Loader` does bounded async ImageIO downsampling/fallback. Source-change notification supports wildcard cache clear.
- P1-4 owns SyncEngine, background recovery/status, DataActor/OutboundProcessor/editor holds and DeckBuilder. Ordinary pushes upload-only; controlled launch/reconnect/manual/timer discovery background, scoped8visit batches revalidated on owner context. Both drivers hold exact active deck; JSON decoded in worker to isolate reference caches. Exit reuses saved JSON, thumbnail after disappear only, no stale geometry save. Compact pill summary off main; details on demand. Vault header adapter authenticates off main, throws on unknown/integrity failure.
- Stage command is operationType `siteVisitStageMove`, entityType siteVisit; both drivers use shared executeIfHandled. Exclude generic CRUD coalescing/recovery/completion barriers. Completed visit precedes stage. Missing token parks original command, local save still succeeds. Deleted-parent restoration parks historical stage command. No generic revive or snapshot refresh on retry.

## Stage contract v1 (unreleased)

P1-5 source: `caec2dfae3c4adfe4ce5bc987b5d0bd9d4e498d1`, `e95d12a0650cd09f5095c4e5cd20534f0e1a93d9`, docs `f0022f8054a4c850f0b03b70234263a79707777e`. SQL: `supabase/migrations/20260906171832_site_visit_stage_commands.sql` in isolated ops-web worktree. Live read-only verified project ops-app `ijeekuhbatykdomumfjx`; trusted identity uses private Firebase bridge helpers, not assumed auth.uid. Additive private revision/receipt tables with minimal grants/RLS; never expire receipts.

`read_site_visit_stage_snapshot(p_opportunity_id)` returns version1/capability site_visit_stage_command_v1, trusted actor/company, current stage, opaqueUUID stage_revision, exact UTC timestamp,can_move. Capture during context loading; default/display/selection/delivery decision must bind the SAME snapshot. Late arrival must not silently rebase existing choice. Do not fetch a new expected token during retry.

`apply_site_visit_stage_command` has eight required parameters: command,visit,opportunity,target,expected stage,expected revision,expected actor,expected company. Actor/company assertions checked before receipt lookup/locks/write. Completed company-scoped exact-bound visit required; targets qualifying/quoting/quoted/follow_up/negotiation only. Exact payload repeat returns immutable historical receipt; mismatch22023. Receipt never projects into fresh Opportunity. Missing capability/permission fails closed. SQL55P03/40P01/40001 retry unchanged. Tenant-scoped NOWAIT locks avoid legacy booking inversion. Initial28/28 local SQL tests passed; original legacy function MD5 unchanged34ce4987e8411de6bfbe8d93dcec7afa.

Final accepted amendment, local tests passed34/34 at26816f355f55807232c8c9f8cb3b406d4314d948: explicit `already_satisfied` immutable NO-OP outcome if, after identity/permission/binding/completion/prior-receipt validation, the current eligible lead is exactly the requested target. transition_id null; no stage/transition/manual-attribution write, no claim command caused transition, no refreshed token. Exact replay preserves original outcome after later movement; existing conflict remains conflict. Different target still requires original expected snapshot, missing/invalid revision fails closed. Covers normal completion trigger new_lead→qualifying and same-target external writer without spurious recovery. P1-2 implementing finalized result handling. Initial outcomes applied/already_applied/conflict/not_ready remain.

P1-5 may run its already approved disposable Unix-socket-only PostgreSQL17 cluster with synthetic data and ≤2 SQL sessions, no downloads/Docker/TCP/production. Stop owned cluster afterward.

## Private phone evidence

User-authorized read-only export: `/private/tmp/ops-ios-audit-20260906/private-store/`, directory700/files600. default.store85,245,952 bytes,WAL0; quick_check ok. Released V25 checksum `oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=`, no merge-base column. Sanitized counts:2636queue rows=2625completed,9pending,1inProgress,1parked;30visits,149artifacts,283answers,25identity drafts,153decks,967project photos,484clients. Raw data never in Git/tests/reports/external tools. No app launch/drain with raw store. Only pure offline migration on disposable clone if needed. Delete private export after diagnostic purpose complete.
No phone writes/install. Phone reports show foreground SwiftUI/SwiftData CPU and two storage-opening crashes; optimized online/offline physical tracing remains unrun.

## Bible, evidence and completion boundary

Bible03 local commit `d9734d5` documents local V26 source+68pass evidence explicitly unreleased; primary shared-current schema still V25 until local-main integration. Bible commit6d52e8a documents final prepared server contract in03/04/10, unapplied SQL not archived. Remaining iOS Bible updates P1-2/3/4 needed. Never archive unapplied SQL as applied migration. Preserve Bible pre-existing .DS_Store,07_SPECIALIZED_FEATURES.md,.worktrees/,specs/future/.
No push, production DB mutation/migration, deployment, phone install/data write or App Store release authorized. Local commit/integration/testing authorized. Separate actual physical speed proof from simulator tests/source inference.
Heartbeat `ios-performance-pm` ACTIVE every10minutes on parent; inspect ledger/tasks and continue meaningful work, quiet unchanged. Pause only when all authorized local work is complete or only explicit external action remains.

## Open review amendment — shared-context custody

P1-1 bounded review found ordinary coordinator saves/rolls back the caller shared ModelContext, inadvertently persisting or discarding pre-existing unsaved B edits while saving A. It also materializes all unsaved unrelated scalar state twice per hot mutation. P1-2 accepted both: exact scoped immutable snapshot → separate durable transaction context; never save/rollback caller context, preserve B pending values and prior stored state including absent new draft on success/failure. Hot VM calls explicit visit/entity scope; include unsaved-heavy snapshot-count coverage. No counterevidence. P1-1 review complete; source remains owned P1-2.

P1-3 approved narrow PhotoProcessor ledger write/remove hooks (previous direct writer bypassed accounting); preserve pipeline behavior. New compile warnings in ImageFileManager budget actor access, Sendable default fetch are being fixed with final media amendments.

## Media cross-review closure requirements

P1-4 read-only review accepted two current WIP findings:1 exact original active actor/company must be rechecked across network/manifest awaits before photo remote write,local heal and retirement; account switch retains originals.2 ProjectFormSheet discards partial-good recover result then calls all-or-nothing retainedBatch throwing map, so one bad original blocks good siblings. P1-3 fixing/tests actual retained/form path. Unknown same-version JSON keys loss has no current producer/semantics; do not hold work for speculative format evolution. Document version increment for new custody semantics; higher versions already fail closed. P1-4 review complete/idle. P1-3 background-accounting isolation sourceb4e2418e integrated as163cf001, new StorageProfilerBudgetTests must join next test selectors.

## Latest coordinator implementation decision

P1-2 refined isolation to a dedicated ModelContext for the lifetime of the capture VM (clone injected encoder/validator), avoiding copying registered/inserted models between contexts. Shared coordinator uses explicit isolated transaction entry point; every reachable shared-context production caller must migrate, not turn valid edits into generic failures when other WIP exists. PM approved narrow ClientLeadAutocreateQueue, SiteVisitDimensionedCaptureStore and PendingWorkView adapters. Verify capture/deck/dimensioned/Opportunity context crossings and exact-ID/snapshot resolution, UI observation, and stale shared objects cannot overwrite owned-context saves. P1-1 should re-review final committed amendment before acceptance. Current core02 compile issue is openVisits complex predicate, plus MainActor error-classifier conversion warning; P1-2 owns both.

`REPAIR-ACCEPTANCE.md` maps all13findings to exact proof suites and physical test sequence. Existing hermetic `SiteVisitContactImportUITests` can provide simulator presentation/screenshots after final source compiles; no new auth or phone writes needed. Raw phone V25 cannot use existing optional V15 test (it opens V15 explicitly); do not point that harness at the exported V25 store. Use synthetic V25 proof already passed unless a separate pure offline copied-store harness is deliberately built.

P1-3 journal/reporting/retirement7690fb0c and consumers/draftsce1def1b now integrated. Their accepted account-switch and partial-sibling follow-up is still active; do NOT rerun or call media final before that commit. No build running/batonNONE.

## Core03 integration and remaining visit host issues

P1-2 stage no-op ca26d189 integrated237c624e, dedicated VM/adapter isolation344c3c7b integrated2db96d8f. P1-3 accepted account-switch/partial-sibling amendmentce233114 integratedd4ed1efb (core/adapters alreadyintegrated). Final handoffs pending. Core03 starts all35 verified focused class selectors, includes three new media suites; session27519, docs/artifacts/ios-performance-combined/core-tests-03.log/.xcresult. P1-1 rereview active.

PM independently found two real UI entry leaks AFTER VM isolation: CaptureConsole retains caller environment context; deck creation View1054-1057 saves it directly with try?, persisting B and swallowing failure. Also entry View61 invokes DataController.ensureSiteVisitTypesSeeded, whose extension74 unconditionally saves shared context even no-op, then queues through same shared context. P1-2 approved to close host/seed context boundary, preserve permissions/template coalescing, test entry/deck with unrelated pending B, and align console/deck/sheet models safely with owned context. ExtensionDataController+SiteVisitTypes.swift now narrowly owned P1-2; no other worker touches it. These fixes not yet in core03; don't claim entireflow isolation until tested.

P1-3 final handoff6c687915 is committed/clean; source fullyintegrated throughce233114. Handoffdoc not yet cherry-picked because core03active. All8media selectors included. Sourcehand-off accepted subject to combinedtypecheck/tests, no performanceclaim. Read full worktree HANDOFF for finalBiblemedia text.

## Coordinator rereview result

P1-1 source review through81ed0606 closes original shared-context save/rollback and unsaved-heavy scan findings; dedicated VMcontext and tests represent correct isolation, runtime pending. New P1 introduced by detached lead snapshot: older copyOpportunityFields omits assignmentVersion/summary/images/coordinates/handled-action fields. ConvertToProjectSheet uses snapshot assignmentVersion, leading falseversion0 rejection. P1-2 must use complete Opportunity.apply(_:) and test nonzeroassignmentversion on initial/reassigned snapshot. Reachable queue entry still applyLocalDelivery saves caller before isolated bind; P1-2 must isolate full cache-insert/bind entry, not just downstreamhelper. Both sent.

Bible local commit0ba0298 documents prepared P1-3media/P1-4syncdeck contracts, tests explicitlypending. P1-2 finalcontext/host/seed/queue docstillneeded; update allprepared verification markers after combined success/localmainintegration.

P1-2 additional committed files awaiting integration aftercore03:835f0a1a thumbnail wildcard/source-key fix;81ed0606 handoff (willneedrefresh afterhost/seed/snapshot/queueamendments). P1-3 finalhandoff6c687915 awaitsdocintegration. Core03hasadvanced into compilingOPSTests; no sourcecompileerrorobserved atlastlogread. P1-1reviewdoneidle(cursor4d3cb209-29b6-4e23-9cc3-a88ce9eed94e:6).

Core03progress: compilation finished far enough to launch hosted test processOPS on PMsimulator (PID55186 observed, xcodebuild53787); no compiler remaining. Tests stillrunning/session27519notcompleted, no pass/failcount yet. SiteVisitDimensionedCaptureStore direct coverage is alreadywithin selectedSiteVisitCapturePacketTests (370/421); no guessed classselectorneeded. Keep batonPARENT untilactualexit andparsedxcresult.

## Core03 confirmed result and next diagnostics

292total,287passed,5failed,0skipped; testphase194seconds, build+testabout453seconds. All8media classes plus sync/deck/storage/coordinator/stage cases passed. Fivefailedcases: LeadCapture offline immediate queue and open-visit queue delivery trap; Continuity explicit same-URL markup stilldeclined; two SearchSource tests missing requestgate. Summary copiedshared combined-core03-summary.json. Full integration summary/tree/.xcresult. Relevant diagnostics only in core03-relevant-diagnostics (test-stdout.txt and current135158/135214crashes); export's unrelated hostlogs removed, originalmachinefiles untouched.

Actual LeadCapturetrap: SwiftData instance destroyedbyModelContext.reset,SyncOperation/p8; stackoperationTypegetter→OutboundProcessor.executeOperation→pendingpass→SyncEngine.pushPending. P1-4assigned driverlifetime diagnosis/fix ifprovenproductionissue, P1-2handlesfixtureteardowncoordination/searchbarrier/markupassertion. SearchGate uses100Task.yield spin andcanmisscontinuation registration/finish, leavinghang; replaceboundedexplicitbarrier, no weaker assertions.

LatestP1-2host/seed/completeleadcopy/queueentryfad0e453 integrated1d276f30 AFTERcore03 (unverifiedyet); thumbnail835f0a1a integrated57944273;handoff81ed0606 integrated11819cce;P1-3handoff6c687915 integrated5545703d. Nextfocusedrunmustinclude latesthost/seed/newqueueparent tests aswellasfailedcases and any P1-4driverregressions. Do not rerun allpassedmedia absentcodechanges.

P1-2 testcase amendments9f6c5cdb nowintegrated: explicit MainActor SearchGate registration expectations (5secondbound)+cancellationcleanup; markup reads exact operationID from freshcontext (same pending/retrycountrequirements); deliveredlead fixture commits DTO/parent/draft binding in separate deliverycontext before notifyingVM. Handoff35f84ee6 integrated. Drivercrash stillP1-4diagnosis; fixtureteardownunchanged pending rootcause. Sourceworkerclean atlastread.

## Driver trap root cause established

P1-4: teststdout693 preceding test startsclient send,694passes,695next begins,706destroyedrow. LeadCapturetearDown removescontainerwhileunstructuredrealconnectivitydrain continues. ActualcrashOutboundProcessor518catch readsoperation.operationType afterawait. Appsourcehas no explicitModelContext.reset; observedreset consistentwithcontainerteardown. Productionseparatevulnerability: SyncEngine stop/logout generationonlychecked afterdriverreturns; driver canaccess/mutateoldmodels first. P1-4implementing holdModelContainerduringdrain, cacheclaimIDforcleanup/log, cancellation+driverinvalidation+activeidentity+registeredmodelidentity guards beforecontinuationaccess, includingreconciliation; configure/logoutinvalidateolddriver, gatedtests. P1-2asked independentlymakeLeadCapturefixtureoffline/hermetic and stopownedcontrollers beforecontainersrelease; injectedlead/visibilityassertionsretained. Must keep productionregression, not hidewithfixtureonlychange.

## Typed executor lifetime amendment coordinated

P1-2 owns optional actor-safe `isCurrent` guard on SiteVisitOutboundSync.executeIfHandled and internal completion/upsert/delete awaits, propagated to SiteVisitMediaSyncManager where retainedmodelsaccessafterawait. P1-4 outerdriver guard cannot protectinner accesses beforetypedexecutorreturns. P1-4 passes actual scope+registeredmodelidentity guard frombothOutBoundProcessor/DataActor; no unconditionaltrue productionwhenrealcontextavailable. Defaultretains tests/sourcecompatibility. Exactsignature tocoordinatebetweenowners; no otheroverlap.

P1-2 source93eac1ec marks never-synced blank/scan deck for firstdelivery inactualhostsave, nowintegrated with latesthandoff9d64bd4c. P1-2muststillcomplete hermetic LeadCapturefixture andinnerawaitguard before rerun; earlierREADYdidnotclose these newerrequirements.

PMsmallinterfaceprobe PASSED current swiftc -swift-version5 -strict-concurrency=complete -warnings-as-errors: optional synchronousisCurrent plus `isolation: isolated (any Actor)? = #isolation` asyncAPI preserves bothMainActor/DataActor-style closures/nonSendablelocalstate. Sourceprobe copiedintegration artifacts/combined/isolation-interface-probe.swift; reference officialSE0420 https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md . Forwardedbothowners. Propagateisolationthroughmodel-boundhelpers only; keepheavybytes/file/imageprepoffmain. This is interfacecompilerproof, not actualappregressionverification.

P1-2 hermeticfixture26e9936d nowintegrated (alwaysoffline backgroundsync/pull/photos; retaincontrollers, syncstop+awaitasyncstop beforecontainersrelease). Productiondriverregression remainsP1-4owned. NewacceptedreachablecaptureCREATELEAD leak: VMstillcallsDataController.createClient/updateClientContact/updateClientNotes whichsave sharedcontext. P1-2approvednarrowcapture-sideownedcontextclient+outbox path preservingexistingpermissions/callbacks; no globalDataControllerrepoint/generalclientredesign. P1-1activeboundedread-onlyhelperresearchtoaidP1-2. Test actualCREATELEADwithBpending + priorstoredvalues.

P1-1 interimclienthelperresearch: no existingcontext-parameterclient API; DataControllerrecordOperation/deferPushstillsharedsaves. Use ownedcontext+SyncOperation.init+notifyDurableOperationQueued. IncludecreateMissingSubContacts→createSubClient sharedsave (sameCREATELEADflow/additionalemails) inapprovedadapterboundary; sentP1-2. Parent dependency andnull-field constraints pendingfinalresearch. No workersmaybuild. Core04notstarted; waitsourceguard/clientadaptercommits, integrate, thenfocusedtests.

P1-1clientresearchcomplete/idle, fullconstraintsforwardedP1-2: capture-specifichelperinsideVMcoordinator.commit ownsClient/SubClient+explicitgenericoutbox+draft.clientId atomically; thennotifyDurableOperationQueued only. Existingparentreferenceguardclient_idalreadygatesSubClient. Preservevisibility/queuedleadhandoff/stoppedparent semantics. IncludeLOCALcamelCase changedFieldsguardsalongsideJSONsnake_case (phoneNumber particularly); explicitnilclearsandno-opguards; notescurrentnonblankcapturebehavior. Returnonlyaftercommit, nonewrowafterrollback. NoexistingownedcontextclientAPI found.
