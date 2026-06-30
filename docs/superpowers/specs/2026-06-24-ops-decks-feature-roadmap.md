# OPS Decks — Full Power-User Feature Roadmap

**Date:** 2026-06-24
**Status:** Draft for Jackson's review (functionality roadmap; companion to the Phase 1 foundation spec)
**Companion:** `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md` (Phase 1 foundation/carve-out)
**Grounded in:** direct code inspection of 73 files under `OPS/DeckBuilder/` + `OPS/DataModels/DeckDesign.swift`; official competitor/support documentation for Trex Deck Designer, Decks.com Deck Designer, and Simpson Strong-Tie Deck Planner; building-code/source review against IRC R507/R311.7/R312 and AWC DCA6; plus the as-built code-audit study. Forum/review mining is not assumed complete until a dedicated corpus is captured.

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
- Address-aware parcel/zoning precheck, setbacks/site plan, the multi-sheet **permit plan set**, the **structural calc report**, the **engineer (PE) stamp workflow**, and CAD interop.
- Advanced stairs (tread types, stringer count, landings, winders), lighting/electrical, built-ins.
- The **as-built CURRENT → TARGET code audit** (§3).

**Graceful degradation (architectural):** FULL designs round-trip through LIGHT via the same `drawing_data` JSON. A LIGHT install opening a fully-engineered design renders the geometry it understands and **preserves (never strips)** the framing/terrain/permit blocks it can't render. One schema, capability-gated rendering.

---

## 1.1 Competitive pain points OPS Decks must beat

Official competitor/support docs surface a clear product gap: existing deck planners can produce attractive 3D views, material lists, and permit-style plans, but they are mostly desktop/laptop workflows and they expose too many structural decisions as hidden defaults, support articles, or late errors.

**Non-negotiable responses:**
- **Field-native first.** The core draw/measure/edit flow must work on iPhone and iPad in a backyard, offline, in sunlight, with voice dimensions and large touch targets. Mac is the engineering/document desk surface, not the only place the product works.
- **No hidden joist-direction hacks.** Joist/decking direction is an explicit control with visible arrows, snap handles, and framing consequences. The user must never have to move the deck away from the house to trick the engine into changing joist direction.
- **Framing is editable, not a black box.** Joist size, beam size, beam role, post spacing, rim/band joists, blocking, hangers, and hardware are inspectable and editable where the tier permits. If a value is locked by LIGHT/default assumptions, the UI says so.
- **Railing is a real object.** Guard runs can be added, removed, split, copied, assigned by edge, and configured independently for deck runs and stair runs. Railing removal must not be a height workaround.
- **Errors explain themselves at the geometry.** Permit/export failures, code findings, and calculation conflicts appear live on the offending member or feature, with the reason, assumption, and next action. Do not wait until PDF generation to reveal a red-mark failure.
- **Brand-neutral by default.** Material, railing, fastener, and hardware catalogs use brand-neutral profiles first, with manufacturer/SKU overlays second. This prevents the app from feeling like a supplier-owned configurator.
- **Permit outputs stay honest.** Existing tools lean on disclaimers because local AHJ rules, site conditions, and hidden work vary. OPS keeps that honesty but moves useful checks inline: objective negative findings, code-package edition, assumptions, and not-assessable states.
- **Address-aware zoning becomes a sales weapon.** A contractor who can stand in the yard, enter the site address, show parcel/setback/coverage constraints, and export a city-ready site sheet is doing preconstruction work competitors still leave to office staff or the AHJ counter.

## 2. Feature roadmap by domain

Complexity: **L** low · **M** medium · **H** high · **VH** very-high. Tier: **LIGHT** / **FULL** / **BOTH** (shared, degrades into LIGHT).

### 2.0 Field-first drawing flow & learning curve

The drawing flow must feel like marking up a jobsite sketch, not operating CAD. Default path:
1. **Start method:** blank rectangle, common template, photo/sketch scan, AR perimeter/height measure, or duplicate an existing deck.
2. **House anchor:** mark the house wall/ledger edge first, set floor datum/door threshold if known, then draw outward from that reference.
3. **Draw perimeter:** tap corners or drag edges; dimensions can be typed, spoken, or captured from AR. Snaps cover square, parallel, perpendicular, 45-degree, equal length, midpoint, offset, and align-to-house.
4. **Constrain dimensions:** lock key dimensions, enter diagonals for squareness, show unresolved or over-constrained geometry immediately, and allow partial/incomplete shapes to save.
5. **Assign edges/features:** tap an edge to assign railing, stairs, gate, house/ledger, fascia, beam role, or no-guard condition. Multi-select lets crews assign the same railing/material to multiple runs.
6. **Preview consequences:** the app shows live surface area, perimeter, height above grade, rough material impact, stair count impact, and where FULL will evaluate code findings.
7. **Progressive disclosure:** first-time users see one next action at a time; power users get keyboard/Pencil shortcuts, persistent inspectors, and batch edit on iPad/Mac.

Drawing failure states are first-class: impossible geometry, missing house edge, unsupported curve, unresolved dimension, conflicting locked members, not-enough-data-for-code, and export-blocking geometry. Each state must point to the exact edge/member that needs attention.

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

**Framing Mode / Structural Mode workflow.** The app needs a first-class mode, not a hidden auto-generated layer:
1. User draws or imports the deck surface geometry first: perimeter, levels, stairs/landings, height above grade, and deck-surface material direction.
2. User marks each boundary edge as **house/ledger**, flush beam, drop beam, cantilever/free edge, or freestanding edge. House edges require the wall object and cladding context from §2.4.
3. User selects framing assumptions: joist direction, joist spacing, default member family, species/grade, pressure-treatment class, live/dead/snow load preset, deflection preset, and jurisdiction/code package when FULL checks are enabled.
4. The auto-framing engine derives joists, beams, posts, ledgers, rim/band joists, blocking/bridging, hangers, footings, and default hardware from the surface outline.
5. User manually edits the generated frame: select, move, split, resize, duplicate, delete, lock, unlock, and exclude from auto-regeneration. Locked members remain fixed when the outline changes unless the edit becomes geometrically impossible.
6. Recompute runs after every geometry or assumption change. LIGHT updates the visual frame and rough BOM only. FULL updates sizing, span/load checks, code overlay findings, calc report data, and permit-plan callouts.

**Member inspector contract.** Every structural member carries source (`auto` / `manual` / `imported`), lock state, phase/tier availability, linked geometry, and BOM impact. Editing a field must state whether it changes geometry, calculation assumptions, material takeoff, hardware takeoff, or code findings.

| Member / feature | Inspector fields and behavior |
|---|---|
| **Joist** | nominal + actual size, species/grade, spacing, direction, start/end bearing, span segment(s), cantilever length, tributary width/area, applied load, blocking requirement, hanger/fastener, material SKU/length, cut count, waste source. FULL shows current span vs max span and assumptions. |
| **Beam** | built-up ply count, nominal + actual size, species/grade or steel profile, dropped/flush role, supported joist spans, post spacing, bearing length, splice locations, reactions, connectors, material/SKU/lengths. |
| **Post / column** | material/profile, nominal + actual size, height, base/top connection, tributary area/load, supported beam(s), footing link, guard/roof load participation, hardware, cut length. |
| **Ledger** | house wall link, cladding/WRB condition, ledger size, attachment strategy, flashing, fastener pattern, lateral-load connection, blocked/isolated spans, freestanding fallback state. |
| **Rim joist / band joist** | structural role, ply count, nominal + actual size, species/grade, edge links, guard-post attachment context, blocking, hold-downs/hardware, splice rules, BOM line. This is distinct from cosmetic fascia. |
| **Blocking / bridging** | type, bay range, spacing, purpose (edge support, picture-frame, diagonal decking, guard-post blocking, joist stability), material, fastener/hanger impact. |
| **Hangers / connectors / hardware** | family, size, load direction, fastener schedule, corrosion class, linked members, included/excluded from BOM. Brand-specific SKUs are optional overlays on brand-neutral profiles. |
| **Cantilevers and span segments** | measured segment, backspan relationship, controlling member, out-of-envelope state, redraw/resize handle, code finding link. |

**LIGHT vs FULL boundary for framing.** LIGHT may visualize a plausible frame, price a rough substructure BOM, and label assumptions as visual/default only. LIGHT must not assert member adequacy, allowable spans, footing adequacy, code status, permit readiness, or inspection outcome. FULL owns those checks and still uses objective-negative language only.

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
| Overhead 3D render + roof covering + estimate | partial | H | BOTH | extends `ComponentEmitter` |
| Overhead roof/load code findings | none | VH | FULL | routes loads into Phase 3/4 structural engines |

**Roof / pergola / patio-cover config fields.** Overhead structures are modeled as real load paths, not decoration. Fields: type (pergola, louvered roof, shed roof, gable, hip, patio cover), attachment mode (house ledger, wall brackets, freestanding), roof plane geometry, slope/pitch, overhangs, post grid, beams, rafters, purlins, roof covering, ceiling/soffit if present, snow/live/dead/wind uplift assumptions, drainage direction, gutters/downspouts when included, flashing assumptions, and connection hardware. FULL checks must route roof loads into posts/footings/ledger and flag unsupported attachment, out-of-envelope load paths, drainage conflicts, and unverified Appendix H / AHJ conditions without claiming approval.

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

**House wall and opening config.** A house wall is a coordinate surface with a floor datum, exterior grade datum, wall height/story height, wall thickness reference, cladding type, WRB/flashing note, and ledger/attachment strategy. Doors and windows are placed in that wall coordinate system, not as loose annotations.

| Opening / wall object | Required fields |
|---|---|
| **Wall / floor datum** | wall segment, origin, floor elevation, story height, wall height, cladding, sheathing/WRB note, ledger-allowed state, freestanding fallback flag. |
| **Door family** | patio slider, French, hinged, multi-slide, garage/service where needed; rough opening, actual size, sill height, head height, swing/operation type, threshold/drop condition, wall coordinate, trim/casing clearance, cutout geometry, schedule mark. |
| **Window family** | fixed, slider, casement, awning, double-hung; rough opening, actual size, sill height, head height, operation type, wall coordinate, egress note if user-supplied, cutout geometry, schedule mark. |
| **Schedules / callouts** | wall elevation labels, opening tags, size schedule, cutout dimensions, ledger conflict notes, flashing/attachment assumptions. |

### 2.5 Site, terrain & ground
| Feature | Today | Cplx | Tier | Code / dep |
|---|---|---|---|---|
| Per-zone ground-type / surface-cover selection (grass/dirt/gravel/rock/concrete/pavers) | none | M | BOTH | `BuiltInMaterial` |
| Textured 3D ground render (replace flat tint) | partial | M | BOTH | `DeckMeshGenerator` |
| **Yard grade/slope capture (keystone)** | none | H | FULL | AR height measure → terrain |
| Height-above-grade engine (post heights + 30″ guard auto-flag) | partial | H | FULL | IRC R312.1.1/.1.2 |
| Grade-driven stair total-rise & step count | partial | M | FULL | `StairCalculator`; IRC R311.7 |
| Footing depth from frost line (zip/AHJ-driven) | partial | M | FULL | IRC R403.1.4 |
| Address → parcel resolver | none | H | FULL | geocode + parcel/APN lookup; confidence scored |
| Parcel/property-line site overlay | none | H | FULL | official GIS parcel layer or user-imported survey |
| Zoning district + overlay lookup | none | VH | FULL | official GIS/open data where available; manual fallback |
| Setback / coverage / height precheck | none | VH | FULL | local zoning; objective-negative only |
| Easement / flood / wildfire / coastal / historic overlay flags | none | VH | FULL | source-dependent; advisory/not-assessable states |
| Drainage / grade-fall check (R401.3) | none | M | FULL | 6″ in 10′; 2% impervious |
| Multi-level grade & retaining walls | partial | VH | FULL | IRC R404/R403 |
| Survey/contour import (DWG/DXF) → terrain TIN | none | VH | FULL | **recommend EXCLUDE** — desktop-CAD territory |

**Under-deck / substrate fields.** Site data must include what is under the deck because it affects renderings, drainage notes, access, skirting takeoff, and some permit drawings. Fields: substrate type (soil, concrete, gravel, pavers, grass), slope/fall direction, drainage path, waterproofing or under-deck ceiling, skirting/lattice/enclosure, access panels, minimum clearance, crawl/access zone, obstructions (meters, vents, hose bibbs, AC units, wells, trees), and notes for non-assessable hidden conditions.

**Address-aware zoning precheck.** This is a FULL-tier pre-permit subsystem, not a promise of zoning approval. The user enters a site address or drops a pin; the app geocodes it, resolves the parcel/APN where available, pulls parcel geometry, zoning district, overlay layers, and jurisdiction/AHJ metadata, then checks the proposed deck footprint against the zoning data it can verify.

| Zoning object | Required fields and behavior |
|---|---|
| **Site address** | normalized address, geocode provider, match precision (`rooftop` / parcel / interpolated / approximate), confidence, user-confirmed pin, privacy/export consent. |
| **Parcel** | APN/PID/folio, owner-visible label when allowed, parcel polygon, property-line dimensions, lot area, source URL, source date, data license, confidence, manual survey/import override. |
| **Jurisdiction / AHJ** | city/county/province/state, permit office, code/zoning package version, official portal URL, contact/inspection notes where available. |
| **Zoning district** | district code, district name, allowed/accessory-use notes, source citation, source date, linked ordinance section or map layer. |
| **Zoning constraints** | front/side/rear/flanking setbacks, lot coverage, impervious coverage, structure height, accessory-structure/deck-specific rules, encroachment allowances, stairs/landing projections, corner-lot rules, easements, overlays, and source/confidence per field. |
| **Manual fallback** | user-entered setback/coverage/height criteria with explicit source label (`user supplied`, `planner email`, `survey`, `permit handout`) and `verify with AHJ` status. |

**Zoning finding model.** Findings attach to the deck footprint, stair footprint, landing, roof/cover projection, railing/guard projection when relevant, or parcel/site layer. Severity states mirror the code overlay: `violation`, `warning`, `out-of-envelope`, `unknown`, and `not-assessable`. Examples: `REAR SETBACK CONCERN`, `LOT COVERAGE OVER LIMIT`, `PARCEL SOURCE UNVERIFIED`, `OVERLAY REVIEW REQUIRED`, `EASEMENT CONFLICT`, `AHJ CONFIRMATION REQUIRED`.

**Zoning site-plan export.** The permit package must include a site/zoning sheet when parcel data is present: north arrow, scale, parcel boundary, proposed deck footprint, stair/landing/roof projections, property-line offsets, setback envelope, lot/impervious coverage table, zoning district, overlay list, source citations, source date, confidence notes, and AHJ verification advisory. If parcel data is unavailable, the export includes a manual site-plan checklist instead of silently omitting zoning.

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

**Railing / guard configuration.** A guard run is a parametric system with separate deck-run and stair-run settings. Required fields: guard-required basis from height above grade, mount type (**top mount** / surface mount / fascia mount / side mount), guard height, post spacing, post material/profile, sleeves, caps, top rail profile, bottom rail, infill type, color/finish, brand-neutral product profile, gates, corner behavior, stair transition behavior, and hardware/fastener takeoff. Code checks cover guard-required status, guard height, opening behavior including 4-inch sphere logic where applicable, stair guard/handrail separation, graspable handrail profile when required, and the rule that benches/privacy walls do not count as guards unless explicitly modeled to qualify.

**Glass guard families.** Include framed glass, semi-frameless glass, and frameless glass. Fields: panel width limits, panel height, glass tint/frost/privacy option, clamp/spigot/shoe system, post/no-post mode, corner conditions, gate compatibility, edge clearance, breakage/replacement note, and fastener/hardware takeoff.

**Cable guard families.** Include horizontal cable and vertical cable. Fields: post material, cable orientation, cable spacing/opening check inputs, terminal/tension hardware, intermediate post behavior, corner/tension run breaks, stair angle transitions, and maintenance/tension note. FULL flags openings or geometry that cannot be assessed from the model.

**Picket / baluster families.** Include aluminum, wood, composite, and PVC. Fields: picket/baluster size, spacing, pattern, rail family, stair rake behavior, corner behavior, gate compatibility, finish, and fastener takeoff.

**Stair / stringer configuration.** Stairs need construction fields separate from the current basic run:
- Construction type: open stringers, closed/housed stringers, mono/steel stringer, dual steel stringers, boxed/platform stairs, and multi-flight with landings where appropriate.
- Stringer material: PT wood, LVL/engineered where allowed, steel; count, spacing, sizing, bearing/support, hanger/connection hardware, intermediate supports, bottom landing connection.
- Tread types: composite/PVC deck boards, PT wood, cedar, **2x6**, **5/4** decking, stair-specific boards, metal grating where appropriate; tread board count per step, nosing, overhang, riser board material, open vs closed riser, slip/finish note.
- Rail/handrail: stair guard mount type, stair-run mount separate from deck-run mount, handrail profile, returns, post locations, transition to deck guard.
- Code overlay checks: rise, run, uniformity, nosing, open riser/opening, landing size, headroom, handrail requirement, handrail height/profile, guard requirement, and stair guard opening behavior.

**Rim/band joist vs fascia.** These are separate systems. The structural rim joist / band joist belongs to the framing model and carries ply count, nominal/actual size, species/grade, structural role, guard-post attachment context, blocking/hardware, splice rules, and code findings. Cosmetic fascia is an independent finish with material, profile, thickness, height, color/finish, SKU, reveal/drop, miter/return rules, fastener pattern, joints, and replacement/takeoff behavior. A fascia board must never be treated as structural unless the user explicitly models a qualifying structural member behind it.

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

**Fastener, connector, and manufacturer-approval fields.** Material and hardware profiles must carry corrosion environment, coastal/salt exposure flag, preservative-treatment compatibility, coating class/material family, allowed substrate/member types, manufacturer installation constraints, evaluation-report/reference link where available, and AHJ/engineer-required state. Glass, cable, composite, PVC, steel stringer, and proprietary railing systems inherit these constraints so the BOM, code overlay, and permit notes do not treat manufacturer-specific limits as generic material choices.

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
| **Multi-sheet permit plan set + jurisdiction-ready title block (export to city)** | none | VH | FULL | NCS title-block standard |
| **Engineering / structural calc report (engineer-reviewable)** | none | VH | FULL | RedX per-member output; DCA6 |
| **Engineer (PE) stamp / seal workflow** | none | H | FULL | prescriptive-envelope check + PDF signing |
| Full lumber + fastener + hardware + concrete schedule (BOM) | partial | H | FULL | |
| CAD interop export (vector PDF; DWG/DXF) | none | H | FULL | **DWG/DXF needs 3rd-party lib/server — price before commitment** |

**Rendering engine split.** SceneKit remains the engineering/model viewport: fast, editable, layer-toggled, and suitable for 2D/3D coordination, framing visibility, dimensions, sections, and code overlays. Realistic/client renderings need a separate RealityKit/Metal/PBR-capable render path or an equivalent renderer that supports material fidelity beyond SceneKit's current non-PBR model.

**Client render requirements.** Renders must support realistic decking grain/color, fascia and rim-board visibility, glass transparency/refraction approximation, cable density, picket/baluster density, shadows, ambient occlusion where available, sun orientation by compass/time preset, camera presets (client hero, plan oblique, stair detail, railing detail, under-deck view), layer visibility, background/ground material, and export sizes for phone share, proposal PDF, App Store screenshot, and high-resolution client image. If an early phase only produces non-photoreal renders, label it as "model render" or "concept render" and do not present it as photoreal.

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
3. **Code-rule packages (downloadable, versioned, jurisdiction-keyed)** — verbatim IRC/DCA6/NBC/BCBC tables + rules as *data packages*, keyed by jurisdiction (country/province/state) + adopted edition, **stored in Supabase and delivered via ops-web**, downloaded for the user's selected jurisdiction and cached offline. Updatable on code revision **without an App Store release**; the app shows "code data current to [edition/date]." Shared by every sizing engine, the compliance engine, *and* the as-built audit. Foundational; build the package format + loader alongside #1. Never hand-type table cells into UI.
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
- **Phase 3 — Structural engineering (FULL).** Code-rule packages (jurisdiction-keyed, Supabase-delivered, offline-cached) + jurisdiction selection UI + joist span + beam/post engine + **per-column load calc** + cantilever + manual member editor. *RedX parity.*
- **Phase 4 — Footings, terrain & connections (FULL).** Grade capture (first) + height-above-grade (30″ guard) + frost/soil + footing sizing + post-footing/uplift hardware + ledger + lateral-connection design + Simpson hardware + full BOM.
- **Phase 5 — House attachment & openings (FULL).** Floor-line datum + door/window placement + wall cutouts + cladding-driven ledger (brick/stone → freestanding fallback) + elevation view + door/window schedule + multi-story stairs-to-grade.
- **Phase 6 — Surface features, patterns & overhead (FULL).** Decking patterns + picture-frame + board-nesting optimizer + fastener/finish takeoff; railing breakdown/families; stair tread types + stringer count + landings/winders; fascia/skirting/built-ins; pergolas/covers (reuse Phase 3 engine); lighting/electrical.
- **Phase 7 — Compliance & permit outputs (FULL).** Code-compliance rules engine + **as-built CURRENT→TARGET audit** + structural calc report + drafting/plan-set engine + dimensioned plan + framing plan + elevations + cross-section + detail callouts + site plan + multi-sheet permit set (export to city) + **PE-stamp workflow** + CAD export. *Where "design → engineer → code-check → permit" is finally fulfilled.*

---

## 6. Architecture implications

- **Platforms — iPhone/iPad/Mac now, Android later (locked 2026-06-24).** Targets all three Apple platforms from one shared `DeckKit` + adaptive SwiftUI, designed for all three now, shipped iPhone → iPad → Mac. **AR is iPhone/iPadOS-only** (no ARKit on Mac → manual/import fallback; guard with `#if os(iOS)`); SceneKit/SwiftUI/SwiftData/PDFKit are cross-Apple; Apple Pencil is first-class on iPad. Workflow split: iPhone = field capture, iPad = design (Pencil), Mac = desk/engineering/permits. A future **Android** build is a Kotlin/Compose + ARCore + Android-3D port — we deliberately do **not** build a cross-platform engine core now (it would discard the existing-Swift reuse advantage); the pure engines + data-driven code packages keep that port cheap (re-implement engine logic in Kotlin, reuse the packages as-is).
- **`drawing_data` JSON is the single growth surface — and it's one blob.** `DeckDesign.drawingDataJSON` round-trips via `DeckDrawingData.toJSON()/fromJSON()`. Every subsystem grows *inside* this blob. **Make `DeckDesign.version` live** (memory flags it dead). Each schema bump must be **additive and backward-decodable**; an unknown/failed sub-block must **not** fail the whole-design decode (the crew-blackout + stale-overwrite incidents in memory prove the inbound merge path is fragile).
- **Capability-gated rendering, not capability-gated data.** LIGHT and FULL share the schema; LIGHT preserves blocks it can't render (never strips on save) — the §1 graceful-degradation mechanism.
- **Shared DeckKit module.** Phase 1 extracts geometry models + engines (`StairCalculator`, `VinylCutListEngine`, `ComponentEmitter`, `EstimateGeneratorService`, `SurfaceDetector`, sketch pipeline) + 3D builders + catalog model. Engines live in DeckKit; capability flags decide which surface in which tier.
- **New engines as pure, testable units.** Precedent: `StairCalculator` encodes IRC R311.7 as a pure function. Span/load/footing engines must be pure (inputs → result + limiting check + cited section), table-driven, unit-tested (heed the AutoSchedule date-brittleness lesson). Keeps heavy engineering offline-capable + verifiable.
- **3D complexity on mobile.** A real engineered frame is an order of magnitude more SceneKit nodes than today's props, on 3-year-old phones in sunlight. Mitigate with **layer toggles** (planking/joists/beams/posts/footings — the Chief Architect pattern), instanced geometry, LOD. Photoreal (Phase 6/7) likely needs a separate RealityKit/Metal path — defer it.
- **Offline-first must hold through the engines.** All sizing/compliance runs **on-device** (pure engines + bundled versioned code tables — no network). PDF via PDFKit/Core Graphics on-device. Exception: **DWG/DXF export** may need a 3rd-party lib or server converter — flag licensing/runtime cost before committing. Watch the Supabase free-tier 500MB ceiling as blobs grow (→ Pro, per the foundation spec).
- **Drafting pipeline is purpose-built.** `DeckShareRenderer.renderPDF` is a 2-page marketing artifact — keep it as the LIGHT deliverable; **do not** extend it into the permit path. The permit set needs its own viewport/scale/annotation/title-block engine.

---

## 7. Liability & compliance posture (LOCKED 2026-06-24)

The highest-risk part of the product is any claim that a deck "meets code" or is "safe." **Decision (Jackson): the app makes only _objective negative_ claims, never positive guarantees.** Code failures are objective and safe to assert; "this deck is safe / will pass" is not. The locked guardrails:

1. **Objective negative claims only.** The app flags what *objectively fails* the selected jurisdiction's code, and reports **"no code failures detected"** when it finds none in assessable items. It never says "safe," "compliant," "guaranteed," or "will pass."
2. **Disclaimer on every compliance/structural output.** "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction." Acknowledged in-app before a compliance report or permit set generates.
3. **Jurisdiction selection drives the ruleset.** The user picks country + province/state (e.g. BC, AB, US-IRC states); the compliance + sizing engines evaluate *that jurisdiction's* package. IRC/DCA6 (US) vs NBC/BCBC Part 9 (Canada, kPa); frost depth + setbacks are AHJ/zoning-delegated — any bundled zip→frost/setback table is a convenience, surfaced as "verify with your AHJ."
4. **Downloadable, versioned code-rule packages (see engine #3).** Code rules are *data*, stored in Supabase and delivered via ops-web, downloaded per selected jurisdiction and cached for offline use. This lets us push code-revision updates **without an App Store release**, and stamp every report **"code data current to [edition/date]."**
5. **Out-of-envelope conditions hard-stop** to "requires a licensed engineer" rather than emitting a number (e.g. > tributary/area limits, soil < 1500 psf / BCBC < 75 kPa, unusual/elevated geometry). The **PE-stamp workflow** makes explicit the app never self-certifies.
6. **Every structural/footing output surfaces its assumptions** — assumed load, species, soil, and the **code package edition** in force.
7. **As-built audit** never outputs a clean pass; hidden elements are tagged "not assessable — verify on site" (§3).
8. **Code tables ingested verbatim, versioned, treated as data** — this research confirmed structure + key thresholds but did **not** transcribe span/footing/connection tables cell-by-cell; each package is built from the adopted edition's actual tables.

### 7.1 Live inline code overlay

Code checking is live while the user draws or edits whenever FULL code checks are enabled. It is toggleable in settings and per-document view controls, but the default FULL workflow surfaces objective negative findings directly on the offending geometry, not only in a report.

**Finding model:** every finding attaches to a specific element or feature (`joist`, `beam`, `post`, `ledger`, `rim joist`, `guard run`, `stair flight`, `opening`, `roof`, `footing`, `site condition`) and carries severity: `violation`, `warning`, `out-of-envelope`, `unknown`, or `not-assessable`. Each finding stores current value, target/limit where applicable, rule/table citation, code package edition, assumptions, source confidence, and recommended next action. Unknown and not-assessable states are first-class outcomes, not hidden errors.

**Tokenized geometry styling:** overlays use design-system tokens directly on geometry: stroke, fill, halo, hatch, badge, and inspector state all derive from severity tokens. A selected member shows the same finding state in the inspector, roll-up list, plan view, 3D view, and report. Reduced-motion mode suppresses animated pulses but keeps the tokenized visual state.

**Example:** if a joist exceeds the selected jurisdiction's span table, the joist receives a styled token along the full offending span. The inline badge reads in the objective-negative form: `SPAN OVER TABLE :: 12'-4" current / 10'-11" max`, then exposes the rule/table citation, code package edition, species/grade/load assumptions, bearing condition, and the affected BOM/member sizing implications. It must never say the rest of the deck is safe, compliant, approved, guaranteed, or will pass inspection.

---

## 8. Scope exclusions & cost flags

- **EXCLUDE survey/contour (DWG/DXF) import → 3D terrain TIN** — desktop-CAD territory; not mobile-appropriate.
- **DWG/DXF export** carries unknown third-party library / server-converter cost — flag and price before committing (UIGraphicsPDFRenderer is raster; vector/CAD is a separate pipeline).
- **Photorealistic rendering** needs a separate RealityKit/Metal path — defer to late phases; don't over-invest while the document/data engines are the priority.
- **IRC Appendix H** (overhead-structure code) is paywalled and unverified in this research — don't ship roof-cover compliance claims against it without validating the actual text.

---

## 9. Decisions (resolved 2026-06-24, Jackson)

1. **Compliance posture — RESOLVED:** objective negative claims only ("no code failures detected," never "safe/guaranteed"), jurisdiction-selectable, with downloadable versioned code packages + disclaimer + licensed-engineer recommendation. See §7.
2. **Scope — RESOLVED:** plan the **full 7-phase vision in detail now** (single comprehensive implementation plan), not a trimmed core. The EXCLUDEs in §8 stand (survey/contour import out; DWG/DXF export cost-flagged; photoreal deferred late).
3. **As-built audit — RESOLVED:** lands in **Phase 7** with the full code engine (reuses it; cheapest + most correct).
