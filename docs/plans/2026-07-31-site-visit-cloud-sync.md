# Site Visit Cloud Sync Implementation Plan

> **For Codex:** REQUIRED EXECUTION SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Use the Supabase and Supabase Postgres best-practices skills for every database task. Use `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, and `ops-copywriter:ops-copywriter` for the small Pending Work / logout UI changes, then run `custom-skills:audit-design-system` before calling the UI complete.

**Goal:** Make every site visit created or edited on iPhone durably reach Supabase, remain usable offline, resume on a second phone before completion, complete exactly once, preserve its project handoff, and erase/export correctly with the company account.

**Architecture:** Keep SwiftData as the immediate offline source of truth and use its existing `SyncOperation` log as the only outbox. Sync the existing `public.site_visits` parent first, followed by normalized artifact, checklist-answer, and identity-draft rows. Media uploads are restart-safe local operations that publish the resulting remote URLs into artifact rows. A guarded, idempotent Postgres completion RPC marks the parent complete, refreshes compatibility projections, and creates at most one timeline activity. There is no server outbox, delivery, or receipt table.

**Tech stack:** SwiftUI, SwiftData, Swift Concurrency, Supabase Swift, Next.js 15, TypeScript, Vitest, PostgreSQL, Row Level Security, Supabase Realtime, S3 presigned uploads, XCTest, and physical iPhone verification.

**Approved product contract:** Opening a visit immediately creates a durable local visit and queues it for cloud persistence. Operators can capture offline without waiting. When a connection returns, an in-progress visit becomes resumable on another authorized phone. **SAVE VISIT** means “the visit is complete”; it is not the first cloud save. The screen only dismisses after the visit and its required queue chain have been committed locally. Cloud retry remains invisible unless work is genuinely stuck, in which case it appears in the existing Pending Work surface.

**Design source:** `docs/superpowers/specs/2026-07-31-site-visit-cloud-sync-design.md` (commit `d63d922c`). This plan supersedes the local-only site-visit decision in `docs/superpowers/specs/2026-07-22-sync-recovery-design.md` §7 while retaining that design's retry and Pending Work conventions.

---

## Hard invariants

1. A capture mutation and its durable queue operation commit in the same SwiftData transaction or neither commits.
2. IDs are lowercase UUID strings at every new boundary. Existing uppercase local IDs are canonicalized during recovery without duplicating rows.
3. Parent `site_visits` upsert completes before any child, media, or completion operation can run.
4. Completion is a distinct, non-coalescible operation and cannot overtake currently captured child/media work.
5. The database is the only writer of the completion activity. iOS and web call the same RPC.
6. Retrying completion returns the same completed visit and the same activity; it never creates a second activity.
7. A later lead/client/project binding on an already completed visit re-invokes the completion RPC so a previously unbound visit gains its one activity when it becomes linkable.
8. `site_visits.company_id`, new child `company_id` columns, and `project_photos.company_id` remain `text`; `activities.company_id` remains `uuid`. The completion RPC resolves and verifies the canonical UUID instead of blindly casting legacy text.
9. Every new server table—including any newly discovered queue, receipt, event, outbox, delivery, or storage-linkage table—is classified in the company-data manifest, customer export decision, scope/privilege snapshots, transactional purge order, regression tests, deletion rehearsal, and Software Bible in the same feature.
10. No trigger, purge path, or test may use `session_replication_role`, disable triggers, or bypass foreign keys.
11. Voluntary logout cannot silently destroy unsent visit work. Forced authentication teardown stores an encrypted, company- and user-scoped local recovery bundle that only the same identity can restore.
12. Project conversion reuses already-uploaded site-visit objects and keeps `site_visit_id` provenance; it does not upload a second copy.
13. Normal project-photo soft deletion does not delete the shared S3 object. A future physical-object collector must prove the URL has no active references in either table before removal.
14. `SiteVisitType` templates remain local authoring templates in this change. The per-visit checklist snapshot is the cloud-backed, cross-device record, so a resumed visit never depends on the originating phone's template row.

---

## Cross-repository release order

The work spans three repositories and must be integrated in this order:

1. **Satisfied baseline:** Wave 1 is merged into local `ops-web/main` at `c709ad2b` (W1-6 account-deletion parent `d8fef5f0`; nothing pushed or deployed). The combined tree passed type-check, lint, and 139 focused Wave 1 tests. Its manifest audits 220 tables, exports 96, and supplies one 199-step transactional purge.
2. Create dedicated feature worktrees from `ops-web/main` at `c709ad2b` (or a verified descendant containing it) and the current local `ops-ios/main`. Recommended paths:
   - `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync`
3. Land database + deletion/export + web contract changes first. Do not deploy web or apply the production migration without Jackson's explicit live-schema/deploy approval.
4. Land iOS schema, sync, capture, recovery, and logout changes against the verified database contract.
5. Update the Software Bible in the same release before any merge is considered complete.
6. Run live authenticated phone, second-device, customer export, and account-purge rehearsals. Only then merge/deploy or prepare the App Store build.

The existing unrelated edits in the primary `ops-ios` checkout (`OPSStyle.swift`, scheduler files, and scheduler tests at plan-writing time) are not part of this feature and must remain untouched.

---

## Task 1: Establish clean execution worktrees and freeze the live contract

**Files:**

- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/data/company-data-manifest.ts`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/supabase/migrations/20260731161122_transactional_company_data_purge.sql`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/supabase/migrations/20260731170226_account_purge_immutable_event_exception.sql`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-ios/docs/superpowers/specs/2026-07-31-site-visit-cloud-sync-design.md`

### Step 1: Gate on the finished erasure contract

Confirm `c709ad2b` is an ancestor of the web feature branch and its route, manifest, snapshots, migrations, and tests are present. The gate is failed if `public.purge_company_data(company_id, manifest_plan)`, the transaction-local marker `ops.company_data_purge_company_id`, or the W1-6 site-visit rehearsal proof is absent. Record the 220-table / 96-export / 199-step counts as the relative baseline; do not hardcode them as permanent constants.

### Step 2: Create isolated feature worktrees

Use the worktree skill and create large-feature branches named `feat/site-visit-cloud-sync` in each repository. Do not rebase or rewrite a branch used by another task. Copy the gitignored `OPS/Utilities/Secrets.xcconfig` into the iOS worktree only after verifying the destination file does not exist.

### Step 3: Re-read live schema, functions, policies, privileges, publication, and migration history

Using the Supabase tools against project `ijeekuhbatykdomumfjx`, record read-only proof for:

- all columns, types, defaults, constraints, indexes, RLS policies, and grants on `site_visits`, `activities`, `project_photos`, `clients`, `sub_clients`, and `deck_designs`;
- definitions and privileges for `private.current_user_can_edit_site_visit`, `private.get_current_user_id`, `private.get_user_company_id`, `public.purge_company_data`, and the allowlisted purge helper;
- `supabase_realtime` publication membership and replica identity;
- the newest applied migration version.

Abort and reconcile the plan if live types differ from these verified planning facts: `site_visits.company_id text`, `project_photos.company_id text`, `activities.company_id uuid`, `site_visits.id uuid`, `clients.id uuid`, `sub_clients.id uuid`, and `deck_designs.id uuid`.

### Step 4: Run clean baselines

Web:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
npm test -- --run tests/integration/company-data-manifest.test.ts tests/integration/data-export-route.test.ts tests/integration/data-delete-account-route.test.ts tests/integration/uploads-presign-s3.test.ts tests/unit/s3-path-auth.test.ts
```

Expected: all selected tests pass on the feature base.

iOS:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-sync-baseline -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitCapturePacketTests -only-testing:OPSTests/SiteVisitHandoffDurabilityTests -only-testing:OPSTests/SiteVisitMigrationTests -only-testing:OPSTests/RecoveryInventoryTests
```

Expected: `TEST SUCCEEDED`. If a shared Xcode process is active, use a unique DerivedData directory and never kill or reuse the sibling's build.

---

## Task 2: Specify the database contract with failing tests

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/site-visit-cloud-sync-migration.test.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/lib/api/services/site-visit-service.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/company-data-manifest.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/data-export-route.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/data-delete-account-route.test.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/rehearsal/company-data-purge/site-visit-sync-fixture.sql`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/rehearsal/company-data-purge/site-visit-sync-rehearsal.test.ts`

### Step 1: Write the migration-shape tests first

Assert the planned migration contains:

- `site_visit_artifacts`, `site_visit_checklist_answers`, and `site_visit_identity_drafts`;
- direct `company_id text NOT NULL` on all three;
- a real single-column FK from each `site_visit_id` to `site_visits(id)`;
- `deleted_at` and `updated_at` on every child;
- `ENABLE ROW LEVEL SECURITY`, explicit policies, explicit table/sequence grants, and explicit RPC grants;
- no `DISABLE TRIGGER`, no `session_replication_role`, and no unconditional immutable-delete trigger;
- an idempotent completion RPC and an activity uniqueness guard;
- publication registration and replica identity for the parent and children.

The test should parse SQL semantically enough to reject commented-out keywords and broad grants. Reuse existing migration contract-test helpers if present.

### Step 2: Write deletion/export failures

Extend the manifest/export/delete tests so they fail until all three tables are:

- company-scoped directly on `company_id` with live type `text`;
- soft-deleted;
- included in customer export because they contain business and personal data;
- ordered before `site_visits` in purge execution;
- represented in live scope and privilege snapshots;
- populated by the deletion rehearsal fixture and absent after purge.

If the final grants intentionally withhold `DELETE` from `service_role`, the tests must additionally require the tables in `DEFINER_PURGED_TABLES` and the narrow SQL allowlist. Otherwise, keep them on the normal manifest-driven delete path and prove the required privilege exists.

### Step 3: Write web completion failures

Mock the Supabase client and assert `SiteVisitService.completeSiteVisit` calls `complete_site_visit_guarded` once, maps the returned visit, and never calls `OpportunityService.createActivity`. Add retry coverage that the same visit/activity result is returned twice.

### Step 4: Run the red tests

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
npm test -- --run tests/integration/site-visit-cloud-sync-migration.test.ts tests/lib/api/services/site-visit-service.test.ts tests/integration/company-data-manifest.test.ts tests/integration/data-export-route.test.ts tests/integration/data-delete-account-route.test.ts
```

Expected: failures identify the missing migration, three missing manifest rows, and the current app-side completion activity.

### Step 5: Commit the executable contract

```bash
git add tests/integration/site-visit-cloud-sync-migration.test.ts tests/lib/api/services/site-visit-service.test.ts tests/integration/company-data-manifest.test.ts tests/integration/data-export-route.test.ts tests/integration/data-delete-account-route.test.ts tests/rehearsal/company-data-purge
git commit -m "test(site-visits): define cloud sync and erasure contract"
```

Use the actual landed rehearsal paths if they changed before execution.

---

## Task 3: Add the normalized visit tables, policies, and guarded completion RPC

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/supabase/migrations/20260731183000_site_visit_cloud_sync.sql`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/data/company-data-manifest.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/data/company-data-scope-snapshot.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/data/company-data-privilege-snapshot.ts`
- Modify: the landed transactional purge allowlist only if Task 2 proves it is necessary.
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/rehearsal/company-data-purge/site-visit-sync-fixture.sql`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/rehearsal/company-data-purge/site-visit-sync-rehearsal.test.ts`

### Step 1: Create business tables, not sync machinery

The migration creates exactly these three tenant tables:

```sql
public.site_visit_artifacts
  id uuid primary key,
  site_visit_id uuid not null references public.site_visits(id) on delete cascade,
  company_id text not null,
  opportunity_id uuid null references public.opportunities(id),
  kind text not null check (...approved artifact kinds...),
  source text not null check (...approved capture sources...),
  title text null,
  body text null,
  asset_url text null,
  rendered_asset_url text null,
  thumbnail_url text null,
  dimensions jsonb null,
  deck_design_id uuid null references public.deck_designs(id),
  included_in_project_review boolean not null default true,
  captured_at timestamptz not null,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null;

public.site_visit_checklist_answers
  id uuid primary key,
  site_visit_id uuid not null references public.site_visits(id) on delete cascade,
  company_id text not null,
  opportunity_id uuid null references public.opportunities(id),
  site_visit_type_id text null,
  field_id text not null,
  label text not null,
  kind text not null check (...approved checklist kinds...),
  required boolean not null default false,
  help_text text null,
  sort_order integer not null default 0,
  answer_value jsonb not null default '{}'::jsonb,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null;

public.site_visit_identity_drafts
  id uuid primary key,
  site_visit_id uuid not null unique references public.site_visits(id) on delete cascade,
  company_id text not null,
  opportunity_id uuid null references public.opportunities(id),
  client_id uuid null references public.clients(id),
  sub_client_id uuid null references public.sub_clients(id),
  client_name text not null default '',
  contact_name text not null default '',
  preferred_email text not null default '',
  additional_emails text[] not null default '{}',
  phone_number text not null default '',
  address text not null default '',
  notes text not null default '',
  created_by text not null,
  last_committed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null;
```

Against the W1-6 baseline and absent unrelated concurrent schema additions, these three direct, exported, soft-delete tables produce relative deltas of +3 audited tables, +3 exported datasets, and +3 purge steps (223 / 99 / 202). Tests must derive the real totals from the manifest so concurrent legitimate additions cannot make the contract stale.

Do not sync `SiteVisitIdentityDraft.searchText`; it is transient UI state and may contain unrelated search fragments. Add length/JSON-shape constraints that match the current client limits, indexes on active `company_id`, `site_visit_id`, `opportunity_id`, and one active checklist row per `(site_visit_id, field_id)`. Add a trigger/helper that rejects a child whose `company_id` differs from its parent while retaining the required direct single-column parent FK.

### Step 2: Add RLS and explicit Data API privileges

Enable RLS on all three tables. Reuse `private.current_user_can_edit_site_visit` through a pinned-search-path helper that loads the parent and verifies both `site_visit_id` and `company_id`. Provide `SELECT`, `INSERT`, and `UPDATE` policies matching the parent visit's assigned-lead scope and company isolation. Normal app deletion is a guarded `UPDATE deleted_at`; do not grant app roles hard `DELETE` merely because the parent currently has a legacy delete policy.

Explicitly grant only the Data API privileges required by the app roles and revoke default function execution before granting the guarded RPC to the actual app roles. Do not rely on automatic new-table exposure. Keep `service_role` privileges aligned with the account-purge snapshot, including hard `DELETE` only when the normal transactional purge path requires it. Add the standard `updated_at` maintenance trigger to every new table.

### Step 3: Add parent compatibility and activity idempotency

Create a unique partial index that permits at most one `type = 'site_visit'` activity per non-null `site_visit_id`. Before creating it, query for duplicates; if any real duplicates exist, stop and prepare a separately reviewed repair rather than deleting data inside this migration.

Add an internal helper that projects normalized rows back into the existing `site_visits.notes`, `measurements`, and `photos` compatibility columns in deterministic capture/sort order. This preserves current web reads while the normalized tables become canonical.

### Step 4: Implement `public.complete_site_visit_guarded`

Use a user-context, idempotent RPC with a pinned search path. Its transaction must:

1. lock the visit row;
2. prove the caller may edit it through the existing helper;
3. resolve `private.get_user_company_id()` to a UUID and require `visit.company_id = resolved_uuid::text`;
4. reject cancelled/deleted visits;
5. refresh the compatibility projections from active children;
6. set `status = 'completed'` and preserve the first `completed_at` on retries;
7. insert or reuse the one `activities` row if the visit has an opportunity/client/project target;
8. stamp `site_visits.activity_id` with the canonical activity id;
9. return the visit plus `activity_id` in a stable JSON contract.

An already completed unbound visit is valid. When a later parent update binds it, the client queues the same completion RPC again; the RPC then materializes the previously impossible activity without changing the original completion time.

### Step 5: Add Realtime publication deliberately

Add `site_visits` and all three child tables to `supabase_realtime` only if absent, and use an appropriate replica identity for safe update/delete payloads. The migration must be idempotent with respect to publication membership.

### Step 6: Integrate deletion/export in the same change

Bump `MANIFEST_VERSION`, add the three direct company-scoped soft-delete/export rows, regenerate live scope and privilege snapshots, and extend the deletion rehearsal with parent + all child fixtures. If the tables are not immutable and `service_role` can delete them, do not add the account-closure marker exception unnecessarily. If actual privileges require the definer purge route, add each exact table to both `DEFINER_PURGED_TABLES` and the SQL allowlist, with the existing transaction-local marker and empty request claims; never broadly grant delete.

### Step 7: Run the focused suite

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
npm test -- --run tests/integration/site-visit-cloud-sync-migration.test.ts tests/integration/company-data-manifest.test.ts tests/integration/data-export-route.test.ts tests/integration/data-delete-account-route.test.ts tests/rehearsal/company-data-purge/site-visit-sync-rehearsal.test.ts
```

Expected: all pass. If the account-erasure feature has landed a canonical reusable rehearsal harness by execution time, extend that harness instead of maintaining a parallel one, update these paths in the plan, and keep the same fixture assertions.

### Step 8: Commit

```bash
git add supabase/migrations/20260731183000_site_visit_cloud_sync.sql src/lib/data/company-data-manifest.ts src/lib/data/company-data-scope-snapshot.ts src/lib/data/company-data-privilege-snapshot.ts tests
git commit -m "feat(site-visits): add durable cloud data contract"
```

---

## Task 4: Route web completion through the database and secure visit media presigns

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/api/services/site-visit-service.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/app/api/uploads/presign/route.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/supabase/user-client.ts` only if a small reusable authenticated-query helper is necessary.
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/lib/api/services/site-visit-service.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/uploads-presign-s3.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/uploads-presign.test.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/unit/s3-path-auth.test.ts` only for retained generic-folder coverage.
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/s3/site-visit-prefix-erasure.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/app/api/cron/storage/site-visit-erasure/route.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/app/api/data/delete-account/route.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/unit/s3/site-visit-prefix-erasure.test.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/tests/integration/site-visit-erasure-cron.test.ts`

### Step 1: Make completion one RPC call

Replace the update-then-best-effort-activity sequence with:

```ts
const { data, error } = await supabase.rpc("complete_site_visit_guarded", {
  p_site_visit_id: id,
  p_completed_at: new Date().toISOString(),
});
```

Map the returned visit, propagate RPC errors, and remove the `OpportunityService.createActivity` call and swallowed catch. Keep the public hook signature stable unless the returned activity id is genuinely needed by the caller.

### Step 2: Add an explicit site-visit media target

Do not accept a caller-supplied site-visit folder. Extend JSON and form-urlencoded presign bodies with a structured target:

```ts
type SiteVisitUploadTarget = {
  targetType: "site_visit";
  siteVisitId: string;
  artifactId: string;
  variant: "original" | "rendered" | "thumbnail";
};
```

After `verifyAuthToken`, build a per-request `getUserScopedClient(token)` and select the parent visit under RLS. Reject missing, deleted, cross-company, or unauthorized visits. Validate both IDs as canonical UUIDs. Derive a deterministic key on the server:

```text
site-visits/{companyId}/{siteVisitId}/{artifactId}/{variant}.{ext}
```

Keep the generic folder route for existing project/training-data callers, but site-visit uploads must never flow through it. Preserve the existing MIME allowlist, rate limit, content-type pinning, S3/Supabase rollback path, filename sanitization, and 10 MB cap.

### Step 3: Prove authorization and stable keys

Add tests for:

- authorized parent returns a key under the server-derived company/visit/artifact path;
- caller-supplied `folder` is ignored/rejected when `targetType = site_visit`;
- foreign-company, missing, deleted, malformed-ID, and RLS-hidden visits return 403/404 without a presign;
- the three variants cannot overwrite each other;
- identical retry requests return a fresh presigned PUT URL for the same deterministic object key and public URL, so a lost response cannot strand duplicate objects;
- generic project and training-data paths remain unchanged.

### Step 4: Run tests and build

Before the build, implement idempotent account-closure media erasure. The delete-account route deletes the deterministic `site-visits/{companyId}/` prefix only after `purge_company_data` commits. A cron protected by the existing cron-secret pattern scans only soft-deleted companies and retries the same prefix deletion until it is empty. Paginate S3 listing, batch `DeleteObjects`, reject unsafe/broad prefixes, and treat an already-empty prefix as success. Do not create a queue/receipt table; if implementation evidence proves one is unavoidable, stop and add it to the manifest, snapshots, privilege contract, purge allowlist/order, export decision, rehearsal, tests, and Bible before continuing.

Tests must prove an active company is never swept, cross-company keys remain, partial S3 failure is retried, pagination deletes every visit object, and a second run is a no-op.

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
npm test -- --run tests/lib/api/services/site-visit-service.test.ts tests/integration/uploads-presign-s3.test.ts tests/integration/uploads-presign.test.ts tests/unit/s3-path-auth.test.ts tests/unit/s3/site-visit-prefix-erasure.test.ts tests/integration/site-visit-erasure-cron.test.ts tests/integration/data-delete-account-route.test.ts
npm run build
```

Expected: all tests pass and Next.js reports a successful production build.

### Step 5: Commit

```bash
git add src/lib/api/services/site-visit-service.ts src/app/api/uploads/presign/route.ts src/lib/supabase/user-client.ts src/lib/s3/site-visit-prefix-erasure.ts src/app/api/cron/storage/site-visit-erasure/route.ts src/app/api/data/delete-account/route.ts tests/lib/api/services/site-visit-service.test.ts tests/integration/uploads-presign-s3.test.ts tests/integration/uploads-presign.test.ts tests/unit/s3-path-auth.test.ts tests/unit/s3/site-visit-prefix-erasure.test.ts tests/integration/site-visit-erasure-cron.test.ts tests/integration/data-delete-account-route.test.ts
git commit -m "fix(site-visits): unify completion and authorize media uploads"
```

Stage only files actually changed.

---

## Task 5: Add the next SwiftData schema without mutating released fingerprints

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/DataModels/Migrations/OPSSchemaV20.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/OPSApp.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/DataModels/Supabase/SiteVisit.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/DataModels/SiteVisits/SiteVisitIdentityDraft.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/DataModels/Enums/FinancialEnums.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitMigrationTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitCloudModelTests.swift`

### Step 1: Reserve the actual next schema version

At plan-writing time the checkout ends at `OPSSchemaV19`; therefore this plan names V20. After rebasing the execution worktree, inspect `OPSMigrationPlan.schemas`. If main has advanced, rename the new file/type to the next adjacent version and update every reference in this task. Never edit a released schema model or its fingerprint to force a migration.

### Step 2: Write migration/model tests first

Test that the prior schema opens and migrates with existing local-only visit rows, artifact rows, answers, and drafts intact. Assert migrated visits receive safe defaults, existing uppercase UUID strings canonicalize during the one-time recovery task rather than breaking the migration, and no unrelated model changes fingerprint.

Add model tests for:

- `.inProgress` status;
- server timestamps and soft-delete/sync bookkeeping;
- canonical parent/child IDs;
- identity draft cloud fields excluding `searchText`;
- compatibility with old `loggedActivityId` data.

### Step 3: Run red tests

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-model-red -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitMigrationTests -only-testing:OPSTests/SiteVisitCloudModelTests
```

Expected: compile/test failures for the missing schema version and fields.

### Step 4: Extend the live models

Add `.inProgress` to `SiteVisitStatus`. Extend `SiteVisit` with the server-backed fields needed to round-trip the live table: project/client refs, duration, assignees, internal notes, measurements/photo projections, calendar event, created-by, updated/deleted timestamps, `needsSync`, and `lastSyncedAt`. Keep `scheduledAt` locally optional for migration safety but make every new visit stamp it immediately; the DTO must never send null to the server. Treat `loggedActivityId` as the local storage slot for server `activity_id` until a later additive rename is warranted—remove its local-only semantics, not its stored field.

Extend `SiteVisitIdentityDraft` with `deletedAt`, `needsSync`, and `lastSyncedAt`. Do not persist cloud search text. Existing artifact and checklist models already have sync fields; preserve them.

### Step 5: Add the adjacent lightweight migration

Create the new version from the current schema model list, using a lightweight migration unless the red migration fixture proves a custom stage is required. Update the application schema registration and comments. Do not delete legacy visit fields during this release.

### Step 6: Run green tests and a device build

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-model-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitMigrationTests -only-testing:OPSTests/SiteVisitCloudModelTests
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/ops-site-visit-model-device -clonedSourcePackagesDirPath .spm-local build
```

Expected: `TEST SUCCEEDED` and `BUILD SUCCEEDED`.

### Step 7: Commit

```bash
git add OPS/DataModels/Migrations OPS/OPSApp.swift OPS/DataModels/Supabase/SiteVisit.swift OPS/DataModels/SiteVisits/SiteVisitIdentityDraft.swift OPS/DataModels/Enums/FinancialEnums.swift OPSTests/SiteVisits/SiteVisitMigrationTests.swift OPSTests/SiteVisits/SiteVisitCloudModelTests.swift
git commit -m "feat(site-visits): add cloud-backed local schema"
```

---

## Task 6: Add DTOs, repositories, and one shared merge mapper

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Supabase/DTOs/SiteVisitDTOs.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Supabase/Repositories/SiteVisitRepository.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitServerMerge.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitDTOTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitRepositoryTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitServerMergeTests.swift`

### Step 1: Write contract tests first

Cover parent and all three child DTOs with realistic JSON fixtures from the migration contract. Tests must prove:

- snake-case coding keys and fractional timestamp tolerance;
- UUID strings canonicalize to lowercase;
- malformed required IDs, enums, JSON, and dates fail or quarantine rather than crash the full sync;
- absent optional legacy fields decode safely;
- identity `searchText` is never encoded;
- checklist `answer_value` preserves every current `SiteVisitChecklistValue` shape;
- artifact dimensions decode through the existing `DimensionsData` compatibility format;
- repository methods always scope by company and use soft deletes;
- completion calls the guarded RPC instead of a table update.

### Step 2: Run red tests

Run the three new test suites with an isolated DerivedData path. Expected: missing symbols.

### Step 3: Implement DTOs and payloads

Define read DTOs plus explicit create/update payloads. Never encode an entire SwiftData model blindly. Parent create must provide the live required fields (`id`, `company_id`, non-null `scheduled_at`, `status`, `created_by`) and may include bound refs. Update payloads include only changed server columns. Child create/update payloads preserve parent/company scope.

### Step 4: Implement the repository

`SiteVisitRepository` owns:

- fetch parent/children for company and `updated_at >= since`;
- fetch the complete bundle by visit id for targeted second-device healing;
- parent/child upsert and soft delete;
- `completeSiteVisit` RPC;
- typed errors that distinguish auth/RLS, FK/dependency, schema capability, transport, and malformed server data.

Do not add write retries inside the repository. Supabase Swift automatically retrying reads does not make writes idempotent; the durable local operation log owns all write retry.

### Step 5: Implement one merge mapper

`SiteVisitServerMerge` applies DTOs to a supplied `ModelContext` and respects `SyncFieldGuard`/pending operations. Both `InboundProcessor` and `DataActor` must call this shared code in later tasks; do not copy merge logic into both large files.

### Step 6: Run green tests and commit

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-repository-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitDTOTests -only-testing:OPSTests/SiteVisitRepositoryTests -only-testing:OPSTests/SiteVisitServerMergeTests
git add OPS/Network/Supabase/DTOs/SiteVisitDTOs.swift OPS/Network/Supabase/Repositories/SiteVisitRepository.swift OPS/Network/Sync/SiteVisitServerMerge.swift OPSTests/SiteVisits/SiteVisitDTOTests.swift OPSTests/SiteVisits/SiteVisitRepositoryTests.swift OPSTests/Sync/SiteVisitServerMergeTests.swift
git commit -m "feat(site-visits): add Supabase repository contract"
```

---

## Task 7: Make every capture write and queue operation atomic

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitSyncOperation.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Services/SiteVisitPersistenceCoordinator.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SiteVisits/SiteVisitDimensionedCaptureStore.swift`
- Modify: other site-visit capture helpers discovered by a full mutation-site search.
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitPersistenceCoordinatorTests.swift`

### Step 1: Inventory every mutation site

Search for writes to `SiteVisit`, `SiteVisitCaptureArtifact`, `SiteVisitChecklistAnswer`, and `SiteVisitIdentityDraft`. Include create/reuse, type selection, note autosave/clear, photos, markup, dimensions, measurements, deck attachment, checklist edits, identity edits, binding/reassignment, include/exclude, cancel/delete, completion, and project handoff. The task is incomplete until no production path can set `needsSync` without inserting or updating a matching open operation.

### Step 2: Write transaction failure tests

Use in-memory SwiftData containers and injectable operation encoding to prove:

- creating a visit inserts the parent and parent-create operation atomically;
- each child mutation inserts/coalesces its own operation in the same transaction;
- an encoding or save failure leaves neither the model mutation nor a misleading success result;
- parent create is the dependency root;
- completion is a separate operation and is never folded into parent create/update;
- binding a completed visit queues parent update followed by a new idempotent completion operation;
- lowercase canonicalization does not fork existing uppercase rows.

### Step 3: Implement typed operation specifications

Add entity cases for `siteVisit`, `siteVisitArtifact`, `siteVisitChecklistAnswer`, and `siteVisitIdentityDraft`. Define a custom `siteVisitComplete` operation type. `SiteVisitSyncOperation` builds JSON payloads and coalescing keys without saving the context itself.

Because `SyncEngine.recordOperation` calls `modelContext.save()` internally, do not use it for these mutations. `SiteVisitPersistenceCoordinator` must insert/update the SwiftData model and its `SyncOperation` inside one `modelContext.transaction`, then save once. Reuse the existing operation model and single `dependsOnId`; do not create another queue.

### Step 4: Replace best-effort `saveContext()` capture paths

Route all inventoried mutations through the coordinator and return a typed result. The view model may update its in-memory collections after commit, but it must not claim success if the transaction failed. Remove the app-side activity task and `postSiteVisitActivityIfNeeded`; completion now only commits local state + operation chain. Retain the stored `loggedActivityId` as the inbound server activity slot.

### Step 5: Run focused tests

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-atomic-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitPersistenceCoordinatorTests -only-testing:OPSTests/SiteVisitCapturePacketTests -only-testing:OPSTests/SiteVisitActivityPostTests
```

Expected: coordinator and capture tests pass. Replace `SiteVisitActivityPostTests` with database-completion queue assertions; its old local-only assertions must be deleted, not merely skipped.

### Step 6: Commit

```bash
git add OPS/Network/Sync/SiteVisitSyncOperation.swift OPS/Services/SiteVisitPersistenceCoordinator.swift OPS/Views/SiteVisits OPSTests/SiteVisits
git commit -m "fix(site-visits): make local capture and queue atomic"
```

---

## Task 8: Implement dependency-aware outbound sync and restart-safe media upload

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitOutboundSync.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitMediaSyncManager.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/PresignedURLUploadService.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/OutboundProcessor.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Utilities/DataActor.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SyncEngine.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitOutboundSyncTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift`

### Step 1: Write dependency and retry tests first

Prove this operation graph:

```text
parent create/upsert
  -> child text/checklist/identity upserts
  -> each media upload
  -> artifact URL upsert
  -> completion RPC
```

Tests must cover offline launch, app kill/restart, duplicate drain, parent failure, child failure, one media failure, completion retry, a child added after an earlier completion operation was queued, and permanent RLS/FK failure parking. Completion must wait for the latest active captured children/media at drain time—not only the dependency snapshot from when Save was tapped.

### Step 2: Add typed site-visit outbound routing

`SiteVisitOutboundSync` resolves the operation into a current model snapshot and calls `SiteVisitRepository`. It owns site-visit-specific coalescing rules:

- create + later updates collapse into one parent upsert while unsent;
- repeated child updates collapse by entity id;
- delete wins over unsent child create;
- completion never coalesces with CRUD;
- a completion retry remains idempotent;
- missing parent is a dependency state, not a generic transport retry;
- a locally deleted/missing entity produces the correct soft-delete/no-op behavior instead of crashing.

Call this helper from both the legacy `OutboundProcessor` and the active `DataActor` outbound route. Keep the behavior in one helper so the two engines cannot drift.

### Step 3: Add site-visit media upload API

Extend `PresignedURLUploadService` with a structured `uploadSiteVisitArtifact(siteVisitId:artifactId:variant:...)` method. It sends the explicit target fields from Task 4 and never constructs a folder.

`SiteVisitMediaSyncManager` reads persisted local URLs from the artifact, uploads original/rendered/thumbnail variants as required, then atomically replaces only the corresponding remote URL fields and queues the artifact upsert. The local file remains until every required variant and its artifact row have synced. On restart, the persisted media operation is sufficient to resume; no in-memory task is authoritative.

Treat dimensioned-photo original and rendered assets as one artifact with independent variants. Do not route pre-project media through `ImageSyncManager` or `DimensionedPhotoSyncManager`; those managers remain responsible for project records after handoff.

### Step 4: Add queue self-healing

Extend the existing orphan sweep so any site-visit model with `needsSync = true` and no open operation is re-driven into the correct operation chain. This is a safety net for historical/legacy writes, not a substitute for atomic coordination. It must be company-scoped and skip quarantined foreign-company bundles.

### Step 5: Run focused tests

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-outbound-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitOutboundSyncTests -only-testing:OPSTests/SiteVisitMediaSyncManagerTests
```

Expected: `TEST SUCCEEDED` with zero duplicate repository calls beyond intentional idempotent retries.

### Step 6: Commit

```bash
git add OPS/Network/Sync/SiteVisitOutboundSync.swift OPS/Network/Sync/SiteVisitMediaSyncManager.swift OPS/Network/PresignedURLUploadService.swift OPS/Network/Sync/OutboundProcessor.swift OPS/Utilities/DataActor.swift OPS/Network/Sync/SyncEngine.swift OPSTests/Sync/SiteVisitOutboundSyncTests.swift OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift
git commit -m "feat(site-visits): sync durable packets and media"
```

---

## Task 9: Add inbound, Realtime, and second-device resume behavior

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/InboundProcessor.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Utilities/DataActor.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/RealtimeProcessor.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SyncFieldGuard.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SyncEngine.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitInboundSyncTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitRealtimeSyncTests.swift`

### Step 1: Write merge matrix tests

Cover parent-first full sync, delta sync, targeted bundle fetch, Realtime insert/update/delete, local pending-field protection, remote soft delete, malformed child quarantine, server activity-id merge, and two-device concurrent edits. Use deterministic last-write behavior based on server `updated_at` for fields with no pending local operation; pending local fields remain protected until their operation resolves.

Required scenario: phone A creates an in-progress visit and adds a note/checklist answer; phone B signs into the same company, syncs, opens the same in-progress visit, sees the captured packet, edits another answer, and phone A receives/merges that update without duplicating the visit or losing its unsent field.

### Step 2: Extend both inbound orders parent-first

Add the four entity cases to `InboundProcessor.syncOrder` and `DataActor.syncOrder` in this order:

```text
siteVisit
siteVisitIdentityDraft
siteVisitChecklistAnswer
siteVisitArtifact
```

Place the parent after its opportunity/client dependencies and before project-photo/note consumers. Route both processors to `SiteVisitServerMerge`; do not add separate merge implementations.

### Step 3: Add targeted self-heal and Realtime routing

When a child arrives without its parent, fetch the bundle by `site_visit_id` and merge parent first. If authorization hides the parent or company mismatches, quarantine the child and surface one Pending Work issue rather than inserting an orphan.

Subscribe to the parent and three child tables only after confirming publication membership and RLS behavior. Register origin suppression for canonical lowercased ids. Realtime accelerates convergence; foreground/background delta sync remains the correctness path.

### Step 4: Protect pending local fields

Extend `SyncFieldGuard` mappings for SwiftData and server column names. A remote echo may clear `needsSync` only after its matching local operation succeeds; an unrelated remote update must not clear pending work.

### Step 5: Run focused tests and commit

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-inbound-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitInboundSyncTests -only-testing:OPSTests/SiteVisitRealtimeSyncTests -only-testing:OPSTests/SiteVisitServerMergeTests
git add OPS/Network/Sync/InboundProcessor.swift OPS/Utilities/DataActor.swift OPS/Network/Sync/RealtimeProcessor.swift OPS/Network/Sync/SyncFieldGuard.swift OPS/Network/Sync/SyncEngine.swift OPSTests/Sync/SiteVisitInboundSyncTests.swift OPSTests/Sync/SiteVisitRealtimeSyncTests.swift
git commit -m "feat(site-visits): resume visits across devices"
```

---

## Task 10: Make Save truthful and surface only actionable stuck work

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SiteVisits/SiteVisitCaptureView.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/RecoveryInventory.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/Components/Sync/PendingWorkView.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SyncStatusCopy.swift` or the actual centralized copy source discovered during execution.
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitCapturePacketTests.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/RecoveryInventoryTests.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SyncStatusCopyPendingWorkTests.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Views/SiteVisitFormSnapshotTests.swift` only if visible output changes.

### Step 1: Write user-outcome tests first

Prove:

- a forced SwiftData transaction failure does not show success or dismiss;
- a successful local durable commit shows the existing terse success and dismisses even while offline;
- a stage-update failure keeps the visit saved and reports the stage issue separately;
- project creation stages its payload only after the completion transaction succeeds;
- normal pending uploads do not interrupt the operator;
- parked/exhausted visit work appears as one grouped Pending Work item with retry;
- VoiceOver labels, Dynamic Type, and 44pt targets remain intact.

### Step 2: Make completion async at the screen boundary

Change `completeVisit()` to return a typed completion result from the coordinator. Both **SAVE VISIT** and **CREATE PROJECT** await that local transaction. Dismiss only on `.committed`. Do not wait for the network or claim “synced.” Preserve the approved product copy register through `ops-copywriter`:

- success remains terse and factual;
- local persistence failure states that the visit was not saved and keeps the screen open;
- normal offline work stays silent because local durability is expected;
- a stage move failure remains distinct from visit saving.

Do not add a new permanent sync badge, setup step, or animation. The existing header's local/offline truth may remain if it is still accurate after copy review.

### Step 3: Group recovery by visit

`RecoveryInventory` must count the parent, children, media variants, and completion operations as one visit bundle for presentation while preserving exact retry diagnostics underneath. Pending Work shows a single tactical row with captured item count and the blocked stage (visit, media, or completion). Retry re-drives the dependency chain, not an isolated child that will fail again.

All visual changes must use `OPSStyle` colors, type, spacing, radii, icons, and the existing Pending Work layout. Run the OPS design, interface, mobile UX, copy, and design-system audit skills. No hardcoded color/spacing/radius/font values.

### Step 4: Run focused tests and snapshot comparison

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-ui-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitCapturePacketTests -only-testing:OPSTests/RecoveryInventoryTests -only-testing:OPSTests/SyncStatusCopyPendingWorkTests -only-testing:OPSTests/SiteVisitFormSnapshotTests
```

Expected: `TEST SUCCEEDED`. If snapshots changed, export the result attachments to `docs/artifacts/site-visit-sync/`, inspect them visually, and keep only useful proof.

### Step 5: Commit

```bash
git add OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift OPS/Views/SiteVisits/SiteVisitCaptureView.swift OPS/Network/Sync/RecoveryInventory.swift OPS/Views/Components/Sync/PendingWorkView.swift OPS/Network/Sync/SyncStatusCopy.swift OPSTests
git commit -m "fix(site-visits): make save state truthful"
```

Stage the actual centralized copy file if its name differs.

---

## Task 11: Reuse uploaded media during project handoff and preserve provenance

**Files:**

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SiteVisits/SiteVisitProjectHandoff.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/ImageSyncManager.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/DimensionedPhotoSyncManager.swift` if its project-row contract requires it.
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Supabase/DTOs/ProjectPhotoDTOs.swift` only if provenance is not already encoded.
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/SiteVisits/SiteVisitHandoffDurabilityTests.swift`
- Modify: relevant image/dimension sync tests discovered during execution.

### Step 1: Write reuse/idempotency tests first

Cover:

- an artifact with a remote original URL creates a `ProjectPhoto` using that URL and queues no upload;
- a local-only artifact continues through the existing project upload path exactly once;
- every project photo sourced from a visit carries lowercased `site_visit_id`;
- retrying handoff does not duplicate rows due to the live `(company_id, project_id, site_visit_id, url)` active unique index;
- dimensioned original/rendered assets reuse their already-uploaded variants and preserve annotations;
- soft-deleting the project photo does not delete or invalidate the active visit artifact URL;
- packet notes and deck links remain idempotent.

### Step 2: Prefer remote URLs in handoff

When a site-visit artifact already has a remote URL, construct the local `ProjectPhoto` around it, set `source = site_visit`, set `siteVisitId`, and queue the row create only. Use `ImageSyncManager`/dimension sync only for artifacts that genuinely remain local. Do not copy the S3 object.

Update current handoff code that intentionally omits `site_visit_id`; the parent now exists in Supabase, so the FK is valid. Preserve the existing in-place local-row healing behavior for artifacts that still upload during conversion.

### Step 3: Run focused tests and commit

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-handoff-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitHandoffDurabilityTests -only-testing:OPSTests/SiteVisitCapturePacketTests
git add OPS/Views/SiteVisits/SiteVisitProjectHandoff.swift OPS/Network/ImageSyncManager.swift OPS/Network/DimensionedPhotoSyncManager.swift OPS/Network/Supabase/DTOs/ProjectPhotoDTOs.swift OPSTests
git commit -m "fix(site-visits): reuse media during project handoff"
```

Stage only changed files.

---

## Task 12: Recover historical orphan bundles and make logout lossless

**Files:**

- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitOrphanRecovery.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/SiteVisitRecoveryVault.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Utilities/DataController.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Views/SettingsView.swift`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPS/Network/Sync/RecoveryInventory.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitOrphanRecoveryTests.swift`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/OPSTests/Sync/SiteVisitRecoveryVaultTests.swift`
- Modify: logout/data-wipe tests discovered by search.

### Step 1: Write recovery matrix tests first

Use fixtures that match the audited phone failure: children with missing parents, two company ids, mixed uppercase/lowercase visit ids, local media paths, incomplete identity drafts, and no site-visit operations. Prove:

- same-company children reconstruct one parent per visit id and queue parent-first sync;
- reconstructed status is `in_progress` unless durable local evidence proves completion;
- scheduled/captured times derive deterministically from earliest child data;
- mismatched-company groups never attach to the signed-in company;
- ambiguous/malformed groups quarantine without upload or deletion;
- the migration is idempotent across launches;
- no child is discarded until its reconstructed or quarantined bundle is durably recorded.

Add logout tests proving all four local site-visit models and their operations are wiped after safe disposition; the current omission of artifact/answer/draft rows must fail.

### Step 2: Implement one-time orphan recovery

Run `SiteVisitOrphanRecovery` after identity/company load and before normal site-visit outbound drain. Group by canonical `(company_id, site_visit_id)`. Reconstruct only groups matching the authenticated company. Use a durable version marker scoped by user + company, but rerun safely if new legacy orphans appear.

Foreign-company and ambiguous groups become RecoveryInventory quarantine entries; they are not visible as active visits to the wrong account.

### Step 3: Add a protected forced-logout vault

Normal voluntary logout first asks the sync engine for a grouped visit-work disposition:

- if no unsent visit work exists, log out normally;
- if work exists and connectivity can progress, keep the user signed in while a bounded flush runs, then log out;
- if work remains, show one terse choice to stay and retry or explicitly discard. Do not hide destructive loss behind the generic confirmation.

Forced auth revocation/token expiry cannot ask. Before clearing the SwiftData store, serialize only unsent/quarantined visit bundles plus referenced local media into an app-private, file-protected recovery vault. Encrypt the bundle with a Keychain-held key and scope its manifest to the exact authenticated user id + company id. Rehydrate only after that same identity/company signs in again, then securely remove the recovered vault entry after the local transaction commits. A different account must neither see nor delete it.

The vault is phone-local machinery, so it does not enter the server company-data manifest. Its encryption key must use a dedicated Keychain service that normal auth-credential cleanup does not erase; remove that key only after all vault entries are restored, explicitly discarded, or deleted with the device account. The vault itself must be deleted on explicit discard and device account deletion.

### Step 4: Complete the wipe list

In `performCompleteDataWipe()`, delete `SiteVisitCaptureArtifact`, `SiteVisitChecklistAnswer`, and `SiteVisitIdentityDraft` before `SiteVisit`. Keep iterative deletion and existing relationship-safe ordering. Verify local media cleanup only removes files whose bundle was synced, vaulted, or explicitly discarded.

### Step 5: Review copy and mobile behavior

Use the required OPS copy/design/mobile skills. The logout guard uses the existing settings alert/sheet language, at least 44pt actions, clear destructive emphasis, Dynamic Type, VoiceOver, and no new animation. The user should understand one fact: leaving now has unsent visit work. Do not expose queue terminology.

### Step 6: Run focused tests and commit

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-recovery-green -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitOrphanRecoveryTests -only-testing:OPSTests/SiteVisitRecoveryVaultTests -only-testing:OPSTests/RecoveryInventoryTests
git add OPS/Network/Sync/SiteVisitOrphanRecovery.swift OPS/Network/Sync/SiteVisitRecoveryVault.swift OPS/Utilities/DataController.swift OPS/Views/SettingsView.swift OPS/Network/Sync/RecoveryInventory.swift OPSTests
git commit -m "fix(site-visits): recover orphaned work across logout"
```

---

## Task 13: Regenerate types and update the Software Bible

**Files:**

- Regenerate: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/src/lib/types/database.types.ts`
- Create mirror: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/migrations/20260731183000_site_visit_cloud_sync.sql`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/04_API_AND_INTEGRATION.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md` only if its storage/recovery section requires the media contract.

### Step 1: Apply to a safe database target before production

Use an existing approved Supabase development branch if one exists. Creating a new branch has a cost and requires `get_cost` plus Jackson's explicit confirmation. If no approved branch exists, validate the SQL locally/static-first and stop for live-schema approval before applying to production.

Apply the migration through the Supabase migration tool, not raw DDL execution. Then query back columns, FKs, policies, grants, functions, indexes, publication membership, manifest snapshots, and the completion RPC definition.

### Step 2: Regenerate types from the applied schema

Use the Supabase type generator against the exact project ref where the migration was applied. Use production project `ijeekuhbatykdomumfjx` only after production application is explicitly approved and verified; a development branch has its own project ref. Replace the generated file as a whole; do not hand-edit generated types. Run the web type/build gate afterward.

### Step 3: Rewrite stale Bible claims

The Bible currently says iOS visits are local-only, never write `site_visits`, omit `project_photos.site_visit_id`, and create completion activity app-side. Replace those claims with:

- the normalized parent/child model and exact live types;
- local atomic outbox and parent-first dependency chain;
- structured site-visit media upload route and S3 key shape;
- cross-device in-progress resume behavior;
- guarded idempotent completion/activity RPC;
- project-photo object reuse and provenance;
- orphan recovery, forced-logout vault, and Pending Work behavior;
- company export/soft-delete/transactional purge classification;
- physical-phone verification requirements.

Document that `SiteVisitType` is a local template while the checklist snapshot is the cloud record. Update source paths and the “last verified” date.

### Step 4: Copy the exact migration into the Bible

The mirror SQL must byte-match the app migration. Verify with:

```bash
cmp /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync/supabase/migrations/20260731183000_site_visit_cloud_sync.sql /Users/jacksonsweet/Projects/OPS/ops-software-bible/migrations/20260731183000_site_visit_cloud_sync.sql
```

Expected: no output and exit 0.

### Step 5: Commit per repository

Web:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
git add src/lib/types/database.types.ts
git commit -m "chore(site-visits): regenerate database types"
```

Bible:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add migrations/20260731183000_site_visit_cloud_sync.sql 03_DATA_ARCHITECTURE.md 04_API_AND_INTEGRATION.md 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md 07_SPECIALIZED_FEATURES.md
git commit -m "docs(site-visits): document durable cloud sync"
```

Stage only the Bible files actually changed and preserve unrelated work.

---

## Task 14: Full verification, live rehearsal, and release gate

**Files:**

- Create as useful proof only: `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync/docs/artifacts/site-visit-sync/`
- No production source changes unless a failing proof uncovers a defect; fix each defect test-first in the owning task/commit.

### Step 1: Run the complete focused web gate

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/site-visit-cloud-sync
npm test -- --run tests/integration/site-visit-cloud-sync-migration.test.ts tests/lib/api/services/site-visit-service.test.ts tests/integration/uploads-presign-s3.test.ts tests/integration/uploads-presign.test.ts tests/unit/s3-path-auth.test.ts tests/integration/company-data-manifest.test.ts tests/integration/data-export-route.test.ts tests/integration/data-delete-account-route.test.ts tests/rehearsal/company-data-purge/site-visit-sync-rehearsal.test.ts
npm run build
```

Expected: all tests pass and production build succeeds.

### Step 2: Run database advisors and live contract readback

After the approved target migration is applied, run Supabase security and performance advisors. Resolve any new finding caused by this migration before proceeding. Query back:

- the three tables and all required columns/FKs/indexes;
- RLS enabled plus policy definitions;
- exact grants;
- completion RPC execution grants and pinned search path;
- one-activity uniqueness index;
- Realtime publication membership;
- manifest scope/privilege snapshot equality.

Provide clickable remediation URLs for any advisor finding. Do not dismiss warnings as unrelated without proving them against the pre-migration baseline.

### Step 3: Run the full site-visit iOS suite

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/site-visit-cloud-sync
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-site-visit-full-tests -clonedSourcePackagesDirPath .spm-local -only-testing:OPSTests/SiteVisitCapturePacketTests -only-testing:OPSTests/SiteVisitHandoffDurabilityTests -only-testing:OPSTests/SiteVisitMigrationTests -only-testing:OPSTests/SiteVisitCloudModelTests -only-testing:OPSTests/SiteVisitDTOTests -only-testing:OPSTests/SiteVisitRepositoryTests -only-testing:OPSTests/SiteVisitPersistenceCoordinatorTests -only-testing:OPSTests/SiteVisitOutboundSyncTests -only-testing:OPSTests/SiteVisitMediaSyncManagerTests -only-testing:OPSTests/SiteVisitInboundSyncTests -only-testing:OPSTests/SiteVisitRealtimeSyncTests -only-testing:OPSTests/SiteVisitOrphanRecoveryTests -only-testing:OPSTests/SiteVisitRecoveryVaultTests -only-testing:OPSTests/RecoveryInventoryTests
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/ops-site-visit-final-device -clonedSourcePackagesDirPath .spm-local build
```

Expected: `TEST SUCCEEDED` and `BUILD SUCCEEDED`.

Then run the repository's agreed full test gate. If it is red, isolate each failure serially and compare with the feature base before calling it a regression. Do not merge while the agreed gate remains red.

### Step 4: Prove the physical-phone offline path

On a real authenticated iPhone using a non-production test tenant or approved production fixture:

1. disable connectivity;
2. start an unbound visit;
3. capture identity, note, checklist, plain photo, annotated/dimensioned photo, and deck reference;
4. background and force-quit the app;
5. relaunch offline and verify the entire packet is intact;
6. tap **SAVE VISIT** and verify immediate truthful local success;
7. restore connectivity;
8. observe Pending Work drain without reopening the visit;
9. query Supabase and prove one parent, exact child counts/content, remote media URLs, completed status, and zero duplicate activity;
10. retry completion and relaunch again; prove counts remain unchanged.

Capture exact visit/company ids and sanitized readback counts in the artifact folder; never commit customer PII or tokens.

### Step 5: Prove second-device resume

On phone A, create an in-progress visit and sync it before completion. On phone B, sign into the same authorized company, pull/receive the visit, resume it, add evidence, and save. Return to phone A and verify convergence. Supabase must show one parent, the union of non-conflicting children, one completion time, and one activity.

Also prove a different-company account cannot see the visit, presign its media, restore its recovery vault, or infer its existence from error detail.

### Step 6: Rehearse customer export and transactional erasure

Populate one fixture company with a visit parent, every child type, an activity, project-photo link, and media URLs. Verify customer export contains the parent and all three child datasets according to the manifest decision. Execute the existing account-deletion rehearsal and prove:

- parent, children, activity, and project-photo rows are gone/soft-deleted as specified;
- no FK, RLS, immutable-trigger, or privilege error rolls back the transaction;
- no server outbox/receipt table was added;
- the account-closure marker is transaction-local and absent afterward;
- triggers and FK enforcement remained enabled.

### Step 7: Check logs and costs

Inspect API, Postgres, Storage, and Realtime logs for the rehearsal window. There should be no repeated 4xx/5xx loop, FK storm, RLS denial for the authorized fixture, or duplicate completion calls beyond intentional retry.

This design adds no vendor or subscription. It does move site-visit media upload earlier, so storage and egress begin before project conversion; record the fixture byte totals and confirm they fit the existing S3/Vercel/Supabase usage envelope. If a tier or paid branch is required, stop and present the exact cost before proceeding.

### Step 8: Final design-system and release audit

Run `custom-skills:audit-design-system` against the touched site-visit/Pending Work/logout views. Confirm zero new hardcoded colors, spacing, radii, fonts, or icons; 44pt targets; outdoor contrast; VoiceOver; Dynamic Type; reduced motion; and no conflicting gesture.

Review `git diff` and `git status` in all three repositories. Confirm every commit is feature-scoped, no unrelated dirty files were staged, the Bible matches the shipped contract, and nothing has been pushed/deployed/applied beyond the explicit approvals received.

### Step 9: Release decision

Only report “ready” when all of the following are evidenced:

- clean focused and agreed full gates;
- successful device build;
- live schema/RLS/privilege/advisor readback;
- physical offline upload proof;
- second-device resume proof;
- exact one-activity proof;
- export proof;
- transactional purge rehearsal;
- design-system audit;
- no unresolved migration or parallel-worktree conflict.

Merging/pushing `ops-web/main`, deploying web, applying production DDL, and shipping the iOS build remain separate explicit approval points.

---

## Expected commit sequence

Web repository:

1. `test(site-visits): define cloud sync and erasure contract`
2. `feat(site-visits): add durable cloud data contract`
3. `fix(site-visits): unify completion and authorize media uploads`
4. `chore(site-visits): regenerate database types`

iOS repository:

1. `feat(site-visits): add cloud-backed local schema`
2. `feat(site-visits): add Supabase repository contract`
3. `fix(site-visits): make local capture and queue atomic`
4. `feat(site-visits): sync durable packets and media`
5. `feat(site-visits): resume visits across devices`
6. `fix(site-visits): make save state truthful`
7. `fix(site-visits): reuse media during project handoff`
8. `fix(site-visits): recover orphaned work across logout`

Bible repository:

1. `docs(site-visits): document durable cloud sync`

Do not squash away the database contract tests or migration boundary during development; they are the audit trail for this repair.
