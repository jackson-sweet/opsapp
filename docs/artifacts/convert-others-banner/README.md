# CLIENT-HAS-OTHERS banner — header wrap fix (bug 4e11e121)

Proof renders for the convert-lead-to-project sheet's tan attention banner,
produced by `OPSTests/Views/ConvertOthersBannerSnapshotTests.swift`
(drawHierarchy harness, banner rendered inside the sheet's exact scroll
subtree).

**Defect:** the header packed two messages — `// THIS CLIENT HAS 02 OTHER
PROJECTS · REVIEW BEFORE CREATING` — into five separate `Text` fragments in an
`HStack`. At 10pt JetBrains Mono + 1.6 kerning that is ~480pt of glyphs on a
~330pt line, so the fragments wrapped at mismatched baselines on every phone
width.

**Fix:** one message (`// CLIENT HAS 02 OTHER PROJECTS`, singular-aware,
zero-padded mono count) in a single concatenated `Text` run with
`.lineLimit(1)` — structurally incapable of fragment-wrapping at any count.
The "REVIEW BEFORE CREATING" clause was dropped: the tan attention tint and
the tappable project chips already carry the review intent, and coaching
copy is a DESIGN.md anti-pattern.

| File | Shows |
|------|-------|
| `before_12_wrapped@3x.png` | Shipped defect at 393pt, 12 others — header wrapped across two mismatched lines |
| `after_12@3x.png` | Fix at 393pt, 12 others — one clean line |
| `after_12_narrow375@3x.png` | Fix at 375pt (smallest supported iPhone) — one line with headroom |
| `after_01_singular@3x.png` | Singular copy path — `// CLIENT HAS 01 OTHER PROJECT` |
| `after_120_threedigit@3x.png` | Defensive ceiling at 375pt — 3-digit count still one line |
