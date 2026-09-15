# Draft corrections — expense atomic-install fixture

Run: `run-atomic-fixture.sh`, PostgreSQL 17.11 (Homebrew), port 55495, disposable
socket-only cluster. All 11 declared cases plus the static guard-embed check passed.

## SQL draft corrections: NONE

`seed.sql`, `snapshot.sql` and `postconditions.sql` were copied from
`claude-handoff/atomic-fixture-incomplete/` and executed **byte-for-byte unmodified**.
Every assertion in them held against the real bundle-installed database:

| Draft file | sha256 | Corrections |
|---|---|---|
| `seed.sql` | `299cfc22fd61756bcd6d280beeec36af8ac33aaab417b26b9989ac07c7ec29b2` | none |
| `snapshot.sql` | `b33428af66c52be4b5531e89d329c57499959ab7803dbbc8e225f6a43518d37b` | none |
| `postconditions.sql` | `b55bc851bf35a75ad5a728cf366fe50f1303609589d6f8c2c3e65fa30835c188` | none |

Notably, no expected-MD5 in `postconditions.sql` needed adjusting. The post-install
values Codex predicted statically all matched the executed result, including
`public.read_agent_payroll_readiness_as_system(...)` = `f2e32a360886d5fed5040c5eb99b76c6`
(the baseline value `c3e517bcc781f6866601c5966fa0b58d` was independently confirmed on
the pre-bundle baseline in C0). No constituent-vs-bundle MD5 comparison was required.

## Harness deviations from the task brief (not draft edits)

### 1. Embedded guard occupies bundle lines 3..52, not 3..51

The brief's static check `sed -n '3,51p' expense-release-atomic.sql | diff - baseline-guard.sql`
is **not** empty: it reports `49a50 > $expense_release_baseline$;`. The closing
dollar-quote terminator of the guard's `DO` block is bundle line 52.
`sed -n '3,52p' … | diff - baseline-guard.sql` **is** empty (exit 0).

Justification: `baseline-guard.sql` is 50 lines; bundle line 2 is `BEGIN;`, so the
guard body starts at line 3 and must end at line 3 + 50 - 1 = 52. Both ranges are
recorded in `guard-embed-check.log`; the harness asserts the 3..52 range.
The guard is therefore embedded verbatim — only the brief's line number was off by one.

### 2. `expense-correction-concurrency.py` needs a second patched literal at port 55495

`tests/runtime/expense-correction-concurrency.py` line 8 hard-codes the reference
harness's port:

    base = [psql, '-h', socket, '-p', '55494', '-U', 'postgres', '-d', 'postgres', …]

The brief mandates port **55495** for this run while also mandating only the reference
harness's single-line database patch. Those two requirements are incompatible: with the
DB patch alone the runner would look for `<socket>/.s.PGSQL.55494`, which does not exist
in this cluster, and every contention check would fail to connect.

The harness therefore patches the COPY twice, asserting each needle occurs exactly once
in the source (both do):

    '-d', 'postgres'  ->  '-d', sys.argv[3]
    '-p', '55494'     ->  '-p', '55495'

No test, assertion or SQL operation in the runner was altered. The full one-line diff is
in `c2b-concurrency-patch.diff`; the patched copy is `correction-concurrency.py` in the
logs directory. The checked-in file under the candidate worktree was never modified.

### 3. C4d / C4f target-object presence check is drift-aware

The brief asks each rejected C4 drift to leave "all 11 target relations absent and
`reimbursement_amount` absent". Two drifts plant one of those objects *themselves*:

* C4d creates `public.expense_accounting_settings` (1 of the 11) as the partial install
* C4f adds `public.expense_batches.reimbursement_amount` as the unexpected column

So their correct expectations are `1/0` and `0/1` respectively, not `0/0`. The
harness asserts the drift-specific value (`absence-checks.log`). The stronger,
drift-independent proof that no migration body ran is the byte-for-byte `cmp` of the
post-rejection snapshot S1 against the pre-run snapshot S0, which passes for all seven
drifts.

## Observed behaviour that differs from the brief's predicted message

C1's blind reapplication is rejected, and nothing changes (S2 == S1 byte-for-byte), but
the exception raised is **not** `Expense release baseline is already installed or
partially changed`. Both the standalone guard and the frozen bundle raise:

    Expense release source baseline changed: private.enforce_expense_edit_authority

This is correct behaviour, not a defect. The guard evaluates its source-function MD5
block (bundle lines 30..41) *before* the target-object block (lines 42..50), and the
bundle replaces 7 of the 15 functions the guard pins:
`private.enforce_expense_edit_authority`, `public.tg_place_expense`,
`public.place_expense`, `public.approve_expense_batch`,
`public.early_clear_expense_line`, `public.mark_expense_batch_paid`,
`public.unmark_expense_batch_paid`. On an installed database the MD5 branch therefore
always fires first. The harness accepts either guard exception, requires the standalone
guard and the embedded guard to agree, and records the exact text in
`c1-reapply-message.log`.

Because the mismatch query is `… LIMIT 1` with no `ORDER BY`, the named function is not
guaranteed to be stable across runs when several are replaced; the harness compares the
*class* of rejection between guard and bundle rather than the function name. Both runs
in this proof reported `private.enforce_expense_edit_authority`.

---

# Production-safe read-only postconditions (`postconditions-production.sql`)

Created at `claude-handoff/atomic-install/postconditions-production.sql`
(sha256 `a4b8f4d6e2e280555f8ef53a726112cea4dc0bdc18e8cf264a156929120a4c48`) for post-install verification on the **live** database. It writes
nothing: the entire file runs inside `begin read only; ... rollback;`.

Verified by harness cases C5a/C5b/C5c on a fresh disposable PG17 cluster (port 55495).

## Exact diff against the fixture `postconditions.sql`

```diff
--- postconditions.sql
+++ postconditions-production.sql
@@ -1,3 +1,9 @@
+-- READ ONLY. Post-install verification for the live database after the expense
+-- release atomic bundle is applied. Runs entirely inside `begin read only; ... rollback;`
+-- and writes nothing. Derived from the fixture postconditions.sql with the seeded
+-- fixture-batch assertion removed and the accounting queue check scoped to
+-- entity_type='expense' so pre-existing AR/AP queue rows do not trip it.
+begin read only;
 do $atomic_postconditions$
 declare v_count integer; v_role text; v_sequence regclass;
 begin
@@ -7,12 +13,8 @@
  'public.expense_accounting_postings','private.expense_accounting_state','private.expense_correction_requests',
  'private.expense_correction_pending','private.expense_correction_scope']) r(name) where to_regclass(r.name) is not null;
  if v_count<>11 then raise exception 'ATOMIC_POSTCONDITION: expected all 11 new relations'; end if;
- if not exists(select 1 from public.expense_batches where id='79000000-0000-4000-8000-000000000100'
-   and reimbursement_amount=100 and total_amount=165 and approved_amount=140 and paid_at is null and paid_by is null) then
-   raise exception 'ATOMIC_POSTCONDITION: crew-only projection or payment markers changed';
- end if;
  if exists(select 1 from public.expense_accounting_events) or exists(select 1 from private.expense_accounting_state)
-   or exists(select 1 from public.accounting_sync_queue) or exists(select 1 from private.expense_correction_requests) then
+   or exists(select 1 from public.accounting_sync_queue where entity_type='expense') or exists(select 1 from private.expense_correction_requests) then
    raise exception 'ATOMIC_POSTCONDITION: installation generated financial/correction work';
  end if;
  if md5(pg_get_functiondef('public.read_agent_payroll_readiness_as_system(uuid,uuid,uuid,uuid,text,text[],text,text,text,text,text,timestamp with time zone,date,integer,integer,integer,integer)'::regprocedure))
@@ -48,3 +50,4 @@
 end;
 $atomic_postconditions$;
 select 'Atomic install postconditions passed';
+rollback;
```

## Why each change

1. **Seeded-batch assertion removed.** It pins `public.expense_batches` row
   `79000000-0000-4000-8000-000000000100` with `reimbursement_amount=100,
   total_amount=165, approved_amount=140` — a row that exists only in the fixture
   `seed.sql`. On the live database it would always fail. The crew-only projection
   arithmetic it guards stays proven by fixture case C1.
2. **Queue check scoped to `entity_type='expense'`.** The fixture check
   `exists(select 1 from public.accounting_sync_queue)` assumes an empty queue,
   which is true only on a fresh fixture. Production carries unrelated AR/AP rows
   (customer, invoice, estimate, payment, supplier, supplier_bill,
   supplier_bill_payment). Scoping to `'expense'` keeps the real assertion — the
   install must not enqueue expense accounting work — while ignoring pre-existing
   rows. The other three tables in that clause
   (`public.expense_accounting_events`, `private.expense_accounting_state`,
   `private.expense_correction_requests`) are created by the bundle itself, so
   they must still be strictly empty and were left unchanged.
   Note `'expense'` only becomes a legal `entity_type` after the bundle widens
   `accounting_sync_queue_entity_type_check` (lifecycle migration lines 160-162).
3. **`begin read only; ... rollback;` wrapper**, with the final
   `select 'Atomic install postconditions passed';` kept inside the transaction so
   the pass line is emitted before the rollback.
4. **Header comment** stating the file is read-only and for post-install
   verification on the live database.

No other line differs from the fixture file: all MD5 pins, grant checks, sequence
privilege checks and the 11-relation check are byte-identical.

## C5 verification results

| Case | Setup | Result |
|---|---|---|
| C5a | unseeded baseline + frozen bundle | exit 0, printed `Atomic install postconditions passed`, transaction ended `ROLLBACK` |
| C5b | unseeded baseline, bundle NOT applied | failed with `ATOMIC_POSTCONDITION: expected all 11 new relations` |
| C5c | seeded baseline + bundle + 1 unrelated `entity_type='invoice'` queue row (1/0 total/expense) | exit 0, printed the pass line — pre-existing AR/AP queue rows do not trip it |

The C5c queue row uses the accounting fixture's own NOT NULL columns:
`company_id, connection_id, provider='quickbooks', entity_type='invoice',
entity_id, operation='create', source_table='invoices', source_action='insert',
idempotency_key, status='pending'`.

## Harness changes for C5

`run-atomic-fixture.sh` gained three environment knobs so a subset can be re-run
without disturbing existing evidence, and all C0-C4 case bodies are unchanged:

* `FX_ONLY` — `all` (default) or `c5`, selecting which case block executes.
* `FX_LOGS_DIR` — append into an existing `proof.XXXXXX` directory instead of
  creating a new one; `result.txt` and `summary.tsv` are appended, not truncated.
* `FX_RUN_TAG` — prefix for this run's cluster-scoped logs (`c5-server.log`,
  `c5-init.log`, `c5-start.log`, `c5-stop.log`, `c5-database-lifecycle.log`), so a
  subset re-run cannot overwrite the full run's logs.

The C5 re-run used `FX_ONLY=c5 FX_RUN_TAG=c5- FX_LOGS_DIR=<proof dir>` on its own
fresh disposable cluster, same port/env/cleanup rules as the full run.
