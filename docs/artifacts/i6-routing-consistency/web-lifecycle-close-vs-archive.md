# I6 · Web-side change filing — completed+paid projects must go to `closed`, not `archived`

**Bug:** `af27ea82-fa83-4217-88ad-af002c3c230d` (part b) — "projects should not be archived after completion… they should be moved to 'closed' when complete and paid. Archived is for when they are paused/cancelled."

**Origin (confirmed):** iOS never writes `archived`/`closed` on completion, and there is **no DB trigger** that does (only `projects_autoname` + `update_timestamp`). The behavior originates entirely **web-side** in the agent-queue lifecycle automation. This filing is the precise, implementation-ready change. It is **not** applied here — it needs an `ops-web` worktree off `origin/main` (the primary checkout is the shared stale `feat/inbox-dark-launch`) plus Jackson's deploy go, and web QA.

## What's wrong today

1. `ProjectLifecycleService.proposeArchiveActions` — `ops-web/src/lib/api/services/project-lifecycle-service.ts` (~L1180–1308) — scans `status = 'completed'` projects and proposes an **`archive_project`** agent action for any whose tasks are all done (`project_tasks` not in completed/cancelled → skip) **and** whose `outstandingBalance === 0` (L1270–1271 `if (outstandingBalance > 0) continue`). That filter is exactly **complete + fully paid**.
2. On accept, `executeArchiveProject` — `ops-web/src/lib/api/services/approval-queue-service.ts` (L481–503) — runs `.update({ status: "archived" })`.

Result: complete + paid projects are pushed to **`archived`**. Per `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` (Automation F + Project Statuses, updated this pass), those are the definition of **`closed`** (terminal success). `archived` is reserved for operator pause/cancel.

The user-visible symptom on iOS was the resulting rail notification: `type='agent_suggestion'`, body *"Archive \"WJ ROYAL BAY\" — completed 53 days ago, all tasks done, fully invoiced"*, `action_url=/agent/queue`. iOS now suppresses that notification type (it has no agent-queue surface); this filing fixes the underlying wrong-target.

## The fix (Approach B — add a `close_project` action type; recommended)

Keeps `archive_project` for a genuine operator pause/cancel path and gives the completion path its own correct terminal target. Do **not** just repoint `executeArchiveProject` to `closed` — that conflates the two lifecycle outcomes.

### 1. `src/lib/types/approval-queue.ts`
- Add `| "close_project"` to the `AgentActionType` union (after `"archive_project"`, L18).
- Add a `CloseProjectActionData` interface mirroring `ArchiveProjectActionData` (`project_id`, `project_title`, `completed_date`, `days_since_completion`, `total_tasks`, `completed_tasks`, `total_invoiced`, `outstanding_balance`).

### 2. `src/lib/api/services/approval-queue-service.ts`
- `EXPIRY_DAYS` (L70–…): add `close_project: 14,`.
- Dispatch switch (L135–…): add `case "close_project": return executeCloseProject(action);`.
- Add `executeCloseProject`, a copy of `executeArchiveProject` (L481–503) that runs `.update({ status: "closed" })` and returns `{ projectId, projectTitle, closedAt }`. Leave `executeArchiveProject` in place for the operator pause/cancel path.

### 3. `src/lib/api/services/project-lifecycle-service.ts`
In the completed-project scan (L1180–1308):
- Propose `actionType: "close_project"` (not `archive_project`).
- `sourceId = \`${projectId}:close\`` and de-dupe against pending **`close_project`** actions (L1201–1210).
- `contextSummary: \`Close "${project.title}" — completed ${daysAgo} days ago, all tasks done, fully paid.\``
- Keep the `outstandingBalance > 0 → continue` guard (only complete **and** paid projects qualify for auto-close).

### 4. UI + i18n
- `src/components/agent/action-card.tsx` — render the `close_project` kind (label/icon; reuse the archive card's shape, verb "Close").
- `src/i18n/dictionaries/en/agent-queue.json` + `es/agent-queue.json` — add the `close_project` label/description. (Email/template version ledger is not involved.)

### 5. Also ensure the paid-invoice cascade fires (Automation F)
The mere existence of the auto-archive scan implies complete+paid projects are **lingering in `completed`** — i.e. the documented "invoice paid → `project.status = closed`" cascade isn't firing. Locate the invoice-paid / payment-recording handler (search `status: 'paid'`, `markInvoicePaid`, payment insert) and confirm it advances the project to `closed` when the project's outstanding balance reaches 0. With that cascade working, `close_project` becomes a rare fallback rather than the primary path.

## Verification (web chip)
- Unit/integration: accepting a `close_project` action sets `projects.status = 'closed'`; the scan proposes `close_project` (never `archive_project`) for complete+paid projects; `archive_project` remains reachable only from the operator pause/cancel path.
- Regression: no project is auto-archived on completion; `CHECK (status IN (…,'closed','archived'))` already permits both (verified live).
- Data cleanup (Jackson's go): projects currently `archived` that are actually complete+paid may be re-mapped to `closed` in a one-off migration — decide separately.
