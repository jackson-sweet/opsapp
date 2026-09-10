# Bible additions for parent integration

Destination: `ops-software-bible/07_SPECIALIZED_FEATURES.md`, iOS review queues / FloatingActionMenu review unlock section. This task has not edited the shared Bible checkout.

## Shared review snapshot (2026-09-06, local implementation pending parent runtime proof)

`ReviewSnapshotStore.shared` is the single passive source for the FAB, JobBoard header, three persistent review-stack rail reports, and periodic payment/task/stale-estimate/projects-without-tasks reminders. The default path awaits the current configured `DataController.readyDataActor()` and calls `DataActor.reviewSnapshot(for:)` on the explicit background executor. It returns Sendable scalar counts; SwiftData models never cross the actor boundary. A refresh fetches live current-company tasks and projects once each. Explicit sheet entry resolves its row arrays on the main context; passive render/refresh paths do not.

Scope identity includes container, current actor instance, company, user, effective review permissions, calendar/time zone/day, company reminder thresholds/frequency, unlock thresholds, and actor execution mode. Scope replacement clears the displayed snapshot; reads recheck scope before/after readiness and completion. Invalidations during an active read reject that result and coalesce into one follow-up read. Relevant schedule/project changes use the existing scheduledTasksDidChange signal; Company inbound and local saves update threshold identity. Foreground forces a refresh. A snapshot also records its next eligibility transition (next day or earlier completedAt/estimate-recency threshold crossing); one RunLoop-default timer expires it then, and every value/report checks expiry independently.

A valid zero still reports all three stack counts, allowing server-owned rail clear/dedupe/threshold rules to operate. Loading or fetch failure never becomes zero. Reports are serialized and coalesced, with identity checks before each RPC. Last successful same-scope counts remain visible during refresh/failure, while failed or stale counts cannot trigger reporting. Review-entry loading is explicit and does not claim that no work has been completed. Completed-task/project unlock thresholds remain separate from server-owned rail loudness.

When `FeatureFlags.useDataActor` is explicitly false, the documented rollback uses two throwing reads from the existing main context and the same calculator/cache. Missing readiness while the flag is enabled does not silently use this fallback.

Intentional correctness correction approved by the parent: review tasks now exclude cached rows from other companies, including completed-task unlock counts. Explicit task sheet queries and the snapshot share this scope. An unresolved company returns no review rows. The global `DataController.getAllTasks()` API retains its existing behavior outside review.

Authored verification: `ReviewSnapshotStoreTests` (coalescing, freshness, identity, failure/zero/report order), `ReviewSnapshotDataActorTests` (membership parity, scoped unlocks, same-day expiry, flag-off and registered-actor read/edit/read), existing `TaskReviewQueryParityTests`, `ReviewThresholdServiceTests`, `AppStateNotificationRPCTests`, and `ReviewCountRefreshMonitorTests`. Worker verification is syntax parse and diff inspection only; the parent must record compilation/test results and Release device timings before claiming runtime improvement.

## Parent verification and lifetime follow-up

Parent reported freshness08 passed 1/1 on integration `2993b0c0`: production-factory off-main execution and immediate same warm actor visibility of main-context task/project edits and deletes. No context-refresh workaround is necessary. The retirement follow-up calls `checkActiveModelSession()` before either fetch, checks the awaited actor is still DataController's current actor before and after reading, and scopes cached values to actor identity even when container/account remain unchanged. Two additional authored tests cover retired-read rejection and same-container actor replacement. Their runtime execution remains parent-owned.

## Reporting intent across startup and transport (2026-09-07)

The parent combined runtime-lifetimes-11 run at `e80350dd` passed 163/164; the only failure was the populated-store threshold service test reporting no RPC calls instead of task 2/payment 1/unscheduled 1. The report task cleared its pending demand before awaiting a snapshot. A nil-to-ready actor binding could correctly invalidate that snapshot while also ending the report with no pending demand. The same loss was possible when scope, revision, or eligibility expiry changed while an RPC was suspended.

The report coordinator now retains that demand only when it observes scope/revision/expiry progress for the same user, company, and container. It rechecks after both the read and the transport. Stable read failure stops without retries or invented zero; a replacement account/container does not inherit the earlier report request. The original populated-store assertion and asynchronous fixture remain unchanged. Four additional deterministic tests cover startup binding, three progress cases during a suspended RPC, account isolation, and stable initial failure. Worker validation: syntax parse and diff check only; parent runtime rerun pending.
