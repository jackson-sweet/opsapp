# Expense Auto-Batching & Submission — Design Spec

**Date:** 2026-06-01
**Status:** Design — pending implementation plan
**Surfaces:** Supabase (server brain) · iOS app · OPS-Web (office review)

---

## 1. Problem

### 1.1 Field submissions are silently stranded (live production bug)

The current App Store build (**3.0.2**) marks an expense `submitted` and relies on a background job to file it into a reviewable batch. That job (`accounting-batch-create` Edge Function) was deprecated 2026-05-08 and had been failing silently before that. Result: an expense submitted from 3.0.2 becomes `status = submitted, batch_id = NULL` — an **orphan** that never lands in any batch, so the office never sees it to approve it. The crew member gets no error and believes it's submitted.

The fix — `always-bundle on submit` (commit `dd10f8ad`, 2026-05-07) — bundles on the client at submit time, but it shipped into **3.0.3, which is not on the App Store**. So every real submission from the current public app still strands.

Verified live: Canpro Deck and Rail's Charlie Gatenby has two real receipts (KMS $50.38, Home Hardware $8.94, both dated 2026-05-31) stranded exactly this way — the only post-2026-05-08 orphans in the entire database, because almost no one else is actively submitting.

**Root weakness:** batching authority lives on the **client**. A one-time backfill (2026-05-08) rescued older orphans, but there is no recurring server-side reconciliation, so any not-yet-updated phone keeps minting orphans.

### 1.2 The submit flow is needless friction

The expense sheet offers two buttons — *Save as draft* and *Submit*. ~99% of field use is "add an expense on the fly." Forcing a draft-vs-submit decision (and a manual submit) is friction — and it is exactly that manual submit, on a stale build, that produces the stranding above.

---

## 2. Goals & non-goals

**Goals**
- **Nothing strands, ever** — every expense reaches the office regardless of which app version created it.
- **One action in the field** — a single *Add*; no draft-vs-submit decision.
- **Automatic, configurable batching** — expenses group into per-person, per-period envelopes by the company's cadence and auto-submit for review on a schedule with a grace window.
- **Server-authoritative** — the server, not the phone, owns placement and submission, so the fix never depends on an app update.
- **Quiet for the field, one clean hand-off for the office.**

**Non-goals**
- Rebuilding the office line-item review UI (largely reuse what exists).
- Changing accounting-sync semantics beyond where it triggers.
- Multi-currency envelope reconciliation (existing behavior unchanged).

---

## 3. Model

### 3.1 Envelope (batch) lifecycle

An **envelope** is an `expense_batches` row: one per `(submitted_by, period, scope_project_id)` within a company, where *period* is derived from the expense's **date** and the company's `review_frequency`. Three phases:

| Phase | `batch.status` | Meaning | Accepts new expenses? | Office |
|---|---|---|---|---|
| **Filling** | `open` *(new value)* | Current period, silently accruing | Yes | Read-only peek; no notification |
| **With the office** | `pending_review` | Auto-sent on schedule | Yes — same-period late items, until approved | Notified once; approve/reject |
| **Done** | `approved` | Office approved | No → late items roll forward | Locked |

**"Closed" = approved.** Until approval, late same-period expenses keep joining the envelope (even after it has sent). Once approved, further same-period expenses roll forward into the current open envelope.

### 3.2 Expense status — enum unchanged (back-compat)

`expenses.status` keeps its existing values: `draft`, `submitted`, `approved`, `rejected`, `reimbursed`. The *envelope's* phase carries "filling vs sent," so the expense enum needs no new values and shipped clients keep working unmodified.

- **draft** — captured but not finalized (quick-capture stack, or incomplete). Not yet placed in an envelope; invisible to the office.
- **submitted** — placed in an envelope (filling or with-the-office), pending the office.
- **approved** — office approved the line (whole-envelope approval, early-clear, or under-threshold auto-clear). Still counted in its envelope.
- **rejected** — office rejected the line; it returns to the crew as needs-fix.
- **reimbursed** — paid.

---

## 4. Server brain

### 4.1 Placement — instant, on add/edit

On expense insert (or an update to `expense_date` / `amount` / allocation), the server places it. This runs as a **database trigger** on `expenses`, so placement is guaranteed regardless of the client:

1. Compute the period window from `expense_date` + company `review_frequency`. **The math currently lives in Swift (`ExpenseBatchPeriod`); it must be ported to a Postgres function** so the server is authoritative.
2. Find the matching `(submitted_by, period, scope_project_id)` envelope that is **not approved** (`open` or `pending_review`):
   - Exists → attach (`batch_id`), set `status = submitted`, recalc envelope total.
   - Doesn't exist → create it as `open` (race-safe get-or-create; extend `get_or_create_open_batch` to create with `open`).
   - Matching period's envelope is **approved** → **roll forward** into the current period's not-yet-approved envelope (created on demand; in the common "filed a little late" case this is the next month).
3. `draft` expenses are **not** placed until completed or swept (§4.2). Blank drafts (no amount) are never auto-placed.

Because this is server-side, no client version can create a stray expense.

### 4.2 The daily sweep — pg_cron

A scheduled job (pg_cron; no per-invocation cost) runs daily and does three jobs:

1. **Auto-send** — every `open` envelope whose period has ended and `auto_submit_grace_days` has elapsed → flip to `pending_review` and fire **one** notification to all `expenses.approve` holders. Before flipping, **sweep in that person's leftover drafts** for the period **that have an amount**; hold blank drafts and nudge the owner.
2. **Safety net** — any expense with `status = submitted, batch_id = NULL` (an orphan from any client/version) → place it (§4.1). This permanently ends the stranding class of bug.
3. **Roll-forward** — any straggler whose home-period envelope is already `approved` → move to the current open envelope.

### 4.3 Timing / cadence

- New per-org setting **`expense_settings.auto_submit_grace_days`** (additive column, default **7**) — "days after the period ends." Monthly → the 7th. Short cadences (weekly/biweekly) would set 1–2.
- **per_job** has no calendar period → its envelope auto-sends N days after the **job is marked complete** (or the office sends manually); it never auto-sends on a calendar.

---

## 5. Experience

### 5.1 Field — iOS (Phase 2)

- A single **Add** (capture/scan or manual) → pending in the right envelope. The snap-a-stack quick-capture still saves drafts to finish later; an unfinished draft gets a gentle "finish your receipt" nudge.
- The list shows each line's state (pending → approved → paid), its month, and the envelope phase quietly (e.g. *April · with the office*), plus a low-key running total for the current filling envelope. No submit button; nothing to manage.

### 5.2 Office — OPS-Web (largely existing surface)

- **Peek** — open anyone's filling envelope anytime: live total, read-only, no approve.
- **Review** — a sent envelope lands in the review queue with one notification; approve the envelope, or reject/flag individual lines (existing line-item review).
- **Early-clear** — from the peek, approve a single line before the deadline; it is paid on its own, stays counted in the month, and **notifies the submitter**. Available both in the review detail and the floating batch popover.
- **Auto-approved batches live in History** on both surfaces (web + iOS) — they need no review.
- Net: one notification per envelope (not per expense); peek + early-clear are new.

---

## 6. Rollout & migration

### Phase 1 — Server, ship now (stops the production bleed; no app release)

Deploy placement + sweep + auto-send + safety net. Effects for **all** current users, including everyone on 3.0.2:

- Currently-stranded `submitted / NULL` expenses are placed into their correct envelopes by date.
- Nothing can strand going forward.
- Envelopes begin auto-sending per cadence + grace.
- Additive and back-compatible: 3.0.2 is unaffected; it simply starts seeing its expenses batched.
- No added infrastructure cost (scheduled DB job).

**Charlie acceptance test:** his two 2026-05-31 receipts land in Canpro's **May 2026** envelope, which (monthly + 7-day grace) auto-sends **June 7, 2026**. If Phase 1 is deployed after June 7, the first sweep run sends it immediately (period + grace already passed). Either way: no manual cleanup.

### Phase 2 — App, next release

Single Add button, remove the draft/submit choice, peek, early-clear, one-notification-per-envelope. Reaches users on update; until then the server keeps everyone safe.

### Data mapping

- Existing `draft` expenses → stay draft.
- Existing batches: `pending_review` → *with the office*; `approved` → *done*. New filling envelopes are created `open`; existing sent batches remain `pending_review`.
- The 19 legacy batched-and-born-submitted expenses are already correct.

---

## 7. Edge cases

- **Rejected line** → returns to the crew as a draft (needs-fix); never stranded. They correct it (flows into the current open envelope) or delete it. The rest of the envelope is unaffected.
- **Editing a pending expense already with the office** (not yet approved) → allowed; envelope total updates, office sees the change. An **approved/paid line is locked.**
- **Changing an expense's date** into another month → re-places by the new date; if that month is already approved, it rolls forward.
- **Deleting** a pending expense → removed, total recalculated. Approved/paid is locked.
- **per_job** → one envelope per `(person, project)`; sends a few days after job completion (no completion → stays open; office can send manually).
- **Changing the org's cadence** → applies to new placements going forward; envelopes already filling finish on their original window.
- **Project splits (allocations)** → unaffected; an expense can still be split across projects inside its envelope.
- **Envelope sits unreviewed** → flagged overdue to the office (existing expense-urgency logic), so it surfaces instead of rotting.
- **Auto-approve threshold** (optional per-org) → under-threshold expenses still land in the envelope (books stay complete) but auto-clear on the spot, exactly like early-clear but automatic. Off by default (Canpro has none set).

---

## 8. Testing

- **Placement math** — each cadence (per_job / weekly / biweekly / monthly / quarterly) places by `expense_date` into the right window, including boundaries: 1st/last of month, Mon/Sun week edges, quarter ends, an April receipt filed in May.
- **The rules** — late receipt joins an `open` or `pending_review` envelope; rolls forward only when its home month is `approved`; "current open envelope" resolves correctly even when several months are closed.
- **Auto-send** — envelope flips on exactly the right day per grace, fires one notification, sweeps in leftover drafts with amounts; blank drafts held + owner nudged.
- **Safety net** — a `submitted / NULL` orphan gets adopted; legacy drafts swept. **Charlie's two are the live acceptance test:** they must land in Canpro's May envelope and auto-send June 7.
- **Money paths** — early-clear approves one line without double-counting it at envelope approval; the auto-approve threshold clears small items but still records them.
- **Safety** — two expenses added at once never spawn duplicate envelopes (race-safe get-or-create); a 3.0.2 phone keeps working untouched.
- Layers: unit (math), integration (sweep / safety-net / migration against a data copy), acceptance (Charlie + one full monthly cycle end-to-end).

---

## 9. Schema changes (all additive — respects the iOS cross-release sync constraint)

- `expense_batches.status` — add allowed value `open`.
- `expense_settings.auto_submit_grace_days int not null default 7`.
- New Postgres function: period computation (port of Swift `ExpenseBatchPeriod`).
- Extend `get_or_create_open_batch` to create envelopes with `open` status.
- New placement function + insert/update trigger on `expenses`.
- pg_cron daily sweep job (auto-send + safety net + roll-forward).
- per_job: job-completion → envelope-send hook.

---

## 10. Open items for the implementation plan

- Exact back-compat behavior of shipped iOS clients (3.0.2 / 3.0.3) when they read a batch with the new `open` status — expected: treated as not-yet-approved / pending, which is acceptable; **must be verified against the actual iOS batch-status handling before the migration ships.**
- Confirm approver RLS permits reading `open` (filling) envelopes so the office peek works — no new RLS dimension expected; verify against the 2026-05-31 expense RLS remediation.
- The per_job completion signal source (which table/field marks a job complete).
- Notification copy for the field "finish your receipt" nudge and the office "envelope ready for review" notification (route through `ops-copywriter`).
