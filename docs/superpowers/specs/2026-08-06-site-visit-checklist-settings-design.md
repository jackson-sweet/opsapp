# Site Visit Checklist Settings — Product Design

## Outcome

Company operators with `settings.company` access can manage reusable site-visit types at **Settings → Operations → Site Visit Types**. A type defines the checklist shown when a future site visit selects it. Existing visit answers remain an immutable visit-time snapshot.

## Entry points

1. Settings contains a `Site Visit Types` row under Operations.
2. The site-visit type picker ends with an `EDIT TYPES` action that opens the same settings screen without discarding the active visit.
3. The first eligible time an operator opens Site Visit, a quiet guide explains where checklists live. Actions are `OPEN SETTINGS`, `NOT NOW`, and `NEVER SHOW AGAIN`. Opening Settings or choosing never-show-again suppresses future guides for that user; not-now allows a future reminder.

Crew members without company-settings permission can use the shared types but do not see edit entry points or the guide.

## Information architecture

The list shows active types in visit-picker order. Each row shows the name, visible-field count, and whether it is the default. Selecting a row opens one focused editor. `NEW VISIT TYPE` opens the same editor with a blank custom type.

The editor owns:

- name and short description;
- default-type selection;
- ordered checklist fields;
- field label, response type, required state, and shown/hidden state;
- add, reorder, and remove for custom fields;
- soft-delete for custom visit types.

Built-in types remain recognizable and cannot be deleted. Their fields can be shown, hidden, made required/optional, and reordered. Canonical built-in labels and response kinds remain product-owned so future app updates can safely add new starter fields without undoing company visibility choices.

At least one field must remain shown. A hidden required field is normalized to optional. At least one active type must remain, and exactly one active type is the default.

## Data contract

`public.site_visit_types` is the company-wide source of truth. The iPhone keeps its existing SwiftData `SiteVisitType` projection for offline use and syncs it through the durable operation queue. Built-ins are seeded locally with deterministic IDs, then uploaded like any other type. Realtime and delta pull keep teammates current.

Checklist fields are stored as a bounded JSON array. `is_visible` is optional in the iOS Codable definition so pre-feature local rows decode as visible. Completed and in-progress visit answers continue to store their own label, kind, required flag, and answer value; template edits never rewrite evidence already captured.

## Active-visit return behavior

Opening settings from an untouched visit can refresh that blank visit from the edited template. Once any checklist response contains evidence, returning from settings preserves the active answer snapshot. This prevents an administrative edit from deleting field work in progress.

## Security and offline behavior

All company members can read active templates. Only users with `settings.company` can create, update, or delete them. RLS also enforces exact company identity. Local edits are saved first and queued for retry, so checklist administration remains safe through temporary signal loss.

## Copy

Guide title: `CHECKLISTS`

Guide body: `Site visit checklists are company-wide. Edit fields or build a new visit type in Settings.`

Settings support line: `Changes apply to future visits. Existing visit records stay unchanged.`
