-- ============================================================================
-- MIGRATION (CRIT-3 Phase C) — RE-KEY RLS IDENTITY OFF THE CRYPTOGRAPHIC SUB
-- Authored 2026-06-14. *** NOT YET APPLIED to prod — GATED. ***
--
-- Apply path: Supabase MCP apply_migration (project ijeekuhbatykdomumfjx), OR
-- mirror into OPS-Web/supabase/migrations/ with the team timestamp convention.
-- Apply ONLY after the gate below is satisfied. After applying, mirror the
-- forward block into OPS-Web/supabase/migrations and run the smoke test.
--
-- WHAT: The five SECURITY DEFINER identity helpers resolve the caller by the
-- JWT `email` claim. OPS never sent Firebase email verification, so an attacker
-- could register a Firebase account on a victim's email and be resolved as the
-- victim by every RLS policy. This re-keys all five to resolve by the
-- cryptographic token sub (auth_id = sub OR firebase_uid = sub) instead.
--
-- BLAST RADIUS: 296 dependent objects (228 RLS policies + 58 functions + 1 view
-- + 9 triggers) reach the email check EXCLUSIVELY through these five helper
-- bodies — nothing inlines the comparison, no dynamic-EXECUTE call was missed
-- (verified by two independent catalog derivations, cross-checked). So this is a
-- CREATE OR REPLACE of five functions; zero policy DDL. Every dependent inherits
-- sub-resolution automatically.
--
-- *** GATE — DO NOT APPLY UNTIL: zero active users that HAVE a Firebase account
-- remain unlinked. *** Re-keying resolves to NULL for any active row whose
-- auth_id AND firebase_uid are both NULL, locking them out. The achievable gate
-- is NOT `private.identity_linkage_metrics.unlinked_with_email = 0` (that figure
-- includes ~140 DORMANT legacy/test rows that have no Firebase account at all
-- and can never authenticate — they self-heal via the sync-user legacy-link path
-- on their eventual first login, which runs server-side as service_role BEFORE
-- any RLS query). The correct gate is the Phase-A backfill script reporting
-- `B (matched) = 0 AND collisions = 0`, i.e. every Firebase account is already
-- linked to its OPS row:
--     node --env-file=.env.local --import tsx scripts/crit3-backfill-identity.ts
-- As of 2026-06-14 the active authenticating base is already ~100% linked
-- (49/50 linked uids present in the ops-ios-app Firebase project; B=1 pending
-- the bulk write). Also coordinate iOS: confirm first-login links the row
-- (sync-user/backfill) BEFORE the first RLS read (see spec GAP 1).
--
-- ROLLED-BACK PROBE EVIDENCE (2026-06-14, BEGIN…ROLLBACK, prod untouched):
--   subject            resolve_uid  before→after     company before→after     is_admin
--   linked admin       1a2b388e → 1a2b388e (same)     7e27a9a8 → 7e27a9a8       true→true
--   linked non-admin   11cd7606 → 11cd7606 (same)     a612edc0 → a612edc0       false→false
--   unlinked w/ email  0472e73e → NULL (locked out)   a612edc0 → NULL           —
--   RLS (projects, authenticated role): linked 310→310 (preserved);
--                                       unlinked 222→0 (locked out).
-- ============================================================================

-- ─────────────────────────── FORWARD (re-key) ──────────────────────────────
BEGIN;

CREATE OR REPLACE FUNCTION private.resolve_uid()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.get_current_user_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.get_user_company_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND company_id IS NOT NULL
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION public.get_user_company_id()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id::text FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND company_id IS NOT NULL
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.current_user_is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE (u.auth_id = (auth.jwt() ->> 'sub') OR u.firebase_uid = (auth.jwt() ->> 'sub'))
      AND u.deleted_at IS NULL
      AND (
        COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
      )
  )
$function$;

COMMIT;

-- ───────────────── SMOKE TEST (run after apply; read-only) ──────────────────
-- Pick one linked user (auth_id+firebase_uid set) and confirm resolution; pick
-- one unlinked active user and confirm they NO LONGER resolve (expected — they
-- must log in to be linked). Replace the sub/email literals with live values.
--   SET request.jwt.claims = '{"sub":"<linked firebase_uid>","email":"<x>"}';
--   SELECT private.resolve_uid();          -- expect the linked user's id
--   SELECT private.get_user_company_id();  -- expect their company_id
--   RESET request.jwt.claims;

-- ──────────────────────── ROLLBACK (restore email) ─────────────────────────
-- If the re-key causes unexpected lockouts, restore the email-based bodies:
/*
BEGIN;
CREATE OR REPLACE FUNCTION private.resolve_uid()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users WHERE email = (auth.jwt() ->> 'email') AND deleted_at IS NULL LIMIT 1
$function$;
CREATE OR REPLACE FUNCTION private.get_current_user_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users WHERE email = (auth.jwt() ->> 'email') AND deleted_at IS NULL LIMIT 1
$function$;
CREATE OR REPLACE FUNCTION private.get_user_company_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id FROM public.users WHERE email = (auth.jwt() ->> 'email') AND company_id IS NOT NULL AND deleted_at IS NULL LIMIT 1
$function$;
CREATE OR REPLACE FUNCTION public.get_user_company_id()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id::text FROM public.users WHERE email = (auth.jwt() ->> 'email') AND company_id IS NOT NULL AND deleted_at IS NULL LIMIT 1
$function$;
CREATE OR REPLACE FUNCTION private.current_user_is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE u.email = (auth.jwt() ->> 'email') AND u.deleted_at IS NULL
      AND (COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[])))
  )
$function$;
COMMIT;
*/
