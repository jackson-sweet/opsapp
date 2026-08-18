# IOS NOTIFICATIONS RPC — Legacy Call-Site Wave (P1-3) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Rewire the 29 remaining dead `createNotification` call sites (bug e302355c ADDENDUM) through 21 new narrow SECURITY DEFINER RPCs, per the doctrine delivered in migrations `20260818023254_ios_notification_surface_rpcs` + `20260818023657_measurement_notification_dedupe_keys`.

**Architecture:** One narrow RPC per surface shape. Actor identity from `private.get_current_user_id()`; company from the actor's row; recipients derived server-side from anchor rows (`projects.team_member_ids`, `project_tasks.team_member_ids`, `calendar_user_events`, `team_invitations`, `inventory_items`, `catalog_stock_units`, `project_notes`) or `public.users_with_permission` — never raw caller input (caller-supplied id lists may only SUBSET a row's recorded membership). Fixed server-side copy templates, byte-parity with the shipped client strings; caller data limited to clamped counts / validated numerics / sanitized self-display strings. Server-literal types. `action_url` internal-path-or-NULL (`ops://` scheme is constraint-invalid; drop it everywhere). Dedupe: persistent surfaces hold at-most-one-unread under advisory xact locks; event surfaces ride the platform unread indexes with discriminating `dedupe_key`s (rows carrying distinct information MUST set one — the `(user, company, type, COALESCE(dedupe_key, title))` unread index swallows same-title rows otherwise). Where the server owns recipient selection and the client pushes via OneSignal, the RPC returns the ids that received NEW rows so push targets rail truth.

**Tech stack:** Postgres plpgsql (prod project `ijeekuhbatykdomumfjx`, applied via MCP `apply_migration`, mirrored byte-exact into `ops-software-bible/migrations/`), Swift/SwiftData iOS bindings in `NotificationRepository` § "Narrow creation RPCs", XCTest with protocol-seam spies (archetypes: `OPSTests/TimeOffDecisionNotificationTests.swift`, `OPSTests/ImageSyncCrewNotificationTests.swift`).

**Design system:** N/A (no UI). Notification copy is user-facing → preserved shipped strings verbatim; the only new copy decisions are recorded per-RPC below (ops-copywriter register: terse, no exclamation points).

**Required skills for executing agents:** superpowers:test-driven-development, superpowers:verification-before-completion.

**Worktree:** `ops-ios/.worktrees/notification-rpc-legacy-20260817` on branch `feat/notification-rpc-legacy-callsites-20260817` (merge → local `main` at the end; NEVER push). Copy `OPS/Utilities/Secrets.xcconfig` in; build with `-clonedSourcePackagesDirPath .spm-local` + worktree-local DerivedData.

---

## Verified recon facts (do not re-derive; re-verify only where marked AGENT-VERIFY)

- `notifications` columns: `user_id text, company_id text, type, title, body, project_id text, note_id text, expense_id text, batch_id text, deep_link_type, persistent bool, action_url, action_label, dedupe_key, is_read, resolved_at …`.
- Unread dedupe index: `UNIQUE (user_id, company_id, type, COALESCE(dedupe_key,title)) WHERE is_read=false AND resolved_at IS NULL`; plus `notifications_open_dedupe_key` and title-only variant. `notification_action_url_internal` CHECK: NULL or `/`-prefixed internal path (no `//`, no backslash, no control chars).
- `users_with_permission(p_company_id uuid, p_permission text, p_required_scope text)` = holders at scope or higher. `has_permission(p_user_id uuid, p_permission text, p_required_scope text)`.
- `PermissionStore.can(_:)` defaults to `requiredScope: "all"` → client gates `time_off.approve` (book-for-others) and `finances.view` (billable week) are ALL-scope; the Forecast dispatcher's recipient lookup explicitly used scope `own`.
- `calendar_user_events`: `user_id text` (target), `status` in none/pending/approved/denied, `reviewed_by`, NO creator column → the request-side requester is the ACTOR by definition.
- `project_tasks`: `custom_title`, `task_type_id → task_types.display`, `team_member_ids text[]`, `dependency_overrides jsonb`, `paired_from_task_id`, `start_date timestamptz`, `status` text with legacy raw values (`Completed`, `In Progress`, `Booked`… — always compare `lower(status)`).
- Task display name = `COALESCE(NULLIF(BTRIM(custom_title),''), task_types.display, 'Task')`. Project title = `COALESCE(NULLIF(BTRIM(title),''), 'Untitled project')`.
- `TaskTypeDependency` encodes with default Codable → **camelCase** JSON keys (`dependsOnTaskTypeId`) in both `project_tasks.dependency_overrides` and `task_types.dependencies`. AGENT-VERIFY with a live sample row before relying on it in tests.
- `inventory_items`: `name, quantity double, warning_threshold, critical_threshold`; iOS site uses **item-level** `thresholdStatus`: critical if `qty <= critical_threshold`, else warning if `qty <= warning_threshold`. Body count is Swift `Int(quantity)` = truncation.
- `team_invitations`: `email, phone, role_id, invited_by uuid, status, created_at`. iOS `InviteResponse` carries **no ids** → RPC matches recent rows (`invited_by = actor`, contact ∈ inputs, `created_at >= now()-'10 min'`, `status <> 'cancelled'`).
- `catalog_stock_units`: `width_value numeric, width_unit, original_length_value, remaining_length_value, length_unit, unit_kind` — vinyl service stores **feet** (`"ft"`). Engine copy renders inches: `inchLabel(w×12)` (round to 0.1, drop trailing .0) and `vinylFormatFeetAndInches(len×12)` (`F'` when whole feet, `F' I"` else, `I"` when <1ft; inches rounded to 0.1, 1-decimal only when fractional).
- `roles`: `name text` (+ per-company custom rows); `user_roles(user_id text, role_id, created_at)`. Client copy uses `UserRole.displayName`: admin→Admin, owner→Owner, office→Office, operator→Operator, crew→Crew, unassigned→Unassigned.
- `forecast_alerts` ledger stays client-driven (anti-spam cadence); the RPCs own only rail-row creation/resolution.
- `BooksFormat.currency` = USD, 0 fraction digits, grouped (negative renders `-$1,234`).
- `DateHelper.simpleDateString` = `"MMM. d"` (e.g. `Aug. 17`); vinyl bulk body uppercases it → `AUG. 17`.
- Time-off date range: `"MMM d"`, en-dash join `start – end` when multi-day (unifying the two shipped variants; TimeOffRequestSheet already shipped the en dash).
- Prior-wave test archetype: protocol seam next to the caller (`protocol XxxNotifying` + `extension NotificationRepository: XxxNotifying {}` + injectable `var` defaulting to `NotificationRepository.shared`), spy records calls/returns scripted results/throws; tests pin (1) verbatim forwarding, (2) zero-work short-circuit, (3) server-owns-recipients (no client-side recipient short-circuits), (4) push targets returned ids only, (5) transport failure containment. SwiftData test fixtures MUST retain containers (`retainedContainers`), seed a warm-up `SyncOperation` before any code path that fetches them, and use `AppHostWindow.acquire()` if any window work (none expected here).
- No pbxproj edits needed for new test files (filesystem-synchronized groups — prior wave added 5 test files with zero pbxproj delta).
- OneSignal lanes stay client-side. Existing signatures used by this wave: `notifyTaskCompletion(userIds:…)`, `notifyProjectCompletion(userIds:…)`, `notifyScheduleChange(userIds:…)`, `notifyScheduleBatchUpdate(userMoveCounts:)`, `notifyTaskAssignment(userId:…)`, `notifyProjectAssignment(userId:…)`, `notifyDependencyCompleted(…recipientUserIds:…)`, `sendToUser(userId:…)`, `sendToUsers(userIds:…)`.

---

## RPC contracts (21)

Shared plumbing for every RPC (copy from the 023254 archetypes verbatim): `security definer`, `set search_path to 'pg_catalog','pg_temp'`, actor resolve + company/active check → 42501 `'notification actor is unavailable'`, anchor-row company validation → 42501, invalid input / unrecorded state → 22023, `revoke all … from public, anon, authenticated, service_role; grant execute … to anon, authenticated;`. All inserted `user_id`/`company_id`/`project_id`/`note_id` values are `::text`. Recipient candidate ids are `lower(btrim(x))` + UUID-regex + company/active user validation (the `notify_project_photos_added` pattern).

### Group A — task/project lifecycle (DataController + ProjectFormSheet)

**A1 `notify_task_completed(p_task_id uuid) returns text[]`** — sites DataController:3987.
Anchor task (`FOR SHARE`): company, `deleted_at IS NULL`, `lower(status)='completed'` else 22023 `'task is not completed'`. Project row from `task.project_id`. Recipients = **project** `team_member_ids` minus actor. Copy: title `Task Completed`, body `{actor_name} completed "{task_display}" on {project_title}` (actor_name fallback `A team member`). type `task_completion`, deep_link `projectDetails`, `project_id` set, no action_url/label. dedupe `task-completed:{task_id}` (unread-collapse; re-completion after read legitimately re-notifies). Advisory lock on the dedupe key. Returns created ids → client `notifyTaskCompletion` targets them.

**A2 `notify_project_completed(p_project_id uuid) returns text[]`** — DataController:4213.
Project row: `lower(status)='completed'` else 22023 `'project is not completed'`. Recipients = project team minus actor. title `Project Completed`, body `"{project_title}" has been marked as completed`. type `project_completion`, deep_link `projectDetails`, project_id. dedupe `project-completed:{project_id}`. Returns created ids → `notifyProjectCompletion`.

**A3 `notify_task_rescheduled(p_task_id uuid) returns text[]`** — DataController:4321.
Task: not deleted, `lower(status) NOT IN ('completed','cancelled')` else 22023 `'task schedule is not announceable'`, `start_date IS NOT NULL AND end_date IS NOT NULL` else 22023. Recipients = **task** team minus actor. title `Schedule Update`, body `"{task_display}" on {project_title} has been rescheduled`. type `schedule_change`, deep_link `taskDetails`, project_id. dedupe `task-rescheduled:{task_id}`. Returns created ids → `notifyScheduleChange`.

**A4 `notify_dependency_ready(p_completed_task_id uuid) returns jsonb`** — DataController:4772.
Completed task: `lower(status)='completed'` else 22023. Dependents = same-project non-deleted tasks ≠ completed task where effective deps (`CASE WHEN jsonb_typeof(t.dependency_overrides)='array' THEN t.dependency_overrides ELSE tt.dependencies END`) contain an element with `elem->>'dependsOnTaskTypeId'` = completed task's `task_type_id::text` (case-insensitive id compare). Per dependent: recipients = its team minus actor; title `Ready to start`, body `{dependent_display} on {project_title} — {completed_display} is complete` (em dash, exact shipped string); type `dependency_completed`, deep_link `taskDetails`, project_id; dedupe `dependency-ready:{completed_id}:{dependent_id}`. Returns `jsonb` array `[{"task_id": "...", "user_ids": [...]}]` (created-only, omit empty tasks) → client loops `notifyDependencyCompleted` per entry, resolving titles from local rows.

**A5 `notify_task_assigned(p_task_id uuid, p_user_ids text[] default null) returns text[]`** — DataController:4992 (delta), ProjectFormSheet:3158 (all).
Task not deleted. Candidates = `COALESCE(p_user_ids, team_member_ids)` normalized, **intersected with the row's `team_member_ids`** (caller may only subset recorded membership), minus actor, active users. title `New Task Assignment`, body `You've been assigned to "{task_display}" on {project_title}`. type `task_assignment`, deep_link `taskDetails`, project_id. dedupe `task-assigned:{task_id}`. Returns created ids → per-id `notifyTaskAssignment`.

**A6 `notify_project_assigned(p_project_id uuid, p_user_ids text[]) returns text[]`** — ProjectFormSheet:2709.
Candidates ∩ `projects.team_member_ids`, minus actor. title `Added to Project`, body `You've been added to "{project_title}"`. type `project_assignment`, deep_link `projectDetails`, project_id. dedupe `project-assigned:{project_id}`. Returns created ids → per-id `notifyProjectAssignment`.

**A7 `notify_task_pair_spawned(p_task_id uuid) returns text[]`** — DataController:5765.
Spawned task row: `paired_from_task_id IS NOT NULL` else 22023 `'task is not a spawned pair'`; predecessor row same company (join). Type display from spawn's task_type; date blurb `''` when `start_date IS NULL` else ` for ` + `to_char(start_date at time zone 'utc', 'Dy Mon FMDD')` (= shipped `EEE MMM d`). Body `Auto-scheduled {UPPER(type_display)}{blurb} — paired from {predecessor_display}`; title `// NEW TASK`. Recipients = predecessor `team_member_ids` (validated); **fallback actor when none valid; actor NOT excluded** (shipped behavior — the spawn is system-initiated info). type `task_pair_spawned`, deep_link `projectDetails`, project_id = spawn's. dedupe `task-pair-spawned:{task_id}`. No push lane. **Call-site ordering:** the dispatch Task must `await syncEngine.pushPending()` FIRST so the spawn create ops land before the RPC reads the rows (applySchedulingPlan precedent); offline → RPC fails → best-effort drop, contained.

**A8 `notify_schedule_run_summary(p_task_ids uuid[]) returns jsonb`** — DataController:7974 (bulk auto-schedule; rows already pushed via `pushPending()` before this runs).
Validate `1 <= cardinality <= 500` else 22023. Moved tasks = input ids resolved to company rows (not deleted); per-member counts from their `team_member_ids`, minus actor. Per member: title `Schedule updated`, body `1 of your tasks was rescheduled` / `{n} of your tasks were rescheduled`; type `schedule_change`, deep_link `jobBoard`, project_id NULL. dedupe `schedule-run:` + `md5` of the sorted task-id list (identical re-run while unread collapses; different run = new info). Returns `[{"user_id":"…","moved_count":n}]` created-only → `notifyScheduleBatchUpdate(userMoveCounts:)`.

### Group B — vinyl (DeckBuilder)

**B1 `notify_vinyl_order_drafted(p_project_id uuid, p_note_id uuid, p_ordered_sq_ft integer) returns text`** — VinylOrderSheet:1630. Self.
Project row validated; note row: same project, `author_id = actor`, not deleted else 42501. sq ft clamped 1..1000000. title `// VINYL ORDER DRAFTED`, body `{UPPER(project_title)} · {sqft} SQ FT READY`. type `catalog_order_drafted`, deep_link `catalogOrders`, project_id + note_id, action_url **NULL** (was `ops://catalog/orders?tab=draft` — constraint-invalid; phone workflow, threshold-rail precedent), action_label `REVIEW`. dedupe `vinyl-order-drafted:{note_id}`. Returns created/noop. Call site keeps its `railFailed` status branch (`ORDER DRAFTED / RAIL FAILED`) — treat RPC throw as railFailed.

**B2 `notify_vinyl_bulk_ordered(p_marked_count integer) returns text`** — VinylBulkOrderWizardView:1186. Self.
Count clamped 1..10000. Body `{n} PROJECT{S} · {UPPER(to_char(now(),'Mon'))}. {to_char(now(),'FMDD')}` → e.g. `3 PROJECTS · AUG. 17` (server clock; parity with uppercased `MMM. d`). title `// VINYL ORDERED`. type `vinyl_bulk_ordered`, no links. dedupe `vinyl-bulk-ordered:` + md5(body). Returns created/noop.

**B3 `notify_vinyl_offcut_banked(p_stock_unit_id uuid, p_project_id uuid default null) returns text`** — VinylOffcutInventoryService:319. Self.
Stock unit row: company, `unit_kind='offcut'`, not deleted else 42501. Optional project validated when present else NULL. width/length inches = value × 12 when unit `ft` (× 1 when `in`, else 22023). Render: width `inchLabel` (round 0.1; whole → int, else 1-decimal) + `"`; length `vinylFormatFeetAndInches` (feet = trunc(rounded/12); whole feet & no inches → `{F}'`; feet>0 → `{F}' {I}"`; else `{I}"`). Body `{W} × {L} BANKED TO STOCK`, title `// OFFCUT BANKED`. type `standard` (shipped), deep_link `catalog_stock`, action `/catalog?segment=stock` / `VIEW STOCK`. dedupe `vinyl-offcut-banked:{stock_unit_id}`. Returns created/noop.

### Group C — guided setup completions

**C1 `notify_guided_setup_completed(p_kind text, p_product_count integer default null, p_recipe_count integer default null, p_service_count integer default null, p_good_count integer default null, p_assembly_count integer default null, p_family_count integer default null, p_variant_count integer default null, p_roll_count integer default null, p_offcut_count integer default null, p_bundle_count integer default null) returns text`** — GuidedProductSetupFlow:2394, GuidedCatalogSetupModel:718, GuidedStockSetupFlow:450. Self; type `standard` all three.
- `product_setup`: product ≥1 (clamp ≤10000), recipe ≥0. Body `{n} product row[s][ and {m} recipe row[s]] saved for estimating.`; title `PRODUCT SETUP COMPLETE`; deep_link `catalog_products`, `/catalog?segment=products` / `VIEW PRODUCTS`.
- `catalog_setup`: service/good/assembly ≥0, sum ≥1 else 22023. Body = nonzero parts of `{n} package[s]` · `{n} service[s]` · `{n} good[s]` joined ` · ` + ` saved for estimating.`; title `CATALOG SETUP COMPLETE`; products links.
- `stock_setup`: family/variant/roll/offcut/product/bundle ≥0, sum ≥1. Body = nonzero parts `{n} family|families` · `variant[s]` · `roll[s]` · `offcut[s]` · `product[s]` · `bundle[s]` joined ` · ` (no suffix); title `STOCK SYSTEM BUILT`; deep_link `catalog_stock`, `/catalog?segment=stock` / `VIEW STOCK`.
Unknown kind → 22023. dedupe `guided-setup:{kind}:` + md5(body). Returns created/noop.

### Group D — team management

**D1 `notify_role_assigned(p_member_id uuid) returns text`** — ManageTeamView:915. Other (the member).
Actor must hold `team.assign_roles` @ `all` else 42501 (lockout-RPC permission). Member row: company, active, `<> actor` (self-assign → `noop`). Role display from latest `user_roles` row join `roles` (fallback `users.role`): preset names map admin→`Admin`, owner→`Owner`, office→`Office`, operator→`Operator`, crew→`Crew`, unassigned→`Unassigned`; custom → `btrim(name)`. No recorded role at all → 22023 `'member role is not recorded'`. Body `You've been assigned the {display} role`, title `Role Updated`. type `role_assigned`, no links. dedupe `role-assigned:{member_id}:` + md5(display). Returns created/noop → client `sendToUser` push only when `created`.

**D2 `notify_team_invites_sent(p_emails text[] default '{}', p_phones text[] default '{}') returns text`** — ManageTeamView:1346. Self.
Matched contacts = input order (emails then phones, WITH ORDINALITY) where a `team_invitations` row exists: company = actor's, `invited_by = actor`, contact equality, `created_at >= now() - interval '10 minutes'`, `status <> 'cancelled'`. Zero matched → `noop`. n=1: body `Invitation sent to {first}.`; n>1: `{n} invitations sent to {first} + {n-1} more.` title `TEAM INVITES SENT`. type `team_invite_sent`, deep_link `team`, action_url **NULL** (was `ops://settings/organization/team`), label `VIEW TEAM`. dedupe `team-invites:` + md5(body). Returns created/noop.

### Group E — time off (request side)

**E1 `notify_time_off_booked(p_event_id uuid) returns text`** — UserEventSheet:1410.
Event: `type='time_off'`, company, not deleted, `status='approved'` else 22023 `'time off is not booked'`. Actor must hold `time_off.approve` @ `all` else 42501 (parity with `canBookTimeOffForOthers`). Recipient = `event.user_id` (validated). Range = `to_char('Mon FMDD')`, multi-day (UTC-date compare) joined ` – `. Self-booking (recipient = actor): body `Your time off for {range} is on the schedule.` else `{actor_name} booked you off for {range}.` title `Time Off Booked`. type `time_off_booked`, deep_link `schedule`. dedupe `time-off-booked:{event_id}`. Returns created/noop → client pushes `sendToUser` when target ≠ actor AND `created`.

**E2 `notify_time_off_requested(p_event_id uuid) returns jsonb`** — UserEventSheet:1463/1478/1503, TimeOffRequestSheet:425/440/461.
Event: `time_off`, company, not deleted, `status='pending'` else 22023 `'time off request is not pending'`. Requester = ACTOR. Target = `event.user_id` (validated; may = actor). Advisory lock per event. Idempotent per event via per-lane dedupe-key existence checks (any read state — transport-retry safe):
- Requester row (dedupe `time-off-request:{event}:requester`): title `Time Off Submitted`; body self → `Your request for {range} is pending review.`, on-behalf → `Submitted for {target_name}: {range} (pending review).`
- Target row when target ≠ actor (dedupe `…:target`): title `Time Off Submitted For You`, body `{actor_name} submitted a time-off request on your behalf for {range}.`
- Approvers = `users_with_permission(company,'time_off.approve','all')` minus actor minus target (dedupe `…:approver`): title `Time Off Request`, body self → `{actor_name} requested time off: {range}`, on-behalf → `{actor_name} requested time off for {target_name}: {range}`.
All type `time_off_requested`, deep_link `schedule`. Returns `{"approver_user_ids":[…created only…],"target_notified":bool}` → client `sendToUsers` push at exactly `approver_user_ids`.

### Group F — inventory

**F1 `notify_inventory_threshold_crossed(p_item_id uuid) returns text[]`** — QuantityAdjustmentSheet:404.
Item row: company, not deleted. Status server-computed (item-level thresholds only): critical when `critical_threshold IS NOT NULL AND quantity <= critical_threshold`; else warning when `warning_threshold IS NOT NULL AND quantity <= warning_threshold`; else return `'{}'` (honest recount, no exception). Recipients = `users_with_permission(company,'inventory.manage','all')` minus actor. Critical: title `Critical Stock Alert`, body `{name} is critically low ({trunc(qty)} remaining)`; warning: title `Low Stock Warning`, body `{name} is running low ({trunc(qty)} remaining)`. types `inventory_critical` / `inventory_warning`, deep_link `inventory`. dedupe `inventory-threshold:{item_id}:{status}`. Returns created ids → `sendToUsers`.

### Group G — photo storage (persistent, self)

**G1 `sync_photo_storage_limit_notification(p_photos_remaining integer, p_device_name text) returns text`** — PhotoPrefetchService:527.
Count clamped 1..1000000. Device sanitized: btrim → strip control chars → left 64 → empty fallback `this device` (self-display string on a self-only row; no cross-user authority). Advisory lock `photo-storage:{actor}:{md5(device)}`; at-most-one-unread per device key (`kept`). persistent TRUE. title `Photo storage limit reached on {device}`, body `{1 photo|N photos} couldn't download to {device}. On that device, open Settings → Photo Storage to raise the limit or free up space.` type `photo_storage_limit`, deep_link `photoStorage`, action_label `Manage Storage`, action_url NULL. dedupe `photo-storage-limit:` + md5(device). Returns created/kept. (Resolution lane unchanged: client `markAllAsReadByType`.)

### Group H — billable week (self)

**H1 `sync_billable_week_notification(p_project_count integer, p_amount numeric, p_week_start date) returns text`** — HomeBillableThisWeekNotificationDispatcher:66.
Actor must hold `finances.view` @ `all` else 42501 (client-gate parity). Count clamped 1..10000; amount `COALESCE ≥ 0` clamp ≤ 1e9; week_start within `now()-'14 days' .. now()+'7 days'` else 22023. Existence check ANY read state on dedupe `billable-week:{week_start}` → `kept` (parity with the old `hasNotification` read-or-unread check). Body: `{n} job[s] ready for billing` when amount=0 else `{n} job[s] / ${to_char(round(amount),'FM999,999,999,990')} billable`. title `BILLABLE THIS WEEK`. type `billable_this_week`, deep_link `billableThisWeek`, action_url **NULL** (was `ops://home/billable-this-week?...`), label `OPEN HOME`. Returns created/kept.

### Group I — cashflow forecast (company-wide, permission-derived)

**I1 `sync_forecast_dip_notification(p_lowest_balance numeric, p_week_start date) returns text[]`** — ForecastNotificationDispatcher:128.
Balance clamped |x| ≤ 1e12; week within `now() ± interval '2 years'` else 22023. Recipients = `users_with_permission(company,'finances.view','own')` **including actor** (shipped: a cash dip is a company condition, not an actor echo). persistent TRUE. Body `Balance drops to {currency} the week of {to_char(week,'Mon FMDD')}.` where currency = `[-]$` + `to_char(round(abs),'FM999,999,999,990')` (BooksFormat parity). Replace-unread per recipient under company advisory lock: identical-body unread row → kept; different-body unread row → mark read, insert fresh; none → insert. dedupe `forecast-dip:{company_id}` (open_dedupe holds one unread per user). type `forecast_dip`, deep_link `cashflow`, action `/books/cashflow` / `REVIEW FORECAST`. Returns created ids. No push lane. (Client anti-spam ledger `forecast_alerts` unchanged.)

**I2 `sync_forecast_cleared_notification() returns text[]`** — ForecastNotificationDispatcher:166.
Marks ALL the company's unread `forecast_dip` rows read (the persistent row must not outlive the condition — `NotificationReadPolicy` contract; the legacy client left them dangling). Inserts non-persistent `forecast_cleared` to `users_with_permission(company,'finances.view','own')`: title `// CASH DIP CLEARED`, body `Projected balance now stays positive across the forecast horizon.`, deep_link `cashflow`, action `/books/cashflow` / `VIEW FORECAST`, dedupe `forecast-cleared:{company_id}`. Returns created ids.

---

## Task 1 — Migration (Fable authors; single migration file)

1. Author `ios_legacy_notification_surface_rpcs` containing all 21 RPCs, header comment naming bug e302355c ADDENDUM + this doctrine, one `-- ---` section per RPC mirroring the 023254 file style.
2. Apply to prod via `mcp__plugin_supabase_supabase__apply_migration`.
3. Verify applied state **by object**: `pg_proc` rows for all 21 names + `has_function_privilege('authenticated', …, 'EXECUTE')` true and `service_role` false.
4. Mirror byte-exact into `ops-software-bible/migrations/<version>_ios_legacy_notification_surface_rpcs.sql`; md5 both sides vs `supabase_migrations.schema_migrations` (psql export channel per `schema_migrations` memory — the MCP result JSON mangles whitespace; write the local file from the SAME source string passed to apply_migration and verify md5 against the ledger).

## Task 2 — Behavioral verification on a synthetic prod tenant (Fable)

Recipe from P1-1: synthetic company + users (+ delete the `trial_attributions` row the company trigger creates on teardown); per-call `set_config('request.jwt.claims','{"sub":"<firebase_uid>"}',false)` + RPC in the SAME `execute_sql` call; temp-table capture for multi-statement assertions. Cover per RPC: recipient derivation, copy parity (assert exact body strings), dedupe/idempotent re-call, 42501 no-claims (wrong actor/company), 22023 invalid input/unrecorded state, returned-id truth. Tear the tenant down fully.

## Task 3 — iOS Wave A (1 opus agent): repository bindings + seam protocols

Extend `NotificationRepository` § "Narrow creation RPCs" with typed methods for all 21 RPCs (naming: `notifyTaskCompleted(taskId:) -> [String]`, `syncBillableWeek(projectCount:amount:weekStart:) -> String`, etc. — mirror existing style, `@discardableResult`, `struct Params: Encodable`). `NoteCreatedFanout`-style Decodable structs for A4 (`DependencyReadyFanout` = `[{task_id, user_ids}]` — decode as `[Entry]`), A8 (`ScheduleRunSummaryEntry`), E2 (`TimeOffRequestFanout`). Date params encode as `yyyy-MM-dd` strings. TDD: bindings are passthroughs (archetype: no direct binding tests), but compile + build-for-testing must pass before Wave B starts. Commit.

## Task 4 — iOS Wave B (4 parallel opus agents, exclusive file ownership)

Every agent: strict TDD (write failing suite → run (xcresult) → implement → green → commit), CRLF-preserving edits, spy seams per the archetype, `_ = try? await` for value-returning best-effort calls (never bare `try?` on `@discardableResult`), push lanes target returned ids only, transport failures contained (never surface into the save path). Delete each site's now-dead DTO construction; `CreateNotificationDTO`/`createNotification` itself stays (legacy shape, documented).

- **B1 — DataController (7 sites) + `OPSTests/DataControllerNotificationRPCTests.swift`.** Seam: one `protocol TaskLifecycleNotifying` (methods for A1–A5, A7, A8) + `extension NotificationRepository: TaskLifecycleNotifying {}` + `var taskLifecycleSyncer: TaskLifecycleNotifying` on DataController (default `.shared`). Rewire: 3987→A1 (push→returned ids), 4213→A2, 4321→A3, 4772→A4 (per-entry push, titles from local task rows), 4992→A5 with `p_user_ids = added ids` (push per returned id), 5765→A7 (dispatch Task awaits `syncEngine.pushPending()` first; per-spawn RPC; no push), 7974→A8 (push map from returned entries). Tests: in-memory store fixtures (retain containers; seed warm-up SyncOperation), spy pins verbatim ids/subset semantics/push-targeting/failure containment/zero-work short-circuits (e.g. no members → RPC still called for A1—server owns recipients—but empty `added` set for A5 skips).
- **B2 — Calendar sheets (7 sites) + `OPSTests/TimeOffRequestNotificationTests.swift`.** Extract the duplicated dispatch logic out of both sheets into `OPS/Services/TimeOffRequestNotificationDispatcher.swift` (enum + closure/protocol seams like HomeBillable's dispatcher): `dispatchBooked(eventId:targetIsSelf:)` → E1 + conditional `sendToUser` push on `created`; `dispatchRequested(eventId:)` → E2 + `sendToUsers` at returned approver ids. Both sheets call the dispatcher; delete their local DTO builders + `RecipientLookupService` usage + date-range formatters (server renders). Tests pin: event id verbatim, push only to returned approvers (empty → no push), booked push only when `created` && !self, failure containment.
- **B3 — Vinyl + catalog + inventory (7 sites) + `OPSTests/VinylCatalogNotificationRPCTests.swift`.** VinylOrderSheet→B1 RPC (keep railFailed branch), VinylBulkOrderWizardView→B2 (drop client date), VinylOffcutInventoryService→B3 (pass created stock-unit id + projectId; AGENT-VERIFY banking writes `ft` units), Guided flows ×3→C1 with per-kind counts (drop client bodies; keep `didPostCompletion` gates + `NotificationCenter` posts), QuantityAdjustmentSheet→F1 (delete client threshold copy + recipient lookup; push `sendToUsers` at returned ids; call after successful save regardless of local status — server recount decides). Seams: small `Notifying` protocols next to each caller (views: extract dispatch into testable helpers where a view owns the logic — VinylOrderSheet's dispatch is inline in the view: move it to a `VinylOrderNotificationDispatcher` enum with seam, same for the wizard summary).
- **B4 — Team/photo/home/forecast (7 sites) + `OPSTests/TeamAndFinanceNotificationRPCTests.swift`.** ManageTeamView 915→D1 (push `sendToUser` only on `created`), 1346→D2 (pass validEmails/validPhones), PhotoPrefetchService→G1 (keep 24h client cooldown; device name passthrough), HomeBillableThisWeekNotificationDispatcher→H1 (replace `hasRemoteNotification`+`createRemoteNotification` closures with one `syncRemote` closure; **update `HomeBillableThisWeekNotificationDispatcherTests` in place** — B4 owns that file), ForecastNotificationDispatcher 128→I1 / 166→I2 (drop `RecipientLookupService`; ledger upserts unchanged), ProjectFormSheet 2709→A6 / 3158→A5(p_user_ids: nil) (A5/A6 bindings from Wave A; push per returned id).

File-ownership matrix (no overlaps): B1 `OPS/Utilities/DataController.swift`; B2 both sheets + new dispatcher; B3 the three vinyl files + three guided files + QuantityAdjustmentSheet; B4 ManageTeamView, ProjectFormSheet, PhotoPrefetchService, HomeBillable dispatcher (+its test file), ForecastNotificationDispatcher. Each agent owns its new test file(s) exclusively.

## Task 5 — Verification (Fable)

Full notification-suite run in the worktree sim clone + `build-for-testing` + generic/iOS device build; counts from **xcresult only** (`xcrun xcresulttool`). Suites: the 4 new + the 8 prior (`AppStateNotificationRPCTests`, `ExpenseDecisionNotificationTests`, `HomeBillableThisWeekNotificationDispatcherTests`, `ImageSyncCrewNotificationTests`, `NoteCreatedNotificationTests`, `SharePhotoFinalizerNotificationTests`, `TimeOffDecisionNotificationTests`, `InboundThresholdAlertSyncTests`, `MeasurementNotificationTests`, `DimensionedPhotoSyncManagerTests`) — zero failures. Grep proves zero remaining legacy `createNotification(` call sites outside the repository file.

## Task 6 — Bible + commits (Fable)

04 § "iOS notification-surface RPCs": add the 21 contracts to the table (new dated subsection "Legacy call-site wave (2026-08-17)"). 07 §14: update the iOS creation-lane inventory. Mirror migration committed with them. iOS: merge worktree branch → local main (no push). Conventional commits; no AI attribution.

## Task 7 — Closeout (Fable)

Append the wave's closure block to bug e302355c `fix_notes` (row stays resolved). Update memory `project_ios_notification_rpc_rewire.md` (spawn ledger: this session = P1-3).
