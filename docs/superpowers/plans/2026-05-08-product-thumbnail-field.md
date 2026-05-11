# Product Thumbnail Field — 2026-05-08

Branch: `catalog-variant-model`
Working dir: `/Users/jacksonsweet/Projects/OPS/ops-ios`
Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (device-only, never simulator)
Lineage prefix: **PRODUCT THUMBNAIL - P1-<n>**

## Why this exists

Products on estimates are sent to clients. Right now they have no visual — just text. A thumbnail field on Product lets the user attach a photo (real product shot, sample install, swatch) so estimates and the products list look like a real catalog. CatalogItem already has `image_url`; Products don't yet.

## Hard constraints (apply to every phase)

- **NEVER** `git add .` / `-A`. Stage by explicit path.
- **NEVER** include `Co-Authored-By: Claude` or AI attribution.
- **Atomic commits per logical change.**
- **Build between commits.** Must end with `** BUILD SUCCEEDED **`. SourceKit "Cannot find type" diagnostics are false positives.
- **All styling traces to OPSStyle tokens.** Voice: `// SECTION HEADERS`, military-tactical.
- **Schema changes need explicit user approval.** Phase 1 below writes the migration to a file — do not call `apply_migration` or `execute_sql`. The user will run it.
- **Permission gating** via `permissionStore.can("catalog.products.manage")` for edits.

## Phase 1 — Migration SQL (DO NOT APPLY — write only)

**Goal:** Additive nullable column on products + Storage bucket policy for product thumbnails.

**Tasks:**

1. Write SQL to `OPS/Migrations/2026-05-08-add-product-thumbnail-url.sql`:

   ```sql
   ALTER TABLE products
     ADD COLUMN IF NOT EXISTS thumbnail_url text;

   COMMENT ON COLUMN products.thumbnail_url IS
     'Optional product thumbnail. Stored as a Supabase Storage public URL pointing into the product-thumbnails bucket. NULL = no image.';
   ```

2. Write a separate file `OPS/Migrations/2026-05-08-product-thumbnails-storage-policy.sql` for the Storage bucket + policies:
   - Create bucket `product-thumbnails` (public read, authenticated write).
   - INSERT/UPDATE/DELETE policies: only the row's product company members can write; SELECT is public.
   - Object naming convention: `{company_id}/{product_id}/{uuid}.jpg`. Document inline.
   - **Verify policy syntax against an existing bucket policy in this Supabase project** — check `storage.objects` policies for hints. Mirror the pattern from `project-images` or `client-photos` if those exist.

3. Companion `.md` doc explaining how to apply (Supabase SQL editor or `apply_migration`) and the bucket / object-naming conventions.

**Acceptance:**
- Three files (`.sql` x2, `.md` x1) in `OPS/Migrations/`.
- Committed: `docs(catalog): migration + Storage policy for product thumbnails (NOT applied)`.
- The agent does NOT apply; user must run.

## Phase 2 — Model + DTOs

**Tasks:**

1. Add `var thumbnailUrl: String?` to [`Product.swift`](OPS/DataModels/Supabase/Product.swift) (place near `imageUrl` — wait, Product doesn't have one; put it after `sku`).
2. Update `ProductDTO` (read), `CreateProductDTO` (write), `UpdateProductDTO` (write) in [`ProductDTOs.swift`](OPS/Network/Supabase/DTOs/ProductDTOs.swift):
   - Add `let thumbnailUrl: String?` (or `var` for Update) with coding key `thumbnail_url`.
   - Wire through `toModel()`.
3. Update `InboundProcessor`'s and `DataActor`'s product merge paths if they write Product fields field-by-field — search for `acceptableFields(...entityType: .product...)` and add `"thumbnailUrl"`.

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): thumbnailUrl on Product model + DTOs`.

## Phase 3 — Storage upload helper

**Goal:** Reusable helper that takes a UIImage + product id, uploads to the bucket, returns the public URL.

**Tasks:**

1. Look for existing image-upload code first:
   - `grep -rn "uploadImage\|StorageReference\|.storage.from" OPS/`.
   - Existing patterns to mirror: there's likely something for `project_images`, `photo_annotations`, or user profile images.
2. Add `OPS/Services/ProductThumbnailUploader.swift`:
   - `func upload(_ image: UIImage, productId: String, companyId: String) async throws -> URL`
   - JPEG-encode at 0.85 compression, max 1024×1024 (resize if larger to keep object size reasonable for sync to slow networks).
   - Path: `{companyId}/{productId}/{UUID().uuidString}.jpg` (matches the migration's object-naming convention).
   - Returns the public URL (`SupabaseService.shared.client.storage.from("product-thumbnails").getPublicURL(path:)`).

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): ProductThumbnailUploader service`.

## Phase 4 — Add Product sheet integration

**Tasks:**

1. In [`QuickAddProductSheet.swift`](OPS/Views/Catalog/Products/QuickAddProductSheet.swift), add a "// THUMBNAIL" section above the "// CATEGORY" section:
   - When no thumbnail picked: show a tap target ("// + ADD THUMBNAIL") that opens the photos picker.
   - When picked: show the chosen image as a preview thumbnail with an "X" to remove + "REPLACE" affordance.
   - Use `PhotosPicker` (SwiftUI) to pick from library. Single image only.
2. On save, if a thumbnail is selected:
   - Save the Product first (existing logic).
   - Then upload the image via `ProductThumbnailUploader`, capture the URL.
   - Then call `repo.update(productId, fields: UpdateProductDTO(thumbnailUrl: url))` to attach.
   - If upload fails, the product is still created — surface a "// THUMBNAIL UPLOAD FAILED — TAP TO RETRY" inline error in the success haptic state, but don't roll back the product. Better degrade-gracefully than block the create.
3. Permission: only show the thumbnail UI when `permissionStore.can("catalog.products.manage")`.

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): thumbnail picker on Add Product sheet`.

## Phase 5 — Edit on ProductDetailView

**Tasks:**

1. In [`ProductDetailView.swift`](OPS/Views/Catalog/Products/ProductDetailView.swift), add a thumbnail section near the top of the detail (above name) — large preview when set, "// + ADD THUMBNAIL" tap-to-add when nil.
2. Edit mode: same picker pattern as Add Product. Replace updates the URL in place via `UpdateProductDTO`.
3. Display fallback: when no thumbnail, render a placeholder rectangle (border + tertiary text "// NO IMAGE") with the same aspect ratio as a thumbnail would have so the layout doesn't jump.

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): thumbnail edit + display on ProductDetailView`.

## Phase 6 — List + estimate display (small)

**Tasks:**

1. [`CatalogProductsListView.swift`](OPS/Views/Catalog/Products/CatalogProductsListView.swift) `ProductRow`: when `product.thumbnailUrl` is non-nil, render a small thumbnail (e.g. 40x40) leading the row. AsyncImage with placeholder + cache.
2. **Skip estimate / invoice display for v1** — that's a separate scope (line item rendering touches estimate sheet, invoice render, customer-facing PDF). Surface as out-of-scope in the report.

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): thumbnail in product row`.

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** PRODUCT THUMBNAIL - P1-1
- **Phases:** completed/partial/skipped with reason
- **Commits:** SHA + subject for each
- **Files changed by commit**
- **Build verification:** last 3 lines of device build output
- **`git status --short`**
- **Migration SQL file paths** + the explicit "USER MUST APPROVE AND RUN" callout for both the products column and the Storage bucket policies
- **Existing Storage pattern referenced** (so the user can verify the policy is consistent with what's already deployed)
- **Concerns / judgment calls**
- **What's deferred:** estimate / invoice / PDF thumbnail display
