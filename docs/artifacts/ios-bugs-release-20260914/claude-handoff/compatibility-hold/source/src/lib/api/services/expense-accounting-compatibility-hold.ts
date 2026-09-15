import "server-only";
import type { AccountingSyncQueueService } from "./accounting-sync-queue-service";
import type {
  AccountingSyncQueueEntityType,
  AccountingSyncQueueRow,
} from "./accounting-sync-queue-types";

export interface ExpenseCompatibilityHoldResult {
  queueId: string;
  entityType: "expense";
  entityId: string;
  status: "blocked" | "needs_review";
  error: string;
}

/** Cutover bridge only: always hold expenses, even if an activation flag is set. */
export async function holdExpenseAccountingDuringCutover(input: {
  row: AccountingSyncQueueRow<AccountingSyncQueueEntityType>;
  workerId: string;
  queue: Pick<AccountingSyncQueueService, "markBlocked" | "markNeedsReview">;
}): Promise<ExpenseCompatibilityHoldResult> {
  const { row, workerId, queue } = input;
  if (
    row.entityType !== "expense" ||
    row.sourceTable !== "expense_accounting_events" ||
    row.operation !== "create" ||
    row.status !== "claimed" ||
    row.lockedBy !== workerId
  ) {
    throw new Error("Expense queue ownership or source is invalid.");
  }
  const evidence = [
    row.providerAcceptedAt,
    row.providerRequestId,
    row.externalId,
    row.idempotencyExpiresAt,
  ].some((value) => value != null);
  const error = evidence
    ? "This expense has provider evidence. Reconcile its accounting result before retrying."
    : "Expense accounting sync is paused.";
  if (evidence) {
    await queue.markNeedsReview(row.id, error, { workerId });
  } else {
    await queue.markBlocked(row.id, error, { workerId });
  }
  return {
    queueId: row.id,
    entityType: "expense",
    entityId: row.entityId,
    status: evidence ? "needs_review" : "blocked",
    error,
  };
}
