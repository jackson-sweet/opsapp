-- ============================================================================
-- PENDING JACKSON'S GO — NOT YET APPLIED TO PROD (blocked by session policy
-- gate 2026-07-03; apply via Supabase MCP `apply_migration` with
-- name: soft_delete_photo_annotation_rpc).
-- ============================================================================
--
-- ADDITIVE ONLY: new SECURITY DEFINER RPC; no table, column, policy, or
-- existing-function changes. Companion to upsert_markup_layer (20260624224155),
-- which already performs this exact class of write (sets deleted_at) via the
-- same identity bridge and grants.
--
-- Why: soft-deleting a photo annotation via a direct client UPDATE is
-- structurally impossible under the RLS shipped 2026-05-12 (see
-- 2026-07-03-photo-annotations-tombstone-select-policy.sql for the full root
-- cause). This RPC is the durable write path for annotation soft-delete going
-- forward: identity via the established firebase_uid/auth_id bridge (NEVER
-- auth.uid(), which throws under the Firebase JWT bridge), company-scoped,
-- idempotent (a retry after a half-acknowledged success still returns success
-- and keeps the original tombstone time), and LOUD on failure — an
-- unresolvable identity raises 42501 instead of silently matching zero rows.
--
-- iOS (from the 2026-07-03 hardening commit) calls this RPC first and falls
-- back to the legacy direct UPDATE when the function does not exist yet, so
-- this migration and the app release can land in either order.
--
-- Authorization semantics match the existing UPDATE policy exactly: any
-- member of the owning company may soft-delete a company annotation (the
-- same rights the direct UPDATE path has always granted).

create or replace function public.soft_delete_photo_annotation(p_annotation_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_company_id uuid;
  v_user_id uuid;
  v_id uuid;
begin
  v_company_id := private.get_user_company_id();
  v_user_id    := private.get_current_user_id();
  if v_company_id is null or v_user_id is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  update public.project_photo_annotations
     set deleted_at = coalesce(deleted_at, now()),
         updated_at = now()
   where id = p_annotation_id
     and company_id = v_company_id::text
   returning id into v_id;

  if v_id is null then
    raise exception 'Annotation not found' using errcode = 'P0002';
  end if;

  return v_id;
end;
$$;

grant execute on function public.soft_delete_photo_annotation(uuid) to anon, authenticated, service_role;

-- ============================================================================
-- VERIFICATION RUNBOOK
-- ============================================================================
--
-- 1) Company member tombstones a company row (expect returned id, rolled back):
--
-- do $$
-- declare v_id uuid;
-- begin
--   perform set_config('request.jwt.claims',
--     '{"sub":"pnLo4LsWtvMi7oxDrRIcLASCash2","role":"anon"}', true);
--   set local role anon;
--   v_id := public.soft_delete_photo_annotation('e975c1fb-fc77-45b9-938f-fa0ce8d903ee');
--   raise exception 'RPC_OK id=% (rolled back)', v_id;
-- end $$;
--
-- 2) Cross-company caller is rejected with P0002 (expect 'Annotation not found'):
--    same block with sub D1HiiNQaeiO6fRfcaiGRnrvoUhp2.
--
-- 3) No-JWT caller is rejected with 42501 (expect 'Not authorized'):
--    same block with claims '{}'.
