# Companies RLS privilege-escalation — fixed (CRIT-2 follow-up)

**Status:** RESOLVED — migration `guard_companies_privileged_columns_crit2` applied to prod
(`ijeekuhbatykdomumfjx`) 2026-06-14. Verified live before and after.
**Severity:** CRITICAL (privilege escalation + billing/paywall bypass).
**Discovered:** during the CRIT-2 remediation (2026-06-13), while hardening `public.users`.

## TL;DR for the owner

Any logged-in **non-admin** member of a company could quietly **make themselves an admin**
of that company — and could rewrite the company's **billing** (mark the subscription active,
give themselves unlimited seats, free priority support, an endless trial). The database rule
that was supposed to protect the company record let *every member* write to it, with no
"are you an admin?" check. We confirmed the hole was live (a non-admin test member
successfully added themselves to the admin list and flipped the subscription to active — both
inside a transaction we rolled back, so no real data changed). It is now closed. Owners and
admins can still do everything they could before — edit company settings, manage seats — and
the Stripe/billing machinery is untouched.

## What was broken (root cause)

The RLS policy `company_self_access` on `public.companies` was `FOR ALL` to `PUBLIC` with:

```
USING (id = private.get_user_company_id())   -- no admin gate, no WITH CHECK
```

`FOR ALL` + no admin gate means any authenticated member of the company passed it for
**UPDATE/DELETE/INSERT**, not just SELECT. So a non-admin could:

- `UPDATE companies SET admin_ids = admin_ids || '<self>'` → and because
  `private.current_user_is_admin()` treats membership in `admin_ids` (and `account_holder_id`)
  as "is admin", they instantly became an admin. That defeats the CRIT-2 `users` guard
  (`guard_users_privileged_columns`), whose `role`-change branch trusts `current_user_is_admin()`.
- `UPDATE companies SET subscription_status='active', max_seats=9999, …` → billing/paywall bypass.

It was also the **only** member-facing SELECT path (the two `company_*_for_creator` policies
only cover the account holder), so the fix had to preserve member reads.

## The fix (mirrors `guard_users_privileged_columns_crit2`)

Migration `guard_companies_privileged_columns_crit2`:

1. **Split `company_self_access`** into:
   - `company_member_select` — `FOR SELECT USING (id = get_user_company_id())` (members keep read).
   - `company_admin_write` — `FOR ALL USING/WITH CHECK (id = get_user_company_id() AND current_user_is_admin())`
     (writes are admin-only). Parallel to `users_company_select` + `users_company_admin`.
2. **`guard_companies_privileged_columns_trg`** (BEFORE UPDATE) — defense-in-depth column lock.
   For `current_user IN ('authenticated','anon')` **only** (so the SECURITY DEFINER onboarding
   RPCs, which run as `postgres`, and the ops-web Stripe routes/webhook/crons, which run as
   `service_role`, are exempt), it blocks client writes to the escalation/billing columns:
   - **Blocked for all clients (incl. admins):** `admin_ids`, `account_holder_id`, `max_seats`,
     `subscription_status`, `subscription_plan`, `subscription_end`, `subscription_period`,
     `subscription_ids_json`, `trial_start_date`, `trial_end_date`, `seat_grace_start_date`,
     `has_priority_support`, `priority_support_period`, `data_setup_purchased/completed/scheduled`,
     `stripe_customer_id`, `company_code`.
   - **Allowed for admins only:** `seated_employee_ids` (seat management is a real admin-gated
     client write on both surfaces).

The onboarding RPCs (`create_company_for_owner`, `join_user_to_company`) and the Stripe
machinery are the **only** mutators left for the privileged columns.

## Blast radius (verified, ops-ios + OPS-Web)

Audited every authenticated-client write to `public.companies`:

- **`admin_ids` / `account_holder_id`:** no client writes them at all. The role/admin model
  lives on `users` + `user_roles` (iOS `Company.setAdminIds` is dead code; web `mapToDb` *can*
  emit them but no caller passes them). Only the legacy onboarding INSERT seeded them, and that
  path is superseded by the `create_company_for_owner` RPC. → safe to block entirely.
- **Billing/entitlement columns:** written **only** by `service_role` (Stripe webhook,
  `/api/stripe/*`, reconcile + expire-grace crons) or the OPS platform-admin console, plus the
  creation-time RPC. → safe to block for clients.
- **`seated_employee_ids`:** a real admin-gated authenticated write (iOS `addSeat/removeSeat`
  gated `settings.billing`; web `useAdd/RemoveSeatedEmployee` gated `team.manage`). **All 53
  seat-managers in prod satisfy `current_user_is_admin()`** (the permissions `settings.billing`,
  `team.manage`, `settings.company` are held only by the `Owner`/`Admin` presets, both
  `is_company_admin=true`). → allowed for admins, blocked for non-admins.
- **`subscription_status` (the one trap):** iOS `SubscriptionManager.checkSubscriptionStatus()`
  fires a `subscription_status='expired'` write for *any* member when a trial has lapsed. But it
  is **fire-and-forget with a swallowed error**, and **both clients compute trial lockout from
  `trial_end_date`, not from the stored status** (iOS `shouldLockoutUser` LAYER 5; web
  `use-lockout-date.ts`). So blocking it changes **no user-facing behavior**. → blocked.

## Verification

Tested as simulated `authenticated`/`service_role` sessions (`SET LOCAL ROLE` + `set_config`
`request.jwt.claims`), every mutation rolled back via `RAISE`. Before apply: non-admin could
write `admin_ids` and `subscription_status` (`rows_updated=1`). After apply:

| Actor | Action | Result |
|---|---|---|
| non-admin | write `admin_ids` | RLS-denied (0 rows) — **hole closed** |
| non-admin | write billing | RLS-denied (0 rows) |
| non-admin | read company | readable — member SELECT preserved |
| admin | edit name / logo / color / precise_scheduling | allowed |
| admin | seat management (`seated_employee_ids`) | allowed |
| admin | change `admin_ids` / `subscription_status` / `max_seats` / `trial_end_date` / `stripe_customer_id` / `company_code` / `account_holder_id` | trigger-blocked (42501) |
| service_role | write billing (`max_seats` delta) | allowed/exempt — Stripe path intact |

`get_advisors(security)` after apply: 0 new lints touching `companies` or the new objects.

## Follow-ups

1. **iOS dead self-heal write — DONE** (ops-ios `7087264f`). Removed the now-blocked
   `subscription_status='expired'` write from `SubscriptionManager.checkSubscriptionStatus()`
   (left a breadcrumb so it isn't re-added). Lockout is unaffected — `shouldLockoutUser()`
   LAYER 5 derives it from `trialEndDate`.
2. **Server-side trial expiry — DONE** (OPS-Web `9a24df26`). `TrialExpiryService.sweepExpiredTrialStatuses()`
   (service_role, run from the existing daily `/api/cron/trial-expiry` cron) flips
   `subscription_status 'trial'→'expired'` for trials ended **>35 days** ago. The 35-day buffer
   sits past the last re-engagement notification mark (day 30, whose scan keys on
   `status='trial'`) so notifications still fire, then the status is made honest. Unit-tested.
3. **Custom-role invariant (standing note).** The admin-only write policy assumes every seat/settings manager is
   an admin (`current_user_is_admin()`). If a future **custom** role grants `team.manage` /
   `settings.billing` to a non-admin, their seat writes will start failing server-side. Today 0
   such users exist.
