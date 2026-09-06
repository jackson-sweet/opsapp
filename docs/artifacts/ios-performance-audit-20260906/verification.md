# Verification — iOS audit, September 6, 2026

**Current source:** `94543f955ca8a2ccee4cc148c24c6d33de92cccc`.

The existing `AppUpdateMigrationTests.testDeclaredSchemaChecksumsStayImmutable` executed on an isolated iPhone 17 simulator running iOS 26.5. **Result: 1 executed, 1 failed, 0 skipped.** This was an assertion failure, not a simulator launch failure. Xcode returned exit code 65.

The test compares the persistent model fingerprints of all 25 declared schema versions against the committed release fixture. V1–V15 match. **Every version V16–V25 differs.** Those ten versions share live `DeckDesign`, which gained stored `syncedDrawingJSON` on September 4 without a new migration stage. This establishes a current schema-compatibility regression. Historical device startup stacks terminate at the same app-level store-opening boundary; their underlying storage NSError remains unavailable.

Evidence: [test summary](/Users/jacksonsweet/Projects/OPS/ops-ios/docs/artifacts/ios-performance-audit-20260906/schema-test-result.json), [sanitized device report metadata](/Users/jacksonsweet/Projects/OPS/ops-ios/docs/artifacts/ios-performance-audit-20260906/device-evidence.json).

Command used:

```sh
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,id=AB2A4B85-7B8E-4877-9DEF-DE3D4C8EDADC' \
  -derivedDataPath /Users/jacksonsweet/Library/Developer/Xcode/DerivedData/OPS-elowtmqmhtazkkfrtzwyyvlyeiol \
  -resultBundlePath /private/tmp/ops-ios-audit-20260906/schema-check.xcresult \
  -only-testing:OPSTests/AppUpdateMigrationTests/testDeclaredSchemaChecksumsStayImmutable \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -disableAutomaticPackageResolution -quiet
```

No other xcodebuild process was active before this run. The temporary audit simulator was removed after verification; no pre-existing simulator was deleted. The existing shared build cache was preserved.

No app source, production database, phone application data, release, or deployment was changed. Source links in the report were checked for existence and valid line numbers. The pre-existing untracked `docs/artifacts/task-groups/` was left untouched.

The performance findings are traced call paths, not freshly measured frame-time improvements. No fix was implemented, and no online/offline A/B interaction trace or broad test-suite result is claimed.
