-- =====================================================================
-- STAGED — NOT APPLIED. DO NOT RUN THIS FILE.
-- =====================================================================
--
-- Milestone owner visibility (MY LEADS day sheet, Task 8 addendum).
--
-- NOTHING MAY APPLY THIS WITHOUT JACKSON'S EXPLICIT APPROVAL. This file is
-- staged in the iOS repo as a reviewed artifact only. It is not a migration
-- and it is not on any migration path. To ship it, Jackson approves, then it
-- is copied VERBATIM into ops-web as a NEW timestamped migration file
-- (`ops-web/supabase/migrations/<YYYYMMDDHHMMSS>_milestone_owner_visibility.sql`)
-- and applied through the normal ops-web migration flow. Never apply this
-- from the iOS repo.
--
-- ---------------------------------------------------------------------
-- WHAT THIS DOES
-- ---------------------------------------------------------------------
-- When a DELEGATE advances a lead with the day-sheet milestone button, the
-- owners who can see the whole pipeline get one rail notification so the
-- move is visible without anyone asking for a status update.
--
--   trigger:    AFTER INSERT ON public.stage_transitions (for each row)
--   fires for:  new_lead -> qualifying   (CONTACTED)
--               qualifying -> quoting    (SITE VISITED)
--               quoting -> quoted        (QUOTE SENT)
--   actor:      only when the acting user's `pipeline.view` scope is
--               'assigned' (i.e. a delegate)
--   recipients: company users whose `pipeline.view` scope is 'all',
--               excluding the actor
--
-- ---------------------------------------------------------------------
-- WHY THESE GATES (each one exists to prevent a specific kind of noise)
-- ---------------------------------------------------------------------
-- 1. MILESTONE-ONLY BY CONSTRUCTION. The gate is three exact (from_stage,
--    to_stage) pairs — the same three the day-sheet milestone button can
--    produce (spec §4). There is no string matching on activity text, no
--    "was this the button or the menu?" flag to keep in sync. A correction
--    made through the stage menu (e.g. quoted -> qualifying, or a skip like
--    new_lead -> quoting) simply is not one of the three pairs and stays
--    silent. That is the point: owners hear about forward progress, not
--    about someone fixing a mistake.
-- 2. WON IS DELIBERATELY ABSENT. Conversion already has its own live
--    notification chain (`20260715181700_opportunity_conversion_notification_delivery.sql`).
--    Adding quoted -> won here would double-notify every win.
-- 3. DELEGATE ACTORS ONLY. An owner moving their own pipeline does not need
--    to be told they moved it, and other owners watching a peer work the
--    board is noise, not signal. Scope 'assigned' is exactly "this user only
--    sees leads assigned to them" — the delegate definition the day sheet is
--    built on. Resolved with the canonical
--    `private.effective_pipeline_scope_for_user(user, company, 'pipeline.view')`
--    installed by `20260715160500_lead_assignment_scoped_rls.sql` — the same
--    helper `private.current_user_scope_for` delegates to for every pipeline
--    permission. Not reinvented, and not read from `users.role`.
-- 4. ACTOR EXCLUDED FROM RECIPIENTS. Follows the `role_needed` fan-out
--    precedent in `20260715180500_notification_creation_hardening.sql`
--    (lines 1601-1628): `users_with_permission(company, permission, 'all')`
--    joined to `public.users`, filtered to same-company, active, not deleted,
--    `u.id <> actor`.
--
-- ---------------------------------------------------------------------
-- LOAD-BEARING ASSUMPTION (verified, not assumed)
-- ---------------------------------------------------------------------
-- The whole trigger hinges on `stage_transitions.transitioned_by` naming the
-- human who moved the lead. Verified against the current definition of
-- `public.move_opportunity_stage` — the RPC the day-sheet milestone button
-- calls through `OpportunityRepository.moveToStage` — which writes
-- `transitioned_by := case when auth.role() = 'service_role' then p_user_id
-- else coalesce(p_user_id, private.get_current_user_id()) end`. iOS passes the
-- acting user, so a delegate's milestone always carries their id.
--
-- The automated writers deliberately leave it NULL — the email-driven
-- transition in `20260713202000_atomic_email_stage_transitions.sql` and the
-- won-conversion trigger in `20260715160000_lead_assignment_foundation.sql`.
-- Those produce no notification here, which is the desired behaviour: a
-- machine moving a stage is not a person making progress. The NULL check is
-- therefore a real gate, not defensive padding.
--
-- ---------------------------------------------------------------------
-- ROW SHAPE (bible §14.3.1 contract)
-- ---------------------------------------------------------------------
--   type            'lead_stage_advanced'
--   title           '<VERB> — <NAME>'    e.g. 'QUOTE SENT — J. MARTINEZ'
--                   VERB is CONTACTED / SITE VISITED / QUOTE SENT, derived
--                   from the stage pair. <= 32 chars; only the NAME is
--                   truncated, on a character boundary, with a trailing '…'.
--   body            '<address> · <job line>' where present, <= 140.
--                   Falls back to 'BY <ACTOR NAME>' when the lead has
--                   neither — the title already names the lead, so the actor
--                   is the one new fact the owner doesn't have; the lead's
--                   display name remains the terminal fallback if the actor
--                   row is gone (§14.3.1 requires a concrete reference, and
--                   an empty body would violate the contract).
--   action_url      '/pipeline?opportunityId=<opportunity_id>'
--   action_label    'OPEN LEAD'
--   deep_link_type  'lead'
--   persistent      false
--   dedupe_key      'milestone:<stage_transition id>'
--
-- <NAME> mirrors the iOS `Opportunity.displayContactName` fallback chain
-- (contact_name -> title -> 'New lead'), so the notification names the lead
-- the same way every other OPS surface does. All copy fragments are
-- whitespace-collapsed: addresses are stored multi-line and a raw newline
-- renders as a broken notification.
--
-- ---------------------------------------------------------------------
-- NOTE: `lead_stage_advanced` IS A NEW NOTIFICATION TYPE — REGISTER IT
-- ---------------------------------------------------------------------
-- Per bible §14.3.1 ("When adding a new notification type"), the type must
-- be registered on both clients. None of this is a hard dependency — an
-- unregistered type falls back to the default bell icon on iOS and a generic
-- chip on web, and the deep link still resolves because `deep_link_type` is
-- 'lead' — but ship them together so the row does not look orphaned:
--
--   ops-web/src/lib/api/services/notification-service.ts
--     add 'lead_stage_advanced' to the NotificationType union
--   ops-web/src/lib/notifications/notification-meta.ts
--     add to NOTIF_TYPE_META, e.g.
--     lead_stage_advanced: { label: "LEAD", icon: "circle-check-big", tone: "ambient" }
--     (tone 'ambient': this is peripheral awareness, never an alarm — the
--      owner is being kept informed, not asked to do anything)
--   ops-ios OPS/Views/Notifications/NotificationListView.swift
--     add a `notificationIcon(for:)` case
--   ops-software-bible/07_SPECIALIZED_FEATURES.md §14.3.1
--     document the type in the table
--
-- iOS tap routing needs NO change: the row carries `deep_link_type = 'lead'`,
-- which `LeadNotificationRouteParser.leadRoutingValues` already matches, and
-- the opportunity id is recoverable from the action url. Adding
-- 'lead_stage_advanced' to `leadRoutingValues` (and to `routeByType` in both
-- AppDelegate.swift and NotificationManager.swift) is the same belt applied
-- to the assignment types — worth doing in the same ship, not required for
-- correctness.
--
-- ---------------------------------------------------------------------
-- SAFETY REVIEW
-- ---------------------------------------------------------------------
-- a. A NOTIFICATION FAILURE MUST NEVER LOSE A MILESTONE. The fan-out is
--    wrapped in an exception handler that warns and returns. A delegate
--    tapping SITE VISITED in the field is committing real work; rolling that
--    insert back because a notification could not be written would be the
--    worse failure by a wide margin. Reliability over features.
-- b. Idempotent. `create_notification_if_new` inserts ON CONFLICT DO NOTHING
--    against `idx_notifications_unread_dedup`, which is unique on
--    (user_id, company_id, type, coalesce(dedupe_key, title)) where unread
--    and unresolved. The dedupe key is per-TRANSITION, so each recipient
--    gets exactly one row per milestone and a replayed trigger adds none.
--    Distinct recipients are distinct user_ids and never collide with each
--    other — the fan-out is not collapsed by the index.
-- c. Read-only against opportunities; writes only to public.notifications.
--    No change to stage_transitions, opportunities, or any existing trigger.
-- d. SECURITY DEFINER with a pinned search_path, in the `private` schema,
--    with EXECUTE revoked — matching the trigger-function convention
--    established by `20260715160700_lead_assignment_child_scope.sql`.
-- e. Soft-deleted or cross-company leads produce no notification.
--
-- =====================================================================

begin;

do $do$
begin
  if to_regclass('public.stage_transitions') is null
     or to_regclass('public.opportunities') is null
     or to_regclass('public.notifications') is null
     or to_regprocedure(
          'private.effective_pipeline_scope_for_user(uuid,uuid,text)'
        ) is null
     or to_regprocedure(
          'public.users_with_permission(uuid,text,text)'
        ) is null
     or to_regprocedure(
          'public.create_notification_if_new(text,text,text,text,text,boolean,text,text,text,text,text)'
        ) is null
  then
    raise exception 'milestone owner visibility prerequisites are missing';
  end if;
end
$do$;

create or replace function private.notify_delegate_milestone_advance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $function$
declare
  v_verb text;
  v_actor_scope text;
  v_opportunity record;
  v_recipient record;
  v_lead_name text;
  v_actor_name text;
  v_address text;
  v_job_line text;
  v_title text;
  v_title_prefix text;
  v_title_budget integer;
  v_body text;
  v_dedupe_key text;
  v_action_url text;
begin
  -- (1) Milestone gate: exactly the three pairs the day-sheet button emits.
  -- Anything else — corrections, skips, WON, lost, discarded — falls through
  -- silently. No string matching, nothing to keep in sync with the client.
  v_verb := case
    when new.from_stage = 'new_lead'   and new.to_stage = 'qualifying' then 'CONTACTED'
    when new.from_stage = 'qualifying' and new.to_stage = 'quoting'    then 'SITE VISITED'
    when new.from_stage = 'quoting'    and new.to_stage = 'quoted'     then 'QUOTE SENT'
    else null
  end;
  if v_verb is null then
    return new;
  end if;

  if new.transitioned_by is null or new.company_id is null then
    return new;
  end if;

  -- (2) Delegate gate: only a user scoped to their own assigned leads.
  v_actor_scope := private.effective_pipeline_scope_for_user(
    new.transitioned_by,
    new.company_id,
    'pipeline.view'
  );
  if v_actor_scope is distinct from 'assigned' then
    return new;
  end if;

  select
    o.contact_name,
    o.title,
    o.address
    into v_opportunity
    from public.opportunities o
   where o.id = new.opportunity_id
     and o.company_id = new.company_id
     and o.deleted_at is null;
  if not found then
    return new;
  end if;

  -- (3) Copy. Every fragment is whitespace-collapsed first: addresses are
  -- stored multi-line and a raw newline renders as a broken notification.
  v_lead_name := coalesce(
    nullif(btrim(regexp_replace(
      coalesce(v_opportunity.contact_name, ''), '\s+', ' ', 'g'
    )), ''),
    nullif(btrim(regexp_replace(
      coalesce(v_opportunity.title, ''), '\s+', ' ', 'g'
    )), ''),
    'New lead'
  );

  -- '<VERB> — <NAME>' capped at 32 characters. Only the name is cut, and a
  -- cut name ends in '…' so a truncated lead never reads as a real name.
  v_title_prefix := v_verb || ' — ';
  if char_length(v_title_prefix || upper(v_lead_name)) <= 32 then
    v_title := v_title_prefix || upper(v_lead_name);
  else
    v_title_budget := 32 - char_length(v_title_prefix) - 1;
    v_title :=
      v_title_prefix
      || rtrim(left(upper(v_lead_name), v_title_budget))
      || '…';
  end if;

  -- '<address> · <job line>', capped at 140. The separator only appears
  -- between two present halves. When the lead carries neither, the body
  -- names WHO advanced it — the title already names the lead, so the actor
  -- is the one new fact the owner doesn't have (lead name = terminal
  -- fallback if the actor row is gone).
  select nullif(btrim(regexp_replace(
           coalesce(u.first_name, '') || ' ' || coalesce(u.last_name, ''),
           '\s+', ' ', 'g'
         )), '')
    into v_actor_name
    from public.users u
   where u.id = new.transitioned_by;
  v_address := nullif(btrim(regexp_replace(
    coalesce(v_opportunity.address, ''), '\s+', ' ', 'g'
  )), '');
  v_job_line := nullif(btrim(regexp_replace(
    coalesce(v_opportunity.title, ''), '\s+', ' ', 'g'
  )), '');
  v_body := left(
    case
      when v_address is not null and v_job_line is not null
        then v_address || ' · ' || v_job_line
      when v_address is not null then v_address
      when v_job_line is not null then v_job_line
      else 'BY ' || upper(coalesce(v_actor_name, v_lead_name))
    end,
    140
  );

  v_action_url := '/pipeline?opportunityId=' || new.opportunity_id::text;
  v_dedupe_key := 'milestone:' || new.id::text;

  -- (4) Fan out to full-pipeline owners, minus the actor. Isolated: a
  -- notification failure must never roll back the delegate's milestone.
  begin
    for v_recipient in
      select u.id
        from public.users_with_permission(
               new.company_id,
               'pipeline.view',
               'all'
             ) permitted(user_id)
        join public.users u
          on u.id = permitted.user_id
       where u.company_id = new.company_id
         and u.id <> new.transitioned_by
         and u.deleted_at is null
         and coalesce(u.is_active, false) = true
    loop
      perform public.create_notification_if_new(
        v_recipient.id::text,
        new.company_id::text,
        'lead_stage_advanced',
        v_title,
        v_body,
        false,
        v_action_url,
        'OPEN LEAD',
        null,
        'lead',
        v_dedupe_key
      );
    end loop;
  exception
    when others then
      raise warning
        'milestone owner visibility notification failed for transition %: %',
        new.id,
        sqlerrm;
  end;

  return new;
end;
$function$;

revoke all on function private.notify_delegate_milestone_advance()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_stage_transitions_notify_delegate_milestone
  on public.stage_transitions;
create trigger trg_stage_transitions_notify_delegate_milestone
after insert on public.stage_transitions
for each row execute function private.notify_delegate_milestone_advance();

comment on function private.notify_delegate_milestone_advance() is
  'Notifies full-pipeline owners when a delegate advances a lead through one of the three day-sheet milestone stage pairs. Silent for owner actors, corrections, skips, and WON (which has its own conversion delivery chain).';

commit;
