# Queue-only expense edge adapter — prepare only

The two source files under `supabase/functions/accounting-sync-expense/` are byte-identical to the prepared candidate. `manifest.json` records hashes, the captured live v5 version and `verify_jwt=false`. Preserve the verified gateway setting so Firebase bearer tokens continue to reach the caller-authorized RPC. No service-role key, provider token/client, or fallback provider call exists in this adapter. Do not add a fallback when the new RPC is temporarily absent.

The exact missing-RPC regression is included: upstream HTTP 404 with PGRST202 returns HTTP 404 and `Accounting sync is unavailable. Try again.`; transport/server failures return 503. The adapter never claims queue/sync success for this interval and sends only one original-bearer RPC request. The user-facing approval decision can already be committed by old clients; identify the adapter-to-schema interval read-only afterward and retain pre-capture approvals as legacy reconciliation, never silently replay them.

After separate deployment permission: replace the legacy v5 writer, confirm the new source/version is serving, record that timestamp, and wait at least 400 seconds while version-specific logs confirm no new v5 invocation starts. Restart the drain if old-version invocation continues. The parent verified the conservative hosted paid-worker 400-second maximum on 2026-09-15 from [Supabase limits](https://supabase.com/docs/guides/functions/limits) and [wall-clock guidance](https://supabase.com/docs/guides/troubleshooting/edge-function-wall-clock-time-limit-reached-Nk38bW). The 150-second HTTP idle timeout is not the drain period. Provider acceptance may outlive its caller; compare legacy evidence read-only and reconcile every uncertain result, without replay. Stop the dependent atomic schema installation if retirement/drain cannot be established.

Parent-only fake-RPC verification:

```sh
npm test -- --run tests/unit/expenses/expense-sync-edge-handler.test.ts
```

No edge deployment, gateway setting write, provider request or real expense sync was performed by this preparing agent.
