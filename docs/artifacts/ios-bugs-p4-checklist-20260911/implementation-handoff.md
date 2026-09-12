# IOS BUGS — P4 checklist handoff

Base: `3f5eaffebd3d81e22d9165140f3c002bc4d22edd`. Report: `1995a554-7fb1-4090-96c4-4e20a901c3a4`.

The implementation adds one selected answer from custom options. It keeps all eight persisted kinds unchanged. A template field uses `kind: short_text` and optional `singleChoice: {version:1,options:[{id,label}]}`. An answer carries the identical immutable document in `values.choice_snapshot`, beside its pure `answer_value` (`{}` or `{text: exactLabel}`). Option IDs are canonical lowercase UUIDs. Options number 2–20 and labels are nonempty, trimmed, at most 120 Unicode scalars, and distinct under Unicode root lowercasing/canonical equivalence. Selected IDs derive from byte-exact label lookup; labels themselves are not Unicode-normalized. The server remains authoritative for Unicode validation and document bounds.

Local snapshots occupy optional Codable metadata in the existing `answerValueData` blob. No stored SwiftData property or schema version changed. The snapshot survives ordinary edits and clear; explicit server hydration replaces the whole local value. Separate DTO hydration avoids leaking metadata into `answer_value` or evidence. New command/base/receipt comparisons include the snapshot. The recovery vault already stores the blob and operation payload bytes, so its production serializer remains unchanged.

The field type picker gains Multiple choice with an option editor supporting add/remove/reorder. Capture shows a vertical one-choice list and a clear action. Unrecognized legacy text remains visible, invalid as an answer, and protected as user content. Existing packet/record readers continue to show selected and historical raw text. Pending Work displays option labels in both compared versions.

The v2 protocol is `site-visit-writes:2026-09-11.v2`, using `apply_site_visit_write_v2`, `review_site_visit_write_v2`, and `resolve_site_visit_write_v2`. Current/base/remote metadata selects v2, including conversion away from choices. New answer specifications also inspect the current referenced template field; this permits a historical nil snapshot to remain nil through the new protocol. The queue cannot coalesce across protocol revisions, and existing requests retain their original bytes. An explicit review/resolve may use v2 based on current metadata while transmitting the unchanged original command, matching root's additive server resolver contract. There is no automatic v1 fallback if v2 is unavailable: saved work remains queued for retry/review.

## Source verification and runtime handoff

This worker ran no compiler, tests, simulator, device, SQL, install or deployment. `git diff --check` passes. Root owns execution and server/Bible/web integration.

New focused suites:

- `OPSTests/SiteVisitSingleChoiceTests`: validation/Unicode, exact label matching, old eight-kind decode, historical snapshot immutability, explicit clear, wire hydration, conditional v2 routing, exact receipt comparison, disk reopen, inbound fresh/clean/dirty merges, unchanged queued v1 with a v2 descendant, and readable packet text.
- `OPSTests/SiteVisitSingleChoiceControlTests`: actual capture row selection/clear via accessibility at 320pt and accessibility text size, plus the actual settings editor adding an option. Four hosted VIEW screenshots and geometry attachments are required; no duplicate test-only choice controls, window-level drawing or screenshot skips. Missing accessibility bridging is an explicit failure. The shell is a hosted fixture; route loading and server save are excluded.
- `OPSTests/SiteVisitFieldWorkflowTests/testCustomChoiceSelectionClearAndRequiredStateSurviveReopenWithOriginalOptions`.
- `OPSTests/SiteVisitRecoveryVaultTests/test_choiceSnapshotAndExactV2CommandSurviveAccountBoundVaultRestore`.

Run related existing checklist settings/DTO/write/versioned sync/persistence/content/recovery tests as root's changed-vertical verification. Server fixture checks and mixed-version SQL behavior are independently owned by root.

## Design token audit

Reviewed every added production UI line against `DESIGN.md`, `mobile/MOBILE.md`, and `OPSStyle`: FormField/FormSelectField reuse; spacing1/2/3; touchTargetMin on the actual button labels; buttonRadius; body/captionBold/metadata typography; primary/secondary/tertiary text and existing surface tokens; semantic tan for correction text; SF Symbols through OPSStyle. No new hardcoded color, font size, spacing, radius, motion or touch-target value was introduced. Existing surrounding row literals predate this change and were not expanded. New controls wrap long labels and expose selected traits and explicit action labels. Runtime geometry/pixel proof remains outstanding until root runs and inspects the attached screens.
