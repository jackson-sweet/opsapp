# Lead Photo Optimistic Display Implementation Plan

**Goal:** Make multi-photo lead imports visible immediately, durable before upload, and safe under concurrent/background queue draining.

**Required skills:** `custom-skills:executing-plans`, `superpowers:test-driven-development`, `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`

**Design-system sources:** `ops-design-system/project/DESIGN.md`, `ops-design-system/project/mobile/MOBILE.md`, `ops-ios/OPS/Styles/OPSStyle.swift`

## 1. Lock the regression with focused tests

- Add service-level coverage proving a selected batch is durably staged and published in input order before any upload drain.
- Add coverage proving a drain preserves queue items that arrive while network work is suspended.
- Add presentation-state coverage proving picker reservations precede staged and remote tiles.
- Run only the focused regression target and confirm the new assertions fail for the current implementation.

## 2. Make lead image staging local-first

- Split staging from upload draining in `LeadImageService`.
- Assign stable local identifiers, write compressed files, append queue entries, publish, and persist before starting network work.
- Return from `addImages` after staging and launch drain as background work.
- Reconcile a drain snapshot by identifier so newer queue entries cannot be clobbered.
- Preserve offline retry, relaunch recovery, deletion, and remote echo behavior.

## 3. Reserve photo-strip positions immediately

- Track stable picker reservation identifiers in `LeadDetailView`.
- Publish reservations synchronously from the picker change handler.
- Decode picker items concurrently and restore original selection order.
- Keep successful siblings if one item fails.
- Remove reservations only after corresponding local thumbnails are published.
- Feed reservation identifiers through `LeadDetailsDocument` to `LeadPhotosSection`.
- Render non-interactive placeholders using existing photo geometry and `OPSStyle` tokens.

## 4. Verify the complete behavior once

- Run the focused test set once after implementation.
- Inspect concurrent build activity before invoking Xcode.
- Run at most one generic-device build if focused tests do not already compile the changed app surface.
- Audit changed UI files for hardcoded color, spacing, radius, or typography values.

## 5. Document, land, and close only this bug

- Update the lead-photo contract in the OPS Software Bible.
- Commit only the isolated lead-photo changes.
- Merge the atomic commit into local `main` without pushing.
- Mark bug `9764f289-f118-4f5d-ad3d-2234af0a64a4` resolved only after readback, with human review requested for immediate multi-select display and background upload behavior.

