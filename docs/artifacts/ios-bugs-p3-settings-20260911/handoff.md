# IOS BUGS - P3-2: Site Visit Types settings

Base: `b08de1042bed5d272d52daa83ef1bc30a501fa86` in the private detached worktree `ios-bugs-p3-settings`.

## Keyboard report: evidence and change

Report `ea83a41c-33e8-477a-91f5-3db669c4ab2c` says the settings keyboard lacks the standard DONE action. The P1 summary explicitly leaves its original cause unestablished: the submitted screenshot has no software keyboard. P1 verified the description editor separately with eleven passing input checks.

The current real editor exposes three input paths:

| Input | Implementation | DONE ownership |
| --- | --- | --- |
| Name | `FormField` using SwiftUI `TextField` | App-wide `UITextField.textDidBeginEditingNotification` observer installs the canonical accessory and reloads active input views. |
| Description | `FormTextEditor` using `FormMultilineTextView` | Accessory is prepared in `makeUIView` before focus; app-wide observer remains fallback. |
| Each editable checklist field label | `FormField` using SwiftUI `TextField` | Same app-wide observer as the name. |

Sources: `OPS/Views/Settings/SiteVisitTypeSettingsView.swift:304`, `:319`, `:432`; `OPS/Styles/Components/FormInputs.swift:49`, `:176`; `OPS/Styles/Components/OPSKeyboardDoneAccessory.swift:199`, `:244`, `:254`; `OPS/AppDelegate.swift:54` starts the coordinator before the app UI.

The initial source review found no bypass and changed only `SiteVisitTypeEditorView` visibility for the real-editor regression. Root's subsequent runtime diagnostics established a lifecycle defect: the global installer executes correctly, but SwiftUI replaces its accessory while completing focus.

In all three tests on root's iOS 26.5 simulator, the same live `UITextField` remained first responder; its canonical `OPSKeyboardDoneAccessoryView` existed during `textDidBeginEditing` and immediately after `becomeFirstResponder`, then became the zero-size, unattached SwiftUI `RootUIView` on the following main-queue turn. The NAME and FIELD LABEL shared that replacement view. DESCRIPTION retained its prepared canonical accessory. Keyboard did-show completed, its frame was `(0, 487, 402, 387)`, pending notifications were empty, and the same editor sheet remained presented. This establishes an actual accessory replacement in the fixture presentation route, not a disabled software keyboard or obsolete field reference. The original user screenshot still cannot establish its exact runtime state.

The scoped repair in `OPS/Styles/Components/OPSKeyboardDoneAccessory.swift` retains each text field's canonical accessory with weak field ownership, then checks once on the next main-queue turn after real did-begin. It restores/reloads only when replaced, only while the same field remains first responder and the coordinator's started lifecycle is unchanged. It uses no private SwiftUI type names, polling, new input implementation, or draft binding changes. The real-editor failing tests are the regression; root must prove that this one reconciliation point remains stable through text entry, focus changes and DONE.

## Prepared regression

New suite: `OPSTests/Views/SiteVisitTypeSettingsKeyboardTests.swift` (three tests).

- Presents the actual `SiteVisitTypeEditorView` in `AppHostWindow` through `fullScreenCover(item:)` -> NavigationStack -> `sheet(item:)` -> NavigationStack, matching the settings presentation containers. The root Settings and Site Visit Types list views are fixtures: routing, wizard/deep-link wrappers, template seeding and server refresh are explicitly excluded. The editor/input controls are real.
- Does not call coordinator `start`, `prepare`, post editing notifications, or assign an accessory. The app's real startup and UIKit editing notifications own installation.
- Checks NAME and FIELD LABEL independently after keyboard did-show/frame completion and stable model/presentation-layer geometry. DONE must have a full screen-contained touch target, visible/unclipped ancestors, sufficient combined opacity and a successful real window hit test.
- Captures full screen-sized editor/keyboard context by drawing real windows' hosted views, never UIWindow itself. The keyboard is first rendered alone on a transparent canvas and its key region must pass a nonblank check independently; editor pixels cannot falsely validate an unrenderable remote keyboard. The combined image, isolated keyboard image and common screen-coordinate geometry are attached. A missing independent keyboard host or unrenderable system keyboard fails explicitly and is a proof-environment limitation, not evidence that DONE is broken.
- DONE must produce a completed keyboard did-hide, unchanged presentation geometry after quiescence, no pending controller transition/dismissal and the same attached sheet. Each post-DONE check resolves fresh fields from that live sheet before checking retained drafts.
- Switches NAME -> DESCRIPTION -> FIELD LABEL -> NAME -> DESCRIPTION, checking separate responder ownership, accessory reuse, correct DONE dismissal and retained drafts.
- Uses UIKit text entry and the real DONE control. No SAVE action is invoked; there is no template/answer/server mutation.

Mutations these tests are designed to catch: removing the AppDelegate coordinator startup; omitting the UITextField notification observer; failing to reload an active TextField after installing its accessory; sharing an accessory whose weak dismissal target still points at the preceding field; dismissing the sheet from DONE; losing local draft state on surrounding SwiftUI updates.

**Repair execution is outstanding.** Root ran the original and diagnostic revisions: both failed all three keyboard tests at focus settling, zero skips. The second run's class/identity timeline established the replacement above. Logs and attachments are under `/private/tmp/ops-ios-bugs-p3-20260911/keyboard-tests-2*`. Per the serial build baton, this worker ran no compiler, build, test, simulator, device, install or release command. `git diff --check` passes. Root should rerun `OPSTests/SiteVisitTypeSettingsKeyboardTests` after integrating the repair. Remote keyboard rendering must be independently available for full-image proof; a generic nonblank composite is insufficient. Existing `SiteVisitTypeSettingsInputTests` remains unchanged.

The failed diagnostic run also attributed internal errors to cleanup while the test's assertion error unwound through a defer that drives UIKit's run loop. The `launch_type` Double mismatch is an expected `try?` probe in `AnyCodableValue` before its valid String decode. `InvalidTransition` attribution still needs verification. The harness now captures the original assertion error, performs keyboard -> sheet -> cover -> original-root cleanup sequentially outside that unwind, logs each phase and rethrows the unchanged original error. It does not suppress errors or claim clean teardown before the next run.

The report must remain open without a claimed new fix until those checks run and the original path is reproduced or an exact device observation establishes the cause.

## Multiple-choice request: confirmed contract

Report `1995a554-7fb1-4090-96c4-4e20a901c3a4` says “Add multiple choice option to checklist.” This worker investigated only; no model, schema, validator or feature implementation changed. P19 reserves `SiteVisitTypeSettingsLogic.swift`, the model files and V28 during its regression.

Current source:

- `SiteVisitFieldKind` has exactly eight kinds; no custom-choice kind (`OPS/DataModels/SiteVisits/SiteVisitType.swift:11`). Field definitions contain no options (`:35`).
- `SiteVisitChecklistValue.choice` is one arbitrary string, but the capture UI presents only YES / NO / N/A for `.yesNoNA`; that property does not constitute custom-choice support (`SiteVisitCaptureView.swift:1938`).
- Selecting a template snapshots label, kind, required, help text and order into answer rows. It does not snapshot custom option definitions (`SiteVisitType.swift:382`). Once any answer exists, settings refresh intentionally preserves the visit's existing snapshot (`SiteVisitCaptureViewModel.swift:367`).
- `SiteVisitChecklistAnswerDTO` decodes the raw kind strictly (`OPS/Network/Supabase/DTOs/SiteVisitDTOs.swift:350`). An unrecognized kind throws during a page fetch. The template's local `fields` accessor catches a field-array decode error and returns an empty checklist (`SiteVisitType.swift:202`).
- `SiteVisitWire.canonicalChecklistValue` explicitly copies the five existing value members (`SiteVisitDTOs.swift:896`); any new value metadata must survive that copy and the sync/recovery serializers as well as Codable encoding.

Read-only production catalog inspection on 2026-09-11 confirms:

- `site_visit_types.fields` and `site_visit_checklist_answers.answer_value` are `jsonb`. Answer `kind` is `text`, and the server CHECK permits only the same eight kinds.
- `private.site_visit_type_fields_valid` also permits only those eight kinds. It bounds the document to 1–100 fields and 131,072 bytes, requires at least one visible field, validates identifiers/labels/help text and rejects duplicate field IDs. No option document is defined.
- `answer_value` has an object/1,048,576-byte shape bound, not a custom option-membership contract.
- `private.agent_p2_site_visit_checklist_value_v1` returns `source_invalid` for an unknown kind. For `yes_no_na`, only yes/no/N/A variants are accepted; storing an arbitrary custom choice under `yes_no_na` would break the agent read contract.
- `private.refresh_site_visit_compatibility` includes only checkbox/yes-no/short-text/long-text answers in the shared notes projection. A new kind would be omitted unless this function changes.
- Existing template authority remains company-scoped reads and `settings.company` writes; checklist rows keep their current company/parent access policies.

Exact constraint, policy and function readback is in `live-checklist-contract-readback.json`. This was catalog-only; no user rows, changes, grants or migrations were executed.

The current primary `ops-web` checkout is an older dirty branch at `bcd252e5`; it was read only and is not a verified current deployment reference. Its site-visit service maps `site_visits.notes`, and its site-visit detail reads that projection. The production compatibility function is the current verified cross-surface contract. Any implementation must identify the current deployed web source before edits.

## Bounded implementation recommendation for the root

Interpret the requested multiple-choice control as one selected answer from custom options. Multiple simultaneous selections would require a different answer shape and is not implied by this scoped investigation.

Use an explicit `single_choice` kind with stable option IDs and ordered, nonblank option labels; snapshot the full option list and selected option identity/label at visit creation. Preserve historical answers when a template option is renamed, removed or reordered. Do not reinterpret the existing `yes_no_na` kind.

The existing encoded template/answer JSON storage could carry optional option/snapshot metadata without adding a new SwiftData stored attribute, but this still requires changing the reserved model source and auditing frozen-schema compatibility with P19. This is a candidate design, not proof that no schema version is needed.

The complete vertical must include:

1. Company settings option creation/removal/reordering, bounded option count and label length, stable IDs, duplicate/blank validation, and a usable default when switching kind.
2. Offline capture selection/clear, required-answer membership validation, immutable per-visit options, completion/review/record rendering and accessibility.
3. Template and answer encode/decode, canonicalization, outbox/inbound merge, replay/recovery/custody copies and round-trip tests. Existing empty and old eight-kind payloads must still decode identically.
4. An additive server migration updating the type validator, answer kind check, option/snapshot validation and legacy notes projection, plus the agent read helper and its result contract. Preserve existing RLS/permissions and bounds; apply no production migration without explicit approval.
5. Current deployed web readers/exports and generated contracts, so selected labels remain visible wherever the visit appears.
6. An explicit mixed-version rollout strategy before any new kind is emitted. Adding `single_choice` now breaks older strict iOS decoders. Encoding choices as extra metadata on `short_text` avoids an unknown enum but older template/value round trips discard that metadata; it does not preserve the required option contract. A minimum-supported-client gate or versioned compatibility protocol must be proven before enabling writes.

Required tests cover blank/duplicate/oversized options, unknown selected IDs, two identical labels with distinct IDs policy, option rename/delete/reorder after capture, switching field kind, required/cleared state, template edits with an existing answer, offline replay, mixed-version payload handling, page decode containing one new kind, note/agent/web projection and unchanged authority. No feature work should land inside the current model reservation.
