# Field Reports 2026-09-08 — Leads Cluster

> **For Claude:** REQUIRED SUB-SKILL: `custom-skills:executing-plans`. Diagnose defects with `superpowers:systematic-debugging` before touching code. UI work loads `ops-design` + `custom-skills:mobile-ux-design`; copy goes through `ops-copywriter:ops-copywriter`; finish with `custom-skills:audit-design-system`.

Six reports the founder filed from his phone today, all on the Leads tab. Read each report's row (`bug_reports`, Supabase `ijeekuhbatykdomumfjx`, read-only) and its screenshot yourself before starting it. Screenshots are S3 objects (`s3:bug-reports/<company>/<id>/screenshot.jpg`, bucket in `ops-web/.env.local`); the principal's copies are at `/private/tmp/claude-501/-Users-jacksonsweet-Projects-OPS/d83a46f2-7671-47fc-aeba-fd0aa3e52fd5/scratchpad/shots2/<id8>.jpg`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; every value an `OPSStyle` token.

## 1. `908888f6` — "Add client in lead details does not work" (DEFECT, first)

Lead detail (Kyle Kingsley, qualifying) shows the `+ ASSIGN CLIENT` chip in the DETAILS card. The chip is `ProjectInfoDoc.empty` in `OPS/Views/Leads/Components/LeadDetailsDocument.swift:238-246`, calling `onEditClient`, which `OPS/Views/Leads/LeadDetailView.swift:378` wires to `showingClientPicker = true`. The hold-to-edit tap-swallow fix (`c69df81a`) IS on main, so this is something else. Establish exactly what fails: does the picker present (a `.sheet` competing with another presentation? a state on a view that is not in the hierarchy?), does the selection write `opportunity.clientId`, does the outbound op record, does the row re-render? Reproduce on the simulator; a hermetic host may be the fastest way (mirror `SiteVisitCaptureQARuntime`). Fix the root cause; add a test that would have caught it.

## 2. `18dea542` — Link Project search does not match client names

`ConvertToProjectSheet.swift:2590` `matches(_:)` checks `displayTitle` and `address` only. Match the client name, the lead/contact name, and the address's city/postal code as well — and put the client name on the row so what matched is visible ("search matches what the operator can see"). Test the predicate.

## 3. `2a89477d` — Filter chips must follow the search

`LeadsTabView.swift` ~500-530: chips deliberately carry raw bucket counts. The founder wants them live: while a search is active, each chip shows the count of matches within that bucket (raw counts return when the search is cleared). Keep the group-header behaviour. Test the counting rule.

## 4. `53e869f6` — Long-press the lead title to edit it

The header title (e.g. `JAIME TAYLOR - LEAD`, auto-generated) gets the same hold-to-edit affordance the dossier fields have (`holdToEdit`): hold → inline title editor → save writes `opportunity.title` through the existing edit path (with the outbound op). Respect the same `canEdit` gate. Snapshot proof of the editing state.

## 5. `52cc8dae` — Pending site visit banner in lead details

When a lead has a booked, not-yet-completed/cancelled site visit, a banner sits directly under the header: `SITE VISIT · TUE SEP 9 · 2:00 PM` with `START` (opens the capture flow), `REBOOK` (the booking sheet, prefilled), `CANCEL` (confirm). Reuse the site-visit booking components (live since 2026-08-14 — find them under `OPS/Views/SiteVisits`). Design per MOBILE.md (glass surface, 44pt targets, mono time). Snapshot proofs: banner present, absent.

## 6. `9a49bd47` — Book a site visit / add a lead for an existing client

From a client (Job Board › Clients › client detail), add `NEW LEAD` (creates a lead prefilled with the client) and `BOOK SITE VISIT` (creates the lead, then opens booking). Find what the client detail offers today (`ClientListView.swift`, `ClientSheet.swift`) and the lead-create sheet's prefill capability; wire the shortest honest path. Snapshot proof of the client actions.

## Verification

Worktree-local DerivedData, private simulator, class-level `-only-testing`, verdicts from the xcresult; proof PNGs via `FixedSizeSnapshot` under `docs/artifacts/field-reports-leads-20260908/`; commit per item on your branch with conventional messages; no push; no AI attribution.
