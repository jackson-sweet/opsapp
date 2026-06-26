# Realtime Reschedule Not Live Root Cause

Updated: 2026-06-26

## Current Evidence

- User repro log after commit `89685545` changes the failure shape:
  - `Firebase JWT ready ... role=authenticated ...`
  - `Channel status -> subscribed`
  - `Subscribed (authenticated) - 15 bindings in 0.32s`
  - No realtime event/dispatch/merge breadcrumb appears after subscription.
    The later calendar updates in the log are background delta sync, not
    realtime.
- Fresh live Supabase checks after that repro:
  - Realtime service logs show tenant initialization/replication startup, not a
    new `create_subscription` table/filter failure.
  - `project_tasks`, `projects`, `deck_designs`, `calendar_user_events`, and
    `notifications` are present in `supabase_realtime`.
  - Five `project_tasks` rows in Nick's company changed around
    `2026-06-26 06:11:21Z`; several were assigned to Nick and matched the
    app's `company_id=eq.ddee107c-33cd-483e-8278-0f8d8a180181` binding.
  - Simulating Nick under Postgres role `authenticated` with Firebase
    `sub=tDmM2XRxP9PJAESzQbyVXeMQUgv1` resolves:
    `private.get_current_user_id() = 6f5ff13a-7108-4384-9699-0ca58207d3a2`,
    `private.get_user_company_id() = ddee107c-33cd-483e-8278-0f8d8a180181`,
    and can select all 56 company `project_tasks`, including the five recent
    updates. So the remaining failure is not authenticated-role RLS invisibility.
- Local `supabase-swift` 2.41.1 source shows the callback-lifetime root cause:
  - `RealtimeSubscription` is a typealias for `ObservationToken`.
  - `ObservationToken` cancels the observation in `deinit` and its doc says to
    store the token to keep the observation alive.
  - OPS was doing `let _ = channel.onPostgresChange(...)` in
    `RealtimeProcessor.subscribeToTable`, which immediately deallocated the
    token and removed every postgres change callback. The channel could still
    join because the SDK's client changes were registered, but no callback
    remained to call `handleChange` when events arrived.
- User repro log after commit `9b6b521e` proves the join is rejected before any
  CDC/table-specific subscription is established:
  - The app logs a real Firebase ID token for Nick:
    `role=—`, `exp=2026-06-25T23:50:40Z`, `sub=tDmM2XRxP9PJAESzQbyVXeMQUgv1`.
  - The raw websocket diagnostic using that exact token and the 15 exact
    bindings returns:
    `Direct join diagnostic — status=error reason=InvalidJWTToken: Fields role and exp are required in JWT`.
  - Because the token summary includes `exp`, the actionable missing field is
    the Firebase custom claim `role='authenticated'`.
  - `subscribeWithError()` still collapses this server reply into
    `RealtimeError("Maximum retry attempts reached.")`, so the raw diagnostic is
    the reliable localizer.
- User repro log after commit `61df30aa` still shows no successful subscription:
  - `[RealtimeProcessor] Subscribe not completed (attempt 1, join failed: RealtimeError(errorDescription: Optional("Maximum retry attempts reached.")))`
  - Attempts 2, 3, and 4 are also `RealtimeError(... "Maximum retry attempts reached.")`.
  - `Socket recovered - rebuilding subscription` fires immediately after each failed join, so socket-status recovery was bypassing the printed backoff.
- Fresh Supabase Realtime logs after the repro showed:
  - `Disconnecting all sockets for tenant ijeekuhbatykdomumfjx`
  - `Database supervisor not found for tenant ijeekuhbatykdomumfjx`
  - Later tenant initialization / replication-slot startup after a direct websocket probe.
  - No new current `create_subscription` table/filter error. The older `role_permissions` Postgrex EncodeError remains in the retained logs but belongs to the already-fixed first cause.
- Fresh SQL check confirmed every current iOS binding is in `supabase_realtime`:
  - `projects`, `project_tasks`, `users`, `clients`, `sub_clients`, `task_types`, `project_notes`, `project_photos`, `project_photo_annotations`, `deck_designs`, `companies`, `expenses`, `expense_batches`, `calendar_user_events`, `notifications`.
- Direct Realtime websocket probe using the app anon key confirmed server accepts:
  - `project_tasks` only
  - `deck_designs` only
  - `notifications` only
  - the 10 core company-filtered bindings
  - the 5 side bindings
  - all 15 bindings in one channel
- Direct Realtime websocket probe of the auth path showed bad join tokens produce explicit server replies:
  - anon/no `access_token`: `status=ok postgres_changes=15`
  - malformed token: `status=error reason=MalformedJWT: The token provided is not a valid JWT`
  - wrong-signature JWT: `status=error reason=JwtSignatureError: Failed to validate JWT signature`
  - live Nick Firebase token without `role`: `status=error reason=InvalidJWTToken: Fields role and exp are required in JWT`
  - This matters because `supabase-swift` `subscribeWithError()` surfaces these as local max-retry timeouts when the channel never reaches `.subscribed`.
- Supabase's Firebase Auth third-party auth docs require assigning the Firebase
  custom user claim `role: 'authenticated'` to all users; Supabase inspects that
  claim to assign the correct Postgres role for Data API, Storage, and Realtime.
  Existing Firebase users need an Admin SDK backfill, and clients need a forced
  ID-token refresh after the claim is added.
- Nick Bradshaw's user row is not missing Firebase identity:
  - `id = 6f5ff13a-7108-4384-9699-0ca58207d3a2`
  - `firebase_uid = auth_id = tDmM2XRxP9PJAESzQbyVXeMQUgv1`
  - `company_id = ddee107c-33cd-483e-8278-0f8d8a180181`
- Simulating Nick's Firebase `sub` under Postgres `anon` resolved identity and company correctly:
  - `private.get_current_user_id() = 6f5ff13a-7108-4384-9699-0ca58207d3a2`
  - `private.get_user_company_id() = ddee107c-33cd-483e-8278-0f8d8a180181`
  - `tasks.view = assigned`
- Simulated Nick RLS checks for the 15 realtime bindings were fast and returned visible rows:
  - `projects=32`, `project_tasks=56`, `users=4`, `clients=11`, `sub_clients=30`, `task_types=21`, `project_notes=54`, `project_photos=28`, `project_photo_annotations=7`, `deck_designs=3`, `companies=1`, `expenses=14`, `expense_batches=47`, `calendar_user_events=0`, `notifications=16`.

## Current Code State

- `RealtimeProcessor.startListening` now lets scheduled retry tasks call back into `startListening` without cancelling themselves.
- Failed channel joins are removed from Supabase's retained channel registry before scheduling the next retry.
- Before a new join, any retained channel for `realtime:company-<companyId>` is removed so retries do not accumulate duplicate `postgres_changes` bindings on the cached SDK channel.
- `RealtimeProcessor` now suppresses socket-status resubscribe while a scheduled join retry is pending.
- `RealtimeProcessor` now logs redacted Firebase JWT metadata before joining:
  - `uid`, `sub`, `sub_matches_uid`, `iss`, `aud`, `role`, `exp`, `kid`, `alg`.
- On SDK join failure, `RealtimeProcessor` now runs a one-shot raw websocket join using the same `postgres_changes` bindings and Firebase token on a unique diagnostic topic, then logs:
  - `[RealtimeProcessor] Direct join diagnostic - status=ok postgres_changes=15 ...`
  - or `[RealtimeProcessor] Direct join diagnostic - status=error reason=<server reason> ...`
  - or a transport/timeout failure.
- `RealtimeProcessor` now refuses to join until a forced-refresh Firebase ID
  token has `role=authenticated`; if the claim is missing it calls OPS-Web
  `/api/auth/sync-user` with `createIfMissing=false` to repair the Firebase
  custom claim server-side, then force-refreshes again before subscribing.
- `RealtimeProcessor` now suppresses socket-recovery rebuilds while a subscribe
  is already in flight, preventing confusing `Socket recovered - rebuilding
  subscription` logs during an in-progress join.
- OPS-Web `/api/auth/sync-user` now uses Firebase Admin SDK to add
  `role='authenticated'` to Firebase-issued users that present a token without
  the claim, preserving any existing custom claims and returning
  `authClaimsUpdated` so clients know to refresh.
- OPS-Web has a dry-run/apply script for the existing Firebase Auth user pool:
  `npm run backfill:firebase-supabase-role -- --apply`.
- Live Firebase backfill was NOT executed in the Codex sandbox during this
  investigation: unsandboxed Firebase Admin/network access was rejected. Until
  the OPS-Web route is deployed or the backfill is explicitly run, already-issued
  production Firebase users may still receive tokens without the role claim.
- Follow-up build fix: `RealtimeProcessor.startListening` originally declared a
  local `String` named `realtimeAccessToken`, which shadowed the helper method
  `realtimeAccessToken(for:)` and produced
  `Cannot call value of non-function type 'String'` at the helper call. The
  local was renamed to `authenticatedAccessToken`.
- Follow-up event-delivery fix: `RealtimeProcessor` now retains every
  `onPostgresChange` `RealtimeSubscription` token for the lifetime of the
  channel, cancels those tokens on teardown / failed join / stop, and logs
  `[RealtimeProcessor] Event received - table=<table>, action=<action>` before
  routing the event to the DataActor or legacy merge path.

## Interpretation

The investigation has now found three separate failures that produced the same
user symptom:

1. The first join failure was a bad table binding: unpublished tables in the
   single channel made server-side `create_subscription` fail.
2. The second join failure was missing Firebase custom claim
   `role='authenticated'`; Realtime rejected the channel before CDC setup.
3. After the join finally succeeded, event callbacks were still dead because the
   returned `RealtimeSubscription` tokens were discarded immediately.

Current evidence rules out another obvious unpublished-table failure, a raw
15-binding payload rejection, a simple Nick identity/RLS visibility gap, and an
authenticated-role RLS visibility gap for `project_tasks`.
If a future repro still fails after claim repair/backfill, key off the raw
diagnostic line:

- `Firebase JWT ready ... role=authenticated` followed by
  `Subscribed (authenticated)` means the channel joined. A teammate edit should
  now also produce `[RealtimeProcessor] Event received ...`; if it does not,
  investigate server emission / SDK message routing.
- `Deferring subscribe - Firebase token missing Supabase role claim` means the
  deployed OPS-Web route/backfill has not repaired that Firebase account yet.
- `Direct join diagnostic - status=error reason=...`: server-side token/JWT
  validation or Realtime auth configuration is still the blocker.
- `Direct join diagnostic - status=ok postgres_changes=15`: the server accepted the exact token and bindings; investigate `supabase-swift` channel handling or implement an SDK workaround/split.
- `Direct join diagnostic failed ... timeout`: device/network websocket path is failing independently of the SDK.
