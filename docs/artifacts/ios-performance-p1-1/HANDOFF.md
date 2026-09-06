# IOS PERFORMANCE - P1-1 handoff

**READY FOR BUILD BATON.** Implementation and lightweight source verification are complete. No build baton held; no xcodebuild, build/test, package resolution, simulator launch, real pending replay, raw phone-store access, or release action occurred.

Worktree: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-1`
Branch: `codex/ios-performance-p1-1`
Audited base: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`

## Atomic commits

1. `28be9966` — Restore released deck schemas, add V26, protect unknown dirty merge bases, add five synthetic migration cases, extend only the V26 fixture entry.
2. `9b5c0d92` — Replace fatal startup with an owned asynchronous storage bootstrap, gate normal app initialization, add recovery UI and four bootstrap cases, record lightweight verification.

The following documentation commit contains this handoff only. Integrate both source commits in order; no sibling adapters are needed for this slice.

## Cross-task contracts

- Current head: `OPSSchemaV26`, still exposed through `OPSSchemaCurrent`.
- `OPSSchemaLegacyDeckDesignV25.DeckDesign` backs released V16–V25; V1–V15 remain unchanged. V26 registers the existing live `DeckDesign`.
- V25→V26 is lightweight and adds only nullable local `syncedDrawingJSON`. No remote schema/query change, metadata rewrite, or merge-base backfill.
- `DeckDesign` retains its API: `syncedDrawingJSON`, `storeDrawingData`, `hasUnsyncedDrawing`, `markDrawingSynced`. No P1-4 signature change.
- Upgrade refinement: `storeDrawingData` seeds a missing base only when the row was clean before the write. Already-dirty legacy rows retain nil until confirmation, including after an unchanged save. Otherwise pre-upgrade unsent geometry would become its own apparent acknowledgement. Existing clean-row seed and confirmed-push semantics are retained.
- No additional persistent fields were requested by another worker. All further model changes still flow through P1-1 and PM.

## Evidence and schema identities

Audit finding 1 and commit `8126e38a` establish that adding the stored field to live DeckDesign rewrote V16–V25. The original compatibility test/output is the existing red baseline; it was not weakened or skipped.

PM's sanitized phone diagnosis reports SQLite quick_check OK, schema identifier V25, original checksum `oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=`, and no ZSYNCEDDRAWINGJSON column. Worker did not access raw customer contents. Tests use only synthetic records/files.

V26's expected fingerprint `W/BL26OkKY5G0Ed7qNE0Bc9SjxDXSTK+LsRyd/fTKy8=` is the widened debug V25 graph measured by the September 6 audit. All 25 existing checksum fixture values remain byte-for-byte unchanged; only V26 is appended. Runtime verification of that V26 expectation is still required.

The widened-debug fixture independently declares the widened deck graph with identifier V25 and pins its observed checksum. It is deliberately absent from OPSMigrationPlan because V26 already has the same graph; adding both creates duplicate compatibility checksums. Its ability to open/reopen with the repaired plan is a required unrun test, not an established claim.

## Startup behavior

`OPSStorageBootstrap` owns one detached container-open/migration task. Concurrent/canceled view waiters join the same attempt; a successful container is retained and reused. Generation guards prevent an old waiter from clearing a later deliberate retry. No ModelContext or model instance crosses actors; ModelConfiguration and ModelContainer are Sendable in the installed SDK and available on iOS 17.

Failures publish structural NSError domain/code only. The retry uses the same configured store. Bootstrap has no file removal, copy, rename, metadata rewrite, alternate/empty container, auth, or sync call.

`OPSInitializedRoot` is installed only for `.ready`, so DataController and service state objects cannot initialize during a failed open. Keeping the state objects on App would not enforce this, because SwiftUI can initialize installed StateObjects even before an explicit wrappedValue read. The original QA root selection and entire ContentView lifecycle/method tail are retained byte-for-byte. AppDelegate/Firebase/notification setup still runs as before; this gates context-dependent app startup rather than claiming all process networking stops.

Recovery UI: `LOCAL DATA UNAVAILABLE`, an honest preserved-file explanation, one `RETRY` button, and advice to contact OPS before reinstalling because unsent work can exist only on the device. Scrollable copy and a bottom safe-area action use existing OPSStyle tokens and primary-button style. No new token values or motion implementation.

## Owned files

- `OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- `OPS/DataModels/Migrations/OPSSchemaV26.swift`
- `OPS/DataModels/Migrations/OPSSchemaCurrent.swift`
- `OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- `OPS/DataModels/DeckDesign.swift`
- `OPS/OPSApp.swift`
- `OPS/Utilities/OPSStorageBootstrap.swift`
- `OPS/Views/Storage/StorageRecoveryView.swift`
- `OPSTests/DataModels/DeckMergeBaseMigrationTests.swift`
- `OPSTests/DataModels/StorageBootstrapTests.swift`
- `OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json`
- This directory's handoff and static verification record.

## Verification performed

See `STATIC-VERIFICATION.md`. Fresh `xcrun swiftc -frontend -parse` on all ten changed/new Swift files and `git diff --check` exited 0. Source comparison proves the frozen deck stored-property declarations match pre-September-4 source; all old fixture values and existing line endings are preserved. The V26 registration differs from V25 only at the deck group. Static design-token review found no new hardcoded styling values.

These are syntax/source checks, not type checking, macro expansion, runtime fingerprints, actual migrations, XCTest results, or UI screenshot proof.

## Focused selectors and exact commands (UNRUN)

Run from the PM integration checkout containing the commits. It must already have the ignored Secrets.xcconfig and approved locked local package checkout. The example uses one integration-only DerivedData directory. Do not run concurrently with any other expensive iOS process. Do not set OPS_V15_STORE_FIXTURE_DIR here; the existing optional private-device fixture test should skip in the synthetic suite.

```sh
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/ops-ios-performance-integration-deriveddata \
  -clonedSourcePackagesDirPath .spm-local \
  -resultBundlePath docs/artifacts/ios-performance-p1-1/storage-tests-01.xcresult \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:OPSTests/AppUpdateMigrationTests \
  -only-testing:OPSTests/DeckMergeBaseMigrationTests \
  -only-testing:OPSTests/StorageBootstrapTests \
  -only-testing:OPSTests/SiteVisitMigrationTests \
  -only-testing:OPSTests/DeckDesignDrawingDataCacheTests \
  -only-testing:OPSTests/DeckDesignSyncTests \
  -only-testing:OPSTests/DeckDesignServerMergeTests
```

Device-target compile (no install/archive):

```sh
xcodebuild build -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/ops-ios-performance-integration-deriveddata \
  -clonedSourcePackagesDirPath .spm-local \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO
```

## Remaining integration requirements / risks

- Compile/macro verification is unrun. First compile should particularly inspect the nested synthetic/frozen models and actor-isolated async bootstrap/XCTest boundary. No known syntax errors remain.
- The unchanged checksum guard must pass for every V1–V26 entry; never replace older values to bless drift.
- Execute populated V16→current and V25→current tests, the unchanged-first-save test, and widened-debug V25→V26 repeated-open test. Verify stopped payload/retry/dependency preservation and synthetic photo bytes.
- Execute unknown-schema preservation/retry, temporary filesystem failure/retry, concurrent/idempotent open and canceled-waiter tests. They use actual synthetic disk stores, not mock migration results.
- Smoke-test the loading/recovery/ready surfaces, retry, large text and VoiceOver, plus ordinary and DEBUG QA launches. No rendered screenshot or iOS 17.6 runtime proof was obtained in this worker.
- PM may separately verify a pure offline migration on a disposable private store copy under its existing authorization. No sync service, network replay, or real phone data changes belong to that proof.
- No claim of device performance, phone recovery, release, or customer-live behavior is made. Source implementation is ready for PM's first serialized verification slice.

## Proposed Bible updates (PM-owned)

Update `03_DATA_ARCHITECTURE.md` schema-head paragraph from V25 to V26; document frozen V16–V25 DeckDesign, adjacent nullable merge-base boundary, original-V25 and widened-debug shape coverage, and the required AppUpdateMigrationTests checksum guard. Clarify that dirty legacy rows keep an unknown base until confirmed and unchanged local saves must not manufacture acknowledgements.

Update the iOS startup/persistence architecture section to describe the owned off-main storage bootstrap, state-gated DataController initialization, preserved-store recovery view and same-location retry. Record verification status accurately after PM runs tests; local implementation is not a phone install or App Store release. No server migration is required for this storage slice.
