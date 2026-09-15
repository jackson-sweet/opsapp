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

## iOS cancellation repair verified and integrated locally

The audit also found a mixed offline-edit defect: queue attachment removal plus a text-only edit, then discard the removal. The old reconciler selects the surviving text payload, finds no attachment key, and leaves the cancelled removal visible. Discarding successive media edits could also restore an earlier cancelled baseline.

Reviewed repair `22f9a4c` independently projects media intent, carries only rollback metadata past cancelled media edits, guards executing/leased successors, and restores only its own attachment baseline after a failed transaction. Outgoing request fields/event identity are unchanged; text-only cancellation preserves independently received server media. A second independent read-only review of `7ef35203` against `daad6217` found no actionable issues.

The current-main verification checkout at `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p8-note-attachments` tested `7ef35203`, based on iOS main `daad6217`. The verified repair is integrated on local iOS main as **`b1cdc644`**. The entire `OPS`, `OPSTests` and `OPS.xcodeproj` Git trees match the passing checkout, along with all seven individually recorded source hashes.

**118 app-hosted simulator tests passed, with zero failures, skipped tests or expected failures.** The result bundle independently confirms 103 `ProjectNoteMentionEditTests`, nine `ActivityEntryEditAttachmentsTests`, four `ProjectNotesMergeTests` and two `ProjectNoteLocalSignalTests`. All 13 new regressions passed: both media/text orders, earlier/later surviving media, current inbound photos, whole-chain and sequential cancellation, UUID ties, failed transactions, independent payload metadata, absent/null legacy baseline keys and executing successors. Swift compilation and whitespace checks also passed.

The user explicitly lifted the cleanup pause for serial verification. A fresh iPhone 17 simulator ran iOS 26.5 (`23F77`) against the iOS 27.0 SDK. The initial two-job build was interrupted by this task for heavy Mac memory pressure before tests (exit75); the completed rerun used one build job, one simulator destination and no parallel testing (exit0). This was a cold app/test build after the old caches had been removed. XCTest execution itself took 4.476 seconds; build/setup time is separate.

Retained proof:

- [Source identity, integration and 13 regression results](photo-attachments-ios-proof.json)
- [Independent Xcode result summary](photo-attachments-ios-test-summary.json)
- Full bundle: `/private/tmp/ops-ios-bugs-p8/focused-2.xcresult`
- Build/test log: `/private/tmp/ops-ios-bugs-p8/focused-2.log`
- Exact invocation: `/private/tmp/ops-ios-bugs-p8/run-focused-serial.sh`

After verification, this task removed its temporary simulator, 5.2GB DerivedData, 8.8GB package cache and copied ignored build configuration. Source and proof remain; reproducing the invocation requires provisioning a dedicated simulator and restoring the ignored build configuration/cache.

Live readback at `2026-09-15T00:15:05.686583Z` still showed only the four-argument RPC with MD5 `9d16ec64ff2d15da9e00fe1fbeb1adc4`. The server migration remains unapplied. This proof establishes local simulator behavior, not original-phone acceptance, production media mutation, installation or an app release. The original bug owner is retained and the report remains open.
