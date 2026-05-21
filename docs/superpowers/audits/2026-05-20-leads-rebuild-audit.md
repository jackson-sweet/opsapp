# LEADS Tab Rebuild — Conformance Audit

**Date:** 2026-05-20
**Auditor:** Spawned agent (LEADS POLISH - P2-1)
**Scope:** Phases 0–6 + Wave 1 polish (P1-1 through P1-4) on `feat/leads-tab-rebuild`
**Method:** Read-only static analysis against design intent, design system canon, designer handoff bundle, and shipped iOS implementation.

---

## Executive summary

| Severity | Count | Recommendation |
|---|---|---|
| CRITICAL | 7 | Must fix before ship |
| WARNING | 18 | Should fix before next polish wave |
| INFO | 13 | Acceptable as-is; documented for future awareness |

**Top-3 highest-priority findings:**

1. **Pipeline footer drill-down is dead** — every row taps and the `OPEN STAGE BOARD →` link route through no-op TODO callbacks (`LeadsTabView.swift:125-126`). Plan §2.1 Q2 committed to "(b) Tap a stage row → filtered single-stage list", and design-intent §23 #5 committed to per-stage drill including Won/Lost. Footer is visually present, interactively dead.
2. **Critical touch-target violations across 5 components** — `QuickGlyph` 34pt (`LeadActionCard.swift:202`), `WonConvertCard` buttons 40pt (`WonConvertCarousel.swift:113, 129`), client-other project chips 32pt (`ConvertToProjectSheet.swift:318`), `FilterChipRow` and `LeadChipPicker` chips 36pt (`FilterChipRow.swift:79`, `LeadFormView.swift:425`). Audit rule F1 says 44×44pt minimum.
3. **Won/Lost stages not surfaceable from `PipelineFooter`** — only the 6 open stages render (`PipelineFooter.swift:35-37`). Design-intent §23 #5 closeout said the footer would carry won/lost drill since the stage-strip CLOSED reveal was deleted; that drill never landed.

---

## Findings

### Token integrity

#### [WARNING] A1 — Atmosphere bypasses color tokens with raw RGB

**File:** `OPS/Styles/Components/Atmosphere.swift:28-31`
**Rule:** Token integrity (CLAUDE.md "Never improvise colors — use OPSStyle tokens"; design intent §17)
**Observation:** The four tone cases duplicate `opsAccent` / `olive` / `tan` / `rose` hex values inline as `Color(red: 111/255, green: 148/255, blue: 176/255)` (etc.) — the comment on line 28 even says "ops-accent". A render-time atmosphere effect, but the literals are still a token bypass.
**Fix:** Replace with `OPSStyle.Colors.opsAccent` / `.olive` / `.tan` / `.rose` in the `color` computed property.

#### [WARNING] A1 — 32 `Color.white.opacity(N)` literals where tokens exist

**Files (representative):** `LeadActionCard.swift:205,209`; `WonConvertCarousel.swift:69`; `PipelineFooter.swift:61`; `ContactCard.swift:193-194`; `ActivityTimeline.swift:53,120,124`; `StageTimeline.swift:47`; `DetailHero.swift:307`; `FilterChipRow.swift:82,87`; `LeadFormView.swift:335,387,428,433`; `GlassSurface.swift:103,107` (preview-only inside the modifier file).
**Rule:** Token integrity. `OPSStyle.Colors.surfaceInput` = white 0.04; `fillNeutralDim` = white 0.06; `surfaceActive` = white 0.08; `line` / `inputFieldBorder` = white 0.10. All four are referenced as raw `Color.white.opacity(...)` instead.
**Observation:** Hex values mostly match the corresponding token, so visually identical — but the brittle pattern violates the project rule that "every value traces to a token."
**Fix:** Replace `Color.white.opacity(0.04)` → `OPSStyle.Colors.surfaceInput`; `0.06` → `fillNeutralDim`; `0.08` → `surfaceActive`; `0.10` → `line`. The 0.18 / 0.20 / 0.03 / 0.05 values have no exact-match token — either extend the token tree or accept them as the few legitimate exceptions and comment.

#### [WARNING] A3 — Toast renders `//` label with system mono instead of JetBrains Mono

**File:** `OPS/Styles/Components/Toast.swift:228, 234`
**Rule:** Token integrity (design system §4 — JetBrains Mono is registered, loaded, and the canonical mono face).
**Observation:** `Font.system(size: 11, weight: .semibold, design: .monospaced)` rather than `Font.custom("JetBrainsMono-Medium", size: 11)` or `OPSStyle.Typography.metadata`. On dark, system mono (SF Mono) reads materially different from JetBrains Mono — narrower digit width, different `0` glyph.
**Fix:** Replace both occurrences with `OPSStyle.Typography.metadata` (= `JetBrainsMono-Regular` 11pt), apply `.fontWeight(.semibold)` at the call site.

#### [WARNING] A4 — Hardcoded `cornerRadius: 6` on the WonConvert badge

**File:** `OPS/Views/Leads/WonConvertCarousel.swift:151, 155`
**Rule:** Token integrity — `OPSStyle.Layout.cardRadius = 6.0` exists for L2 nested cards / small chips.
**Observation:** Two `RoundedRectangle(cornerRadius: 6, style: .continuous)` literals on the olive WON badge tile.
**Fix:** `cornerRadius: OPSStyle.Layout.cardRadius`.

#### [WARNING] A4 — Hardcoded `cornerRadius: 5` on the QuickGlyph

**File:** `OPS/Views/Leads/Components/LeadActionCard.swift:204, 208`
**Rule:** Token integrity — `OPSStyle.Layout.buttonRadius = 5.0` exists.
**Observation:** Same pattern.
**Fix:** `cornerRadius: OPSStyle.Layout.buttonRadius`.

#### [INFO] A2 — Hardcoded sizes across `HeroWidget`, `LeadActionCard`, sheets

**Files:** Multiple — e.g. `HeroWidget.swift:53,122`; `LeadsTabView.swift:130,313`; `LeadActionCard.swift:107,129,202`; `DetailHero.swift:281`; `WonConvertCarousel.swift:63,151,149`.
**Rule:** Token integrity — `OPSStyle.Layout.spacing*` exists.
**Observation:** Magic numbers in spacing/sizing (14pt, 22pt, 38pt font sizes for Mohave Light hero; 18pt, 12pt assorted paddings; `200` bottom padding; `100` bottom padding; `152` card height). Most match prototype specs exactly; few correspond to existing tokens. Plan §6.3 explicitly noted this and recommended adding a `Typography.Mobile` sub-namespace — that scope was deferred. INFO because the values are spec-correct, just not tokenized.
**Fix:** Optional — add a `Typography.Mobile` enum with `hero` (38pt), `subValue` (22pt), `kvValue` (18pt), `bodyName` (15pt) so call sites can drop the `Font.custom("Mohave-Light", size: 38)` chains. Spacing constants for the 14pt / 18pt / 22pt / 100pt / 152pt magic numbers similarly.

---

### Anti-patterns

#### Passed audit

- **B1 — Accent leakage.** No violations. Accent (`opsAccent`) appears only on (a) `WonConvertCard.CONVERT → PROJECT` outlined CTA (`WonConvertCarousel.swift:112,116`); (b) `WonNotConvertedCard.CONVERT → PROJECT` fill CTA (`LeadDetailView.swift:252`); (c) `StickyActionBar.MARK WON` (`StickyActionBar.swift:127`); (d) `SheetCTAButton.primary` fill (`LeadFormView.swift:577`); (e) `FilterChipRow.waitingOnYou` chip dot (`LeadsTabView.swift:299`) — explicitly permitted by drift register §23 #2; (f) `SubMetric.steel` tone label (`SubMetric.swift:35`) — semantic "reply-due"; (g) `LeadActionCard.steel` tone (`LeadActionCard.swift:37`) — same. All within the allowlist.
- **B2 — Cards with rounded corners + colored left-border accent.** No instances found. Stage identity reads from earth-tone chip on `DetailHero.StageTag` and from caption + verb-tone on `LeadActionCard`. The 3pt leading rail anti-pattern is fully eliminated per drift closeout §23 #3.
- **B3 — Spring physics / bounce.** No `Animation.spring`, `interactiveSpring`, `.bouncy`, or `OPSStyle.Animation.spring` references in any rebuild file. All easing goes through `OPSStyle.Animation.standard` (the canonical `cubic-bezier(0.22, 1, 0.36, 1)`) or the `.fast`/`.faster` aliases — Toast.swift:163-167 picks among them. ✓
- **B4 — Box-shadows on dark.** Zero `.shadow(...)` modifiers and zero `OPSStyle.Layout.Shadow.*` references across the rebuild files. ✓
- **B5 — Emoji.** None present. ✓
- **B6 — Exclamation points.** None in user-facing copy. ✓
- **B7 — Coaching language.** None ("Welcome", "Awesome", "Oops", "Great", "Saved!" etc. all absent). Loss toast is `// LEAD LOST` in tan, not rose — design intent §11 "no drama, just acknowledgment." ✓

---

### Voice & copy

#### Passed audit

- **C1 — `//` prefix on system labels.** Consistent throughout: `// QUEUE`, `// BY STAGE`, `// FROM WON LEAD`, `// NEXT FOLLOW-UP`, `// STAGE HISTORY`, `// RECENT ACTIVITY`, `// DANGER ZONE`, `// LEAD CREATED`, etc.
- **C2 — UPPERCASE for authority / sentence case for content.** Section headers, button labels, status chips all UPPERCASE; placeholder copy ("What did you talk about?", "Roof access notes, gate codes…") in sentence case.
- **C3 — Number formatting.** All currency formatted via NumberFormatter or compact-money helpers; all counts zero-padded (`%02d`); empty state always `—` or `00`. No raw numbers surfaced.
- **C4 — Marketing voice.** None. Empty state copy is tactical (`// — NO OVERDUE FOLLOW-UPS`).
- **C5 — First-person voice.** None. Provenance footer in `ConvertToProjectSheet.swift:507` says "Marks the lead WON and creates a Project (status: ACCEPTED)…" — declarative third-person.

#### [WARNING] Type floor — 8.5pt hint text on SubMetric / KvCell sub-line

**Files:** `OPS/Views/Leads/Components/SubMetric.swift:56`; `OPS/Views/Leads/Components/DetailHero.swift:289`.
**Rule:** DESIGN.md §4 — "11px minimum. No exceptions." MOBILE.md §1 type scale floor for tags/badges is 9.5–10pt.
**Observation:** Both render meaningful descriptive labels (`NEEDS NOW`, `FOLLOW UP`, `03 WAITING`, `ESTIMATED`, `@ 60%`, `LEAD · L-XXXXXX`) at 8.5pt JetBrains Mono. Below both the universal 11pt floor and the mobile 9.5pt tag floor. On outdoor screens with glare this becomes hard to read.
**Fix:** Bump to 9.5pt (matching MOBILE.md tag floor) or to 10pt (matching the `LeadActionCard` row3 and `LeadDetailView.DetailNavBar` precedents). The visual hierarchy still holds.

#### [WARNING] Type floor — 9pt mono on `LeadActionCard` row3 due chip and REFERRAL caption

**File:** `OPS/Views/Leads/Components/LeadActionCard.swift:150, 158`.
**Rule:** DESIGN.md §4 — 11pt floor; MOBILE.md §1 — 9.5pt tag floor.
**Observation:** Due chip ("2D OVERDUE" / "TODAY" / "TOMORROW" / "IN 3D") and the REFERRAL caption render at JetBrains Mono 9pt — below even the MOBILE.md tag floor. The chip is semantically tone-tinted (rose/tan/steel) so contrast helps, but 9pt is the smallest text on the surface.
**Fix:** Lift to 9.5pt (mobile floor) at minimum, ideally 10pt.

#### [INFO] Sheet titles use `//` mono header instead of MOBILE.md §6.3 spec

**Files:** All five sheets via `SheetTitleLabel` in `OPS/Views/Leads/Sheets/LeadFormView.swift:624-638`.
**Rule:** MOBILE.md §6.3 full-sheet spec: "Title | Cake Mono 300, 22px, uppercase, top-left."
**Observation:** All sheets render the title as `// NEW LEAD` / `// EDIT · L-XXXXXX` / `// CONVERT → PROJECT` etc. via `JetBrainsMono-Medium 11pt` centered. The display divergence is intentional (matches the LEADS-tab `//` voice throughout), but MOBILE.md was not updated to scope the deviation. INFO because it's a coherent design choice; flag for the design system to either accept LEADS as an exception or revise MOBILE.md §6.3.
**Fix:** Decide direction with the design system maintainer; if keeping current implementation, add a note to MOBILE.md §6.3 carving out OPS-app sheets.

---

### Visual hierarchy + surface tier

#### Passed audit

- **D1/D2 — L1 vs L2 selection is correct.** `HeroWidget`, `LeadActionCard`, `ContactCard`, `FollowUpsCard`, `ActivityTimeline`, `StageTimeline`, `PipelineFooter`, `WonConvertCard`, `WonNotConvertedCard`, `leadSummaryCard` (Convert sheet) all use `.glassSurface()` (L1). KPI strip (`DetailHero.kpiStrip`), task preview rows, lost-reason summary, estimate rows, project chips, QuickGlyph all use `.nestedCard()` (L2) or flat fill correctly.
- **D3 — Three-deep glass nesting.** No `.glassSurface()` inside `.glassSurface()` inside `.glassSurface()` found. Max nesting is L0 canvas → L1 card → L2 nested card. ✓
- **D4 — Legacy `cardBackground` in new code.** No references to `OPSStyle.Colors.cardBackground` / `cardBackgroundDark` / `darkBackground` in any of the 21 rebuild files. ✓

#### [INFO] `WonNotConvertedCard` double-strokes on its rounded rectangle

**File:** `OPS/Views/Leads/LeadDetailView.swift:260-264`
**Rule:** `.glassSurface()` already applies a 0.09-white hairline; the additional `.overlay(...strokeBorder(oliveLineM, lineWidth: 1))` paints a second border on top.
**Observation:** In practice the olive-line-M stroke at 55% alpha dominates the 9% glass border, so visually the user only sees the olive. Both strokes render through the same `RoundedRectangle(cornerRadius: panelRadius)` so they overlay cleanly — but the layering is implicit and easy to miss.
**Fix:** Optional — extend `GlassSurfaceModifier` with a `borderColor` parameter to swap the stroke inline, rather than overlaying two borders.

---

### Mobile contrast (MOBILE.md §1 outdoor-glare uplift)

#### Passed audit

- **E1 — `-M` (mobile-contrast) earth-tone variants used throughout.** Hero widget delta chip → `oliveTextM` / `roseTextM` (`HeroWidget.swift:102`); LeadActionCard verb/due tones → `roseTextM` / `tanTextM` (`LeadActionCard.swift:35-39`); DetailHero StageTag → `oliveFillM` / `oliveLineM` / `oliveTextM` and tan/rose counterparts (`DetailHero.swift:222-244`); FollowUpsCard → `roseTextM` / `tanTextM` (`FollowUpsCard.swift:103-105`); ActivityTimeline inbound tint → `oliveTextM` (`ActivityTimeline.swift:134`); WonConvert badge + eyebrow → olive-M trio (`WonConvertCarousel.swift:148, 152, 156, 173`); StickyActionBar LOST → rose-M trio (`StickyActionBar.swift:51, 55, 59`); ConvertToProjectSheet duplicate-card → olive-M trio (`ConvertToProjectSheet.swift:208, 245, 249`); ConvertToProjectSheet client-others banner → tan-M trio (`ConvertToProjectSheet.swift:261, 289, 293`); SheetCTAButton.destructive → rose-M trio (`LeadFormView.swift:570, 579, 588`); Toast tone palette → all three -M trios (`Toast.swift:38-50`). No legacy `oliveSoft`/`oliveLine`/`tanSoft`/`roseSoft` slip through.
- **E2 — Body contrast.** Primary body content uses `text` (#EDEDED, 18.8:1) and `text2` (#B5B5B5, 10.3:1). `text3` (#8A8A8A, 5.4:1) is reserved for metadata/labels; `textMute` (#6A6A6A, 3.4:1) is reserved for `//` prefix and decorative separators. No body copy uses `text3` or `textMute` for non-decorative purposes.

---

### Touch targets + field-first

#### [CRITICAL] F1 — `QuickGlyph` 34×34pt is below the 44pt minimum

**File:** `OPS/Views/Leads/Components/LeadActionCard.swift:202`
**Rule:** CLAUDE.md "Touch targets: Minimum 44x44pt"; DESIGN.md §15; MOBILE.md §1.
**Observation:** All three triage-row quick glyphs (LOG, MORE, ADVANCE → opens `LeadLogActivitySheet`, confirmation dialog, `moveToStage`) render at 34×34pt. They are tappable (`Button`) with no extended hit area. Three of them sit adjacent on the row; the operator is field-using with gloves.
**Fix:** Bump `.frame(width: 34, height: 34)` → `.frame(width: 44, height: 44)` and reduce the icon's visual padding instead. Or apply `.contentShape(Rectangle()).frame(width: 44, height: 44)` to keep the 34pt visual chip but extend the hit area to 44pt.

#### [CRITICAL] F1 — `WonConvertCard` CONVERT / LATER buttons at 40pt

**File:** `OPS/Views/Leads/WonConvertCarousel.swift:113, 129`
**Rule:** Same 44pt minimum.
**Observation:** Both buttons specify `.frame(minHeight: 40)`. The CONVERT button opens the Convert sheet (high-stakes action); LATER opens the detail view. Below the universal touch-target floor by 4pt — measurable miss for a user with gloves or in motion.
**Fix:** Bump both to `minHeight: 44` (or 48 to match other CTA conventions in the rebuild).

#### [CRITICAL] F1 — `ConvertToProjectSheet` other-project chips at 32pt

**File:** `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift:318`
**Rule:** Same 44pt minimum.
**Observation:** Project chips in the "THIS CLIENT HAS N OTHER PROJECTS" banner render at `minHeight: 32`. Tapping a chip navigates to that project's detail. 32pt is well below the floor, and these chips sit inside an already-cramped warning banner with multiple chips per row.
**Fix:** Bump `minHeight: 32` → `minHeight: 44`, or wrap each chip in a `frame(minHeight: 44)` outer touch container while keeping the visual chip dense.

#### [CRITICAL] F1 — `FilterChipRow` chips at 36pt

**File:** `OPS/Styles/Components/FilterChipRow.swift:79`
**Rule:** CLAUDE.md / DESIGN.md §15 say 44pt minimum. MOBILE.md §4.3 allows 36pt for filter chips ("chips are denser than tabs"), but does not invoke the "extend tap area beyond visible" affordance.
**Observation:** Chip `minHeight: 36`. Filter is the operator's primary triage tool — selected dozens of times per session. Spec ambiguity between MOBILE.md §4.3 and the universal 44pt rule.
**Fix:** Either (a) bump `minHeight: 44` to align with universal rule; (b) keep visual at 36pt but wrap each chip in an outer `frame(minHeight: 44)` with `contentShape(Rectangle())` to extend the tap area without changing the look; (c) leave at 36pt and revise MOBILE.md §4.3 to explicitly OK this only when chips appear in a horizontal scroll row with 6+pt spacing.

#### [CRITICAL] F1 — `LeadChipPicker` chips at 36pt (Form sheets)

**File:** `OPS/Views/Leads/Sheets/LeadFormView.swift:425`
**Rule:** Same as FilterChipRow.
**Observation:** The wrap-layout chip group used for SOURCE / STAGE / PRIORITY pickers in Add/Edit, REASON in LostReason, TYPE / DIRECTION / OUTCOME in LogActivity. All render at `minHeight: 36`. Per MOBILE.md §4.3 "filter chips" is in spec, but these are form pickers (single-select per group) — closer to MOBILE.md §4.2 "scrolling tabs" which mandates 44pt min.
**Fix:** Same options as FilterChipRow. Recommend (b) — keep visual density, extend tap area.

#### [INFO] F2 — `DetailHero` KvCell rows aren't tappable

**File:** `OPS/Views/Leads/Components/DetailHero.swift:106-134`
**Observation:** Three KPI cells render `KvCell` rows but don't wire any `Button` / `onTapGesture`. They are display-only. If future polish needs them tappable (e.g., VALUE → estimate breakdown, WEIGHTED → forecast breakdown), the layout has no current tap target. Not a violation today.
**Fix:** None required. Flagged so designer/PM are aware before wiring drill-ins.

---

### Empty / loading / error states

#### Passed audit

- **G1 — Empty states follow `00` + `// — NO X` pattern.** `LeadsTabView.BucketEmpty` (`LeadsTabView.swift:389-419`) — Mohave Light 32pt `00` + JetBrains Mono 11pt mute `// — NO OVERDUE FOLLOW-UPS` (and per-bucket variants). `ActivityTimeline.EmptyLine` (`ActivityTimeline.swift:183-196`) — `// NO ACTIVITY LOGGED`. `StageTimeline.EmptyLine` — `// NO STAGE CHANGES LOGGED`. No emoji, no illustrations, no coaching language anywhere. ✓
- **G3 — Error states name the thing.** `AddLeadSheet.simplifyError` returns `OFFLINE — TAP SAVE TO RETRY` / `PERMISSION DENIED` / `COULD NOT SAVE — TAP TO RETRY` / `NO COMPANY ON SESSION`. `LeadConversionService.LeadConversionError` enum surfaces `LEAD NOT FOUND` / `PROJECT CREATED — REFRESH`. All sheet status lines use the `// ERROR — <REASON>` pattern. ✓

#### [INFO] G2 — Loading states use SwiftData/network without skeleton

**Files:** `LeadsTabView.swift:166-171` (initial load); `LeadDetailView.swift:135-137` (loadAll); `ConvertToProjectSheet.swift:124-127` (preflight load).
**Observation:** First-paint shows an empty `ScrollView` while VM is hydrating. There's no skeleton/pulsing state per MOBILE.md §10 ("Pulsing rectangles matching the expected content layout"). For an offline-first app this is usually instant from cache, so not user-visible in the steady state — but cold launch or sync-stale state could surface a blank canvas before the first frame.
**Fix:** Optional — add a `isLoading` skeleton view for HeroWidget / LeadActionCard rows that fades to real content. Plan §14 referenced this implicitly; not in plan scope.

---

### Motion + animation

#### Passed audit

- **H1 — Single easing curve.** All animations in the rebuild use `OPSStyle.Animation.standard` / `.fast` / `.faster` (the OPS-canonical curve). No `.spring` / `.interactiveSpring` / `.easeIn` / `.easeOut` / `.linear` / `.bouncy` anywhere in the rebuild files (verified via grep).
- **H2 — Reduced motion.** `Toast.swift:141` reads `@Environment(\.accessibilityReduceMotion)`. Banner transition at line 173-177 falls back to `.opacity` only; the host animator at line 162-167 falls back to `OPSStyle.Animation.faster` (150ms). ✓

#### [INFO] H2 — Other rebuild views don't explicitly check reduced motion

**Files:** `LeadsTabView`, `LeadDetailView`, `WonConvertCarousel`, and the four full-detent sheets.
**Observation:** None of these mount animations beyond the implicit transitions SwiftUI applies for NavigationStack push / sheet presentation. Those transitions inherit the OS-level reduced-motion preference automatically, so functionally compliant. But should any future polish add explicit `withAnimation(...)` blocks (e.g. card-appear stagger), the patterns aren't in place — Toast.swift is the only file currently demonstrating reduced-motion handling.
**Fix:** None required today. Note for future polish work.

---

### Plan conformance

#### [CRITICAL] I1 — `PipelineFooter` row taps and "OPEN STAGE BOARD →" hint are dead TODOs

**File:** `OPS/Views/Leads/LeadsTabView.swift:125-126`
**Rule:** Plan §2.1 Q2 chose option (b) "Tap a stage row → filtered single-stage list. Reuses `LeadActionCard` rendering."
**Observation:** `LeadsTabView` passes empty closures with TODO comments to `PipelineFooter` — `onStageTap: { _ in /* Phase 6 may wire this — defer for now */ }` and `onBoardTap: { /* same */ }`. `PipelineFooter` itself wires the tap correctly (`PipelineFooter.swift:49-55` fires the closure, `PipelineSectionHeader.swift:58-66` wires the hint button) — the parent's no-op closures are the dead end. Visually the rows render a chevron + light haptic on tap, suggesting interactivity that doesn't deliver.
**Fix:** Implement the filtered single-stage list view (or repurpose `LeadActionCard` inside a navigation destination); wire `onStageTap` and `onBoardTap` to push it.

#### [CRITICAL] I2 — Pipeline footer omits Won/Lost stages

**File:** `OPS/Views/Leads/PipelineFooter.swift:35-37`
**Rule:** Design intent §23 #5 closeout: "Per-stage drill from the pipeline footer can list won/lost. The CLOSED reveal in the stage strip is gone."
**Observation:** `private let stages: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]` — only 6 stages. Won and Lost are never surfaced. With the CLOSED reveal deleted from the stage strip, there's now no path from the LEADS tab to a list of won or lost leads.
**Fix:** Either (a) add `.won` and `.lost` to the stages array with a visual divider, dimmed treatment per design intent §15 alternative (60% opacity); or (b) document an explicit deferral in `2026-05-19-leads-tab-design-intent.md` §23 #5 — the closeout claim doesn't match the shipped behavior.

#### [INFO] I3 — Convert flow deep-links to project; designer prototype stayed on LEADS

**File:** `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift:671-676, 694-697`
**Rule:** Designer handoff README §6 "Save semantics — engineering work required" → "Confirm with PM whether to deep-link to the new project after creation. The prototype defers that — operator stays on LEADS."
**Observation:** Both `createProject` and `openExistingProjectAction` fire `appState.viewProjectDetailsById(projectId)` after a 350ms delay, deep-linking the operator to the new/existing project. This diverges from the prototype's stay-on-LEADS behavior. Reasonable PM call; just not the prototype-default.
**Fix:** None required; documented for posterity. If PM signed off, no action.

#### Passed audit

- **I1 — Filter icon deleted entirely (Q4).** `LeadsTabView.metaRow:200-232` confirms no filter icon. Comment at line 214-216 documents the decision.
- **I1 — Search icon also deleted.** Same metaRow has no search affordance; persistent overlay search elsewhere (per comment).
- **I1 — Every sheet exit marks WON (Q3).** `ConvertToProjectSheet` has `didCommitWon` guard + `commitNoProjectAndDismiss()` for CANCEL / `×` / scrim / drag-down (lines 711-720); `onDisappear` fallback at 128-135 fires `markWonNoProjectSilently()` if no path committed. CREATE PROJECT path fires the convert RPC (lines 634-682). OPEN PROJECT path marks won + opens existing project (lines 684-699).
- **I1 — WonConvert is a carousel (Q6).** `WonConvertCarousel` paginates all unconverted wins (`WonConvertCarousel.swift:32-58`).
- **I1 — LOG glyph builds `LeadLogActivitySheet` (Q5).** `LeadLogActivitySheet.swift` exists with full form per design.
- **I1 — Forecast delta wired (P1-3).** `PipelineViewModel.forecastDeltaPct` (lines 420-446) reconstructs 30-day prior baseline from `allStageTransitions` and computes percent change. Velocity tile wires identically (`avgVelocityDays`, lines 470-502) and the hero hides the 4th column when nil.
- **I1 — Toast surface mounted (P1-1).** `MainTabView.swift:491-492` `.toastHost().leadsToastSubscriber()` confirmed.
- **I2 — Drift register §23 #1, #2, #3 all resolved.** No carousel; no accent leakage on chrome; no stage-color leading rail.

---

### Cleanup completeness

#### Passed audit

- **J1 — Legacy directory deleted.** `OPS/Views/Books/Pipeline/` does not exist on the audit branch.
- **J1 — Phase-1 LEADS file orphans deleted.** No `LeadsHeaderCarousel`, `BallInCourtBar`, `LeadListPage`, `LeadCard`, `LeadStageStrip`, `ForecastBreakdownSheet`, `PipelineSectionView`, `StageStripView`, `LeadCardView` files. (Verified via `ls` and grep for class names.)
- **J3 — Spec doc supersede banner in place.** `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md:3` reads `> **SUPERSEDED 2026-05-19** by 2026-05-19-leads-tab-rebuild.md (implementation plan)`.

#### [INFO] J1 — Stale doc-comment references to deleted symbols

**Files:**
- `OPS/DataModels/Enums/PipelineStage+Color.swift:14` — comment references `LeadsHeaderCarousel's "ACTIVE PIPELINE" card` (the carousel was deleted).
- `OPS/Views/Leads/HeroWidget.swift:42` — comment references "a future `ForecastBreakdownSheet`" (the sheet was deleted per drift register §23 #7).

**Rule:** J1 cleanup completeness — comments referencing deleted symbols should be removed or updated.
**Observation:** Both are doc comments, not live code, so they don't break compilation. The `HeroWidget` reference is forward-looking (a hypothetical future sheet), so it's defensible — the `PipelineStage+Color.swift` reference is purely historical.
**Fix:** Optional — update `PipelineStage+Color.swift:14` to reference the new surface (`HeroWidget`) or strip the example sentence entirely. `HeroWidget.swift:42` can stay if the sheet may be revived; otherwise rephrase as "future breakdown drill-in (deferred)."

#### [INFO] J2 — VM cleanup is complete per the plan

**File:** `OPS/ViewModels/PipelineViewModel.swift`
**Observation:** Removed: `inCourtCount`, `inCourtBuckets`, `inCourtTotalValue`, `inCourtOpportunityIds`, `oldestStaleDescription`. Kept (per plan §10.2 exception): `closeRate(periodDays:)` for the BOOKS tab; `staleLeadsCount` and `weightedForecastValue` still used. Added: `forecastDeltaPct`, `weightedForecast(asOf:)`, `stage(for:asOf:)`, `avgVelocityDays(periodDays:)` for hero polish P1-3. Triage bucketize + `bucketOf` + `verbFor` + `toneFor` + `defaultBucket` all per plan. ✓
**Fix:** None required.

---

### Other findings

#### [WARNING] Button flex ratio bug across all 5 sheets

**Files:** `AddLeadSheet.swift:106`; `EditLeadSheet.swift:133`; `LostReasonSheet.swift:173`; `ConvertToProjectSheet.swift:556, 566`; `LeadLogActivitySheet.swift:276`.
**Rule:** Designer handoff README §3 / §6 footer: "`CANCEL` ghost (1/3) + `SAVE LEAD` accent-fill (2/3)". Plan §8.3 confirms "CANCEL ghost (flex:1) + SAVE LEAD accent (flex:2)".
**Observation:** The intended 1:2 ratio is expressed via `.frame(maxWidth: .infinity)` on CANCEL and `.frame(maxWidth: .infinity * 2)` on the SAVE/CREATE/LOG/CONFIRM LOST button. `.infinity * 2` evaluates to `.infinity` in CGFloat math, which collapses to the same `maxWidth: .infinity` as the sibling. Both buttons render at equal width — not the 1:2 ratio. The visual hierarchy the design called for (primary button noticeably wider than CANCEL) is missing.
**Fix:** Replace with a real ratio. Wrap both buttons in a `GeometryReader { geo in ... }` that allocates `editWidth = (geo.size.width - 8) / 3` and `wonWidth = editWidth * 2` (mirroring the pattern in `StickyActionBar.swift:69-77`, which gets this right). Or use SwiftUI's `Spacer().frame(minLength: ...)` with explicit widths.

#### [INFO] `Color.black` used as foreground on accent-fill buttons

**Files:** `LeadDetailView.swift:247` (CONVERT → PROJECT); `StickyActionBar.swift:123` (MARK WON); `LeadFormView.swift:568` (SheetCTAButton.primary foreground).
**Rule:** Token integrity (`OPSStyle.Colors.invertedText` exists).
**Observation:** Apple-default `.black` instead of `OPSStyle.Colors.invertedText`. `.black` resolves identically to `#000000` in dark mode; functionally equivalent.
**Fix:** Optional — `OPSStyle.Colors.invertedText` for trace-to-token discipline.

#### [INFO] `LeadDetailView` nav bar has no right-side action icons

**File:** `OPS/Views/Leads/LeadDetailView.swift:206-211`
**Rule:** MOBILE.md §2.1 "Action icons — Right-aligned, 20px Lucide icons, --text-2. Max 2 icons" — suggests at least one right-side action on detail surfaces.
**Observation:** Right side is empty (Spacer + nothing). Inline comment at line 178-181 confirms this is intentional: archive lives in `EditLeadSheet`'s danger zone and per-row actions are reachable from the sticky action bar. Reasonable design call.
**Fix:** None required.

#### [INFO] Atmosphere may render two glows on the same screen

**Files:** `LeadsTabView.swift:81` and `LeadDetailView.swift:89`.
**Rule:** MOBILE.md §3 "Maximum ONE glow per screen."
**Observation:** Each surface mounts its own `Atmosphere`. When `LeadDetailView` is pushed via `.navigationDestination`, the parent `LeadsTabView`'s ZStack still exists in the navigation stack, so theoretically two atmospheres could overlap if SwiftUI doesn't cull the unmounted view. In practice, NavigationStack hides the parent during the push, so only one renders at a time. Worth a visual sanity check on a slow-animation device.
**Fix:** None required; verify visually.

---

## Sections that passed audit

The following dimensions had zero CRITICAL findings — engineers reading the audit should treat these as confidently shipped:

- **Anti-pattern compliance (B1, B2, B3, B4, B5, B6, B7, B8)**: Accent allowlist honored, no colored-rail cards, no springs, no shadows, no emoji, no exclamation marks, no coaching language, no 999px-pill chrome.
- **Voice & copy (C1, C2, C3, C4, C5)**: `//` prefix throughout, UPPERCASE-for-authority + sentence-case-content discipline, all numbers formatted, no marketing voice, no first-person.
- **Surface hierarchy (D1, D2, D3, D4)**: L1/L2 correctly selected; no triple-glass nesting; no legacy `cardBackground` in rebuild code.
- **Mobile contrast (E1, E2)**: `-M` earth-tone variants used universally for tags/cards; `text3`/`textMute` reserved for metadata.
- **Empty/error states (G1, G3)**: `00` + `// — NO X` pattern consistent; error copy names the thing + offers next action.
- **Motion (H1)**: Single curve throughout. Toast handles reduced-motion explicitly.
- **Cleanup (J1, J2, J3)**: Legacy `Books/Pipeline/*` and all six Phase-1 LEADS file orphans deleted; VM dead code removed; spec supersede banner in place.
- **Plan decisions (I1)**: 6-of-6 Q-decisions (Q1 hide-delta-when-nil, Q2-deferred, Q3 every-exit-marks-won, Q4 filter-icon-deleted, Q5 LeadLogActivitySheet-built, Q6 carousel) all implemented as decided. Wave 1 polish (P1-1 toast, P1-2 photo bible, P1-3 forecast/velocity, P1-4 site-visit photos in RPC) all landed.
- **Drift register closeout (I2)**: Items #1 (carousel removed), #2 (accent leakage), #3 (rounded-card-with-rail) all genuinely resolved.

Also notable:
- **`LeadConversionService` is atomic and well-designed** — RPC-backed transaction with typed error mapping (`opportunity_not_found` / `access_denied` / `projectCreatedButFetchFailed`). Pre-flight checks against SwiftData for DUPLICATE-EXISTS and CLIENT-HAS-OTHERS states. Idempotent escape-hatch (`markWonNoProjectSilently`) tolerates network failure.
- **Toast surface (P1-1)** is the cleanest piece in the rebuild. Tone palette, accessibility hint, dismiss-on-tap, reduced-motion-aware enter/exit, JBM-Mono `//` styling (modulo the system-mono drift flagged above).
- **Triage bucketize logic (`PipelineViewModel.triageBuckets`)** correctly mirrors the prototype's `bucketize()` with right edge-cases (won → unconvertedWon, lost → excluded, `lastMessageDirection == "in"` → waitingOnYou unless newLead, etc.). Sort orders within buckets all match the "stale first, then lastActivityAt desc" rule.

---

## Recommendations

1. **Spawn Wave 2 polish to address the 7 CRITICAL findings:**
   - Wire the pipeline footer's row tap and "OPEN STAGE BOARD →" link (LeadsTabView.swift:125-126) to a filtered single-stage list view.
   - Add Won/Lost to the pipeline footer's stage list (PipelineFooter.swift:35-37) per design-intent §23 #5 — or document the deferral.
   - Bump touch targets: `QuickGlyph` (34→44pt), `WonConvertCard` buttons (40→44pt), Convert sheet project chips (32→44pt), `FilterChipRow` chips (36→44pt or extend hit area), `LeadChipPicker` chips (same).

2. **Schedule the 18 WARNING findings for the next polish wave:**
   - Token cleanup pass (Atmosphere RGB literals → `OPSStyle.Colors.*`; `Color.white.opacity(N)` literals → `surfaceInput`/`fillNeutralDim`/`surfaceActive`/`line`; Toast system mono → `Typography.metadata`; two `cornerRadius: 5/6` literals → tokens).
   - Type-floor lift: bump 8.5pt and 9pt mono labels to 9.5pt (mobile floor) on `SubMetric.hint`, `DetailHero.KvCell.sub`, `LeadActionCard.row3` due chip and REFERRAL caption.
   - Button-flex-ratio bug across 5 sheets (`.frame(maxWidth: .infinity * 2)` is a no-op).

3. **Defer the 13 INFO findings to the next polish cycle or roll into design system maintenance:**
   - MOBILE.md §6.3 spec drift (sheet titles use `//` mono instead of Cake Mono 22) — decide doc revision vs. implementation revision.
   - Stale doc-comment references to deleted symbols (PipelineStage+Color, HeroWidget).
   - Optional `Typography.Mobile` enum to consolidate `Font.custom("Mohave-Light", size: 38/22/18)` chains.
   - Loading skeletons for first-paint.
   - `Color.black` → `invertedText` token discipline.

4. **Escalate to PM / design system maintainer:**
   - MOBILE.md §4.3 says filter chips "min 36pt height", but CLAUDE.md and DESIGN.md §15 mandate 44pt universal. Reconcile or scope a per-component exception.
   - Convert flow deep-links to the new project; prototype/designer README said the operator stays on LEADS. Confirm the PM call is final, or implement the alternative.
   - Pipeline footer Won/Lost surfacing — if not implementing soon, formally close out design-intent §23 #5 with the new direction.

5. **The rebuild is otherwise ready to ship.** Anti-pattern discipline, voice consistency, surface hierarchy, mobile contrast, and motion are all clean. The CRITICAL findings cluster around two themes — touch-target sizing and the unfinished pipeline-footer drill-down — both addressable in a tight Wave 2 pass without revisiting core architecture.
