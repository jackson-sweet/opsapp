import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// QuickBooks API base URLs
const QB_API_BASE = "https://quickbooks.api.intuit.com/v3";
// Sage API base URL
const SAGE_API_BASE = "https://api.accounting.sage.com/v3.1";

const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 1000;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: authUser } } = await supabaseAdmin.auth.getUser(token);
    if (!authUser) throw new Error("Unauthorized");

    const { expenseId, companyId } = await req.json();
    if (!expenseId || !companyId) {
      return jsonResponse({ error: "expenseId and companyId are required" }, 400);
    }

    // Fetch the expense with allocations and category
    const { data: expense, error: expError } = await supabaseAdmin
      .from("expenses")
      .select("*, expense_project_allocations(*), expense_categories(*)")
      .eq("id", expenseId)
      .single();

    if (expError || !expense) {
      return jsonResponse({ error: "Expense not found" }, 404);
    }

    if (expense.status !== "approved") {
      return jsonResponse({ error: "Only approved expenses can be synced" }, 400);
    }

    // Fetch active accounting connections for this company
    const { data: connections } = await supabaseAdmin
      .from("accounting_connections")
      .select("*")
      .eq("company_id", companyId)
      .eq("is_connected", true)
      .eq("sync_enabled", true);

    if (!connections || connections.length === 0) {
      // No active connection — mark as pending
      await supabaseAdmin
        .from("expenses")
        .update({ accounting_sync_status: "pending" })
        .eq("id", expenseId);
      return jsonResponse({ status: "pending", message: "No active accounting connection" });
    }

    // Sync to each connected provider
    const results: Record<string, unknown> = {};
    for (const conn of connections) {
      try {
        // Refresh token if expired
        const accessToken = await ensureFreshToken(conn);

        // Fetch category mapping
        const categoryMapping = await getCategoryMapping(
          companyId,
          conn.provider,
          expense.category_id
        );

        if (conn.provider === "quickbooks") {
          results.quickbooks = await syncToQuickBooks(
            expense,
            accessToken,
            conn.realm_id,
            categoryMapping
          );
        } else if (conn.provider === "sage") {
          results.sage = await syncToSage(
            expense,
            accessToken,
            categoryMapping
          );
        }
      } catch (syncErr) {
        results[conn.provider] = { error: (syncErr as Error).message };
      }
    }

    // Check if any provider succeeded
    const anySuccess = Object.values(results).some(
      (r: any) => r && !r.error
    );

    const syncStatus = anySuccess ? "synced" : "error";
    const syncId = anySuccess
      ? JSON.stringify(results)
      : null;

    await supabaseAdmin
      .from("expenses")
      .update({
        accounting_sync_status: syncStatus,
        accounting_sync_id: syncId,
      })
      .eq("id", expenseId);

    // Log the sync
    for (const [provider, result] of Object.entries(results)) {
      await supabaseAdmin.from("accounting_sync_log").insert({
        company_id: companyId,
        provider,
        direction: "outbound",
        entity_type: "expense",
        entity_id: expenseId,
        external_id: (result as any)?.id ?? null,
        status: (result as any)?.error ? "error" : "success",
        details: (result as any)?.error ?? "Expense synced successfully",
      });
    }

    return jsonResponse({ status: syncStatus, results });
  } catch (err) {
    return jsonResponse({ error: (err as Error).message }, 400);
  }
});

// --- Ensure token is fresh ---
async function ensureFreshToken(conn: any): Promise<string> {
  const expiresAt = new Date(conn.token_expires_at);
  const now = new Date();
  // Refresh if token expires within 5 minutes
  if (expiresAt.getTime() - now.getTime() < 5 * 60 * 1000) {
    // Call the accounting-oauth function to refresh
    const refreshResponse = await fetch(
      `${SUPABASE_URL}/functions/v1/accounting-oauth`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({
          action: "refresh",
          provider: conn.provider,
          companyId: conn.company_id,
        }),
      }
    );

    if (!refreshResponse.ok) {
      throw new Error(`Token refresh failed for ${conn.provider}`);
    }

    const refreshData = await refreshResponse.json();
    return refreshData.accessToken;
  }

  return conn.access_token;
}

// --- Get category mapping ---
async function getCategoryMapping(
  companyId: string,
  provider: string,
  categoryId: string | null
): Promise<{ externalAccountId: string; externalAccountName: string } | null> {
  if (!categoryId) return null;

  const { data } = await supabaseAdmin
    .from("accounting_category_mappings")
    .select("external_account_id, external_account_name")
    .eq("company_id", companyId)
    .eq("provider", provider)
    .eq("expense_category_id", categoryId)
    .single();

  if (data) {
    return {
      externalAccountId: data.external_account_id,
      externalAccountName: data.external_account_name,
    };
  }
  return null;
}

// --- QuickBooks Sync ---
async function syncToQuickBooks(
  expense: any,
  accessToken: string,
  realmId: string,
  categoryMapping: { externalAccountId: string; externalAccountName: string } | null
): Promise<any> {
  // Build the QBO Purchase object
  const purchaseBody: any = {
    PaymentType: mapPaymentType(expense.payment_method),
    TotalAmt: expense.amount,
    TxnDate: expense.expense_date,
    PrivateNote: expense.description || "",
    Line: [
      {
        Amount: expense.amount,
        DetailType: "AccountBasedExpenseLineDetail",
        AccountBasedExpenseLineDetail: {
          AccountRef: categoryMapping
            ? { value: categoryMapping.externalAccountId, name: categoryMapping.externalAccountName }
            : { value: "1", name: "Uncategorized Expenses" },
        },
      },
    ],
  };

  // Add vendor reference if merchant name exists
  if (expense.merchant_name) {
    const vendorRef = await findOrCreateQBVendor(
      accessToken,
      realmId,
      expense.merchant_name
    );
    purchaseBody.EntityRef = vendorRef;
  }

  // Add project/customer refs from allocations
  if (expense.expense_project_allocations?.length > 0) {
    const allocation = expense.expense_project_allocations[0];
    if (allocation.project_id) {
      // Map project to QBO CustomerRef for job costing
      purchaseBody.Line[0].AccountBasedExpenseLineDetail.CustomerRef = {
        value: allocation.project_id,
      };
    }
  }

  // Set AccountRef for the payment account based on payment method
  purchaseBody.AccountRef = getQBPaymentAccountRef(expense.payment_method);

  return await retryableFetch(
    `${QB_API_BASE}/company/${realmId}/purchase`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify(purchaseBody),
    }
  );
}

function mapPaymentType(paymentMethod: string): string {
  switch (paymentMethod) {
    case "cash": return "Cash";
    case "personal_card":
    case "company_card": return "CreditCard";
    default: return "Cash";
  }
}

function getQBPaymentAccountRef(paymentMethod: string): { value: string; name: string } {
  // These are placeholder account IDs — companies map their own accounts
  switch (paymentMethod) {
    case "company_card":
      return { value: "41", name: "Company Credit Card" };
    case "personal_card":
      return { value: "42", name: "Employee Reimbursable" };
    default:
      return { value: "35", name: "Cash" };
  }
}

async function findOrCreateQBVendor(
  accessToken: string,
  realmId: string,
  displayName: string
): Promise<{ value: string; name: string }> {
  // Search for existing vendor
  const searchUrl = `${QB_API_BASE}/company/${realmId}/query?query=${encodeURIComponent(
    `SELECT * FROM Vendor WHERE DisplayName = '${displayName.replace(/'/g, "\\'")}'`
  )}`;

  const searchResp = await fetch(searchUrl, {
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Accept": "application/json",
    },
  });

  if (searchResp.ok) {
    const searchData = await searchResp.json();
    const vendors = searchData?.QueryResponse?.Vendor;
    if (vendors?.length > 0) {
      return { value: vendors[0].Id, name: vendors[0].DisplayName };
    }
  }

  // Create new vendor
  const createResp = await fetch(
    `${QB_API_BASE}/company/${realmId}/vendor`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({ DisplayName: displayName }),
    }
  );

  if (createResp.ok) {
    const createData = await createResp.json();
    return {
      value: createData.Vendor.Id,
      name: createData.Vendor.DisplayName,
    };
  }

  // Fallback: return placeholder
  return { value: "0", name: displayName };
}

// --- Sage Sync ---
async function syncToSage(
  expense: any,
  accessToken: string,
  categoryMapping: { externalAccountId: string; externalAccountName: string } | null
): Promise<any> {
  // Find or create contact for merchant
  let contactId: string | null = null;
  if (expense.merchant_name) {
    contactId = await findOrCreateSageContact(accessToken, expense.merchant_name);
  }

  const paymentBody: any = {
    other_payment: {
      transaction_date: expense.expense_date,
      total_amount: expense.amount,
      payment_lines: [
        {
          ledger_account_id: categoryMapping?.externalAccountId ?? null,
          total_amount: expense.amount,
          tax_amount: expense.tax_amount ?? 0,
          description: expense.description || expense.merchant_name || "Expense",
        },
      ],
    },
  };

  if (contactId) {
    paymentBody.other_payment.contact_id = contactId;
  }

  return await retryableFetch(
    `${SAGE_API_BASE}/other_payments`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify(paymentBody),
    }
  );
}

async function findOrCreateSageContact(
  accessToken: string,
  name: string
): Promise<string | null> {
  // Search for existing contact
  const searchResp = await fetch(
    `${SAGE_API_BASE}/contacts?search=${encodeURIComponent(name)}`,
    {
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Accept": "application/json",
      },
    }
  );

  if (searchResp.ok) {
    const data = await searchResp.json();
    if (data?.$items?.length > 0) {
      return data.$items[0].id;
    }
  }

  // Create new contact
  const createResp = await fetch(
    `${SAGE_API_BASE}/contacts`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        contact: {
          name,
          contact_type_ids: [], // Vendor type
        },
      }),
    }
  );

  if (createResp.ok) {
    const createData = await createResp.json();
    return createData?.id ?? null;
  }

  return null;
}

// --- Retryable fetch with exponential backoff ---
async function retryableFetch(
  url: string,
  options: RequestInit,
  attempt = 0
): Promise<any> {
  const response = await fetch(url, options);

  if (response.ok) {
    return await response.json();
  }

  // Retry on transient failures (429, 5xx)
  if (attempt < MAX_RETRIES && (response.status === 429 || response.status >= 500)) {
    const delay = RETRY_BASE_DELAY_MS * Math.pow(2, attempt);
    await new Promise((resolve) => setTimeout(resolve, delay));
    return retryableFetch(url, options, attempt + 1);
  }

  const errText = await response.text();
  throw new Error(`API call failed (${response.status}): ${errText}`);
}

// --- Helper ---
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

