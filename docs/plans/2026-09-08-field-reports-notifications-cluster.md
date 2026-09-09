# Field Reports 2026-09-08 — Notifications + Bug-Report Tool Cluster

> **For Claude:** REQUIRED SUB-SKILL: `custom-skills:executing-plans`. UI work loads `ops-design` + `custom-skills:mobile-ux-design`; copy goes through `ops-copywriter:ops-copywriter`; finish with `custom-skills:audit-design-system`.

Three reports the founder filed from his phone today. Read each report's row (`bug_reports`, Supabase `ijeekuhbatykdomumfjx`, read-only) and its screenshot; the principal's copies are at `/private/tmp/claude-501/-Users-jacksonsweet-Projects-OPS/d83a46f2-7671-47fc-aeba-fd0aa3e52fd5/scratchpad/shots2/<id8>.jpg`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; every value an `OPSStyle` token.

## 1. `589e3b1e` — "Several REPLY WAITING NO OWNER notifications… does not take me to any lead"

Facts (verified in prod): these are `type=system`, `persistent`, `deep_link_type=inbox`, `action_url=/inbox/<thread>` rows the web's Phase C agent emits per email thread, hourly batches; 4 of 5 sampled threads have `email_threads.opportunity_id = NULL` — there is no lead. iOS already resolves `/inbox/<thread>` → `email_threads.opportunity_id` (`OpportunityRepository.opportunityId(forEmailThreadId:)`, `NotificationListView.emailThreadId(fromActionUrl:)`) and falls back to the Job Board when nil — which is the dead tap the founder describes. The generator half is filed to the web session as bug `fc7eebd9`; the iOS half is yours:

- Group every inbox-type notification whose thread resolves to no lead into ONE row: title `Replies waiting in the inbox`, body `<N> customer replies are not linked to a lead yet. Handle them on the web.` (copy via ops-copywriter). No dead tap: the row expands to show the count and a `MARK READ` action that marks the whole group read. Resolution runs once per thread id and is cached for the list's lifetime (no per-row network storms; batch the select with `.in("id", …)`).
- Ones that DO resolve to a lead keep opening the lead.
- Tests: the grouping rule (pure), the batched resolver seam, and a snapshot of the grouped row.

## 2. `74bbb5b7` — "APPOINTMENT NEEDS REVIEW … Angela Wall has no site visit"

Facts (verified): `type=phase_c_appointment_review`, `action_url=/pipeline?opportunityId=9c137fe0…`, generic body. The source is `phase_c_bilateral_event_handoffs` row `83ede0eb…` with `status=review`, `event_kind=site_visit`, `starts_at=NULL`, `review_reason=event_date_or_time_unresolved` — OPS read an email about a site visit but could not tell when. The lead has no `site_visits` row. The generator half is filed to the web session as bug `f0b39d3d`; on iOS:

- Render this type with the lead's name (resolve the opportunity locally from the action_url id) and an honest body: `OPS read an email about a site visit with Angela Wall but couldn't tell when. Set the time.` Action label `SET TIME` → opens that lead's site-visit booking sheet (live since 2026-08-14; find it under `OPS/Views/SiteVisits`). If the handoff row is readable by the app (verify `phase_c_bilateral_event_handoffs` grants/RLS with SQL before relying on it), use `review_reason` to choose the sentence; otherwise the sentence above is the default for this type.
- Tests: the copy/action mapping (pure) and a snapshot of the row expanded.

## 3. `5aabcc3a` — "Need to allow user to select an element with bug report if necessary"

Add an optional POINT AT IT step to the screenshot-triggered bug report (`OPS/Services/BugReport/ScreenshotBugReportOffer.swift`, `BugReportPresenter.swift`, `BugReportTriggerCoordinator.swift`): the report sheet shows the captured screenshot; the operator taps the spot; the tap is marked on the screenshot (a small ring in `OPSStyle.Colors.primaryAccent` — the one accent on the sheet) and the report gains `custom_metadata.element = { x, y, label, identifier, viewType }` from a hit-test of the app window's view hierarchy captured at trigger time (accessibility label/identifier of the deepest view). One tap, skippable, no new screen. Copy via ops-copywriter (`POINT AT IT` / `SKIP`). Tests: the hit-test mapping seam (pure) and a snapshot of the sheet with a mark.

## Verification

Worktree-local DerivedData, private simulator, class-level `-only-testing`, verdicts from the xcresult; proof PNGs via `FixedSizeSnapshot` under `docs/artifacts/field-reports-notifications-20260908/`; commit per item on your branch with conventional messages; no push; no AI attribution.
