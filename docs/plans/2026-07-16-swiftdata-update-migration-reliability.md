# SwiftData Update Migration Reliability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make an installed V15 OPS store migrate to the current app without `NSCocoaErrorDomain 134504`, preserve the store on any future container-load failure, and fail tests whenever a released schema fingerprint drifts.

**Architecture:** Freeze the exact V15 `Opportunity` and `DeckDesign` shapes, introduce their additive fields only in a new V16 lightweight stage, and point app bootstrap at V16. Centralize the SwiftData configuration on the existing OPS App Group and replace the catch-all destructive reset with a throwing loader that leaves the store untouched. Lock every schema fingerprint with Core Data metadata so future in-place model changes cannot silently rewrite released versions.

**Tech Stack:** Swift 5, SwiftData, Core Data SQLite metadata, XCTest, Xcode 26.5.

**Design System:** N/A — persistence and bootstrap only; no interface work.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `superpowers:using-git-worktrees`, `custom-skills:executing-plans`, `superpowers:verification-before-completion`.

---

### Task 1: Reproduce the released-schema drift in tests

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/DataModels/AppUpdateMigrationTests.swift`
- Modify: `OPSTests/Catalog/CatalogDataFoundationTests.swift`

**Step 1: Write failing structural assertions**

Add tests proving that the migration plan must end at V16, V15 must not reference the widened live `Opportunity` or `DeckDesign` types, and the app-update boundary must contain one stage after V15.

**Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath .dd-local -clonedSourcePackagesDirPath .spm-local \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:OPSTests/AppUpdateMigrationTests \
  -only-testing:OPSTests/CatalogDataFoundationTests/testMigrationPlanStagesHaveModelSetDeltasAcrossAllVersions
```

Expected: FAIL because the current plan ends at V15 and both changed live models still participate in V15.

### Task 2: Add the V15 to V16 migration boundary

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPS/DataModels/Migrations/OPSSchemaV16.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV1.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV2.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV3.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV4.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV5.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV6.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV9.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV10.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV11.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV12.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV13.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV14.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaV15.swift`
- Modify: `OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- Modify: `OPS/OPSApp.swift`
- Test: `OPSTests/DataModels/AppUpdateMigrationTests.swift`

**Step 1: Freeze the V15 model shapes**

Copy the exact pre-July-14 stored properties for `Opportunity` and `DeckDesign` into migration-only nested models. Preserve entity names, property types, defaults, uniqueness, and timestamps exactly; exclude `Opportunity.images`, `Opportunity.latitude`, `Opportunity.longitude`, and `DeckDesign.opportunityId`.

**Step 2: Version-scope both models**

Remove the live types from `OPSSchemaCommon.unchangedModels`. Add V1-V15 arrays pointing to the frozen types and a V16 array pointing to the live types. Update every V1-V15 schema to include the frozen arrays.

**Step 3: Add V16 and its lightweight stage**

Create `OPSSchemaV16` from the V15 model set with only the two live widened models substituted. Append V16 to `OPSMigrationPlan.schemas`, add a single V15-to-V16 lightweight stage, and make `OPSApp` construct `Schema(versionedSchema: OPSSchemaV16.self)`.

**Step 4: Add the real row-preservation test**

Create V10 and V15 SQLite stores, insert one frozen opportunity and one frozen deck design, reopen each through the full migration plan as V16, and assert all old values survive while the four new fields default to empty/nil and accept new values.

**Step 5: Run focused migration tests and verify GREEN**

Run the Task 1 command plus `PhotoAnnotationMigrationTests`, `ActivityMigrationTests`, and `SiteVisitMigrationTests`.

Expected: all selected tests pass with no 134504, 134110, or duplicate-checksum errors.

### Task 3: Preserve the real App Group store on bootstrap failure

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPS/Utilities/OPSModelStore.swift`
- Modify: `OPS/OPSApp.swift`
- Modify: `OPSTests/DataModels/AppUpdateMigrationTests.swift`

**Step 1: Write failing configuration and preservation tests**

Assert the production configuration explicitly uses `group.co.opsapp.ops` and hosted tests remain in memory without App Group storage.

**Step 2: Run the focused test and verify RED**

Expected: compile/test failure because the centralized store loader does not exist and current bootstrap deletes a different container's files.

**Step 3: Implement the minimal non-destructive loader**

Create one configuration factory using `ModelConfiguration.GroupContainer.identifier("group.co.opsapp.ops")`. Make it the sole bootstrap path. On container failure, report the exact configuration URL and terminate without deleting, moving, or overwriting any store file. Remove `destroyDefaultStore()` and the catch-all wipe/retry behavior.

**Step 4: Run the focused tests and verify GREEN**

Expected: configuration points at the App Group store and failed loads preserve the SQLite file and sidecars.

### Task 4: Lock released schema fingerprints

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json`
- Modify: `OPSTests/DataModels/AppUpdateMigrationTests.swift`
- Modify: `OPSTests/Catalog/CatalogDataFoundationTests.swift`

**Step 1: Add a metadata fingerprint test with one deliberately incorrect fixture value**

For V1 through V16, create a SQLite store and read Core Data's public `NSPersistentStoreModelVersionChecksumKey` compatibility checksum. Compare those checksums to the checked-in fixture.

**Step 2: Run and verify RED**

Expected: the deliberately incorrect entry fails and prints the computed digest.

**Step 3: Record the verified V1-V16 digests**

Replace the incorrect fixture with the computed values only after confirming all 16 declared versions are present and distinct.

**Step 4: Run twice and verify GREEN/stability**

Expected: identical results on both runs. Any future stored-property edit to a released schema will now fail this test.

### Task 5: Update the OPS Software Bible

**Skills:** none beyond the plan workflow.

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/06_TECHNICAL_ARCHITECTURE.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_ARCHITECTURE.md`

Document V16, the four additive fields it owns, the explicit App Group store location, the non-destructive failure policy, and the fingerprint-fixture release rule. Correct the stale container example that still shows an unversioned schema.

### Task 6: Full verification and atomic commit

**Skills:** `superpowers:verification-before-completion`

**Step 1: Run the complete migration-focused suite**

Run all migration and catalog schema tests on the required iPhone 17 / iOS 26.5 simulator destination.

**Step 2: Run a generic iOS device build**

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .dd-device -clonedSourcePackagesDirPath .spm-local \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

**Step 3: Review diffs and commit**

Stage only the migration, bootstrap, tests, fixture, plan, and Bible files. Commit as:

```bash
git commit -m "fix(ios): preserve SwiftData stores across app updates"
```

Do not push.
