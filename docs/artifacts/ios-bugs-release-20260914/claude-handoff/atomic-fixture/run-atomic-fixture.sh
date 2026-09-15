#!/usr/bin/env bash
# Atomic expense-release bundle proof. One NEW socket-only PG17 cluster; no OPS DB.
# Read-only against every frozen input; all writes land in the disposable cluster
# and in the run's own logs directory.
set -euo pipefail
umask 077

fx_evidence=/private/tmp/ops-ios-bugs-p9-expense
fx_work=$fx_evidence/atomic-fixture
fx_handoff=/Users/jacksonsweet/Projects/OPS/ops-ios/docs/artifacts/ios-bugs-release-20260914/claude-handoff
fx_atomic=$fx_handoff/atomic-install
fx_candidate=/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p9-expense-release
fx_pg=/opt/homebrew/opt/postgresql@17/bin
fx_python=/usr/bin/python3
fx_port=55495
# Complete allowlist: no inherited credentials, service files, PGOPTIONS,
# Python startup settings, user shell configuration or application environment.
fx_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C LC_ALL=C PYTHONDONTWRITEBYTECODE=1)

fx_bundle=$fx_atomic/expense-release-atomic.sql
fx_guard=$fx_atomic/baseline-guard.sql
fx_preflight=$fx_atomic/baseline-preflight-readonly.sql
fx_seed=$fx_work/seed.sql
fx_snapshot_sql=$fx_work/snapshot.sql
fx_post=$fx_work/postconditions.sql
fx_concurrency=$fx_candidate/tests/runtime/expense-correction-concurrency.py
fx_production_post=$fx_atomic/postconditions-production.sql

fx_bundle_sha=4d53da61929337ab783070818f387ac1e8650cd900230fd7685418a32c543d22
fx_guard_sha=0c7f1fd89944620614ba17b595ffcccbe0d14b1c8f324f7719997d919b010423
fx_payroll_baseline_md5=c3e517bcc781f6866601c5966fa0b58d
fx_payroll_signature='public.read_agent_payroll_readiness_as_system(uuid,uuid,uuid,uuid,text,text[],text,text,text,text,text,timestamp with time zone,date,integer,integer,integer,integer)'

# Exact order required before the bundle. The four bundle constituents are absent
# on purpose: the bundle itself is the only thing that installs them.
fx_stack=(
 "$fx_candidate/tests/sql/expense-decision-authority-baseline.sql"
 "$fx_candidate/tests/sql/expense-accounting-fixture.sql"
 "$fx_candidate/tests/sql/expense-correction-fixture.sql"
 "$fx_candidate/supabase/migrations/20260720024121_expense_atomic_save.sql"
 "$fx_candidate/supabase/migrations/20260720024623_fix_expense_batch_recalculation_alias.sql"
 "$fx_candidate/tests/sql/expense-payroll-projection-live-baseline.sql"
 "$fx_candidate/tests/sql/expense-correction-baseline.sql"
)
fx_accounting_runtime=$fx_candidate/tests/sql/expense-accounting-runtime.sql
fx_correction_runtime=$fx_candidate/tests/sql/expense-correction-runtime.sql

for fx_file in "${fx_stack[@]}" "$fx_bundle" "$fx_guard" "$fx_preflight" "$fx_seed" \
 "$fx_snapshot_sql" "$fx_post" "$fx_production_post" "$fx_concurrency" "$fx_accounting_runtime" "$fx_correction_runtime"; do
 [[ -r "$fx_file" ]] || { printf 'Missing required input: %s\n' "$fx_file" >&2; exit 1; }
done
for fx_binary in "$fx_pg/initdb" "$fx_pg/pg_ctl" "$fx_pg/psql" "$fx_pg/createdb" "$fx_pg/dropdb" "$fx_python"; do
 [[ -x "$fx_binary" ]] || { printf 'Missing executable: %s\n' "$fx_binary" >&2; exit 1; }
done

# FX_ONLY selects a case subset (all | c5). FX_LOGS_DIR appends into an existing
# proof directory and FX_RUN_TAG prefixes this run's cluster-scoped log names so a
# subset re-run never overwrites an earlier run's evidence.
fx_only=${FX_ONLY:-all}
fx_runtag=${FX_RUN_TAG:-}
fx_scratch=$(mktemp -d "$fx_evidence/pg.XXXXXX")
if [[ -n "${FX_LOGS_DIR:-}" ]]; then
 fx_logs=$FX_LOGS_DIR
 [[ -d "$fx_logs" ]] || { printf 'FX_LOGS_DIR is not a directory: %s\n' "$fx_logs" >&2; exit 1; }
else
 fx_logs=$(mktemp -d "$fx_work/proof.XXXXXX")
fi
fx_socket=$fx_scratch/socket
mkdir -p "$fx_socket"
: > "$fx_scratch/pgpass"
: > "$fx_scratch/pg_service.conf"
fx_env+=("PGPASSFILE=$fx_scratch/pgpass" "PGSERVICEFILE=$fx_scratch/pg_service.conf")
fx_started=0
cleanup() {
 fx_exit=$?
 trap - EXIT
 fx_safe_to_remove=1
 if [[ $fx_started == 1 ]]; then
  if ! "${fx_env[@]}" "$fx_pg/pg_ctl" -D "$fx_scratch/data" -m immediate -w stop > "$fx_logs/${fx_runtag}stop.log" 2>&1; then
   fx_safe_to_remove=0
   printf 'Cluster stop needs inspection; preserving %s\n' "$fx_scratch" >&2
   fx_exit=1
  fi
 fi
 if [[ $fx_safe_to_remove == 1 ]]; then
  case "$fx_scratch" in "$fx_evidence"/pg.*) rm -rf "$fx_scratch";; esac
 fi
 printf 'Atomic fixture logs retained: %s\n' "$fx_logs"
 exit "$fx_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Atomic expense bundle proof logs: %s\n' "$fx_logs"

if [[ -z "${FX_LOGS_DIR:-}" ]]; then : > "$fx_logs/summary.tsv"; : > "$fx_logs/result.txt"; fi
touch "$fx_logs/summary.tsv" "$fx_logs/result.txt"
fx_fail() { printf 'FAIL: %s\n' "$*" | tee -a "$fx_logs/result.txt" >&2; exit 1; }
fx_note() { # case status key-line
 printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\n\t' '  ')" >> "$fx_logs/summary.tsv"
}
fx_pass() { printf 'PASS: %s\n' "$*" | tee -a "$fx_logs/result.txt"; }

# ---------------------------------------------------------------- input hashes
"${fx_env[@]}" "$fx_python" - "$fx_bundle" "$fx_guard" "$fx_preflight" "$fx_seed" \
 "$fx_snapshot_sql" "$fx_post" "$fx_production_post" "$fx_concurrency" "$fx_accounting_runtime" \
 "$fx_correction_runtime" "${fx_stack[@]}" > "$fx_logs/source-inputs.log" <<'PY'
import hashlib, pathlib, sys
for name in sys.argv[1:]:
    print(hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest(), name)
PY
"${fx_env[@]}" "$fx_python" - "$fx_bundle" "$fx_bundle_sha" "$fx_guard" "$fx_guard_sha" >> "$fx_logs/source-inputs.log" <<'PY'
import hashlib, pathlib, sys
for name, expected in zip(sys.argv[1::2], sys.argv[2::2]):
    actual = hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()
    assert actual == expected, (name, actual, expected)
    print('frozen hash confirmed', expected, name)
size = pathlib.Path(sys.argv[1]).stat().st_size
assert size == 146738, size
print('frozen byte count confirmed', size)
PY
printf 'PG psql version: %s\n' "$("${fx_env[@]}" "$fx_pg/psql" --version)" >> "$fx_logs/source-inputs.log"

# ------------------------------------------------- guard embedded verbatim check
{
 printf '# brief-stated range 3,51 (expected empty)\n'
 if sed -n '3,51p' "$fx_bundle" | diff - "$fx_guard"; then printf 'RANGE 3,51 IDENTICAL\n'; else printf 'RANGE 3,51 DIFFERS (exit %s)\n' "$?"; fi
 printf '\n# actual guard range 3,52 (closing dollar-quote is bundle line 52)\n'
 if sed -n '3,52p' "$fx_bundle" | diff - "$fx_guard"; then printf 'RANGE 3,52 IDENTICAL\n'; else printf 'RANGE 3,52 DIFFERS (exit %s)\n' "$?"; fi
 printf '\n# bundle line 1/2 and final statement\n'
 sed -n '1,2p' "$fx_bundle"
 printf 'line 2510: %s\n' "$(sed -n '2510p' "$fx_bundle")"
 printf 'bundle line count: %s\n' "$(wc -l < "$fx_bundle" | tr -d ' ')"
 printf 'guard file line count: %s\n' "$(wc -l < "$fx_guard" | tr -d ' ')"
} > "$fx_logs/guard-embed-check.log" 2>&1
sed -n '3,52p' "$fx_bundle" | diff -q - "$fx_guard" > /dev/null \
 || fx_fail 'embedded guard is not verbatim at bundle lines 3..52'
[[ "$(sed -n '2510p' "$fx_bundle")" == 'COMMIT;' ]] || fx_fail 'bundle line 2510 is not COMMIT;'
if [[ "$fx_only" == all ]]; then
 fx_note guard-embed PASS 'bundle lines 3..52 byte-identical to baseline-guard.sql (brief said 3..51; line 52 is the closing $expense_release_baseline$;)'
fi

# ------------------------------------------------------------ cluster lifecycle
"${fx_env[@]}" "$fx_pg/initdb" -D "$fx_scratch/data" -A trust --no-locale -E UTF8 -U postgres > "$fx_logs/${fx_runtag}init.log" 2>&1
fx_started=1
"${fx_env[@]}" "$fx_pg/pg_ctl" -D "$fx_scratch/data" -l "$fx_logs/${fx_runtag}server.log" \
 -o "-k $fx_socket -p $fx_port -c listen_addresses='' -c timezone=UTC -c max_connections=8 -c shared_buffers=32MB -c max_parallel_workers=0" \
 -w start > "$fx_logs/${fx_runtag}start.log" 2>&1

fx_q() { # db sql -> single value, quiet
 local db=$1; shift
 "${fx_env[@]}" "$fx_pg/psql" -h "$fx_socket" -p "$fx_port" -U postgres -d "$db" -X -Atq -v ON_ERROR_STOP=1 -v VERBOSITY=verbose "$@"
}
fx_raw() { # db user on_error_stop logbase [psql args...] -> tags visible; never aborts the script
 local db=$1 user=$2 stop=$3 base=$4; shift 4
 local rc=0
 "${fx_env[@]}" "$fx_pg/psql" -h "$fx_socket" -p "$fx_port" -U "$user" -d "$db" \
   -X -v "ON_ERROR_STOP=$stop" -v VERBOSITY=verbose "$@" > "$base.out" 2> "$base.err" || rc=$?
 cat "$base.out" "$base.err" > "$base.log"
 return $rc
}
fx_last_line() { /usr/bin/grep -v '^[[:space:]]*$' "$1" | tail -n 1; }
# Strip the psql file:line prefix and the verbose SQLSTATE so only the server
# message text is compared between the standalone guard and the embedded guard.
fx_errmsg() { /usr/bin/grep -m1 'ERROR:' "$1" | sed -E 's/^.*ERROR:[[:space:]]*//; s/^[0-9A-Z]{5}:[[:space:]]*//' ; }
fx_errclass() {
 case "$1" in
  *'Expense release baseline is already installed or partially changed'*) printf 'already-installed-or-partial';;
  *'Expense release source baseline changed:'*) printf 'source-baseline-changed';;
  *'Expense release requires the reviewed postgres migration owner'*) printf 'non-postgres-owner';;
  *) printf 'other';;
 esac
}

fx_reset() { # disposable database name from a closed allowlist
 local db=$1
 case "$db" in
  atomic_fixture_c0|atomic_fixture_c1|atomic_fixture_c2a|atomic_fixture_c2b|atomic_fixture_c3|\
  atomic_fixture_c4a|atomic_fixture_c4b|atomic_fixture_c4c|atomic_fixture_c4d|\
  atomic_fixture_c4e|atomic_fixture_c4f|atomic_fixture_c4g|\
  atomic_fixture_c5a|atomic_fixture_c5b|atomic_fixture_c5c) ;;
  *) fx_fail "unsafe disposable DB name: $db";;
 esac
 "${fx_env[@]}" "$fx_pg/dropdb" -h "$fx_socket" -p "$fx_port" -U postgres --if-exists --force "$db" >> "$fx_logs/${fx_runtag}database-lifecycle.log" 2>&1
 "${fx_env[@]}" "$fx_pg/createdb" -h "$fx_socket" -p "$fx_port" -U postgres -T template0 -E UTF8 "$db" >> "$fx_logs/${fx_runtag}database-lifecycle.log" 2>&1
}
fx_baseline() { # db seeded|unseeded logfile
 local db=$1 seeded=$2 log=$3 file
 fx_reset "$db"
 : > "$log"
 for file in "${fx_stack[@]}"; do
  printf 'Loading %s\n' "$file" >> "$log"
  fx_q "$db" -f "$file" >> "$log" 2>&1 || { tail -n 40 "$log" >&2; fx_fail "baseline load failed on $file ($db)"; }
 done
 if [[ "$seeded" == seeded ]]; then
  printf 'Loading %s\n' "$fx_seed" >> "$log"
  fx_q "$db" -f "$fx_seed" >> "$log" 2>&1 || { tail -n 40 "$log" >&2; fx_fail "seed failed ($db)"; }
 fi
}
fx_snapshot() { # db outfile
 local db=$1 out=$2
 fx_q "$db" -f "$fx_snapshot_sql" > "$out" 2> "$out.err" || { cat "$out.err" >&2; fx_fail "snapshot failed ($db)"; }
 [[ "$(wc -l < "$out" | tr -d ' ')" == 1 ]] || fx_fail "snapshot is not a single line ($db)"
 rm -f "$out.err"
}
fx_absent() { # db label [expected] -> "<target relations present>/<reimbursement_amount present>"
 # Expected is 0/0 everywhere except the C4 drifts that deliberately plant one of
 # the target objects themselves; the byte-for-byte S1==S0 comparison is what
 # proves no migration body ran, this is the independent new-connection check.
 local db=$1 label=$2 expect=${3:-0/0} seen
 seen=$(fx_q "$db" -c "select (select count(*) from unnest(array['public.expense_accounting_settings','public.expense_accounting_payee_mappings','public.expense_accounting_tax_mappings','public.expense_accounting_category_mappings','public.expense_accounting_project_mappings','public.expense_accounting_events','public.expense_accounting_postings','private.expense_accounting_state','private.expense_correction_requests','private.expense_correction_pending','private.expense_correction_scope']) t(name) where to_regclass(t.name) is not null)||'/'||(select count(*) from pg_attribute a where a.attrelid='public.expense_batches'::regclass and a.attname='reimbursement_amount' and not a.attisdropped)")
 printf '%s target-relations/reimbursement_amount present = %s\n' "$label" "$seen" >> "$fx_logs/${fx_runtag}absence-checks.log"
 [[ "$seen" == "$expect" ]] || fx_fail "$label: expected $expect target relations + reimbursement_amount, got $seen"
}

[[ "$(fx_q postgres -c 'show server_version_num')" == 17* ]] || fx_fail 'require PG17'
printf 'server_version: %s\n' "$(fx_q postgres -c 'show server_version')" >> "$fx_logs/source-inputs.log"

if [[ "$fx_only" == all ]]; then
# =============================================================== C0 clean guard
fx_baseline atomic_fixture_c0 seeded "$fx_logs/c0-baseline-load.log"
fx_raw atomic_fixture_c0 postgres 1 "$fx_logs/c0-preflight-readonly" -f "$fx_preflight" \
 || fx_fail 'C0: read-only preflight failed on a clean seeded baseline'
/usr/bin/grep -q '^ROLLBACK$' "$fx_logs/c0-preflight-readonly.out" \
 || fx_fail 'C0: read-only preflight did not report ROLLBACK'
fx_raw atomic_fixture_c0 postgres 1 "$fx_logs/c0-guard-standalone" -f "$fx_guard" \
 || fx_fail 'C0: standalone baseline guard rejected a clean baseline'
fx_c0_md5=$(fx_q atomic_fixture_c0 -c "select md5(pg_get_functiondef('$fx_payroll_signature'::regprocedure))")
printf 'payroll baseline md5: %s\n' "$fx_c0_md5" > "$fx_logs/c0-payroll-md5.log"
[[ "$fx_c0_md5" == "$fx_payroll_baseline_md5" ]] \
 || fx_fail "C0: payroll baseline md5 is $fx_c0_md5, expected $fx_payroll_baseline_md5"
fx_note C0 PASS "preflight ROLLBACK + guard exit 0 + payroll baseline md5 $fx_c0_md5"
fx_pass 'C0 guard on clean baseline: read-only preflight ends ROLLBACK, standalone guard exits 0, payroll baseline md5 matches'

# ======================================================== C1 full atomic install
fx_baseline atomic_fixture_c1 seeded "$fx_logs/c1-baseline-load.log"
fx_snapshot atomic_fixture_c1 "$fx_logs/c1-snapshot-S0.json"
fx_raw atomic_fixture_c1 postgres 1 "$fx_logs/c1-bundle-install" -f "$fx_bundle" \
 || { tail -n 30 "$fx_logs/c1-bundle-install.log" >&2; fx_fail 'C1: frozen bundle failed on a clean seeded baseline'; }
fx_c1_tag=$(fx_last_line "$fx_logs/c1-bundle-install.out")
[[ "$fx_c1_tag" == 'COMMIT' ]] || fx_fail "C1: bundle final transaction result is '$fx_c1_tag', expected COMMIT"
fx_raw atomic_fixture_c1 postgres 1 "$fx_logs/c1-postconditions" -f "$fx_post" \
 || { tail -n 30 "$fx_logs/c1-postconditions.log" >&2; fx_fail 'C1: postconditions failed after install'; }
/usr/bin/grep -q 'Atomic install postconditions passed' "$fx_logs/c1-postconditions.out" \
 || fx_fail 'C1: postconditions did not print the pass line'
fx_snapshot atomic_fixture_c1 "$fx_logs/c1-snapshot-S1.json"
if cmp -s "$fx_logs/c1-snapshot-S0.json" "$fx_logs/c1-snapshot-S1.json"; then
 fx_fail 'C1: S1 equals S0 - the bundle changed nothing'
fi
# Blind reapplication must be rejected by the same guard, changing nothing.
if fx_raw atomic_fixture_c1 postgres 1 "$fx_logs/c1-guard-reapply" -f "$fx_guard"; then
 fx_fail 'C1: standalone guard accepted an already-installed database'
fi
fx_c1_guard_msg=$(fx_errmsg "$fx_logs/c1-guard-reapply.err" || true)
if fx_raw atomic_fixture_c1 postgres 1 "$fx_logs/c1-bundle-reapply" -f "$fx_bundle"; then
 fx_fail 'C1: frozen bundle reapplied successfully on an already-installed database'
fi
fx_c1_bundle_msg=$(fx_errmsg "$fx_logs/c1-bundle-reapply.err" || true)
[[ "$(fx_errclass "$fx_c1_guard_msg")" == "$(fx_errclass "$fx_c1_bundle_msg")" ]] \
 || fx_fail "C1: guard and bundle rejection classes differ ('$fx_c1_guard_msg' vs '$fx_c1_bundle_msg')"
case "$(fx_errclass "$fx_c1_guard_msg")" in
 already-installed-or-partial|source-baseline-changed) ;;
 *) fx_fail "C1: unexpected reapply rejection message: $fx_c1_guard_msg";;
esac
fx_snapshot atomic_fixture_c1 "$fx_logs/c1-snapshot-S2.json"
cmp "$fx_logs/c1-snapshot-S1.json" "$fx_logs/c1-snapshot-S2.json" \
 || fx_fail 'C1: rejected reapplication changed the database (S2 != S1)'
fx_note C1 PASS "bundle COMMIT; postconditions passed; reapply rejected with: $fx_c1_guard_msg; S2==S1"
fx_pass "C1 full atomic install: bundle COMMITs, postconditions pass, blind reapply rejected identically by guard and bundle, S2==S1 byte-for-byte"
{ printf 'C1 standalone-guard reapply rejection: %s\n' "$fx_c1_guard_msg"
  printf 'C1 frozen-bundle reapply rejection:   %s\n' "$fx_c1_bundle_msg"
  printf 'C1 rejection class: %s\n' "$(fx_errclass "$fx_c1_guard_msg")"
} > "$fx_logs/c1-reapply-message.log"

# ======================================= C2 focused contracts on a bundled DB
fx_baseline atomic_fixture_c2a unseeded "$fx_logs/c2a-baseline-load.log"
fx_raw atomic_fixture_c2a postgres 1 "$fx_logs/c2a-bundle-install" -f "$fx_bundle" \
 || { tail -n 30 "$fx_logs/c2a-bundle-install.log" >&2; fx_fail 'C2: bundle failed on the unseeded accounting DB'; }
fx_raw atomic_fixture_c2a postgres 1 "$fx_logs/c2a-accounting-runtime" -f "$fx_accounting_runtime" \
 || { tail -n 45 "$fx_logs/c2a-accounting-runtime.log" >&2; fx_fail 'C2: expense-accounting-runtime.sql failed on the bundle-installed DB'; }
/usr/bin/grep -q '123 expense accounting runtime assertions passed' "$fx_logs/c2a-accounting-runtime.log" \
 || { tail -n 45 "$fx_logs/c2a-accounting-runtime.log" >&2; fx_fail 'C2: accounting runtime pass line missing'; }

fx_baseline atomic_fixture_c2b unseeded "$fx_logs/c2b-baseline-load.log"
fx_raw atomic_fixture_c2b postgres 1 "$fx_logs/c2b-bundle-install" -f "$fx_bundle" \
 || { tail -n 30 "$fx_logs/c2b-bundle-install.log" >&2; fx_fail 'C2: bundle failed on the unseeded correction DB'; }
fx_raw atomic_fixture_c2b postgres 1 "$fx_logs/c2b-correction-runtime" -f "$fx_correction_runtime" \
 || { tail -n 45 "$fx_logs/c2b-correction-runtime.log" >&2; fx_fail 'C2: expense-correction-runtime.sql failed on the bundle-installed DB'; }
/usr/bin/grep -q '69 expense correction assertions passed' "$fx_logs/c2b-correction-runtime.log" \
 || { tail -n 45 "$fx_logs/c2b-correction-runtime.log" >&2; fx_fail 'C2: correction runtime pass line missing'; }

# Patch a COPY of the concurrency runner: disposable DB name, and the fixture port
# (the checked-in runner hard-codes the reference harness port 55494).
"${fx_env[@]}" "$fx_python" - "$fx_concurrency" "$fx_logs/correction-concurrency.py" "$fx_port" \
 > "$fx_logs/c2b-concurrency-patch.log" <<'PY'
import ast, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
ast.parse(source, feature_version=9)
db_needle = "'-d', 'postgres'"
port_needle = "'-p', '55494'"
assert source.count(db_needle) == 1, source.count(db_needle)
assert source.count(port_needle) == 1, source.count(port_needle)
# Preserve every test and SQL operation; only inject the disposable DB and port.
patched = source.replace(db_needle, "'-d', sys.argv[3]").replace(port_needle, "'-p', '%s'" % sys.argv[3])
pathlib.Path(sys.argv[2]).write_text(patched)
ast.parse(patched, feature_version=9)
print('patched database argument:', db_needle, '->', "'-d', sys.argv[3]")
print('patched port argument:', port_needle, '->', "'-p', '%s'" % sys.argv[3])
PY
diff "$fx_concurrency" "$fx_logs/correction-concurrency.py" > "$fx_logs/c2b-concurrency-patch.diff" || true
"${fx_env[@]}" "$fx_python" "$fx_logs/correction-concurrency.py" "$fx_pg/psql" "$fx_socket" atomic_fixture_c2b \
 > "$fx_logs/c2b-concurrency.log" 2>&1 || { cat "$fx_logs/c2b-concurrency.log" >&2; fx_fail 'C2: correction concurrency runner failed'; }
/usr/bin/grep -q '7 real contention checks passed' "$fx_logs/c2b-concurrency.log" \
 || fx_fail 'C2: concurrency pass line missing'
fx_note C2 PASS '123 expense accounting runtime assertions passed; 69 expense correction assertions passed; 7 real contention checks passed'
fx_pass 'C2 contracts on bundle-installed databases: 123 accounting assertions, 69 correction assertions, 7 real contention checks'

# ============================================ C3 deliberate late failure rollback
fx_failure_copy=$fx_logs/expense-release-atomic.deliberate-failure.sql
"${fx_env[@]}" "$fx_python" - "$fx_bundle" "$fx_failure_copy" > "$fx_logs/c3-copy.log" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines(keepends=True)
assert len(lines) == 2510, len(lines)
assert lines[-1].rstrip('\n') == 'COMMIT;', lines[-1]
injected = "DO $atomic_fixture_failure$ BEGIN RAISE EXCEPTION 'ATOMIC_FIXTURE: deliberate late failure'; END; $atomic_fixture_failure$;\n"
lines.insert(len(lines) - 1, injected)
pathlib.Path(sys.argv[2]).write_text(''.join(lines))
print('inserted 1 line before the final COMMIT; new line count', len(lines))
PY
diff "$fx_bundle" "$fx_failure_copy" > "$fx_logs/c3-failure-copy.diff" || true
fx_added=$(/usr/bin/grep -c '^> ' "$fx_logs/c3-failure-copy.diff" || true)
fx_removed=$(/usr/bin/grep -c '^< ' "$fx_logs/c3-failure-copy.diff" || true)
[[ "$fx_added" == 1 && "$fx_removed" == 0 ]] \
 || fx_fail "C3: failure copy differs by $fx_removed removed / $fx_added added lines, expected 0/1"

fx_baseline atomic_fixture_c3 seeded "$fx_logs/c3-baseline-load.log"
fx_snapshot atomic_fixture_c3 "$fx_logs/c3-snapshot-S0.json"
# ON_ERROR_STOP=0 so the trailing COMMIT still runs against the aborted transaction.
fx_raw atomic_fixture_c3 postgres 0 "$fx_logs/c3-bundle-failure" -f "$fx_failure_copy" || true
/usr/bin/grep -q 'ATOMIC_FIXTURE: deliberate late failure' "$fx_logs/c3-bundle-failure.err" \
 || fx_fail 'C3: deliberate failure message not observed'
fx_c3_tag=$(fx_last_line "$fx_logs/c3-bundle-failure.out")
[[ "$fx_c3_tag" == 'ROLLBACK' ]] || fx_fail "C3: final COMMIT produced '$fx_c3_tag', expected ROLLBACK"
fx_snapshot atomic_fixture_c3 "$fx_logs/c3-snapshot-S1.json"
cmp "$fx_logs/c3-snapshot-S0.json" "$fx_logs/c3-snapshot-S1.json" \
 || fx_fail 'C3: database changed after the rolled-back install (S1 != S0)'
fx_raw atomic_fixture_c3 postgres 1 "$fx_logs/c3-guard-after" -f "$fx_guard" \
 || fx_fail 'C3: baseline guard no longer passes after rollback'
if fx_raw atomic_fixture_c3 postgres 1 "$fx_logs/c3-postconditions-after" -f "$fx_post"; then
 fx_fail 'C3: postconditions passed after a fully rolled-back install'
fi
fx_c3_post_msg=$(fx_errmsg "$fx_logs/c3-postconditions-after.err" || true)
fx_absent atomic_fixture_c3 'C3 after rollback'
fx_note C3 PASS "final COMMIT -> ROLLBACK; S1==S0; guard passes; postconditions fail with: $fx_c3_post_msg"
fx_pass 'C3 deliberate late failure: transaction ends ROLLBACK, S1==S0 byte-for-byte, baseline guard passes again, postconditions fail, all 11 relations and reimbursement_amount absent'

# ==================================================== C4 drift/partial rejection
fx_drift() { # tag setup-sql expected-message [user] [expected-presence]
 local tag=$1 setup=$2 expected=$3 user=${4:-postgres} presence=${5:-0/0}
 local db=atomic_fixture_$tag
 fx_baseline "$db" seeded "$fx_logs/$tag-baseline-load.log"
 fx_q "$db" -c "$setup" > "$fx_logs/$tag-drift-setup.log" 2>&1 \
  || { cat "$fx_logs/$tag-drift-setup.log" >&2; fx_fail "C4 $tag: drift setup failed"; }
 fx_snapshot "$db" "$fx_logs/$tag-snapshot-S0.json"
 if fx_raw "$db" "$user" 1 "$fx_logs/$tag-bundle-rejected" -f "$fx_bundle"; then
  fx_fail "C4 $tag: frozen bundle was NOT rejected"
 fi
 local bundle_msg guard_msg
 bundle_msg=$(fx_errmsg "$fx_logs/$tag-bundle-rejected.err" || true)
 case "$bundle_msg" in *"$expected"*) ;; *) fx_fail "C4 $tag: expected '$expected', got '$bundle_msg'";; esac
 if fx_raw "$db" "$user" 1 "$fx_logs/$tag-guard-rejected" -f "$fx_guard"; then
  fx_fail "C4 $tag: standalone guard was NOT rejected"
 fi
 guard_msg=$(fx_errmsg "$fx_logs/$tag-guard-rejected.err" || true)
 [[ "$guard_msg" == "$bundle_msg" ]] \
  || fx_fail "C4 $tag: standalone guard message differs ('$guard_msg' vs '$bundle_msg')"
 fx_snapshot "$db" "$fx_logs/$tag-snapshot-S1.json"
 cmp "$fx_logs/$tag-snapshot-S0.json" "$fx_logs/$tag-snapshot-S1.json" \
  || fx_fail "C4 $tag: rejected install still changed the database (S1 != S0)"
 fx_absent "$db" "C4 $tag after rejection" "$presence"
 fx_note "C4$(printf '%s' "${tag#c4}")" PASS "$bundle_msg"
 fx_pass "C4${tag#c4} drift rejected before any migration body ran: $bundle_msg"
}

fx_drift c4a "alter function public.tg_place_expense() set search_path='public'" \
 'Expense release source baseline changed: public.tg_place_expense'
fx_drift c4b "do \$\$ begin create role atomic_drift_owner; exception when duplicate_object then null; end \$\$; alter function public.place_expense(uuid) owner to atomic_drift_owner" \
 'Expense release source baseline changed: public.place_expense'
fx_drift c4c "alter function public.early_clear_expense_line(uuid) rename to early_clear_expense_line_drift" \
 'Expense release source baseline changed: public.early_clear_expense_line'
fx_drift c4d "create table public.expense_accounting_settings(id uuid primary key)" \
 'Expense release baseline is already installed or partially changed' postgres 1/0
fx_drift c4e "create function public.request_expense_accounting_sync(p text) returns void language sql as 'select 1'" \
 'Expense release baseline is already installed or partially changed'
fx_drift c4f "alter table public.expense_batches add column reimbursement_amount numeric" \
 'Expense release baseline is already installed or partially changed' postgres 0/1
fx_drift c4g "do \$\$ begin create role atomic_drift_super superuser login; exception when duplicate_object then null; end \$\$" \
 'Expense release requires the reviewed postgres migration owner' atomic_drift_super
fi

# ============ C5 production-safe read-only postconditions for the live database
if [[ "$fx_only" == all || "$fx_only" == c5 ]]; then
# C5a: bundle-installed database passes, and the whole check rolls back.
fx_baseline atomic_fixture_c5a unseeded "$fx_logs/c5a-baseline-load.log"
fx_raw atomic_fixture_c5a postgres 1 "$fx_logs/c5a-bundle-install" -f "$fx_bundle" \
 || { tail -n 30 "$fx_logs/c5a-bundle-install.log" >&2; fx_fail 'C5a: bundle failed on the unseeded baseline'; }
fx_raw atomic_fixture_c5a postgres 1 "$fx_logs/c5a-production-postconditions" -f "$fx_production_post" \
 || { tail -n 30 "$fx_logs/c5a-production-postconditions.log" >&2; fx_fail 'C5a: production postconditions failed on a bundle-installed database'; }
/usr/bin/grep -q 'Atomic install postconditions passed' "$fx_logs/c5a-production-postconditions.out" \
 || fx_fail 'C5a: production postconditions did not print the pass line'
fx_c5a_tag=$(fx_last_line "$fx_logs/c5a-production-postconditions.out")
[[ "$fx_c5a_tag" == 'ROLLBACK' ]] \
 || fx_fail "C5a: production postconditions ended '$fx_c5a_tag', expected ROLLBACK"
fx_note C5a PASS "Atomic install postconditions passed; read-only transaction ended $fx_c5a_tag"
fx_pass 'C5a production postconditions on a bundle-installed database: pass line printed, read-only transaction ends ROLLBACK'

# C5b: without the bundle the first assertion must reject the database.
fx_baseline atomic_fixture_c5b unseeded "$fx_logs/c5b-baseline-load.log"
if fx_raw atomic_fixture_c5b postgres 1 "$fx_logs/c5b-production-postconditions" -f "$fx_production_post"; then
 fx_fail 'C5b: production postconditions passed on a database without the bundle'
fi
fx_c5b_msg=$(fx_errmsg "$fx_logs/c5b-production-postconditions.err" || true)
case "$fx_c5b_msg" in
 *'ATOMIC_POSTCONDITION: expected all 11 new relations'*) ;;
 *) fx_fail "C5b: expected the 11-relations failure, got '$fx_c5b_msg'";;
esac
fx_note C5b PASS "$fx_c5b_msg"
fx_pass "C5b production postconditions reject an uninstalled database: $fx_c5b_msg"

# C5c: a pre-existing unrelated AR/AP queue row must not look like expense work.
fx_baseline atomic_fixture_c5c seeded "$fx_logs/c5c-baseline-load.log"
fx_raw atomic_fixture_c5c postgres 1 "$fx_logs/c5c-bundle-install" -f "$fx_bundle" \
 || { tail -n 30 "$fx_logs/c5c-bundle-install.log" >&2; fx_fail 'C5c: bundle failed on the seeded baseline'; }
fx_q atomic_fixture_c5c -c "insert into public.accounting_sync_queue(company_id,connection_id,provider,entity_type,entity_id,operation,source_table,source_action,idempotency_key,status) values('79000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000900','quickbooks','invoice','79000000-0000-4000-8000-000000000901','create','invoices','insert','atomic-fixture-unrelated-invoice','pending')" \
 > "$fx_logs/c5c-queue-insert.log" 2>&1 \
 || { cat "$fx_logs/c5c-queue-insert.log" >&2; fx_fail 'C5c: unrelated queue row insert failed'; }
fx_c5c_rows=$(fx_q atomic_fixture_c5c -c "select count(*)||'/'||count(*) filter (where entity_type='expense') from public.accounting_sync_queue")
printf 'C5c accounting_sync_queue total/expense rows = %s\n' "$fx_c5c_rows" > "$fx_logs/c5c-queue-rows.log"
[[ "$fx_c5c_rows" == '1/0' ]] || fx_fail "C5c: expected 1 total / 0 expense queue rows, got $fx_c5c_rows"
fx_raw atomic_fixture_c5c postgres 1 "$fx_logs/c5c-production-postconditions" -f "$fx_production_post" \
 || { tail -n 30 "$fx_logs/c5c-production-postconditions.log" >&2; fx_fail 'C5c: an unrelated AR/AP queue row tripped the production postconditions'; }
/usr/bin/grep -q 'Atomic install postconditions passed' "$fx_logs/c5c-production-postconditions.out" \
 || fx_fail 'C5c: production postconditions did not print the pass line'
fx_note C5c PASS "1 unrelated invoice queue row present ($fx_c5c_rows total/expense); Atomic install postconditions passed"
fx_pass 'C5c production postconditions ignore pre-existing non-expense accounting queue rows'
fi

# ------------------------------------------------------------------- summary.json
"${fx_env[@]}" "$fx_python" - "$fx_logs" "$fx_bundle_sha" "$fx_guard_sha" > "$fx_logs/summary.json" <<'PY'
import datetime, hashlib, json, pathlib, subprocess, sys
logs = pathlib.Path(sys.argv[1])
cases = []
for line in (logs / 'summary.tsv').read_text().splitlines():
    name, status, key = line.split('\t', 2)
    cases.append({'case': name, 'status': status, 'key_output': key})
inputs = {}
for line in (logs / 'source-inputs.log').read_text().splitlines():
    parts = line.split(' ', 1)
    if len(parts) == 2 and len(parts[0]) == 64:
        inputs[parts[1]] = parts[0]
version = subprocess.run(['/opt/homebrew/opt/postgresql@17/bin/psql', '--version'],
                         capture_output=True, text=True).stdout.strip()
payload = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'postgres': version,
    'port': 55495,
    'logs_dir': str(logs),
    'frozen_bundle_sha256': sys.argv[2],
    'baseline_guard_sha256': sys.argv[3],
    'input_sha256': inputs,
    'cases': cases,
    'result_lines': (logs / 'result.txt').read_text().splitlines(),
}
print(json.dumps(payload, indent=2))
PY

printf '\n=== result.txt ===\n'
cat "$fx_logs/result.txt"
