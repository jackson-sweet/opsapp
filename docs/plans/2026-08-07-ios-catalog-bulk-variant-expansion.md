# iOS Catalog Bulk Variant Expansion — Implementation Plan

> Execute with `custom-skills:executing-plans`. Follow strict red-green-refactor, use the approved design in `docs/superpowers/specs/2026-08-07-ios-catalog-bulk-variant-expansion-design.md`, and keep all production and Supabase writes local-only until Jackson explicitly authorizes release.

## Goal

Ship a locally complete iOS flow that expands one option axis across selected stock families, plus an additive atomic Supabase RPC migration. Preserve all existing stock identity and create only zero-stock, blank-SKU variants.

## Architecture

The iPhone owns selection, input, deterministic preview, persisted draft state, and post-success SwiftData reconciliation. A UI-independent planner turns current SwiftData catalog rows into a normalized plan and request fingerprints. `CatalogBulkVariantExpansionService` calls one `catalog_bulk_expand_variants` RPC through `CatalogRepository`; it treats a server success as committed even if local reconciliation must fall back to a catalog resync.

The migration adds a dedicated idempotency receipt table and one `SECURITY INVOKER` RPC. The RPC verifies `private.get_user_company_id()` and `private.current_user_has_permission('catalog.manage', 'all')`, locks selected family rows in deterministic order, validates source fingerprints and variant signatures, then creates/reuses option rows, labels existing source variants, and inserts each new combination in the same transaction. The function has a pinned search path and execute grants only for the Firebase bridge roles already used by the app.

## Task 1 — Prove the planner contract

**Files**

- Create: `OPSTests/Catalog/CatalogBulkVariantExpansionPlannerTests.swift`
- Create: `OPS/Services/Catalog/CatalogBulkVariantExpansion.swift`

**Red tests**

Add literal-fixture tests that name these breaks:

1. New axis fails to label every source variant or emits the wrong clone count.
2. Existing axis clones variants outside the selected source value.
3. A clone loses safe settings, copies SKU/quantity, or loses a non-target option relationship.
4. Case/whitespace variants create a duplicate option/value instead of reusing it.
5. Duplicate requested values, blank input, incomplete option pins, multiple values on one axis, duplicate source signatures, or no real additions do not block review.
6. Mixed families produce unstable ordering or incorrect total counts.
7. Source fingerprints fail to change when a source variant, option pin, or family timestamp changes.

Run the focused test target and capture the expected compilation/test failure before adding production types.

**Green implementation**

Create immutable Codable/Equatable input, preview, blocker, family-plan, source-fingerprint, and RPC payload/response types. Keep normalization in one locale-stable helper. Build plans in family/name/ID-stable order. Explicitly exclude stock units from the clone model.

Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .derived-data-catalog-bulk -only-testing:OPSTests/CatalogBulkVariantExpansionPlannerTests
```

## Task 2 — Prove RPC and reconciliation behavior

**Files**

- Create: `OPSTests/Catalog/CatalogBulkVariantExpansionServiceTests.swift`
- Create: `OPS/Services/Catalog/CatalogBulkVariantExpansionService.swift`
- Modify: `OPS/Network/Supabase/Repositories/CatalogRepository.swift`

**Red tests**

Test the real service boundary with only the network operation injected:

1. The exact company ID, lowercase idempotency key, and planner payload reach the RPC operation.
2. Server blockers remain rejected and do not touch SwiftData.
3. Success inserts/updates returned options, values, variants, and joins in one local save.
4. Existing variants keep IDs, quantities, SKUs, and settings after reconciliation.
5. A post-commit reconciliation error returns committed-with-resync and calls the resync hook exactly once.
6. Replaying the same successful response does not duplicate local rows or joins.

**Green implementation**

Add Codable RPC parameters and `CatalogRepository.expandCatalogVariants`. Implement a main-actor commit/reconcile service modeled on `CatalogSetupCommitService`, but bounded to the expansion response. Normalize returned UUID strings to lowercase before matching. Never translate a successful server response into a failed operation because of local cache repair.

Run the planner and service test classes together.

## Task 3 — Define the atomic server transaction

**Files**

- Create: `OPS/Migrations/2026-08-07-catalog-bulk-variant-expansion.sql`
- Create: `OPS/Migrations/2026-08-07-catalog-bulk-variant-expansion.md`

Implement additive SQL only:

1. Add `catalog_bulk_variant_requests` with company/key uniqueness, request hash, status, response/error, timestamps, company-isolated RLS, and bounded authenticated/Firebase-bridge grants.
2. Add `public.catalog_bulk_expand_variants(p_company_id uuid, p_idempotency_key text, p_payload jsonb) returns jsonb` with pinned `search_path` and explicit relation schemas.
3. Reject missing/malformed IDs, wrong company, missing `catalog.manage`, non-lowercase UUID keys, duplicate family IDs, duplicate/blank values, and oversized payloads.
4. Insert/lock the idempotency receipt and reject key reuse with a different SHA-256 request hash.
5. Lock selected active company families in UUID order and compare every submitted source fingerprint with a server-derived canonical fingerprint.
6. Resolve/create the target axis and values case-insensitively; reject duplicate active option axes if legacy data is ambiguous.
7. Validate every active source has exactly one pin per existing active axis and no duplicate signature.
8. Add the existing-value join to source variants only when the target axis is new.
9. Insert new variants with quantity zero and SKU null, copying only unit/overrides/thresholds/active state, then insert exact non-target pins plus the new target value.
10. Return complete created/reused option, value, variant, and join rows plus family counts; persist the exact response for idempotent replay.
11. On any blocker, return a structured rejection and write no catalog rows. On any SQL exception, let the transaction roll back rather than persisting a misleading partial failure.
12. Revoke execute from public, then grant only to `authenticated`, `anon` for the Firebase bridge, and `service_role`, matching current OPS auth architecture.

Perform migration hygiene checks locally (`git diff --check`, forbidden `auth.uid`, unpinned search path, public execute, destructive DDL) and compare every referenced column/helper against the verified live schema. Do not apply the migration to production.

## Task 4 — Build the guided mobile flow

**Files**

- Create: `OPS/Views/Catalog/Stock/BulkVariants/CatalogBulkVariantExpansionFlow.swift`
- Create: `OPS/Views/Catalog/Stock/BulkVariants/CatalogBulkVariantExpansionModel.swift`
- Create: `OPS/Views/Catalog/Stock/BulkVariants/CatalogBulkVariantFamilyStep.swift`
- Create: `OPS/Views/Catalog/Stock/BulkVariants/CatalogBulkVariantChangeStep.swift`
- Create: `OPS/Views/Catalog/Stock/BulkVariants/CatalogBulkVariantReviewStep.swift`
- Create: `OPSTests/Catalog/CatalogBulkVariantExpansionModelTests.swift`
- Modify: `OPS/Views/Catalog/CatalogView.swift`

**Red tests**

1. Selection/filter/select-all cannot include inactive or invalid families.
2. Continue/apply state is wrong for empty, invalid, offline, stale, saving, and successful states.
3. Draft encoding loses selected families, field values, new values, stage, or idempotency key.
4. Stale-preview response does not return to a refreshed review.
5. Successful commit does not clear the draft and request sync.

**Green implementation**

Add `Bulk Add Variants` beneath `Add Variant`, gated on `catalog.manage`, and present the full-screen flow. Query the existing SwiftData catalog models directly. Use a small observable model for navigation, validation, draft persistence, and injected commit behavior.

UI contract:

- three labeled stages (`FAMILIES`, `CHANGE`, `REVIEW`) without decorative wizard chrome;
- 60-point family rows, search, filtered select-all/clear, explicit selected count;
- labeled option/existing/new-value inputs with inline ownership of errors;
- grouped review with stable counts and expandable family detail;
- fixed safe-area bottom action above the custom tab bar boundary;
- online gating from `DataController.isConnected` and actionable offline text;
- discard confirmation only when the draft contains meaningful input;
- one light haptic on stage transitions, medium on apply, success/error notification haptics once;
- accessibility labels/values/traits, Dynamic Type-safe wrapping, keyboard dismissal, and no iOS-18-only API;
- every color, font, spacing, radius, border, icon, and animation from `OPSStyle`.

Use OPS copy exactly as approved in the design spec. Do not create a notification-rail row because this operation completes synchronously in the foreground.

Run planner/service/model tests, then `xcodebuild build-for-testing` for the full test target.

## Task 5 — Document the shipped contract

**Files**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

Document the dedicated receipt table/RPC, permission and company guards, clone/preservation rules, iOS entry and stages, offline behavior, stale-preview response, and the explicit boundary between bulk dimensional expansion, one-off variant editing, and CSV creation.

Because the Bible is outside the iOS repository, keep its edits isolated from unrelated root work and do not commit unrelated files.

## Task 6 — Audit and verify the whole local feature

1. Run `custom-skills:audit-design-system` over every new/modified SwiftUI file and remove hardcoded visual values.
2. Run Swift syntax parsing for new/modified Swift files.
3. Run all focused Catalog bulk-expansion tests twice: once alone and once with the existing Catalog test group to expose shared-state issues.
4. Run a generic device build with worktree-local DerivedData and SPM cache:

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .derived-data-catalog-bulk build
```

5. Verify `git diff --check`, inspect the final diff for unrelated files, and scan for `TODO`, `FIXME`, unsafe force unwraps, hardcoded colors/spacing/radii/fonts, `auth.uid`, destructive DDL, and unauthorized notification writes.
6. Make atomic local commits for planner/service, migration, UI, and documentation. Do not push, apply the migration, release, or modify Canpro data.

## Completion evidence

Report separately:

- source: locally committed feature and migration;
- automated proof: exact focused test/build results;
- production: migration not applied and no live catalog writes;
- customer/device: not released and not device-proven until an authorized build is installed and the migration is applied.
