# Lead Existing-Project Match Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Let an authorized operator match a lead to the eligible existing project surfaced by conversion preflight, without creating a duplicate or bypassing the canonical conversion transaction.

**Architecture:** Keep `get_conversion_preflight` as the read authority and `convert_opportunity_to_project(p_link_to_project_id:)` as the only write authority. The conversion sheet will distinguish review-only related projects from server-approved match candidates, hold the candidate selection until the operator confirms, and submit creation or matching through one guarded function. Remove the direct `opportunities.project_id` patch and post-conversion relink/unlink UI.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Supabase Postgres RPC, SwiftData display cache

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`

**Required Skills:** `supabase:supabase`, `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

---

### Task 1: Pin the matching contract with failing tests

**Skills:** `superpowers:test-driven-development`, `supabase:supabase`

**Files:**
- Modify: `OPSTests/Pipeline/LeadAssignmentFoundationTests.swift`
- Modify: `OPSTests/Views/ConvertOthersBannerSnapshotTests.swift`
- Test: `OPSTests/Pipeline/LeadAssignmentFoundationTests.swift`

**Design tokens:** N/A for the network-free contract tests; snapshot fixtures continue using `OPSStyle` tokens.

1. Add a test proving a likely-duplicate preflight ref routes to `.match`, while a same-client informational ref routes to `.open`.
2. Add a test proving the conversion submission target carries the selected project id and changes the final CTA from `CREATE PROJECT` to `MATCH PROJECT`.
3. Run the focused test and confirm it fails because the routing/submission types do not exist yet.

### Task 2: Replace the unsafe direct link with guarded matching

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Modify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift`
- Modify: `OPS/Views/Leads/LeadDetailView.swift`
- Modify: `OPS/Views/Leads/Components/LeadDetailsDocument.swift`
- Modify: `OPS/ViewModels/LeadDetailViewModel.swift`
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
- Delete: `OPS/Views/Leads/Sheets/LeadProjectPickerSheet.swift`

**Design tokens:** Existing `OPSStyle.Colors` semantic colors, `OPSStyle.Typography`, `OPSStyle.Layout` spacing/radius/touch-target tokens, and the existing sheet/card/button primitives only. Add no color, spacing, radius, or font literals.

1. Implement pure action-routing and submission-target types used by both tests and UI.
2. Make a preflight candidate's `MATCH` chip select the project; keep non-candidate project chips review-only.
3. Render the selected state with existing semantic tokens and change the primary CTA to `MATCH PROJECT`.
4. Funnel create and match through one conversion method that supplies the selected id as `linkToProjectId` and preserves the guarded stage/assignment snapshot.
5. Route the unlinked dossier PROJECT affordance to the conversion sheet; remove relink/unlink affordances for already-linked projects.
6. Delete the direct repository/view-model association mutation and its local picker.
7. Run the focused tests and confirm they pass.

### Task 3: Verify the complete conversion surface

**Skills:** `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Files:**
- Verify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift`
- Verify: `OPS/Views/Leads/Components/LeadDetailsDocument.swift`
- Verify: `OPSTests/Views/ConvertOthersBannerSnapshotTests.swift`

**Design tokens:** Audit every changed UI value against the existing `OPSStyle` semantic tokens and the 44-point mobile touch floor.

1. Run the conversion foundation tests and banner snapshot harness on the isolated simulator DerivedData path.
2. Inspect the rendered selected-match state at the narrow supported width.
3. Run a full `OPS` simulator build with code signing disabled.
4. Review the diff for any direct project-link patch, hardcoded styling, unsafe retry, or unrelated changes.

### Task 4: Update the OPS Software Bible and bug record

**Skills:** `supabase:supabase`, `superpowers:verification-before-completion`

**Files:**
- Modify in an isolated Bible worktree: `09_FINANCIAL_SYSTEM.md`
- Modify in an isolated Bible worktree: `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

**Design tokens:** N/A.

1. Document that iOS `MATCH` candidates come from authorized conversion preflight and commit only through `p_link_to_project_id`.
2. Document that post-conversion relink/unlink is not a client-side field patch.
3. Commit the iOS fix and Bible update atomically in their respective repositories.
4. Record the exact commits and verification evidence on live `public.bug_reports`, leaving it `in_progress` with human review required.
5. Stop for Jackson's manual verification; do not push or start another bug.
