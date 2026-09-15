#!/usr/bin/env bash
# Prepared for the parent to execute. One NEW socket-only PG17 cluster; no OPS DB.
set -euo pipefail
umask 077

task_evidence=/private/tmp/ops-ios-bugs-p9-expense
task_candidate=/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p9-expense-release
task_fixes=/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p5-accounting
task_pg=/opt/homebrew/opt/postgresql@17/bin
task_python=/usr/bin/python3
task_port=55494
# Complete allowlist: no inherited credentials, service files, PGOPTIONS,
# Python startup settings, user shell configuration or application environment.
task_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C LC_ALL=C PYTHONDONTWRITEBYTECODE=1)

task_authority=$task_fixes/supabase/migrations/20260912012607_expense_decision_company_authority.sql
task_accounting=$task_fixes/supabase/migrations/20260912203328_expense_accounting_lifecycle.sql
task_accounting_fixture=$task_fixes/tests/sql/expense-accounting-fixture.sql
task_identity=$task_fixes/tests/runtime/expense-identity-lock-concurrency.py
task_sequence=$task_fixes/tests/sql/expense-accounting-sequence-runtime.sql
task_original_authority=$task_evidence/original-authority-migration.sql
task_original_accounting=$task_evidence/original-accounting-migration.sql
task_payroll=$task_candidate/supabase/migrations/20260914200910_expense_payroll_reimbursement_projection.sql
task_correction=$task_candidate/supabase/migrations/20260914214748_expense_admin_correction_review.sql

task_common_before=(
 "$task_candidate/tests/sql/expense-decision-authority-baseline.sql"
 "$task_accounting_fixture"
 "$task_candidate/tests/sql/expense-correction-fixture.sql"
 "$task_candidate/supabase/migrations/20260720024121_expense_atomic_save.sql"
 "$task_candidate/supabase/migrations/20260720024623_fix_expense_batch_recalculation_alias.sql"
)
task_after=(
 "$task_candidate/tests/sql/expense-payroll-projection-live-baseline.sql"
 "$task_payroll"
 "$task_candidate/tests/sql/expense-correction-baseline.sql"
 "$task_correction"
 "$task_correction"
)
task_payroll_files=(
 "$task_candidate/tests/sql/agent-payroll-readiness-setup.sql"
 "$task_candidate/supabase/migrations/20260901190000_agent_payroll_readiness.sql"
 "$task_candidate/tests/sql/expense-payroll-projection-live-baseline.sql"
 "$task_candidate/tests/sql/agent-payroll-readiness-runtime.sql"
 "$task_candidate/tests/sql/expense-payroll-projection-fixture.sql"
 "$task_payroll" "$task_payroll"
 "$task_candidate/tests/sql/expense-payroll-projection-runtime.sql"
)
for task_file in "${task_common_before[@]}" "${task_after[@]}" "${task_payroll_files[@]}" \
 "$task_authority" "$task_accounting" "$task_original_authority" "$task_original_accounting" \
 "$task_identity" "$task_sequence" \
 "$task_candidate/tests/sql/expense-accounting-runtime.sql" \
 "$task_candidate/tests/sql/expense-correction-runtime.sql" \
 "$task_candidate/tests/runtime/expense-correction-concurrency.py"; do
 [[ -r "$task_file" ]] || { printf 'Missing required fixture: %s\n' "$task_file" >&2; exit 1; }
done
for task_binary in "$task_pg/initdb" "$task_pg/pg_ctl" "$task_pg/psql" "$task_pg/createdb" "$task_pg/dropdb" "$task_python"; do
 [[ -x "$task_binary" ]] || { printf 'Missing executable: %s\n' "$task_binary" >&2; exit 1; }
done

# Unique socket directory makes the fixed compatibility-runner port private.
task_scratch=$(mktemp -d "$task_evidence/pg.XXXXXX")
task_logs=$(mktemp -d "$task_evidence/proof.XXXXXX")
mkdir -p "$task_scratch/socket"
: > "$task_scratch/pgpass"
: > "$task_scratch/pg_service.conf"
task_env+=("PGPASSFILE=$task_scratch/pgpass" "PGSERVICEFILE=$task_scratch/pg_service.conf")
task_started=0
cleanup() {
 task_exit=$?
 trap - EXIT
 task_safe_to_remove=1
 if [[ $task_started == 1 ]]; then
  if ! "${task_env[@]}" "$task_pg/pg_ctl" -D "$task_scratch/data" -m immediate -w stop > "$task_logs/stop.log" 2>&1; then
   task_safe_to_remove=0
   printf 'Cluster stop needs inspection; preserving %s\n' "$task_scratch" >&2
   task_exit=1
  fi
 fi
 if [[ $task_safe_to_remove == 1 ]]; then
  case "$task_scratch" in "$task_evidence"/pg.*) rm -rf "$task_scratch";; esac
 fi
 printf 'Verification logs retained: %s\n' "$task_logs"
 exit "$task_exit"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Expense release regression logs: %s\n' "$task_logs"

# Record input hashes and validate Python 3.9 syntax without bytecode output.
"${task_env[@]}" "$task_python" - "$task_identity" "$task_candidate/tests/runtime/expense-correction-concurrency.py" \
 "$task_logs/correction-concurrency.py" "$task_original_authority" "$task_original_accounting" \
 "$task_authority" "$task_accounting" "$task_sequence" "$task_accounting_fixture" "$task_payroll" "$task_correction" \
 > "$task_logs/source-inputs.log" <<'PY'
import ast, hashlib, pathlib, sys
for name in [sys.argv[1],sys.argv[2]]:
    ast.parse(pathlib.Path(name).read_text(), feature_version=9)
source=pathlib.Path(sys.argv[2]).read_text()
needle="'-d', 'postgres'"
assert source.count(needle)==1
# Preserve every test and SQL operation; only inject the disposable DB argument.
pathlib.Path(sys.argv[3]).write_text(source.replace(needle,"'-d', sys.argv[3]"))
ast.parse(pathlib.Path(sys.argv[3]).read_text(), feature_version=9)
for name in [sys.argv[1],sys.argv[2]]+sys.argv[4:]:
    print(hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest(),name)
assert hashlib.sha256(pathlib.Path(sys.argv[4]).read_bytes()).hexdigest()=='93f4d57097e05cda31b993d84445356bde43d21a44cb20acdf9575524d04b939'
assert hashlib.sha256(pathlib.Path(sys.argv[5]).read_bytes()).hexdigest()=='713b56128ac1ce2632ae62ecdb3d90dc5eb2ed09bbdc5db1f235cc0d00523eff'
print('Python 3.9 source parsing and original migration hashes passed')
PY

"${task_env[@]}" "$task_pg/initdb" -D "$task_scratch/data" -A trust --no-locale -E UTF8 -U postgres > "$task_logs/init.log" 2>&1
task_started=1
"${task_env[@]}" "$task_pg/pg_ctl" -D "$task_scratch/data" -l "$task_logs/server.log" \
 -o "-k $task_scratch/socket -p $task_port -c listen_addresses='' -c timezone=UTC -c max_connections=8 -c shared_buffers=32MB -c max_parallel_workers=0" \
 -w start > "$task_logs/start.log" 2>&1

db_query() {
 local task_db=$1; shift
 "${task_env[@]}" "$task_pg/psql" -h "$task_scratch/socket" -p "$task_port" -U postgres -d "$task_db" -X -Atq -v ON_ERROR_STOP=1 -v VERBOSITY=verbose "$@"
}
reset_database() {
 local task_db=$1
 case "$task_db" in expense_release_original|expense_release_repaired) ;; *) printf 'Unsafe disposable DB name\n' >&2; exit 1;; esac
 "${task_env[@]}" "$task_pg/dropdb" -h "$task_scratch/socket" -p "$task_port" -U postgres --if-exists --force "$task_db" >> "$task_logs/database-lifecycle.log" 2>&1
 "${task_env[@]}" "$task_pg/createdb" -h "$task_scratch/socket" -p "$task_port" -U postgres -T template0 -E UTF8 "$task_db" >> "$task_logs/database-lifecycle.log" 2>&1
}
load_stack() {
 local task_db=$1 task_mode=$2 task_log=$3 task_file
 local task_a=$task_authority task_l=$task_accounting
 if [[ "$task_mode" == original ]]; then task_a=$task_original_authority; task_l=$task_original_accounting; fi
 reset_database "$task_db"
 for task_file in "${task_common_before[@]}" "$task_a" "$task_l" "${task_after[@]}"; do
  printf 'Loading %s\n' "$task_file" >> "$task_log"
  db_query "$task_db" -f "$task_file" >> "$task_log" 2>&1 || { tail -n 45 "$task_log"; return 1; }
 done
}
identity() {
 local task_db=$1 task_expect=$2 task_log=$3
 "${task_env[@]}" OPS_EXPENSE_IDENTITY_FIXTURE=1 "$task_python" "$task_identity" \
  --psql "$task_pg/psql" --socket "$task_scratch/socket" --port "$task_port" \
  --database "$task_db" --user postgres --expect "$task_expect" > "$task_log" 2>&1
}
sequence() {
 local task_db=$1 task_repaired=$2 task_log=$3
 db_query "$task_db" -v "expense_sequence_repaired=$task_repaired" -f "$task_sequence" > "$task_log" 2>&1
}

# Identity/ACL red versus green, on separately initialized databases.
load_stack expense_release_original original "$task_logs/original-load.log"
load_stack expense_release_repaired repaired "$task_logs/repaired-load.log"
[[ $(db_query expense_release_repaired -c 'show server_version_num') == 17* ]] || { printf 'Require PG17\n' >&2; exit 1; }
identity expense_release_original vulnerable "$task_logs/identity-original.log" || { cat "$task_logs/identity-original.log"; exit 1; }
sequence expense_release_original false "$task_logs/sequence-original.log" || { cat "$task_logs/sequence-original.log"; exit 1; }
# Negative control: the fixed expectation must detect the original race.
if identity expense_release_original repaired "$task_logs/identity-negative-control.log"; then
 printf 'Identity negative control unexpectedly passed\n' >&2; exit 1
fi
/usr/bin/grep -q 'auth_id withdrawal during actor wait' "$task_logs/identity-negative-control.log"
identity expense_release_repaired repaired "$task_logs/identity-repaired.log" || { cat "$task_logs/identity-repaired.log"; exit 1; }
sequence expense_release_repaired true "$task_logs/sequence-repaired.log" || { cat "$task_logs/sequence-repaired.log"; exit 1; }
cat "$task_logs/identity-original.log" "$task_logs/identity-repaired.log"

# Recreate only our own two database names: existing suites assert global counts.
load_stack expense_release_repaired repaired "$task_logs/p7-load.log"
db_query expense_release_repaired -f "$task_candidate/tests/sql/expense-correction-runtime.sql" > "$task_logs/p7-runtime.log" 2>&1 || { tail -n 45 "$task_logs/p7-runtime.log"; exit 1; }
"${task_env[@]}" "$task_python" "$task_logs/correction-concurrency.py" "$task_pg/psql" "$task_scratch/socket" expense_release_repaired > "$task_logs/p7-concurrency.log" 2>&1 || { cat "$task_logs/p7-concurrency.log"; exit 1; }
/usr/bin/grep -q '69 expense correction assertions passed' "$task_logs/p7-runtime.log"
/usr/bin/grep -q '7 real contention checks passed' "$task_logs/p7-concurrency.log"

load_stack expense_release_original repaired "$task_logs/p5-load.log"
db_query expense_release_original -f "$task_candidate/tests/sql/expense-accounting-runtime.sql" > "$task_logs/p5-runtime.log" 2>&1 || { tail -n 45 "$task_logs/p5-runtime.log"; exit 1; }
/usr/bin/grep -q '123 expense accounting runtime assertions passed' "$task_logs/p5-runtime.log"

# Existing P7 prerequisite and baseline guards still reject changed contracts.
db_query expense_release_original -c "alter function public.tg_place_expense() set search_path='public'" > "$task_logs/drift-setup.log" 2>&1
if db_query expense_release_original -f "$task_correction" > "$task_logs/drift-rejection.log" 2>&1; then
 printf 'Expected correction drift rejection missing\n' >&2; exit 1
fi
/usr/bin/grep -q 'Expense authority or placement changed' "$task_logs/drift-rejection.log"
db_query expense_release_repaired -c 'alter function private.lock_expense_approver_context() rename to test_missing_expense_context' > "$task_logs/prerequisite-setup.log" 2>&1
if db_query expense_release_repaired -f "$task_correction" > "$task_logs/prerequisite-rejection.log" 2>&1; then
 printf 'Expected correction prerequisite rejection missing\n' >&2; exit 1
fi
/usr/bin/grep -q 'Install the P5 expense decision and accounting migrations first' "$task_logs/prerequisite-rejection.log"

# Payroll's existing setup has its own minimal schema, so reuse one clean DB.
reset_database expense_release_original
for task_file in "${task_payroll_files[@]}"; do
 db_query expense_release_original -f "$task_file" >> "$task_logs/payroll-runtime.log" 2>&1 || { tail -n 45 "$task_logs/payroll-runtime.log"; exit 1; }
done
/usr/bin/grep -q '17 payroll reimbursement projection assertions passed' "$task_logs/payroll-runtime.log"

printf '%s\n' \
 'PASS: 9 original identity observations; fixed expectation rejects original code' \
 'PASS: 9 repaired identity observations with unchanged financial state on denial' \
 'PASS: 6 original role sequence calls allowed; 6 repaired calls denied; owner allocation preserved' \
 'PASS: 69 correction assertions and 7 existing correction contention checks' \
 'PASS: 123 existing P5 accounting assertions with P7 installed' \
 'PASS: 2 existing P7 migration guard rejections' \
 'PASS: existing payroll contract and 17 reimbursement projection assertions' \
 | tee "$task_logs/result.txt"
