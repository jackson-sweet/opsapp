# Leads — Discard a lead (iOS)

**Date:** 2026-07-05
**Surface:** iOS · Leads tab
**Status:** Design approved (direction + friction model confirmed by Jackson). Feasibility verified against live DB (`ops-app` / `ijeekuhbatykdomumfjx`). No migration required.

---

## 1. Problem

A lead can land in the pipeline that was **never a real lead** — spam, a vendor, an applicant, a duplicate, a mis-typed entry, platform noise, test data. Today iOS has no first-class way to remove it. The only options are:

- **Archive** — wrong: implies "real lead, revisit later," and keeps it counted as a real opportunity.
- **Mark Lost** — wrong: pollutes win/loss reporting with a deal that never existed.
- The **buried "Delete"** in the Edit sheet's danger zone — a soft-delete (`deleted_at`) whose confirmation copy promises *"restored from the trash,"* which is **false on iOS**: `TrashView` restores projects/clients/tasks, **not leads**. So a soft-deleted lead is effectively unrecoverable on-device.

The user needs a distinct **Discard** action meaning *"this should not have been a lead."*

## 2. The concept already exists in OPS — use it

`discarded` is a first-class, purpose-built pipeline state, not something we invent here:

- **`01_PRODUCT_REQUIREMENTS.md`**: *"Discard — Terminal stage for leads not worth pursuing. Discarded leads stay in the system for analytics but are off the active board. Enables ad-targeting quality measurement: won+lost (real leads) vs discarded (junk quality)."*
- **`10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`** lifecycle table: `discarded` = *"Should not have been a lead: spam, vendor, applicant, internal, platform noise, test data" → counts toward data-quality analysis, not sales performance.*
- `PipelineStage.swift:19`: `case discarded = "discarded"  // server-only junk state (migration 045); terminal, never in the triage queue`.

It has been **server-only** to date (Phase-C auto-cleanup was the only writer). This feature gives the operator the **manual** discard the PRD already envisions (*"User marks lead as not worth pursuing"*).

### The three-action model (why each is distinct)

| Action  | Means | Data effect | Counts as | Reversible |
|---------|-------|-------------|-----------|------------|
| **Archive** | "Done for now, but keep it." | sets `archived_at` | a real, dormant opportunity | yes (`unarchive`) |
| **Lost** | "Real lead I chased and didn't win." | `stage=lost` + reason | a lost sale (win-rate) | via stage move |
| **Discard** | "This was never a real lead." | `stage=discarded` | junk / data-quality signal — **not** a sale | via stage move |

Discard is **better than a delete**: the lead comes off the board, is *not* logged as a lost deal, and quietly feeds an ad-quality signal (real leads vs junk) — invisible helpfulness. It is also recoverable (stage move), unlike the iOS soft-delete.

## 3. Mechanism (verified — no backend work)

Discard = move the opportunity to `stage = discarded`, exactly as `markLost`/`markWon` move to `lost`/`won`.

- **RPC:** `move_opportunity_stage(p_opportunity_id uuid, p_to_stage text, p_user_id uuid)`.
  - `p_to_stage` is `text` — **no CHECK constraint, no enum** on `opportunities.stage`; `'discarded'` is accepted. *(Verified.)*
  - Body updates `stage`, `stage_entered_at`, `stage_manually_set`, `updated_at`, and inserts an **immutable `stage_transitions` row** → the discard is audited automatically.
  - No-ops if already in target stage. Only touches rows where `deleted_at IS NULL`.
- **RLS:** `role_scope_update` (RESTRICTIVE) requires `private.current_user_has_permission('pipeline.manage','all')` for both USING and WITH CHECK; `company_isolation` scopes to the caller's company. → Gate the UI on **`pipeline.manage`** (the `canManage` flag the Leads tab already uses for Archive). *(Verified.)*
- **Triggers:** only `trg_opp_timestamp` (timestamp bump) and an INSERT-only default-title trigger — nothing rejects or special-cases a discard. *(Verified.)*

**iOS additions (repository + view-model):**

- `OpportunityRepository.discard(_ opportunityId:userId:)` → wraps `moveToStage(opportunityId:to:.discarded, userId:)`. (Mirror of `markLost`/`markWon`, minus the lost/won field patch. Sets `actualCloseDate` to `now()` for parity with other terminal moves — TBD-confirm during plan against how web stamps discarded.)
- `PipelineViewModel.discard(opportunityId:)` → calls the repo method, then updates the local model's `stage`/`stageEnteredAt` so the row drops out of the triage buckets immediately (terminal stages are excluded from triage).

No SwiftData migration. No Supabase migration. No new RPC.

## 4. UX

### Friction model (Jackson's decision: *"explain once, then quick confirm"*)

A **single shared first-run flag** (`@AppStorage("leads_discard_explainer_seen")`) governs both entry points, so the education shows exactly once regardless of where the first discard happens.

- **First discard ever →** the **Explainer** (`DiscardExplainerSheet`): a compact OPS sheet contrasting Discard vs Lost, with a `DISCARD LEAD` (destructive) primary + `CANCEL`. Proceeding performs the discard and sets the flag.
- **Every discard after →** a **quick confirm** — native `.confirmationDialog` ("Discard this lead?" + one line) with `DISCARD` (destructive) / `CANCEL`, mirroring the existing Edit-sheet delete-confirm pattern.

> This intentionally diverges from the PRD's "no confirmation dialog" line, per Jackson's explicit direction. Reconcile `01_PRODUCT_REQUIREMENTS.md` §Discard to note the iOS manual-discard UX (first-run explainer + lightweight confirm) in the same session.

### Entry point 1 — the mark-as-lost sheet (`LostReasonSheet`)

The user reaches the lost sheet via the rose ✕ in `StickyActionBar`. This is the exact moment of "is this lost, or was it never real?" confusion. Add a **subordinate tertiary action below the CANCEL / CONFIRM LOST row**:

- Muted, single-line text button — e.g. *"Not a real lead? Discard instead"* (final copy via `ops-copywriter`).
- Visually clearly below and quieter than `CONFIRM LOST` — it must never compete with the primary destructive action.
- Tapping runs the discard flow (explainer or quick-confirm). On success, dismiss the lost sheet too and toast `// LEAD DISCARDED`.
- Lives inside the footer overlay's gradient mask so it reads as part of the commit zone, not floating content.

### Entry point 2 — the long-press context menu

Both `LeadsTabView.swift` (~402–414) and `PipelineStageListView.swift` (~144–156) carry an identical `.contextMenu { Edit · Archive }`, gated by `canManage`. Add a **third action, `Discard`**, `role: .destructive`:

```
Edit          (pencil)
Archive       (archivebox)      — neutral "file it"
Discard       (<junk icon>)     — destructive; "never a real lead"   ← new
```

- Same `canManage` (`pipeline.manage`) gate.
- Destructive role/red styling differentiates it from the neutral Archive at a glance.
- Icon: distinct from Archive and from a plain trash/delete (candidate SF Symbols: `xmark.bin`, `trash.slash`, `nosign` — finalize in `ops-design`/`mobile-ux-design`; must not read as "delete").
- Runs the same shared discard flow.
- The two context menus are duplicated today — factor the Edit/Archive/Discard block into one shared modifier/view so both stay in lockstep (targeted improvement, in-scope).

### Feedback + haptics

- Success: `UINotificationFeedbackGenerator().notificationOccurred(.success)` + toast `Feedback.Lead.discarded` (`// LEAD DISCARDED`, tone TBD — likely `.warning`, matching archive; confirm in `ops-design`). Add the message to `Feedback.swift`.
- Failure: reuse the sheet/`errorToast` pattern (`OFFLINE — TAP TO RETRY` / `PERMISSION DENIED`).
- Post a `LeadDiscardedSuccess` NotificationCenter event mirroring `LeadArchivedSuccess`/`LeadMarkedLostSuccess`, so open lists refresh via the existing `.opsLeadsDidChange` funnel.

### Retire the buried, mislabeled Delete

Since Discard is now the clear, recoverable "get rid of a junk lead" path, remove the confusing `EditLeadSheet` danger-zone **Delete** (soft-delete → `deleted_at`) whose "restore from trash" promise is false on iOS. Keep **Archive** in the danger zone. (Approved in principle; Jackson may veto. Do not touch the repo's `softDelete` method — only the UI affordance — in case web/other callers rely on it.)

## 5. Copy (draft — finalize via `ops-copywriter`)

OPS voice: terse, tactical, sentence case for content / UPPERCASE for authority, no emoji, no exclamation points.

- Explainer title: `DISCARD vs LOST`
- Explainer — Lost: *"A real lead you chased and didn't win. Counts in your win rate."*
- Explainer — Discard: *"Never a real lead — spam, a wrong number, a duplicate. Comes off your board and won't count as a lost deal."*
- Explainer primary: `DISCARD LEAD` · secondary: `CANCEL`
- Lost-sheet tertiary: `Not a real lead? Discard instead`
- Repeat confirm title: `Discard this lead?` · body: *"It comes off your board and won't count as a lost deal."* · buttons `DISCARD` / `CANCEL`
- Long-press label: `Discard`
- Toast: `// LEAD DISCARDED`

## 6. Edge cases

- **Already terminal (won/lost/discarded):** the lost sheet only shows for non-terminal leads (StickyActionBar hidden when `stage.isTerminal`), so the lost-sheet entry can't act on a terminal lead. In the context menu, hide/omit Discard when `lead.stage.isTerminal` (a discarded/won/lost lead shouldn't be re-discarded). Confirm triage never surfaces terminal leads anyway.
- **Offline:** the RPC call fails → surface retry copy; do **not** locally flip the stage until the call succeeds (match `EditLeadSheet` save's failure handling — never show a false state).
- **Permission absent:** `canManage == false` → the action isn't rendered (matches Archive). RLS is the backstop.
- **Concurrency / realtime:** a discard elsewhere arrives via `.opsLeadsDidChange`; identity-preserving merge already handles removal from triage.
- **Recovery:** discarded is a stage move, so the row persists (not deleted) and can be moved back to an active stage by an operator with `pipeline.manage`. A dedicated on-iOS "discarded" review/restore surface is **out of scope** here (the quick-confirm gate makes accidental discard unlikely); note as a possible follow-up.

## 7. Out of scope

- A discarded-leads review/restore screen on iOS.
- Any change to `move_opportunity_stage`, RLS, or the `opportunities` schema.
- Web parity changes (web already has the `discarded` stage in its enum).
- Removing/altering the repository `softDelete` method (UI affordance only).

## 8. Verification plan

- **Build:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` clean.
- **Behavioral proof (simulator):** discard from long-press → lead leaves triage; discard from lost sheet → both sheets dismiss, toast shows. First run shows explainer; second run shows quick confirm (assert `leads_discard_explainer_seen`).
- **DB proof (read-only, test company):** after a simulated discard, confirm `opportunities.stage='discarded'` and a new `stage_transitions` row (`to_stage='discarded'`).
- **Snapshot proof:** render `DiscardExplainerSheet` + the updated `LostReasonSheet` footer + the context menu via the `BooksSnapshotTests` harness → PNGs to `docs/artifacts/`.
- **Design-system audit:** `audit-design-system` — zero hardcoded color/spacing/radius/font; all values trace to `OPSStyle`.

## 9. Skills to invoke during the build (per OPS standards)

`custom-skills:writing-plans` (produce the plan) → then during execution: `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter:ops-copywriter` (all copy), `custom-skills:wizard-audit` (war-game the explainer/confirm flow), `animation-studio:animation-architect` + `ios-animations` (sheet/menu motion), and `custom-skills:audit-design-system` before calling it done.
