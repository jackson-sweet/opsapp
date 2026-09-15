#!/usr/bin/env python3
"""Prepare an isolated patch on exact production; never apply or deploy it."""
import difflib
import hashlib
import json
import subprocess
from pathlib import Path

OUT=Path(__file__).resolve().parent
REPO=Path('/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p9-expense-release')
BASE='b5b0cb59275f0addf923db608b1daeac4afca844'
QBO='src/app/api/cron/accounting/quickbooks/push-queue/route.ts'
SAGE='src/app/api/cron/accounting/sage/push-queue/route.ts'
TYPES='src/lib/api/services/accounting-sync-queue-types.ts'
HELPER='src/lib/api/services/expense-accounting-compatibility-hold.ts'
TEST='tests/unit/expenses/expense-accounting-compatibility-hold.test.ts'

def original(path):
    return subprocess.check_output(['git','-C',str(REPO),'show',f'{BASE}:{path}'],stderr=subprocess.DEVNULL).decode()

helper='''import "server-only";
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
'''
qbo=original(QBO)
needle='  if (isSupplierBillQueueEntity(row.entityType as string)) {'
assert qbo.count(needle)==1
qbo=qbo.replace(needle,'''  if ((row.entityType as string) === "expense") {
    return holdExpenseAccountingDuringCutover({ row, workerId, queue });
  }

'''+needle)
qbo='import { holdExpenseAccountingDuringCutover } from "@/lib/api/services/expense-accounting-compatibility-hold";\n'+qbo
sage=original(SAGE)
needle='            if (isSupplierBillQueueEntity(row.entityType)) {'
assert sage.count(needle)==1
sage=sage.replace(needle,'''            if ((row.entityType as string) === "expense") {
              results.push(
                await holdExpenseAccountingDuringCutover({ row, workerId, queue })
              );
            } else if (isSupplierBillQueueEntity(row.entityType)) {''')
sage=sage.replace('type SagePushQueueResult = SageQueueResult | SupplierBillQueueResult;', '''type SagePushQueueResult =
  | SageQueueResult
  | SupplierBillQueueResult
  | ExpenseCompatibilityHoldResult;''')
sage='''import {
  holdExpenseAccountingDuringCutover,
  type ExpenseCompatibilityHoldResult,
} from "@/lib/api/services/expense-accounting-compatibility-hold";
'''+sage
types=original(TYPES)
needle='  | SupplierBillSyncEntityType;'
assert types.count(needle)==1
types=types.replace(needle,'  | SupplierBillSyncEntityType\n  | "expense";')
tests='''import { afterEach, describe, expect, it, vi } from "vitest";
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
'''
files={QBO:qbo,SAGE:sage,TYPES:types,HELPER:helper,TEST:tests}
for path in ['tests/integration/qbo-push-queue-route.test.ts','tests/integration/sage-push-queue-route.test.ts']:
    files[path]=(REPO/path).read_text()
manifest={'prepareOnly':True,'productionBase':BASE,'files':[],'executedTests':False,'deployed':False}
patch=[]
for path, body in files.items():
    try: old=original(path)
    except subprocess.CalledProcessError: old=''
    dest=OUT/'source'/path
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(body)
    if old:
        dest=OUT/'base-check'/path
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_text(old)
    patch.append('diff --git a/'+path+' b/'+path+'\n')
    if not old: patch.append('new file mode 100644\n')
    patch.extend(difflib.unified_diff(old.splitlines(keepends=True),body.splitlines(keepends=True),fromfile='a/'+path if old else '/dev/null',tofile='b/'+path))
    manifest['files'].append({'path':path,'baseSha256':hashlib.sha256(old.encode()).hexdigest() if old else None,'preparedSha256':hashlib.sha256(body.encode()).hexdigest()})
patch=''.join(patch)
(OUT/'production-compatibility-hold.patch').write_text(patch)
manifest['patchSha256']=hashlib.sha256(patch.encode()).hexdigest()
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'files':len(files),'patchSha256':manifest['patchSha256']}))
