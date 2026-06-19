# Around-call lead capture + call logging — spike + spec (item 154cb8a3)

**Status:** Feasibility spike complete + adversarially verified (2026-06-19). Ready for a focused build session.

## Spike verdict — reset "in-call" to "around-call"

iOS gives a third-party (non-VoIP) app **no** custom in-call UI, **no** access to the system call log, and **no** way to create app data or open the app *during* a native Phone call. Verified against Apple docs and the live repo (zero CallKit/CXCallObserver/Call Directory/AppIntents/SiriKit code; zero `.appex` targets):

- **CXCallObserver** reports only call *state* (connected/ended/outgoing/onHold), exposes **no phone number**, and fires reliably **only while OPS is foregrounded**. Usable to drive a best-effort post-call prompt, nothing more.
- **CallKit Call Directory** extension can only label/block numbers from a pre-staged DB — it is *not* launched on an incoming call and cannot write app data.
- **App Shortcuts** (`AppShortcutsProvider` + `AppIntent`) auto-expose a one-tap action to Siri/Spotlight/Action Button (iPhone 15 Pro+)/Control Center **with no setup** — and live in the **main app target** (NO new extension target, NO special entitlement; the design's original "AppIntents extension" framing was wrong, corrected in verify).
- **Call recording/transcription is not feasible for a 3rd-party app** — iOS exposes no API to tap a native call's audio. Substitute: an in-app **voice note** dictated after the call (mic + Speech already authorized), saved to the activity body. Canada is one-party consent (operator's own dictation is lawful); never market as "call recording."

## Shippable design — "Call log" (around-call capture)

Three App-Store-safe entry points, all funneling into the **existing** data layer (`OpportunityRepository.create` with `source:"phone"`; `OpportunityRepository.logActivity` type `"call"`; a prod trigger auto-advances `new_lead → qualifying` on first activity):

1. **Outbound post-call prompt (strongest path).** `ContactCard` already places calls via `tel:`. Record the outbound intent locally (who/when); when OPS next foregrounds and `CXCallObserver` saw `hasEnded`, surface a non-blocking "Log that call?" sheet pre-filled to that exact lead (outcome chips spoke/voicemail/no-answer, optional duration, optional voice note).
2. **Inbound/manual capture.** Global FAB → "New lead from a call" → `CNContactPicker` (already wired) or manual entry → create lead (`source:"phone"`) + log the inbound call activity in one flow (mirror `LogActivityViewModel.save`). If the number matches an existing lead, switch to Attach.
3. **App Shortcut "Log a call to OPS"** in the **main target** → Action Button/Siri/Spotlight/Control Center → deep-links (`ops://leads/<id>`) into the capture sheet.

Optional later: a Call Directory **recognition** extension labeling inbound pipeline numbers as "OPS lead: <name>" — the ONLY piece needing a new `.appex` + `com.apple.developer.callkit.call-directory` entitlement + App Group (external gate). Pure recognition, no data write.

## Build plan (focused session)

1. **Additive, nullable migration** on `activities` for call provenance: `call_source text`, `caller_number text`, `call_started_at timestamptz` (verify live schema first; nullable-only per the iOS-sync constraint). Extend `CreateActivityDTO`/`ActivityDTO` + CodingKeys.
2. **`normalizePhone(_:)` + `OpportunityRepository.findByContactPhone(_:)`** (none exist) — match a caller to an existing lead to avoid duplicates (match locally-synced `Opportunity.contactPhone`). Mandatory to prevent pipeline pollution.
3. **`CallStateObserver`** (CXCallObserver wrapper, foreground-only) + **`CallLogStore`** (records outbound intents from `ContactCard`'s `tel:` tap).
4. **`LogCallSheet`** (model on `LeadLogActivitySheet`): outcome/direction/duration/voice-note → `logActivity`/`create`.
5. **FAB entry** "Log a call" + the foreground post-call prompt.
6. **`LogCallToOPS: AppIntent` + `AppShortcutsProvider`** in the main target (no extension).
7. Gate every surface on `pipeline.view` + the `pipeline` feature flag (match all Leads surfaces). Copy via `ops-copywriter`; motion/haptics via OPSStyle tokens.
8. Recording stretch = **in-app voice note only** (mic + on-device Speech), transcript → activity `body_text`. No phone-call audio.
9. Update the bible (pipeline section) + schema docs.

**Permissions/sync:** additive-only schema; anon-role RLS already covers opportunities/activities inserts; gate on `pipeline.view`. **Build verifies with `CODE_SIGNING_ALLOWED=NO`**; the optional Call Directory extension is the only piece needing portal provisioning.

Full verified spike output: workflow `wf_30ed4b45-2e9` (CallKit lead-capture spike).
