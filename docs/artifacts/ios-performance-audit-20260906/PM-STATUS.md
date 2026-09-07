# IOS PERFORMANCE — runtime repair in progress

Status: RUNTIME STALLS CONFIRMED; FOCUSED BACKGROUND-EXECUTOR REPAIR IN PROGRESS. September6,2026,23:15PDT. Parent task01a0779e-54bf-72a3-976c-81c692990d23. Founder result:REPAIR-RESULTS.md; diagnosis:REPORT.md; proof map:REPAIR-ACCEPTANCE.md. P1-4 is active on the runtime executor repair. P1-2 completed its read-only audit and is implementing a bounded shared background review snapshot; other workers are accepted and idle.

## Current runtime follow-through (September6,23:15PDT)

User said go ahead; phone was unlocked. Both protected recovery files copied successfully. First optimized on-phone launch/profile completed60seconds; realV25→V26 upgrade opened successfully and quick_checkok. Exact original identities retained for30visits,149artifacts,283answers,25drafts,153decks,967originalphotos and2636outboxrows. All153original deck JSON documents unchanged.10queued operations completed;1parked operation retained exact identity/payload/status;2photos and1client arrived through online sync.

CUA screen viewing stalled for hours behind missing macOS Computer Use permissions; do not call it again or try to bypass permissions. CLI profiling works. Native UI interaction is unavailable; user was asked via async input whether OPS opened normally and to connect USB/confirm readiness for manual visit/photo/note/deck comparison. No answer yet. Current transport last readlocalNetwork.

First profile:5main-thread microhangs379.32,383.55,252.60,278.94,276.87ms at5.478,6.061,8.162,8.414,12.189seconds. ThermalNominal.16,482ms total sampledCPU,4,068ms main sampledCPU over62.045seconds; not latency percent or equivalent-build speedup. Main thread includes DataActor.processPendingOperations1117ms inclusive, executeOperation816ms and media queueArtifactURLUpsert414ms. DataController.setModelContext creates @ModelActor DataActor synchronously onMainActor, so its claimed background executor is actually running onmain. WorkerP1-4 resumed to confirm with regression probe and repair construction/readiness/binding in fresh isolated checkout frommain6f485f72. No build/test baton yet; parent owns integration and phoneinstall. No new server mutation. The second45second attached capture used a DIFFERENT Debug binary, UUIDE57C1800-7645-3AD2-8EB9-7CB7F010C8F3, matching the shared DerivedData Debug product rebuilt22:50:48. It is excluded from comparisons. User was asked whether another task owns phone testing; no phone replacement until coordination resolved. Raw traces/exports/database remain private; summarize symbols/aggregates only.

Historical installation/approval details below remain valid except the prior first-launch lock boundary is now cleared.

## Authorization

Jackson answered Yes to the exact proposal to apply the reviewed server update and install an optimized test build on his iPhone for online/offline measurements. Those actions are authorized; do not ask again. No git push, App Store release, unrelated production mutation or external messaging is authorized. The user was asked to unlock the phone and connect USB for airplane-mode profiling; no reply yet. Apple independently denied launch with FBSOpenApplicationErrorDomain7 Locked. This is a physical action requirement, not an approval-review rejection.

## Server completed

- Applied ONLY the reviewed P1-5 migration on ops-app/ijeekuhbatykdomumfjx. Ledger20260907001000/site_visit_stage_commands. One statement, byte-exact approved source; SHA2562f642640d3be1fc273e6bef82ccdc9f0f149d9dac3bbf1fc950dd41b9df696a6, MD54117df9396c7367d6da29c694ea92765.
- Parent and independent P1-5 readback exactly match local-catalog.json: all6function rows including unchanged legacy,2private RLS tables, exact enabled trigger. Independent23dependency function fingerprints,100public columns and13public policies unchanged. Private constraints/defaults/deny-all ACL verified.
- Both exact HTTP RPC parameter sets resolve and deny anonymous callers before invocation with401/42501; no missing schema-cache capability. Only public anon key and zero synthetic IDs used. No authenticated snapshot, mutating canary, or provider-fanout proof yet.
- Security advisors returned426notices:163INFO,263WARN. Only new-object notices are2intentional RLS/no-policy INFO for private deny-all tables; no new-object warning. Unrelated baseline was not remediated in this migration scope.
- Exact applied SQL mirrored in Bible migrations/20260907001000_site_visit_stage_commands.sql; schema/API/lifecycle updated in local Bible commitb341ab0. Existing unrelated07/.DS_Store work preserved. No Vercel deployment needed; nothing pushed.

## Historical initial phone installation

- Paired jPhone iPhone16Pro/iOS26.6.1, CoreDeviceF1B83A71-FF52-5645-BA81-F8B8DB07A44C; initially connected over localNetwork. Existing development identity/profiles cover phone and all3app targets.
- Signed Release build succeeded33.5seconds from verified source622010a01839387a91e6fadbba3444950f6acfff; same production source as optimized/UI-verified8ef739cd. Deep/strict codesign verification passed. Binary UUID639B0831-CC55-3666-8C84-3C4C034753E7, arm64, version/build3.0.5.
- Apple install command succeeded in place, followed by independent installed-app listing. No uninstall/reset/data deletion. Database after installation is byte-identical to fresh preinstall copy, quick_checkok, WAL0. All1,664Documents files retain exact sizes/modification dates. Both protected recovery-file entries likewise remain unchanged by metadata; their content was not read while locked.
- First launch attempt was denied explicitly because phone is locked. Physical V25→V26 first launch, authenticated snapshot and latency remain unverified. This is not an App Store release or measured lag resolution.

## Private custody and build baton (current details override initial lock notes)

Private safety data is retained at /private/tmp/ops-ios-device-update-20260906/ under mode700 while first launch is pending. Contains current app/group inventories, pre/post-install group copies, complete Documents backup and partial other app folders.7group files85,287,664bytes and1,664Documents files1,551,901,947bytes matched the source inventory exactly. Protected recovery vault content could not be copied while locked; its phone original and metadata remain intact. This is not a full-phone backup. Never put these contents, record IDs, keys, data hashes or raw logs into git/reports/external tools. Finish protected-file copy after unlock; remove task-created private copies after successful first-launch/data validation and diagnostic purpose ends.

The earlier private V25 migration-proof copies were removed after their successful test; the new safety copy is distinct. Integration checkout /Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration retains production source622010a0 plus two probe commits, currentHEAD7462292d, .spm-local and generic build/test evidence. Signed app: /private/tmp/ops-ios-performance-integration-deriveddata/Build/Products/Release-iphoneos/OPS.app. Phone traces/transfers completed. Executor-probe-01 completed in54.3seconds at integration3078bc4d:2executed,1pass,1fail,0skip. Old MainActor constructor control passed; detached-constructor real transaction still reported main, so the simple detached fix is NOT proven. Worker is refining the mechanism probe (constructor vs method vs transaction and container creation thread). Expanded four-case probe87b2586e is cherry-picked as7462292d and ready. Parent is waiting for external xcodebuildPID12985, cwdOPS, to finish before running executor-probe-02. No worker build baton. Before any new heavy build/test, check current processes and disk. Preserve untracked iOS docs/artifacts/task-groups/, dirty shared ops-web and Bible07/.DS_Store.

## Remaining authorized sequence (current)

1. Complete the measured executor/startup repair with P1-4. Test construction, actor method entry and transaction thread separately; verify no early legacy sync, stale publication, auth/reset regression or context crossover. P1-2 implements the accepted shared review-snapshot repair in a fresh runtime checkout, coordinated with P1-4 readiness; no builds.
2. Build/test serially in the integration checkout after checking external builds. Review, integrate and document only proven repairs.
3. Resolve pending phone ownership question before replacing the Debug build installed by another Xcode run. Initial optimized install and its real V25→V26 upgrade/data custody are already verified; don't repeat or erase them.
4. With USB and user readiness, capture only OPS traces for a manual visit→checklist→photos→notes→deck→return→save/reopen sequence, then equivalent offline/reconnect conditions. No arbitrary production business-data canary. Computer Use is unavailable; do not retry or bypass it.
5. Verify a read-only stage snapshot through the actual signed-in Firebase bridge without exposing credentials or customer values. No SQL impersonation or privileged synthetic JWT.
6. Report measured results honestly; preserve other work and keep the Bible/report current. Remove task-created private diagnostic copies after their purpose ends. Push and App Store release remain unapproved.

## Local proof retained

13audit recommendations implemented; source integrated on local iOS main622010a0 plus documentation-only commits. Storage68pass/1optionalV15skip; actual disposable copiedV25→V26/reopen1pass/0skip with16group count/keyed content-custody equality. Core03 287/292pass, core04 306/309pass, finalcore05 127/127pass/0skip closing every observed failure; counts overlap. Media35/35pass. Real contact-picker UI2/2pass/0skip with inspected screenshots. Original optimized unsigned iPhone build0errors/204warnings/854sec; not warning-free or Swift6 migration. Server34/34localPostgreSQL17pass. General artifacts remain in integration docs/artifacts/ios-performance-combined; sanitized summaries are here.

## Automation

Existing ios-performance-pm heartbeat is ACTIVE for runtime repair follow-through. Prompt updated to honor the completed migration/install approvals, serial build baton, blocked Computer Use tool, and phone ownership clarification. Stay quiet on unchanged state. Pause when authorized implementation/proof is complete or only the clearly reported physical/coordination step remains. P1-5 is idle; its final cursor is in tasks.json.
