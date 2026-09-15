#!/usr/bin/env python3
"""Prepare read-only catalog assertions from parent-captured evidence; no SQL execution."""
import hashlib
import json
import re
from pathlib import Path

OUT=Path(__file__).resolve().parent
EVIDENCE=Path('/private/tmp/ops-ios-bugs-p9-expense')
catalog=json.loads((EVIDENCE/'live-catalog.json').read_text())
helpers=json.loads((EVIDENCE/'live-helpers.json').read_text())
all_functions=catalog['functions']+helpers
names=[
 'private.get_current_user_id', 'private.get_user_company_id',
 'private.current_user_is_admin', 'private.current_user_scope_for',
 'private.current_user_has_permission', 'public.has_permission',
 'private.enforce_expense_edit_authority', 'public.save_expense_atomic',
 'public.approve_expense_batch', 'public.early_clear_expense_line',
 'public.mark_expense_batch_paid', 'public.unmark_expense_batch_paid',
 'public.recalculate_expense_batch_total', 'public.place_expense', 'public.tg_place_expense',
]
functions=[]
for name in names:
 rows=[f for f in all_functions if f['schema']+'.'+f['proname']==name]
 assert len(rows)==1, (name,len(rows))
 f=rows[0]
 assert f.get('owner','postgres')=='postgres'
 functions.append({'schema':f['schema'],'name':f['proname'],'identityArguments':f['args'],'md5':f['md5'],'owner':'postgres'})

def quote(s): return "'"+s.replace("'","''")+"'"
values=',\n'.join('    ('+', '.join(map(quote,[f['schema'],f['name'],f['identityArguments'],f['md5']]))+')' for f in functions)
# These names are the exact new custody objects inspected in the four sources.
tables=[
 'public.expense_accounting_settings', 'public.expense_accounting_payee_mappings', 'public.expense_accounting_tax_mappings',
 'public.expense_accounting_category_mappings', 'public.expense_accounting_project_mappings',
 'public.expense_accounting_events', 'public.expense_accounting_postings',
 'private.expense_accounting_state', 'private.expense_correction_requests',
 'private.expense_correction_pending', 'private.expense_correction_scope',
]
# Name-based denial deliberately also catches an unexpected overload at a new endpoint.
new_names=[
 'private.lock_expense_approver_context','private.lock_expense_batch_for_approval',
 'private.execute_expense_decision','public.request_expense_accounting_sync',
 'public.retry_expense_accounting_before_write','public.correct_expense_for_review',
 'public.list_expense_corrections','private.derive_expense_reimbursement_amount',
 'private.refresh_expense_reimbursement_amount',
]
# Derive and check all newly declared expense-accounting/correction objects as well.
source_text='\n'.join(p.read_text() for p in sorted((OUT/'constituent-sources').glob('*.sql')))
actual_tables=re.findall(r'(?im)^create table(?: if not exists)? ([\w.]+)',source_text)
assert set(tables)==set(actual_tables),(set(tables)-set(actual_tables),set(actual_tables)-set(tables))
actual_functions=re.findall(r'(?im)^create or replace function ([\w.]+)\(',source_text)
for name in actual_functions:
 if not any(f['schema']+'.'+f['proname']==name for f in all_functions) and name not in new_names:
  new_names.append(name)
assert all(name in actual_functions for name in new_names),set(new_names)-set(actual_functions)
assert not any(f['schema']+'.'+f['proname'] in new_names for f in all_functions)
guard=f'''-- Read-only assertions; also included at the start of the atomic install.
-- Baseline captured {catalog['read_at']} for project {catalog['project_id']}.
-- No catalog assertion is a lock against a parallel privileged DDL release.
DO $expense_release_baseline$
DECLARE
  mismatch text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Expense release requires the reviewed postgres migration owner';
  END IF;
  WITH expected(schema_name,function_name,identity_arguments,expected_md5) AS (VALUES
{values}
  )
  SELECT e.schema_name || '.' || e.function_name INTO mismatch
  FROM expected e
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=e.schema_name
  LEFT JOIN pg_catalog.pg_proc p ON p.pronamespace=n.oid AND p.proname=e.function_name
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)=e.identity_arguments
  WHERE p.oid IS NULL
    OR pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) IS DISTINCT FROM e.expected_md5
    OR pg_catalog.pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
  LIMIT 1;
  IF mismatch IS NOT NULL THEN
    RAISE EXCEPTION 'Expense release source baseline changed: %', mismatch;
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[{','.join(map(quote,tables))}]) AS target(name)
    WHERE pg_catalog.to_regclass(target.name) IS NOT NULL)
  OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname || '.' || p.proname = ANY(ARRAY[{','.join(map(quote,new_names))}]))
  OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expense_batches'::regclass
      AND a.attname='reimbursement_amount' AND NOT a.attisdropped) THEN
    RAISE EXCEPTION 'Expense release baseline is already installed or partially changed';
  END IF;
END;
$expense_release_baseline$;
'''
(OUT/'baseline-guard.sql').write_text(guard)
(OUT/'baseline-preflight-readonly.sql').write_text('BEGIN READ ONLY;\n'+guard+'\nROLLBACK;\n')
(OUT/'baseline-manifest.json').write_text(json.dumps({'capturedAt':catalog['read_at'],'projectId':catalog['project_id'],'functions':functions,'absentRelations':tables,'absentFunctions':new_names,'guardSha256':hashlib.sha256(guard.encode()).hexdigest(),'executed':False},indent=2)+'\n')
print('Prepared baseline assertions for',len(functions),'functions,',len(tables),'absent relations and',len(new_names),'absent function names.')
