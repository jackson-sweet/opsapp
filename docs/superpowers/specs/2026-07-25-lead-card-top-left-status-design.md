# Lead Card Top-Left Status — Design

**Date:** 2026-07-25  
**Bug:** `b4eee308-83c7-434c-9f55-d83c897dd720`  
**Scope:** `LeadTriageCard` on the OPS iOS Leads tab and stage drill.

## Problem

The lead's stage is currently placed in the lower metadata row after the chase strip. That makes a core scan attribute visually subordinate and forces an operator to read deep into each card to understand pipeline position.

## Approved layout

The card begins with a dedicated status/value row:

```text
[QUOTED · 9D ▾]                       $14.2K
Marcus Webb
Roof tear-off — 28 sq
```

- The existing interactive `StageTag` and `LeadStatusMenu` occupy the literal top-left.
- Estimated value remains top-right in its existing mono treatment.
- Contact name moves to a full-width row directly beneath.
- The job line remains beneath the contact name.
- The lower metadata row keeps stage progress and source only; it no longer repeats the stage badge.
- Terminal cards use the same top-left `StageTag` without a menu, preserving their existing read-only behavior.

## Interaction and accessibility

Status-menu permissions, haptics, labels, stage transitions, swipe behavior, card tap behavior, and terminal handling do not change. The badge remains text-labelled so stage is never communicated by color alone.

## Visual-system contract

The correction reuses the existing `StageTag`, `LeadStatusMenu`, typography, spacing, color, and card tokens. It adds no copy, color, motion, radius, or custom measurement. The new top row uses the card's existing spacing tokens and preserves the 44pt effective menu target.

## Verification

- A focused presentation/layout regression proves the top region orders status/value before contact/job and the metadata row excludes status.
- Existing lead-card snapshot coverage is rerun for open and terminal cards.
- The changed app surface compiles.
- The final diff passes the OPS design-system token audit.
