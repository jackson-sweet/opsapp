BEGIN READ ONLY;
-- Read-only assertions; also included at the start of the atomic install.
-- Baseline captured 2026-09-15T03:05:51.671Z for project ijeekuhbatykdomumfjx.
-- No catalog assertion is a lock against a parallel privileged DDL release.
DO $expense_release_baseline$
DECLARE
  mismatch text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Expense release requires the reviewed postgres migration owner';
  END IF;
  WITH expected(schema_name,function_name,identity_arguments,expected_md5) AS (VALUES
    ('private', 'get_current_user_id', '', '127ffd06387933500d95f96aba24b605'),
    ('private', 'get_user_company_id', '', '3de642ffe4b81ee8827c1cc6507f85c4'),
    ('private', 'current_user_is_admin', '', '71fedd6dc3d8226af0b506dcfce72dd8'),
    ('private', 'current_user_scope_for', 'p_permission text', '2ac60f997a0ac6de618bef5ff7aa5592'),
    ('private', 'current_user_has_permission', 'p_permission text, p_min_scope text', '43eb70a695fbf7b8efb38fd40f9c57c3'),
    ('public', 'has_permission', 'p_user_id uuid, p_permission text, p_required_scope text', '2a04ca2eb341948215285025249f48f9'),
    ('private', 'enforce_expense_edit_authority', '', 'a489f4f6506516e5934ff08f8fba69ad'),
    ('public', 'save_expense_atomic', 'p_command jsonb', 'aebfc5e480082b8160de4c6cc4b6fbb3'),
    ('public', 'approve_expense_batch', 'p_batch_id uuid', '87bc087970d0c1fb3f36313836869d66'),
    ('public', 'early_clear_expense_line', 'p_expense_id uuid', '9b271925be5fe9e9ab8c6ca67cf1115c'),
    ('public', 'mark_expense_batch_paid', 'p_batch_id uuid', '0ca6d6ae5d05d8283bcc3bb67b8436b5'),
    ('public', 'unmark_expense_batch_paid', 'p_batch_id uuid', '981f644ded66f43707d800d7400ef6ce'),
    ('public', 'recalculate_expense_batch_total', 'p_batch_id uuid', '8781e28a7a0485dc02b1d06eefcc8a22'),
    ('public', 'place_expense', 'p_expense_id uuid', '69ae7eaa26297db59646c704ea454712'),
    ('public', 'tg_place_expense', '', '2a9d3575dd23507040a31cb49dc69825')
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
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['public.expense_accounting_settings','public.expense_accounting_payee_mappings','public.expense_accounting_tax_mappings','public.expense_accounting_category_mappings','public.expense_accounting_project_mappings','public.expense_accounting_events','public.expense_accounting_postings','private.expense_accounting_state','private.expense_correction_requests','private.expense_correction_pending','private.expense_correction_scope']) AS target(name)
    WHERE pg_catalog.to_regclass(target.name) IS NOT NULL)
  OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname || '.' || p.proname = ANY(ARRAY['private.lock_expense_approver_context','private.lock_expense_batch_for_approval','private.execute_expense_decision','public.request_expense_accounting_sync','public.retry_expense_accounting_before_write','public.correct_expense_for_review','public.list_expense_corrections','private.derive_expense_reimbursement_amount','private.refresh_expense_reimbursement_amount','private.invalidate_expense_accounting_connection_binding','private.enforce_expense_accounting_authority','private.enforce_expense_accounting_related_authority','private.expense_queue_cancelled_before_write','private.cancel_unwritten_expense_reversals','private.queue_expense_accounting_event','private.append_expense_accounting_event','private.capture_expense_accounting_state','private.capture_expense_accounting_change','private.capture_expense_accounting_allocation','public.prepare_expense_accounting_write','public.finalize_expense_accounting_sync','public.save_expense_accounting_settings','private.notify_expense_accounting_review','private.expense_correction_content','private.expense_correction_snapshot','private.immutable_expense_correction','private.correct_expense_for_review','private.list_expense_corrections']))
  OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expense_batches'::regclass
      AND a.attname='reimbursement_amount' AND NOT a.attisdropped) THEN
    RAISE EXCEPTION 'Expense release baseline is already installed or partially changed';
  END IF;
END;
$expense_release_baseline$;

ROLLBACK;
