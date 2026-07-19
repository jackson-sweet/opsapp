# Leads Tab Redesign — Design Spec

**Date:** 2026-07-17
**Baseline:** `claude/adoring-ardinghelli-4bfb99` at `5eab107a` (lead-assignment work: assignment sheet, `// ASSIGNED TO` hero row, labeled sticky bar — all kept)
**Approved by:** Jackson, in-session (visual companion mockups, section by section)
**Scope:** iOS Leads tab — triage queue, lead card, log activity, lead detail. Plus two additive DB columns and small web parity items (handoff, not built here).

---

## 1 · Why

Jackson's diagnosis, confirmed in code:

- **WAITING FOR YOU rots.** A lead lands there when the last recorded touch was inbound (`lastMessageDirection == "in"`, `PipelineViewModel.triageBuckets`). The only way to record an answer is the full Log Activity form — which has no text-message type at all (`UnifiedLogActivitySheet` explicitly scopes it out). Real communication is sporadic texts; Jackson will not log them one by one. So the system never learns he answered, and the bucket fills with lies.
- **No fast way to flip the ball.** Nothing on the card says "handled — their move now."
- The **ADVANCE button** should be swipe (Job Board grammar) + a real status dropdown.
- The **detail screen** buried what matters, still showed retired win-probability math, spent four buttons on contact modes, and never surfaced the backend's lead summary (`opportunities.ai_summary` — web renders it; iOS never read it).

**Design goals:** the queue tells the truth without depending on logging; every correction is a one-second gesture; the detail reads like a predictable dossier; one status control everywhere; weighted probability is fully retired.

---

## 2 · The chase system (semantics)

### 2.1 Ball-in-court with an override

- New additive column **`opportunities.handled_at timestamptz null`**.
- Bucket rule change: a lead is **YOUR MOVE** (formerly "waiting on you") only when `stage != new_lead && last_message_direction == "in" && (handled_at IS NULL OR last_inbound_at > handled_at)`. Everything else in `triageBuckets` is unchanged (overdue / due today by `next_follow_up_at`; fresh = new_lead; else waiting).
- An inbound touch after a flip (new `last_inbound_at > handled_at`) naturally re-flips the lead to YOUR MOVE. No cron, no extra state.

### 2.2 HANDLED — the flip

- Tapping the card strip's **HANDLED ✓** (or the same strip on detail) sets `handled_at = now()` **and** auto-schedules the comeback: `next_follow_up_at = now() + 3 days` — unless an existing **future** follow-up is sooner, which is kept. Past-due dates are always replaced (otherwise an overdue lead could never leave OVERDUE).
- Feedback: success haptic + toast `// HANDLED · BACK FRI` with a tappable **ADJUST** that opens a compact date chooser (3D / 1W / 2W / date). The toast is the only ceremony.
- On a **THEIR MOVE / WAITING** lead the strip's button reads **ADJUST** and opens the same chooser (rescheduling the comeback).
- On **OVERDUE / DUE TODAY** leads the button is **HANDLED ✓** with identical behavior (the overdue follow-up is considered done; next one scheduled).

### 2.3 Vocabulary — one language everywhere

| Where | Copy |
|---|---|
| Strip states | `→ YOUR MOVE · 2D` / `→ CHASE · 3D LATE` / `→ DUE TODAY` / `THEIR MOVE · BACK IN 3D` / `NEW · 2H` |
| Chips + group headers | `ALL · OVERDUE · DUE TODAY · YOUR MOVE · FRESH · WAITING` (replaces "WAITING ON YOU / WAITING ON THEM"; `TriageBucket.label` "REPLY DUE" dies too) |
| Buttons | `HANDLED ✓` / `ADJUST` |

---

## 3 · Quick contact = the log (card bottom row)

`CALL · TEXT · EMAIL` on the card **do the thing and stamp the touch** — no form, fact-only (Jackson's explicit choice: the fast path never captures a note):

- **CALL** — existing around-call pattern (`CallLogStore.recordOutbound` → `tel:`). Unchanged.
- **TEXT** — opens `sms:` and logs an `activities` row `type = "text_message"`, direction out. Value verified: web already defines `TextMessage = "text_message"` (`src/lib/types/pipeline.ts:113`); iOS `ActivityType` gains `case textMessage = "text_message"` with icon + labels.
- **EMAIL** — opens Mail composing **into the ongoing thread**: `mailto:` with `subject = "Re: <subject>"` from the lead's most recent `opportunity_correspondence_events.subject` (column verified). No thread yet → blank compose. Logs `type = "email"`, direction out.
- Every quick log lands with an **UNDO toast** (same grammar as around-call auto-log). Logging an outbound touch flips the server's `last_message_direction` → the lead leaves YOUR MOVE without `handled_at` being involved.
- The **✎** glyph opens the full `UnifiedLogActivitySheet` for comprehensive entries; the sheet's type chips gain **TEXT** (same enum case), keeping call/email/meeting/note + dictation as-is.
- Buttons with no phone/email on file render disabled at 35% opacity (existing ContactCard convention).

## 4 · The card (`LeadTriageCard` rebuilt)

Anatomy, top to bottom (approved mockup `card-face-v3`):

1. **Name + value** — contact name, `$14.2K` mono right.
2. **Job line** — description / title.
3. **Chase strip** — tinted per urgency (rose overdue / tan due today / steel your-move / neutral waiting), left = state + age, right = `HANDLED ✓` / `ADJUST` button chip. The whole strip is one 44pt-min control.
4. **Meta row (information only)** — 6-segment stage progress, `QUOTED · 9D ▾` stage chip (opens the status menu, §6), source. **Win % dot and number deleted.**
5. **Contact row** — `CALL · TEXT · EMAIL` (§3) + `✎`.
6. **Summary footer band** — full-width `// SUMMARY · 2D AGO ⌄` strip, widget-footer anatomy, 44pt hit height; tap unfolds the agent summary below the band (lavender `--ops-agent` rail, `ai_summary` text). No summary → no band. Expansion is per-card session state, default collapsed.

**Gestures:** horizontal swipe = stage advance (right) / regress (left) with `UniversalJobBoardCard` mechanics (threshold fade layer, snap, disable-in-sheet flag). Advance into WON routes through the convert sheet, never direct. Long-press context menu unchanged (EDIT · ARCHIVE · DISCARD). Card tap still opens detail.

**Removed from the card:** ADVANCE button, won ✓ / lost ✗ glyphs (endings live in the status menu, swipe, and detail).

## 5 · Lead detail (`LeadDetailView` rebuilt)

Approved composition (`lead-detail-v3` + `-v4`):

1. **Map hero** — the site map fixed behind the top, `ProjectDetailsView` treatment verbatim: content scrolls over it; 90pt gradient (clear → bg 25% @ 55% → 75% @ 85% → solid); taps on the open map area launch directions. No address → plain canvas, no gap.
2. **Nav row over the map** — `‹ LEADS` left; **status chip top-right** (`QUOTED ▾`, mobile-contrast stage tones) opening the status menu (§6).
3. **Hero text** — `// L-XXXXXX · 9D IN STAGE`, then **title as header** (fallback: description → contact name → "Unnamed lead"), subtitle `Contact Name · Client Name` (contact omitted when it mirrors the client — web's `mirrorsClient` rule), subtitle `address`.
4. **`// ASSIGNED TO` row** — exactly as shipped in the assignment work.
5. **KPI strip** — `VALUE` (estimated) · **`NEXT TOUCH`** (from `next_follow_up_at`, `—` when none; replaces WEIGHTED) · `SOURCE`.
6. **Chase strip** — same control as the card.
7. **`// SUMMARY`** — always open, lavender agent rail, `· UPDATED …` stamp only when `ai_summary_updated_at` (§8) is present. No summary → section absent.
8. **Action pair** — **`CONTACT ▾`** (sheet: CALL / TEXT / EMAIL with the full phone + email printed, same do-and-stamp behavior as the card) + **`⋯`** (START SITE VISIT · LOG ACTIVITY · SHARE LEAD — workflows only).
9. **`// DETAILS`** — fixed document, `—` for blanks, order never changes:
   - **CLIENT** — client name; beneath it the roster state for the lead's person: `HELEN — ON FILE` when matched to a `sub_clients` row by email-then-name (web's normalization rules), or an `ADD TO CLIENT` action when unmatched (gated by `canEdit`), hidden when contact mirrors client. Tap → client.
   - **PROJECT** — linked project (tap → project) or `—`. `WON · NOT CONVERTED` card keeps its current conditional behavior above the document.
   - **DECK** — linked deck design(s), tap → deck builder; creation via existing picker kept.
   - **PHOTOS** — thumbnail strip + add (existing `LeadPhotosSection` mechanics under the new row skin).
   - **FILES** — lead attachments: `email_attachments` rows (`opportunity_id`, `filename`, `storage_path` verified) + estimate PDFs (`estimates.opportunity_id` verified). Tap → viewer/share sheet.
10. **`// ACTIVITY · N`** — **one stream** (stage changes fold in as entries; separate `StageTimeline` section deleted). Rows expand inline to the note / email gist / correspondence body where present (`⌄`/`⌃`). `VIEW ALL →` pushes the full history. Follow-up card deleted — NEXT TOUCH + strip carry it.
11. **Sticky bar** — **`✎ EDIT` + `MARK WON →`** (LOST moved into the status menu; MARK WON keeps the only accent on the screen — the site-visit card's competing accent is gone with the card itself).

## 6 · The status menu + standardized confirm

One dropdown component, two hosts: the detail header chip and the card's stage chip.

- Contents: `// SET STATUS` → NEW LEAD / QUALIFYING / QUOTING / QUOTED / FOLLOW UP / NEGOTIATION / WON → divider → LOST (rose) / ARCHIVE / DISCARD (rose). Current stage checkmarked; picking a stage commits instantly (`moveToStage`, stage_manually_set semantics unchanged).
- **Guarded exits, one standardized component.** A new **`OPSConfirm`** generalizes `DeleteConfirmationModifier` (title / message / verb / tone parameters) — the app's single confirmation popup going forward, no inline one-offs on these paths:
  - **ARCHIVE** → OPSConfirm → archive + toast.
  - **DISCARD** → first-time explainer kept (`LeadDiscardFlow`), its lightweight confirm leg replaced by OPSConfirm.
  - **LOST** → `LostReasonSheet` (the cancelable reason sheet is the confirmation — no double-ask).
  - **WON** → `ConvertToProjectSheet` (same principle).
- Permission gating mirrors today's rules (`canEdit` for stages/lost/archive/discard, `canConvert` for won).

## 7 · Top of the Leads tab (work-first, option A)

`LeadsSummary` rebuilt:

- **Hero:** `4 NEED ACTION` (overdue + due today + your move). Numeral tone: rose when overdue > 0, else tan when the count > 0, else primary text at zero. Breakdown line `2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE` in bucket tones. Zero state: `0 NEED ACTION` + `// ALL QUIET` treatment consistent with `LeadsCaughtUp`.
- **Tile row:** `PIPELINE $86K` (sum of open leads' estimated value — **unweighted**) · `OPEN 12` · `WON · JUL $22.4K` (sum of won `actual ?? estimated` this calendar month, olive).
- **`// PIPELINE BY STAGE`** row kept as-is (stage drill).
- **Chips renamed** per §2.3. `WON · CONVERT` nudge unchanged. Caught-up hint swaps weighted forecast for the open-pipeline total (`BooksFormat.compact`).
- `weightedForecastValue`, `winProbabilityOverride ?? stage.winProbability` displays, and every weighted/win-prob render are deleted app-wide (model fields may stay for schema compatibility; nothing reads them for UI).

## 8 · Data & schema (additive-only, both clients keep working)

| Change | Type | Writer | Reader |
|---|---|---|---|
| `opportunities.handled_at timestamptz null` | new nullable column | iOS + web (flip action) | both triage engines |
| `opportunities.ai_summary_updated_at timestamptz null` | new nullable column | web summary writer (parity item) | iOS + web stamp |
| `activities.type = "text_message"` | new value, no DDL (web enum already defines it) | iOS quick-log + sheet | both timelines |

- iOS `OpportunityDTO` gains `handled_at`, `ai_summary`, `ai_summary_updated_at` (nullable reads — safe for shipped builds; additive-only rule respected).
- **Outbound allowlist gotcha:** `handled_at` + `next_follow_up_at` writes must be added to *both* outbound field lists (DataActor default path + OutboundProcessor legacy path) — known drift trap.
- Correspondence subject: lightweight fetch of the latest `opportunity_correspondence_events.subject` for the lead (detail load + email compose path). Attachments: read `email_attachments` by `opportunity_id`; estimates by `estimates.opportunity_id`.
- Realtime: existing `.opsLeadsDidChange` funnel covers `opportunities` updates (handled_at flips arrive as row updates). No new channels.
- Offline: leads remain network-backed (deliberately outside the SwiftData sync engine). Chase actions that fail offline get the error haptic + `Feedback.Err` toast, matching the assignment sheet's semantics; no new offline queue in this scope.

## 9 · Web parity handoff (filed, not built here)

1. Respect `handled_at` in the web triage/"reply due" logic (same rule as §2.1).
2. Set `ai_summary_updated_at` when the agent writes `ai_summary`.
3. Optional vocabulary alignment (YOUR MOVE / WAITING) on web chips.

## 10 · Haptics

Light impact: card tap, quick-contact launch, menu open, expand/collapse. Medium: HANDLED, stage change, status-menu exits. Success notification: quick-log landed, flip toast. Error notification: failed mutations. No spam — one haptic per user action.

## 11 · Accessibility

- Every control ≥ 44pt (strip, band, chips, menu rows). Band + strip are single VoiceOver elements with state labels ("Your move, 2 days. Double-tap to mark handled.").
- Summary band announces "Summary, updated 2 days ago, collapsed/expanded."
- Status chip: "Status: Quoted. Double-tap to change." Menu exits announce their guard ("Opens confirmation").
- Color never alone: every tone pairs with words (`YOUR MOVE`, `3D LATE`). Reduced-motion: expansion/menu fall back to 150ms opacity.

## 12 · Testing (proof obligations for the plan)

- Unit: bucket logic with `handled_at` (flip, re-flip on newer inbound, comeback floor rule); NEED ACTION math; vocabulary labels; Re-subject compose string; text_message round-trip.
- Snapshot: card states (all strip tones, band collapsed/expanded, no-summary), detail (map/no-address, blanks-as-`—`, ON FILE states), status menu, top summary (loaded/zero).
- Migration safety: DTO decodes rows with and without the new columns.
- Manual device QA: swipe feel vs Job Board, glove-size band, sms/mailto handoffs, undo toast timing.

## 13 · Non-goals

No push-notification changes; no web UI rebuild (parity items are a handoff); no offline queue for lead mutations; no changes to site-visit capture internals, conversion flow, assignment flow, or Spotlight/universal search; `CallDirectory` untouched; win-probability columns not dropped (just unread).
