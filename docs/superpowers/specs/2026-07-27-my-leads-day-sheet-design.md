# MY LEADS — Delegate Day Sheet (Design Spec)

**Date:** 2026-07-27 · **Surface:** ops-ios LEADS tab · **Status:** Approved by Jackson (direction + expanded-card anatomy + deck placement), mockups in session scratchpad `my-leads-day-sheet.html` / `day-sheet-proof.png`.

## 1 · Intent

Owners delegate leads to salespeople/runners ("Jason"). Today the LEADS tab renders the owner triage console (weighted forecast, by-stage row, convert nudges, chase queue) for anyone with `pipeline.view`. A delegate with a handful of assigned leads gets a business command center that is wrong for his job. This feature gives assigned-scope users a **day sheet**: their leads, ordered by whose move it is, with contact/route verbs on every row and a one-press milestone button that keeps the pipeline honest.

Competitive grounding (2026-07-27 Market Intel sweep, 104 sources): best-in-class rep views sort by next action, not stage (Pipedrive Focus, ServiceTitan Follow Up, HubSpot prospecting); zero-setup assigned-only scoping is the low-friction benchmark (Follow Up Boss roles); no trades product ships call + text + navigate on a lead row, photo-led rows, or an offline lead list. ServiceTitan's strongest idea — stage moves as a consequence of logged events, never a picker — is adopted here.

## 2 · View selection (which user sees what)

Branch in `LeadsTabView` on the already-shipped permission scope — **never on role names**:

| `leadAccessPolicy.scope(for: .view)` | Renders |
|---|---|
| `nil` (or pipeline feature disabled) | No LEADS tab (unchanged, `MainTabView.hasLeadsAccess`) |
| `.all` | Existing triage console (unchanged) |
| `.assigned` | **Day sheet** (this spec) |

Server enforcement already exists: `opportunities` RLS `role_scope_read` → `private.current_user_can_view_opportunity`, and a production role already carries `pipeline.view/edit/convert/assign = assigned`. Zero new settings, zero migration for view selection. Client still row-filters defensively with `LeadAccessPolicy.can(.view, assignedTo:)` (mirror of `ClientLeadsViewModel.apply`) so a stale/over-broad fetch can never render someone else's lead.

## 3 · Day sheet anatomy

### 3.1 Header
- Nav title `LEADS` (Cake Mono 300, 28), root-tab style, no back button, no right icons for pure delegates. If `leadAccessPolicy.canCreate` → single `+` nav action presenting `AddLeadSheet`.
- Sub-line (JetBrains Mono 10, `--text-3`, 0.16em): `// N LEADS · M YOUR MOVE` (`//` in `--text-mute`, `N LEADS` in `--text`). Empty: `// 0 LEADS`.

### 3.2 Grouping + order
Reuse the existing `PipelineViewModel.TriageBucket` engine (do not fork cadence logic). Delegate-facing collapse:

| Group header | Buckets | Row urgency token |
|---|---|---|
| `// YOUR MOVE · n` | overdue, dueToday, waitingOnYou | `XD LATE` (rose, mobile-lift chip) · `TODAY` (tan, mobile-lift chip) · `YOUR MOVE` (neutral) |
| `// NEW · n` | fresh | `XH AGO` / `XD AGO` (plain mono `--text-3`) |
| `// WAITING · n` | waitingOnThem | `BACK <DAY>` / `BACK <MMM D>` (plain mono `--text-3`) |

Within groups: most-late first, then follow-up due ascending, then newest. Empty groups collapse entirely (header included). Terminal stages (`won`/`lost`/`discarded`) never appear on the day sheet; a delegate's won lead lives on in FULL LEAD and the client profile. Archived/deleted excluded (same predicate as console).

### 3.3 Collapsed row (scan surface — no verbs beyond the two icons)
L1 glass card (`--glass`, hairline, r10), min 80pt, full-row tap target → expand.

- **Leading thumb 56×56 r6:** first `opportunity.images` entry → else static map snapshot of coords/address (existing Snapshotter pattern from project-details header) → else neutral tile. Photo-count micro-badge bottom-right when ≥2 images.
- **Name** `displayContactName` (Mohave 500, 15, `--text`, 1 line).
- **Address** (JetBrains Mono 10, `--text-3`, uppercase, 1 line).
- **Chips row:** stage chip `STAGE · XD` (neutral tag; days-in-stage from `stageEnteredAt`; omit `· XD` under 1D) + urgency token per table above.
- **Trailing, behind a hairline:** CALL and ROUTE icon buttons, 44×44 each. CALL = existing `LeadQuickTouchLogger` do-and-stamp dial (around-call capture continues to work). ROUTE = Apple Maps driving directions via `latitude/longitude`, else address-string query; disabled (`--text-mute`) when no address. Icons SF Symbols via `OPSStyle.Icons`, 20pt, `--text-2`.

### 3.4 Expanded card (one tap, in place — accordion; only one open at a time)
Order: photos → deck → summary → contact → quick actions → milestone → footer. Expansion pushes rows (250ms `--ease-smooth`); light haptic on open.

1. **Photo strip:** existing images as 52pt tiles (tap → `LeadPhotoViewer`) + trailing dashed `+` tile → `LeadImageService` capture/library flow (offline-queued, `local://project_images/` namespace). Strip hidden entirely only when zero images AND no add permission (viewer without edit still sees photos).
2. **Deck tile** (only when a design is attached): 2D snapshot thumbnail + design name + meta (`W × L · MATERIAL · RAIL`), chevron. Tap → existing fullscreen deck viewer. Resolution via `DeckDesignRepository.fetchForOpportunity` display-candidate logic (same as `LeadDeckSection`). Creating/attaching decks stays in FULL LEAD and the site-visit flow — the day sheet surfaces, it does not author.
3. **Summary band** (only when `ai_summary` exists): 2px lavender `--ops-agent` rail + `// SUMMARY · <AGE>` head + body (Mohave 13, `--text-2`). Provenance color per agent-token rules.
4. **Contact block** (L2 nested card): rows ADDRESS / PHONE / EMAIL — label mono 9.5 `--text-3`, value (address Mohave 14; phone/email JetBrains Mono 12). Absent lines are omitted, never `—` here (this block is verbs, not a report). **Long-press any row → iOS context menu: COPY** (plus CALL/TEXT on phone, MAIL on email). Values single-line ellipsized.
5. **Quick actions:** CALL · TEXT · EMAIL, three equal 44pt outlined buttons (Cake Mono 13). Each is do-and-stamp via `LeadQuickTouchLogger` (`.call/.text/.email`), identical logging semantics to `LeadTriageCard`'s contact row. EMAIL/TEXT hidden when the lead lacks that channel (surviving buttons flex wider).
6. **Milestone button** — see §4. Present only when `can(.edit, assignedTo:)` and the current stage has a defined next event. 48pt, full-width. **The only accent element on the screen.**
7. **Footer:** `FULL LEAD →` (mono 9.5 uppercase, `--text-3`) → pushes existing `LeadDetailView` (already permission-adaptive; StickyActionBar, activity timeline, edit, deck section all inherited). Estimated value renders in the expanded card as a quiet `EST $12,400` metadata line **only when** `permissionStore.can("finances.view")` — never on the collapsed row.

### 3.5 States
- **Empty:** `0` (Mohave 300, 32, `--text-3`) + `// NO LEADS ASSIGNED` (mono 10, `--text-mute`). CTA only if `canCreate` (`NEW LEAD` outlined-accent). No illustrations, no coaching.
- **All-caught-up** is NOT a distinct state — groups simply collapse; if every lead is waiting, the sheet is just `// WAITING`.
- **Loading:** skeleton rows (3, pulsing per MOBILE.md §10).
- **Offline:** render cached sheet + `SYS :: OFFLINE — LAST SYNC 07:12` line under the header (mono 10, `--tan`). All reads work; CALL/TEXT/route work (device capabilities); milestone/photo/log actions queue with pending affordance and drain on the existing connectivity/timer/app-launch triggers.
- **Error (fetch failed, have cache):** show cache + `SYS ::` line. **No cache:** `// ERROR — LEADS UNAVAILABLE` + `RETRY` per MOBILE.md error pattern.

## 4 · Milestone button (stage as a consequence)

One stage-aware verb per lead — the next real-world event worth stamping. Press = log activity + advance stage via `move_opportunity_stage` + notify. Never a stage picker on the scan surface.

| Current stage | Verb | On press → stage |
|---|---|---|
| `new_lead` | `CONTACTED` | `qualifying` |
| `qualifying` | `SITE VISITED` | `quoting` |
| `quoting` | `QUOTE SENT` | `quoted` |
| `quoted` / `follow_up` / `negotiation` | `WON` | opens the existing won flow (`LeadsWonChooserSheet`-adjacent path → `ConvertToProjectSheet` when `can(.convert)`; without convert scope it stamps WON only) |
| terminal | — (no button) | — |

**Press mechanics (answers "does pressing again unsend?"):** No — it is an event stamp, not a toggle. Press → medium haptic → button morphs to confirmation (`QUOTED ✓`) with an inline `UNDO` for **5 seconds** → then the card animates to its new group (e.g. YOUR MOVE → WAITING as the follow-up timer starts). `UNDO` fully reverts: stage restored, stamped activity deleted, card stays put. After the window, corrections are deliberate, not accidental: long-press the **stage chip** → existing `LeadStatusMenu` (edit-scope only), or FULL LEAD. This mirrors the shipped around-call auto-log UNDO pattern. A quote that truly went out can't be "unsent" by a button — the record should say it happened; the menu exists for honest corrections.

`WON` presses skip the undo-chip pattern — the won flow is its own confirm surface; cancel = no-op.

## 5 · Arrival (assignment is the delivery)

- On `assigned_to` set/changed to a user: push notification `NEW LEAD — <NAME>` / `<address> · <job line>`; tap deep-links to the lead (existing `pendingLeadDeepLinkId` drain in `LeadsTabView` — works for the day sheet too since it's the same tab).
- In-app: notification row per the OPS notification architecture (bible §07-14) so the web rail and iOS notifications stay consistent. Reassignment away removes the lead from the old assignee's sheet on next refresh (realtime lead-mutation notifications already drive reload).
- **Dependency to resolve at plan time:** the LEAD ASSIGNMENT initiative's delivery tables/RPCs (web branch, migrations unapplied). If that branch hasn't shipped by build time, ship the minimal independent path: DB trigger on `opportunities.assigned_to` → notifications pipeline. Verify current notification plumbing before choosing.

## 6 · Offline cache

Leads are repo-fetched (not SwiftData-synced). Day sheet persists the last successful fetch (JSON snapshot keyed by user+company, stored in app support; includes computed buckets' inputs, not the buckets) and thumbnails via the existing image cache/prefetch path. Milestone/log/photo writes queue offline and drain via existing triggers. This is a marketed differentiator — no competitor ships an offline lead list — and a hard requirement per field-first standards.

## 7 · Motion, haptics, accessibility

- Expand/collapse 250ms, group re-sort moves 300ms, all `cubic-bezier(0.22,1,0.36,1)`; reduced-motion → 150ms opacity.
- Haptics: light on expand, medium on milestone press, success notification on WON completion. No haptic on scroll/scan.
- 44pt minimum targets everywhere (row 80pt, icons 44, milestone 48). VoiceOver labels on all icon-only controls (CALL <name>, DIRECTIONS TO <address>). Mobile contrast lifts per MOBILE.md §1 (status chips 0.32/0.88, brightened text). Color never sole signal (urgency chips carry text).

## 8 · Copy (locked)

`LEADS` · `// N LEADS · M YOUR MOVE` · `// YOUR MOVE` `// NEW` `// WAITING` · `XD LATE` `TODAY` `XH AGO` `BACK FRI` · `CONTACTED` `SITE VISITED` `QUOTE SENT` `WON` · `UNDO` · `FULL LEAD →` · `// NO LEADS ASSIGNED` · `SYS :: OFFLINE — LAST SYNC <T>` · `// ERROR — LEADS UNAVAILABLE` / `RETRY` · push: `NEW LEAD — <NAME>`. No exclamation points, no emoji, numbers mono.

## 9 · Implementation surface (for the plan)

- New: `DaySheetViewModel` (pure `apply()` over fetched opps → groups; preview seam for snapshot harness), `LeadDaySheetView`, `DaySheetLeadRow` (collapsed+expanded), `MilestoneEngine` (verb map + undo window + queued commit), offline snapshot store, assignment push path (per §5 dependency check).
- Reused: `LeadAccessPolicy`, `PipelineViewModel.TriageBucket` cadence, `LeadQuickTouchLogger`, `LeadImageService`, `LeadPhotoViewer`, deck display-candidate + fullscreen viewer, `LeadDetailView` + sheets, `AddLeadSheet`, map snapshotter, notification pipeline.
- `LeadsTabView` becomes a thin permission branch; console path untouched. `ContactDetailView`-style type-checker caution: extract sections to `@ViewBuilder` vars.
- Tests: VM grouping/ordering, permission gating (view/edit/create/finances), verb map + undo revert, offline snapshot round-trip, row + expanded snapshot proofs (harness pattern: UIHostingController + scene-attached UIWindow + drawHierarchy).
- Bible: update pipeline/leads section + notification section in the build session.
- Out of scope v1: web parity, first-to-claim/pond assignment models, a MINE filter on the owner console, Carbon icon migration.

## 10 · Open items

1. §5 delivery mechanism — decide after checking the lead-assignment branch state at plan time.
2. Exact copy of the won flow entry for convert-scoped delegates (reuse existing sheets; wording only).
