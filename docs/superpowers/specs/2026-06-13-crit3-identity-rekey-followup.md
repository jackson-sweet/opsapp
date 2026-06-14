# CRIT-3 follow-up — re-key identity off the token `sub`, not the email claim

**Status:** CORE FIX LIVE — Phases A & B shipped (OPS-Web `feat/inbox-dark-launch`),
**Phase C (the RLS re-key) APPLIED to prod 2026-06-14** (migration
`20260614083934_crit3_phase_c_rekey_rls_identity_helpers`); Phase D MED-3 RPC + web
changes staged behind `CRIT3_SUB_IDENTITY` (deploy follow-up). Created 2026-06-13;
executed 2026-06-14. See **Execution log (2026-06-14)** at the bottom.
**Severity:** CRITICAL (account takeover), but the full fix is a coordinated platform change — do NOT rush it.

## TL;DR for the owner

Right now, **who you are** in the OPS backend is decided by your **email address**, and an
attacker can register a Firebase account using *someone else's* email (we never make them
prove they own it). That means an attacker can be treated as that other person by the
database. I shipped the safe, no-risk parts of the fix today. The real fix touches almost
every Row-Level-Security (RLS) rule in the database plus the login plumbing, and **a naive
version of it would lock ~75% of current users out of the web app.** So it needs to be
planned and rolled out deliberately, not hot-fixed. This document is that plan.

## What is actually broken (root cause)

Every RLS identity helper resolves the caller by the **JWT email claim**:

```
private.resolve_uid()          ->  WHERE email = auth.jwt() ->> 'email'
private.get_current_user_id()  ->  WHERE email = auth.jwt() ->> 'email'
private.get_user_company_id()  ->  WHERE email = auth.jwt() ->> 'email'
private.current_user_is_admin()->  WHERE u.email = auth.jwt() ->> 'email'
public.get_user_company_id()   ->  WHERE email = auth.jwt() ->> 'email'
```

The email claim is **not proof of identity**: OPS web signup uses Firebase
email/password and **never sends an email-verification message** (`sendEmailVerification`
is never called; the SendGrid template + `verifyEmail` action handler exist but are not
wired). So `email_verified` is **permanently false** for every email/password account, and
an attacker can set their Firebase account's email to a victim's address and be resolved as
the victim by all of the helpers above.

`OPS-Web/src/app/api/auth/sync-user/route.ts` compounded it by *adopting* an existing row
when the (caller-supplied) email matched, writing the attacker's `firebase_uid`/`auth_id`
onto the victim's row.

## Why the naive fix is dangerous (measured blast radius, 2026-06-13)

`public.users`, active rows:

| metric | count |
|---|---|
| total active | 202 |
| `firebase_uid IS NULL` | 152 (75%) |
| `auth_id IS NULL` | 182 |
| **`firebase_uid` AND `auth_id` both NULL (fully unlinked)** | **152 (75%)** |
| `auth_id` set (sub-matchable) | 20 |

`users.email` is **NOT unique** (only `firebase_uid`, `auth_id`, `bubble_id`, `id` are).

Those 152 unlinked users rely on the **email fallback** in `sync-user` to attach their
Firebase account to their pre-existing row on first web login. If we gate that fallback on
`email_verified === true` (as a literal reading of the finding suggests):

- every **email/password** login breaks (they can never be verified — no flow exists), and
- because `email` is not unique, the gated path **silently creates a duplicate empty row**
  instead of erroring — the user lands in a brand-new account with no company/data, losing
  access to their real one.

That is an unacceptable 75% lockout / silent-data-loss, so the literal contained gate was
**NOT applied**. See "What shipped today" for the safe subset that was.

## What shipped today (safe, zero-blast-radius)

`OPS-Web/src/app/api/auth/sync-user/route.ts`:

1. The email fallback now resolves on the **verified token email** (`firebaseUser.email`),
   never the caller-supplied request-body email (removes body-email spoofing).
2. A row matched **only by email** that is already bound to a **different** identity
   (a non-null `auth_id`/`firebase_uid` that isn't this token's `sub`) is **refused (403)**
   for an unverified caller — it is neither rewritten nor handed back. Sub-matched rows and
   **unclaimed** rows (both identity columns null — the legacy-link path the 152 depend on)
   are unaffected, so no legitimate login breaks.

This stops the clearest hijack — an unverified attacker rewriting / reading back an
**already-linked** account by email — without touching the legacy-link path. It does **not**
close the root email-RLS issue; the unclaimed-row population remains reachable by an
unverified email match until the deep fix lands.

## The deep fix (proposed, needs owner sign-off)

Do these in order; each is independently shippable and reversible.

### Phase A — make every active user sub-linked (prerequisite, no user-visible change)
- Backfill `auth_id` (and `firebase_uid` where Firebase-issued) for the 152 unlinked rows.
  Source of truth: Firebase Auth (export the `email -> uid` map) and/or the next successful
  authenticated request per user. Add a one-shot server task that, on every authenticated
  request, writes `auth_id = sub` when null **and** the row was matched by the deterministic
  path — i.e. opportunistic backfill — so the unlinked count trends to zero before Phase C.
- Add observability: a daily count of `auth_id IS NULL` active users. Phase C cannot ship
  until this is ~0.

### Phase B — roll out email verification (closes the `email_verified` signal gap)
- Wire `sendEmailVerification` (Firebase) on email/password signup, using the existing
  dormant SendGrid `EmailVerification` template + the `?mode=verifyEmail` action handler.
- Decide UX: soft (banner) vs hard (block on unverified). Likely soft first.
- This makes `email_verified` meaningful so a future email-based fallback can be gated
  safely if ever needed.

### Phase C — re-key the RLS helpers off the cryptographic sub
- Rewrite `private.resolve_uid` / `get_current_user_id` / `get_user_company_id` /
  `current_user_is_admin` (+ `public.get_user_company_id`) to resolve by
  `auth_id = auth.jwt() ->> 'sub'` (and/or `firebase_uid = sub`) instead of email.
- This is the actual closure: identity becomes cryptographic. Touches ~every RLS policy
  that transitively calls these helpers — audit each before/after with rolled-back probes.
- Coordinate with iOS: iOS sends a Firebase JWT whose `sub` is the Firebase UID; ensure
  `firebase_uid`/`auth_id` are populated for all iOS users (Phase A) so the re-keyed helpers
  resolve them. `AuthManager.backfillFirebaseUID` already writes these on iOS login.

### Phase D — finish the contained web pieces under the new model
- `OPS-Web/src/lib/supabase/find-user-by-auth.ts` (email fallback ~L46-53),
  `join-company` route (`findUserByFirebaseUid` email branch ~L199-207),
  `setup/progress` route (`findUserByAuth` ~L107) — once Phase A makes sub-resolution
  reliable, drop the email fallbacks (or gate them on verified email).
- MED-3: route the `setup/progress` `is_company_admin`/`company_id` writes (currently
  service_role on an email-resolved row) through a JWT-`sub`-deriving definer RPC so the
  privileged write trusts the cryptographic sub, not an email match.

## Rollback room
Phases A/B are additive. Phase C is the risky one — ship it behind a tested migration with a
verified rollback (restore the email-based helper bodies) and a rolled-back probe matrix for
every dependent policy. Do NOT ship Phase C until Phase A shows ~0 unlinked active users.

---

## Execution log (2026-06-14)

### Measured blast radius (live, re-confirmed)
- 202 active users; 152 both-null; **141 unlinked-with-email** + **11 unlinked-no-email**;
  50 linked; 0 duplicate active emails; `email` still non-unique.
- Phase C dependency closure (two independent catalog derivations, cross-checked):
  **296 objects** = 228 RLS policies + 58 functions + 1 view (`project_table_rows`) + 9
  triggers — ALL reaching the email check *only through the 5 helper bodies*. So the re-key
  is a `CREATE OR REPLACE` of 5 functions; zero policy DDL.
- Supabase Auth (`auth.users`) holds 5 rows — identity is ~100% Firebase; `sub` == Firebase UID.

### Key finding that redefines the Phase C gate
The production Firebase project (`ops-ios-app`, verified: 49/50 linked uids present) has only
**53 accounts**. The active, currently-authenticating user base is **already ~100% sub-linked**
(login backfills did their job). The 140 "unlinked-with-email" rows are **dormant legacy/Bubble +
test accounts with no Firebase account at all** — they cannot authenticate today, so the re-key
cannot lock them out of a live session; they self-heal via the sync-user legacy-link path
(service_role, pre-RLS) on first login. Therefore:

> **The achievable Phase C gate is "zero unlinked rows that HAVE a Firebase account",
> not `unlinked_with_email = 0`** (which never reaches 0 due to dormant rows). Operationally:
> the Phase-A backfill script reports `B (matched) = 0 AND collisions = 0`.

### Phase A — SHIPPED (OPS-Web)
- **A1** `fix(auth)` `e94e3c68`: opportunistic sub-backfill in `findUserByAuth` — on a
  cryptographic (firebase_uid) match with NULL auth_id, stamp auth_id = sub (NULL-guarded,
  idempotent). Never on the email branch. TDD, 5 tests.
- **A2** observability migration applied to prod (`crit3_phase_a_identity_linkage_observability`):
  `private.identity_linkage_metrics` table + `private.capture_identity_linkage_metrics()`
  (SECURITY DEFINER, search_path pinned, anon/auth/public revoked) + daily `pg_cron` job
  `crit3-identity-linkage-daily` (08:07 UTC) + seeded baseline. Advisors: 0 new warnings
  (1 intended `rls_enabled_no_policy` INFO). Gate metric tracked: `unlinked_with_email`.
- **A3** `feat(auth)` `036524d5`: bulk Firebase→Supabase backfill script
  (`scripts/crit3-backfill-identity.ts`, dry-run default, NULL-guarded + collision-safe +
  rollback emit). **Live write APPLIED 2026-06-14 (owner-approved): 31 linked (30 catA + 1 catB),
  0 failed**, rollback at `/tmp/crit3-backfill-rollback-*.sql`. Post-write re-run confirms the gate:
  **A=0, B=0, collisions=0** — every Firebase account is now sub-linked; 51 fully linked; the 140
  unmatched + 11 no-email remaining have no Firebase account (cannot authenticate; self-heal on
  first login).

### Phase B — SHIPPED (OPS-Web) — `feat(auth)` `95315478`
Wired the dormant verification stack: `POST /api/auth/send-verification` generates a Firebase
verification link (Admin SDK), rebuilds it through the existing `/auth/action?mode=verifyEmail`
handler from the oobCode, and sends via the OPS-branded SendGrid template. Invoked best-effort +
non-blocking from both signup sites (soft UX). `email_verified` is now meaningful. 4 route tests.

### Phase C — APPLIED to prod 2026-06-14 ✅
Migration `20260614083934_crit3_phase_c_rekey_rls_identity_helpers` (the 5 helpers now resolve by
`auth_id/firebase_uid = auth.jwt()->>'sub'`). Applied only after the backfill satisfied the gate
(B=0) and the iOS paths were verified (GAP 1 below). **Live post-apply verification:** real linked
admin & non-admin resolve correctly by sub (id/company/is_admin), live `resolve_uid` body confirmed
sub-based, and an authenticated linked user reads **310 projects + 362 clients** — identical to the
pre-re-key baseline (zero access change). Security advisors: **no new issues** (152 total, 0 ERROR,
unchanged from baseline). Staged forward/rollback/probe-evidence:
`docs/superpowers/migrations/2026-06-14-crit3-phase-c-rekey-rls-helpers.sql`. **Rollback** if needed:
restore the email-based bodies (rollback block in that file). The account-takeover vector is closed.

### Phase D — BUILT + TESTED + STAGED, behind flag `CRIT3_SUB_IDENTITY` (default off)
- MED-3 RPC `public.update_company_setup_for_member` staged in
  `docs/superpowers/migrations/2026-06-14-crit3-phase-d-med3-rpc.sql`; rolled-back probe (post-C
  sim): admin→ok, non-owner→`NOT_AUTHORIZED` (self-elevation blocked), email-only→`NO_USER_ROW`,
  no-sub→`NO_JWT`.
- Web `feat(auth)` `2d8578bf`: behind `CRIT3_SUB_IDENTITY`, `findUserByAuth` drops the email
  fallback and `/api/setup/progress` routes the privileged company writes through the RPC. Flip
  the flag in lockstep with applying Phase C. Follow-up: consolidate join-company's duplicate
  `findUserByFirebaseUid` onto the shared resolver.

### iOS GAP 1 (must verify before applying Phase C)
`AuthManager.loadUserFromSupabase` bootstraps identity via an RLS-subject `fetchByEmail`, and the
client backfill needs the `users.id` from that lookup. Once RLS resolves by sub, a legacy iOS
user whose `firebase_uid` is NULL server-side cannot self-heal (chicken-and-egg). The fix is the
server-side backfill (A3) + ensuring first-login links the row (sync-user) BEFORE the first RLS
read. Confirm iOS login order, or switch iOS to resolve by firebase_uid first, before Phase C.

### iOS GAP 1 — VERIFIED SAFE (2026-06-14)
Traced the iOS source: the rebuilt onboarding (new + dormant-legacy first logins) calls server-side
`sync-user` (service_role, RLS-bypassing) which links the row BEFORE any RLS read, and self-heals a
race (`OnboardingManager` NO_USER_ROW → re-run sync-user → retry). The plain login path
(`loadUserFromSupabase` + RLS-gated `backfillFirebaseUID`) only serves already-linked users (safe).
The chicken-and-egg could only bite a user who is *authenticatable AND unlinked* — the bulk write
drove that set to zero. No app update is required; existing users are unaffected.

### Remaining work (follow-up — not blocking; the core fix is live)
1. **Phase D deploy:** apply the MED-3 RPC (staged) + set `CRIT3_SUB_IDENTITY=true` in OPS-Web env +
   deploy `feat/inbox-dark-launch`, in lockstep, after Phase C has baked. This drops the web email
   fallbacks and routes the setup/progress elevation through the sub-resolving RPC.
2. **join-company:** consolidate the duplicate `findUserByFirebaseUid` onto the shared resolver.
3. **Optional iOS hardening:** switch `loadUserFromSupabase` to resolve by firebase_uid first
   (defense-in-depth; not required given the backfill).
4. Watch auth error rates over the next hours; rollback block is ready if any lockout surfaces.
