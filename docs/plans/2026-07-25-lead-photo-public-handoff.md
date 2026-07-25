# Lead Photo Public Handoff Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task by task.

**Goal:** Make photos added to a lead load reliably before and after project conversion, while preserving existing lead-photo authorization and recovering every affected live URL without data loss.

**Root cause:** The affected lead and converted project both contain all seven expected photo URLs, but anonymous reads to the current `opportunities/{company}/{opportunity}/...` S3 prefix return `403 Forbidden`. Objects under the established `projects/{company}/...` media namespace return `200 OK`. Upload and conversion persistence are working; the stored URLs point at a prefix the bucket does not expose.

**Architecture:** New lead photos use `projects/{companyId}/leads/{opportunityId}` so they inherit the public project-media read contract without weakening the bucket. Both old and new key grammars continue to authorize deletion through the canonical opportunity edit RPC. Existing live objects are copied server-side, verified as publicly readable, and referenced URLs are rewritten only after the compatible web delete route is deployed.

**Tech Stack:** Swift 6, XCTest, Next.js route handlers, TypeScript, Vitest, AWS S3, Supabase Postgres.

**Required Skills:** `supabase:supabase`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

**Scope boundary:** No UI, styling, animation, or user-facing copy changes. Do not change the project-conversion RPC or photo persistence model. Do not delete legacy S3 objects until every database reference has been migrated and reverified.

### Task 1: Lock the iOS storage-path contract

**Files:**
- Create: `OPSTests/Pipeline/LeadImageStoragePathTests.swift`
- Modify: `OPS/Services/LeadImageService.swift`

1. Add a focused test asserting the lead upload folder is exactly `projects/{companyId}/leads/{opportunityId}`.
2. Run only that test and confirm it fails because the production path helper does not yet exist.
3. Add a pure `LeadImageStoragePath.folder(companyId:opportunityId:)` helper in the existing service source.
4. Use the helper in both immediate upload and durable queue drain.
5. Update the service contract comment so it describes the public project-media namespace.
6. Rerun only the focused test and confirm it passes.

### Task 2: Lock the web upload and delete contracts

**Files:**
- Create: `src/lib/s3/lead-media-key.ts`
- Create: `tests/unit/s3/lead-media-key.test.ts`
- Modify: `src/lib/api/services/lead-photo-upload.ts`
- Modify: `src/app/api/uploads/delete/route.ts`
- Modify: `tests/integration/uploads-delete.test.ts`

1. Add focused unit coverage for the new lead-media folder grammar.
2. Add integration coverage proving both `opportunities/{company}/{opportunity}/...` and `projects/{company}/leads/{opportunity}/...` delete through canonical opportunity authorization.
3. Add denial coverage for a foreign-company nested lead key and a canonical RPC denial.
4. Run only these two test files and confirm the new cases fail.
5. Implement a shared lead-media folder builder and use it for web uploads.
6. Recognize the nested public key before generic project namespace authorization, while preserving legacy opportunity and email-import behavior.
7. Rerun the same two test files once and confirm they pass.

### Task 3: Prove the storage behavior and integrate atomically

1. Copy one affected legacy object server-side to its deterministic new key without changing database references.
2. Confirm anonymous `HEAD` returns `200 OK` for the destination.
3. Review the focused iOS and web diffs for namespace consistency, company isolation, legacy compatibility, and unrelated changes.
4. Commit the iOS change atomically on `fix/lead-photo-handoff-p1-1`.
5. Commit the web change atomically in the prepared clean web worktree.
6. Do not push or deploy without Jackson's explicit permission.

### Task 4: Deploy, recover live references, and close the bug

1. After explicit push/deploy permission, deploy the compatible web route.
2. Reconfirm the production delete route understands both key grammars.
3. Inventory every live `opportunities.images`, `project_photos.url`, and `projects.project_images` reference using the legacy opportunity prefix.
4. Copy all remaining legacy objects to deterministic new keys and prove every destination is publicly readable.
5. In one guarded Supabase transaction, rewrite only references whose source and destination keys match the verified inventory.
6. Read back all affected lead and project rows; confirm zero legacy database references and successful anonymous reads for every new URL.
7. Remove exact legacy objects only after reference count is zero and destination proof is complete; if IAM prevents cleanup, record the exact authorization blocker without risking customer data.
8. Update the OPS Software Bible's lead-photo storage and conversion contract using path-scoped staging.
9. Guard-update only bug `ff1c4e7d-2ad7-40a2-8f6f-63dadb58bacd` with commit, deployment, backfill, and readback evidence, then read it back.
