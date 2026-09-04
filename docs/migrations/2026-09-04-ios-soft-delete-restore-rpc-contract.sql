-- =====================================================================
-- CONTRACT TEST for 2026-09-04-ios-soft-delete-and-restore-rpcs.staged.sql
--
-- Safe to run against prod: the whole thing is one transaction that ends in
-- ROLLBACK. It writes nothing durable. Run it as a superuser/owner connection
-- (psql via the pooler) — it drops to `authenticated` itself with `set local`.
--
-- Everything is resolved from live data, so it stays runnable as the fixtures
-- change. Read the final `select * from probe_out order by ord` and compare the
-- `sqlstate`/`msg` columns against `expected`.
--
-- Bugs db15baf2 (task delete), 2a55c78f (client delete, fired on the founder's
-- phone 2026-09-04 17:15 UTC).
-- =====================================================================

begin;

create temp table probe_out(
  ord      int,
  step     text,
  expected text,
  sqlstate text,
  msg      text
) on commit drop;

create temp table probe_fixture(
  admin_sub          text,
  admin_user_id      uuid,
  admin_company      uuid,
  admin_pipeline_mgr boolean,
  client_id          uuid,
  project_id         uuid,
  linked_project_id  uuid,
  task_id            uuid,
  foreign_client_id  uuid,
  lowpriv_sub        text,
  lowpriv_user_id    uuid
) on commit drop;

-- `pg_temp` resolves to this session's own temp schema; the grant is needed
-- because the probe writes its findings while running as `authenticated`.
grant usage on schema pg_temp to authenticated;
grant all on probe_out to authenticated;
grant all on probe_fixture to authenticated;

-- ---------------------------------------------------------------- fixtures
-- Resolved while still running as the owner, before dropping to `authenticated`.

insert into probe_fixture
select
  coalesce(u.auth_id, u.firebase_uid),
  u.id,
  u.company_id,
  public.has_permission(u.id, 'pipeline.manage', 'all'),
  (select c.id
     from public.clients c
    where c.company_id = u.company_id and c.deleted_at is null
    limit 1),
  (select p.id
     from public.projects p
    where p.company_id = u.company_id
      and p.deleted_at is null
      and p.opportunity_ref is null
      and p.opportunity_id is null
    limit 1),
  (select p.id
     from public.projects p
    where p.company_id = u.company_id
      and p.deleted_at is null
      and (p.opportunity_ref is not null or p.opportunity_id is not null)
    limit 1),
  (select t.id
     from public.project_tasks t
     join public.projects p
       on p.id = t.project_id and p.deleted_at is null
    where t.company_id = u.company_id and t.deleted_at is null
    limit 1),
  (select c.id
     from public.clients c
    where c.company_id is distinct from u.company_id and c.deleted_at is null
    limit 1),
  (select coalesce(o.auth_id, o.firebase_uid)
     from public.users o
    where o.deleted_at is null
      and coalesce(o.is_active, false)
      and coalesce(o.auth_id, o.firebase_uid) is not null
      and not public.has_permission(o.id, 'clients.delete', 'all')
    limit 1),
  (select o.id
     from public.users o
    where o.deleted_at is null
      and coalesce(o.is_active, false)
      and coalesce(o.auth_id, o.firebase_uid) is not null
      and not public.has_permission(o.id, 'clients.delete', 'all')
    limit 1)
from public.users u
where u.deleted_at is null
  and coalesce(u.is_active, false)
  and u.company_id is not null
  and coalesce(u.auth_id, u.firebase_uid) is not null
  and public.has_permission(u.id, 'clients.delete', 'all')
  and public.has_permission(u.id, 'projects.delete', 'all')
  and public.has_permission(u.id, 'tasks.edit', 'all')
  -- The actor's company must actually hold one of each fixture. Without these
  -- the first eligible admin can land on an empty company and the whole probe
  -- silently degrades to nulls. (Verified 2026-09-04: with them, this resolves
  -- to the Canpro admin whose phone filed bug 2a55c78f.)
  and exists (select 1 from public.clients c
               where c.company_id = u.company_id and c.deleted_at is null)
  and exists (select 1 from public.projects p
               where p.company_id = u.company_id and p.deleted_at is null
                 and p.opportunity_ref is null and p.opportunity_id is null)
  and exists (select 1 from public.project_tasks t
               join public.projects p on p.id = t.project_id and p.deleted_at is null
              where t.company_id = u.company_id and t.deleted_at is null)
limit 1;

do $$
begin
  if not exists (select 1 from probe_fixture) then
    raise exception 'no privileged actor found — cannot run the contract test';
  end if;
end $$;

set local role authenticated;

-- ---------------------------------------------------------------- SECTION A
-- The privileged actor. RLS must be UNCHANGED (raw writes still refused) and
-- every RPC must work and be idempotent.

do $$
declare
  f probe_fixture;
  r jsonb;
  n int;
begin
  select * into f from probe_fixture;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', f.admin_sub, 'role', 'authenticated')::text,
    true
  );

  -- A1-A3: the raw PATCH must STILL be refused. If any of these is ACCEPTED the
  -- migration weakened row security — reject it.
  begin
    update public.clients set deleted_at = now() where id = f.client_id;
    insert into probe_out values (1, 'raw PATCH clients set deleted_at', '42501',
      '00000', 'ACCEPTED — RLS WAS WEAKENED, REJECT THIS MIGRATION');
  exception when others then
    insert into probe_out values (1, 'raw PATCH clients set deleted_at', '42501', SQLSTATE, SQLERRM);
  end;

  begin
    update public.projects set deleted_at = now() where id = f.project_id;
    insert into probe_out values (2, 'raw PATCH projects set deleted_at', '42501',
      '00000', 'ACCEPTED — RLS WAS WEAKENED, REJECT THIS MIGRATION');
  exception when others then
    insert into probe_out values (2, 'raw PATCH projects set deleted_at', '42501', SQLSTATE, SQLERRM);
  end;

  begin
    update public.project_tasks set deleted_at = now() where id = f.task_id;
    insert into probe_out values (3, 'raw PATCH project_tasks set deleted_at', '42501',
      '00000', 'ACCEPTED — RLS WAS WEAKENED, REJECT THIS MIGRATION');
  exception when others then
    insert into probe_out values (3, 'raw PATCH project_tasks set deleted_at', '42501', SQLSTATE, SQLERRM);
  end;

  -- A4: clients — delete, idempotent re-delete, restore, idempotent re-restore.
  begin
    select public.soft_delete_client(f.client_id) into r;
    insert into probe_out values (4, 'RPC soft_delete_client', 'deleted: true', '00000', r::text);
    select public.soft_delete_client(f.client_id) into r;
    insert into probe_out values (5, 'RPC soft_delete_client (2nd)', 'deleted: false', '00000', r::text);

    -- The raw restore is the silent half of the bug: no error, zero rows.
    update public.clients set deleted_at = null where id = f.client_id;
    get diagnostics n = row_count;
    insert into probe_out values (6, 'raw PATCH clients clear deleted_at (row_count)',
      '0 — silently matches nothing', '00000', n::text);

    select public.restore_client(f.client_id) into r;
    insert into probe_out values (7, 'RPC restore_client', 'restored: true', '00000', r::text);
    select public.restore_client(f.client_id) into r;
    insert into probe_out values (8, 'RPC restore_client (2nd)', 'restored: false', '00000', r::text);
  exception when others then
    insert into probe_out values (4, 'clients RPC family', 'no error', SQLSTATE, SQLERRM);
  end;

  -- A9: projects (no opportunity link, so the link trigger is not in play).
  begin
    select public.soft_delete_project(f.project_id) into r;
    insert into probe_out values (9, 'RPC soft_delete_project', 'deleted: true', '00000', r::text);
    select public.soft_delete_project(f.project_id) into r;
    insert into probe_out values (10, 'RPC soft_delete_project (2nd)', 'deleted: false', '00000', r::text);
    select public.restore_project(f.project_id) into r;
    insert into probe_out values (11, 'RPC restore_project', 'restored: true', '00000', r::text);
    select public.restore_project(f.project_id) into r;
    insert into probe_out values (12, 'RPC restore_project (2nd)', 'restored: false', '00000', r::text);
  exception when others then
    insert into probe_out values (9, 'projects RPC family', 'no error', SQLSTATE, SQLERRM);
  end;

  -- A13: project_tasks. The DELETE half already shipped (ledger 20260902160624);
  -- restore is the new object.
  begin
    select public.soft_delete_project_task(f.task_id) into r;
    insert into probe_out values (13, 'RPC soft_delete_project_task', 'deleted: true', '00000', r::text);
    select public.restore_project_task(f.task_id) into r;
    insert into probe_out values (14, 'RPC restore_project_task', 'restored: true', '00000', r::text);
    select public.restore_project_task(f.task_id) into r;
    insert into probe_out values (15, 'RPC restore_project_task (2nd)', 'restored: false', '00000', r::text);
  exception when others then
    insert into probe_out values (13, 'tasks RPC family', 'no error', SQLSTATE, SQLERRM);
  end;

  -- A16: the opportunity-link invariant is preserved, not suppressed. The
  -- trigger reads the caller's JWT, so an actor holding pipeline.manage 'all'
  -- succeeds and one without it is refused 42501 access_denied. Both are the
  -- correct outcome — the expectation depends on this actor's permission, which
  -- is reported alongside.
  if f.linked_project_id is null then
    insert into probe_out values (16, 'RPC soft_delete_project (opportunity-linked)',
      'skipped — no linked project in this company', '00000', null);
  else
    begin
      select public.soft_delete_project(f.linked_project_id) into r;
      insert into probe_out values (16, 'RPC soft_delete_project (opportunity-linked)',
        'ok when pipeline.manage all = ' || f.admin_pipeline_mgr, '00000', r::text);
    exception when others then
      insert into probe_out values (16, 'RPC soft_delete_project (opportunity-linked)',
        '42501 access_denied when pipeline.manage all = false (actor has: '
        || f.admin_pipeline_mgr || ')', SQLSTATE, SQLERRM);
    end;
  end if;

  -- A17: cross-company. A client in another company is refused, never disclosed
  -- as "already deleted".
  if f.foreign_client_id is null then
    insert into probe_out values (17, 'RPC soft_delete_client (other company)',
      'skipped — no second company', '00000', null);
  else
    begin
      select public.soft_delete_client(f.foreign_client_id) into r;
      insert into probe_out values (17, 'RPC soft_delete_client (other company)',
        '42501 client_delete_forbidden', '00000', 'ACCEPTED — CROSS-COMPANY LEAK, REJECT');
    exception when others then
      insert into probe_out values (17, 'RPC soft_delete_client (other company)',
        '42501 client_delete_forbidden', SQLSTATE, SQLERRM);
    end;
  end if;
end $$;

-- ---------------------------------------------------------------- SECTION B
-- Least privilege: whoever could not delete a client before still cannot.

do $$
declare
  f probe_fixture;
  r jsonb;
begin
  select * into f from probe_fixture;

  if f.lowpriv_sub is null then
    insert into probe_out values (18, 'RPC soft_delete_client (no clients.delete all)',
      'skipped — every active user holds the permission', '00000', null);
    return;
  end if;

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', f.lowpriv_sub, 'role', 'authenticated')::text,
    true
  );

  begin
    select public.soft_delete_client(f.client_id) into r;
    insert into probe_out values (18, 'RPC soft_delete_client (no clients.delete all)',
      '42501 client_delete_forbidden', '00000', 'ACCEPTED — PERMISSION LADDER LEAK, REJECT');
  exception when others then
    insert into probe_out values (18, 'RPC soft_delete_client (no clients.delete all)',
      '42501 client_delete_forbidden', SQLSTATE, SQLERRM);
  end;

  begin
    select public.restore_client(f.client_id) into r;
    insert into probe_out values (19, 'RPC restore_client (no clients.delete all)',
      '42501 client_restore_forbidden', '00000', 'ACCEPTED — PERMISSION LADDER LEAK, REJECT');
  exception when others then
    insert into probe_out values (19, 'RPC restore_client (no clients.delete all)',
      '42501 client_restore_forbidden', SQLSTATE, SQLERRM);
  end;
end $$;

-- ---------------------------------------------------------------- SECTION C
-- ACL shape. Every public wrapper: definer, owned by postgres, EXECUTE to anon
-- + authenticated only — no service_role. Every private core: postgres only.

reset role;

select
  n.nspname || '.' || p.proname as fn,
  pg_get_function_identity_arguments(p.oid) as args,
  p.prosecdef,
  pg_get_userbyid(p.proowner) as owner,
  coalesce(array_to_string(p.proacl, ' | '), '(default — INVESTIGATE)') as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname in (
  'soft_delete_client', 'restore_client',
  'soft_delete_project', 'restore_project',
  'restore_project_task', 'soft_delete_project_task',
  'soft_delete_client_for_actor', 'restore_client_for_actor',
  'soft_delete_project_for_actor', 'restore_project_for_actor',
  'restore_project_task_for_actor'
)
order by n.nspname, p.proname;

select * from probe_out order by ord;

rollback;
