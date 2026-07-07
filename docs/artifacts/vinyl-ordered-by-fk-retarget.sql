-- OPTIONAL follow-up migration — NOT required for the vinyl feature to work.
-- Bug 0f86b9b0 / c6e90385 investigation surfaced that
--   projects.vinyl_ordered_by  FK → auth.users(id)
-- but under the Firebase JWT bridge the app's identities live in public.users
-- (a public.users.id is never present in auth.users). The column has never been
-- successfully written (0 populated rows, verified live 2026-07-04), and the
-- "who marked it ordered" value is not surfaced anywhere in the app, so the iOS
-- clients now persist status + timestamp and leave vinyl_ordered_by NULL.
--
-- Apply this ONLY if we later want to record attribution (who marked vinyl
-- ordered). It retargets the FK to public.users(id), mirroring
-- catalog_orders.created_by_id (FK users(id) ON DELETE SET NULL). Safe:
--   * 0 rows populated, so no existing data can violate the new constraint.
--   * Transparent to installed iOS builds — the column stays uuid; this only
--     changes which table a (currently always-NULL) value must reference.
-- After applying, the iOS marker writes can send the operator's public.users.id
-- again instead of NULL.
--
-- This is a PRODUCTION DDL change and must be applied with Jackson's explicit
-- go (it was intentionally NOT auto-applied).

alter table public.projects drop constraint if exists projects_vinyl_ordered_by_fkey;
alter table public.projects
  add constraint projects_vinyl_ordered_by_fkey
  foreign key (vinyl_ordered_by) references public.users(id) on delete set null;
