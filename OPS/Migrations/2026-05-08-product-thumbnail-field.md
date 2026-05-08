# Product Thumbnail Field — schema + Storage bucket

**Files:**

- `2026-05-08-add-product-thumbnail-url.sql` — adds `products.thumbnail_url`
- `2026-05-08-product-thumbnails-storage-policy.sql` — creates the
  `product-thumbnails` bucket and the four `storage.objects` policies
  it needs

**Status:** NOT APPLIED. Awaiting user approval before either touches
the database. The iOS app code in this branch will compile and ship
without the column being live (`thumbnail_url` round-trips as `nil` and
the UI gracefully shows the placeholder), but the upload + display
flow doesn't activate until both files are run.

## What the column migration does

Adds a single nullable `text` column on `products` whose value is a
public Supabase Storage URL into the `product-thumbnails` bucket. NULL
means "no thumbnail" and is the default for every existing row.

This is intentionally additive + nullable so the iOS sync constraint
holds — prior App Store builds ignore the unknown column, and the new
build degrades gracefully when the column hasn't been added yet.

## What the Storage migration does

1. Creates the `product-thumbnails` bucket (public read, authenticated
   write).
2. Adds four policies on `storage.objects`:
   - SELECT (`Anyone can view product thumbnails`) — public read.
   - INSERT (`Company members can upload product thumbnails`) — must
     be authenticated.
   - UPDATE (`Company members can update product thumbnails`) — must
     be authenticated. Required because the uploader uses
     `upsert: true` to overwrite the same path on replace.
   - DELETE (`Company members can delete product thumbnails`) — must
     be authenticated.

The shape matches the existing `client-images` bucket on this project
(public read, `auth.role() = 'authenticated'` write/delete, no MIME
allowlist, no size cap — the iOS uploader resizes + JPEG-compresses
before upload).

## Object naming convention

The iOS uploader writes to:

    {company_id}/{product_id}/{UUID().uuidString}.jpg

The first path segment is the `company_id`. We're not enforcing it in
the policy yet (matches every other bucket in this project), but the
layout means a future tightening like

    (storage.foldername(name))[1] = (
      SELECT u.company_id::text FROM users u WHERE u.id = auth.uid()
    )

can be added without re-keying any objects.

## How to apply

Either:

1. **Supabase SQL editor (recommended for one-off runs).** Paste the
   contents of `2026-05-08-add-product-thumbnail-url.sql` into the
   editor and run it. Then paste
   `2026-05-08-product-thumbnails-storage-policy.sql` and run it.

2. **`apply_migration` MCP tool.** Pass each SQL block as the `query`
   argument. Both files are idempotent — safe to re-run.

3. **`psql`** against the Supabase Postgres connection string:

       psql "$SUPABASE_DB_URL" -f OPS/Migrations/2026-05-08-add-product-thumbnail-url.sql
       psql "$SUPABASE_DB_URL" -f OPS/Migrations/2026-05-08-product-thumbnails-storage-policy.sql

## Idempotency

- The column migration uses `ADD COLUMN IF NOT EXISTS`. Re-runs are
  no-ops.
- The bucket insert uses `ON CONFLICT (id) DO NOTHING`. Re-runs leave
  the bucket alone.
- Each policy is `DROP POLICY IF EXISTS` followed by `CREATE POLICY`,
  so re-runs replace the policy in place — same shape, same name.

## Verification

After applying:

```sql
-- 1. Column landed.
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'products'
  AND column_name = 'thumbnail_url';

-- 2. Bucket exists and is public.
SELECT id, name, public FROM storage.buckets WHERE id = 'product-thumbnails';

-- 3. All four policies present.
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename  = 'objects'
  AND policyname LIKE '%product thumbnails%'
ORDER BY policyname;
```

Expected: 1 column row, 1 bucket row with `public = true`, 4 policy
rows (SELECT/INSERT/UPDATE/DELETE).
