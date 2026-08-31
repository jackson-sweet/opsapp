-- Cluster J / bug 16d487c4. Server-state verdict for sync reconcilers.
create or replace function public.project_server_state(p_project_id uuid)
returns text
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
  select coalesce(
    (select case when p.deleted_at is null then 'active' else 'deleted' end
       from public.projects p
      where p.id = p_project_id
        and p.company_id = (select private.get_user_company_id())),
    'absent'
  );
$$;

revoke all on function public.project_server_state(uuid) from public;
grant execute on function public.project_server_state(uuid) to anon, authenticated, service_role;

-- PROBES:
-- select public.project_server_state('a0636b77-3545-43fb-b94b-5d95feff74e1'); -- as service role: 'absent' is
--   expected here ONLY because get_user_company_id() is null without a user JWT — that null-company behavior is
--   itself part of the contract (no JWT/company ⇒ 'absent', never an error).
-- Definition check:
-- select prosecdef, proconfig from pg_proc where proname='project_server_state';
