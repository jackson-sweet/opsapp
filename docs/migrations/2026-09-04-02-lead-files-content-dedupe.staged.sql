-- =====================================================================
-- STAGED — NOT APPLIED. Bug sweep 2026-09-04, cluster PHOTOS & MEDIA.
-- Related bug: 05f0aae6 ("many duplicate photos were uploaded to Mariah
-- Burton's lead").
--
-- NOTHING MAY APPLY THIS WITHOUT EXPLICIT APPROVAL. This file is staged in
-- the iOS repo as a reviewed artifact only. It is not on any migration path.
-- To ship it: copy VERBATIM into ops-web as a NEW timestamped migration
-- (`ops-web/supabase/migrations/<YYYYMMDDHHMMSS>_lead_files_content_dedupe.sql`)
-- and apply through the normal ops-web migration flow.
-- =====================================================================
--
-- ---------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------
-- The lead PHOTOS strip and the FILES count both read
-- `public.get_opportunity_lead_files` -> `private.get_opportunity_lead_files`.
-- That function returns EVERY attributed, client-visible `email_attachments`
-- row with no content dedupe, and does not even project `content_sha256` — so
-- iOS has no hash to dedupe on and cannot fix this client-side.
--
-- Every reply in an email thread re-includes the previous message's inline
-- images. The ingester correctly keys on a PER-MESSAGE identity
-- `(company_id, connection_id, message_id, attachment_id)`, so each quote
-- becomes a new row plus a new S3 object. Those rows are TRUE — each really
-- does record that a specific message carried that attachment. The identity
-- the OPERATOR sees is the file's CONTENT, not the message. The read was
-- wrong, not the data.
--
-- Measured on the reported lead (2667c10d-73fc-44c3-a279-e05e8d762aa2):
--   total_attachments 29 | image_attachments 29 | distinct_sha 9
--   distinct_messages 14 | inline_count 29 | window 2026-07-21 -> 2026-08-28
--   1000030451.jpg  4.27 MB  10 copies across 10 messages / 10 storage paths
--   1000030666.jpg  2.33 MB   9 copies across  9 messages /  9 storage paths
--   IMG_5031.jpeg   1.10 MB   4 copies across  4 messages /  4 storage paths
--   6 others        1 copy each
--
-- Replay-on-drain (the 3-day email freeze drained 2026-09-04) was tested and
-- ruled out: ZERO rows on this lead were created 2026-09-01 -> 2026-09-04.
-- The duplication accrued gradually as the thread grew.
--
-- ---------------------------------------------------------------------
-- WHAT THIS DOES
-- ---------------------------------------------------------------------
-- One row per distinct file CONTENT, keeping the EARLIEST occurrence — the
-- message where the customer actually sent the photo — then restoring the
-- newest-first presentation order the client expects.
--
-- Safety notes:
--   * `coalesce(content_sha256, id::text)` means a NULL-hash row can never be
--     collapsed into another. (Of all 277 attributed, client-visible rows in
--     prod today, ZERO have a NULL content_sha256 — the coalesce is future
--     insurance, not a live path.)
--   * Signature, return type and column order are IDENTICAL. Only the row set
--     shrinks, so every already-shipped iOS build is fixed the moment this
--     lands — no App Store release needed, zero iOS changes.
--   * `public.get_opportunity_lead_files` is a `select * from private.…`
--     wrapper and needs NO change.
--   * `get_opportunity_lead_files` is not referenced anywhere in `ops-web/src`
--     (verified by grep) — iOS is the only consumer, so web cannot regress.
--   * The `attribution_status` / `ingest_status` / safe-URL / inbox-visibility
--     filters are carried over BYTE-FOR-BYTE from the current definition.
--
-- NO DATA REPAIR IS PERFORMED, DELIBERATELY. Deleting the 82 redundant rows
-- company-wide would destroy per-message provenance, break the
-- `email_attachments_storage_path_unique` bookkeeping, and orphan S3 objects.
-- Company-wide scope for context: 32 duplicate groups, 82 redundant rows,
-- 0.18 GiB of duplicated S3 bytes across 12 leads — under $0.01/month at S3
-- Standard us-west-2 list pricing (~$0.023/GB-month). Not worth a destructive
-- cleanup. If storage cleanup is ever wanted it is a separate, independently
-- decided task.
--
-- ---------------------------------------------------------------------
-- VERIFY AFTER APPLYING
-- ---------------------------------------------------------------------
--   select count(*) from public.get_opportunity_lead_files(
--     '2667c10d-73fc-44c3-a279-e05e8d762aa2');
--   -- EXPECT 9   (was 29)
--
-- Then open Mariah Burton's lead on a device WITHOUT reinstalling: PHOTOS
-- shows one tile per real image and FILES reads `9 attachments`.
--
-- ---------------------------------------------------------------------

begin;

create or replace function private.get_opportunity_lead_files(p_opportunity_id uuid)
returns table(id uuid, filename text, mime_type text, source_url text,
              from_email text, ingest_status text,
              occurred_at timestamp with time zone, created_at timestamp with time zone)
language sql
stable
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  -- One row per distinct file CONTENT. A quoted reply re-sends the same inline
  -- image under a new message id, so the per-message identity that the ingester
  -- (correctly) keys on is NOT the identity the operator sees. The earliest
  -- occurrence wins: that is when the customer actually sent it.
  with visible as (
    select
      attachment.id,
      attachment.filename,
      attachment.mime_type,
      case when attachment.ingest_status = 'external' then attachment.source_url else null end as source_url,
      attachment.from_email,
      attachment.ingest_status,
      attachment.occurred_at,
      attachment.created_at,
      coalesce(attachment.content_sha256, attachment.id::text) as content_key
    from public.email_attachments as attachment
    where attachment.opportunity_id = p_opportunity_id
      and attachment.attribution_status = 'attributed'
      and attachment.ingest_status in ('stored', 'external')
      and (
        attachment.ingest_status = 'stored'
        or private.is_safe_https_attachment_url(attachment.source_url)
      )
      and private.current_user_can_view_opportunity_inbox(
            p_opportunity_id, attachment.connection_id)
  ),
  earliest as (
    select distinct on (content_key)
      id, filename, mime_type, source_url, from_email, ingest_status, occurred_at, created_at
    from visible
    order by content_key, occurred_at asc nulls last, created_at asc, id asc
  )
  select id, filename, mime_type, source_url, from_email, ingest_status, occurred_at, created_at
  from earliest
  order by occurred_at desc nulls last, created_at desc, id desc;
$function$;

-- `create or replace` preserves the existing ACL, so no re-grant is needed.
-- Recorded for the reviewer, captured from prod 2026-09-04:
--   private.get_opportunity_lead_files(uuid)
--     postgres=X/postgres | anon=X/postgres | authenticated=X/postgres
--   public.get_opportunity_lead_files(uuid)  (unchanged by this migration)
--     postgres=X/postgres | anon=X/postgres | authenticated=X/postgres

commit;
