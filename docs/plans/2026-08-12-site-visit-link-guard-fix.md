# Site-Visit Opportunity Link Guard Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Un-wedge the 114 site-visit sync operations stuck on Jackson's phone and make the server accept the iOS app's designed site-visit lead-linking lifecycle, without weakening the opportunity-child reparent protection for completed records.

**Architecture:** Replace the generic token-only reparent guard on `public.site_visits` with a site-visit-specific guard that (a) allows permission-checked opportunity link changes (attach NULL→X, reassign A→B, clear X→NULL) while the visit is still live (`status` in scheduled/in_progress, `completed_at IS NULL`), (b) keeps completed/cancelled visits locked behind the existing token dance, and (c) still honors minted tokens so admin/RPC paths keep working. Also grant EXECUTE on `private.site_visit_type_fields_valid` to the client roles — its absence is what parks all custom checklist-type creates. **No iOS code changes**: the shipped client's plain PATCH lifecycle becomes valid server behavior, so the phone's queued operations drain as-is on their next retry.

**Why no iOS change:** The iOS capture flow (`SiteVisitCaptureViewModel`) attaches (`reassignVisit`), switches, and clears (`clearIdentitySelection`) the lead on a live visit via plain field updates — `SiteVisitSyncOperation.parent()` always includes `opportunity_id` in changedFields. Every build in the field does this. A server-side RPC-only posture would require an App Store release to stop the bleeding; a permission-checked live-visit window fixes all builds at once. Post-completion the linkage freezes, which is when the record becomes money-bearing evidence (activity, quotes downstream).

**Tech Stack:** Supabase Postgres (prod project `ijeekuhbatykdomumfjx` — low-tenant, direct prod migrations approved), plpgsql trigger function, MCP `apply_migration`. Verification via `xcrun devicectl` device-DB pulls + SQL.

**Design System:** N/A (no UI).

**Required Skills:** `supabase:supabase-postgres-best-practices` for the migration; `superpowers:verification-before-completion` before claiming done.

**Security invariants preserved:**
- Completed/cancelled visits: opportunity linkage immutable except via token dance (unchanged from today).
- Live visits: linkage changes require a resolvable actor (`private.get_current_user_id()`), company match, edit permission on the visit (`private.current_user_can_edit_site_visit`), and — when linking to a target — target opportunity in-company, not archived/deleted, and `private.user_can_edit_opportunity(actor, target)`.
- All other guarded tables (deck_designs, activities, email_threads, …) keep the generic token-only guard untouched.
- Children (`site_visit_capture_artifacts`, checklist answers, identity drafts) stay consistent via the existing `site_visits_propagate_child_opportunity` trigger + `site_visit_child_opportunity_mismatch` checks.

---

### Task 1: Author + apply the migration

**Files:** none local (prod migration via MCP `apply_migration`, name `site_visit_opportunity_link_guard`). Mirror into bible migrations ledger in Task 5.

**Migration SQL:**

```sql
-- Site visits: the iOS capture flow attaches/reassigns/clears the lead on a
-- LIVE visit via plain updates (quick-start visits are born unlinked and
-- linked mid-visit). The generic token-only reparent guard therefore wedges
-- every quick-start visit's sync queue (114 ops on the founder's device,
-- 2026-08-12). Replace it on site_visits only with a permission-checked
-- guard scoped to live visits; completed/cancelled visits keep the token-only
-- lock. All other guarded tables are unchanged.

create or replace function private.guard_site_visit_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
declare
  v_old_opportunity_id uuid := old.opportunity_id;
  v_new_opportunity_id uuid := new.opportunity_id;
  v_consumed boolean;
  v_actor_user_id uuid;
  v_company_id uuid;
  v_target public.opportunities%rowtype;
begin
  if v_old_opportunity_id is not distinct from v_new_opportunity_id then
    return new;
  end if;

  -- Path 1: minted token (admin/RPC flows) — identical semantics to
  -- private.guard_opportunity_child_reparent.
  delete from private.opportunity_child_reparent_tokens token
   where token.transaction_id = txid_current()
     and token.backend_pid = pg_backend_pid()
     and token.table_name = tg_table_name
     and token.row_id = old.id
     and token.old_opportunity_id is not distinct from v_old_opportunity_id
     and token.new_opportunity_id is not distinct from v_new_opportunity_id
  returning true into v_consumed;
  if found and coalesce(v_consumed, false) then
    return new;
  end if;

  -- Path 2: permission-checked change on a LIVE visit. Completed/cancelled
  -- visits are frozen evidence — token-only.
  if old.completed_at is not null
     or old.status::text not in ('scheduled', 'in_progress') then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();
  if v_actor_user_id is null or v_company_id is null then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;
  if old.company_id is distinct from v_company_id::text then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;
  if not private.current_user_can_edit_site_visit(
    old.company_id, v_old_opportunity_id, old.project_id, old.project_ref
  ) then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;

  if v_new_opportunity_id is not null then
    select * into v_target
      from public.opportunities o
     where o.id = v_new_opportunity_id;
    if not found or v_target.company_id is distinct from v_company_id then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
    if v_target.archived_at is not null or v_target.deleted_at is not null then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
    if not private.user_can_edit_opportunity(v_actor_user_id, v_new_opportunity_id) then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_site_visits_guard_opportunity_reparent on public.site_visits;
create trigger trg_site_visits_guard_opportunity_reparent
  before update of opportunity_id on public.site_visits
  for each row
  execute function private.guard_site_visit_opportunity_link();

-- Custom checklist types: the CHECK constraint on site_visit_types calls
-- private.site_visit_type_fields_valid, which was EXECUTE-granted only to
-- postgres — every client-side insert fails with permission denied (32 ops
-- parked on the founder's device). CHECK constraints run as the invoking role.
grant execute on function private.site_visit_type_fields_valid(jsonb) to anon, authenticated, service_role;
```

**Steps:**
1. Apply via MCP `apply_migration` (name: `site_visit_opportunity_link_guard`).
2. Confirm trigger swap: query `pg_trigger` for `site_visits` — trigger must point at `guard_site_visit_opportunity_link`.
3. Confirm grants: `information_schema.routine_privileges` for `site_visit_type_fields_valid` includes anon + authenticated.

### Task 2: Post-apply behavioral tests (fixture transaction, rolled back)

Run a single `execute_sql` DO block that inserts a throwaway visit + opportunity in Jackson's company, then asserts, capturing SQLSTATE in nested BEGIN/EXCEPTION blocks:

1. **No actor, no token, live visit, NULL→X** → expect `42501` (postgres role has no `get_current_user_id()` identity — permission path must NOT open for identity-less callers).
2. **Token minted, completed visit, A→B** → expect success (token path intact).
3. **No token, completed visit, NULL→X** → expect `42501` (frozen after completion).
4. Clean up all fixture rows at the end of the block (delete by fixture ids).

The **permission path's positive case cannot be simulated from MCP** (no client JWT); its verification is Task 3 — the real phone draining is the authoritative end-to-end test.

### Task 3: Device drain verification

1. Jackson opens OPS on the iPhone (failed roots auto-revive at launch; they were retrying as recently as 17:09 UTC today).
2. Re-pull the device store via `devicectl` (retry loop — connection is flaky) and check `ZSYNCOPERATION`: pending+failed for siteVisit* should fall from 114 toward 0. Poll every few minutes.
3. Server-side proof: the 5 visits show `status='completed'`, `opportunity_id` set, `completed_at` non-null; `site_visit_capture_artifacts` / checklist answers rows exist; activities created by `complete_site_visit_guarded`; media objects present in storage.

### Task 4: Parked-item retries (operator action)

Parked ops never auto-retry. After Task 1–3, Jackson opens PENDING WORK and taps RETRY on: 32 checklist-type creates (fixed by the grant), 1 artifact (fixed once its parent linked). Verify server rows after. The 2 parked deckDesign updates (RLS `assigned_lead_scope_update`) are a **separate defect** — investigate after the drain; do not block this initiative on it.

### Task 5: Documentation + records

1. Bible: update site-visit section + migrations ledger in `ops-software-bible` with the guard behavior change (live-visit permission window + completed freeze) and the grant fix. Commit (conventional message, no AI attribution).
2. Update bug `ac712cca-1b45-42fc-b93d-2751751802b1` → `resolved` once the drain is verified.
3. Update memory `project_site_visit_sync_wedge_114.md` with outcome + verification evidence.

**Rollback plan:** re-point the trigger back at `private.guard_opportunity_child_reparent('opportunity_id','id')` (one statement); revoke the grants. No schema shape changes, iOS-sync additive-only constraint honored (no schema change at all).
