\set ON_ERROR_STOP on
begin;
insert into public.companies(id) values('79000000-0000-4000-8000-000000000001');
insert into public.users(id,company_id,firebase_uid,is_active,is_company_admin) values
 ('79000000-0000-4000-8000-000000000010','79000000-0000-4000-8000-000000000001','atomic-reviewer',true,true),
 ('79000000-0000-4000-8000-000000000011','79000000-0000-4000-8000-000000000001','atomic-crew',true,false);
insert into public.expense_batches(id,company_id,submitted_by,status,batch_number,amendment_number,total_amount,approved_amount)
 values('79000000-0000-4000-8000-000000000100','79000000-0000-4000-8000-000000000001',
 '79000000-0000-4000-8000-000000000011','partially_approved','ATOMIC-FIXTURE',0,165,140);
insert into public.expenses(id,company_id,submitted_by,batch_id,status,merchant_name,amount,tax_amount,currency,expense_date,payment_method) values
 ('79000000-0000-4000-8000-000000000200','79000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000011','79000000-0000-4000-8000-000000000100','approved','Crew expense',100,0,'CAD',current_date,'personal_card'),
 ('79000000-0000-4000-8000-000000000201','79000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000011','79000000-0000-4000-8000-000000000100','approved','Company expense',40,0,'CAD',current_date,'company_card'),
 ('79000000-0000-4000-8000-000000000202','79000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000011','79000000-0000-4000-8000-000000000100','submitted','Pending expense',25,0,'CAD',current_date,'cash');
commit;
