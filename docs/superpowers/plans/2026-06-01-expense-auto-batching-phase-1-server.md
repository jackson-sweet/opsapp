# Expense Auto-Batching — Phase 1 (Server Brain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the server the single authority for expense batching and submission, so no client version can strand an expense and envelopes auto-submit for review on a per-org schedule.

**Architecture:** A placement trigger files every non-draft, unbatched expense into a per-person/per-period envelope (`expense_batches`) by the expense's *date*; a daily `pg_cron` sweep auto-sends due envelopes, adopts any orphans, sweeps in completed drafts, and rolls stragglers forward. Reuses the existing `expense_batches` table, `get_or_create_open_batch`, `recalculate_expense_batch_total`, `users_with_permission`, and the `fire_due_task_reminders` notification pattern. All schema changes are additive (the iOS cross-release sync constraint holds; 3.0.2 keeps working).

**Tech Stack:** Postgres (Supabase project `ijeekuhbatykdomumfjx`), pg_cron 1.6.4, pg_net 0.19.5, SQL via the Supabase MCP (`apply_migration` / `execute_sql`). Spec: `ops-ios/docs/superpowers/specs/2026-06-01-expense-auto-batching-design.md`.

**Conventions (verified this session):**
- Migrations are applied via the Supabase MCP `apply_migration` and **mirrored** into `ops-software-bible/migrations/<UTCYYYYMMDDHHMMSS>_<name>.sql`.
- No SQL test harness exists → every task is validated with `execute_sql` assertions **on a Supabase dev branch**, never prod, until Task 9.
- Server-only `SECURITY DEFINER` functions follow the house lockdown: `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated; GRANT … TO service_role`. The existing `get_or_create_open_batch` / `recalculate_expense_batch_total` stay broadly executable (3.0.3 clients still call them during the transition).
- Bible must be updated the **same session** (Task 8): `03_DATA_ARCHITECTURE.md`, `04_API_AND_INTEGRATION.md`, `07_SPECIALIZED_FEATURES.md` §14, `09_FINANCIAL_SYSTEM.md`.

**Production safety:** Tasks 1–8 run entirely on a throwaway Supabase branch. Task 9 (apply to prod + backfill real expense rows) is the only prod-touching step and **requires explicit user go-ahead** before running.

---

## File / object map

New DB objects (all created via migrations mirrored to `ops-software-bible/migrations/`):

| Object | Kind | Responsibility |
|---|---|---|
| `expense_settings.auto_submit_grace_days` | column (int, default 7) | Days after a period ends before its envelope auto-sends |
| `expense_batches_open_unique` | index (replaced) | One active envelope per scope — widened to `status IN ('open','pending_review')` |
| `expense_envelope_period(date, text)` | function | Period window from expense date + cadence (SQL port of `ExpenseBatchPeriod.swift`) |
| `get_or_create_open_batch(...)` | function (extended) | Now creates/looks up the **`open`** filling envelope |
| `place_expense(uuid)` | function | Attach one expense to its envelope (by date), roll forward if home period approved |
| `tg_place_expense()` + `trg_place_expense` | trigger fn + trigger | Fire `place_expense` on any non-draft, unbatched expense |
| `expense_envelope_sweep()` | function | Daily: auto-send due envelopes + notify, sweep completed drafts, adopt orphans, roll forward |
| `expense_envelope_sweep_daily` | pg_cron job | Runs the sweep once a day |
| `expense_batches` RLS | policy (added) | Gate transition-to-`approved` to `expenses.approve` holders |

Plan doc: this file. Spec: as above. Migration SQL: `ops-software-bible/migrations/`.

---

## Task 0: Create an isolated Supabase dev branch

**Files:** none (MCP only)

- [ ] **Step 1: Create the branch**

Run via Supabase MCP: `create_branch` with `project_id = ijeekuhbatykdomumfjx`, `name = "expense-auto-batching"`. Record the returned branch `project_id` (call it `<BRANCH_ID>`); **all execute_sql/apply_migration in Tasks 1–8 target `<BRANCH_ID>`**, not prod.

- [ ] **Step 2: Confirm the branch mirrors current schema**

Run via MCP `execute_sql` on `<BRANCH_ID>`:
```sql
select count(*) as batches, count(*) filter (where status='pending_review') as pending
from expense_batches;
```
Expected: returns without error (counts may differ from prod; the branch seeds from prod schema).

---

## Task 1: Additive schema — grace setting + widened active-envelope index

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_expense_envelope_schema.sql`

- [ ] **Step 1: Write the assertion (failing) — grace column + open-aware index do not yet exist**

Run on `<BRANCH_ID>`:
```sql
select
  (select count(*) from information_schema.columns
     where table_name='expense_settings' and column_name='auto_submit_grace_days') as has_col,
  (select indexdef from pg_indexes where indexname='expense_batches_open_unique') as idx;
```
Expected (pre-change): `has_col = 0`, and `idx` WHERE clause mentions only `status = 'pending_review'`.

- [ ] **Step 2: Apply the migration**

Run via MCP `apply_migration` on `<BRANCH_ID>`, name `expense_envelope_schema`:
```sql
alter table public.expense_settings
  add column if not exists auto_submit_grace_days integer not null default 7;

-- Widen the race-safety index so the new 'open' (filling) phase is also one-per-scope.
drop index if exists public.expense_batches_open_unique;
create unique index expense_batches_open_unique
  on public.expense_batches (company_id, submitted_by, period_start, period_end, scope_project_id)
  nulls not distinct
  where status in ('open','pending_review') and amendment_number = 0;
```

- [ ] **Step 3: Re-run the assertion — now passes**

Re-run Step 1 query. Expected: `has_col = 1`, and `idx` WHERE clause now reads `status = ANY (ARRAY['open'::text, 'pending_review'::text])`.

- [ ] **Step 4: Commit (mirror to bible)**

Save the exact SQL above to `ops-software-bible/migrations/<ts>_expense_envelope_schema.sql` (use the UTC timestamp `apply_migration` recorded). Then:
```bash
git -C ops-software-bible add migrations/<ts>_expense_envelope_schema.sql
git -C ops-software-bible commit migrations/<ts>_expense_envelope_schema.sql -m "feat(expenses): grace-days setting + open-aware active-envelope index"
```

---

## Task 2: Period function (SQL port of `ExpenseBatchPeriod.swift`)

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_expense_envelope_period_fn.sql`
- Reference (port source): `ops-ios/OPS/DataModels/Helpers/ExpenseBatchPeriod.swift`

- [ ] **Step 1: Write the failing assertion**

Run on `<BRANCH_ID>`:
```sql
select to_regprocedure('public.expense_envelope_period(date, text)') is null as missing;
```
Expected: `missing = true`.

- [ ] **Step 2: Create the function**

Run via `apply_migration` on `<BRANCH_ID>`, name `expense_envelope_period_fn`:
```sql
create or replace function public.expense_envelope_period(p_expense_date date, p_review_frequency text)
returns table(period_start date, period_end date)
language sql
immutable
set search_path to 'public','pg_temp'
as $$
  select
    case coalesce(p_review_frequency,'monthly')
      when 'per_job'   then p_expense_date
      when 'weekly'    then date_trunc('week', p_expense_date)::date            -- Postgres week starts Monday
      when 'biweekly'  then case when extract(day from p_expense_date) <= 14
                                 then date_trunc('month', p_expense_date)::date
                                 else (date_trunc('month', p_expense_date) + interval '14 days')::date end
      when 'quarterly' then date_trunc('quarter', p_expense_date)::date
      else date_trunc('month', p_expense_date)::date                            -- monthly + unknown
    end as period_start,
    case coalesce(p_review_frequency,'monthly')
      when 'per_job'   then p_expense_date
      when 'weekly'    then (date_trunc('week', p_expense_date) + interval '6 days')::date
      when 'biweekly'  then case when extract(day from p_expense_date) <= 14
                                 then (date_trunc('month', p_expense_date) + interval '13 days')::date
                                 else (date_trunc('month', p_expense_date) + interval '1 month - 1 day')::date end
      when 'quarterly' then (date_trunc('quarter', p_expense_date) + interval '3 months - 1 day')::date
      else (date_trunc('month', p_expense_date) + interval '1 month - 1 day')::date
    end as period_end;
$$;
```

- [ ] **Step 3: Assert each cadence + boundary (must all pass)**

Run on `<BRANCH_ID>`:
```sql
do $$
begin
  -- monthly: Apr 26 -> Apr 1..Apr 30
  assert (select period_start from expense_envelope_period('2026-04-26','monthly')) = '2026-04-01';
  assert (select period_end   from expense_envelope_period('2026-04-26','monthly')) = '2026-04-30';
  -- late-logged April receipt still maps to April
  assert (select period_start from expense_envelope_period('2026-04-26','monthly')) = '2026-04-01';
  -- weekly: Wed 2026-04-15 -> Mon Apr 13 .. Sun Apr 19
  assert (select period_start from expense_envelope_period('2026-04-15','weekly')) = '2026-04-13';
  assert (select period_end   from expense_envelope_period('2026-04-15','weekly')) = '2026-04-19';
  -- biweekly first half: Apr 14 -> Apr 1..14 ; second half: Apr 15 -> Apr 15..30
  assert (select period_end   from expense_envelope_period('2026-04-14','biweekly')) = '2026-04-14';
  assert (select period_start from expense_envelope_period('2026-04-15','biweekly')) = '2026-04-15';
  assert (select period_end   from expense_envelope_period('2026-04-15','biweekly')) = '2026-04-30';
  -- quarterly: May -> Apr 1..Jun 30
  assert (select period_start from expense_envelope_period('2026-05-31','quarterly')) = '2026-04-01';
  assert (select period_end   from expense_envelope_period('2026-05-31','quarterly')) = '2026-06-30';
  -- per_job: single day
  assert (select period_start from expense_envelope_period('2026-05-31','per_job')) = '2026-05-31';
  assert (select period_end   from expense_envelope_period('2026-05-31','per_job')) = '2026-05-31';
  -- null/unknown frequency falls back to monthly
  assert (select period_start from expense_envelope_period('2026-05-31', null)) = '2026-05-01';
end $$;
```
Expected: no exception (a failed `assert` raises). If any assertion fails, fix the function and re-run.

- [ ] **Step 4: Commit (mirror to bible)**

Save SQL to `ops-software-bible/migrations/<ts>_expense_envelope_period_fn.sql`, then:
```bash
git -C ops-software-bible add migrations/<ts>_expense_envelope_period_fn.sql
git -C ops-software-bible commit migrations/<ts>_expense_envelope_period_fn.sql -m "feat(expenses): expense_envelope_period() — server-side period math"
```

---

## Task 3: Extend `get_or_create_open_batch` to create the `open` (filling) envelope

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_get_or_create_open_batch_v2.sql`

The current function creates batches as `pending_review`. We change it to create as **`open`** and to match an existing `open` **or** `pending_review` envelope (a late item joins a not-yet-approved envelope even after it has sent).

- [ ] **Step 1: Assert current behaviour creates `pending_review` (baseline)**

Run on `<BRANCH_ID>`:
```sql
select status from public.get_or_create_open_batch(
  (select id from companies limit 1),
  gen_random_uuid(), '2030-01-01', '2030-01-31', null);
```
Expected (baseline): `pending_review`. (This row is throwaway test data on the branch.)

- [ ] **Step 2: Replace the function (create as `open`, match not-approved)**

Run via `apply_migration` on `<BRANCH_ID>`, name `get_or_create_open_batch_v2`:
```sql
create or replace function public.get_or_create_open_batch(
  p_company_id uuid, p_submitted_by uuid, p_period_start date, p_period_end date,
  p_scope_project_id uuid default null::uuid)
returns expense_batches
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_batch public.expense_batches;
begin
  if p_company_id is null or p_submitted_by is null then
    raise exception 'get_or_create_open_batch: company_id and submitted_by are required';
  end if;

  -- Match a not-yet-approved envelope (filling OR already-sent) for the scope.
  select * into v_batch
  from public.expense_batches
  where company_id = p_company_id
    and submitted_by = p_submitted_by
    and status in ('open','pending_review')
    and amendment_number = 0
    and coalesce(period_start,     '1970-01-01'::date) = coalesce(p_period_start,     '1970-01-01'::date)
    and coalesce(period_end,       '1970-01-01'::date) = coalesce(p_period_end,       '1970-01-01'::date)
    and coalesce(scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid) =
        coalesce(p_scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid)
  order by created_at desc
  limit 1;

  if v_batch.id is not null then
    return v_batch;
  end if;

  begin
    insert into public.expense_batches (
      company_id, batch_number, period_start, period_end,
      status, submitted_by, total_amount, amendment_number, scope_project_id
    ) values (
      p_company_id, public.get_next_expense_batch_number(p_company_id),
      p_period_start, p_period_end, 'open', p_submitted_by, 0, 0, p_scope_project_id)
    returning * into v_batch;
  exception when unique_violation then
    select * into v_batch
    from public.expense_batches
    where company_id = p_company_id
      and submitted_by = p_submitted_by
      and status in ('open','pending_review')
      and amendment_number = 0
      and coalesce(period_start,     '1970-01-01'::date) = coalesce(p_period_start,     '1970-01-01'::date)
      and coalesce(period_end,       '1970-01-01'::date) = coalesce(p_period_end,       '1970-01-01'::date)
      and coalesce(scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid) =
          coalesce(p_scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid)
    order by created_at desc
    limit 1;
  end;

  return v_batch;
end;
$function$;
```

- [ ] **Step 3: Assert it now creates `open` and is idempotent**

Run on `<BRANCH_ID>`:
```sql
do $$
declare c uuid := (select id from companies limit 1); u uuid := gen_random_uuid();
        b1 expense_batches; b2 expense_batches;
begin
  b1 := public.get_or_create_open_batch(c, u, '2031-02-01', '2031-02-28', null);
  b2 := public.get_or_create_open_batch(c, u, '2031-02-01', '2031-02-28', null);
  assert b1.status = 'open', 'new envelope must be open';
  assert b1.id = b2.id, 'second call must return the same envelope (idempotent)';
  delete from expense_batches where id = b1.id;  -- cleanup branch test row
end $$;
```
Expected: no exception.

- [ ] **Step 4: Commit (mirror to bible)** — save SQL, then:
```bash
git -C ops-software-bible add migrations/<ts>_get_or_create_open_batch_v2.sql
git -C ops-software-bible commit migrations/<ts>_get_or_create_open_batch_v2.sql -m "feat(expenses): get_or_create_open_batch creates the 'open' filling envelope"
```

---

## Task 4: Placement function + trigger (the no-strand guarantee)

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_place_expense_trigger.sql`

- [ ] **Step 1: Verify the per_job scope source column**

Run on `<BRANCH_ID>`:
```sql
select column_name from information_schema.columns
where table_schema='public' and table_name='expense_project_allocations'
order by ordinal_position;
```
Expected: includes `expense_id` and `project_id`. Confirm these names before the function below (used only for the `per_job` scope lookup).

- [ ] **Step 2: Create `place_expense` + trigger**

Run via `apply_migration` on `<BRANCH_ID>`, name `place_expense_trigger`:
```sql
create or replace function public.place_expense(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_exp     public.expenses;
  v_freq    text;
  v_ps      date; v_pe date;
  v_scope   uuid;
  v_batch   public.expense_batches;
  v_home_approved boolean;
begin
  select * into v_exp from public.expenses where id = p_expense_id;
  if v_exp.id is null or v_exp.deleted_at is not null then return; end if;
  if v_exp.status = 'draft' or v_exp.batch_id is not null then return; end if;

  select coalesce(es.review_frequency,'monthly') into v_freq
  from public.expense_settings es where es.company_id = v_exp.company_id;
  v_freq := coalesce(v_freq,'monthly');

  select period_start, period_end into v_ps, v_pe
  from public.expense_envelope_period(v_exp.expense_date, v_freq);

  if v_freq = 'per_job' then
    select project_id into v_scope
    from public.expense_project_allocations
    where expense_id = v_exp.id order by created_at limit 1;
  else
    v_scope := null;
  end if;

  -- Home-period envelope already approved? Then roll forward to the current period.
  select exists(
    select 1 from public.expense_batches b
    where b.company_id = v_exp.company_id and b.submitted_by = v_exp.submitted_by
      and b.amendment_number = 0 and b.status = 'approved'
      and coalesce(b.period_start,'1970-01-01'::date) = v_ps
      and coalesce(b.period_end,'1970-01-01'::date)   = v_pe
      and coalesce(b.scope_project_id,'00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(v_scope,'00000000-0000-0000-0000-000000000000'::uuid)
  ) into v_home_approved;

  if v_home_approved then
    select period_start, period_end into v_ps, v_pe
    from public.expense_envelope_period(current_date, v_freq);
  end if;

  v_batch := public.get_or_create_open_batch(
    v_exp.company_id, v_exp.submitted_by, v_ps, v_pe, v_scope);

  update public.expenses set batch_id = v_batch.id, updated_at = now()
  where id = v_exp.id;

  perform public.recalculate_expense_batch_total(v_batch.id);
end;
$$;

create or replace function public.tg_place_expense()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if NEW.deleted_at is null and NEW.status <> 'draft' and NEW.batch_id is null then
    perform public.place_expense(NEW.id);
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_place_expense on public.expenses;
create trigger trg_place_expense
after insert or update of status, expense_date, batch_id on public.expenses
for each row execute function public.tg_place_expense();

-- Server-only: trigger fn + placement fn are never called by clients.
revoke execute on function public.place_expense(uuid) from public, anon, authenticated;
grant  execute on function public.place_expense(uuid) to service_role;
```
Note: `recalculate_expense_batch_total` sums all non-deleted lines in the batch — an early-cleared (approved) line stays counted, matching the spec.

- [ ] **Step 3: Assert orphan placed, draft skipped, roll-forward works**

Run on `<BRANCH_ID>`:
```sql
do $$
declare c uuid := (select id from companies limit 1); u uuid := gen_random_uuid();
        e_orphan uuid; e_draft uuid; b_id uuid;
begin
  -- ensure monthly cadence for this company on the branch
  insert into expense_settings(company_id, review_frequency)
  values (c,'monthly')
  on conflict (company_id) do update set review_frequency='monthly';

  -- (a) orphan: inserted already-submitted with no batch -> trigger must place it
  insert into expenses(company_id, submitted_by, status, amount, expense_date)
  values (c,u,'submitted',42.00,'2026-04-10') returning id into e_orphan;
  assert (select batch_id from expenses where id=e_orphan) is not null, 'orphan must be placed';
  assert (select status from expense_batches b join expenses e on e.batch_id=b.id where e.id=e_orphan) = 'open';

  -- (b) draft: must NOT be placed
  insert into expenses(company_id, submitted_by, status, amount, expense_date)
  values (c,u,'draft',9.00,'2026-04-11') returning id into e_draft;
  assert (select batch_id from expenses where id=e_draft) is null, 'draft must not be placed';

  -- (c) roll-forward: approve April's envelope, then a new April expense lands in the current month
  select batch_id into b_id from expenses where id=e_orphan;
  update expense_batches set status='approved' where id=b_id;
  declare e_late uuid;
  begin
    insert into expenses(company_id, submitted_by, status, amount, expense_date)
    values (c,u,'submitted',5.00,'2026-04-12') returning id into e_late;
    assert (select b.period_start from expense_batches b join expenses e on e.batch_id=b.id where e.id=e_late)
           = (select period_start from expense_envelope_period(current_date,'monthly')),
           'late April expense must roll into the current month once April is approved';
  end;

  -- cleanup branch rows
  delete from expenses where submitted_by=u;
  delete from expense_batches where submitted_by=u;
end $$;
```
Expected: no exception.

- [ ] **Step 4: Commit (mirror to bible)** — save SQL, then:
```bash
git -C ops-software-bible add migrations/<ts>_place_expense_trigger.sql
git -C ops-software-bible commit migrations/<ts>_place_expense_trigger.sql -m "feat(expenses): server-side placement trigger — no client can strand an expense"
```

---

## Task 5: The daily sweep (auto-send + notify + draft sweep + safety net + roll-forward)

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_expense_envelope_sweep.sql`
- Pattern source: `fire_due_task_reminders` (cron-invoked, inserts `notifications`, status flip = idempotency guard).

- [ ] **Step 1: Create the sweep function**

Run via `apply_migration` on `<BRANCH_ID>`, name `expense_envelope_sweep`:
```sql
create or replace function public.expense_envelope_sweep()
returns integer
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_sent int := 0;
  v_batch record;
  v_uid uuid;
  v_draft record;
begin
  -- (1) SAFETY NET: adopt any non-draft, unbatched expense (orphans from old clients / failed calls).
  for v_draft in
    select id from public.expenses
    where deleted_at is null and status <> 'draft' and batch_id is null
    for update skip locked
  loop
    perform public.place_expense(v_draft.id);
  end loop;

  -- (2) AUTO-SEND: every 'open' envelope whose period + grace has elapsed.
  for v_batch in
    select b.* from public.expense_batches b
    where b.status = 'open' and b.amendment_number = 0
      and b.period_end + (
        coalesce((select auto_submit_grace_days from public.expense_settings s
                  where s.company_id = b.company_id), 7) * interval '1 day'
      ) <= now()
    for update of b skip locked
  loop
    -- sweep this person's completed drafts (amount present) for the period into the envelope
    for v_draft in
      select id from public.expenses e
      where e.company_id = v_batch.company_id and e.submitted_by = v_batch.submitted_by
        and e.status = 'draft' and e.deleted_at is null and e.amount is not null and e.amount > 0
        and e.expense_date between v_batch.period_start and v_batch.period_end
      for update skip locked
    loop
      update public.expenses set status='submitted', batch_id=v_batch.id, updated_at=now() where id=v_draft.id;
    end loop;

    perform public.recalculate_expense_batch_total(v_batch.id);

    -- flip open -> pending_review (this transition is the idempotency guard: never re-picked)
    update public.expense_batches set status='pending_review' where id = v_batch.id;

    -- notify every approver (granular permission, never role)
    for v_uid in select user_id from public.users_with_permission(v_batch.company_id, 'expenses.approve')
    loop
      insert into public.notifications(
        user_id, company_id, type, title, body, batch_id, deep_link_type, action_url, action_label)
      values (
        v_uid::text, v_batch.company_id::text, 'expense_submitted',
        'Expenses ready for review',
        v_batch.batch_number || ' — ' || to_char(v_batch.period_start,'Mon YYYY')
          || ' (' || to_char(v_batch.total_amount,'FM999G999G990D00') || ')',
        v_batch.id::text, 'invoice_detail',
        '/expenses?batch=' || v_batch.id, 'REVIEW');
    end loop;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

revoke execute on function public.expense_envelope_sweep() from public, anon, authenticated;
grant  execute on function public.expense_envelope_sweep() to service_role;
```
Note: confirm `users_with_permission` returns a column named `user_id` (uuid). If it returns a bare set/different column name, adjust the `for v_uid in select … ` accordingly — run `select * from users_with_permission((select id from companies limit 1),'expenses.approve') limit 1;` on the branch first.

- [ ] **Step 2: Assert auto-send flips + notifies once, blank draft held, orphan adopted**

Run on `<BRANCH_ID>`:
```sql
do $$
declare c uuid := (select id from companies limit 1); u uuid := gen_random_uuid();
        b_id uuid; n_before int; n_after int;
begin
  insert into expense_settings(company_id, review_frequency, auto_submit_grace_days)
  values (c,'monthly',7) on conflict (company_id) do update set review_frequency='monthly', auto_submit_grace_days=7;

  -- a completed expense in a past month -> open envelope that is now overdue to send
  insert into expenses(company_id, submitted_by, status, amount, expense_date)
  values (c,u,'submitted',100.00, (date_trunc('month', now()) - interval '1 month')::date + 9);
  select batch_id into b_id from expenses where submitted_by=u limit 1;
  assert (select status from expense_batches where id=b_id) = 'open';

  -- a blank draft (no amount) in the same period -> must be HELD
  insert into expenses(company_id, submitted_by, status, amount, expense_date)
  values (c,u,'draft',null,(date_trunc('month', now()) - interval '1 month')::date + 10);

  select count(*) into n_before from notifications where batch_id = b_id::text;
  perform public.expense_envelope_sweep();
  assert (select status from expense_batches where id=b_id) = 'pending_review', 'overdue envelope must send';
  assert (select count(*) from expenses where submitted_by=u and status='draft') = 1, 'blank draft must be held';

  -- idempotency: a second sweep does not re-send or duplicate notifications
  select count(*) into n_before from notifications where batch_id=b_id::text;
  perform public.expense_envelope_sweep();
  select count(*) into n_after  from notifications where batch_id=b_id::text;
  assert n_after = n_before, 'second sweep must not re-notify';

  delete from expenses where submitted_by=u;
  delete from notifications where batch_id=b_id::text;
  delete from expense_batches where id=b_id;
end $$;
```
Expected: no exception.

- [ ] **Step 3: Schedule the daily cron job**

Run on `<BRANCH_ID>` (mirrors the house `cron.schedule` usage, e.g. the email crons):
```sql
select cron.schedule('expense_envelope_sweep_daily', '15 15 * * *', 'select public.expense_envelope_sweep();');
```
Verify:
```sql
select jobname, schedule from cron.job where jobname='expense_envelope_sweep_daily';
```
Expected: one row, schedule `15 15 * * *` (daily 15:15 UTC; mirrors the 14:xx UTC email-cron window).

- [ ] **Step 4: Commit (mirror to bible)** — save the function SQL **and** the `cron.schedule` call to `ops-software-bible/migrations/<ts>_expense_envelope_sweep.sql`, then:
```bash
git -C ops-software-bible add migrations/<ts>_expense_envelope_sweep.sql
git -C ops-software-bible commit migrations/<ts>_expense_envelope_sweep.sql -m "feat(expenses): daily envelope sweep — auto-send, draft sweep, orphan safety net"
```

---

## Task 6: Harden `expense_batches` RLS (close the self-approve gap)

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_expense_batches_rls_approve_scope.sql`

Today `expense_batches` has only `company_isolation` (ALL, any company member) — a crew member could flip their own batch to `approved` via a direct write. Gate the approve/reviewed transitions to `expenses.approve` holders.

- [ ] **Step 1: Add an approve-scope UPDATE policy + keep company_isolation for read/insert**

Run via `apply_migration` on `<BRANCH_ID>`, name `expense_batches_rls_approve_scope`:
```sql
-- Only expenses.approve holders may move a batch into a reviewed/approved state or set review fields.
-- (Server functions run as SECURITY DEFINER / service_role and bypass this; this guards direct client writes.)
create policy expense_batches_approve_scope
on public.expense_batches
as restrictive
for update
to public
using ( company_id = (select private.get_user_company_id()) )
with check (
  company_id = (select private.get_user_company_id())
  and (
    status not in ('approved','auto_approved')
    or public.has_permission((select private.get_current_user_id()), 'expenses.approve', 'all')
  )
);
```

- [ ] **Step 2: Assert non-approver cannot approve, approver can**

This requires simulating two users. Run on `<BRANCH_ID>` with `execute_sql` using `set local role` + JWT claims is not available via MCP, so assert the policy predicate logic directly instead:
```sql
-- Confirm the policy exists and is RESTRICTIVE on UPDATE.
select polname, polpermissive, polcmd
from pg_policy where polrelid = 'public.expense_batches'::regclass and polname='expense_batches_approve_scope';
```
Expected: one row, `polpermissive = false` (restrictive), `polcmd = 'w'` (UPDATE). Full two-user enforcement is verified in Task 9 acceptance against a real approver/non-approver pair.

- [ ] **Step 3: Confirm `private.get_current_user_id()` exists (used above)**

Run on `<BRANCH_ID>`:
```sql
select to_regprocedure('private.get_current_user_id()') is not null as ok;
```
Expected: `ok = true`. (Referenced by existing expense RLS per the 2026-05-31 remediation.) If it is named differently, adjust the policy to the actual helper before committing.

- [ ] **Step 4: Commit (mirror to bible)** — save SQL, then:
```bash
git -C ops-software-bible add migrations/<ts>_expense_batches_rls_approve_scope.sql
git -C ops-software-bible commit migrations/<ts>_expense_batches_rls_approve_scope.sql -m "fix(expenses): gate batch approval to expenses.approve holders (RLS)"
```

---

## Task 7: One-time backfill of existing orphans (branch dry-run)

**Files:**
- Create migration: `ops-software-bible/migrations/<ts>_backfill_expense_orphans.sql`

- [ ] **Step 1: Count orphans on the branch (dry-run scope)**

Run on `<BRANCH_ID>`:
```sql
select count(*) as orphans
from public.expenses
where deleted_at is null and status <> 'draft' and batch_id is null;
```
Record the count. On prod (Task 9) this is the set that gets placed.

- [ ] **Step 2: Backfill via the placement function**

Run via `apply_migration` on `<BRANCH_ID>`, name `backfill_expense_orphans`:
```sql
do $$
declare r record;
begin
  for r in select id from public.expenses
           where deleted_at is null and status <> 'draft' and batch_id is null
           order by expense_date
  loop
    perform public.place_expense(r.id);
  end loop;
end $$;
```

- [ ] **Step 3: Assert zero orphans remain**

Run on `<BRANCH_ID>`:
```sql
select count(*) as remaining_orphans
from public.expenses
where deleted_at is null and status <> 'draft' and batch_id is null;
```
Expected: `0`.

- [ ] **Step 4: Commit (mirror to bible)** — save SQL, then:
```bash
git -C ops-software-bible add migrations/<ts>_backfill_expense_orphans.sql
git -C ops-software-bible commit migrations/<ts>_backfill_expense_orphans.sql -m "fix(expenses): backfill — place pre-existing orphaned submitted expenses"
```

---

## Task 8: Update the bible (same-session requirement)

**Files:**
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md` (new column, index, batch `open` status)
- Modify: `ops-software-bible/04_API_AND_INTEGRATION.md` (new RPCs: `expense_envelope_period`, `place_expense`, `expense_envelope_sweep`; extended `get_or_create_open_batch`)
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md` §14 (the server-side "Expenses ready for review" notification on auto-send)
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md` (the envelope lifecycle: `open → pending_review → approved`; auto-send + grace; placement trigger; mark the deprecated cron section corrected)

- [ ] **Step 1: Edit `09_FINANCIAL_SYSTEM.md`** — replace the stale "batch_id is null until the cron Edge Function" language and the deprecated-cron paragraph with the server-authoritative model (placement trigger + daily sweep + `open` phase + `auto_submit_grace_days`). Date the section `(2026-06-01)`.

- [ ] **Step 2: Edit `03_DATA_ARCHITECTURE.md`** — document `expense_settings.auto_submit_grace_days`, the `expense_batches.status` value `open`, and the widened `expense_batches_open_unique` index, citing the migration filenames from Tasks 1/3.

- [ ] **Step 3: Edit `04_API_AND_INTEGRATION.md`** — add `expense_envelope_period`, `place_expense`, `expense_envelope_sweep` and the revised `get_or_create_open_batch` to the function table, each citing its migration file.

- [ ] **Step 4: Edit `07_SPECIALIZED_FEATURES.md` §14** — document the `expense_submitted`-type notification now emitted server-side, one per envelope, on auto-send (deep link `invoice_detail`, action `REVIEW`).

- [ ] **Step 5: Commit the bible docs (separate from migrations)**
```bash
git -C ops-software-bible add 03_DATA_ARCHITECTURE.md 04_API_AND_INTEGRATION.md 07_SPECIALIZED_FEATURES.md 09_FINANCIAL_SYSTEM.md
git -C ops-software-bible commit 03_DATA_ARCHITECTURE.md 04_API_AND_INTEGRATION.md 07_SPECIALIZED_FEATURES.md 09_FINANCIAL_SYSTEM.md -m "docs(bible): server-authoritative expense envelope lifecycle"
```

---

## Task 9: Promote to production (REQUIRES USER GO-AHEAD)

**Files:** none new — re-applies Task 1–7 migrations to prod `ijeekuhbatykdomumfjx`.

- [ ] **Step 1: Get explicit user approval.** This is the first prod-touching step (schema + a trigger that fires on live expense writes + a backfill of real rows). Do not proceed without it.

- [ ] **Step 2: Apply migrations 1→6 to prod** via `apply_migration` on `ijeekuhbatykdomumfjx`, in order (schema, period fn, get_or_create v2, placement trigger, sweep + cron, RLS). Run the Task-2/3/4/5 assertion blocks against prod after each; expected: no exception.

- [ ] **Step 3: Run the backfill (Task 7) on prod**, then assert zero orphans remain (Task 7 Step 3 query against prod).

- [ ] **Step 4: Charlie acceptance test (prod).**
```sql
select e.merchant_name, e.amount, b.batch_number, b.status, b.period_start, b.period_end,
       b.period_end + 7 as auto_send_on
from expenses e join expense_batches b on b.id = e.batch_id
join users u on u.id = e.submitted_by
where u.first_name='Charlie' and u.last_name='Gatenby'
  and e.company_id = 'a612edc0-5c18-4c4d-af97-55b9410dd077';
```
Expected: both KMS ($50.38) and Home Hardware ($8.94) now have a `batch_id`; envelope `period_start = 2026-05-01`, `period_end = 2026-05-31`, `auto_send_on = 2026-06-07`. Status `open` if before June 7, else `pending_review` (the daily sweep will have sent it).

- [ ] **Step 5: Confirm the cron job is registered on prod**
```sql
select jobname, schedule, active from cron.job where jobname='expense_envelope_sweep_daily';
```
Expected: one active row.

- [ ] **Step 6: Tear down the dev branch** via MCP `delete_branch` for `<BRANCH_ID>`.

---

## Self-review (completed against the spec)

- **Spec §3 lifecycle** → Tasks 1 (`open` status/index), 3 (create `open`), 5 (flip to `pending_review`). ✔
- **Spec §4.1 placement by date** → Task 2 (period fn) + Task 4 (trigger, condition `status<>'draft' AND batch_id IS NULL`). ✔
- **Spec §4.1 roll-forward** → Task 4 Step 2 (home-approved → current period) + assertion (c). ✔
- **Spec §4.2 sweep (auto-send / safety net / roll-forward) + draft sweep + blank-held** → Task 5. ✔
- **Spec §4.3 configurable grace + per_job** → Task 1 (`auto_submit_grace_days`) + Task 2 (`per_job` single-day) + Task 4 (per_job scope). ✔
- **Spec §6 rollout / Charlie** → Task 7 backfill + Task 9 Step 4 acceptance. ✔
- **Spec §9 additive-only** → all migrations add columns/values/objects; no drops, no enum tightening; 3.0.2 untouched. ✔
- **Security find (RLS gap)** → Task 6. ✔
- **Placeholder scan:** the only "confirm the exact name" steps (Task 4 Step 1 allocations column, Task 5 Step 1 `users_with_permission` column, Task 6 Step 3 `get_current_user_id`) are explicit verification steps with the exact query to run, not deferred implementation. ✔
- **Type/name consistency:** `expense_envelope_period`, `place_expense`, `expense_envelope_sweep`, `expense_envelope_sweep_daily`, `auto_submit_grace_days` used identically across tasks. ✔

**Not in this plan (separate plans):** Phase 2a iOS (single Add button, state display, drop draft/submit choice); Phase 2b Web (office peek + early-clear). Each depends on Phase 1 but ships independently.
