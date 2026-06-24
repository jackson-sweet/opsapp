# OPS Decks — Claude Design Surface Brief

**Date:** 2026-06-24
**Purpose:** Tell Claude Design **what surfaces to design** for the standalone OPS Decks app — screens, states, flows, and platform adaptation. The OPS design system (military tactical minimalist; Mohave / JetBrains Mono / Cake Mono; monochrome + steel-blue accent; glass + hairlines; one easing curve) is already loaded — this brief does **not** restate visual tokens. Design the *what*; apply the system for the *how*.
**Companions:** feature roadmap (`2026-06-24-ops-decks-feature-roadmap.md`), foundation spec, 7-phase plan.

---

## 0. Product in one line

A power-user deck-design app for contractors: **draw a deck → see it in 3D → assign any material → get a priced estimate, cut list, and engineered/code-checked permit set** — on iPhone, iPad, and Mac, offline-capable. Plus an **as-built mode**: scan an existing deck, get a "what fails code" report.

## 1. Platform model (design adaptive for all three)

| Platform | Primary job | Navigation shell |
|---|---|---|
| **iPhone** | Field capture — AR measure, photos, quick edits | Bottom tab bar; full-screen canvas; sheets for config |
| **iPad** | Design — the drawing canvas with **Apple Pencil**; client-facing 3D | Sidebar (collapsible) + canvas + a floating/edge inspector |
| **Mac** | Desk/office — structural editor, permit plan sets, calc reports, as-built review | Three-pane: source-list sidebar · canvas/document · inspector panel |

Design each surface so it **reflows** across these — phone = one thing at a time (sheets/tabs); iPad/Mac = multi-pane with a persistent inspector. Note where a surface is **primarily** a Mac/iPad surface (the document/engineering ones) vs iPhone (capture).

**Canvas / 3D / AR are NATIVE — do not design them here.** Design the *chrome around* them (toolbars, inspectors, pickers, panels, overlays, badges). The drawing surface, 3D viewport, and AR camera view are placeholders in the prototype.

## 2. Voice & numbers (applies to every surface)

- Terse, tactical, sentence case for content / UPPERCASE for authority. No emoji, no exclamation. (Final copy comes from `ops-copywriter` — use plausible placeholder copy in that register.)
- All numbers monospaced, tabular, formatted (`9′-2″`, `$4,250`, `40 psf`). Empty = `—`.
- **Compliance language is objective-negative only:** "No code failures detected," "3 code concerns found," never "safe" / "compliant" / "guaranteed." Every compliance/structural output carries a one-line advisory ("Not a guarantee — have plans reviewed by a licensed engineer in your jurisdiction").
- Every surface needs its **empty / loading / populated / error** states designed, plus **free vs Pro** where gating applies.

---

## 3. Surfaces to design

Each entry: **purpose · key contents · states · platform notes · priority**. Priority tiers: **P0** (prototype first — onboarding/library/paywall/designer chrome/core docs), **P1** (engineering surfaces), **P2** (compliance/as-built/permit depth).

### A. Onboarding & account

**A1 · Welcome / first-run** — Purpose: get to drawing in seconds. Contents: one-line value prop, "Start a deck" primary, subtle "I have an account." States: first-run vs returning. Platform: full-bleed phone; centered card iPad/Mac. **P0**

**A2 · Design-first, no-account** — Purpose: let them draw immediately with zero signup. Contents: the designer opens directly; a persistent unobtrusive "Sign in to save" affordance. States: anonymous working session. **P0**

**A3 · Sign in with Apple (at save / paywall)** — Purpose: minimal-friction account only when saving. Contents: Apple sign-in button, one-line why ("to save and sync your deck"), nothing else. States: signing in / error / success. **P0**

**A4 · Jurisdiction setup** — Purpose: pick country + province/state so code rules apply. Contents: searchable jurisdiction list, the code-package for it (edition + "current to [date]"), download state. States: not-selected / downloading / ready / update-available / offline. Platform: sheet on phone, inline panel on iPad/Mac. **P1** (can be deferred to first compliance use)

### B. Deck library / home

**B1 · Deck library** — Purpose: see, open, create decks. Contents: deck cards (thumbnail, name, last-edited, status chip), "New deck" primary, search/sort. States: empty (first deck) / 1 deck (free) / locked-create (free + at cap) / many (Pro). Platform: grid on iPad/Mac, list/grid on phone; sidebar source-list on Mac. **P0**

**B2 · New-deck entry** — Purpose: start a deck. Contents: choose start method — blank, template, photo/sketch scan, AR measure. States: method picker. Platform: sheet (phone) / inline (iPad/Mac). **P0**

**B3 · Deck card context actions** — rename, duplicate, delete, export, share. Contents: row/long-press menu. **P0**

### C. Monetization

**C1 · Paywall (free → Pro)** — Purpose: convert at the 1-deck cap or on a Pro-only action. Contents: what Pro unlocks (unlimited decks + the power features), monthly vs annual, restore purchases, "maybe later." States: triggered-by-cap vs triggered-by-feature; purchasing / error / success. **P0**

**C2 · Upgrade to full OPS** — Purpose: the wedge upsell. Contents: "OPS Decks is the design layer of OPS — get crew, scheduling, invoicing," what carries over (your account + decks), the credit-for-remaining-time note, CTA to OPS. States: standard. Platform: full-screen story (phone) / panel (Mac). **P1**

### D. Designer workspace chrome (around the native canvas)

**D1 · Toolbar** — drawing tools (draw/edit/measure/dimension/voice), undo/redo, level switcher, view switch (2D ⇄ 3D), share/export. Platform: bottom bar (phone), top/side bar (iPad/Mac). **P0**

**D2 · Assignment wheel / material+feature selector** — radial or palette to tag edges/surfaces (material, railing, stairs, gate, house edge). States: open / item-selected. **P0**

**D3 · Property / inspector panel** — context properties for the selected element (edge type, dimension, elevation, footing, railing config). Platform: sheet (phone) / persistent inspector (iPad/Mac). **P0**

**D4 · Level tabs + level-connection** — multi-level deck switcher; connect levels (stairs/step-down). **P1**

**D5 · 3D view controls** — camera presets, **layer toggles** (decking / joists / beams / posts / footings / railings), share-render button. (Viewport is native; design the controls + the toggle panel + on-model badges.) **P1**

**D6 · Dimension / elevation / voice input** — numeric entry for a dimension or height; voice-dimension affordance + waveform. States: entering / confirmed. **P1**

### E. Materials

**E1 · Material catalog** — browse/select material families (PT, cedar, composite/PVC boards by brand, vinyl membrane, aluminum), profiles, lengths, finish. Contents: family → product → detail; brand-neutral. States: built-in vs user-added. **P0**

**E2 · Material editor (Pro)** — add/edit a material: price, vendor/SKU, per-length pricing, coverage, fastener system. States: new / edit / validation. Platform: form sheet (phone) / inspector (Mac). **P1**

**E3 · Decking pattern picker** — parallel / diagonal / picture-frame / herringbone / chevron, board direction, border. **P2**

### F. Structural / framing surfaces

**F1 · Framing inspector** — for a selected member (joist/beam/post/ledger): size, species/grade, spacing, ply, the computed span/load result, and any code flag. Contents: readouts + editable fields (manual override). States: auto-derived / user-locked / out-of-envelope ("requires a licensed engineer"). **P1**

**F2 · Load & assumptions panel** — per-post/column load readout; the assumed load/species/soil + code edition surfaced. **P1**

**F3 · Inline code-flag + roll-up** — a violating member shows an inline flag on the model; a roll-up chip shows total concerns → opens the list. (Objective-negative wording.) **P1**

**F4 · Species / load preset selector** — pick lumber species/grade + a load preset (live/dead/snow). **P1**

### G. Footings / terrain

**G1 · Footing config** — type (pier/sonotube/helical/deck-block/pad), size/depth, auto-sized result, count + concrete volume. States: auto / manual / out-of-envelope. **P1**

**G2 · Terrain / grade** — ground-type per zone (grass/dirt/gravel/rock/concrete/pavers); grade/slope capture handoff (AR on iPhone/iPad; manual on Mac); frost-depth + soil inputs. **P1**

### H. House attachment & openings

**H1 · House wall + ledger** — mark the house edge, cladding type (stucco/Hardie/brick/stone/vinyl), the ledger/attachment strategy (incl. brick/stone → freestanding fallback). **P2**

**H2 · Door & window placement** — place/size patio/French/slider doors and windows on the house wall; schedule. Platform: best on iPad/Mac. **P2**

**H3 · Elevation view** — front-on orthographic drawing surface (chrome + placeholder). **P2**

### I. Surface features

**I1 · Railing/guard config** — system (cable/glass/aluminum/wood/composite), height, infill, posts, gates. **P1**

**I2 · Stairs config** — flights/landings/winders, **tread type** (open/closed riser, material, nosing), **stringer count/spacing**, rise/run readout + code check. **P1**

**I3 · Built-ins & lighting** — benches/planters/privacy walls; deck lighting layout + basic electrical notes. **P2**

**I4 · Overhead structures** — pergola / cover / roof config (type, posts/beams/rafters, shade %). **P2**

### J. Compliance (design-time)

**J1 · Code-compliance report** — objective pass/fail by item, each with the current value, the code target, the cited section, severity, and the advisory disclaimer. Contents: summary-first (count of concerns) → per-item rows. States: no concerns / N concerns / out-of-envelope → "requires a licensed engineer." Platform: document on Mac/iPad, scrollable report on phone. **P1**

**J2 · Code-package management** — installed jurisdictions, editions, "current to [date]," update-available, download/offline state. **P2**

### K. As-built CURRENT → TARGET audit (flagship)

**K1 · Capture wizard** — guide the user to record an existing deck: AR/photo capture (native viewport) + the step prompts. States: capturing / reviewing. iPhone/iPad primary. **P2**

**K2 · Hidden-structure wizard** — guided questions for what the phone can't see (joist size/spacing, fastener type, footing depth, connectors present?), with photo-of-fastener prompts. States: per-question; "not assessable" path. **P2**

**K3 · CURRENT → TARGET report** — per finding: `ITEM · SEVERITY · CURRENT · TARGET · CODE § · FIX · CONFIDENCE · EVIDENCE(photo)`; hidden items tagged "not assessable — verify on site"; never a clean pass; the advisory disclaimer. **P2**

### L. Documents / outputs

**L1 · Priced estimate / proposal** — line items, quantities (with waste), prices, totals; branded; client-ready; e-signable affordance. **P0** (early revenue surface)

**L2 · Cut list** — material cut/nesting output (boards + vinyl roll/offcut plan). **P1**

**L3 · Permit plan set** — multi-sheet: plan view, framing plan, elevations, cross-section, detail callouts, site plan, title block; "export to city." Platform: Mac/iPad document surface. **P2**

**L4 · Structural calc report (engineer-reviewable)** — per-member loads/spans/sizes + assumptions + code edition; PE-stamp workflow affordance. **P2**

**L5 · Client 3D render / hero** — the sell-the-job image/share sheet (chrome around the native render). **P1**

### M. Settings & account

**M1 · Settings** — account, jurisdiction/code packages, units, default material catalog, subscription status. **P1**

**M2 · Account & billing** — plan, manage/restore subscription, **account deletion** (Apple-required), data export. **P1**

**M3 · Sync / offline status** — subtle indicator + a detail surface (synced / pending / offline). **P1**

---

## 4. Key flows to storyboard

1. **First run → first deck:** Welcome → start a deck (blank/template/scan/AR) → draw → assign materials → 3D → "Sign in to save" (Apple) → saved in library.
2. **Design → price → export:** open deck → assign → estimate (L1) → cut list (L2) → share/export.
3. **Free → Pro:** create 2nd deck (or tap a Pro feature) → paywall (C1) → purchase → unlocked.
4. **Scan existing → audit:** New deck → AR capture (K1) → hidden-structure wizard (K2) → CURRENT→TARGET report (K3).
5. **Design → engineer → permit:** framing auto-draws → inspect/adjust members (F1–F4) → footings/terrain (G) → compliance report (J1) → permit plan set (L3) + calc report (L4) → export to city.
6. **Upgrade to OPS:** settings/banner → C2 → hand-off.

## 5. Prototype priority (suggested order)

1. **P0 set** — the spine that proves the product: Welcome/onboarding (A1–A3), deck library (B), paywall (C1), designer chrome (D1–D3), material catalog (E1), and the **estimate/proposal** (L1). This is a usable, demoable standalone app.
2. **P1 set** — the engineering & document depth: structural inspector + flags (F), footings/terrain (G), stairs/railings (I1–I2), compliance report (J1), cut list (L2), client render (L5), settings/account (M).
3. **P2 set** — the differentiated heavy surfaces: house/openings (H), as-built audit (K), permit plan set + calc report (L3–L4), overhead/built-ins (I3–I4), patterns (E3), code-package mgmt (J2).

## 6. Notes for Claude Design

- Apply the OPS design system throughout (military tactical minimalist; the three-font system; monochrome + steel-blue; glass + hairlines; one easing curve; honor reduced-motion). Mobile overrides (outdoor contrast, 44pt+ targets) apply on phone/iPad.
- Design **states**, not just the happy path — empty, loading, error, offline, and free-vs-Pro.
- Make the **adaptive story explicit**: show the same surface as phone (single-focus) and iPad/Mac (multi-pane with inspector) for at least the designer workspace, library, and a document.
- Placeholder copy in the OPS voice; final copy comes from `ops-copywriter`.
- The canvas, 3D viewport, and AR view are native — represent them as labeled placeholders and design the surrounding chrome.
