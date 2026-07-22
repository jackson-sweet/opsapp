# SYNC RECOVERY — Pending Work screen, retry policy, orphan designs

Design spec · 2026-07-22 · initiative `SYNC RECOVERY` (single phase, P1)
Born from the 2026-07-22 outage: the "Charles" site-visit bundle parked invisibly; three clients' auto-leads 400 forever; 15 deck designs orphaned server-side.

## 1 · Verified root causes (evidence, not hypothesis)

| # | Defect | Mechanism | Evidence |
|---|--------|-----------|----------|
| RC1 | Auto-created leads 400 forever | `ClientLeadAutocreate.makeOpportunityDTO` sends `source_thread_key`; `private.create_opportunity_company_serialized_internal` rejects any key outside its `v_allowed_keys` (errcode 22023 → HTTP 400 `unsupported_opportunity_field: source_thread_key`). `ClientLeadAutocreateQueue` retries on a 60s timer with no classification, cap, or surfacing. | RPC source read from prod; `ClientLeadAutocreate.swift:73`; queue timer `ClientLeadAutocreateQueue.swift:91`; clients Amber Chen / David Lunn / Laurel Labelle exist with 0 opportunities. |
| RC2 | Failed creates park invisibly, restart doesn't help | Both outbound paths fetch `status == "pending"` only. After `maxRetries`(20) an op → `"failed"` — never re-fetched. An op stranded `"inProgress"` by an app kill is equally dead. No 4xx/5xx distinction: a 400 burns the same 20 retries as a 504. Released build has no failed-item UI (redesigned notifications panel unshipped); status pill counts pending only. | `DataActor.swift:3946,4134-4166`; `OutboundProcessor.swift:41,302-321`; `SyncStatusProvider.swift:61-79`. |
| RC3 | Deck designs orphan server-side | `validDeckDesignColumns` in BOTH outbound paths omits `opportunity_id` — every create/update strips the lead link before push. Post-hoc PATCH is blocked by `trg_deck_designs_guard_opportunity_reparent` (token-guarded). | `OutboundProcessor.swift:446-450`; `DataActor.swift:4679-4683`; 15 orphan rows in prod, four titled "Site visit deck". |
| RC4 | Site-visit lead create is one-shot | `createLeadFromIdentityDraft` calls the RPC directly; on failure only sets an error string. In-code comment admits the gap ("Opportunity has no offline write queue"). | `SiteVisitCaptureViewModel.swift:859-872`. |

## 2 · Server work (prod `ijeekuhbatykdomumfjx`, migrations sanctioned)

### M1 — `source_thread_key` support in guarded create
Extend `private.create_opportunity_company_serialized_internal`:
- Add `source_thread_key` to `v_allowed_keys`.
- Write `source_thread_key` in the INSERT (nullable; `nullif(btrim(...),'')`).
- Idempotency: when `(company_id, source_thread_key)` already exists (pre-check + unique-violation catch on `23505`), return the existing row as `ok:true, conflict:true, opportunity:<existing>` instead of raising — a retried create must be a success, not an error. Preserve the existing return shape.
- Precondition check before writing the migration: confirm `public.opportunities.source_thread_key` column + unique index on `(company_id, source_thread_key)` exist in prod (verified 2026-07-22: repo comments assert it; agent must re-verify with `\d`-equivalent SQL and abort if absent).
- Additive-only: old clients that never send the key see zero behavior change.

### M2 — `public.link_deck_design_to_opportunity_guarded(p_design_id uuid, p_target_opportunity_id uuid) returns jsonb`
Mirrors the `reassign_opportunity_email_thread_guarded` token pattern, scoped to one row:
- SECURITY DEFINER, `search_path` pinned like siblings; callable by the app role (NOT service_role-gated — this is an end-user action).
- Resolve actor via `private.get_current_user_id()` / `private.get_user_company_id()`; 42501 when null.
- Load design `for update`; require: exists, `company_id` matches, `deleted_at is null`.
- **Orphan-only:** require `opportunity_id IS NULL`. If already equal to target → return `already_linked:true` success (idempotent retry). If linked to a different opportunity → raise 23514 (moving between leads stays forbidden, per brief).
- Authorization: `private.current_user_can_edit_deck_design(company_id, NULL::uuid, project_id, 'deck_builder.edit')` AND `private.user_can_edit_opportunity(actor, target)`. Target must be same-company, not archived/deleted.
- Lock order: `private.lock_lead_assignment_company(company_id)` first, then design row, then target opportunity row `for update` (matches sibling RPC ordering).
- Mint token into `private.opportunity_child_reparent_tokens` (`table_name='deck_designs'`, `row_id=p_design_id`, old NULL → new target), UPDATE `deck_designs.opportunity_id`, delete tokens keyed `(txid_current(), pg_backend_pid())`; `exception when others` re-deletes tokens and re-raises.
- Return `jsonb: {ok, design_id, opportunity_id, already_linked}`.
- Live verification after apply: create scratch design + link + assert + re-link (idempotent) + cross-link rejection + cleanup, in one SQL session as the postgres role AND once through PostgREST semantics if feasible.

## 3 · iOS retry policy (the state machine)

New pure `SyncErrorClassifier` (single source of truth, unit-tested):

| Input | Disposition |
|-------|-------------|
| URLError offline/connection-lost/timeout | `.transient` |
| HTTP 5xx, 429, 408 | `.transient` |
| PostgREST SQLSTATE `40001`, `40P01`, `55P03`, `57014` | `.transient` (serialization/lock/timeout — the outage class) |
| PostgREST `PGRST301` / JWT / 401 | `.auth` (existing behavior preserved) |
| HTTP 4xx otherwise; SQLSTATE `22xxx`, `23xxx`, `42xxx`, `P0001-P0002` | `.permanent` |
| PK-violation on create | (handled before classification — idempotent success, unchanged) |
| Unknown | `.transient` (never park work on a guess) |

Supabase-swift error shapes (PostgrestError.code/message, HTTPError.response.statusCode) must be inspected in `Package.resolved` checkouts during implementation — no guessing.

**SyncOperation state machine** (no schema change — new `status` VALUE, avoids the versioned-schema checksum minefield):
- `pending → inProgress → completed`
- `.transient` failure: `retryCount += 1`; `< 20` → `pending` (existing 2^n≤60s backoff); `≥ 20` → `failed` (recoverable).
- `.permanent` failure: → **`parked`** immediately, `lastError` set. No further auto-retries. Ever.
- `.auth`: → `failed` + `.syncAuthExpired` (unchanged).

**Re-enqueue sweep** — `SyncEngine` preamble (transactional), runs at app launch and on connectivity-restore (NOT every 180s tick):
- `inProgress` with `lastAttemptedAt` older than 5 min (or nil) → `pending` (crash recovery; PK-violation idempotency makes replays safe).
- `failed` → `pending`, `retryCount = 0`, keep `lastError` (fresh budget per session — "restart retries by default").
- `parked` stays parked. Only user retry (which resets to `pending`, `retryCount 0`) or Discard moves it.

**ClientLeadAutocreateQueue** gets the same policy: per-request `attempts`, `lastAttemptAt`, `lastError`, `parkedAt` (Codable-additive, optional with defaults). Transient: exponential backoff (60s base ×2, cap 15 min) enforced inside `drain()`; no attempt cap (survives launches; the SyncOperation-style cap is unnecessary because the timer is slow, but backoff is mandatory). Permanent: `parkedAt` set — excluded from drain, surfaced in UI. Retry action clears `parkedAt`/`attempts`. Successful delivery also binds site-visit drafts (below).

**Site-visit lead create (RC4):** on `createLeadFromIdentityDraft` failure → enqueue into `ClientLeadAutocreateQueue` (dedup key = clientId already). Direct DTO gains `sourceThreadKey` (same `client-autocreate:` key) so direct-path and queued-path creates can never duplicate. On queue delivery: existing local-insert + notification, PLUS bind any `SiteVisitIdentityDraft` with matching `clientId` and nil `opportunityId` (set draft.opportunityId, rebind visit, link visit's attached deck designs to the lead locally + record link ops).

**Deck design payloads (RC3):**
- CREATE: add `"opportunity_id"` to both `validDeckDesignColumns` sets (create-with-link passes the trigger — it fires on UPDATE only; RLS insert policy covers linked inserts under `assigned` scope).
- UPDATE: strip `opportunity_id` from PATCH payloads. A NULL→X link travels as a new operationType `"linkOpportunity"` on entityType `deckDesign` → handler calls `DeckDesignRepository.linkToOpportunity` (the M2 RPC). `already_linked` → success. Different-opportunity conflict → `.permanent` park.
- One-shot heal sweep behind `UserDefaults` flag `deckDesignLinkBackfill.v1`: for local designs with `opportunityId != nil`, enqueue `linkOpportunity` ops. RPC idempotency makes it safe; different-link conflicts park visibly instead of fighting.

## 4 · The screen — PENDING WORK

**Who/when:** an operator who just saw a "needs a look" badge, or is checking "is my work safe?" before leaving signal. Unit of thought = the piece of WORK ("Charles — site visit"), not sync ops.

**Flow:**
```
[sync pill tap / toast tap / Settings › DATA row / notifications VIEW ALL]
    → PENDING WORK
        → row tap → item/bundle detail (half sheet) → RETRY / EXPORT / DISCARD / LINK
        → all clear → zero-state (— // NOTHING PENDING)
        → offline → rows render with WAITING FOR SIGNAL tone; retry queues rather than fires
```

### Wireframe variants considered

V1 Status-first (flat urgency list) — strongest for "what's wrong", weak bundle story.
V2 Entity-type dashboard — REJECTED: renders the data model, not the situation.
V3 Single RETRY ALL hero + disclosure — hides the inventory; fails the forensic need.
V4 **Bundle-first hybrid (CHOSEN):** urgency section pinned on top, then work-unit bundles, then loose items, then chronic orphans. Matches the badge→triage mental model and the site-visit story.

```
┌──────────────────────────────────────┐
│ ← SETTINGS   // PENDING WORK         │  nav (Cake Mono 28px; sheet: × close)
├──────────────────────────────────────┤
│ // NEEDS ATTENTION · 2               │  JBM 10px --text-3, tan count
│ ┌─ L1 ────────────────────────────┐  │
│ │ ⚠ Charles — site visit      2h  │  │  bundle card: Mohave 15px title
│ │   CLIENT ✓ · LEAD ⏸ · DECK ⏸   │  │  member strip: JBM 10px tones
│ │   SYS :: SERVER REJECTED IT  ⟳  │  │  status line + inline retry (44pt)
│ ├─────────────────────────────────┤  │
│ │ ⚠ Creating client · Amber Chen ⟳│  │  loose row (56pt, panel anatomy)
│ └─────────────────────────────────┘  │
│ // IN FLIGHT · 3                     │
│ ┌─ L1 ────────────────────────────┐  │
│ │ ⟳ Updating project · Lyall St   │  │  quiet rows, no actions
│ │ ◷ Photo upload · 2 queued       │  │
│ └─────────────────────────────────┘  │
│ // DRAFTS · 1                        │
│ ┌─ L1 ────────────────────────────┐  │
│ │ ◷ Site visit — no client yet →  │  │  tap = resume capture
│ └─────────────────────────────────┘  │
│ // NOT LINKED · 4                    │
│ ┌─ L1 ────────────────────────────┐  │
│ │ ▦ Site visit deck · JUL 15  LINK│  │  thumb 32px, LINK inline (44pt)
│ └─────────────────────────────────┘  │
│         [ RETRY ALL · 2 ]            │  floating CTA only when failures>0
└──────────────────────────────────────┘
```

**Sections** (render only when non-empty; order fixed):
1. `// NEEDS ATTENTION` — `parked` + `failed` ops, parked autocreates, failed photos. Bundles absorb their members. Tones: tan (recoverable/attention), rose only for `parked` (out of auto-retries — mirrors existing `retryCount>=20` rose rule).
2. `// IN FLIGHT` — `pending`/`inProgress`/backoff + draining autocreates. Informational; rows show relative backoff ("RETRYING · NEXT IN 40S" via copy chokepoint).
3. `// DRAFTS` — `SiteVisitIdentityDraft`s with no committed lead AND an open visit. Tap resumes capture (existing resume machinery).
4. `// NOT LINKED` — orphan deck designs: local `(projectId == nil && opportunityId == nil && deletedAt == nil)`. Inline `LINK`.

**Bundle definition (RecoveryInventory, pure + unit-tested):** a site-visit draft/visit joins its client SyncOperation (by `clientId`), its autocreate-queue request (by clientId), the visit's attached deck-design ops, and its `LocalPhoto`s. Bundle tone = worst member (parked > failed > pending). Everything unjoined renders as loose rows. Inventory builder consumes plain value snapshots (ops, requests, drafts, photos, designs) so it's test-constructible without SwiftData.

**Detail half sheet** (row tap; §6.2): member list with per-member status + timestamps, the mapped error line (`SYS :: …` via SyncStatusCopy) with the raw error behind a `DETAILS` disclosure, then actions: `RETRY NOW` (primary), `EXPORT` (share sheet), `DISCARD` (destructive, confirm `DESTRUCTIVE. NO UNDO.`). Orphan sheet: `LINK TO…` primary + `EXPORT` + `OPEN DESIGN`.

**Export escape hatch:** share-sheet payload = deck design PNG (existing UIHostingController+drawHierarchy snapshot approach — never bare ImageRenderer) + text summary (client name/contact/address/notes + item statuses + raw errors) + failed photos as images. Nothing is ever unrecoverable.

**Discard semantics:** create-op/bundle → deletes local entity/entities + ops (confirm). Update-op → cancels the op (server state wins on next inbound). Parked autocreate → removes request. Orphans: no discard here (designs list owns deletion).

**Link picker** (from NOT LINKED): half sheet, search field, two scopes via segmented control `LEADS / PROJECTS` (client search folds into lead/project rows — client is a route to its lead, not a separate target). Pick → lead: enqueue `linkOpportunity` op (offline-safe); project: enqueue plain update op (`project_id` PATCH). Optimistic local set + row leaves the section.

**Entry points & badge:**
- `SyncStatusIndicator` pill becomes tappable → full-screen cover. Pill states: syncing (unchanged), `N pending` (unchanged), NEW `N NEED A LOOK` tan/rose when attention > 0 — counts from RecoveryInventory, not raw pending.
- Connection-restore toast (`PushInMessage`) gains tap → same cover.
- `SettingsView` DATA section: row `PENDING WORK` + trailing mono count (`—` when zero).
- `NotificationListView` sync section header gains `VIEW ALL →` when inventory non-empty.

**States:** loading = skeleton rows (§10); empty = `—` + `// NOTHING PENDING · ALL WORK SYNCED`; offline = rows tone-shift to waiting, retry enqueues; error loading inventory = `// ERROR — COULD NOT READ QUEUE` + RETRY.

**Tokens:** all via `OPSStyle` — L1 `.glassSurface()`, rows per SyncStatusPanel anatomy (16px status glyph, Mohave 15 title, JBM 10 status, 44pt actions), tan/rose/olive semantics, JBM tabular for counts/times, Cake Mono screen title, 5px button radius, one easing, reduced-motion honored. Zero hardcoded values; any missing token gets added to OPSStyle, not inlined.

**Anti-patterns actively avoided:** no accent on rows/links/sections (accent only on RETRY ALL primary CTA), no entity-type grouping, no verbs-on-scan-rows beyond the single dominant action, no third glass layer, no emoji/exclamation, numbers always mono.

## 5 · Copy (all through `SyncStatusCopy` — chokepoint rule)

New strings (final wording via ops-copywriter at implementation): screen title, section headers, bundle member glyph labels (CLIENT/LEAD/DECK/PHOTOS), backoff line, parked line (`SERVER REJECTED IT · WON'T RETRY`→ needs copy pass), draft row, orphan row, link picker, discard confirms, export summary template, pill badge, empty state. Every string unit-tested like the existing 16 cases.

## 6 · Testing & proof

- Unit: SyncErrorClassifier (every disposition row above); DataActor + OutboundProcessor policy (permanent→parked immediately, transient→cap→failed, sweep transitions incl. inProgress-stale); ClientLeadAutocreateQueue (park/backoff/retry-clears/delivery-binds-drafts); RecoveryInventory (bundle join, tones, section split); SyncStatusCopy new strings; payload sanitizers (deck create keeps opportunity_id, update strips it; DTO carries source_thread_key on both lead paths).
- Snapshot: PendingWorkView states (attention/in-flight/drafts/orphans/empty) via the SyncStatusPanel harness pattern (UIHostingController + drawHierarchy PNGs).
- Server: live RPC verification script per §2.
- Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` + full test pass on `iPhone 17, OS=26.5`.
- Live retro-verification: after M1 applies, the three stuck clients' leads must deliver on next app drain — verify rows appear in prod `opportunities` (this is the incident's own data healing).

## 7 · Explicitly out of scope

- Syncing `site_visits` rows to the server (visits stay local-only by design; recovery = bundle surfacing + resume + export).
- Auto-DISCARD/aging of parked items (never silently drop — the whole point).
- Web-side recovery UI.

## 8 · Taste items for Jackson (non-blocking; ship with defaults)

1. Screen name `PENDING WORK` (alternatives: `UNSYNCED`, `PENDING & DRAFTS`).
2. Pill badge escalation threshold (tan always vs rose when any parked — default: rose only when parked exists).
3. Whether DRAFTS section also lists committed-but-open site visits (default: no — only uncommitted identity drafts).
