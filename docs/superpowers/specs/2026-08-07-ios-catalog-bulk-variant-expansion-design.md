# iOS Catalog Bulk Variant Expansion — Product Design

## Outcome

An operator can add one meaningful variant dimension across many existing stock families without editing every SKU by hand. The flow preserves every existing variant, quantity, stock unit, SKU, price/cost override, threshold, product link, and family image. It adds only the requested option/value relationships and new zero-stock variants.

The motivating Canpro operation is:

- selected families: every rail and accessory family affected by top-rail profile;
- option: `Top profile`;
- existing value: `Round top`;
- new value: `Flat top`.

Existing variants become explicitly `Round top`. For every existing combination, OPS creates the matching `Flat top` variant with quantity `0` and no SKU.

## Product boundary

This is a dimensional expansion tool, not a generic spreadsheet editor. The operator chooses families, defines one option axis, identifies the value represented by the existing variants, and adds one or more new values. OPS calculates the exact resulting combinations.

Unrelated one-off variants still use `Add Variant`. Existing quantity or SKU changes still use the stock list and variant detail. CSV remains the right path for creating a new catalog from an external file; it is not used to mutate existing families.

## Entry and permission

The STOCK kebab menu gains `Bulk Add Variants`, adjacent to `Add Variant`. It is visible only when the user can manage inventory. Opening it presents a full-screen flow so the operator has stable navigation, enough room for family selection and review, and a bottom action that is not obscured by the app's custom tab bar.

Read-only users never see the entry point. The server independently verifies the active company and `catalog.manage` permission before apply; hiding the menu is not the security boundary.

## Flow

The flow has three stages: `FAMILIES`, `CHANGE`, and `REVIEW`.

### Families

The first screen lists active stock families, not individual variants. Search matches family names, categories, and current option/value labels. Each row shows the family name, number of active variants, and its current option axes. A 60-point selection row and clear selected state support gloves and outdoor use.

Selection is always explicit. The operator can select all currently filtered families, clear the selection, and see a persistent selected count. Inactive or deleted families are excluded.

OPS analyzes the selected structures continuously. Families do not need identical option names, but each must be safely expandable: every active source variant must have at most one value for each existing option and no duplicate option-value signature. Any unsafe family is identified by name with an actionable reason and cannot proceed until deselected or repaired.

### Change

The second screen asks only for the product decision:

1. `OPTION` — choose an option name shared by the selected families or enter a new one, such as `Top profile`.
2. `EXISTING VALUE` — the value that describes the variants already in the catalog, such as `Round top`.
3. `NEW VALUES` — one or more values to add, such as `Flat top`.

Names are trimmed and compared case-insensitively. The preview preserves the operator's capitalization while reusing an existing same-name option or value. Blank values, repeated values, or a new value matching the existing value are blocked inline.

If the option already exists on a selected family, the operator chooses which existing value is the source. Only source variants carrying that value are cloned. Variants already carrying another value remain untouched. If the option is new to a family, every active variant is assigned the existing value and becomes a source.

### Review

The review starts with a compact impact summary:

- families affected;
- existing variants labeled;
- new variants added;
- conflicts or skipped combinations.

Families are grouped in a scannable list. Each family row shows `before → after` variant counts and can expand to show source and resulting option labels. The review states the data rules once: existing stock stays unchanged; new variants start at zero; new SKUs remain blank.

The primary action says `ADD VARIANTS` and includes the new-variant count. Apply is enabled only when the preview is current, has at least one real addition, has no blocker, and the device is online.

## Variant creation rules

For each selected family:

1. Resolve or create the requested option using a trimmed, case-insensitive name.
2. Resolve or create the existing and new option values under that family-specific option.
3. When the option is new, attach the existing value to every active source variant without changing the variant row.
4. For each source variant and each new value, create one variant that copies the source's unit, price override, unit-cost override, warning threshold, critical threshold, and active state.
5. Set every new variant's quantity to `0` and SKU to null. Do not copy physical stock units or inventory history.
6. Copy every non-target option-value relationship from the source and replace the target-axis relationship with the new value.
7. Never create a combination whose normalized option-value signature already exists in the family.

Existing variant IDs never change. Existing quantities and SKUs never change. Family defaults, tags, images, product recipes, option mappings, orders, snapshots, and physical stock-unit rows are not rewritten.

## Preview and concurrency contract

Preview is deterministic and runs locally from the synced catalog so feedback is immediate. Its request includes the selected family IDs and the source variant fingerprints used to build the review.

Apply runs as one database transaction across all selected families. The server locks and re-reads the requested families, verifies company ownership and permission, and recalculates the relevant signatures. If a teammate changed any source family after preview, apply returns a stale-preview blocker and writes nothing. The app refreshes the catalog and returns the operator to review with a clear instruction to check the updated result.

The request carries a client-generated lowercase UUID idempotency key. Retrying the same request returns the original success result. Reusing that key with different content is rejected. The operation cannot partially save one family while failing another.

## Local reconciliation and sync

The successful response returns server IDs and complete rows for created options, values, variants, and joins, plus the existing joins it added. iOS reconciles them into SwiftData in one local save. If that local reconciliation fails after the server transaction committed, OPS reports success, requests a catalog resync, and never invites the operator to apply the operation again.

The flow may be prepared offline, and its input persists if the sheet is dismissed or the app backgrounds. Preview remains available from local data, but apply is disabled with `Connect to add these variants.` Once connectivity returns, the operator reviews again before applying. This protects a structural catalog change from ambiguous offline conflict handling.

## Error recovery

- Empty selection: continue is disabled and the selected-count support text explains what is needed.
- Invalid option/value: the exact field owns the correction message.
- Unsupported family structure: the family row names the conflict; no data is written.
- Existing combination: it is shown as already present and omitted from the addition count; an operation with no additions cannot apply.
- Stale preview: no data is written; catalog sync runs and the refreshed review is shown.
- Permission loss: no data is written; the flow explains that catalog-management access is required.
- Network interruption before commit: the operation remains retryable with the same idempotency key.
- Network interruption after commit: retry returns the original response and local reconciliation completes safely.
- App background or dismissal: the draft and stage persist locally until success or explicit discard.

## Completion

Success replaces the bottom action with a concise result: `VARIANTS ADDED`, followed by the family and variant counts. A success haptic fires once. Closing returns to STOCK, requests an immediate catalog sync, and keeps the operator's prior catalog presentation mode.

No notification-rail entry is created. The operation is foreground, synchronous, and complete before the success screen; a second durable notification would duplicate feedback rather than help the user.

## Copy

- Menu: `Bulk Add Variants`
- Title: `ADD VARIANTS`
- Family support: `Choose every stock family that gets the same new option.`
- Existing value support: `This labels what is already in stock. Existing quantities and SKUs stay unchanged.`
- New value support: `OPS creates matching variants with zero stock and blank SKUs.`
- Offline: `Connect to add these variants.`
- Stale preview: `Catalog changed since this review. Check the refreshed variants before adding them.`
- Apply: `ADD VARIANTS · {count}`
- Success: `VARIANTS ADDED`

## Acceptance criteria

The feature is complete when automated tests and a generic-device build prove:

- a new option expands every existing combination exactly once;
- an existing option expands only the selected source value;
- existing variant IDs, quantities, SKUs, overrides, and joins are preserved;
- new variants start at zero, have no SKU, copy safe variant settings, and do not copy stock units;
- normalized duplicate axes, values, and variant signatures are rejected or reused correctly;
- mixed selected families produce one deterministic review;
- stale data, wrong-company IDs, lost permission, and a repeated request cannot cause partial or duplicate writes;
- successful local reconciliation makes the new variants immediately visible, while reconciliation failure requests resync without misreporting the server result;
- draft, offline, error, and success states remain actionable at Dynamic Type sizes and with minimum 44-point targets;
- all interface values use `OPSStyle` tokens and iOS 17.6-compatible APIs.
