# Spotlight Indexing — Manual Test Checklist

Run after any changes to the Spotlight indexing or deep-link code. This checklist
exists because most Spotlight functionality cannot be unit tested — Core Spotlight
has no test-accessible read API, and deep-link taps require a real device.

## Setup
- [ ] Delete app from test device
- [ ] Install fresh build
- [ ] Log in as admin user (has all permissions — `projects.view`, `clients.view`, `pipeline.view`, etc.)
- [ ] Wait for initial sync + Spotlight backfill notification flow

## Initial backfill
- [ ] iOS banner appears: "Indexing your OPS data…"
- [ ] Banner body updates through phases: Projects → Clients → Contacts → Tasks → Invoices → Estimates → Leads with a percentage
- [ ] Final "Search ready" completion banner fires
- [ ] Xcode console shows `[Spotlight] Indexed N projects/clients/sub-clients/tasks/invoices/estimates`
- [ ] Xcode console shows `[Spotlight] Indexed N leads` (network fetch — requires connectivity; leads are the only domain not sourced from local SwiftData)

## Search from home-screen swipe-down
- [ ] Search by project title → project appears under OPS with a thumbnail
- [ ] Search by client name → client appears with avatar (or person SF Symbol)
- [ ] Search by client phone (last 4 digits) → client appears
- [ ] Search by client email domain → client appears
- [ ] Search by invoice number (e.g. "INV-001") → invoice appears
- [ ] Search by estimate number → estimate appears
- [ ] Search by task title → task appears with parent project thumbnail
- [ ] Search by lead contact name → lead appears with the steel-blue opportunity glyph; subtitle shows stage + street
- [ ] Search by lead phone (last 4 digits) → lead appears
- [ ] Search by lead email domain → lead appears
- [ ] Search by lead street/address → lead appears

## Tap → detail routing
- [ ] Tap project result → app opens project detail sheet
- [ ] Tap client result → app opens ClientSheet in edit mode
- [ ] Tap invoice result → app opens InvoiceDetailView
- [ ] Tap estimate result → app opens EstimateDetailView
- [ ] Tap lead result → app switches to the LEADS tab and opens LeadDetailView (resolves from memory, or by network `fetchOne` if not loaded — test both by tapping a lead right after a cold launch before opening the LEADS tab)
- [ ] Tap task result → app routes to task (currently opens project detail — task detail requires a `ops://projects/X/tasks/Y` form; log it as known limitation if still missing)

## Permission re-check (critical)
- [ ] While admin role: index everything normally
- [ ] In Supabase admin, change the user's role from admin to field crew
- [ ] Relaunch app → permissions refetch detects role change → Spotlight clears and re-indexes
- [ ] Verify previously-visible invoices/estimates no longer appear in Spotlight search
- [ ] Verify previously-visible leads no longer appear (field crew lack `pipeline.view`)
- [ ] If you search for a cached invoice ID directly from a prior screenshot, tap it → `AccessDeniedSheet` appears
- [ ] Turn OFF the `pipeline` feature flag for an admin (keep `pipeline.view`) → relaunch / next pipeline load → leads drop out of Spotlight, and a tap on a cached lead result → `AccessDeniedSheet` ("You don't have permission to view leads.")

## Offline
- [ ] Airplane mode → search still returns results (Spotlight index is on-device)
- [ ] Airplane mode → tap result → detail sheet loads from local SwiftData

## Logout
- [ ] Log out → Spotlight index cleared (search for known project → no result)
- [ ] Log back in → backfill runs again → results reappear

## Edge cases
- [ ] Project with no images → briefcase SF Symbol thumbnail
- [ ] Client with no avatar → person SF Symbol thumbnail
- [ ] Invoice with empty title → invoice number used as title
- [ ] Phone number search with formatting differences (e.g. "(555) 123-4567" vs "5551234567") → both work
- [ ] Soft-deleted project (deleted_at set server-side) → removed from Spotlight after next sync
- [ ] Email-sourced lead with blank contact name → title falls back to the inquiry subject (never "Unnamed lead" while a subject exists)
- [ ] Archive a lead (or delete it, or convert it to a project) → after the next pipeline load it disappears from Spotlight (`[Spotlight] Pruned N stale leads` in console)
- [ ] Create a new lead → after the pipeline reload it becomes searchable by name/phone/email

## Deep link scheme (URL-based entry)
- [ ] `ops://projects/{known-id}` in Safari → app opens → project detail sheet
- [ ] `ops://clients/{known-id}` → client sheet
- [ ] `ops://invoices/{known-id}` → invoice sheet
- [ ] `ops://estimates/{known-id}` → estimate sheet

## Performance
- [ ] Backfill on a company with 1000+ projects completes in under 30 seconds
- [ ] App remains responsive during backfill (indexing runs off main thread via `UIBackgroundTask`)
