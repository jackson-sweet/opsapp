-- =============================================================================
-- Products CSV Import — atomic apply + dry-run RPCs
--
-- USER MUST APPROVE AND RUN. This file is **NOT** auto-applied. Open it in the
-- Supabase SQL editor (or run via `apply_migration` after review) only after
-- you have read it end-to-end. The iOS client calls these by name —
-- `products_import_validate` and `products_import_apply` — so the names are
-- load-bearing. Re-naming requires a coordinated client + server change.
--
-- Companion doc: 2026-05-08-products-import-rpc.md
-- Sibling RPC:   2026-05-08-catalog-import-rpc.sql (catalog families+variants)
--
-- WHAT THIS FILE DOES
--
-- Defines two SECURITY DEFINER plpgsql functions on the `public` schema:
--
--   1. products_import_validate(p_company_id uuid, p_payload jsonb) -> jsonb
--      Pure validator. Walks the payload, runs every per-row check, returns
--      either {success: true, totals: {...}} or {success: false, errors: [...]}.
--      Never INSERTs. Never mutates anything. Used by the iOS preview screen.
--
--   2. products_import_apply(p_company_id uuid, p_payload jsonb) -> jsonb
--      Atomic apply. Runs the same validation; if it passes, INSERTs every
--      product row inside a single transaction. On any validation failure:
--      ROLLBACK and return {success: false, errors: [...]}.
--      On success: returns {success: true, created_product_ids: {...},
--      totals: {products: N}}.
--
-- PAYLOAD JSON SCHEMA
--
--   {
--     "products": [
--       {
--         "row_index": 0,                       -- int, 0-based, references
--                                                 -- the row inside this array
--         "name": "Composite deck install",     -- required, non-empty
--         "description": "...",                 -- optional, may be null
--         "base_price": 25.00,                  -- required, numeric, >= 0
--         "unit_cost": 12.00,                   -- optional, numeric, >= 0
--         "category_id": "uuid-or-null",        -- optional; if set must
--                                                 -- belong to p_company_id
--         "unit_id": "uuid-or-null",            -- optional; if set must
--                                                 -- belong to p_company_id
--         "category": "Hardware",               -- optional legacy free text;
--                                                 -- written alongside FK
--         "unit": "sqft",                       -- optional legacy free text;
--                                                 -- written alongside FK
--         "pricing_unit": "sqft",               -- optional, free text (legacy
--                                                 -- enum). NOT NULL on the
--                                                 -- table; defaults to 'each'
--                                                 -- server-side if absent.
--         "sku": "DECK-INST",                   -- optional, no uniqueness
--                                                 -- check (table has no unique
--                                                 -- constraint on SKU)
--         "kind": "service",                    -- optional, 'service' | 'good'.
--                                                 -- NOT NULL on the table;
--                                                 -- defaults to 'service'
--                                                 -- server-side if absent.
--         "type": "LABOR",                      -- optional, LineItemType raw
--                                                 -- ('LABOR' | 'MATERIAL' |
--                                                 -- 'OTHER'). NOT NULL on the
--                                                 -- table; defaults to 'LABOR'
--                                                 -- server-side if absent.
--         "is_taxable": true                    -- optional, default true
--       }
--     ]
--   }
--
-- RESULT JSON SCHEMA
--
--   Success:
--     {
--       "success": true,
--       "created_product_ids": {"0": "uuid", "1": "uuid", ...},
--       "totals": {"products": N}
--     }
--
--   Failure:
--     {
--       "success": false,
--       "errors": [
--         {
--           "scope": "product" | "payload",
--           "row_index": 0,
--           "field": "name" | "category_id" | "...",
--           "reason": "human-readable single sentence"
--         }
--       ]
--     }
--
-- VALIDATION RULES
--
--   Payload-level
--   -------------
--   * `products` must be a JSON array, non-empty.
--   * `p_company_id` must equal `private.get_user_company_id()` for the
--     calling auth.uid(). Mismatch -> fatal payload-scope error.
--
--   Product rows
--   ------------
--   * `row_index` integer, present, unique within the products array.
--   * `name` text, required, non-empty after trim.
--   * `base_price` numeric, required, >= 0.
--   * `unit_cost` numeric, optional, >= 0.
--   * `category_id` if present + non-null must resolve to a row in
--     `catalog_categories` with the same company_id and `deleted_at IS NULL`.
--   * `unit_id` if present + non-null must resolve to a row in
--     `catalog_units` with the same company_id and `deleted_at IS NULL`.
--   * `kind` if present must be 'service' or 'good'.
--   * `type` if present must be 'LABOR', 'MATERIAL', or 'OTHER'.
--   * `pricing_unit` if present is accepted as free text (legacy enum value).
--   * `sku` if present is accepted as-is. The Products table has no unique
--     SKU constraint (per audit), so we do not soft-fail on duplicates the
--     way the catalog import does for variants. Pass through verbatim.
--
-- TRANSACTIONALITY
--
--   `products_import_apply` runs in a single implicit transaction (every
--   plpgsql function call is one). On any RAISE or returned error path we
--   bail out without committing. Postgres rolls back automatically when
--   the function exits abnormally. Returning the failure object means the
--   function exited normally — so we explicitly do NOT INSERT before the
--   final validation pass.
--
-- =============================================================================

-- ----------------------------------------------------------------------------
-- products_import_validate
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.products_import_validate(
  p_company_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_caller_company_id uuid;
  v_errors jsonb := '[]'::jsonb;
  v_products jsonb;
  v_product jsonb;
  v_seen_indexes jsonb := '{}'::jsonb;
  v_row_index int;
  v_name text;
  v_kind text;
  v_type text;
  v_category_id uuid;
  v_unit_id uuid;
  v_base_price numeric;
  v_unit_cost numeric;
BEGIN
  -- Caller / company guard
  v_caller_company_id := private.get_user_company_id();
  IF v_caller_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'errors', jsonb_build_array(jsonb_build_object(
        'scope', 'payload',
        'row_index', -1,
        'field', 'auth',
        'reason', 'No authenticated company context.'
      ))
    );
  END IF;
  IF v_caller_company_id <> p_company_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'errors', jsonb_build_array(jsonb_build_object(
        'scope', 'payload',
        'row_index', -1,
        'field', 'company_id',
        'reason', 'p_company_id does not match the caller''s company.'
      ))
    );
  END IF;

  -- Shape guard
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object(
      'success', false,
      'errors', jsonb_build_array(jsonb_build_object(
        'scope', 'payload',
        'row_index', -1,
        'field', 'root',
        'reason', 'Payload must be a JSON object.'
      ))
    );
  END IF;

  v_products := COALESCE(p_payload->'products', '[]'::jsonb);

  IF jsonb_typeof(v_products) <> 'array' THEN
    v_errors := v_errors || jsonb_build_object(
      'scope', 'payload', 'row_index', -1,
      'field', 'products', 'reason', 'products must be a JSON array.');
  END IF;
  IF jsonb_typeof(v_products) = 'array' AND jsonb_array_length(v_products) = 0 THEN
    v_errors := v_errors || jsonb_build_object(
      'scope', 'payload', 'row_index', -1,
      'field', 'products', 'reason', 'At least one product row is required.');
  END IF;

  -- Bail early if shape failures already accumulated
  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  -- Per-product validation
  FOR v_product IN SELECT * FROM jsonb_array_elements(v_products) LOOP
    -- row_index
    IF jsonb_typeof(v_product->'row_index') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object(
        'scope','product','row_index',-1,'field','row_index',
        'reason','row_index must be present and numeric.');
      CONTINUE;
    END IF;
    v_row_index := (v_product->>'row_index')::int;
    IF v_seen_indexes ? v_row_index::text THEN
      v_errors := v_errors || jsonb_build_object(
        'scope','product','row_index',v_row_index,'field','row_index',
        'reason','Duplicate row_index in products.');
    ELSE
      v_seen_indexes := v_seen_indexes || jsonb_build_object(v_row_index::text, true);
    END IF;

    -- name
    v_name := NULLIF(TRIM(COALESCE(v_product->>'name','')),'');
    IF v_name IS NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'scope','product','row_index',v_row_index,'field','name',
        'reason','name is required and cannot be blank.');
    END IF;

    -- base_price required + numeric + >= 0
    IF jsonb_typeof(v_product->'base_price') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object(
        'scope','product','row_index',v_row_index,'field','base_price',
        'reason','base_price is required and must be numeric.');
    ELSE
      v_base_price := (v_product->>'base_price')::numeric;
      IF v_base_price < 0 THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','base_price',
          'reason','base_price must be >= 0.');
      END IF;
    END IF;

    -- unit_cost optional + >= 0
    IF v_product ? 'unit_cost' AND jsonb_typeof(v_product->'unit_cost') = 'number' THEN
      v_unit_cost := (v_product->>'unit_cost')::numeric;
      IF v_unit_cost < 0 THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','unit_cost',
          'reason','unit_cost must be >= 0.');
      END IF;
    ELSIF v_product ? 'unit_cost'
          AND jsonb_typeof(v_product->'unit_cost') NOT IN ('null','number') THEN
      v_errors := v_errors || jsonb_build_object(
        'scope','product','row_index',v_row_index,'field','unit_cost',
        'reason','unit_cost must be numeric or null.');
    END IF;

    -- category_id
    IF v_product ? 'category_id' AND jsonb_typeof(v_product->'category_id') <> 'null' THEN
      BEGIN
        v_category_id := (v_product->>'category_id')::uuid;
        IF NOT EXISTS (
          SELECT 1 FROM catalog_categories
          WHERE id = v_category_id
            AND company_id = p_company_id
            AND deleted_at IS NULL
        ) THEN
          v_errors := v_errors || jsonb_build_object(
            'scope','product','row_index',v_row_index,'field','category_id',
            'reason','category_id does not match an active category for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','category_id',
          'reason','category_id is not a valid uuid.');
      END;
    END IF;

    -- unit_id
    IF v_product ? 'unit_id' AND jsonb_typeof(v_product->'unit_id') <> 'null' THEN
      BEGIN
        v_unit_id := (v_product->>'unit_id')::uuid;
        IF NOT EXISTS (
          SELECT 1 FROM catalog_units
          WHERE id = v_unit_id
            AND company_id = p_company_id
            AND deleted_at IS NULL
        ) THEN
          v_errors := v_errors || jsonb_build_object(
            'scope','product','row_index',v_row_index,'field','unit_id',
            'reason','unit_id does not match an active unit for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','unit_id',
          'reason','unit_id is not a valid uuid.');
      END;
    END IF;

    -- kind enum
    IF v_product ? 'kind' AND jsonb_typeof(v_product->'kind') <> 'null' THEN
      v_kind := v_product->>'kind';
      IF v_kind NOT IN ('service','good') THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','kind',
          'reason','kind must be ''service'' or ''good''.');
      END IF;
    END IF;

    -- type enum (LineItemType)
    IF v_product ? 'type' AND jsonb_typeof(v_product->'type') <> 'null' THEN
      v_type := v_product->>'type';
      IF v_type NOT IN ('LABOR','MATERIAL','OTHER') THEN
        v_errors := v_errors || jsonb_build_object(
          'scope','product','row_index',v_row_index,'field','type',
          'reason','type must be ''LABOR'', ''MATERIAL'', or ''OTHER''.');
      END IF;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'totals', jsonb_build_object(
      'products', jsonb_array_length(v_products)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.products_import_validate(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.products_import_validate(uuid, jsonb) TO authenticated;


-- ----------------------------------------------------------------------------
-- products_import_apply
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.products_import_apply(
  p_company_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_validation jsonb;
  v_product jsonb;
  v_product_id_map jsonb := '{}'::jsonb;     -- {row_index_text: uuid}
  v_row_index int;
  v_new_product_id uuid;
  v_products jsonb;
BEGIN
  -- Re-run the validator. Single source of truth — no drift between
  -- preview and apply.
  v_validation := public.products_import_validate(p_company_id, p_payload);
  IF NOT (v_validation->>'success')::boolean THEN
    RETURN v_validation;
  END IF;

  v_products := COALESCE(p_payload->'products', '[]'::jsonb);

  -- Insert products, capture id mapping keyed by row_index.
  FOR v_product IN SELECT * FROM jsonb_array_elements(v_products) LOOP
    v_row_index := (v_product->>'row_index')::int;

    INSERT INTO products (
      company_id,
      name,
      description,
      base_price,
      unit_cost,
      unit,
      category,
      category_id,
      unit_id,
      pricing_unit,
      sku,
      kind,
      type,
      is_taxable,
      is_active
    ) VALUES (
      p_company_id,
      TRIM(v_product->>'name'),
      NULLIF(v_product->>'description',''),
      (v_product->>'base_price')::numeric,
      NULLIF(v_product->>'unit_cost','')::numeric,
      NULLIF(v_product->>'unit',''),
      NULLIF(v_product->>'category',''),
      NULLIF(v_product->>'category_id','')::uuid,
      NULLIF(v_product->>'unit_id','')::uuid,
      COALESCE(NULLIF(v_product->>'pricing_unit',''), 'each'),
      NULLIF(v_product->>'sku',''),
      COALESCE(NULLIF(v_product->>'kind',''), 'service'),
      COALESCE(NULLIF(v_product->>'type',''), 'LABOR'),
      COALESCE((v_product->>'is_taxable')::boolean, true),
      true
    ) RETURNING id INTO v_new_product_id;

    v_product_id_map := v_product_id_map || jsonb_build_object(v_row_index::text, v_new_product_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'created_product_ids', v_product_id_map,
    'totals', jsonb_build_object(
      'products', jsonb_array_length(v_products)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.products_import_apply(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.products_import_apply(uuid, jsonb) TO authenticated;
