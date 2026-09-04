-- =====================================================================
-- CONTRACT TESTS for 2026-09-04-02-lead-files-content-dedupe.staged.sql
-- Bug sweep 2026-09-04, cluster PHOTOS & MEDIA, bug 05f0aae6.
--
-- SAFE TO RUN AGAINST PROD. The whole script is wrapped in
-- `begin; … rollback;` — every seeded row is thrown away. It mutates nothing.
-- Run it AFTER applying the dedupe migration. Every assertion raises on
-- failure, so a clean run that prints "ALL CONTRACT TESTS PASSED" is the proof.
--
-- These exercise the REAL deployed function under REAL RLS with a REAL
-- identity — not a copy of the SQL — which is the only version of this test
-- worth having. Copy it into the ops-web SQL contract suite when the migration
-- is copied there.
--
-- Fixtures (captured from prod 2026-09-04, Canpro is the only tenant):
--   opportunity  2667c10d-73fc-44c3-a279-e05e8d762aa2   (Mariah Burton, won)
--   can view     canprojack@gmail.com  283d49df-90a1-4abb-b94c-3e9f17f02c0d
--                firebase_uid 8SUXPDPJG0QdQVghxKuMpnvq7yx1
--   cannot view  j4ckson.sweet@gmail.com 1746a0c1-be43-45d6-ab4d-584e82594b1b
--                firebase_uid forL6eR8CSdlgHL7WpjDyBIDv9H3
--
-- `auth.uid()` is unusable under the Firebase JWT bridge (the JWT `sub` is a
-- non-UUID Firebase UID), which is why identity is set through
-- `request.jwt.claims` with the firebase_uid as `sub`.
-- =====================================================================

begin;

do $$
declare
  k_opportunity constant uuid := '2667c10d-73fc-44c3-a279-e05e8d762aa2';
  k_viewer_uid  constant text := '8SUXPDPJG0QdQVghxKuMpnvq7yx1';
  k_outsider_uid constant text := 'forL6eR8CSdlgHL7WpjDyBIDv9H3';

  v_company    uuid;
  v_connection uuid;
  v_thread     text;
  v_baseline   int;
  v_actual     int;
  v_id         uuid;
  v_first      uuid;
  v_second     uuid;
begin
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"anon"}', k_viewer_uid), true);

  if private.get_current_user_id() is null then
    raise exception 'FIXTURE BROKEN: viewer firebase_uid % no longer resolves', k_viewer_uid;
  end if;

  select company_id, connection_id, provider_thread_id
    into v_company, v_connection, v_thread
  from public.email_attachments
  where opportunity_id = k_opportunity
  limit 1;

  if v_company is null then
    raise exception 'FIXTURE BROKEN: no email_attachments on opportunity %', k_opportunity;
  end if;

  select count(*) into v_baseline
  from public.get_opportunity_lead_files(k_opportunity);

  -- The reported lead is the headline proof: 29 raw rows collapse to 9 files.
  if v_baseline <> 9 then
    raise exception
      'BASELINE FAILED: expected 9 deduped files on the reported lead, got %', v_baseline;
  end if;
  raise notice 'PASS baseline — reported lead returns 9 files (raw rows: %)',
    (select count(*) from public.email_attachments where opportunity_id = k_opportunity);

  -- ------------------------------------------------------------------
  -- TEST 1 — two rows, same content_sha256, different message_id:
  --          ONE row returned, and it is the EARLIER occurrence.
  -- ------------------------------------------------------------------
  insert into public.email_attachments (
    company_id, connection_id, provider_thread_id, message_id, attachment_id,
    opportunity_id, filename, mime_type, content_sha256, storage_path,
    is_inline, ingest_status, attribution_status, occurred_at)
  values
    (v_company, v_connection, v_thread, 'ct-msg-early', 'ct-att-1',
     k_opportunity, 'contract-dupe.jpg', 'image/jpeg', 'ct-sha-shared',
     'contract/early.jpg', true, 'stored', 'attributed',
     timestamptz '2020-01-01 00:00:00+00')
  returning id into v_first;

  insert into public.email_attachments (
    company_id, connection_id, provider_thread_id, message_id, attachment_id,
    opportunity_id, filename, mime_type, content_sha256, storage_path,
    is_inline, ingest_status, attribution_status, occurred_at)
  values
    (v_company, v_connection, v_thread, 'ct-msg-late', 'ct-att-2',
     k_opportunity, 'contract-dupe.jpg', 'image/jpeg', 'ct-sha-shared',
     'contract/late.jpg', true, 'stored', 'attributed',
     timestamptz '2020-01-02 00:00:00+00')
  returning id into v_second;

  select count(*) into v_actual
  from public.get_opportunity_lead_files(k_opportunity) f
  where f.filename = 'contract-dupe.jpg';
  if v_actual <> 1 then
    raise exception 'TEST 1 FAILED: same-sha rows collapsed to % rows, expected 1', v_actual;
  end if;

  select f.id into v_id
  from public.get_opportunity_lead_files(k_opportunity) f
  where f.filename = 'contract-dupe.jpg';
  if v_id <> v_first then
    raise exception
      'TEST 1 FAILED: kept the later occurrence (%), expected the earlier (%)', v_id, v_first;
  end if;
  raise notice 'PASS test 1 — content dedupe keeps the earliest occurrence';

  -- ------------------------------------------------------------------
  -- TEST 2 — two rows with NULL content_sha256 are NEVER collapsed.
  --          `coalesce(content_sha256, id::text)` guarantees this.
  -- ------------------------------------------------------------------
  insert into public.email_attachments (
    company_id, connection_id, provider_thread_id, message_id, attachment_id,
    opportunity_id, filename, mime_type, content_sha256, storage_path,
    is_inline, ingest_status, attribution_status, occurred_at)
  values
    (v_company, v_connection, v_thread, 'ct-msg-null-a', 'ct-att-3',
     k_opportunity, 'contract-nullsha.jpg', 'image/jpeg', null,
     'contract/null-a.jpg', true, 'stored', 'attributed',
     timestamptz '2020-02-01 00:00:00+00'),
    (v_company, v_connection, v_thread, 'ct-msg-null-b', 'ct-att-4',
     k_opportunity, 'contract-nullsha.jpg', 'image/jpeg', null,
     'contract/null-b.jpg', true, 'stored', 'attributed',
     timestamptz '2020-02-02 00:00:00+00');

  select count(*) into v_actual
  from public.get_opportunity_lead_files(k_opportunity) f
  where f.filename = 'contract-nullsha.jpg';
  if v_actual <> 2 then
    raise exception 'TEST 2 FAILED: NULL-sha rows collapsed to % rows, expected 2', v_actual;
  end if;
  raise notice 'PASS test 2 — NULL content_sha256 rows are never collapsed';

  -- ------------------------------------------------------------------
  -- TEST 3 — an `external` row with an unsafe source_url stays excluded.
  --          Regression guard on the filter this migration did not touch.
  -- ------------------------------------------------------------------
  insert into public.email_attachments (
    company_id, connection_id, provider_thread_id, message_id, attachment_id,
    opportunity_id, filename, mime_type, content_sha256, source_url,
    is_inline, ingest_status, attribution_status, occurred_at)
  values
    (v_company, v_connection, v_thread, 'ct-msg-unsafe', 'ct-att-5',
     k_opportunity, 'contract-unsafe.jpg', 'image/jpeg', 'ct-sha-unsafe',
     'http://insecure.example.test/contract-unsafe.jpg',
     false, 'external', 'attributed',
     timestamptz '2020-03-01 00:00:00+00');

  select count(*) into v_actual
  from public.get_opportunity_lead_files(k_opportunity) f
  where f.filename = 'contract-unsafe.jpg';
  if v_actual <> 0 then
    raise exception 'TEST 3 FAILED: unsafe external url returned % rows, expected 0', v_actual;
  end if;
  raise notice 'PASS test 3 — unsafe external source_url still excluded';

  -- ------------------------------------------------------------------
  -- TEST 4 — presentation order is newest-first by occurred_at.
  --          The seeded rows are all dated 2020, so they must sort LAST,
  --          and among themselves newest-first.
  -- ------------------------------------------------------------------
  if exists (
    select 1
    from (
      select f.occurred_at,
             lag(f.occurred_at) over (order by ordinality) as previous
      from public.get_opportunity_lead_files(k_opportunity)
        with ordinality as f(id, filename, mime_type, source_url, from_email,
                             ingest_status, occurred_at, created_at, ordinality)
    ) ordered
    where previous is not null and occurred_at > previous
  ) then
    raise exception 'TEST 4 FAILED: rows are not newest-first by occurred_at';
  end if;
  raise notice 'PASS test 4 — rows return newest-first by occurred_at';

  -- ------------------------------------------------------------------
  -- TEST 5 — tenant isolation. A caller who fails
  --          `current_user_can_view_opportunity_inbox` gets ZERO rows,
  --          dedupe or no dedupe.
  -- ------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"anon"}', k_outsider_uid), true);

  select count(*) into v_actual
  from public.get_opportunity_lead_files(k_opportunity);
  if v_actual <> 0 then
    raise exception 'TEST 5 FAILED: outsider saw % rows, expected 0', v_actual;
  end if;

  perform set_config('request.jwt.claims', null, true);
  select count(*) into v_actual
  from public.get_opportunity_lead_files(k_opportunity);
  if v_actual <> 0 then
    raise exception 'TEST 5 FAILED: unauthenticated caller saw % rows, expected 0', v_actual;
  end if;
  raise notice 'PASS test 5 — tenant isolation holds for outsider and anon';

  raise notice 'ALL CONTRACT TESTS PASSED';
end $$;

rollback;
