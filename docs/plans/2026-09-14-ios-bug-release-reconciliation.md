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
8. User approval to resume one serial iOS verification run was received after the cleanup pause. Compile and run the mixed-media/text cancellation repair with the complete note-edit, attachment-presentation, note-merge and local-signal suites in an isolated current-main checkout. Integrate only after passing, preserve exact source/result evidence, and append verified local status to the original photo report without changing ownership or closing it.
9. With the user's subsequent explicit approval for the prepared photo-removal database update, repeat its exact live baseline guard, apply only that migration, independently read back the ledger/function/security state, and probe public API request resolution without changing customer notes. Align local migration filenames with the actual ledger version, update the Bible and append deployment evidence to the original unresolved bug.

Step8 completed: 118/118 simulator tests passed, including all 13 new regressions; source integrated as `b1cdc644` with matching app/test/project trees, proof committed as `a43be4be`, Bible updated as `1182a9f`, and the Supabase note independently verified with a zero-row guard replay. The temporary test environment was removed after retaining proof. The independent photo server migration was prepared but unapplied at that point.

Step9 completed: the exact production baseline guard passed, then Supabase applied the byte-identical reviewed SQL under ledger `20260915021754`. OPS-Web `c7098c283` records its canonical filename. Independent readback verified function MD5 `2bbb8d6782b140843ab050fabe72431b`, new nullable proof columns and unchanged authority/grants/immutability. All three anonymous no-change API probes returned expected validation/actor-denial errors. The original bug's deployment note read back exactly at `2026-09-15T02:28:48.306606Z`, preserving its owner, `in_progress` and null fix/resolution fields; the replay changed zero rows. Proof is in `docs/artifacts/ios-bugs-release-20260914/photo-attachments.md` and its linked JSON artifacts. No customer note was edited.

Constraints: Lead Details and LeadDeckScreen remain with their existing owner. The original build/simulator/cache pause was lifted only for step8's serial verification and necessary corrective reruns. Production approval covered only step9's independent photo-removal migration. The other five pending expense/project migrations, phone interaction, worker/environment changes, provider writes, pushes and iOS release remain unauthorized.
