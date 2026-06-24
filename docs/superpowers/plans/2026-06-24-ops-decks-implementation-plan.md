# OPS Decks — Master Implementation Plan (Index)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement each phase plan task-by-task. This is the **index**; the executable detail lives in the per-phase plans and the architecture contract.

**Goal:** Spin the OPS deck designer out as a standalone power-user iOS app ("OPS Decks") — design → engineer → code-check → permit — while the OPS-embedded designer becomes the LIGHT version, across a single shared codebase.

**Architecture:** One codebase, two app targets (OPS + OPS Decks) over a shared `DeckKit` Swift package (+ `OPSDesignKit` for styling). "Company of one" on the existing Supabase backend (same `deck_designs` table + company RLS). The whole deck serializes to one versioned, additive, capability-gated `drawing_data` JSON blob. Compliance is jurisdiction-scoped via downloadable, versioned code-rule packages and makes only objective negative claims.

**Tech Stack:** Swift / SwiftUI / SwiftData, SceneKit (3D) + ARKit (measure), Vision (OCR), Firebase Auth, Supabase (sync + code packages), RevenueCat + StoreKit 2 (billing), PDFKit/Core Graphics (drawings). iOS build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`; tests on the iPhone 17 / OS 26.5 simulator.

**Platforms (locked 2026-06-24):** **iPhone + iPad + Mac** — one shared `DeckKit` + adaptive SwiftUI, designed for all three now, shipped **iPhone → iPad → Mac**. AR is **iPhone/iPadOS-only** (no ARKit on Mac → manual/import fallback, guard `#if os(iOS)`). Workflow split: iPhone = field capture, iPad = design (Apple Pencil), Mac = desk/engineering/permits. **Android** is a future Kotlin/Compose + ARCore port — not built now; the pure engines + data-driven code packages keep it cheap (no cross-platform core today).

---

## The document set

| Doc | Role | Fidelity |
|-----|------|----------|
| **Specs** | | |
| [`…specs/2026-06-24-ops-decks-standalone-app-design.md`](2026-06-24-ops-decks-standalone-app-design.md) | Phase 1 foundation spec (carve-out, company-of-one, billing, upgrade path, costs) | committed |
| [`…specs/2026-06-24-ops-decks-feature-roadmap.md`](2026-06-24-ops-decks-feature-roadmap.md) | Full power-user feature roadmap + LIGHT/FULL split + 7-phase map + liability posture | committed |
| **Plans** | | |
| [`2026-06-24-ops-decks-architecture-contract.md`](2026-06-24-ops-decks-architecture-contract.md) | **Binding source of truth** — module layout, the versioned `drawing_data` schema + per-phase additive blocks, engine signatures, capability flags, compliance rules. Every phase plan conforms to it. | authoritative |
| [`…-phase-1-foundation.md`](2026-06-24-ops-decks-phase-1-foundation.md) | Carve-out + standalone app + company-of-one + billing + waste-fix + catalog model + proposal/render | **Full bite-sized TDD** (code exists today) |
| [`…-phase-2-framing.md`](2026-06-24-ops-decks-phase-2-framing.md) | Framing data model + auto-framing + real 3D members + ground-type | Comprehensive task plan |
| [`…-phase-3-structural.md`](2026-06-24-ops-decks-phase-3-structural.md) | Code-rule packages + jurisdiction + spans + per-column load + manual editor | Comprehensive task plan |
| [`…-phase-4-footings-terrain.md`](2026-06-24-ops-decks-phase-4-footings-terrain.md) | Footings + grade/terrain + ledger + connections + hardware | Comprehensive task plan |
| [`…-phase-5-house-openings.md`](2026-06-24-ops-decks-phase-5-house-openings.md) | House model + doors/windows + elevations + multi-story | Comprehensive task plan |
| [`…-phase-6-surface-features.md`](2026-06-24-ops-decks-phase-6-surface-features.md) | Patterns/cut-optimizer + stairs (tread types + stringers) + railings + overhead + lighting | Comprehensive task plan |
| [`…-phase-7-compliance-permits.md`](2026-06-24-ops-decks-phase-7-compliance-permits.md) | Compliance engine + as-built audit + permit plan sets + PE stamp + calc report | Comprehensive task plan |

**Fidelity note (read this):** Phase 1 is executable today — its code exists or is a concrete carve-out of existing code, so it's written as full red→green→commit TDD tasks. Phases 2–7 build on code earlier phases create, so each is a comprehensive task-decomposition plan (file structure, per-task interfaces bound to the contract, test strategy, dependencies, code/standard references, risks); their literal bite-sized steps are finalized at each phase's start once predecessors exist. This is deliberate — writing literal code against not-yet-built foundations would be fiction.

---

## Dependency spine & phase order

The build order is forced by dependencies: **model → auto-derive → size → validate → draw.**

```
P1 Foundation ─┬─> P2 Framing model ──> P3 Structural ──┬─> P4 Footings/Terrain ──┐
               │   (+ ground-type)      (+ code pkgs,    │                          ├─> P6 Surface features ──> P7 Compliance + as-built + permits
               │                         load, editor)   └─> P5 House/openings ─────┘   (patterns, stairs, overhead)
               └─ early wins ride along: estimate waste-factor fix, catalog model, client proposal/render
```

- **P2** is the universal blocker (the framing data model); it also delivers the first "serious tool" moment (real 3D members) as shared LIGHT/FULL value, with no compliance claim yet.
- **P3** turns the plausible frame into a *sized, defensible* frame (RedX parity) and introduces the jurisdiction-keyed code-rule packages.
- **P4 and P5** can proceed in parallel after P3 (footings/terrain vs house/openings).
- **P7** is strictly last — every output (permit set, calc report, as-built audit) depends on the full model + the compliance engine.

Each phase ships standalone value; P1–P2 fund the long engineering tail.

---

## Cross-cutting (applies to every phase)

- **Compliance posture (locked):** objective negative claims only ("no code failures detected," never "safe/guaranteed"), jurisdiction-selectable, downloadable versioned code-rule packages (Supabase-delivered, offline-cached, updatable without an App Store release, stamped "current to [edition]"), disclaimer + licensed-engineer recommendation, out-of-envelope → "requires a licensed engineer," PE-stamp workflow. See contract §6 + roadmap §7.
- **Schema discipline:** one `drawing_data` blob, versioned, additive, backward-decodable — an unknown/failed sub-block must never fail the whole-design decode. LIGHT preserves blocks it can't render (never strips). Make `DeckDesign.version` live.
- **Engines are pure, table-driven, offline, unit-tested** (the `StairCalculator` precedent). All sizing/compliance runs on-device against bundled/cached code packages — no network round-trip.
- **Platforms:** all surfaces are built **platform-agnostic in `DeckKit` + adaptive SwiftUI** so iPhone/iPad/Mac share one codebase; AR lives behind `#if os(iOS)` (no Mac AR). Design for all three from the start; ship iPhone → iPad → Mac. Keep every engine pure + platform-free so a future Android (Kotlin/Compose + ARCore) port re-implements only the UI/3D/AR layer.
- **Cost prerequisites:** **Supabase → Pro ($25/mo) before any standalone customer data lands** (no backups on free tier today). Apple 15% (<$1M, SBP)/30%; RevenueCat free <~$2.5k/mo then ~1%. DWG/DXF export carries unverified third-party cost — flag before committing.
- **Parallel-work hazard:** the in-flight deck-overhaul Drops 1–6 touch the same `DeckBuilder/` files. **Sequence: land the current Drop, then do the Phase 1 package extraction as one coherent branch, then continue.** Coordinate against sibling sessions before extracting (memory: shared-tree branch-switch hazard).
- **Cross-phase consistency:** reviewed and reconciled 2026-06-24 — PermitMeta (P1-owned, incl. `disclaimerAcknowledgedAt`), `JurisdictionDescriptor` superset (P1-owned), the engine-result envelope + `MemberSizingResult` (P2-owned), `TerrainModel` (P2-owned, P4 fills grade), `CodePackageLoaderError` (P1-owned). The architecture contract is authoritative on any residual drift.

---

## Execution

This session is **planning only** — no implementation. When build begins (a future session), per the writing-plans handoff:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, two-stage review between tasks (superpowers:subagent-driven-development). Best for Phase 1's bite-sized TDD tasks.
2. **Inline Execution** — batch execution with checkpoints (superpowers:executing-plans).

Start with **Phase 1**. Before each of Phases 2–7, do a short phase-start refinement pass (re-read predecessor code, lock the literal signatures, then execute), since each plan was written against the contract rather than not-yet-existing code.
