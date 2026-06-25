# Realtime Reschedule Not Live Root Cause

Updated: 2026-06-25

## Current Evidence

- User repro log still shows no successful subscription:
  - `[RealtimeProcessor] Subscribe not completed (attempt 1, join failed: RealtimeError(errorDescription: Optional("Maximum retry attempts reached.")))`
  - Attempts 2+ were `CancellationError()`, which pointed to a client retry bug rather than a server table rejection.
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
- Nick Bradshaw's user row is not missing Firebase identity:
  - `id = 6f5ff13a-7108-4384-9699-0ca58207d3a2`
  - `firebase_uid = auth_id = tDmM2XRxP9PJAESzQbyVXeMQUgv1`
  - `company_id = ddee107c-33cd-483e-8278-0f8d8a180181`

## Current Fix

- `RealtimeProcessor.startListening` now lets scheduled retry tasks call back into `startListening` without cancelling themselves.
- Failed channel joins are removed from Supabase's retained channel registry before scheduling the next retry.
- Before a new join, any retained channel for `realtime:company-<companyId>` is removed so retries do not accumulate duplicate `postgres_changes` bindings on the cached SDK channel.

## Interpretation

The second failure was not another unpublished table and not the raw 15-binding payload. The first failed join appears consistent with a transient tenant/socket-side Realtime outage around the repro window. The app then failed to recover because the retry task cancelled itself and, if allowed to continue, would have reused a failed cached channel with duplicated bindings. The client now retries from a clean channel.
