# Expense Auto-Batching — Phase 2 · Workstream A (Server + Cross-Cutting) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (or executing-plans) to implement task-by-task. Steps use checkbox (`- [ ]`) tracking.

**Goal:** Add the server pieces the office/field UX needs — atomic approve + early-clear RPCs, a routable notification deep-link, per_job completion-driven send, and server-side under-threshold auto-clear — so Workstreams B (web) and C (iOS) can build on a correct, race-safe server.

**Architecture:** Extends the Phase-1 server brain. Approval moves from the web's non-transactional direct writes to two `SECURITY DEFINER` RPCs that check `expenses.approve` internally and write atomically. The daily sweep is re-applied to emit a routable `action_url` and to send `per_job` envelopes on job completion. `place_expense` gains under-threshold auto-clear.

**Tech Stack:** Postgres (Supabase prod `ijeekuhbatykdomumfjx`), SQL via Supabase MCP `apply_migration`/`execute_sql`. No UI.

**Design System:** N/A (server only).

**Required Skills:** none beyond SQL. (UI skills load in Workstreams B/C.)

**Production safety:** every task is a prod write → **requires explicit user go-ahead** (Task-9-style gate the classifier enforces). Validate each with rollback-wrapped (`raise 'OK_ROLLBACK_SENTINEL'`) `DO`-blocks so no test rows persist. Mirror each migration to `ops-software-bible/migrations/<version>_<name>.sql` and commit (no AI attribution, stage by name). No pushes.

---

## Task A0: Pre-flight verification (read-only, prod)

- [ ] **Step 1:** Confirm the fields the RPCs/sweep depend on. Run on prod:
```sql
select
  (select data_type from information_schema.columns where table_schema='public' and table_name='projects' and column_name='completed_at') as projects_completed_at,
  (select string_agg(column_name,',') from information_schema.columns where table_schema='public' and table_name='expense_settings' and column_name in ('auto_approve_threshold','admin_approval_threshold','review_frequency')) as settings_cols,
  (select string_agg(column_name,',') from information_schema.columns where table_schema='public' and table_name='expense_batches' and column_name in ('reviewed_by','reviewed_at','approved_amount','total_amount')) as batch_review_cols,
  to_regprocedure('public.recalculate_expense_batch_total(uuid)') is not null as has_recalc,
  to_regprocedure('public.has_permission(uuid,text,text)') is not null as has_has_permission,
  to_regprocedure('private.get_current_user_id()') is not null as has_get_current_user;
```
Expected: `projects_completed_at='timestamp with time zone'`; `settings_cols` includes `auto_approve_threshold` + `review_frequency`; review cols present; all `true`. **If `auto_approve_threshold` is named differently, adjust A4. If `projects.completed_at` is absent, find the real completion field before A3.**

- [ ] **Step 2:** Capture how the web currently triggers accounting sync on approve (so early-clear matches). Grep OPS-Web for `accounting-sync-expense` invocation in the approve path (`src/lib/hooks/use-expense-approval.ts`, `expense-approval-service.ts`). Record whether sync is a client edge-function call after the status write (expected) — if so, early-clear's sync stays a **web** follow-up call (B), not part of the RPC.

---

## Task A1: `approve_expense_batch` + `early_clear_expense_line` RPCs

**Files:** Create migration `ops-software-bible/migrations/<ts>_expense_approval_rpcs.sql`.

- [ ] **Step 1: Apply** via `apply_migration` name `expense_approval_rpcs`:
```sql
-- Atomic whole-envelope approve: permission-checked, batch + its non-rejected lines in one txn.
create or replace function public.approve_expense_batch(p_batch_id uuid)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_uid uuid := private.get_current_user_id(); v_batch public.expense_batches;
begin
  if v_uid is null or not public.has_permission(v_uid,'expenses.approve','all') then
    raise exception 'approve_expense_batch: caller lacks expenses.approve';
  end if;
  select * into v_batch from public.expense_batches where id = p_batch_id;
  if v_batch.id is null then raise exception 'approve_expense_batch: batch % not found', p_batch_id; end if;
  update public.expenses set status='approved', updated_at=now()
   where batch_id = p_batch_id and deleted_at is null and status not in ('rejected','approved','reimbursed');
  update public.expense_batches set status='approved', reviewed_by=v_uid::text, reviewed_at=now() where id = p_batch_id;
  perform public.recalculate_expense_batch_total(p_batch_id);
end; $$;

-- Early-clear one line: permission-checked, approve a single line, envelope stays open, notify submitter.
create or replace function public.early_clear_expense_line(p_expense_id uuid)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_uid uuid := private.get_current_user_id(); v_exp public.expenses;
begin
  if v_uid is null or not public.has_permission(v_uid,'expenses.approve','all') then
    raise exception 'early_clear_expense_line: caller lacks expenses.approve';
  end if;
  select * into v_exp from public.expenses where id = p_expense_id;
  if v_exp.id is null then raise exception 'early_clear_expense_line: expense % not found', p_expense_id; end if;
  update public.expenses set status='approved', updated_at=now() where id = p_expense_id;
  if v_exp.batch_id is not null then perform public.recalculate_expense_batch_total(v_exp.batch_id); end if;
  insert into public.notifications(user_id, company_id, type, title, body, expense_id, deep_link_type, action_url, action_label, dedupe_key)
  values (v_exp.submitted_by::text, v_exp.company_id::text, 'expense_approved', 'Expense approved',
          coalesce(v_exp.merchant_name,'Expense') || ' (' || to_char(v_exp.amount,'FM999G999G990D00') || ') was cleared',
          v_exp.id::text, 'expense', '/accounting?tab=expenses', 'VIEW', 'expense_cleared:' || v_exp.id)
  on conflict do nothing;
end; $$;

grant execute on function public.approve_expense_batch(uuid)  to anon, authenticated, service_role;
grant execute on function public.early_clear_expense_line(uuid) to anon, authenticated, service_role;
```
(Note: callable by clients but each internally enforces `expenses.approve`; SECURITY DEFINER does the writes atomically, sidestepping the non-transactional double-write + edit-vs-approve mismatch. Accounting sync stays a web follow-up call per A0.)

- [ ] **Step 2: Validate** (rollback-wrapped) — confirm a non-approver is rejected and an approver path approves batch+lines. Use a sentinel `DO` block on prod that sets a fake JWT context is not possible via MCP; instead assert the permission guard raises for a synthetic no-perm uid, and that the happy path (call as the function owner, which bypasses the guard only if has_permission returns true) approves. Concretely: insert a throwaway batch+line for Canpro, call `approve_expense_batch`, assert batch+line `approved`, then `raise 'OK_ROLLBACK_SENTINEL'`. (Permission-deny path is verified in B against a real non-approver.)

- [ ] **Step 3:** Mirror to bible + commit `feat(expenses): atomic approve_expense_batch + early_clear_expense_line RPCs`.

---

## Task A2: Re-apply sweep — routable deep-link + per_job completion send

**Files:** migration `<ts>_expense_envelope_sweep_v3.sql`.

- [ ] **Step 1:** `create or replace public.expense_envelope_sweep()` identical to the deployed `20260601213757` version EXCEPT: (a) `action_url` becomes `'/accounting?tab=expenses&batch=' || v_batch.id`; (b) the AUTO-SEND selection adds per_job handling — for a batch whose company `review_frequency='per_job'`, gate on the linked project's completion instead of `period_end + grace`:
```sql
-- in the auto-send WHERE, replace the single period_end+grace predicate with:
and (
  case
    when (select s.review_frequency from public.expense_settings s where s.company_id=b.company_id) = 'per_job'
      then (select p.completed_at from public.projects p where p.id = b.scope_project_id) is not null
           and (select p.completed_at from public.projects p where p.id = b.scope_project_id)
               + (coalesce((select auto_submit_grace_days from public.expense_settings s where s.company_id=b.company_id),7) * interval '1 day') <= now()
    else b.period_end + (coalesce((select auto_submit_grace_days from public.expense_settings s where s.company_id=b.company_id),7) * interval '1 day') <= now()
  end
)
```
Keep `revoke … from public, anon, authenticated; grant … to service_role`.

- [ ] **Step 2: Validate** (rollback-wrapped): overdue monthly envelope still sends with `action_url like '/accounting?tab=expenses&batch=%'`; a synthetic per_job company envelope whose project has no `completed_at` is NOT sent, and once `completed_at` is set + grace passed it IS. `raise 'OK_ROLLBACK_SENTINEL'`.

- [ ] **Step 3:** Mirror + commit `fix(expenses): sweep routable deep-link + per_job completion-driven send`.

---

## Task A3: `place_expense` — server-side under-threshold auto-clear

**Files:** migration `<ts>_place_expense_under_threshold_autoclear.sql`.

- [ ] **Step 1:** `create or replace public.place_expense(uuid)` identical to deployed `20260601210846` EXCEPT after the `update … set batch_id …` + recalc, add:
```sql
  -- Under-threshold auto-clear: keep it in the envelope (books complete) but clear the line.
  if coalesce((select auto_approve_threshold from public.expense_settings es where es.company_id = v_exp.company_id), 0) > 0
     and v_exp.amount is not null
     and v_exp.amount < (select auto_approve_threshold from public.expense_settings es where es.company_id = v_exp.company_id)
  then
    update public.expenses set status='approved', updated_at=now() where id = v_exp.id and status <> 'approved';
    perform public.recalculate_expense_batch_total(v_batch.id);
  end if;
```
(Preserve the `order by id` allocation fix.)

- [ ] **Step 2: Validate** (rollback-wrapped): set a throwaway Canpro `auto_approve_threshold=25`, insert a $10 submitted expense → assert it is placed (batch_id set) AND `status='approved'`; insert a $100 expense → assert placed + still `submitted`. `raise 'OK_ROLLBACK_SENTINEL'` (restores threshold too).

- [ ] **Step 3:** Mirror + commit `feat(expenses): under-threshold auto-clear on placement (server-side)`.

---

## Task A4: Bible updates

- [ ] Update `04_API_AND_INTEGRATION.md` (+ `09_FINANCIAL_SYSTEM.md` functions table) with the two RPCs, the per_job send rule, and under-threshold auto-clear. Commit `docs(bible): approve/early-clear RPCs + per_job + under-threshold auto-clear`. (03/09 may carry parallel WIP — patch-stage own hunks as in Phase 1.)

---

## Acceptance (Workstream A)
- `approve_expense_batch` / `early_clear_expense_line` exist, callable by clients, enforce `expenses.approve`, write atomically; non-approver is rejected.
- Sweep emits `action_url=/accounting?tab=expenses&batch=<id>`; per_job envelopes send on project completion, not calendar.
- `place_expense` auto-clears under-threshold lines while keeping them in the envelope.
- All migrations mirrored + committed; advisors clean for new objects; no pushes.
