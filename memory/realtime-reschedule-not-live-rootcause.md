# Realtime Reschedule Not Live Root Cause

Updated: 2026-06-25

## Current Evidence

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
  - This matters because `supabase-swift` `subscribeWithError()` surfaces these as local max-retry timeouts when the channel never reaches `.subscribed`.
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

## Interpretation

The second failure is still not fully proven fixed. The earlier conclusion that this was only a transient tenant/socket outage plus a retry cleanup bug is outdated: the latest repro proves clean-channel retries still hit real SDK join timeouts.

Current evidence rules out another obvious unpublished-table failure, a raw 15-binding payload rejection, and a simple Nick identity/RLS visibility gap. The remaining split is whether the live device's Firebase token is rejected by Realtime/Supabase third-party JWT validation, or whether the server accepts the exact token/bindings and `supabase-swift` is failing to observe/process the successful join reply.

Next repro must key off the new diagnostic line:

- `Direct join diagnostic - status=error reason=...`: server-side token/JWT validation or Realtime auth configuration is the blocker.
- `Direct join diagnostic - status=ok postgres_changes=15`: the server accepted the exact token and bindings; investigate `supabase-swift` channel handling or implement an SDK workaround/split.
- `Direct join diagnostic failed ... timeout`: device/network websocket path is failing independently of the SDK.
