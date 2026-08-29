-- =====================================================================
-- PM MUST APPLY — NOT YET APPLIED TO PROD.
--
-- Apply order: 1 of 3. Apply via MCP `apply_migration` against
-- ijeekuhbatykdomumfjx with migration name:
--     lead_won_prompt_decline_columns
-- Then read the stamped version back out of
-- supabase_migrations.schema_migrations and mirror this SQL into
-- ops-software-bible/migrations/<ledger_version>_<ledger_name>.sql per
-- that directory's README. Verify by object, never by version key.
--
-- The iOS half of this change (LeadWonPrompt.swift) is inert until all
-- three of these are applied: the prompt evaluates a column that does
-- not exist yet and simply never fires.
-- =====================================================================
--
-- D3 of ops-software-bible/specs/plans/2026-08-18-lead-project-identity-design.md
-- — bug 9a89b951. Additive only (two nullable columns), so an installed
-- iOS build that knows nothing about them keeps working unchanged.

alter table public.opportunities
  add column won_prompt_declined_at timestamptz,
  add column won_prompt_declined_by uuid;

comment on column public.opportunities.won_prompt_declined_at is
  'Operator declined the mark-lead-won proposal raised when its linked project entered an active status (accepted/in_progress/completed/closed). Non-null suppresses the prompt permanently for this lead; winning the lead makes it moot. D3 of 2026-08-18-lead-project-identity-design.';
comment on column public.opportunities.won_prompt_declined_by is
  'users.id of the operator who declined. Plain uuid by the vinyl_ordered_by convention (no FK).';
