-- Storage bucket + RLS policies for product thumbnails.
--
-- Mirrors the existing `client-images` bucket pattern in this project:
--   bucket is public-read, authenticated-write, no MIME allowlist, no
--   size cap (we resize/JPEG-compress client side before upload).
--
-- Object naming convention (enforced by the iOS uploader):
--   product-thumbnails/{company_id}/{product_id}/{uuid}.jpg
--
-- The first path segment is the company_id so future tightening (per-
-- company write check via `(storage.foldername(name))[1] = ...::text`)
-- can land without renaming objects.

-- 1. Create the bucket if it doesn't already exist. Public read so the
--    URLs returned by `getPublicURL(...)` resolve without a session.
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-thumbnails', 'product-thumbnails', true)
ON CONFLICT (id) DO NOTHING;

-- 2. SELECT — anyone (anon + authenticated) can read. Public bucket
--    + this policy is the same shape used by client-images / profiles
--    / project-photos in this project.
DROP POLICY IF EXISTS "Anyone can view product thumbnails" ON storage.objects;
CREATE POLICY "Anyone can view product thumbnails"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'product-thumbnails');

-- 3. INSERT — authenticated users only. Mirrors
--    "Company members can upload client images".
DROP POLICY IF EXISTS "Company members can upload product thumbnails" ON storage.objects;
CREATE POLICY "Company members can upload product thumbnails"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );

-- 4. UPDATE — authenticated users only. Used when the iOS uploader
--    upserts to overwrite an existing object at the same path (the
--    .upload(... upsert: true) path the client takes for replace).
DROP POLICY IF EXISTS "Company members can update product thumbnails" ON storage.objects;
CREATE POLICY "Company members can update product thumbnails"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  )
  WITH CHECK (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );

-- 5. DELETE — authenticated users only. Matches the equivalent
--    "Company members can delete client images" policy. Tightening
--    to per-company / per-product can come later — for now this
--    matches the shape of every sibling bucket on this project.
DROP POLICY IF EXISTS "Company members can delete product thumbnails" ON storage.objects;
CREATE POLICY "Company members can delete product thumbnails"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );
