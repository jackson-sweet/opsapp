# Site Visit Checklist Settings — Implementation Plan

## 1. Lock behavior with tests

- Prove legacy field JSON defaults to shown.
- Prove answer snapshots include shown fields only.
- Prove built-in reconciliation preserves company visibility/required/order choices and appends new canonical fields.
- Prove the first-open guide suppression policy is user-scoped.
- Prove DTO decoding and company-safe merge behavior.

## 2. Add the shared contract

- Add `site_visit_types` migration with bounded JSON validation, tenant indexes, `settings.company` write policies, realtime publication, and replica identity.
- Mirror the migration byte-for-byte into OPS Web and the Software Bible.
- Add the table to account-purge and schema documentation where required.

## 3. Complete iOS persistence and sync

- Extend field definitions with backward-compatible visibility.
- Add DTO, repository, durable outbound routing, full/delta pull, pending-field merge protection, realtime upsert/delete, and inbound-change signalling.
- Queue built-in seeds and all editor mutations.

## 4. Build the product flow

- Add Settings → Operations → Site Visit Types and settings-search entries.
- Build the type list and focused editor using OPS tokens and native mobile controls.
- Add the first-open guide and `EDIT TYPES` picker action, permission-gated to company-settings operators.
- Refresh untouched active visits after returning from settings while preserving captured evidence.

## 5. Verify and document

- Run focused behavior and sync tests, then the wider site-visit test set.
- Run a generic iOS device build with isolated package and DerivedData paths.
- Audit new UI for OPS design tokens, accessibility labels, touch targets, and reduced-motion compliance.
- Verify migration parity and update the Software Bible.
- Commit atomically without pushing or applying the production migration.
