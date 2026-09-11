# Phase 19 parent phone integration — 2026-09-11

## Outcome

Merged phone implementation `187a36d631a7413ced22d631c3cc153c62eb195f` combines the complete accepted phase head `b028aa553f52a1fb8c0ee123c95e937a2a4bd98a` with exact main `b08de1042bed5d272d52daa83ef1bc30a501fa86`. The merge had no overlapping source conflicts. All reviewed migration/model files remain byte-identical to the accepted phase head. The incoming calendar-address, toast/PIN, receipt and other main changes are retained unchanged.

After the earlier external build finished, one serial unsigned app-hosted regression ran on this exact source. `xcodebuild` exited **0**, `TEST SUCCEEDED`. The independent result-bundle report confirms **140 selected tests: 138 passed, 2 skipped, 0 failures**, across 16 suites. This is one complete combined run, not an aggregation of prior corrected subsets. Local main was subsequently fast-forwarded from the exact original head to the tested merge without modifying unrelated untracked work.

## Verified boundaries

- Every released V1–V27 schema checksum matches its original fixture; only V28 is new. The independent file comparison also confirms all 27 old fixture entries unchanged, with V28 `nKgJeuKrTdQESe0YctzHunky4wMIqOpHYSoPkjdozIk=`.
- `testV27PacketAndOutboxMigrateToV28PreservingEveryStoredField` passed, including independent reopen, exact original scalar/payload custody and seven new nullable fields remaining nil.
- Historical app and site-visit migrations, five Deck migration/custody cases and all-version migration adjacency passed.
- Field writes, originating-actor checks, immutable operation bases, linked photo/metadata/answer ordering, completion receipt handling, explicit conflict recovery, discard and restart persistence passed.
- All 26 calendar mirror cases and both lead-resolution/cache-isolation cases passed alongside the P19 changes.
- All 11 site-visit settings input cases passed. Three conflict-review rendering tests passed; prior visually inspected screenshots remain separate evidence, not a new manual visual review.

The two skipped tests are `testCopiedDeviceV15StoreMigratesToCurrentWithoutLosingRows` and `testCopiedDeviceV25StoreMigratesToCurrentPreservingCustody`, requiring explicit private copied-store fixtures that were not supplied. They are not claimed as passes. Generated populated-store migrations ran successfully.

## Reproduction and evidence

Run [run-parent-integration-tests.sh](run-parent-integration-tests.sh) with a new suffix **only after acquiring the shared build slot**. It rejects an existing result/log path, uses private DerivedData/SourcePackages under `/private/tmp/ops-site-visits-p19`, two jobs, serial tests and `CODE_SIGNING_ALLOWED=NO`. The test-only Mapbox placeholder is not a production credential.

Simulator: `FA315A2B-AD37-45C2-937A-816BD34CDCDD`, iPhone 17 Pro, iOS 26.5. [Independent Xcode summary](parent-integration-result-20260911.json). Result bundle: `/private/tmp/ops-site-visits-p19/phone-tests-parent-integration-20260911.xcresult`. Raw log: `/private/tmp/ops-site-visits-p19/phone-app-tests-parent-integration-20260911.log`. Xcode initially needed permission to populate its report cache; the authorized read succeeded. SDK startup logged a test-host Firebase keychain warning; it did not fail any assertion and is not evidence of authenticated analytics behavior.

The build process exited and an independent process check found no remaining `xcodebuild` or Swift compiler before returning the build slot to the iOS Bugs coordinator. No push, signing, device installation, production migration, company activation, provider/customer message or release was performed. Simulator tests do not prove signed-device offline behavior, a live host grant, production calendar reconciliation or App Store distribution.
