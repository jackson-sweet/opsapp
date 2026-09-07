# IOS PERFORMANCE — runtime repair verification

Updated September 7, 2026. Parent task `01a0779e-54bf-72a3-976c-81c692990d23`. Current source: integration `993ca64133060d0c5184cc30526d76430923ba39`; shared main `00e2bc11` contains the initial thirteen repairs at `622010a0` plus documentation. Runtime repairs are not yet merged to main. Founder report: REPAIR-RESULTS.md. Original diagnosis: REPORT.md. Detailed initial acceptance: REPAIR-ACCEPTANCE.md.

## Current verified state

The optimized phone startup recorded five main-thread stalls of 253–384 ms with nominal thermals. Symbolicated samples put database queue/claim/media work on main. The old synchronous actor constructor and detached construction both reproduced main-thread transactions in controlled probes. The repair uses an explicit serial executor and awaited startup. Shared review counts remove repeated task/project enumeration from passive UI rendering.

Production executor/startup checkpoint: 44/44 passed. Review checkpoint: 41/41 passed, plus a separate persisted warm-context read/edit/read test passed. Combined runtime-lifetimes-11: 164 executed, 163 passed, one failed, no skips. The failure is ReviewThresholdServiceTests/test_evaluateFeedsStoreCountsToTheSyncer. All executor/startup/inbound/lifetime/photo/Spotlight cases passed. Runtime-concurrency-12: 38/38 passed with Core Data multithreading assertions independently confirmed active. Counts overlap; do not add them.

The earlier failing review fixture exposed a real report-intent gap at actor readiness. P1-2 correctiona91e1001 (integrated993ca641) preserves same-owner intent across superseded reads and transport, stops stable failures and isolates account replacement. Final combined runtime-final-13 passed168/168,0failures/0skips in59.2seconds, including the unchanged original2/1/1assertion and4new deterministic gated tests. All workers are accepted and idle. Parent final signed optimized build device-signed-runtime-release-02 is running from993ca641; shellsession8160. No other build baton is active.

P1-1's final exact read-only review closed all concrete findings, including cancelled current sync busy-state cleanup (`18ca2a12`) and Spotlight nested-await/batch ownership (`34cbdbc`). P1-3 image retirement and P1-4 executor/startup/inbound/readers/realtime/Spotlight work are accepted and idle. P1-5 remains complete and idle. Task IDs and cursors are in tasks.json. Reuse these tasks; no new workers are required.

## Local source and proof

Integration checkout: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration`, branch `codex/ios-performance-integration`. Runtime source sequence includes explicit factory/startup `6597daf1`, shared review counts `49f2d202`, inbound retirement `22bf9182`, throwing retired readers `8d0f98b1`, review actor guards `e7b4b204`, cancelled cycle cleanup `f8ce539c`, image retirement `0fa09a40`, MainActor teardown correction `95c5eb71`, and Spotlight `e80350dd`. Parent fixture/compiler correction commits are included in the history. P1-2 `14fcf64e` and `53ff2036` duplicate already integrated parent patches; do not cherry-pick them again.

Logs, exact selectors, source revisions and result bundles are under integration `docs/artifacts/ios-performance-combined/`. Sanitized executor-mechanism-summary.json maps the diagnostic controls and production runs. Compile-only failures in production05, freshness07 and lifetime10 were corrected before subsequent runtime runs. The previous fixture patch at `/private/tmp/ops-ios-production-executor-fixtures.patch` was fully reapplied and committed; it is not pending.

Private DerivedData: `/private/tmp/ops-ios-performance-integration-deriveddata`. Private `.spm-local` clones and ignored mode600 signing config remain in integration. Parent-owned synthetic simulator: `1C6A8F09-A337-41F0-AFDD-81C4F3EDFB8A`. Check live processes/disk before expensive work. Never run alongside a sibling build, reuse their DerivedData, stop their processes or delete simulators. Last disk check: 43 GiB available.

Initial repair proof retained: storage68pass/1optionalV15skip; actual disposable V25 upgrade/reopen1pass/0skip preserving16checked groups; final focused core127/127 after earlier failures were resolved; media35/35; real contact-picker UI2/2 with inspected screenshots; initial optimized Release0errors/204warnings; server34/34localPostgreSQL17. These precede the physical executor finding and do not prove runtime lag resolved.

## Authorization and production server state

Jackson explicitly approved the exact reviewed server migration, an optimized in-place iPhone install and online/offline measurements. These approvals persist. No push, App Store release, unrelated production mutation, arbitrary business-data canary or external messaging is authorized.

Applied only the reviewed P1-5 SQL on ops-app/ijeekuhbatykdomumfjx: ledger `20260907001000/site_visit_stage_commands`. Source SHA256 `2f642640d3be1fc273e6bef82ccdc9f0f149d9dac3bbf1fc950dd41b9df696a6`; applied MD5 `4117df9396c7367d6da29c694ea92765`. Parent and independent worker catalog readback match all6functions,2private RLS tables and trigger. The23dependency function fingerprints,100public columns and13public policies were unchanged. Both exact HTTP RPC shapes resolve and deny anonymous callers before invocation with401/42501, no PGRST202. No signed-in snapshot or provider delivery canary was performed. Security advisories:163INFO/263WARN baseline; the only new-object notices are2intentional private deny-all RLS/no-policy INFO. No new-object warning. No Vercel deployment needed.

Applied SQL and contracts are recorded in Bible main `b341ab0`; verified runtime ownership and review reporting are now committed in `f0d076b` (chapters03,04,06 only). Preserve sibling changes in07 and .DS_Store. Shared iOS has unrelated untracked docs/artifacts/task-groups/; preserve it.

## Actual phone evidence and current boundary

Initial signed optimized build: source622010a0, version/build3.0.5, UUID639B0831-CC55-3666-8C84-3C4C034753E7. Signature checked; in-place install independently listed. Pre/post-install database bytes and1664Documents inventory matched. After unlock, both protected recovery files copied; optimized first launch succeeded and actual V25→V26 quick_check passed. All original identities retained for30visits,149artifacts,283answers,25drafts,153decks,967photos,2636outbox rows. All153original drawings byte-equal. Ten queued operations completed through ordinary online sync; the parked operation kept its identity/payload/status. Two photos and one client arrived through ordinary sync. This is verified upgrade/custody, not a measured workflow speedup.

Valid optimized startup trace:60seconds requested/62.045seconds timeline;5main microhangs379.32,383.55,252.60,278.94,276.87ms. Main sampledCPU4068ms of16482ms all-threadCPU. Inclusive frames overlap; no latency percentage inferred. Sanitized physical-upgrade-summary.json, physical-custody-summary.json and physical-startup-profile-summary.json are durable evidence.

A separate Xcode run then installed Debug UUIDE57C1800-7645-3AD2-8EB9-7CB7F010C8F3. Its45second warm trace is excluded. The user was asked whether another task owns device testing; no answer yet. Do not overwrite that phone build until coordination is resolved. The already authorized install does not authorize disrupting an active sibling task.

Device: jPhone iPhone16Pro/iOS26.6.1; CoreDeviceF1B83A71-FF52-5645-BA81-F8B8DB07A44C; UDID00008140-00060D840286801C; bundleco.opsapp.ops.OPS. Last transportlocalNetwork; USB/user workflow readiness still pending. Initial lock is resolved. Computer Use permission was absent and the tool stalled for hours. Do not call CUA again or bypass its permission boundary. CLI profiling works; manual phone interaction requires the user.

Private app safety copies/traces live at `/private/tmp/ops-ios-device-update-20260906/` mode700. Raw database, recovery files, customer records/IDs, keys and logs must never enter Git, reports, fixtures or external services. This is app-specific custody, not a full-phone backup. Do not repeat the1.6GBDocuments transfer. Keep the copies while current device diagnosis needs them; remove task-created copies when their diagnostic purpose ends.

## Remaining sequence

1. Finish signed optimized build device-signed-runtime-release-02 and independently verify signature/UUID. Final168/168 tests are already complete. Parent alone runs expensive checks.
2. Update Bible/report with actual final evidence; integrate runtime repairs on local main, preserving unrelated work. No push or App Store action.
3. Await the pending phone ownership/readiness answer. Once resolved, install the approved optimized build in place and capture the same manual visit/checklist/photo/note/deck/save/reopen sequence online, offline and after reconnect. No comparison to a different Debug binary or idle trace.
4. An actual signed-in read-only stage snapshot remains unverified; never substitute privileged SQL impersonation or synthetic JWTs.
5. Pause ios-performance-pm when local authorized implementation/proof is complete and only the reported physical/coordination step remains. Stay quiet on unchanged state; do not repeatedly prompt.
