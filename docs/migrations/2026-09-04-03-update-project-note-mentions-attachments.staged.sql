-- =====================================================================
-- STAGED — NOT APPLIED. Bug sweep 2026-09-04, cluster PHOTOS & MEDIA.
-- Related bug: f5f57917 ("When editing a comment, user is not able to remove
-- the attached photo").
--
-- NOTHING MAY APPLY THIS WITHOUT EXPLICIT APPROVAL. This file is staged in
-- the iOS repo as a reviewed artifact only. It is not on any migration path.
-- To ship it: copy VERBATIM into ops-web as a NEW timestamped migration
-- (`ops-web/supabase/migrations/<YYYYMMDDHHMMSS>_project_note_mentions_attachments.sql`)
-- and apply through the normal ops-web migration flow.
-- =====================================================================
--
-- ---------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------
-- Editing a note can change its text and its mentions, and nothing else. The
-- whole chain — ActivityEntryView -> ProjectNotesViewModel ->
-- DataController.updateProjectNoteContent -> SyncEngine
-- .recordProjectNoteMentionEdit -> ProjectNoteRepository.updateMentions ->
-- update_project_note_mentions — carries no media field, and the RPC's only
-- write is `set content = …, mentioned_user_ids = …, updated_at = …`.
--
-- A user who wants to keep the words and drop the photo therefore has no path
-- at all. The only removal route is Delete, which destroys the whole note.
--
-- This migration adds the media half of the edit contract.
--
-- ---------------------------------------------------------------------
-- SCOPE: DETACH-ONLY, `attachments` ONLY
-- ---------------------------------------------------------------------
-- Removing a photo removes it FROM THE NOTE. The photo stays in the project
-- gallery, where it is site evidence. This is deliberate:
--   * the note-delete flow already owns the "…and from the gallery?" question;
--   * a second destructive dialog inside an inline edit is exactly the noise
--     the design rules forbid;
--   * `project_photos` grants anon/authenticated only INSERT, SELECT — no
--     UPDATE — so ANY gallery-removal path from iOS 42501s today. That is bug
--     1154fe67, still open and out of this cluster's scope. Detach-only is the
--     design that can actually ship right now, and it does not depend on it.
--
-- `photo_url` is untouched. A note whose `photo_url` is set was posted from the
-- photo viewer's comment composer — the photo is the comment's SUBJECT, not an
-- attachment; detaching it would orphan the sentence. Those notes keep today's
-- behaviour and Delete remains their route. The client enforces the same rule.
--
-- ---------------------------------------------------------------------
-- WHAT THIS DOES
-- ---------------------------------------------------------------------
-- 1. Adds `p_attachments jsonb default null` as a FIFTH parameter.
--    NULL means "leave attachments unchanged", so the existing 4-argument
--    named call from every shipped iOS build still resolves and still behaves
--    byte-identically.
-- 2. Extends the replay equality test with the attachment set, so a reused
--    event id carrying a DIFFERENT attachment set still raises 22023 instead
--    of silently returning the old event.
-- 3. Validates the supplied shape — a JSON array of strings — with 22023.
-- 4. Refuses to strand an empty note (no text, no attachments, no photo_url).
--    Server-authoritative; the client guard mirrors it.
-- 5. Records provenance on the immutable event (`requested_attachments`,
--    `attachments_snapshot`) and echoes `attachments` in both returns.
--
-- Everything else is UNCHANGED and carried over byte-for-byte from the live
-- definition captured 2026-09-04 via
--   select pg_get_functiondef(
--     'public.update_project_note_mentions(uuid,text,text[],uuid)'::regprocedure);
-- — in particular the author-only gate, the `event_kind is not null` gate, the
-- `for update` serialization, the mention-id regex validation, the actor and
-- project `for share` checks, and the added-recipient computation.
--
-- ---------------------------------------------------------------------
-- WHY DROP AND CREATE, NOT `create or replace`
-- ---------------------------------------------------------------------
-- `create or replace` with an EXTRA defaulted parameter creates a SECOND
-- function rather than replacing the first, and the existing 4-argument named
-- call then becomes AMBIGUOUS (PostgREST error) for every shipped client. The
-- drop and the create must happen in the SAME transaction.
--
-- A drop does NOT carry grants over. The live ACL captured 2026-09-04 is
--   postgres=X/postgres | anon=X/postgres | authenticated=X/postgres
-- i.e. EXECUTE was revoked from PUBLIC and granted to anon + authenticated.
-- The re-grant below reproduces that exactly. Verified: nothing else in the
-- database depends on this function (pg_depend + prosrc scan both empty).
--
-- ---------------------------------------------------------------------
-- VERIFY AFTER APPLYING
-- ---------------------------------------------------------------------
--   select oid::regprocedure::text from pg_proc
--   where proname = 'update_project_note_mentions';
--   -- EXPECT exactly ONE row, the 5-arg signature
--
--   select coalesce(array_to_string(proacl::text[], ' | '), 'NULL(default)')
--   from pg_proc where proname = 'update_project_note_mentions';
--   -- EXPECT postgres=X/postgres | anon=X/postgres | authenticated=X/postgres
--
-- Then, from the app on a build that predates the iOS change: edit a note's
-- TEXT ONLY and confirm it still saves. That proves the defaulted parameter
-- did not break shipped clients.
--
-- ---------------------------------------------------------------------

begin;

-- Immutable-event columns for the media half of the edit. Additive and
-- nullable: existing rows keep NULL, which reads as "this edit predates
-- attachment provenance" and never as "the edit cleared the attachments".
--
-- These come FIRST: the function body declares
-- `v_replay public.project_note_mention_events%rowtype` and reads
-- `v_replay.requested_attachments`, so the columns must exist before the
-- function is created.
alter table public.project_note_mention_events
  add column if not exists requested_attachments jsonb,
  add column if not exists attachments_snapshot  jsonb;

drop function if exists public.update_project_note_mentions(uuid, text, text[], uuid);

create function public.update_project_note_mentions(
  p_note_id uuid,
  p_content text,
  p_mentioned_user_ids text[],
  p_event_id uuid,
  p_attachments jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_id uuid := private.get_current_user_id();
  v_company_id uuid := private.get_user_company_id();
  v_existing public.project_notes%rowtype;
  v_replay public.project_note_mention_events%rowtype;
  v_actor_name text;
  v_project_title text;
  v_effective_mentioned_user_ids text[] := '{}'::text[];
  v_added_recipient_ids text[] := '{}'::text[];
  v_updated_at timestamptz;
begin
  if p_note_id is null or p_event_id is null or p_content is null then
    raise exception 'invalid project note mention edit'
      using errcode = '22023';
  end if;
  if p_mentioned_user_ids is null then
    raise exception 'explicit mention list is required'
      using errcode = '22023';
  end if;
  if array_position(p_mentioned_user_ids, null) is not null then
    raise exception 'requested mention user id is invalid'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_mentioned_user_ids) requested(user_id)
    where requested.user_id !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception 'requested mention user id is invalid'
      using errcode = '22023';
  end if;

  -- Media half of the edit contract. NULL means "leave attachments alone",
  -- which is what every pre-change client sends by omitting the argument.
  if p_attachments is not null then
    if jsonb_typeof(p_attachments) <> 'array' then
      raise exception 'note attachments must be a json array'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_attachments) element
      where jsonb_typeof(element) <> 'string'
    ) then
      raise exception 'note attachments must be an array of strings'
        using errcode = '22023';
    end if;
  end if;

  select concat_ws(
    ' ',
    nullif(btrim(actor.first_name), ''),
    nullif(btrim(actor.last_name), '')
  )
    into v_actor_name
  from public.users actor
  where actor.id = v_actor_id
    and actor.company_id = v_company_id
    and actor.is_active
    and actor.deleted_at is null
  for share;

  if not found then
    raise exception 'project note mention edit actor is unavailable'
      using errcode = '42501';
  end if;
  if v_actor_id is null or v_company_id is null then
    raise exception 'project note mention edit actor is unavailable'
      using errcode = '42501';
  end if;
  v_actor_name := coalesce(nullif(btrim(v_actor_name), ''), 'A team member');

  -- Every edit of one note serializes here. A replay waits for the first call,
  -- then reads its immutable event instead of applying the stale mutation over
  -- any newer edit.
  select *
    into v_existing
  from public.project_notes
  where id = p_note_id
  for update;

  if not found then
    raise exception 'project note mention edit is unavailable'
      using errcode = '42501';
  end if;

  select event.*
    into v_replay
  from public.project_note_mention_events event
  where event.id = p_event_id;

  if found then
    if v_replay.note_id = p_note_id
       and v_replay.actor_user_id = v_actor_id
       and v_replay.company_id = v_company_id
       and v_replay.requested_content is not distinct from p_content
       and v_replay.requested_mentioned_user_ids is not distinct from p_mentioned_user_ids
       and v_replay.requested_attachments is not distinct from p_attachments then
      return jsonb_build_object(
        'event_id', v_replay.id,
        'note_id', v_replay.note_id,
        'project_id', v_replay.project_id,
        'content', v_replay.content_snapshot,
        'mentioned_user_ids', v_replay.mentioned_user_ids_snapshot,
        'attachments', v_replay.attachments_snapshot,
        'recipient_user_ids', v_replay.recipient_user_ids,
        'added_count', cardinality(v_replay.recipient_user_ids),
        'updated_at', v_replay.note_updated_at,
        'replayed', true
      );
    end if;
    raise exception 'mention edit event id was reused with a different request'
      using errcode = '22023';
  end if;

  if v_existing.author_id is distinct from v_actor_id::text
     or v_existing.company_id is distinct from v_company_id::text
     or v_existing.deleted_at is not null
     or v_existing.event_kind is not null then
    raise exception 'project note mention edit is unavailable'
      using errcode = '42501';
  end if;

  -- A note must keep either words or a photo. Never let an edit quietly become
  -- a delete. `photo_url` is the note's SUBJECT when set, so it counts.
  if p_attachments is not null
     and jsonb_array_length(p_attachments) = 0
     and btrim(p_content) = ''
     and coalesce(btrim(v_existing.photo_url), '') = '' then
    raise exception 'a note must keep either text or a photo'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(candidate.user_id order by candidate.ordinality),
    '{}'::text[]
  )
    into v_effective_mentioned_user_ids
  from (
    select normalized.user_id, min(normalized.ordinality) as ordinality
    from (
      select
        requested.user_id::uuid::text as user_id,
        requested.ordinality
      from unnest(p_mentioned_user_ids)
        with ordinality as requested(user_id, ordinality)
    ) normalized
    group by normalized.user_id
  ) candidate
  where candidate.user_id <> v_actor_id::text;

  if exists (
    select 1
    from unnest(v_effective_mentioned_user_ids) candidate(user_id)
    where not exists (
      select 1
      from public.users user_row
      where user_row.id = candidate.user_id::uuid
        and user_row.company_id = v_company_id
        and user_row.is_active
        and user_row.deleted_at is null
    )
  ) then
    raise exception 'requested mention user is not active in actor company'
      using errcode = '22023';
  end if;

  select project.title
    into v_project_title
  from public.projects project
  where project.id::text = v_existing.project_id
    and project.company_id = v_company_id
    and project.deleted_at is null
  for share;

  if not found then
    raise exception 'project note mention edit project is unavailable'
      using errcode = '42501';
  end if;
  v_project_title := coalesce(
    nullif(btrim(v_project_title), ''),
    'Untitled project'
  );

  select coalesce(
    array_agg(candidate.user_id order by candidate.ordinality),
    '{}'::text[]
  )
    into v_added_recipient_ids
  from unnest(v_effective_mentioned_user_ids)
    with ordinality as candidate(user_id, ordinality)
  where candidate.user_id in (
    select unnest(v_effective_mentioned_user_ids)
    except
    select prior.user_id::uuid::text
    from unnest(coalesce(v_existing.mentioned_user_ids, '{}'::text[]))
      as prior(user_id)
    where prior.user_id ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

  update public.project_notes
  set content = p_content,
      mentioned_user_ids = v_effective_mentioned_user_ids,
      attachments = coalesce(p_attachments, attachments),
      updated_at = clock_timestamp()
  where id = p_note_id
  returning updated_at into v_updated_at;

  insert into public.project_note_mention_events (
    id,
    note_id,
    project_id,
    company_id,
    actor_user_id,
    requested_content,
    requested_mentioned_user_ids,
    requested_attachments,
    prior_content_snapshot,
    prior_mentioned_user_ids,
    content_snapshot,
    mentioned_user_ids_snapshot,
    attachments_snapshot,
    recipient_user_ids,
    actor_name_snapshot,
    project_title_snapshot,
    note_updated_at
  ) values (
    p_event_id,
    p_note_id,
    v_existing.project_id,
    v_company_id,
    v_actor_id,
    p_content,
    p_mentioned_user_ids,
    p_attachments,
    v_existing.content,
    coalesce(v_existing.mentioned_user_ids, '{}'::text[]),
    p_content,
    v_effective_mentioned_user_ids,
    coalesce(p_attachments, v_existing.attachments),
    v_added_recipient_ids,
    v_actor_name,
    v_project_title,
    v_updated_at
  );

  return jsonb_build_object(
    'event_id', p_event_id,
    'note_id', p_note_id,
    'project_id', v_existing.project_id,
    'content', p_content,
    'mentioned_user_ids', v_effective_mentioned_user_ids,
    'attachments', coalesce(p_attachments, v_existing.attachments),
    'recipient_user_ids', v_added_recipient_ids,
    'added_count', cardinality(v_added_recipient_ids),
    'updated_at', v_updated_at,
    'replayed', false
  );
end;
$function$;

-- A drop+create does NOT carry grants over. Reproduce the captured live ACL
-- exactly: EXECUTE revoked from PUBLIC, granted to anon + authenticated.
revoke execute on function public.update_project_note_mentions(
  uuid, text, text[], uuid, jsonb
) from public;
grant execute on function public.update_project_note_mentions(
  uuid, text, text[], uuid, jsonb
) to anon, authenticated;

commit;
