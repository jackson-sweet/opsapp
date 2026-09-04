-- =====================================================================
-- STAGED — NOT APPLIED. Bug sweep 2026-09-04, cluster PHOTOS & MEDIA.
-- Related bug: bf2a75fb (PROJECT_ROW_MISSING).
--
-- NOTHING MAY APPLY THIS WITHOUT EXPLICIT APPROVAL. This file is staged in
-- the iOS repo as a reviewed artifact only. It is not on any migration path.
-- To ship it: copy VERBATIM into ops-web as a NEW timestamped migration
-- (`ops-web/supabase/migrations/<YYYYMMDDHHMMSS>_project_server_state_unknown_verdict.sql`)
-- and apply through the normal ops-web migration flow.
-- =====================================================================
--
-- ---------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------
-- `public.project_server_state(uuid)` collapses two different facts into one
-- answer. Its body is:
--
--   select coalesce(
--     (select case when p.deleted_at is null then 'active' else 'deleted' end
--        from public.projects p
--       where p.id = p_project_id
--         and p.company_id = (select private.get_user_company_id())),
--     'absent');
--
-- When `private.get_user_company_id()` returns NULL — the caller could not be
-- resolved to a company at all — the subselect yields no row and the function
-- answers 'absent' for a LIVE project. Measured in prod:
--
--   | scenario        | get_user_company_id() | project_server_state(d5e96bf6-…) |
--   | Charlie's JWT   | a612edc0-…            | active                           |
--   | no JWT claims   | NULL                  | absent   <-- FALSE               |
--
-- That is not academic. iOS treats an 'absent' verdict as proof the project is
-- gone: `ImageSyncManager` reports a PROJECT_ROW_MISSING auto-bug and
-- `settle(.heldProjectAbsent)` calls `removePortalMirrors(urls:)`, which drops
-- the queued portal mirror PERMANENTLY. Any user whose `users` row has a NULL
-- `company_id` (or a non-null `deleted_at`) would silently lose photo delivery
-- against a perfectly live job.
--
-- The fix separates "I could not identify you" from "no such row".
--
-- ---------------------------------------------------------------------
-- SAFETY FOR ALREADY-SHIPPED iOS BUILDS
-- ---------------------------------------------------------------------
-- Signature, return type and language are unchanged; only a new possible
-- string value is introduced. `SyncOperationReconcilers.ProjectServerState`
-- (`OPS/Network/Sync/SyncOperationReconcilers.swift`) is a `String`-backed enum
-- read through `init(rawValue:)`, so an unrecognized verdict decodes to `nil`,
-- and `ImageSyncManager` maps `nil` to `.retryQueued` with a warning. Old
-- builds therefore degrade to "queue it and try again" — exactly the desired
-- behaviour. No App Store release is required for this migration to be safe.
--
-- ---------------------------------------------------------------------
-- VERIFY AFTER APPLYING
-- ---------------------------------------------------------------------
--   select set_config('request.jwt.claims',
--            '{"sub":"kefAyAucVqb5If2DGnX7ztABy082","role":"anon"}', true) is not null,
--          public.project_server_state('d5e96bf6-42c6-4c92-a1ce-71a634cfebf8');
--   -- EXPECT 'active'
--
--   select set_config('request.jwt.claims', NULL, true) is not null,
--          public.project_server_state('d5e96bf6-42c6-4c92-a1ce-71a634cfebf8');
--   -- EXPECT 'unknown'   (was 'absent')
--
-- ---------------------------------------------------------------------

begin;

create or replace function public.project_server_state(p_project_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  -- 'unknown' means the CALLER could not be resolved to a company, not that
  -- the row is missing. Callers must treat it as "no answer" and retry, never
  -- as evidence of deletion.
  select case
    when (select private.get_user_company_id()) is null then 'unknown'
    else coalesce(
      (select case when p.deleted_at is null then 'active' else 'deleted' end
         from public.projects p
        where p.id = p_project_id
          and p.company_id = (select private.get_user_company_id())),
      'absent')
  end;
$function$;

-- `create or replace` preserves the existing ACL, so no re-grant is needed.
-- Recorded for the reviewer, captured from prod 2026-09-04:
--   postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres

commit;
