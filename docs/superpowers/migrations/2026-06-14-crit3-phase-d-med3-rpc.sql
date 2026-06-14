-- ============================================================================
-- MIGRATION (CRIT-3 Phase D / MED-3) — sub-resolving company-setup RPC
-- Authored 2026-06-14. *** RPC APPLIED to prod 2026-06-14 (Phase C is live):
-- migrations 20260614xxxxxx_crit3_phase_d_med3_update_company_setup_rpc +
-- crit3_med3_rpc_revoke_anon. The WEB changes below are committed behind env
-- CRIT3_SUB_IDENTITY (default off) and take effect only when that flag is flipped
-- and feat/inbox-dark-launch is deployed. ***
--
-- WHAT: /api/setup/progress, in the "company already exists" branch, performs a
-- privileged service_role write — users.is_company_admin = true + company_id
-- link, plus the company profile update + initialize_company_defaults — on a row
-- resolved by findUserByAuth, which includes an EMAIL fallback. An email match
-- is not proof of possession, so an unverified caller whose email equals a
-- victim's could have is_company_admin set on the victim's row (MED-3).
--
-- FIX: this SECURITY DEFINER RPC resolves the caller from the cryptographic JWT
-- sub ONLY (auth_id = sub OR firebase_uid = sub), authorizes that the caller is
-- an owner/admin of their own company (account_holder_id / admin_ids /
-- is_company_admin — which also blocks a joined MEMBER from self-elevating), and
-- performs all writes against the sub-resolved caller's own row + company. The
-- route invokes it via getUserScopedClient(token) (same pattern as
-- create_company_for_owner), so the privileged write can never land on an
-- email-matched row. Mirrors create_company_for_owner's grants (authenticated +
-- service_role; never PUBLIC/anon).
--
-- DEPLOY ORDER: this RPC internally calls initialize_company_defaults, which
-- itself resolves identity via the helpers. A sub-only JWT therefore requires
-- the Phase C re-key to be live (validated: under email helpers a sub-only token
-- fails initialize_company_defaults' own authz; under the re-keyed helpers it
-- succeeds). Apply with/after Phase C and flip the web flag CRIT3_SUB_IDENTITY.
--
-- ROLLED-BACK PROBE EVIDENCE (2026-06-14, post-C simulation, BEGIN…ROLLBACK):
--   admin (owner)        -> ok, company renamed, defaults ran
--   linked non-owner     -> NOT_AUTHORIZED (self-elevation blocked, not elevated)
--   unlinked/email-only  -> NO_USER_ROW (no privileged write on an unproven row)
--   no sub               -> NO_JWT
-- ============================================================================

-- ─────────────────────────────── FORWARD ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_company_setup_for_member(
  p_name text,
  p_industries text[],
  p_company_size text,
  p_company_age text,
  p_weather_dependent boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_user public.users%rowtype;
  v_company public.companies%rowtype;
BEGIN
  IF v_sub IS NULL OR v_sub = '' THEN
    RAISE EXCEPTION 'NO_JWT';
  END IF;

  -- Resolve the caller by the cryptographic sub ONLY — never by email.
  SELECT * INTO v_user FROM public.users
  WHERE (auth_id = v_sub OR firebase_uid = v_sub) AND deleted_at IS NULL
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_USER_ROW';
  END IF;

  IF v_user.company_id IS NULL THEN
    RAISE EXCEPTION 'NO_COMPANY';
  END IF;

  SELECT * INTO v_company FROM public.companies
  WHERE id = v_user.company_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_COMPANY';
  END IF;

  -- Only an owner/admin of THIS company may run setup writes. Blocks a joined
  -- member (company_id set, not holder/admin) from self-elevating to admin.
  IF NOT (
    COALESCE(v_user.is_company_admin, false)
    OR v_user.id::text = v_company.account_holder_id
    OR v_user.id::text = ANY(COALESCE(v_company.admin_ids, ARRAY[]::text[]))
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE public.companies SET
    name = COALESCE(NULLIF(p_name, ''), name),
    industries = CASE WHEN p_industries IS NOT NULL AND array_length(p_industries, 1) IS NOT NULL
                      THEN p_industries ELSE industries END,
    company_size = COALESCE(p_company_size, company_size),
    company_age = COALESCE(p_company_age, company_age),
    weather_dependent = COALESCE(p_weather_dependent, weather_dependent),
    updated_at = now()
  WHERE id = v_user.company_id;

  UPDATE public.users SET is_company_admin = true, updated_at = now()
  WHERE id = v_user.id;

  PERFORM public.initialize_company_defaults(v_user.company_id);

  RETURN v_user.company_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) FROM public;
-- NOTE: this DB's default privileges auto-grant EXECUTE to anon on new public
-- functions, and REVOKE FROM public does not remove that direct grant — revoke
-- anon explicitly (matches create_company_for_owner / server-only hardening).
REVOKE EXECUTE ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) TO authenticated, service_role;

-- ─────────────────────────────── ROLLBACK ──────────────────────────────────
-- DROP FUNCTION IF EXISTS public.update_company_setup_for_member(text, text[], text, text, boolean);


-- ============================================================================
-- WEB CHANGES (deploy with this migration; gated behind env CRIT3_SUB_IDENTITY)
-- ----------------------------------------------------------------------------
-- 1. src/lib/supabase/find-user-by-auth.ts — when CRIT3_SUB_IDENTITY is on, the
--    email fallback branch (auth_id → firebase_uid → [email]) is skipped, so all
--    identity resolution is cryptographic. (Implemented behind the flag.)
-- 2. src/app/api/setup/progress/route.ts — when the flag is on, the
--    "company exists" branch calls update_company_setup_for_member via
--    getUserScopedClient(token) instead of the service_role is_company_admin /
--    company_id / profile writes, and stops passing the token email to
--    findUserByAuth. (Implemented behind the flag.)
-- 3. src/app/api/auth/join-company/route.ts — the route-local findUserByFirebaseUid
--    duplicates the email fallback (L~199-207). FOLLOW-UP: delete it in favor of
--    the shared findUserByAuth (one hardened resolver), or gate its email branch
--    behind CRIT3_SUB_IDENTITY identically. Documented, not yet code-changed.
-- ============================================================================
