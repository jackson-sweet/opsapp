-- ============================================================================
-- PENDING JACKSON'S GO — NOT YET APPLIED TO PROD (blocked by session policy
-- gate 2026-07-03; apply via Supabase MCP `apply_migration` with
-- name: heal_user_identity_rpc).
-- ============================================================================
--
-- ADDITIVE ONLY: new SECURITY DEFINER RPC; nothing existing changes.
--
-- Self-heal for the email/password firebase_uid linking gap (WS-I1 item b).
--
-- users RLS keys every self-write on private.resolve_uid() (JWT sub matched
-- against auth_id/firebase_uid). A legacy/unlinked row (both NULL) therefore
-- cannot be linked by its own user — the very row that needs healing is the
-- one RLS cannot resolve. AuthManager.backfillFirebaseUID's direct UPDATE
-- matches zero rows, its read-back verification fails, and it gives up after
-- 3 attempts (verified in code 2026-07-03; 32 of 79 active users are
-- currently fully unlinked). This RPC closes the loop using the
-- Firebase-SIGNED email claim instead of the unresolvable sub.
--
-- Security invariants:
--   * requires a JWT with non-empty sub AND email AND email_verified=true
--     (Google/Apple sign-ins are always provider-verified; email/password
--     only links after the user verifies their address — blocks the
--     "register the victim's email unverified, inherit their row" takeover)
--   * only fills NULL identities — a row with ANY non-null auth_id or
--     firebase_uid is never re-keyed (no takeover of linked accounts)
--   * soft-deleted rows excluded; newest matching row wins deterministically
--   * NEVER auth.uid() (throws under the Firebase JWT bridge)
--
-- iOS calls this (from the 2026-07-03 hardening commit) whenever the direct
-- backfill's read-back fails; a missing function is tolerated silently, so
-- this migration and the app release can land in either order.

create or replace function public.heal_user_identity()
returns uuid
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_sub      text := nullif(auth.jwt() ->> 'sub', '');
  v_email    text := lower(nullif(auth.jwt() ->> 'email', ''));
  v_verified boolean := coalesce((auth.jwt() ->> 'email_verified')::boolean, false);
  v_id uuid;
begin
  if v_sub is null or v_email is null then
    return null;
  end if;

  -- Already linked? Return that row and touch nothing.
  select id into v_id
    from public.users
   where (auth_id = v_sub or firebase_uid = v_sub)
     and deleted_at is null
   limit 1;
  if found then
    return v_id;
  end if;

  if not v_verified then
    return null;
  end if;

  update public.users u
     set auth_id = v_sub,
         firebase_uid = v_sub,
         updated_at = now()
   where u.id = (
     select id
       from public.users
      where lower(email) = v_email
        and auth_id is null
        and firebase_uid is null
        and deleted_at is null
      order by created_at desc
      limit 1
   )
   returning u.id into v_id;

  return v_id;
end;
$$;

grant execute on function public.heal_user_identity() to anon, authenticated, service_role;

-- ============================================================================
-- VERIFICATION RUNBOOK (self-reverting — the synthetic row and the heal are
-- both rolled back by the closing RAISE EXCEPTION)
-- ============================================================================
--
-- do $$
-- declare v_row uuid; v_healed uuid; v_neg uuid; v_fuid text;
-- begin
--   insert into public.users (id, email, first_name, last_name, role, user_type, company_id, created_at)
--   values (gen_random_uuid(), 'heal-test@example.invalid', 'Heal', 'Test', 'crew', 'company',
--           'ddee107c-33cd-483e-8278-0f8d8a180181', now())
--   returning id into v_row;
--
--   -- unverified email must NOT link
--   perform set_config('request.jwt.claims',
--     '{"sub":"HEALTESTSUB123","email":"heal-test@example.invalid","email_verified":false,"role":"anon"}', true);
--   set local role anon;
--   v_neg := public.heal_user_identity();
--   reset role;
--
--   -- verified email links exactly the unlinked row
--   perform set_config('request.jwt.claims',
--     '{"sub":"HEALTESTSUB123","email":"heal-test@example.invalid","email_verified":true,"role":"anon"}', true);
--   set local role anon;
--   v_healed := public.heal_user_identity();
--   reset role;
--
--   select firebase_uid into v_fuid from public.users where id = v_row;
--   raise exception 'HEAL_TEST unverified=% healed=% expected_row=% firebase_uid=% (all rolled back)',
--     coalesce(v_neg::text,'<null>'), v_healed, v_row, v_fuid;
-- end $$;
--
-- Expected: unverified=<null>, healed == expected_row, firebase_uid=HEALTESTSUB123.
