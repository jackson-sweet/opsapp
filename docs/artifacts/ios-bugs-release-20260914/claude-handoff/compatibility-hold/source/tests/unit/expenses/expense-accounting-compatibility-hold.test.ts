import { afterEach, describe, expect, it, vi } from "vitest";
import { holdExpenseAccountingDuringCutover } from "@/lib/api/services/expense-accounting-compatibility-hold";
import type { AccountingSyncQueueRow } from "@/lib/api/services/accounting-sync-queue-types";

const row: AccountingSyncQueueRow<"expense"> = {
  id: "queue", companyId: "company", connectionId: "connection",
  provider: "quickbooks", entityType: "expense", entityId: "expense",
  operation: "create", sourceTable: "expense_accounting_events", sourceAction: "insert",
  sourceUpdatedAt: null, idempotencyKey: "event:connection", status: "claimed",
  attempts: 1, maxAttempts: 5, runAfter: "2026-09-14T00:00:00Z",
  lockedAt: "2026-09-14T00:00:00Z", lockedBy: "worker",
  externalId: null, providerRequestId: null, providerAcceptedAt: null,
  idempotencyExpiresAt: null, lastError: null,
  payloadSnapshot: { eventId: "event", providerEnvironment: "production", providerIdentitySnapshot: "identity" },
  createdAt: "2026-09-14T00:00:00Z", updatedAt: "2026-09-14T00:00:00Z",
};
const queue = () => ({ markBlocked: vi.fn(), markNeedsReview: vi.fn() });
afterEach(() => vi.unstubAllEnvs());
describe("expense cutover bridge", () => {
  it.each([undefined, "false", "true"])("always holds when activation is %s", async (value) => {
    vi.stubEnv("EXPENSE_ACCOUNTING_WRITE_ENABLED", value);
    for (const provider of ["quickbooks", "sage"] as const) {
      const custody = queue();
      const input = { ...row, provider };
      const original = structuredClone(input);
      const result = await holdExpenseAccountingDuringCutover({ row: input, workerId: "worker", queue: custody });
      expect(result.status).toBe("blocked");
      expect(custody.markBlocked).toHaveBeenCalledWith("queue", "Expense accounting sync is paused.", { workerId: "worker" });
      expect(custody.markNeedsReview).not.toHaveBeenCalled();
      expect(input).toEqual(original);
    }
  });
  it.each(["externalId", "providerAcceptedAt", "providerRequestId", "idempotencyExpiresAt"] as const)("keeps %s for reconciliation", async (field) => {
    const custody = queue();
    const input = { ...row, [field]: "evidence" };
    const original = structuredClone(input);
    expect((await holdExpenseAccountingDuringCutover({ row: input, workerId: "worker", queue: custody })).status).toBe("needs_review");
    expect(custody.markBlocked).not.toHaveBeenCalled();
    expect(custody.markNeedsReview).toHaveBeenCalledOnce();
    expect(input).toEqual(original);
  });
  it.each([{ lockedBy: "other" }, { sourceTable: "expenses" }, { status: "blocked" as const }, { operation: "update" as const }])("rejects invalid ownership or source %s", async (invalid) => {
    const custody = queue();
    await expect(holdExpenseAccountingDuringCutover({ row: { ...row, ...invalid }, workerId: "worker", queue: custody })).rejects.toThrow(/ownership/i);
    expect(custody.markBlocked).not.toHaveBeenCalled();
    expect(custody.markNeedsReview).not.toHaveBeenCalled();
  });
  it.each([false, true])("propagates failed guarded persistence with evidence=%s", async (evidence) => {
    const custody = queue();
    custody.markBlocked.mockRejectedValue(new Error("hold failed"));
    custody.markNeedsReview.mockRejectedValue(new Error("hold failed"));
    await expect(holdExpenseAccountingDuringCutover({ row: { ...row, externalId: evidence ? "accepted" : null }, workerId: "worker", queue: custody })).rejects.toThrow("hold failed");
    expect(custody.markBlocked.mock.calls.length + custody.markNeedsReview.mock.calls.length).toBe(1);
  });
});
