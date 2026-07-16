# Font-token sweep — zero-visual-change proof

## What changed

Two mechanical tokenization passes over hand-rolled `.font(.custom(...))` literals,
each replacement pointing at an `OPSStyle.Typography` token whose definition is
**byte-identical** to the literal it replaces (so the resolved `Font` is unchanged).
Per-site `.tracking` / `.kerning` / `.textCase` were left untouched.

**Pass 1 — `miniLabelBold` adoption (13 sites).** The remaining
`.custom("JetBrainsMono-Medium", size: 10)` usages outside Leads → `OPSStyle.Typography.miniLabelBold`
(defined = JetBrains Mono Medium 10): Books (9 across 8 files), `TacticalFilterChips` (1),
`UnifiedLogActivitySheet` (3). Companion to the earlier Leads-header migration.

**Pass 2 — Leads literal tokenization (42 of 86 sites).**
- `JetBrainsMono-Regular 10` → `miniLabel` (24)
- `JetBrainsMono-Regular 9.5` → **new token `nanoLabel`** (14) — the densest micro-label
  tier (timeline stamps, stage tags, KPI-cell labels); a genuinely recurring role.
- `JetBrainsMono-Regular 11` → `metadata` (1); `JetBrainsMono-Regular 13` → `dataValue` (1);
  `Mohave-Regular 14` → `cardBody` (1); `Mohave-Medium 16` → `bodyBold` (1)

The remaining ~44 Leads literals were deliberately **left** as call-site values: context-sized
numeric readouts (money/counts/percent at bespoke sizes with no matching numeric token), the
heterogeneous `JetBrainsMono-Medium 11` cluster (no single coherent role), the `Mohave-Medium 14`
row *titles* (mapping to the same-metrics `smallButton` token would be a role-lie), dynamic
`size:` expressions, and one-off badge sizes.

New token added: `Font.nanoLabel` (Fonts.swift) mirrored as `OPSStyle.Typography.nanoLabel`.

## Method

`iPhone 17` simulator (OS 26.5), `@3x`. Three snapshot classes rendered **before** (clean
`566a9001` base) and **after** (all edits), attachments exported and compared by SHA-256, keyed on
`testIdentifier` + attachment name:

- `MoneyLeadsRedesignSnapshotTests` — Books command grid, ledger primitives/rows/swipes, lens
  sheets, review-batches link, Leads summary/triage.
- `UnifiedLogActivitySnapshotTests` — the activity sheet (call + note).
- `LeadDetailAdditionsSnapshotTests` — full lead detail (DetailHero + timelines), lead form, deck
  rows, photo strip.

Device-target build (`generic/platform=iOS`): **BUILD SUCCEEDED**, zero errors.

## Result — 37 / 38 snapshots byte-identical

The one non-match, `leads_detail_components`, differs **only** in the fixture's random lead id
(`Opportunity.preview(id: UUID().uuidString)` → `displayId` `L-9A6F20` before vs `L-1B9C7E` after).
Every font-bearing pixel — including the `nanoLabel` labels (`VALUE`, `WEIGHTED`, `SOURCE`,
`ESTIMATED`, `9D IN STAGE`, `60% WIN PROB`) and the `cardBody` subtitle (`Roof tear-off, 28 sq`) —
is pixel-identical across the two renders. See `leads_detail_components_before@3x.png` vs
`_after@3x.png` in this directory (only the `L-…` id text moves). This is a fixture artifact,
orthogonal to the refactor.

### Byte-identical (before SHA-256 == after SHA-256)

| Snapshot | SHA-256 |
|---|---|
| `testRenderCommandGridPermissionReflow :: money_grid_no_pipeline@3x_0` | `aaf7758116a1dc6cdd46ee597d09e17a21d6ba7c96960f79e2d0caebdb6a37b0` |
| `testRenderCommandGridPermissionReflow :: money_grid_pipeline_only@3x_0` | `251f0f1da27058fa149c2463bd0b754fd0d09216c3d7204e01da17b8139eddcd` |
| `testRenderDeckCard :: lead_deck_card@3x_0` | `74cf9119e8c1aac60b686ebffa60dec62f0bcce1b472eb360def8555cd8d98fd` |
| `testRenderDeckStartRow :: lead_deck_start_row@3x_0` | `152dee50cba9161e6bc5c1e0d93fa2d5b55ad2b39fc140d371f3e014457db9c7` |
| `testRenderEditLeadSheet :: edit_lead_sheet@3x_0` | `116c43674a99950b4fe2738f47ade7dad4835b60a94f1e5a05ab8fae7ad37eab` |
| `testRenderLeadDetail :: lead_detail_full@3x_0` | `7c3ed263c8af053c566b8eeca6ac94cdf8113f3ec09ce880abd0547c08475f69` |
| `testRenderLeadForm :: lead_form_address@3x_0` | `c6065b9e792dab1e3fe20b7f11eee1f6ef37146a36dd29e86ef4a46b6dadffbd` |
| `testRenderLeadTriageCardSource :: leads_triage_card_source@3x_0` | `b8347f8e6a159086bf9fb4a67775b276a97caf3fc62326cd61c098272040f9cc` |
| `testRenderLeadTriageCards :: leads_triage_cards@3x_0` | `fac733c0a3a0f7febb5f2f0d5be4dd94e40dd51e814772072eb4b6515c856695` |
| `testRenderLeadTriageCardsTerminal :: leads_triage_cards_terminal@3x_0` | `54ac8da7e2f892980395af05d17c231cd4148935302353935c8d2e5e382f32fc` |
| `testRenderLeadsSummary :: leads_by_stage@3x_0` | `011ad968363ad3be62e3f7c75fa1a07a8e268bd3bed772c69c1d1644b3f7e59f` |
| `testRenderLeadsSummary :: leads_caught_up@3x_0` | `40bcc890930bf813c6ff58b10be9c97d6527a2441f7367ea41dbba77e91166fd` |
| `testRenderLeadsSummary :: leads_summary@3x_0` | `77a67e140fc49f8da94a351180e4b900896ca3c32f2013e44045d8591b9bd090` |
| `testRenderLeadsSummary :: leads_won_nudge@3x_0` | `ab019f02809b493ea62e9f753a8f915d232b643a3c2ee0aa42e16ece2fa4dcfb` |
| `testRenderLeadsWonChooser :: leads_won_chooser@3x_0` | `415cf3f8ad76a76c700bf2185409ed855b7e908abf9f23af2ffef717bab95309` |
| `testRenderLedgerRows :: money_estimate_rows@3x_0` | `57e0a077345f1ca348fdf4bc4fa699569b86b4fde85037088ae53bd2978233cb` |
| `testRenderLedgerRows :: money_expense_rows@3x_0` | `6ff4adf9892ef850f21ad16b8eb9ea5c242a2ed09640d7ed03e0937b5f9d2552` |
| `testRenderLedgerRows :: money_invoice_rows@3x_0` | `f968f468386885a8c5f485584ab1e356fcd02c6fd7653769e5cea6930a9e653b` |
| `testRenderLedgerSwipeStrips :: money_swipe_leading_payment@3x_0` | `99503044752737f63ea90e376e2f61b83effc1503869fee156115073d0d78f60` |
| `testRenderLedgerSwipeStrips :: money_swipe_leading_send@3x_0` | `ca110254536b0c605d39245b5030b0f061a94190119b9eca44d66eafb0274b09` |
| `testRenderLedgerSwipeStrips :: money_swipe_trailing_delete@3x_0` | `45638cfca2a19f96b1df3dc73e89c331729bc4a982b412f4eaa63d61fe435387` |
| `testRenderLedgerSwipeStrips :: money_swipe_trailing_void@3x_0` | `7dd3b41013f3fb93cc9ee8b1b9ace1d6e1230010557e30b8551a6ed054583ddb` |
| `testRenderLensSheets :: sheet_cashflow@3x_0` | `807c9597c68f3c98638f40bb4ce11e1febac8e42b68872ea51ffa33c9744e168` |
| `testRenderLensSheets :: sheet_empty_state@3x_0` | `61d9b964ba22a5ebc7dd45143a0274ea0c6a24ba51849119db3d0a54702c121a` |
| `testRenderLensSheets :: sheet_forecast@3x_0` | `2b924ed65cc6b5c6087ad3393c2beaf2d05c9cab79c5d10c5b9ef8f16945a7c7` |
| `testRenderLensSheets :: sheet_jobs@3x_0` | `a285c356ea9f7eb3412f474cb9ffa16e0ab4b4c254392342b227425eab27b3f5` |
| `testRenderLensSheets :: sheet_pl@3x_0` | `a0769915d5479ee1b4dd37e90099d2bee6d0cf3cdf86327e4285e831bac50057` |
| `testRenderLensSheets :: sheet_receivables@3x_0` | `23048fccae6f98b1327eff42f175a9ae660fde266ab201459d80a4ce04a0606c` |
| `testRenderMoneyCommandGrid :: money_command_grid@3x_0` | `6acdf9ad3f64fc1ab6d4a68328dfb1beae21a531c0f9b5a8f94fd110b3248903` |
| `testRenderMoneyLedgerPrimitives :: money_ledger_empty@3x_0` | `b88b2e250433ea33234395e60c26c9bb9a1efafbf5a8f70338c7a7c27e91a070` |
| `testRenderMoneyLedgerPrimitives :: money_ledger_segments@3x_0` | `969497244b6ca63bbac371f7f8b3297eb933dedae924e2448a908e124a7e74a7` |
| `testRenderMoneyLedgerPrimitives :: money_status_pills@3x_0` | `7704183539d39a191a505a4ab6d50c8406a70840fc7de7c0b8c91238d7290a81` |
| `testRenderPhotosEmptyManage :: lead_photos_empty_manage@3x_0` | `1ab1ca009b434d280a8c43e160eb8307cbeec1cc570821d6bd3a0858930a399a` |
| `testRenderPhotosStripWithQueuedTiles :: lead_photos_strip_queued@3x_0` | `7fbd7554164a4ef24f2454960fcc6ee469ab2ad3ba3f1c1223bb731c38e57f4b` |
| `testRenderReviewBatchesLink :: money_review_batches_link@3x_0` | `e34bf9c55e9b36c1ce8d1919136750e1f4e97f656f2f20b896575949c80eac59` |
| `testRenderUnifiedSheetCall :: unified_activity_call@3x_0` | `67223c6fe14a386dd30f16dbd3706228ce17b5f57ea56d5c79cb96828fd8ad00` |
| `testRenderUnifiedSheetNote :: unified_activity_note@3x_0` | `d8a228fef0d5956e567693f6fe602213de86cc328abc5e73673a4e5298c4b77d` |

### Explained non-match (random fixture id only)

| Snapshot | before SHA-256 | after SHA-256 |
|---|---|---|
| `testRenderLeadDetailComponents :: leads_detail_components@3x_0` | `6cf61d49f746442916e8c36636fbcb8929516d787d91995219eff1c806f02611` | `40c3d49a1668f025335012cf72e73626cef80dab4dfff47258d8e879f0fc1130` |
