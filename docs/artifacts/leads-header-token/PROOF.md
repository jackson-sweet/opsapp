# Leads panel-header font tokenization — zero-visual-change proof

**Change:** the 13 hand-rolled `.font(.custom("JetBrainsMono-Medium", size: 10))` usages
across the 7 Leads files now reference `OPSStyle.Typography.miniLabelBold`
(defined in `OPS/Styles/Fonts.swift`, mirrored in `OPSStyle.Typography`).
Per-site `.tracking`/`.kerning` values (0.9–1.6) are unchanged — spacing is a
per-component spec applied at the call site, per the Typography enum's own
convention.

**Proof:** `MoneyLeadsRedesignSnapshotTests/testRenderLeadsSummary` rendered
before and after the migration (iPhone 17 sim, @3x). All four PNGs are
**byte-identical** (`cmp` + SHA-256):

| Snapshot | SHA-256 (before == after) |
|---|---|
| leads_summary | `77a67e14…9bd090` |
| leads_by_stage | `011ad968…f7e59f` |
| leads_won_nudge | `ab019f02…4dcfb` |
| leads_caught_up (control) | `40bcc890…166fd` |

`leads_summary@3x.png` in this directory is the rendered header surface
(identical on both sides of the change).
