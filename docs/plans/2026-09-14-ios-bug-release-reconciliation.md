# iOS bug release reconciliation implementation plan

**Goal:** Reconcile live iOS reports with source evidence and prepare an exact, reviewable release manifest.
**Architecture:** Read-only audits of existing code and live schema; guarded metadata updates for this task's verified fixes. Preserve existing ownership and customer records.
**Tech Stack:** Swift, PostgreSQL, TypeScript, Supabase.
**Design System:** N/A; no product UI changes in this reconciliation.
**Required Skills:** custom-skills:writing-plans, superpowers:dispatching-parallel-agents, superpowers:systematic-debugging, supabase:supabase.

1. Fetch live bug and QA schemas, records, ownership, and current repository state.
2. Independently audit older photo/visit reports and the P5/P6/P7 release dependency stack.
3. Verify exact current source hashes against retained P6/P7 test proof.
4. Verify production migration ledger and existing function fingerprints; record safe aggregate preflight evidence.
5. Append exact local verification and release limits to this task's five bug records. Preserve unresolved status and null fixed/resolved timestamps; read back each update and replay its guard.
6. Record the verified release manifest and outstanding source/acceptance gaps under docs/artifacts. Commit only these new documentation files.
7. Prepare the missing attachment-edit server migration against the current production baseline, verify it in disposable PostgreSQL with synthetic data, and independently review it. Preserve the existing iOS implementation and staged September4 artifact. Integrate verified server source and update the Bible before requesting production migration approval.

Constraints: Lead Details and LeadDeckScreen remain with their existing owner. No build, simulator, cache restoration, phone interaction, production migration, worker/environment change, provider write, push, or release.
