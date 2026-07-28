-- =====================================================================
-- STAGED — NOT APPLIED. DO NOT RUN THIS FILE.
-- =====================================================================
--
-- Lead-assignment notification copy alignment (MY LEADS day sheet, Task 8).
--
-- NOTHING MAY APPLY THIS WITHOUT JACKSON'S EXPLICIT APPROVAL. This file is
-- staged in the iOS repo as a reviewed artifact only. It is not a migration
-- and it is not on any migration path. To ship it, Jackson approves, then it
-- is copied VERBATIM into ops-web as a NEW timestamped migration file
-- (`ops-web/supabase/migrations/<YYYYMMDDHHMMSS>_lead_assignment_copy_alignment.sql`)
-- and applied through the normal ops-web migration flow. Never edit the
-- already-applied `20260715161600_lead_assignment_delivery_worker.sql` in
-- place, and never apply this from the iOS repo.
--
-- ---------------------------------------------------------------------
-- WHAT THIS CHANGES
-- ---------------------------------------------------------------------
-- Exactly two strings on the rail notification row that
-- `public.claim_opportunity_assignment_deliveries` materializes for the new
-- assignee. Nothing else. No signature change, no new joins, no change to
-- staleness revalidation, dedupe, suppression, preference resolution,
-- leasing, retry, or the returned result set.
--
--   notifications.title
--     current:  'Lead assigned'
--     target:   'NEW LEAD — <NAME>'          (<NAME> uppercased, <= 32 total)
--
--   notifications.body
--     current:  '<opportunity.title> is now assigned to you.'
--     target:   '<address> · <job line>'      (<= 140)
--
-- Both are assembled from whitespace-collapsed fragments, because addresses
-- are stored multi-line and a raw newline renders as a broken notification.
--
-- WHY
-- MY LEADS day-sheet spec §8 locks assignment copy as
-- `NEW LEAD — <NAME>` / `<address> · <job line>`
-- (docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §5 + §8,
-- restated in docs/plans/2026-07-27-my-leads-day-sheet.md Task 8). The
-- delivery pipeline shipped 2026-07-17 ahead of that spec and still writes
-- the pre-spec strings. `action_label` is already 'OPEN LEAD' and already
-- conforms — it is untouched.
--
-- <NAME> mirrors the iOS `Opportunity.displayContactName` fallback chain
-- (contact_name -> title -> 'New lead') so the push, the web rail, and the
-- day-sheet row all name the lead identically.
--
-- ---------------------------------------------------------------------
-- CAPS
-- ---------------------------------------------------------------------
-- The 32-char title / 140-char body caps are the OPS notification contract
-- in `ops-software-bible/07_SPECIALIZED_FEATURES.md` §14.3.1. They are a
-- convention, not a DB CHECK constraint (none exists on public.notifications
-- in the ops-web migration set), so this function enforces them in code:
-- the title truncates the NAME portion only, on a character boundary, with a
-- trailing '…' when it had to cut; the body keeps the existing `left(…, 140)`.
-- Note '—' and '·' are single CHARACTERS but multi-byte — every cap here is
-- computed with char_length/left (character semantics), never octet_length.
--
-- ---------------------------------------------------------------------
-- SAFETY REVIEW
-- ---------------------------------------------------------------------
-- 1. `complete_opportunity_assignment_delivery` re-verifies the materialized
--    row before completing a lease. It matches on id, user_id, company_id,
--    type, persistent, action_url, deep_link_type and dedupe_key — it does
--    NOT inspect title or body. Changing copy therefore cannot break the
--    delivery proof, and no companion change to that function is needed.
-- 2. The returned `lead_title` column is left computing EXACTLY as shipped
--    (`coalesce(nullif(btrim(o.title), ''), 'New lead')`). It is the value the
--    ops-web TypeScript worker feeds to the OneSignal push, so touching it
--    would silently change push copy. The new rail strings are built in new
--    local variables instead.
-- 3. Two columns are added to the claim SELECT list (`o.contact_name`,
--    `o.address`). That is the only non-string edit in the file and it is
--    required to build the locked copy. Same row, same joins, same `for
--    update of d, o skip locked`, same ordering, same limit — no behavioral
--    effect.
-- 4. Rows already in the rail keep their old copy. This is forward-only; no
--    backfill is included, and none should be added (rewriting delivered
--    notification history would be dishonest to the operator who read it).
-- 5. Out of scope: `lead_assignment_required` ('Lead needs an owner' /
--    'Assign <title>'), which is materialized by the separate unassigned-lead
--    worker in `20260723214524_company_mailbox_intake_owner.sql`. Spec §8 does
--    not lock that copy. Deliberately unchanged, not overlooked.
--
-- ---------------------------------------------------------------------
-- NOTE: COMPANION ops-web TYPESCRIPT CHANGES — REQUIRED IN THE SAME SHIP
-- ---------------------------------------------------------------------
-- The OneSignal PUSH title/body are NOT built in SQL. They are hardcoded in
-- TypeScript and are not changed by this file. Shipping this migration alone
-- aligns the in-app/web RAIL copy while the PUSH still reads the old strings.
-- Both must land together.
--
--   FILE: ops-web/src/lib/api/services/lead-assignment-delivery-service.ts
--
--   (a) push title — inside `LeadAssignmentDeliveryService.processBatch`,
--       the `deps.sendPush({ ... })` call:
--         current:  title: "Lead assigned",
--         target:   title: `NEW LEAD — ${<uppercased lead name>}`   (<= 32)
--
--   (b) push body — same call site:
--         current:  body: buildLeadAssignmentPushBody(claim.lead_title),
--         target:   body: `${address} · ${jobLine}`
--
--   (c) `buildLeadAssignmentPushBody` and its two module constants:
--         current:  const MAX_PUSH_BODY_LENGTH = 50;
--                   const PUSH_BODY_PREFIX = "Open ";
--                   -> produces "Open <lead title>", ellipsised at 50 chars
--         target:   the "Open " prefix is retired; the helper formats
--                   "<address> · <job line>" with the same graceful
--                   truncation, and the title helper enforces the 32-char cap
--
--   (d) tests that pin the current strings and must move with them:
--         ops-web/tests/unit/notifications/lead-assignment-delivery-service.test.ts
--
--   BLOCKER — READ BEFORE SCHEDULING THE TS WORK.
--   The claim RPC returns only `lead_title`. To build the target push strings
--   the worker also needs the lead NAME, ADDRESS and JOB LINE. Postgres
--   rejects a `create or replace function` that alters a `returns table`
--   signature ("cannot change return type of existing function"), so adding
--   those columns requires `drop function` + `create` in one migration,
--   deployed in lockstep with the TypeScript (the old TS would break against
--   a widened row, and the new TS breaks against the old row). This file
--   deliberately does NOT widen the signature: it is copy-only and drop-in
--   safe against the currently deployed worker, so it can ship on its own.
--   Sequence the signature widening + TS change as its own coordinated
--   deploy; do not fold it in here.
--
-- =====================================================================

begin;

-- Refuse to run anywhere the shipped worker is not already present. This is a
-- REPLACE of a live function, never a first definition.
do $do$
begin
  if to_regprocedure(
       'public.claim_opportunity_assignment_deliveries(uuid,integer,integer)'
     ) is null
  then
    raise exception
      'lead assignment delivery worker is not installed; apply 20260715161600 first';
  end if;
end
$do$;

create or replace function public.claim_opportunity_assignment_deliveries(
  p_worker_id uuid,
  p_limit integer default 25,
  p_lease_seconds integer default 180
) returns table (
  delivery_id uuid,
  delivery_lease_token uuid,
  assignment_event_id uuid,
  company_id uuid,
  opportunity_id uuid,
  recipient_user_id uuid,
  notification_id uuid,
  lead_title text,
  should_push boolean,
  requires_notification boolean,
  disposition text
)
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $function$
declare
  v_limit integer := greatest(0, least(coalesce(p_limit, 25), 100));
  v_lease_seconds integer := greatest(30, least(coalesce(p_lease_seconds, 180), 900));
  v_row record;
  v_notification_id uuid;
  v_lease_token uuid;
  v_dedupe_key text;
  v_lead_title text;
  v_notification_body text;
  v_pref_push jsonb;
  v_should_push boolean;
  v_disposition text;
  -- Copy-alignment locals (spec §8). Separate from v_lead_title, which stays
  -- the returned push value and must not shift.
  v_lead_name text;
  v_notification_title text;
  v_title_prefix constant text := 'NEW LEAD — ';
  v_title_budget integer;
  v_address text;
  v_job_line text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise insufficient_privilege using
      message = 'lead assignment delivery claims require service role';
  end if;
  if p_worker_id is null then
    raise exception 'lead assignment delivery worker id is required';
  end if;
  if v_limit = 0 then
    return;
  end if;

  for v_row in
    select
      d.*,
      o.title as opportunity_title,
      -- Added for spec §8 copy only; no effect on row selection or locking.
      o.contact_name as opportunity_contact_name,
      o.address as opportunity_address,
      o.assigned_to as current_assignee_id,
      o.assignment_version as current_assignment_version,
      o.deleted_at as opportunity_deleted_at,
      o.archived_at as opportunity_archived_at,
      e.new_assignee_id,
      e.assignment_version as event_assignment_version,
      e.company_id as event_company_id,
      e.opportunity_id as event_opportunity_id,
      u.company_id as user_company_id,
      u.deleted_at as user_deleted_at,
      u.is_active as user_is_active,
      np.push_enabled as preference_push_enabled,
      np.channel_preferences
    from public.opportunity_assignment_deliveries d
    join public.opportunities o
      on o.id = d.opportunity_id
    join public.opportunity_assignment_events e
      on e.id = d.assignment_event_id
    join public.users u
      on u.id = d.recipient_user_id
    left join public.notification_preferences np
      on np.user_id = d.recipient_user_id
     and np.company_id = d.company_id
    where (
      (
        d.state in ('pending', 'failed')
        and d.available_at <= now()
        and d.attempts < d.max_attempts
      )
      or (d.state = 'processing' and d.lease_expires_at <= now())
    )
    order by
      case
        when d.state = 'processing' then d.lease_expires_at
        else d.available_at
      end,
      d.created_at,
      d.id
    for update of d, o skip locked
    limit v_limit
  loop
    v_disposition := null;

    -- A crashed worker that exhausted its final lease is terminal, but still
    -- returned so the cron reports the condition instead of hiding it.
    if v_row.state = 'processing'
       and v_row.attempts >= v_row.max_attempts
    then
      update public.opportunity_assignment_deliveries d
         set state = 'failed',
             disposition = 'terminal_failure',
             terminal_at = now(),
             claimed_at = null,
             claimed_by = null,
             lease_token = null,
             lease_expires_at = null,
             available_at = 'infinity'::timestamptz,
             last_error = coalesce(
               d.last_error,
               'lease expired after maximum attempts'
             ),
             updated_at = now()
       where d.id = v_row.id;

      return query values (
        v_row.id,
        null::uuid,
        v_row.assignment_event_id,
        v_row.company_id,
        v_row.opportunity_id,
        v_row.recipient_user_id,
        v_row.notification_id,
        coalesce(nullif(btrim(v_row.opportunity_title), ''), 'New lead'),
        false,
        false,
        'terminal_failure'::text
      );
      continue;
    end if;

    if v_row.notify = false then
      v_disposition := 'silent';
    elsif v_row.access_after = false
       or v_row.company_id is distinct from v_row.event_company_id
       or v_row.opportunity_id is distinct from v_row.event_opportunity_id
       or v_row.assignment_version is distinct from v_row.event_assignment_version
       or v_row.assignment_version is distinct from v_row.current_assignment_version
       or v_row.new_assignee_id is distinct from v_row.recipient_user_id
       or v_row.current_assignee_id is distinct from v_row.recipient_user_id
       or v_row.opportunity_deleted_at is not null
       or v_row.opportunity_archived_at is not null
    then
      v_disposition := 'stale';
    elsif v_row.user_company_id is distinct from v_row.company_id
       or v_row.user_deleted_at is not null
       or not coalesce(v_row.user_is_active, false)
       or not private.user_can_view_opportunity(
         v_row.recipient_user_id,
         v_row.opportunity_id
       )
    then
      v_disposition := 'inaccessible';
    end if;

    if v_disposition is not null then
      if v_disposition in ('stale', 'inaccessible')
         and v_row.notification_id is not null
      then
        update public.notifications n
           set is_read = true,
               resolved_at = now(),
               resolution_reason = 'assignment_delivery_suppressed'
         where n.id = v_row.notification_id
           and n.dedupe_key =
             'lead-assignment-delivery:' || v_row.id::text;
      end if;

      update public.opportunity_assignment_deliveries d
         set state = 'delivered',
             attempts = d.attempts + 1,
             claimed_at = null,
             claimed_by = null,
             lease_token = null,
             lease_expires_at = null,
             delivered_at = now(),
             disposition = v_disposition,
             push_state = 'suppressed',
             terminal_at = null,
             last_error = case v_disposition
               when 'silent' then null
               when 'stale' then 'suppressed stale assignment delivery'
               else 'suppressed delivery for inaccessible recipient'
             end,
             updated_at = now()
       where d.id = v_row.id;

      return query values (
        v_row.id,
        null::uuid,
        v_row.assignment_event_id,
        v_row.company_id,
        v_row.opportunity_id,
        v_row.recipient_user_id,
        v_row.notification_id,
        coalesce(nullif(btrim(v_row.opportunity_title), ''), 'New lead'),
        false,
        false,
        v_disposition
      );
      continue;
    end if;

    -- Returned to the caller and used by the ops-web worker to build the push.
    -- UNCHANGED from the shipped definition — see SAFETY REVIEW note 2.
    v_lead_title := coalesce(
      nullif(btrim(v_row.opportunity_title), ''),
      'New lead'
    );

    -- ---- spec §8 rail copy -------------------------------------------------
    -- Every copy fragment is whitespace-collapsed first. Addresses are stored
    -- multi-line ('123 Main St\nVancouver, BC'), and a raw newline inside a
    -- notification title or body renders as a broken line on both rails and in
    -- the push. This mirrors the normalization the ops-web push builder already
    -- applies (`leadTitle.replace(/\s+/g, " ").trim()`).
    --
    -- <NAME>: mirrors iOS Opportunity.displayContactName
    -- (contact_name -> title -> 'New lead').
    v_lead_name := upper(
      coalesce(
        nullif(btrim(regexp_replace(
          coalesce(v_row.opportunity_contact_name, ''), '\s+', ' ', 'g'
        )), ''),
        nullif(btrim(regexp_replace(
          coalesce(v_row.opportunity_title, ''), '\s+', ' ', 'g'
        )), ''),
        'New lead'
      )
    );

    -- 'NEW LEAD — <NAME>' capped at 32 characters. Only the name is cut, and
    -- a cut name ends in '…' so a truncated lead never reads as a real name.
    if char_length(v_title_prefix || v_lead_name) <= 32 then
      v_notification_title := v_title_prefix || v_lead_name;
    else
      v_title_budget := 32 - char_length(v_title_prefix) - 1;
      v_notification_title :=
        v_title_prefix
        || rtrim(left(v_lead_name, v_title_budget))
        || '…';
    end if;

    -- '<address> · <job line>', capped at 140. Either half may be missing:
    -- the separator only appears between two present halves. When the lead
    -- carries neither an address nor a job line the body falls back to the
    -- previously shipped sentence, which still names a concrete entity as
    -- §14.3.1 requires — an empty body would be a contract violation.
    v_address := nullif(btrim(regexp_replace(
      coalesce(v_row.opportunity_address, ''), '\s+', ' ', 'g'
    )), '');
    v_job_line := nullif(btrim(regexp_replace(
      coalesce(v_row.opportunity_title, ''), '\s+', ' ', 'g'
    )), '');
    v_notification_body := left(
      case
        when v_address is not null and v_job_line is not null
          then v_address || ' · ' || v_job_line
        when v_address is not null then v_address
        when v_job_line is not null then v_job_line
        else v_lead_title || ' is now assigned to you.'
      end,
      140
    );
    -- ------------------------------------------------------------------------

    v_dedupe_key := 'lead-assignment-delivery:' || v_row.id::text;
    v_notification_id := null;

    insert into public.notifications (
      user_id,
      company_id,
      type,
      title,
      body,
      is_read,
      persistent,
      action_url,
      action_label,
      project_id,
      deep_link_type,
      dedupe_key
    ) values (
      v_row.recipient_user_id::text,
      v_row.company_id::text,
      'lead_assigned',
      v_notification_title,
      v_notification_body,
      false,
      false,
      '/pipeline?opportunityId=' || v_row.opportunity_id::text,
      'OPEN LEAD',
      null,
      'lead',
      v_dedupe_key
    )
    on conflict do nothing
    returning id into v_notification_id;

    if v_notification_id is null then
      select n.id
        into v_notification_id
        from public.notifications n
       where n.dedupe_key = v_dedupe_key
         and n.user_id = v_row.recipient_user_id::text
         and n.company_id = v_row.company_id::text
         and n.type = 'lead_assigned';
    end if;

    if v_notification_id is null then
      raise exception 'lead assignment notification could not be materialized';
    end if;

    v_pref_push := v_row.channel_preferences #> '{lead_assignments,push}';
    v_should_push := coalesce(v_row.preference_push_enabled, true)
      and case
        when jsonb_typeof(v_pref_push) = 'boolean'
          then (v_pref_push #>> '{}')::boolean
        else true
      end;

    v_lease_token := gen_random_uuid();
    update public.opportunity_assignment_deliveries d
       set state = 'processing',
           attempts = d.attempts + 1,
           claimed_at = now(),
           claimed_by = p_worker_id::text,
           lease_token = v_lease_token,
           lease_expires_at = now() + make_interval(secs => v_lease_seconds),
           notification_id = v_notification_id,
           disposition = null,
           push_state = 'pending',
           terminal_at = null,
           last_error = null,
           updated_at = now()
     where d.id = v_row.id;

    return query values (
      v_row.id,
      v_lease_token,
      v_row.assignment_event_id,
      v_row.company_id,
      v_row.opportunity_id,
      v_row.recipient_user_id,
      v_notification_id,
      v_lead_title,
      v_should_push,
      true,
      'notified'::text
    );
  end loop;
end;
$function$;

-- `create or replace` preserves grants and comments; these are restated so the
-- file is self-contained and the privilege surface is provable from one read.
revoke all on function public.claim_opportunity_assignment_deliveries(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_opportunity_assignment_deliveries(uuid, integer, integer)
  to service_role;

comment on function public.claim_opportunity_assignment_deliveries(uuid, integer, integer) is
  'Service-only SKIP LOCKED lead-assignment delivery claim. Silently consumes old-assignee, stale, and inaccessible rows; materializes one durable rail notification before returning push work.';

commit;
