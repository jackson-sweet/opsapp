-- Read-only preflight for the UNINSTALLED four-expense-migration baseline.
-- Compare every row with the retained audit. Any changed hash/object/ACL needs
-- review, and this snapshot is not a cutover lock or deployment authorization.
begin read only;
select clock_timestamp() observed_at,current_database() database;
with expected(schema_name,function_name,identity_arguments,expected_md5) as (values
('private','agent_p2_expense_assigned_approver_v1','p_actor_user_id uuid, p_company_id uuid, p_expense_id uuid','d86420383942ee9ad9098bfd422f5328'),
('private','agent_p2_expense_attention_v1','p_actor_user_id uuid, p_company_id uuid, p_permission_snapshot_revision text, p_registered_permission_keys text[], p_authorization_candidate jsonb, p_read_at timestamp with time zone, p_limit integer, p_source_limit integer','c6ab5d962f54e00374a539c8444e2063'),
('private','agent_p2_expense_batch_assigned_approver_v1','p_actor_user_id uuid, p_company_id uuid, p_batch_id uuid','a4e17e750b2307774d323edd5bb65ae8'),
('private','agent_p2_expense_batch_item_v1','p_company_id uuid, p_batch_id uuid, p_for_list boolean','60af91ded5727c05bab941e6daa914b6'),
('private','agent_p2_expense_context_v1','p_request_id text, p_company_id uuid, p_actor_user_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_registered_permission_keys text[], p_capability_manifest_revision text, p_capability_id text, p_capability_revision text, p_authorization_candidate jsonb, p_expense_id uuid, p_source_limit integer, p_allocation_limit integer, p_allocation_fetch_limit integer, p_review_reason_character_limit integer','84b9669704c49ab69b4cdfb56d4bfc3f'),
('private','agent_p2_expense_expected_candidate_v1','p_variant text, p_permissions jsonb','acdfd108706dfc836efcbd9dcda3900a'),
('private','agent_p2_expense_hash_ref','p_prefix text, p_material jsonb','2359fed54fcc2d7c7211cc82af957afe'),
('private','agent_p2_expense_item_v1','p_company_id uuid, p_expense_id uuid, p_project_filter uuid, p_allocation_limit integer','aca5c5bc148e6b4cb14d45b251462e85'),
('private','agent_p2_expense_list_v1','p_request_id text, p_company_id uuid, p_actor_user_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_registered_permission_keys text[], p_capability_manifest_revision text, p_capability_id text, p_capability_revision text, p_authorization_candidate jsonb, p_view_kind text, p_project_id uuid, p_batch_disposition text, p_item_limit integer, p_page_fetch_limit integer, p_source_limit integer, p_cursor_read_at timestamp with time zone, p_cursor_source_revisions jsonb, p_after_order_date date, p_after_id uuid','30ad0163887e54a975fc95158a96c124'),
('private','agent_p2_expense_money_v1','p_amount numeric, p_currency text','1d85363fd41059e7468026597241012f'),
('private','agent_p2_expense_project_assigned_v1','p_actor_user_id uuid, p_company_id uuid, p_project_id uuid','cf2f70ea6c875a828fafda02a97c4073'),
('private','agent_p2_expense_proof_candidate_v1','p_candidate jsonb','5f110afe75c8f2f2b1d09ed970f0513c'),
('private','agent_p2_expense_read_context_v1','p_actor_user_id uuid, p_company_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_registered_permission_keys text[], p_authorization_candidate jsonb, p_expected_variant text','d1d60547ce892cc8c451b3d90d5b71fe'),
('private','bump_agent_artifact_expense_allocation_revision','','7c0c5e8739ebeba5f6648bc0554f2e64'),
('private','bump_agent_expense_source_revision','','f92b48861a589cfd079e400cf96f1114'),
('private','current_user_has_permission','p_permission text, p_min_scope text','43eb70a695fbf7b8efb38fd40f9c57c3'),
('private','current_user_is_admin','','71fedd6dc3d8226af0b506dcfce72dd8'),
('private','current_user_scope_for','p_permission text','2ac60f997a0ac6de618bef5ff7aa5592'),
('private','enforce_expense_edit_authority','','a489f4f6506516e5934ff08f8fba69ad'),
('private','expense_atomic_response','p_expense_id uuid','b4be82b8e6f397b72f2f93cba3e8ab2b'),
('private','get_current_user_id','','127ffd06387933500d95f96aba24b605'),
('private','get_user_company_id','','3de642ffe4b81ee8827c1cc6507f85c4'),
('private','run_expense_envelope_sweep_controlled','','07af8c47c18cacf46dcc3032722c208a'),
('private','set_expense_updated_at','','24546a8c51b36ec977e1624355fc6869'),
('private','touch_expense_from_allocation','','f4f2109685a5184bf9c1dcfe34d59b9f'),
('public','approve_expense_batch','p_batch_id uuid','87bc087970d0c1fb3f36313836869d66'),
('public','early_clear_expense_line','p_expense_id uuid','9b271925be5fe9e9ab8c6ca67cf1115c'),
('public','expense_envelope_period','p_expense_date date, p_review_frequency text','f2245029594013ed33ff380558f11f8a'),
('public','expense_envelope_sweep','','aa4be69a2553c815cf242bbd7b43f684'),
('public','get_next_expense_batch_number','p_company_id uuid','86c77a0cca8a84efcc445dc6849a56db'),
('public','get_user_company_id','','ba0586ac430c84e355a72cce703d6142'),
('public','mark_expense_batch_paid','p_batch_id uuid','0ca6d6ae5d05d8283bcc3bb67b8436b5'),
('public','notify_expense_batch_decision','p_batch_id uuid, p_decision text, p_count integer','238f41d9b847c97637aa9271639d97e1'),
('public','place_expense','p_expense_id uuid','69ae7eaa26297db59646c704ea454712'),
('public','read_agent_expense_context_as_system','p_request_id text, p_company_id uuid, p_actor_user_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_registered_permission_keys text[], p_capability_manifest_revision text, p_capability_id text, p_capability_revision text, p_authorization_candidate jsonb, p_expense_id uuid, p_source_limit integer, p_allocation_limit integer, p_allocation_fetch_limit integer, p_review_reason_character_limit integer','81fceedc09b6186a95f9359b83ad492c'),
('public','read_agent_expenses_as_system','p_request_id text, p_company_id uuid, p_actor_user_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_registered_permission_keys text[], p_capability_manifest_revision text, p_capability_id text, p_capability_revision text, p_authorization_candidate jsonb, p_view_kind text, p_project_id uuid, p_batch_disposition text, p_item_limit integer, p_page_fetch_limit integer, p_source_limit integer, p_cursor_read_at timestamp with time zone, p_cursor_source_revisions jsonb, p_after_order_date date, p_after_id uuid','060c97af0a09959342611677924df837'),
('public','recalculate_expense_batch_total','p_batch_id uuid','8781e28a7a0485dc02b1d06eefcc8a22'),
('public','save_expense_atomic','p_command jsonb','aebfc5e480082b8160de4c6cc4b6fbb3'),
('public','tg_place_expense','','2a9d3575dd23507040a31cb49dc69825'),
('public','unmark_expense_batch_paid','p_batch_id uuid','981f644ded66f43707d800d7400ef6ce'),
('private','bump_agent_read_domain_revision','','5a32a1da0b91d3e8e0b5c55a9ca3d52d'),
('private','guard_financial_document_distribution','','2055ba36169a4a4878fb404e6e32e6eb'),
('public','has_permission','p_user_id uuid, p_permission text, p_required_scope text','2a04ca2eb341948215285025249f48f9'),
('public','read_agent_payroll_readiness_as_system','p_actor_user_id uuid, p_company_id uuid, p_oauth_grant_id uuid, p_oauth_client_id uuid, p_grant_revision text, p_granted_scope_ceiling text[], p_permission_snapshot_revision text, p_capability_manifest_revision text, p_exposure_revision text, p_capability_id text, p_capability_revision text, p_observed_at timestamp with time zone, p_target_date date, p_recurring_obligation_limit integer, p_reimbursement_batch_limit integer, p_receivable_limit integer, p_payer_history_limit integer','c3e517bcc781f6866601c5966fa0b58d'),
('private','effective_permission_scope_for_user','p_actor_user_id uuid, p_actor_company_id uuid, p_permission text','71379de17663ca1354d7f18f8a2e61cb'),
('private','raw_permission_scope_for_user','p_actor_user_id uuid, p_actor_company_id uuid, p_permission text','95f8357783737b3e9f6d73dd42dfa96a'),
('private','user_is_company_admin','p_actor_user_id uuid, p_actor_company_id uuid','fdd51485e950e4540c5777845e98c6a1'),
('public','get_or_create_open_batch','p_company_id uuid, p_submitted_by uuid, p_period_start date, p_period_end date, p_scope_project_id uuid','243314b13e3a19dc91787eee29b1de6d')
)
select e.*,md5(pg_get_functiondef(p.oid)) actual_md5,
  coalesce(md5(pg_get_functiondef(p.oid))=e.expected_md5,false) matches,
  p.proacl::text acl,p.prosecdef security_definer,p.proconfig
from expected e left join pg_namespace n on n.nspname=e.schema_name
left join pg_proc p on p.pronamespace=n.oid and p.proname=e.function_name
 and pg_get_function_identity_arguments(p.oid)=e.identity_arguments
order by e.schema_name,e.function_name,e.identity_arguments;

select clock_timestamp() observed_at,
 (select jsonb_agg(jsonb_build_object('provider',provider,'status',status,'count',n) order by provider,status) from (select provider,status,count(*) n from public.accounting_sync_queue where status not in ('succeeded','cancelled') group by provider,status) s) nonterminal_queue,
 (select jsonb_agg(jsonb_build_object('provider',provider,'count',n) order by provider) from (select provider,count(*) n from public.accounting_connections where is_connected and sync_enabled and sync_direction in ('push_only','bidirectional') group by provider) s) eligible_expense_push,
 (select count(*) from supabase_migrations.schema_migrations where version in ('20260912012607','20260912203328','20260914200910','20260914214748')) prepared_migration_ledger_count,
 (select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and (c.relname like 'expense_accounting_%' or c.relname like 'expense_correction_%')) partial_relations,
 (select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'args',pg_get_function_identity_arguments(p.oid)) order by n.nspname,p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and (p.proname like '%expense_accounting%' or p.proname like '%expense_correction%' or p.proname in ('correct_expense_for_review','list_expense_corrections','lock_expense_approver_context','lock_expense_batch_for_approval','execute_expense_decision','derive_expense_reimbursement_amount','refresh_expense_reimbursement_amount'))) partial_functions;

select count(*) claimed,count(*) filter(where provider_accepted_at is not null) accepted_claims
from public.accounting_sync_queue where status='claimed';
select count(*) legacy_export_evidence from public.expenses
where accounting_sync_id is not null or accounting_synced_at is not null or accounting_sync_status='synced';
select count(*) mixed_company,count(*) filter(where e.submitted_by is distinct from b.submitted_by) also_mixed_submitter
from public.expenses e join public.expense_batches b on b.id=e.batch_id
where e.company_id is distinct from b.company_id;
select count(*) mixed_submitter from public.expenses e join public.expense_batches b on b.id=e.batch_id
where e.submitted_by is distinct from b.submitted_by;
select count(*) asymmetric_paid_markers from public.expense_batches where (paid_at is null)<>(paid_by is null);
select exists(select 1 from information_schema.columns where table_schema='public' and table_name='expense_batches' and column_name='reimbursement_amount') unexpected_projection_column;
select role,has_schema_privilege(role,'private','USAGE') private_usage
from unnest(array['anon','authenticated','service_role']) role;
select n.nspname schema,r.rolname creator,d.defaclobjtype::text object_type,d.defaclacl::text acl
from pg_default_acl d join pg_roles r on r.oid=d.defaclrole
left join pg_namespace n on n.oid=d.defaclnamespace
where n.nspname in ('public','private') order by 1,2,3;
commit;
