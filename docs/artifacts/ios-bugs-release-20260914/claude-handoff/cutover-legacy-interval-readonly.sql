-- Read-only. Identify expense approvals committed while the queue-only adapter was serving
-- but before the atomic bundle existed (interval [T2, T3]). Replace :t2 / :t3 with the recorded
-- timestamps. These rows are legacy reconciliation work; they are never auto-queued or replayed.
begin read only;
select e.id, e.company_id, e.status, e.updated_at, b.reviewed_at, e.accounting_sync_status
from public.expenses e
left join public.expense_batches b on b.id = e.batch_id
where e.deleted_at is null
  and e.status in ('approved','reimbursed')
  and e.accounting_sync_id is null
  and (e.updated_at between :t2 and :t3 or b.reviewed_at between :t2 and :t3)
  and not exists (select 1 from private.expense_accounting_state s where s.expense_id = e.id)
order by e.updated_at;
rollback;
