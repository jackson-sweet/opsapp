# Vinyl order → inventory → offcut tracking — investigation + spec (item 4bde9847)

**Status:** Investigation complete + adversarially verified (2026-06-19). Buildable iOS-only, NO schema change. Ready for a focused build session.

## What exists today

- **Vinyl order = two decoupled things**, both from `OPS/DeckBuilder/Views/VinylOrderSheet.swift`:
  - (A) A project **status marker** — `projects.vinyl_order_status|vinyl_ordered_at|vinyl_ordered_by` (`Project.swift:538-607`, `ProjectVinylOrderMarker`). `vinyl_ordered_by` FKs `auth.users` → must be NULL for Firebase operators.
  - (B) A **draft purchase order** — `createOrderAndNote()` (`VinylOrderSheet.swift:930-1054`) creates a `catalog_orders` (draft) + one `catalog_order_items` line (`quantityRequested = totalOrderedSqFt`) + a `project_notes` row + a `catalog_order_drafted` notification.
- **Modern catalog inventory** (where offcuts belong): `catalog_variants.quantity` (mirrored aggregate); `catalog_stock_units` (one physical row per roll/offcut, `unit_kind`/`status`/`width_value`/`original_length_value`/`remaining_length_value`, `source_order_item_id` FK→catalog_order_items); `catalog_stock_unit_events` (parentage ledger, `related_catalog_stock_unit_id`, anon "firebase bridge" RLS). iOS has `CatalogStockUnitRepository` (full CRUD, gated on `CatalogSchemaCapabilityGate.current.catalogStockUnits`) + `CatalogStockUnitAggregator`. iOS has **no** DTO/repo for `catalog_stock_unit_events` yet.
- **Gap:** the vinyl draft stops at `catalog_order_items` — it never creates `catalog_stock_units` and never sets `source_order_item_id`. `VinylCutListEngine.assignOffcuts()` (`VinylCutListEngine.swift:720-759`) *computes* offcut lanes but discards them (in-memory only; `VinylCutPlan` has no remnant field). Offcut detail survives only as free text in the order notes.

## Verified preconditions (no work)

`catalog_stock_units`, `catalog_stock_unit_events` (anon RLS + `related_catalog_stock_unit_id`), `source_order_item_id`, `set_company_inventory_mode`, `complete_project_task` all exist on prod. **No schema change needed.** `catalog_stock_units` and `catalog_stock_unit_events` both have anon (firebase-bridge) insert/select RLS. Prior art to reuse: `CatalogSetupFlowSheet.createOffcut(from:variantId:)` (`OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift:2005`) already implements the debit-source + create-offcut + emit-events split (draft form) — lift it into the runtime path.

## Build plan (focused session)

**Phase 1 — order → stock receipt (no schema change).** After `createOrderAndNote()` succeeds with a resolved variant + created `catalog_order_items.id`, add a roll-receipt step (operator confirms roll count/length/width). For each roll, `CatalogStockUnitRepository.create(CreateCatalogStockUnitDTO(company_id: …, unit_kind: roll, quantity_value: 1, original_length_value = remaining_length_value = length, width_value, status: full, source_order_item_id: createdItem.id))`. Re-mirror `catalog_variants.quantity` via `CatalogStockUnitAggregator` + `CatalogStockQuantityPolicy`.

**Phase 2 — persist offcuts (additive only).** Surface the surviving `OffcutLane`s from `assignOffcuts()` (add `producedOffcuts` to `VinylCutPlan`; promote the hardcoded 6" threshold at lines 741/747 to `VinylOrderSettings`; seed `assignOffcuts` from on-hand offcut stock units so reuse spans jobs). New `OPS/Network/Supabase/DTOs/CatalogStockUnitEventDTOs.swift` + `Repositories/CatalogStockUnitEventRepository.swift`. On "cut from this roll": update parent roll (`remaining_length_value -=`, status full→partial), create an `offcut` stock unit (qty 1, status partial), and insert events.

### CRITICAL corrections from adversarial verify (must apply)

1. **`event_type` values** — the live CHECK allows only: `receive, consume, scrap, offcut_create, adjust, reserve, release, restore, delete`. Use **`consume`** (or `adjust`) for the parent-roll debit and **`offcut_create`** for the new offcut. NOT `cut`/`offcut_created` (those fail the CHECK). `CatalogSetupFlowSheet` already uses the correct `.offcutCreate/.adjust/.consume/.scrap`.
2. **`company_id` is NOT NULL** on both `catalog_stock_units` and `catalog_stock_unit_events`, and the anon RLS requires `company_id = private.get_user_company_id()`. Include it on every insert (the repos already carry `companyId`). Let `catalog_stock_unit_events.created_by` default server-side (`private.get_current_user_id()`); `catalog_stock_units` has **no** actor column (no auth.users FK hazard there).
3. **Reuse, don't reinvent** — adapt `CatalogSetupFlowSheet.createOffcut` + its event-draft shape (`relatedStockUnitClientId/ServerId → related_catalog_stock_unit_id`, the `offcut_create` + source-adjust pair) so the deck-builder consume path and the setup wizard stay consistent.

### Gating + sync (mandatory)

- All stock writes no-op unless `company_inventory_settings.inventory_mode == .tracked` (`CompanyInventoryModeRepository`) **AND** `CatalogSchemaCapabilityGate.current.catalogStockUnits`. Otherwise order/marker behavior is unchanged.
- Register the new events entity in `SyncTypes.swift` at **priority 13** (after stock_units=12, variants=11; before catalog_orders=14) so inbound FK resolves; wire fetch in InboundProcessor/DataActor mirroring `catalogStockUnit`.
- Re-mirror `catalog_variants.quantity` after every stock mutation (web `/catalog` STOCK reads variants directly).
- Post an "OFFCUT BANKED" rail notification on offcut creation (deep link `ops://catalog?segment=stock`).
- Do NOT duplicate the server consumption pipeline (`complete_project_task` is authoritative); the manual deck-builder cut is a distinct surface. Guard against double-deduct if vinyl install later also flows through task completion (idempotency marker on events).
- Update `ops-software-bible/07_SPECIALIZED_FEATURES.md` (the 2026-05-21 "marker-only v1" boundary is superseded) + document `catalog_stock_unit_events`.

**Verify:** device-target `xcodebuild`; test against Canpro/Maverick with `inventory_mode` flipped both ways (confirm no-op when off); confirm anon-role writes succeed.

Full verified investigation: workflow `wf_eef71279-566` (vinyl-inventory-investigation).
