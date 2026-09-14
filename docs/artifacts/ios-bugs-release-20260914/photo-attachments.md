# Photo attachment repair — 2026-09-14

Bug: `f5f57917-ac58-4d51-b706-eff0e68131e5`.

## Server repair verified; unapplied

Live inspection found only the four-argument `update_project_note_mentions(uuid,text,text[],uuid)`, MD5 `9d16ec64ff2d15da9e00fe1fbeb1adc4`. Current iOS sends a fifth `p_attachments` argument when media changes, so the live API cannot resolve that call.

Prepared migration `20260914224026_project_note_mentions_attachments.sql` is integrated on local OPS-Web main `7ccb38e84` (implementation `a5d2bdfdc`; all five final source/proof files are byte-identical to agent commit `0c600e4be`).

Migration SHA256: `863b2db89142bf2cc3728fb389786489ac71bd6e5d4ff82794baa3fd876e1d1d`.
Expected installed function MD5: `2bbb8d6782b140843ab050fabe72431b`.

The replacement accepts one optional attachment array and keeps one unambiguous RPC signature. Omitted/SQL-NULL requests preserve the old response shape and UPDATE-column behavior. Explicit arrays may only remove existing attachments, retaining original order/multiplicity; legacy blank entries remain representable but never count as evidence that an otherwise empty note survives. Gallery images and a photo comment's subject remain unchanged.

The existing active author/company/mention checks and immutable event replay remain. Old replay cannot reapply stale media over a later edit. Migration guards cover current function/helper/schema/owner/ACL/dependencies and immutable proof storage. Drop/create restores exactly postgres/anon/authenticated EXECUTE, removes default-added grantees, and requests a schema reload.

**Independent final verification: 62 SQL assertions + 24 real concurrency/migration-adversarial checks passed, exit0.** Logs: `/private/tmp/ops-note-attachments-proof.8599tG`. Earlier independent run `Fpd5g4` had 62+22 checks; two additional drift cases prompted this final rerun. The first sandbox attempt failed to allocate PostgreSQL shared memory before tests; the approved isolated run uses synthetic identities and a private Unix socket, never OPS credentials or a production connection. The cluster cleans up on exit.

Reproduce from OPS-Web: `bash scripts/test-project-note-attachments-postgres.sh`. The script pins this exact migration. Proof includes concurrent exact retry, mismatched request IDs, stale attachment resurrection denial, actor/company changes while waiting, transient lock timeout, receipt-persistence rollback, legacy response/trigger behavior, and 15 baseline drift refusals. Source fixture uses captured live identity/immutability/lifecycle helpers with synthetic supporting rows; it does not establish customer-live PostgREST or phone behavior.

The September4 staged artifact is unchanged. This migration is independent of the five pending expense/project-reopen migrations. Applying it to production still requires explicit approval and immediate live-baseline/readback checks; it has not been applied.

## iOS cancellation repair prepared; runtime pending

The audit also found a mixed offline-edit defect: queue attachment removal plus a text-only edit, then discard the removal. The old reconciler selects the surviving text payload, finds no attachment key, and leaves the cancelled removal visible. Discarding successive media edits could also restore an earlier cancelled baseline.

Reviewed repair `22f9a4c` independently projects media intent, carries only rollback metadata past cancelled media edits, guards executing/leased successors, and restores only its own attachment baseline after a failed transaction. Outgoing request fields/event identity are unchanged; text-only cancellation preserves independently received server media.

Current-main verification checkout:
`/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p8-note-attachments` at `7ef35203`, based on iOS main `daad6217`. Main remains unchanged.

**13 new regression cases are prepared but have not been compiled or run.** They cover both media/text orders, earlier/later surviving media, current inbound photos, whole-chain and sequential cancellation, UUID ties, failed transactions, independent payload metadata, absent/null legacy baseline keys and executing successors. Agent parsing and whitespace checks passed; current-main patch integration and whitespace checks passed. This is not runtime proof.

The cleanup task explicitly paused iOS builds and simulator work. A request to resume one serial focused run is pending. Run `ProjectNoteMentionEditTests` with related attachment presentation/claim tests after that restriction is lifted, then integrate only verified source. No simulator/cache restoration, device access, installation or app release occurred in this continuation.
