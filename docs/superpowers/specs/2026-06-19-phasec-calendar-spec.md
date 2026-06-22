# Phase-C calendar — detected-event confirm-to-add + connect calendar (item 63144953)

**Status:** Investigation complete (2026-06-19). The **connect-calendar half is already shipped**; the **detected-events half is blocked** on server work + a deliberate constraint. Spec'd for a focused build session, to land when its prerequisites do.

## Part A — "connect Apple/Google/Outlook calendar" — ALREADY SHIPPED

`CalendarMirrorService` (`OPS/Services/CalendarMirrorService.swift`) is a one-way EventKit mirror that pushes OPS schedule rows (`CalendarUserEvent` + `ProjectTask`) into a dedicated "OPS" `EKCalendar` in the device's **default calendar account** — which is whatever Apple/Google/Outlook account the user set as default in iOS Settings. There is **no provider OAuth and none is needed**: EventKit routes the calendar to the backing account. `IntegrationsSettingsView` already exposes the CONNECT/DISCONNECT card ("Mirror OPS work… into the Apple, Google, or Outlook calendar account set as default on this iPhone"). The canonical add seam is `CalendarMirrorService.shared.mirrorEvent(opsId:source:)` (idempotent, no-ops unless enabled + `.fullAccess`).

**Optional enhancement** (only if the operator must target a *specific non-default* Google/Outlook calendar): change `ensureCalendar()`'s source selection (lines 290-294) to let the user pick an `EKSource`/`EKCalendar`, persisting the choice. Today it always uses the default account — adequate for the request as written.

## Part B — "Phase-C agent auto-adds detected events (with confirmation)" — BLOCKED, decoupled design

### Why it's blocked (must clear before building)
1. **Phase C is not live for the app.** Per standing guidance it is headless, Canpro-only, not live-deployed, and **the app must never depend on it.** A feature that requires the engine to be running violates that.
2. **iOS cannot read detected events today.** Phase-C detected events are rows in `agent_memories` (category=`commitment`, with a nullable `due_date` = the detected event time; also `project_event`/`timeline` categories, date-less). Its RLS is `company_id = (auth.jwt()->>'company_id')::uuid`, which is **NULL for iOS's Firebase-bridged JWT** (the known auth-claims gap) — so the policy matches zero rows for an iOS session. There is **no iOS-facing read path** (no company-scoped RPC, no `/api/inbox/commitments` mobile equivalent).

### Prerequisites (server, not iOS)
- A **SECURITY DEFINER RPC** (or mobile API endpoint) that returns a company's unresolved, time-bearing detected events, matching identity by **email/`firebase_uid`** (the established OPS pattern — never `auth.uid()`/JWT `company_id`). Return commitment id, `content`, `due_date`, `entity_id`, `confidence`, `resolved_at`.

### Decoupled iOS design (build when the prerequisite RPC exists)
- A **"Suggested events" review surface** that calls the RPC and lies **fully dormant when it returns nothing** (no Phase C running → no rows → feature invisible, no errors). This satisfies "app never depends on Phase C": iOS only reads a list; an empty list is the normal, healthy state.
- Each suggested event → a confirm card (the detected `content` + `due_date`, design-system compliant). On **confirm**: create a `CalendarUserEvent` (type `personal`, the detected title/time) via `CalendarUserEventRepository.create` — which already fires `mirrorEvent` → the event lands in the user's connected calendar. Mark the source commitment resolved (`resolved_at`) via the RPC so it isn't re-offered ("not already in the calendar").
- Dedup ("not already in the calendar"): before offering, skip commitments whose `resolved_at` is set, and skip if a matching `CalendarUserEvent` (same title+day) already exists.
- Gate the surface on the calendar feature + the user's own events; require `CalendarMirrorService` enabled (reuse `CalendarMirrorPromptSheet` consent) for the add-to-phone step. Honor `NSCalendarsFullAccessUsageDescription` (verify present).

### Recommendation
Ship **Part A** as-is (already done; optionally add explicit calendar-account selection). **Part B** is a server-gated feature: build the RPC first (server), then the dormant iOS review surface. Do not couple the app to the Phase C engine — the dormant-when-empty contract is the whole point.

Verified investigation: workflow `wf_3b0446fd-30b` (phasec-calendar-design); maps verified by citation against the live code + Supabase.
