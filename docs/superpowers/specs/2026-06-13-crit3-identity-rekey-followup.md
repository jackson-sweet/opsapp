# CRIT-3 follow-up — re-key identity off the token `sub`, not the email claim

**Status:** OPEN — needs owner decision. Created 2026-06-13 during the onboarding-rebuild security pass.
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
