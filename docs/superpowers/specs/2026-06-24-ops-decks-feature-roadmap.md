# OPS Decks — Full Power-User Feature Roadmap

**Date:** 2026-06-24
**Status:** Draft for Jackson's review (functionality roadmap; companion to the Phase 1 foundation spec)
**Companion:** `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md` (Phase 1 foundation/carve-out)
**Grounded in:** direct code inspection of 73 files under `OPS/DeckBuilder/` + `OPS/DataModels/DeckDesign.swift`; 8 feature domains benchmarked vs pro tools (RedX Decks, Simpson Deck Planner, Chief Architect) + building code (IRC R507/R311.7/R312, AWC DCA6, NBC/BCBC Part 9); plus a dedicated as-built code-audit study.

---

## 0. Executive summary

The most important finding, verified against code (not optimistic labels): **OPS today has zero engineering.** What renders as "structure" in the 3D view is decorative SceneKit geometry — fixed 6×6 posts, an 11″×5″ footing box, rim joists hardcoded to 9.25″ (`DeckSceneBuilder.swift:370-521`) — plus a 3-case `FootingType` enum (`DeckGeometry.swift:160`). There are **no** model fields for joists, beams, posts, spans, species, loads, doors, windows, terrain, or roofs. The estimate engine bills raw square/linear footage with **no waste factor** (`EstimateGeneratorService.swift:185-194`) — a correctness bug that systematically under-orders material.

What OPS *is* genuinely good at — the ~10% that works, and what the **LIGHT** tier keeps — is **field capture and communication**: freehand/template 2D drawing, AR perimeter + height measure, a 7-stage sketch scan-to-plan, multi-level geometry, material/railing/stair assignment, a real `StairCalculator` (encodes IRC R311.7), a fully-solved `VinylCutListEngine` with offcut banking, and branded PNG/PDF share.

**The standalone product is an *engineering* product wearing a deck-design UI.** It does not meaningfully exist until two foundational pieces land: a **framing data model** and a **versioned, jurisdiction-aware code-table store**. Everything else — sizing, footings, compliance, permit drawings — depends on those. The competitive bar is **RedX Decks** (mobile, already does auto-framing + per-member load calc + permit blueprints).

**The line between LIGHT and FULL is one word: _compliance._** LIGHT may *visualize* and *price* a plausible deck. The moment the app asserts a member size, a span, a footing dimension, a code pass, or permit-readiness, that is a FULL-tier engineering claim with legal weight — and it must be gated behind the liability guardrails in §7.

---

## 1. The LIGHT vs FULL split

**Principle: LIGHT sells and scopes the job; FULL builds, engineers, and permits it.** The boundary is any *assertion* of a member size, span, footing dimension, code pass, or permit-readiness.

A salesperson in a backyard or an estimator at a desk needs a believable picture and a defensible price — not an engineering claim. The instant the app says "this beam is a doubled 2×10 spanning 9′-2″, code-compliant," it has crossed into FULL.

**LIGHT (stays embedded in OPS):**
- All current field capture: freehand/template 2D drawing, AR perimeter + height measure, sketch scan-to-plan, multi-level geometry, photo overlay, undo/redo.
- Material / railing / stair / gate assignment (shares the catalog *schema*; exposes a simpler picker).
- The vinyl cut engine (already complete; a genuine differentiator for vinyl shops).
- A **plausible auto-derived frame** for visualization + a rough substructure BOM — *with sane defaults and no code claim*.
- A **single tunable waste % per pattern** (fixing the zero-waste bug — a correctness fix, not a power feature).
- Ground-type selection + better textured 3D ground (cosmetic; no grade math).
- The cladding picker (already ships).
- Branded PNG/PDF share + client proposal + a sell-grade 3D render.

**FULL (standalone power tool) exclusively owns:**
- Every span/load/sizing calculation (joist, beam, post, footing, cantilever) + the versioned code-table store behind them.
- **Load calculation at each column/post** (tributary → per-member reactions).
- Ledger + lateral-connection design and Simpson hardware selection.
- Grade/slope capture and everything it unlocks (post-height engine, 30″ guard auto-flag, grade-driven stairs, frost-depth footings, drainage, retaining walls).
- House model + door/window placement + wall cutouts + elevation/section drawing views.
- Roofs / overhead structures with engineered load paths.
- Decking-pattern + picture-frame engines, board-nesting cut optimization, fastener takeoff, finish takeoff.
- Setbacks/site plan, the multi-sheet **permit plan set**, the **structural calc report**, the **engineer (PE) stamp workflow**, and CAD interop.
- Advanced stairs (tread types, stringer count, landings, winders), lighting/electrical, built-ins.
- The **as-built CURRENT → TARGET code audit** (§3).

**Graceful degradation (architectural):** FULL designs round-trip through LIGHT via the same `drawing_data` JSON. A LIGHT install opening a fully-engineered design renders the geometry it understands and **preserves (never strips)** the framing/terrain/permit blocks it can't render. One schema, capability-gated rendering.

---

## 2. Feature roadmap by domain

Complexity: **L** low · **M** medium · **H** high · **VH** very-high. Tier: **LIGHT** / **FULL** / **BOTH** (shared, degrades into LIGHT).

### 2.1 Structural framing & load engineering — *the largest net-new build*
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Framing data model (joist/beam/post/ledger/rim/blocking) | none | H | BOTH | foundational; grows inside `drawingDataJSON` |
| Auto-framing engine (derive members from outline + height) | none | VH | BOTH | uses `EdgeType.houseEdge`; mirrors `DeckTemplateEngine` auto-then-preserve; IRC R507.5/.6 |
| Species/grade + load preset selector | none | L | BOTH | 40+10 psf default; 50/60/70 snow |
| Joist span-table engine (allowable span + deflection) | none | VH | FULL | IRC R507.6 + AWC DCA6; `StairCalculator` precedent |
| Beam sizing & post-spacing back-solve | none | VH | FULL | IRC R507.5; bearing 1.5″ wood/3″ concrete |
| **Load calc (tributary → per-post/beam)** | none | H | FULL | IRC R507.1 / Table R301.5; RedX parity |
| Post sizing & height limits | partial (hardcoded 6×6) | H | FULL | IRC R507.4 |
| Cantilever modeling (2021 adjacent-span limits) | none | H | FULL | IRC R507.6 |
| Rim/band joist, blocking & bridging | partial (visual) | M | BOTH | DCA6 (8′ cap w/o blocking) |
| Manual framing editor (select/size/move/lock) | none | H | FULL | mirrors Chief Architect edit |
| Framing-layer 3D render (real members) | partial | M | BOTH | `DeckMeshGenerator` |
| Framing takeoff/BOM (lumber + hardware + concrete) | partial (footings only) | M | BOTH | `ComponentEmitter` |

### 2.2 Footings & foundations
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Footing-type catalog (pier/sonotube/helical/deck-block/pad) | partial (3-case enum) | L | BOTH | `DeckGeometry.swift:160` |
| Per-footing sizing fields (dia/depth; helical torque) | none | L | BOTH | |
| Manual footing placement (interior/beam-line piers) | partial (perimeter only) | M | BOTH | `PropertySheetView` |
| Footing count + concrete volume/bag takeoff | partial (count @ $0) | M | BOTH | |
| Soil bearing input (presumptive / geotech override) | none | L | FULL | IRC R401.4 (1500 psf default); BCBC 9.12 |
| Frost-depth dataset + per-project frost line | none | H | FULL | IRC R403.1.4; needs geolocation |
| Auto-footing sizing engine | none | VH | FULL | IRC R507.3.1; DCA6 Tbl 4; NBC/BCBC 9.12.2.2 |
| Post-to-footing connection & uplift hardware | none | H | FULL | IRC R507.4 |
| Real 3D footing geometry (cylinder/helix/pad) | partial (fake box) | M | FULL | |
| Footing code-compliance check & report | none | VH | FULL | IRC R403.1.4/.2, R507.3/.4 |

### 2.3 Overhead structures (pergolas, covers, roofs)
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Overhead-structure data model + attachment | none | H | FULL | reuses framing/footing |
| Pergola / open shade (rafters+beams+posts, shade %) | none | H | BOTH | first overhead build |
| Louvered / adjustable roof (aluminum product) | none | M | FULL | StruXure/Azenco as catalog products |
| Solid roof / patio cover (shed/gable/hip) + ledger & flashing | none | VH | FULL | IRC App. H + R507 *(App. H paywalled — unverified)* |
| Engineered members via shared structural engine | partial | VH | FULL | build engine once, apply to deck + overhead |
| Overhead 3D render + roof covering + estimate + code check | partial | VH | BOTH | extends `ComponentEmitter` |

### 2.4 House attachment (ledger, doors, windows, cladding, multi-story)
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Cladding-type picker (stucco/Hardie/brick/stone/vinyl/wood/parapet) | **exists** | L | BOTH | `DeckGeometry.swift:272-310` |
| House wall as real object (floor-line datum + story heights) | partial (cosmetic) | H | FULL | uses AR height measure |
| **Door placement & sizing** (patio/French/slider) | none (OCR keyword only) | H | FULL | `SketchOCR.swift:210` |
| **Window placement & sizing** | none (OCR keyword only) | H | FULL | `SketchOCR.swift:211` |
| Wall-opening cutout (2D & 3D) | none | H | FULL | |
| Elevation (front-on) drawing view | none | H | FULL | gates permit set |
| Ledger attachment detail + code check per cladding | none | VH | FULL | IRC R507.9; brick/stone → freestanding fallback |
| Multi-story deck at upper floor + stairs to grade | partial (multi-level only) | H | FULL | `DeckLevel`, `LevelConnection`, `StairCalculator` |
| Door/window schedule + plan callouts | none | M | FULL | |

### 2.5 Site, terrain & ground
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Per-zone ground-type / surface-cover selection (grass/dirt/gravel/rock/concrete/pavers) | none | M | BOTH | `BuiltInMaterial` |
| Textured 3D ground render (replace flat tint) | partial | M | BOTH | `DeckMeshGenerator` |
| **Yard grade/slope capture (keystone)** | none | H | FULL | AR height measure → terrain |
| Height-above-grade engine (post heights + 30″ guard auto-flag) | partial | H | FULL | IRC R312.1.1/.1.2 |
| Grade-driven stair total-rise & step count | partial | M | FULL | `StairCalculator`; IRC R311.7 |
| Footing depth from frost line (zip/AHJ-driven) | partial | M | FULL | IRC R403.1.4 |
| Setbacks & property-line site overlay | none | H | FULL | local zoning (user-supplied) |
| Drainage / grade-fall check (R401.3) | none | M | FULL | 6″ in 10′; 2% impervious |
| Multi-level grade & retaining walls | partial | VH | FULL | IRC R404/R403 |
| Survey/contour import (DWG/DXF) → terrain TIN | none | VH | FULL | **recommend EXCLUDE** — desktop-CAD territory |

### 2.6 Deck surface features (railings, stairs, gates, fascia, skirting, built-ins, lighting, patterns)
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Guard/railing parametrics (height/spacing/mount/color) | **exists** | L | BOTH | IRC R312.1.2/.1.3 |
| Straight-flight stairs with stringers | **exists** | L | BOTH | `StairCalculator`; IRC R311.7 |
| **Stair tread types** (open/closed riser, tread material, nosing) | none | M | FULL | IRC R311.7.5 |
| **Stringer count / spacing / sizing** | none | M | FULL | DCA6 stair guidance |
| Multi-level decks & transitions | **exists** | M | BOTH | |
| Mandatory handrail logic (graspable, 4+ risers) | partial | L | BOTH | IRC R311.7.8 |
| Gate model (width/leaf/hinge/latch/self-close pool flag) | partial (bool+36″) | M | BOTH | `DeckGeometry.swift:538-587` |
| Railing component breakdown (rail/infill/post/sleeve/cap) | partial | H | FULL | `ComponentEmitter` |
| Railing frame-material families (alu/composite/PVC/wood/cable/glass) | partial | M | FULL | |
| Stair landings & multi-flight (L/U-turn) | none | H | FULL | IRC R311.7.6 |
| Winder / curved stairs | none | VH | FULL | IRC R311.7.5.2.1 |
| Fascia & rim-board cover | none | M | FULL | |
| Skirting / lattice / under-deck enclosure | none | M | FULL | |
| Decking pattern + board-direction engine + cut-list/waste | none | H | FULL | DCA6 diagonal blocking 12″ o.c. |
| Picture-frame / border decking (miters, breaker boards) | none | H | FULL | DCA6 perimeter blocking |
| Deck lighting layout (low-voltage + transformer sizing) | none | H | FULL | NEC Art. 411 |
| Basic electrical (receptacle + GFCI note) | none | M | FULL | NEC 210.52(E), 210.8(A)(3) |
| Built-in benches / planters / privacy walls | none | H | FULL | IRC R312 (bench ≠ guard unless 36″) |
| Automated guard/stair code review | none | VH | FULL | IRC R312/R311.7; 30″ rule |

### 2.7 Materials, finishes, patterns & fasteners
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Brand-neutral catalog model (family/profile/lengths/coverage/fastener/finish) | partial | H | BOTH | `BuiltInMaterial`, `ProductUnitDimension` |
| User-editable catalog (prices, vendor/SKU, per-length pricing) | partial | H | BOTH | needs Supabase sync + ops-web admin |
| **Pattern-aware waste-factor engine** (single-% even in LIGHT) | none | M | BOTH | fixes `EstimateGeneratorService:185-194` zero-waste bug |
| Vinyl/PVC membrane roll + seam planner | **exists** | H | BOTH | `VinylCutListEngine` |
| Decking pattern per surface (parallel/diagonal/picture-frame/herringbone/chevron) | none | M | FULL | |
| Board-nesting cut optimizer (all board families) | partial (vinyl only) | VH | FULL | generalize `VinylCutListEngine` |
| Fastener system takeoff (hidden clips vs face screws) | none | H | FULL | couples to joist layout |
| Finish/coatings takeoff (stain/sealant/paint) | none | L | FULL | |
| Brand preset packs (Trex/TimberTech/Fiberon/Duradek… editable seed) | partial | M | FULL | |

### 2.8 Outputs (permit plan sets, framing plans, elevations, schedules, deliverables)
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Branded share image / quick PDF | **exists** | L | BOTH | `DeckShareRenderer` |
| Vinyl cut plan / offcut output | **exists** | L | BOTH | `VinylCutListEngine` |
| Client proposal (priced, branded, e-signable) | partial | M | BOTH | ties to pipeline/notifications |
| Upgraded client 3D render / hero image | partial | M | BOTH | |
| Photorealistic render + walkthrough | none | H | FULL | needs RealityKit/Metal (SceneKit non-PBR) |
| Dimensioned plan-view (to scale + dimension strings) | partial | H | FULL | drafting engine + title block |
| **Framing plan** (joist/beam/post/ledger callouts) | none | VH | FULL | needs structure model + drafting |
| **Elevation drawings** (front/rear/side to scale) | none | H | FULL | needs house model + terrain |
| **Cross-section** (footing→post→beam→joist→decking→guard) | none | VH | FULL | DCA6 |
| Footing & connection detail callouts | partial | H | FULL | |
| Site plan sheet (deck vs property lines/setbacks) | none | H | FULL | |
| **Multi-sheet permit plan set + compliant title block (export to city)** | none | VH | FULL | NCS title-block standard |
| **Engineering / structural calc report (engineer-reviewable)** | none | VH | FULL | RedX per-member output; DCA6 |
| **Engineer (PE) stamp / seal workflow** | none | H | FULL | prescriptive-envelope check + PDF signing |
| Full lumber + fastener + hardware + concrete schedule (BOM) | partial | H | FULL | |
| CAD interop export (vector PDF; DWG/DXF) | none | H | FULL | **DWG/DXF needs 3rd-party lib/server — cost TBD** |

---

## 3. As-built CURRENT → TARGET code audit (flagship FULL feature)

**Concept:** record an *existing* deck (AR/LiDAR + photos + manual input), evaluate it against code, and produce a CURRENT → TARGET remediation report — what fails and what's required to fix it. Reuses the **same code-rules engine** as design (build once, run in the audit direction).

**Market:** a genuine, unoccupied gap — no tool pairs as-built capture with automated deck code-checking (capture tools have no code brain; code tools take *drawings*; inspection software deliberately avoids code). Primary buyer is the **remediation/repair contractor** (~30M decks past service life; CPSC ~6,000 injuries/yr; NADRA: ~90% of collapses are *ledger* failures; "National Deck Safety Month" is a marketing hook). It opens buyers beyond new-build: repair contractors, inspectors (advisory only), real-estate, insurance.

**The intrinsic constraint that shapes the design:** the deadliest violations are *physically hidden* — ledger fasteners, lateral connectors, and footings are behind cladding or underground; the phone cannot see them. So the honest, defensible scope is:
- **Auto-check (visible geometry):** guard height + 30″-guard-required rule, baluster/opening 4″ spacing (photo-assisted near threshold), stair rise/run + uniformity, handrail height, deck height above grade, post spacing, footprint.
- **Ask the user (hidden but knowable):** joist size/spacing/species, beam config, fastener/connector type (guided photo-of-fastener), lateral hold-downs present?, flashing present?
- **Punt / flag-only (truly hidden):** footing depth/size → "not assessable — verify on site."

**Report UX (borrowed from inspection + code-check tools):** summary-first, tiered severity (Safety hazard → Marginal → Minor), each finding a row: `ITEM · SEVERITY · CURRENT (measured/entered) · TARGET (code value) · CODE §· FIX · CONFIDENCE · EVIDENCE(photo/3D)`. Hidden-data rows carry a `SOURCE: not assessable` tag so the report never implies the app saw something it can't.

**Liability:** never the words "safe" or "compliant"; no clean bill of health (the app can't verify ledger/footings). Frame as *"potential code concerns identified — verify with a licensed professional."* See §7.

---

## 4. New subsystems / engines (ranked by what they unlock)

1. **Framing data model** — *critical path.* First-class joist/beam/post/ledger/rim/blocking, serialized into `drawing_data`. **Nothing in structure, footings, outputs, fasteners, or roofs ships until this exists.** Build first.
2. **Auto-framing engine** — derives a default frame from outline + house edge + elevation. Delivers BOTH-tier value early; substrate every sizing engine edits.
3. **Code-table store (versioned, jurisdiction-aware)** — verbatim IRC/DCA6/NBC/BCBC tables, keyed by adopted edition. Shared by every sizing engine *and* the compliance engine. Foundational; build alongside #1. Never hand-type table cells into UI.
4. **Structural sizing + load engine** — joist span, beam/post back-solve, tributary load, cantilever. Consumes #1–#3.
5. **Footing engine** — sizes from per-post load + soil + frost. Downstream of #4.
6. **Code-compliance rules engine** — pass/fail per cited section + out-of-envelope detection → "requires engineer." Powers both design-time checks *and* the as-built audit (§3). Headline differentiator and biggest liability.
7. **Terrain/ground system** — grade-capture keystone + height-above-grade. Unlocks guard auto-flag, grade stairs, frost footings, drainage. Parallel to structure.
8. **House model + opening placement + elevation/section renderer** — floor datum, doors/windows + cutouts, orthographic drawing surfaces. Gates permit-set elevation/section sheets.
9. **Drafting / plan-set engine** — true-scale dimensioned drawing, viewports, title blocks, schedule tables, multi-sheet PDF + PE-stamp. Downstream of nearly everything; phase last.
10. **Roof / overhead modeler** — roof-plane geometry; reuses #4 (build the structural engine once).
11. **Material catalog + board-nesting optimizer + fastener engine** — brand-neutral catalog feeding a generalized vinyl-nesting engine + geometry-coupled fastener takeoff.

---

## 5. Phasing

Each phase is coherent and shippable. The spine: **model → auto-derive → size → validate → draw.**

- **Phase 1 — Foundation / carve-out (already specced).** Standalone app, shared `DeckKit`, capability-gated `drawing_data` schema + LIGHT↔FULL round-trip. Land the two no-new-engineering wins: **per-pattern waste factor** (fixes under-ordering) + **brand-neutral catalog model**. Ship **client proposal + upgraded render** for early standalone revenue while engineering is built.
- **Phase 2 — Framing foundation (BOTH).** Framing data model + species/load presets + auto-framing + real framing 3D render + rough framing BOM + textured ground + ground-type selection. *First "serious tool" moment; shared value, no compliance claim yet.*
- **Phase 3 — Structural engineering (FULL).** Code-table store + joist span + beam/post engine + **per-column load calc** + cantilever + manual member editor. *RedX parity.*
- **Phase 4 — Footings, terrain & connections (FULL).** Grade capture (first) + height-above-grade (30″ guard) + frost/soil + footing sizing + post-footing/uplift hardware + ledger + lateral-connection design + Simpson hardware + full BOM.
- **Phase 5 — House attachment & openings (FULL).** Floor-line datum + door/window placement + wall cutouts + cladding-driven ledger (brick/stone → freestanding fallback) + elevation view + door/window schedule + multi-story stairs-to-grade.
- **Phase 6 — Surface features, patterns & overhead (FULL).** Decking patterns + picture-frame + board-nesting optimizer + fastener/finish takeoff; railing breakdown/families; stair tread types + stringer count + landings/winders; fascia/skirting/built-ins; pergolas/covers (reuse Phase 3 engine); lighting/electrical.
- **Phase 7 — Compliance & permit outputs (FULL).** Code-compliance rules engine + **as-built CURRENT→TARGET audit** + structural calc report + drafting/plan-set engine + dimensioned plan + framing plan + elevations + cross-section + detail callouts + site plan + multi-sheet permit set (export to city) + **PE-stamp workflow** + CAD export. *Where "design → engineer → code-check → permit" is finally fulfilled.*

---

## 6. Architecture implications

- **`drawing_data` JSON is the single growth surface — and it's one blob.** `DeckDesign.drawingDataJSON` round-trips via `DeckDrawingData.toJSON()/fromJSON()`. Every subsystem grows *inside* this blob. **Make `DeckDesign.version` live** (memory flags it dead). Each schema bump must be **additive and backward-decodable**; an unknown/failed sub-block must **not** fail the whole-design decode (the crew-blackout + stale-overwrite incidents in memory prove the inbound merge path is fragile).
- **Capability-gated rendering, not capability-gated data.** LIGHT and FULL share the schema; LIGHT preserves blocks it can't render (never strips on save) — the §1 graceful-degradation mechanism.
- **Shared DeckKit module.** Phase 1 extracts geometry models + engines (`StairCalculator`, `VinylCutListEngine`, `ComponentEmitter`, `EstimateGeneratorService`, `SurfaceDetector`, sketch pipeline) + 3D builders + catalog model. Engines live in DeckKit; capability flags decide which surface in which tier.
- **New engines as pure, testable units.** Precedent: `StairCalculator` encodes IRC R311.7 as a pure function. Span/load/footing engines must be pure (inputs → result + limiting check + cited section), table-driven, unit-tested (heed the AutoSchedule date-brittleness lesson). Keeps heavy engineering offline-capable + verifiable.
- **3D complexity on mobile.** A real engineered frame is an order of magnitude more SceneKit nodes than today's props, on 3-year-old phones in sunlight. Mitigate with **layer toggles** (planking/joists/beams/posts/footings — the Chief Architect pattern), instanced geometry, LOD. Photoreal (Phase 6/7) likely needs a separate RealityKit/Metal path — defer it.
- **Offline-first must hold through the engines.** All sizing/compliance runs **on-device** (pure engines + bundled versioned code tables — no network). PDF via PDFKit/Core Graphics on-device. Exception: **DWG/DXF export** may need a 3rd-party lib or server converter — flag licensing/runtime cost before committing. Watch the Supabase free-tier 500MB ceiling as blobs grow (→ Pro, per the foundation spec).
- **Drafting pipeline is purpose-built.** `DeckShareRenderer.renderPDF` is a 2-page marketing artifact — keep it as the LIGHT deliverable; **do not** extend it into the permit path. The permit set needs its own viewport/scale/annotation/title-block engine.

---

## 7. Liability & compliance posture (recommended)

The highest-risk part of the product is any claim that a deck "meets code" or is "safe." Recommended guardrails (non-negotiable if we make compliance claims at all):

1. **Never assert "safe" or "compliant" unconditionally.** The defensible claim is *"prescriptive-compliant per AWC DCA-6"* for **in-envelope** decks only.
2. **Every structural/footing output surfaces its assumptions** — assumed load, species, soil, and **code edition**.
3. **Out-of-envelope conditions hard-stop** to "requires a licensed engineer" rather than emitting a number (e.g. >100 sq ft tributary, soil < 1500 psf / BCBC < 75 kPa, unusual/elevated geometry).
4. **All outputs labeled advisory** pending licensed-engineer / AHJ review; the **PE-stamp workflow** makes explicit the app never self-certifies.
5. **As-built audit** never outputs a clean pass; hidden elements are tagged "not assessable — verify on site" (§3).
6. **Code tables ingested verbatim, versioned, treated as data** — this research confirmed structure + key thresholds but did **not** transcribe span/footing/connection tables cell-by-cell.
7. **Jurisdiction-aware from day one** — IRC/DCA6 (US) vs NBC/BCBC Part 9 (Canada, kPa); frost depth + setbacks are AHJ/zoning-delegated; any bundled zip→frost/setback table is a convenience, surface "verify with your AHJ."

---

## 8. Scope exclusions & cost flags

- **EXCLUDE survey/contour (DWG/DXF) import → 3D terrain TIN** — desktop-CAD territory; not mobile-appropriate.
- **DWG/DXF export** carries unknown third-party library / server-converter cost — flag and price before committing (UIGraphicsPDFRenderer is raster; vector/CAD is a separate pipeline).
- **Photorealistic rendering** needs a separate RealityKit/Metal path — defer to late phases; don't over-invest while the document/data engines are the priority.
- **IRC Appendix H** (overhead-structure code) is paywalled and unverified in this research — don't ship roof-cover compliance claims against it without validating the actual text.

---

## 9. Open decisions for Jackson

1. **Compliance posture** (§7): make prescriptive code-compliance *claims* (with the guardrails) vs the more conservative "engineer-reviewable only — never assert compliance." Recommended: claims **with** guardrails — it's the RedX bar and the headline value — but it's a real legal call.
2. **Scope appetite:** confirm the full 7-phase vision (this is a large, multi-phase, largely-greenfield engineering build) vs trimming the tail (e.g. defer overhead/lighting/CAD).
3. **The EXCLUDEs in §8** — confirm or override.
4. **As-built audit priority:** it's slotted in Phase 7 (needs the code engine), but it's also the most differentiated single feature — option to pull a *visible-geometry-only* version earlier as a standalone hook.
