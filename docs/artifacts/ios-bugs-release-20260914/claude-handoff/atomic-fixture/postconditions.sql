do $atomic_postconditions$
declare v_count integer; v_role text; v_sequence regclass;
begin
 select count(*) into v_count from unnest(array[
 'public.expense_accounting_settings','public.expense_accounting_payee_mappings','public.expense_accounting_tax_mappings',
 'public.expense_accounting_category_mappings','public.expense_accounting_project_mappings','public.expense_accounting_events',
 'public.expense_accounting_postings','private.expense_accounting_state','private.expense_correction_requests',
 'private.expense_correction_pending','private.expense_correction_scope']) r(name) where to_regclass(r.name) is not null;
 if v_count<>11 then raise exception 'ATOMIC_POSTCONDITION: expected all 11 new relations'; end if;
 if not exists(select 1 from public.expense_batches where id='79000000-0000-4000-8000-000000000100'
   and reimbursement_amount=100 and total_amount=165 and approved_amount=140 and paid_at is null and paid_by is null) then
   raise exception 'ATOMIC_POSTCONDITION: crew-only projection or payment markers changed';
 end if;
 if exists(select 1 from public.expense_accounting_events) or exists(select 1 from private.expense_accounting_state)
   or exists(select 1 from public.accounting_sync_queue) or exists(select 1 from private.expense_correction_requests) then
   raise exception 'ATOMIC_POSTCONDITION: installation generated financial/correction work';
 end if;
 if md5(pg_get_functiondef('public.read_agent_payroll_readiness_as_system(uuid,uuid,uuid,uuid,text,text[],text,text,text,text,text,timestamp with time zone,date,integer,integer,integer,integer)'::regprocedure))
   <> 'f2e32a360886d5fed5040c5eb99b76c6' then raise exception 'ATOMIC_POSTCONDITION: payroll replacement missing'; end if;
 if md5(pg_get_functiondef('private.enforce_expense_edit_authority()'::regprocedure))<>'d342596cd9e55adf458239a7025dfeaa'
   or md5(pg_get_functiondef('public.tg_place_expense()'::regprocedure))<>'258dc02efee98372f6205e731ac0251f'
   or md5(pg_get_functiondef('public.place_expense(uuid)'::regprocedure))<>'5d3a1254421fc4378f9b9a32d4cc3bd5' then
   raise exception 'ATOMIC_POSTCONDITION: correction authority/placement replacement missing';
 end if;
 if to_regprocedure('public.request_expense_accounting_sync(uuid,uuid)') is null
   or to_regprocedure('public.retry_expense_accounting_before_write(uuid,uuid)') is null
   or to_regprocedure('private.lock_expense_approver_context()') is null then
   raise exception 'ATOMIC_POSTCONDITION: earlier migration functions missing';
 end if;
 if not has_function_privilege('authenticated','public.correct_expense_for_review(jsonb)','EXECUTE')
   or not has_function_privilege('authenticated','private.correct_expense_for_review(jsonb)','EXECUTE')
   or not has_function_privilege('authenticated','public.list_expense_corrections(uuid,uuid)','EXECUTE') then
   raise exception 'ATOMIC_POSTCONDITION: authenticated correction access missing';
 end if;
 foreach v_role in array array['anon','service_role'] loop
   if has_function_privilege(v_role,'public.correct_expense_for_review(jsonb)','EXECUTE')
     or has_function_privilege(v_role,'public.list_expense_corrections(uuid,uuid)','EXECUTE') then
     raise exception 'ATOMIC_POSTCONDITION: unapproved correction grant for %',v_role;
   end if;
 end loop;
 v_sequence:=pg_get_serial_sequence('public.expense_accounting_events','sequence')::regclass;
 if v_sequence is null then raise exception 'ATOMIC_POSTCONDITION: identity sequence missing'; end if;
 foreach v_role in array array['anon','authenticated','service_role'] loop
   if has_sequence_privilege(v_role,v_sequence,'USAGE,SELECT,UPDATE') then
     raise exception 'ATOMIC_POSTCONDITION: sequence grant retained for %',v_role;
   end if;
 end loop;
end;
$atomic_postconditions$;
select 'Atomic install postconditions passed';
