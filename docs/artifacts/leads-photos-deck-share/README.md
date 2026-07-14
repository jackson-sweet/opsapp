# LEADS additions — visual proofs (2026-07-14)

Rendered by `OPSTests/Views/LeadDetailAdditionsSnapshotTests.swift` (ImageRenderer @3x,
iPhone 17 / iOS 26.5 simulator, dark scheme, DEBUG preview seeders).

| Shot | Proves |
|------|--------|
| `lead_photos_empty_manage@3x.png` | PHOTOS section empty state for pipeline.manage — single quiet 48pt ADD PHOTOS row, no acreage |
| `lead_photos_strip_queued@3x.png` | Thumb strip: ADD tile + 84pt tiles, QUEUED badges on offline captures, `// PHOTOS 03` header count |
| `lead_deck_start_row@3x.png` | DECK DESIGN empty state — START DECK DESIGN row (feature-flag + manage gated) |
| `lead_deck_card@3x.png` | Deck card: read-only 2D blueprint preview, title + UPDATED stamp, chevron affordance |
| `edit_lead_sheet@3x.png` | Name-first edit header (`// EDIT · L-XXXXXX` eyebrow over the contact name) |
| `lead_form_address@3x.png` | The shared MapKit autocomplete SITE ADDRESS field — 48pt row, token chrome parity with sibling inputs, use-my-location affordance |
| `lead_detail_full@3x.png` | Full detail composition — hero → contact → site-visit → PHOTOS → DECK → activity, share affordance in the nav bar |

Notes:
- Rendered via UIHostingController + UIWindow **attached to the host
  UIWindowScene** + drawHierarchy — ImageRenderer leaves ScrollView content
  blank, and an unsceened window renders blank white.
- Remote photo tiles render through AsyncImage (network) — the strip proof uses
  seeded QUEUED tiles so the pixels are deterministic.
- Test-side seeding uses the DEBUG-only `LeadImageService._setQueueForSnapshots`.
