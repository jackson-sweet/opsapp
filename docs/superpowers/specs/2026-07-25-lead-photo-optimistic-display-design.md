# Lead Photo Optimistic Display Design

**Date:** 2026-07-25  
**Status:** Approved

## Problem

Selecting several photos for a lead closes the system picker, but the lead sheet stays visually unchanged while every asset is decoded and uploaded. The finished photos then appear all at once. This makes a successful action look lost.

The delay comes from two serial boundaries:

1. `LeadDetailView` waits for every `PhotosPickerItem` to decode before handing images to the service.
2. `LeadImageService` only publishes a local photo when an upload fails. Healthy uploads remain invisible until the full batch has reached storage and the opportunity row is reconciled.

## Product Decision

The photo strip owns the action immediately:

- Reserve one stable, tokenized tile for every picker selection as soon as the picker closes.
- Decode selected assets concurrently while preserving selection order.
- Replace reserved tiles with locally persisted thumbnails before any network upload begins.
- Upload and reconcile in the background.
- Keep successful siblings when one selected asset cannot be decoded.
- Preserve the existing `QUEUED` presentation for locally staged photos and existing remote-photo behavior.

There is no new modal, blocking progress state, explanatory copy, or decorative motion.

## Interaction States

1. **Selected:** Reserved photo tiles appear immediately in the existing horizontal strip.
2. **Decoded and staged:** Each reservation becomes the real local thumbnail in the same batch position. The durable local queue is already written.
3. **Uploading:** The local thumbnail remains visible with the existing queued treatment. The lead sheet stays interactive.
4. **Synced:** The remote URL replaces the local queue entry without creating a duplicate.
5. **Partial failure:** Failed selections leave the reservation state; successful selections continue. Existing save-error feedback reports the partial failure.
6. **Offline or interrupted:** Staged files and queue metadata survive, remain visible, and retry later.

## Visual Contract

- Reuse the current 84-point lead-photo tile geometry.
- Use only `OPSStyle` color, radius, typography, spacing, and icon tokens.
- Reserved tiles are quiet placeholders inside the existing photo row, not a page-level loader.
- Maintain at least the existing mobile touch targets.
- Add no custom animation. State replacement must remain legible with Reduce Motion enabled.

## Correctness Invariants

- The photo row changes synchronously when picker selection is returned.
- Every uploadable image is persisted locally before the service attempts network work.
- Queue publication and queue persistence happen before background drain starts.
- A drain may never overwrite photos queued while it is awaiting network work.
- Batch order remains deterministic.
- Remote reconciliation removes only the matching staged item.
- Leaving and reopening the lead cannot erase staged photos.

