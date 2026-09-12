# Site visit single choice implementation plan

**Goal:** Let company checklist editors define one answer from custom options and preserve each visit's option definitions offline and through sync.

**Architecture:** Keep the persisted kind `short_text`. Template fields carry optional `singleChoice`; answer rows carry a separate immutable `choice_snapshot`. Both use `{version:1,options:[{id,label}]}`. The selected answer remains `{text:label}`. Local snapshots live in existing encoded data attributes; no SwiftData stored property or schema version changes.

**Design system:** `ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, existing `OPSStyle` tokens and form components.

**Skills:** brainstorming, custom writing-plans/executing-plans, ops-design, interface-design, mobile-ux-design, ops-copywriter, systematic-debugging and audit-design-system. Root owns every compiler, test, simulator and database operation. This worker authors source and tests only.

1. Add the bounded option document and validation (2–20 options, distinct lowercase UUIDs, trimmed nonempty labels of at most 120 Unicode scalars, case-insensitive unique labels). Keep the persisted enum unchanged. Snapshot on answer creation; preserve through setters and clear. Distinguish valid answer from raw content custody.
2. Add separate DTO snapshot hydration and explicit pure answer wire serialization. Include snapshots in exact command/base/receipt comparison. Select v2 only for choice-bearing current/base/remote state, including conversion away from choices. Keep existing queued v1 commands intact and route each protocol to its matching apply/review/resolve RPC.
3. Add a distinct UI field type and option editor using FormField/FormSelectField, OPSStyle spacing, touch targets, fonts, surfaces and icons. Capture uses a vertical one-choice list, visible legacy text correction and explicit clear; preserve saved records as readable text.
4. Author focused validation, DTO, snapshot, clear, v1/v2 replay and persistence/merge regression tests. Root executes them after source review and integration; there are no worker runtime claims.
5. Source-review changed paths, inspect token usage, commit an atomic implementation and hand off exact suite names and remaining server/visual acceptance requirements. Root owns the additive server migration, mixed-client write guard and Bible/web updates.
