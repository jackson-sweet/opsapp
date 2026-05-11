-- Adds an optional thumbnail URL to products so estimates and the
-- catalog list can carry a real visual instead of text-only rows.
--
-- Additive + nullable to keep the iOS sync constraint intact: prior
-- App Store builds keep working because they ignore unknown columns,
-- and any row without a thumbnail just renders the placeholder.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS thumbnail_url text;

COMMENT ON COLUMN products.thumbnail_url IS
  'Optional product thumbnail. Stored as a Supabase Storage public URL pointing into the product-thumbnails bucket. NULL = no image.';
