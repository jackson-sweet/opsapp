# Deck Span Table Sources

Provenance record for every span number encoded in
`OPS/DeckBuilder/Engine/DeckSpanTables.swift`.

**Retrieval date:** 2026-09-05. The three PDFs beside this file are the exact
copies retrieved on that date; re-verify against them, not against a fresh
download, when auditing the encoded rows.

**Standing of the output:** illustrative only. The framing preview is a
picture, not an engineered design and not a code-compliance claim. See
§ "How this is presented in-product" below.

---

## 1. The document the numbers come from

**Canadian Wood Council, *Prescriptive Residential Exterior Wood Deck Span
Guide*, OUTDOOR PROJECT SERIES, Revision 1, © 2016 Canadian Wood Council,
Ottawa.**

- File: `cwc-deck-span-guide.pdf`
- URL: https://cwc.ca/wp-content/uploads/2019/03/Prescriptive-Residential-Exterior-Wood-Deck-Span-Guide.pdf
- Tables used, all **Hem-Fir (H-F)**, **incised**, imperial variants:
  - **Table 3b** — DECK JOIST SPANS INCISED (ft-in) — joist spans + maximum
    allowable cantilever. (Metric twin: Table 3a.)
  - **Table 5b** — BEAM SELECTION INCISED SUPPORTING SINGLE SPAN (ft).
  - **Table 7b** — BEAM SELECTION INCISED SUPPORTING TWO SPANS (ft).
  - **Note 5** to Tables 4a/4b/5a/5b/6a/6b/7a/7b — minimum post size.
  - **Figure 1** notes 3 and 4 — continuity limit and the rule that a
    cantilever is added to the joist span before entering the beam tables.

### Design assumptions, verbatim from p.4

> - Design based on CSA O86-14 and NBC 2015
> - Live load: 1.9 kPa (40 psf)
> - Dead load: 0.5 kPa (10 psf)
> - Grade: No.2 or better
> - Live load deflection limit: L/360
> - Wet service condition factors for all Tables (Ksb = 0.84, Ksv = 0.96,
>   KSE = 0.94)
> - Treatment factors for incised lumber Tables (KT = 0.85 for Bending and
>   Shear, KT = 0.95 for Modulus of Elasticity)

The CWC guide is an **industry guide, not code text**. It is based on
NBC 2015 and CSA O86-14, not on the 2018 BCBC directly. Its provincial
standing comes from § 2.

---

## 2. The BC endorsement

**BC Housing, *Illustrated Guide: Building Safe and Durable Wood Decks and
Balconies*** (prepared by RDH Building Science Inc.), 31 pp.

- File: `bchousing-decks.pdf`
- URL: https://www.bchousing.org/publications/IG-Building-Safe-Durable-Decks-Balconies.pdf

p.12, verbatim:

> The following tables are reproduced from the CWC Prescriptive Residential
> Exterior Wood Deck Span Guide and can be used for incised (treated) wood
> products in wet service conditions. Note that wet service conditions and the
> use of pressure treated lumber will reduce allowable spans compared to
> untreated, protected framing members.

**This settles the incising question.** Pressure-treated deck lumber in BC is
incised and in wet service. The CWC **Incised** tables already carry both
reductions (KT = 0.85 bending/shear, KT = 0.95 MOE; Ksb 0.84 / Ksv 0.96 /
KSE 0.94). **Apply no further treatment or wet-service factor of your own** —
that would double-count, and inventing a factor is barred.

Reproduction verified byte-identical for CWC Table 3a row 38 × 184:
BC Housing p.12 gives `3.71 3.89 3.95 3.23 | 3.21 3.37 3.49 2.80 |
2.62 2.75 2.85 2.28 | 400`, matching CWC Table 3a's four species groups at
300/400/600 mm with a 400 mm cantilever.

Also used from this guide:

- p.10 — decks must carry the greater of local snow load or 1.9 kPa
  (BCBC 9.4.2.3), plus the table of BC design snow loads. See § 5.
- p.11 — BCBC 9.17.4.1 requires 140 × 140 mm (5.5" × 5.5") posts absent
  structural calculation. This is why the encoded default post is **6x6**.
- p.13 — 600 mm (24 in) maximum joist spacing for Part 9 buildings
  (BCBC 9.23.1.1).

BC Housing disclaimer, verbatim (p.3), which governs how the numbers may be
presented:

> While care has been taken to confirm the accuracy of information contained
> herein, the authors, contributors, funders, and publishers assume no
> liability for the accuracy of the statements made or for any damage, loss,
> injury or expense that may be incurred or suffered as a result of the use of
> or reliance on the contents of this Guide. It is the responsibility of all
> persons undertaking the design and construction of wood decks or balconies to
> review and comply with British Columbia's Building Code.

---

## 3. The BCBC document — retained for reference, deliberately NOT used for spans

**2018 British Columbia Building Code, Division B — Span Tables**, document id
`BCBC_2018DBP9ST`, title `835_Division B - Span Tables`, 44 pp, published free
by BC Publications.

- File: `bcbc2018-span-tables.pdf`
- URL: https://free.bcpublications.ca/civix/document/id/public/bcbc2018/bcbc_2018dbp9st

Its Table 9.23.4.2.-A (floor joists) and Table 9.23.4.2.-H (built-up floor
beams) cover Hem-Fir No.1/No.2 — **and must not be used for a deck**:

- **9.23.4.1.(1)** limits those spans to floors that "serve residential areas
  as described in Table 4.1.5.3." A deck is an exterior platform, not an
  interior residential floor.
- BC Housing p.10: wood framing in wet service "is not accounted for in the
  prescriptive solutions provided in BCBC 9.23". The Part 9 floor tables carry
  no wet-service and no incising reduction; OPS's specified lumber is
  pressure-treated.
- **Part 9 contains no prescriptive deck-joist cantilever limit.** The only
  cantilever article, **9.23.9.9.(1)**, applies to floor joists supporting roof
  loads. A deck joist supports no roof load, so the article does not govern.
  Applying it to a deck would be an inference, which is barred.

Retained because its ledger/anchorage articles (9.23.6.2, 9.23.8.1) and the
post minimum (9.17.4.1) *are* deck-applicable.

---

## 4. What is deliberately NOT encoded

Anything without a citable Canadian source is absent from the code. Do not add
any of these without primary source text.

| Item | Why it is absent |
|---|---|
| **Beam overhang / post inset from the side edges** | No Canadian source gives one. Searched: CWC guide (joist cantilever only, no overhang rule), BC Housing guide, BCBC 2018 Div. B § 9.23 (9.23.8 covers beam *bearing*, not overhang), City of Courtenay deck guide (procedural only). A US rule exists (IRC R507.5.1 / AWC DCA6, overhang ≤ ¼ back-span) but was only found in secondary calculator sites, and it is American. Not encoded. |
| **Ledger fastener spacing** | BC Housing p.14 supplies a table but states BCBC "does not provide comprehensive guidance on ledger fastening patterns" and the table is adapted from IRC R507.2. Out of scope — the preview draws a ledger, it does not spec fasteners. |
| **Footing size / depth** | Governed by soil (BCBC 9.12.2.2). Footings stay schematic. |
| **Lateral bracing** | BCBC 9.17.2.2 requires it above 600 mm. The preview does not draw bracing. |
| **`blockingRunCapInches = 48.0`** in the planner | Not a span limit; no cited source governs it. Left untouched rather than replaced with an invented number. |
| **4x4 posts under 6.5 ft** | CWC Note 5 permits them; BCBC 9.17.4.1 requires 6x6 absent calculation. Encoded default is 6x6. |
| **2x4 joists** | CWC Table 3b has the row, but Table 3b note 2 forces ≥ 2x8 wherever a guard is required, and `LumberSize` has no 2x4 case. Not encoded. |

---

## 5. Known limitation — snow load

CWC's basis is a 1.9 kPa live load. BC Housing p.10: decks "must be designed to
accommodate the local specified snow load or an occupancy load of 1.9 kPa —
whichever load is higher (BCBC 9.4.2.3)."

From BC Housing's own table of design snow loads for decks (p.10):

| Within the CWC basis (≤ 1.9 kPa) | Exceeds it |
|---|---|
| Victoria 1.0, Kelowna 1.0, Kamloops 1.2, Vancouver 1.2, Merritt 1.3, Abbotsford 1.4, Cranbrook 1.9 | Prince George 2.1, Terrace 3.6, Whistler 6.1 |

**OPS has no location or snow-load input.** In high-snow locations the
illustration is optimistic. This cannot be fixed without a snow input, and it
is an independent reason the output must stay labelled illustrative.

---

## 6. How this is presented in-product

The 3D framing preview is transient: `DeckFramingPreviewPlanner` output is a
local inside `DeckSceneBuilder` and is never saved, synced, sized, or emitted
as authored framing. `FramingMember.sizing` stays nil. The viewport carries an
`ILLUSTRATION ONLY` mark.

Never present this output using the words "code", "compliant", "approved",
"engineered" or "certified".

---

## 7. Relationship to DeckKit (`ops-decks-ios`)

DeckKit has a sizing subsystem (`CodePackage.swift` `BeamSpanSizingRow` /
`PostHeightSizingRow`, `StructuralSizingEngine.swift`) but its Canadian package
`CodePackages/CA-BC-2024.subset.json` is **empty** — `beamSpanTable: []`,
`postHeightTable: []`, `envelopeLimits: {}` — and `catalog.json` states
"Structural span and post tables are not included and remain not assessable."
The two repos share zero code today.

`DeckSpanTables.swift` therefore mirrors DeckKit's field naming so that a later
merge is mechanical, but does not attempt a cross-repo SPM link.
