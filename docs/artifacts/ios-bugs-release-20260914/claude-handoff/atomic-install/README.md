# Atomic expense install — prepare only

Frozen source revision: `53d334378cd0d61adec387a8580d569a46cf5d33`. The parent's later QBO test-only typing correction does not change these SQL bytes. Bundle `expense-release-atomic.sql` SHA256: `4d53da61929337ab783070818f387ac1e8650cd900230fd7685418a32c543d22` (146738 bytes).

`manifest.json` retains the source and transformed-body hashes and precise removed statement offsets for exactly:

1. `20260912012607_expense_decision_company_authority.sql`
2. `20260912203328_expense_accounting_lifecycle.sql`
3. `20260914200910_expense_payroll_reimbursement_projection.sql`
4. `20260914214748_expense_admin_correction_review.sql`

The source bodies are unchanged except removal of the three exact outer BEGIN/COMMIT pairs. Payroll has no outer transaction. Function bodies, comments, grants, sequence fences, identity-wait correction, payroll guard and correction hashes are preserved. A lexical statement scanner ignores comments, quoted strings and dollar-quoted bodies and rejects any unexpected top-level transaction statement. `constituent-sources/` preserves the four byte-identical originals. `prepare-bundle.py` only reads frozen Git objects and writes local artifacts; it has no database interface.

The bundle adds one outer BEGIN/COMMIT and a separate initial `baseline-guard.sql`. The identical guard can first run as `baseline-preflight-readonly.sql` (BEGIN READ ONLY/ROLLBACK). It checks 15 captured core actor/permission/decision/save/placement/recalculation definitions and their postgres owner, current migration owner postgres, absence of 11 new relations/28 new function names and absence of expense_batches.reimbursement_amount. `baseline-manifest.json` gives every assertion and its capture timestamp. The broader parent read-only preflight also checks schema/ACL/ledger/legacy evidence. A matching guard is not a lock against a concurrent privileged DDL release; serialize this release with other database changes and stop on any fresh drift.

This makes authority, durable capture, reimbursement semantics and reviewer correction visible together. Do not apply the four constituent files independently: that would leave an authority-only interval with old payout semantics. While the install acquires its existing DDL locks, ordinary requests can wait or encounter a truthful transient failure; a failure must roll back the entire install. Do not claim already-running legacy edge calls were cancelled by this database transaction.

Parent verification required before release:

- Run the standalone guard read-only against the freshly audited live baseline. No production migration is authorized by preparation.
- On a disposable exact-baseline fixture including the July 20 atomic-save migrations, confirm the initial guard passes, then install the entire bundle and run the focused expense contracts.
- Introduce a late deliberate SQL failure in a temporary copy before the outer COMMIT. Run it on a fresh disposable baseline and prove the authority function hashes, absence of new relations/column, grants and ordinary records are unchanged after rollback. Do not alter the frozen artifact to make a failing fixture pass.
- Prove changed function hash, wrong owner, a partial target relation/function and an unexpected reimbursement column reject before any of the four bodies run. Preserve actual test logs separately.

## One ledger entry and canonical source after an authorized install

Use the approved Supabase `apply_migration` tool **once** with this complete exact SQL payload. Let that mechanism record its one actual migration version; never manufacture four ledger rows or write the ledger directly. Record the actual returned version (or independently read its exact name/version back), submitted bundle hash, SQL source and constituent manifest. If the result is uncertain, inspect current schema and that exact ledger entry before any retry. The initial absence guard intentionally rejects blind reapplication.

Only after successful schema and ledger readback, make one local source reconciliation commit:

1. Rehome the four original pending constituent files, unchanged, under a clearly non-pending provenance directory such as `docs/artifacts/expense-release/constituents/`; remove them from `supabase/migrations/` so a later migration runner cannot replay them.
2. Add one `supabase/migrations/<ACTUAL_RETURNED_VERSION>_<ACTUAL_APPLIED_NAME>.sql` whose bytes are identical to the payload actually submitted. Do not invent the version in advance, rename another migration to impersonate it, or reformat the deployed SQL.
3. Preserve the manifest and a supersession record mapping all four prepared versions to that one actual version. Update the isolated test-harness paths to archived constituents where needed, and add/use the atomic-bundle test path; tests still need provenance, but migration discovery must see only the actual applied bundle.
4. Reconcile that canonical migration record into every release checkout before another migration command. A CLI history mismatch must be resolved from the actual ledger, not by `db push --include-all` or blind migration-repair writes.
5. Review and test the resulting source before the separately authorized full web deployment. No constituent archival, ledger mutation, migration apply or deployment has been performed by this preparing agent.
