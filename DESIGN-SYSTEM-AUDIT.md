# iOS Design-System Audit

Audit pass over the iOS Swift sources in this worktree against the canonical OPS
visual system (`OPS/Styles/OPSStyle.swift`, `Styles/Components/`, the cross-platform
spec in `ops-design-system/project/DESIGN.md`, and the mobile overrides in
`ops-design-system/project/mobile/MOBILE.md`).

Scope: `OPS/**/*.swift` (951 production files). Excludes `Preview Content`,
`OPS/Tests`, `OPSTests`, `OPSUITests`, and the token sources themselves
(`OPS/Styles/OPSStyle.swift`, `OPS/Styles/Fonts.swift`, `OPS/Styles/Animation+OPS.swift`,
`OPS/Styles/Components/**`).

Counts are best-effort tallies from systematic grep sweeps — every category was
sampled meaningfully but not enumerated line-by-line.

## Top-line summary

| # | Category | Total | Severity |
|---|----------|------:|----------|
| 1 | Hardcoded colors (named, RGB, hex, UIColor system) | ~349 | High |
| 2 | Hardcoded spacing (`.padding(N)`, `.padding(.x, N)`, literal `.frame`, `Spacer().frame`) | ~4,673 | High |
| 3 | Hardcoded fonts (`.font(.system(size:))`, non-brand `Font.custom`, `.system(...design:.monospaced)`) | ~422 | High |
| 4 | Hardcoded corner radii (`.cornerRadius(N)`, `RoundedRectangle(cornerRadius: N)`) | ~163 | Medium |
| 5 | Touch-target violations (interactive elements <44pt) | ~30+ confirmed; ~297 candidates | Medium |
| 6 | Min font-size violations (<11pt) | ~60 | High |
| 7 | Shadow violations on dark canvas | ~30 (excluding documented floating-CTA exception) | High |
| 8 | Motion violations (`spring`, `easeIn/Out`, `linear`) | ~528 (109 spring + 391 other ease + ~5 default + ~23 OPSStyle.spring aliases) | High |
| 9 | Accent misuse (steel blue as fill / foreground beyond CTA + focus ring) | ~592 broad call sites; conservative confirmed misuse ~80–120 | High |
| 10 | Mid-grey on canvas (`Color.gray` / `Color(white:0.x)` fills/bgs) | ~13 confirmed in non-debug code; 31 incl. debug | Low–Medium |

The iOS app is *not* close to compliant. Counts in items 2, 3, 8, 9 each individually
exceed what a single design-system pass can fully resolve — they justify a multi-phase
campaign, not a single touch-up.

---

## 1. Hardcoded colors  ·  ~349 violations  ·  High

Anything that isn't routed through `OPSStyle.Colors` (or one of its semantic
aliases like `opsAccent`, `text`, `olive`, `tan`, `rose`, `brick`). Worst-case
patterns:

- `Color(hex:"#…")` literals: **216** call sites outside `OPSStyle`.
- `Color(red:…, green:…, blue:…)` literals: **88**.
- `Color.red / .blue / .green / .orange / .yellow / .purple / .gray / .cyan / .teal`: **40** (most are debug, tutorial, deck-builder, calendar legend swatches).
- `UIColor.systemRed / systemBlue / systemGreen / systemOrange / .cyan`: **5**.

Representative examples:

- `OPS/Views/JobBoard/TaskTypeSheet.swift:1536` — entire file uses 40 `Color(hex:)` literals for task-type chip colors.
- `OPS/Map/Core/OPSMapStyle.swift` — 38 `Color(hex:)` literals (the entire map palette is hand-rolled).
- `OPS/Tutorial/TutorialData.swift:33-197` — 19 `Color(hex: "#…")` literals seeding tutorial data; every one duplicates an existing token (`#9DB582` = `olive`, `#B58289` = `rose`, `#8195B5` ≈ `opsAccent`).
- `OPS/DataModels/Enums/PipelineStage+Color.swift:15-22` — second copy of pipeline-stage colors hardcoded in RGB tuples; canonical `OPSStyle.Colors.pipelineStageColor(for:)` exists in `OPSStyle.swift:244-254`.
- `OPS/V2/CertificationsSettingsView.swift:39-43,281` — `Color.green / .red / .orange` used directly for cert-status semantics (should be `olive / brick / tan`).
- `OPS/DeckBuilder/3D/DeckSceneBuilder.swift:15-25` — 10 `UIColor(red:green:blue:)` material constants. SceneKit needs `UIColor`, so the *fix* is to define `UIColor` mirrors of the token palette in `OPSStyle` rather than scatter the values.
- `OPS/DeckBuilder/Rendering/DeckShareRenderer.swift:10-15` — duplicate `accentColor = #597794` (not the brand `#6F94B0`).
- `OPS/Measurement/RenderedPhotoComposer.swift:80-445` — ~12 `UIColor.black / .white / UIColor(red:…)` literals across photo composition.
- `OPS/Views/Calendar Tab/Components/UserEventSheet.swift:861-863` — `Color.blue / .orange / .green` legend dots.
- `OPS/Views/Debug/DeveloperDashboard.swift:63-72` — `Color.blue / .green / .orange / .teal / .purple / .cyan` per debug-tile; acceptable in debug, but should still map to text colors.
- `OPS/Onboarding/Views/Components/OnboardingComponents.swift:52,186,191` — `Color.gray` for inactive step / disabled CTA borders (should be `textMute` or `text3`).
- `OPS/Onboarding/Views/OnboardingPreviewHelpers.swift:17,20` — `Color.blue / .gray` as preview-stub stand-ins for `primaryAccent / secondaryText`. The comment admits it: "Use actual accent color in real app".

**Recommended fix.** For each hex/RGB call: identify the closest token in `OPSStyle.Colors` (semantic intent first — is it status, accent, text, or surface?). Replace. For `UIColor` call-sites in CoreGraphics / SceneKit / PDF rendering, extend `OPSStyle.Colors` with `UIColor` mirrors (e.g. `static let opsAccentUI = UIColor(named: "AccentPrimary")!`) so renderers can resolve tokens too. Centralize **all** task-type, pipeline-stage, and map-pin palettes onto the existing helpers (`OPSStyle.Colors.pipelineStageColor(for:)`, etc.) instead of duplicating swatches inline.

---

## 2. Hardcoded spacing  ·  ~4,673 violations  ·  High

Three subcategories:

| Subcategory | Count |
|---|---:|
| `.padding(.x, N)` with literal N | 3,119 |
| `.frame(width: N, height: N)` with literal N | 1,234 |
| `.padding(N)` (omnidirectional) literal | 281 |
| `Spacer().frame(width:/height: N)` literal | 39 |

Representative examples (top offenders):

- `OPS/Tutorial/V2/TutorialFlowViewV2.swift` — 74 directional-padding literals in one file (e.g. `.padding(.horizontal, 24)` at multiple call sites).
- `OPS/Tutorial/TutorialFlowView.swift` — 60 directional-padding literals (`.padding(.horizontal, 12)` at line 333, `.padding(.bottom, 90)` at line 29).
- `OPS/Views/Calendar Tab/MonthGridView.swift` — 43 literals.
- `OPS/Views/SettingsView.swift` — 39 literals.
- `OPS/Views/Settings/Organization/ManageTeamView.swift` — 39.
- `OPS/Views/Settings/NotificationSettingsView.swift` — 39.
- `OPS/Views/Settings/ProfileSettingsView.swift` — 37.
- `OPS/Views/JobBoard/JobBoardView.swift` — 36 literals (e.g. `.padding(.horizontal, 16)` x N).
- `OPS/Views/Subscription/SubscriptionLockoutView.swift` — 33 literals (this is a high-visibility upgrade flow).
- `OPS/Tutorial/Steps/EstimateApprovedStep.swift:200` — `.frame(width: 24, height: 24)` (icon size; should be `OPSStyle.Layout.IconSize.lg`).
- `OPS/Views/Pipeline/LogActivitySheet.swift` — 32 literals.

The literal-value distribution skews to the same handful of numbers (`4, 8, 10, 12, 14, 16, 20, 24, 32`) — every one maps to an existing token: `spacing1=4`, `spacing2=8`, `spacing2_5=12`, `spacing3=16`, `spacing3_5=20`, `spacing4=24`, `spacing5=32`. Literal `10`/`14` are off-grid and should round to the nearest token after a UX call.

**Recommended fix.** Bulk-replace via mechanical mapping:

| Literal | Token |
|---:|---|
| 4 | `OPSStyle.Layout.spacing1` |
| 8 | `OPSStyle.Layout.spacing2` |
| 12 | `OPSStyle.Layout.spacing2_5` |
| 16 | `OPSStyle.Layout.spacing3` |
| 20 | `OPSStyle.Layout.spacing3_5` |
| 24 | `OPSStyle.Layout.spacing4` |
| 32 | `OPSStyle.Layout.spacing5` |
| 10, 14, 15, 18, 22, 28 | round to nearest token after PR review |

For `.frame(width: N, height: N)` icon containers (16/20/24/32/48): swap to `OPSStyle.Layout.IconSize.{sm,md,lg,xl,xxl}`. For Spacer literals: replace with the spacing tokens of equivalent value.

---

## 3. Hardcoded fonts / non-brand fonts  ·  ~422 violations  ·  High

| Subcategory | Count |
|---|---:|
| `.font(.system(size: N))` with literal N | 359 |
| `.system(size: N, … design:.monospaced)` (legacy mono — should be `JetBrains Mono`) | 57 |
| `Font.custom("Kosugi-Regular", …)` (retired font, still bundled?) | 6 |

The retired-font cases are a hard violation — Kosugi was removed from the bundle per `Fonts.swift:12`:

- `OPS/Views/Components/Common/TaskBadge.swift:25-28` — 4 `Font.custom("Kosugi-Regular", …)` per `BadgeSize` case. The whole struct needs to map onto `Font.tagLabel / .miniLabel / .microLabel / .smallCaption` (already remapped to JetBrains Mono in `Fonts.swift:182-200`).
- `OPS/Views/Inventory/InventoryListView.swift:104,108` — 2 more Kosugi references.

Top `.system(size:)` offenders:

- `OPS/Tutorial/V2/TutorialFlowViewV2.swift` — 29 sites (e.g. `.font(.system(size: 11))` at line 816, `.font(.system(size: 22))` at line 945).
- `OPS/Tutorial/TutorialFlowView.swift` — 21 sites.
- `OPS/DeckBuilder/AR/ARPerimeterView.swift` — 17 sites, all `design: .monospaced` (e.g. `.font(.system(size: 9, weight: .bold, design: .monospaced))` at line 218 — replace with `Font.metadata` / `Font.dataValue`).
- `OPS/Views/Components/SyncStatusSection.swift` — 12 sites (the sync banner uses literal sizes throughout).
- `OPS/DeckBuilder/AR/ARHeightMeasureView.swift` — 11 sites.
- `OPS/DeckBuilder/Views/PropertySheetView.swift` — 10 sites.
- `OPS/DeckBuilder/Views/TemplateDimensionInputView.swift` — 9 sites.

System-mono replacements: every `.system(size: N, weight:, design: .monospaced)` should resolve to one of `Font.panelTitle / .dataValue / .dataValueLg / .category / .metadata / .miniLabel / .microLabel / .smallCaption` based on its semantic role (panel title, hero number, micro label, etc.).

**Recommended fix.** Map literals to roles. Most common literal sizes and target roles:

| Literal pt | Likely role | Token |
|---:|---|---|
| 11, 12 | metadata, category | `Font.metadata` / `Font.category` / `Font.smallCaption` |
| 13 | data value | `Font.dataValue` |
| 14 | small body / caption | `Font.smallBody` / `Font.caption` |
| 18 | section / preview | `Font.section` / `Font.previewLabel` |
| 20 | hero metric | `Font.dataValueLg` |
| 22 | page title / subtitle | `Font.pageTitle` / `Font.subtitle` |

Kosugi: delete `TaskBadge` and `InventoryListView` Kosugi calls — replace with `Font.tagLabel` / `Font.smallCaption` (both already JetBrains Mono per `Fonts.swift:190,148`).

---

## 4. Hardcoded corner radii  ·  ~163 violations  ·  Medium

| Subcategory | Count |
|---|---:|
| `RoundedRectangle(cornerRadius: N)` literal | 139 |
| `.cornerRadius(N)` modifier literal | 24 |

Top offenders:

- `OPS/Views/JobBoard/TaskTypeSheet.swift` — 12 hardcoded `RoundedRectangle(cornerRadius: N)`.
- `OPS/Map/Views/ProjectPinCard.swift` — 8.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift` — 7 (most are `cornerRadius: 1` for progress bars; should be `OPSStyle.Layout.progressBarRadius` = 2).
- `OPS/Views/Calendar Tab/Components/CalendarUserEventCard.swift` — 6.
- `OPS/Tutorial/TutorialFlowView.swift` — 6.
- `OPS/Map/Views/NavigationHeader.swift` — 6.
- `OPS/Views/Pipeline/LogActivitySheet.swift:226` — `.cornerRadius(20)` — far above any token; round to `panelRadius` (10) or `modalRadius` (12).
- `OPS/Views/Books/Components/PeriodPill.swift:47` — `.cornerRadius(12)` — should be `modalRadius` (12) but token name fits better; pill use-case may want `chipRadius`(4) for tactical look.
- `OPS/Views/Review/TaskBioSheet.swift:124` — `.cornerRadius(2)` — `progressBarRadius` (2).
- `OPS/DeckBuilder/Views/DeckToolbar.swift:110,264,332,617` — 4 sites at `cornerRadius: 4` (= `chipRadius`).

**Recommended fix.** Map every literal to a `OPSStyle.Layout` token:

| Literal | Token |
|---:|---|
| 2 | `OPSStyle.Layout.progressBarRadius` |
| 4 | `OPSStyle.Layout.chipRadius` |
| 5 | `OPSStyle.Layout.buttonRadius` / `cornerRadius` |
| 6 | `OPSStyle.Layout.cardRadius` / `sidebarHoverRadius` |
| 8, 10 | `OPSStyle.Layout.panelRadius` |
| 12 | `OPSStyle.Layout.modalRadius` |
| 1, 20, etc. | round to closest token (1 → 2, 20 → 12) |

---

## 5. Touch-target violations  ·  ~30 confirmed; ~297 candidates  ·  Medium

`OPSStyle.Layout.touchTargetMin = 44.0`. Field-first CLAUDE.md prefers 60pt for primary actions.

Filtering for interactive elements (`Button(` / `.onTapGesture`) within a few lines of a sub-44pt `.frame`:

Confirmed violations (button frames under 44pt):

- `OPS/Views/Measurement/Components/ExportSheet.swift:95` — `Button` content with `.frame(width: 28, height: 28)`.
- `OPS/Views/JobBoard/ProjectFormSheet.swift:2073` — Button `.frame(width: 24, height: 24)`.
- `OPS/Views/JobBoard/TaskManagementSheets.swift:179` — `.frame(width: 3, height: 30)` on tappable bar.
- `OPS/Views/JobBoard/JobBoardProjectListView.swift:728,791,872` — tap targets at 20×20 and 8×8.
- `OPS/Views/JobBoard/ProjectManagementSheets.swift:181,465` — 3×30 and 12×12 tappable.
- `OPS/Views/JobBoard/JobBoardView.swift:1301` — 20×20 button.
- `OPS/Views/Components/Images/PhotoAnnotationView.swift:143` — annotation handle at 20×20.
- `OPS/Views/Components/Images/PhotoCommentViewer.swift:288,623` — comment buttons at 20×20 / 24×24.
- `OPS/Views/Components/Project/Tabs/ActivityEntryView.swift:224` — 24×24 button.
- `OPS/Views/Components/Project/Tabs/ActivityTabView.swift:232` — 32×32 button.
- `OPS/Views/LandingView.swift:595` — 40×40 button (so close — bump to 44+).

Most `.frame(width: N, height: N)` with N<44 are non-interactive (dots, progress segments, indicator circles — see `Tutorial/*.swift`, `.frame(width: 5, height: 5)` etc.). Only ~30 are inside or directly adjacent to a tappable. A targeted manual sweep is required to confirm each one.

**Recommended fix.** For every interactive element under 44pt:
1. Add `.contentShape(Rectangle())` and wrap with `.frame(minWidth: 44, minHeight: 44, alignment: .center)` so the visual stays small but the hit-target meets HIG.
2. Or replace with `OPSStyle.Layout.touchTargetMin / .touchTargetStandard / .touchTargetLarge` directly when the visual is permissive of a larger target.
3. The 8×8 pins in `JobBoardProjectListView` look ornamental — confirm they are actually tap-handlers, not just visual dots.

---

## 6. Min font-size violations  ·  ~60 violations  ·  High

Spec floor is 11pt. Anything <11pt is a violation. Sample:

- `OPS/Tutorial/TutorialFlowView.swift:2628` — `.font(.system(size: 8, weight: .bold))`.
- `OPS/Tutorial/Steps/EstimateApprovedStep.swift:142` — `.font(.system(size: 9))`.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift:3151,3356,3381,3391` — 4 sites at 7-9pt.
- `OPS/DeckBuilder/AR/ARPerimeterView.swift:218,259,576` — 7-9pt mono in AR overlay.
- `OPS/Views/Settings/AllPhotosGalleryView.swift:626` — `.font(.system(size: 9))`.
- `OPS/Views/Leads/HeroWidget.swift:105` — `.font(.system(size: 9, weight: .semibold))`.
- `OPS/Views/JobBoard/JobBoardProjectListView.swift:726` — `.font(.system(size: 8, weight: .bold))`.
- `OPS/Views/JobBoard/JobBoardView.swift:1299` — `.font(.system(size: 8, weight: .bold))`.
- `OPS/Views/Books/Cards/ARCard.swift:221` — `.font(.system(size: 9, weight: .regular))`.
- `OPS/Views/Books/Components/PeriodPill.swift:37` — `.font(.system(size: 9, weight: .semibold))`.
- `OPS/Views/Books/Components/BooksDrillTile.swift:57` — `.font(.system(size: 9, weight: .regular))`.
- `OPS/Views/Inventory/Import/ColumnMappingView.swift:293,312` — 9pt bold.
- `OPS/Map/Views/ProjectPinCard.swift:121` — `.font(.system(size: 8, weight: .medium))`.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift:3381` — **7pt** (the smallest single instance).

The AR-overlay cases (`ARPerimeterView`) are the most defensible — overlay text on a live camera feed has aggressive space constraints — but spec floor still applies on the iOS surface.

**Recommended fix.** Round every literal up to **11pt minimum** using existing tokens (`Font.miniLabel` is 10pt — needs to be raised to 11 or replaced with `Font.metadata`). Where the overlay genuinely cannot fit, escalate to design — do not silently keep sub-11pt.

---

## 7. Shadow violations on dark canvas  ·  ~30 violations  ·  High

Spec v2 explicitly states: zero box-shadows on dark backgrounds. Depth = glass + hairlines. Floating CTAs are the documented exception (a single floating action bar).

`OPSStyle.Layout.Shadow` is marked DEPRECATED in `OPSStyle.swift:457-463`. Active offenders:

- `OPS/DeckBuilder/Views/DeckBuilderView.swift:81,216,295,502,523,544,614,821,849,895` — **10 shadows**, all `.shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)`. The entire deck-builder surface trades hairlines for soft shadows.
- `OPS/DeckBuilder/AR/ARPerimeterView.swift:246,302,488` — 3 shadows.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift:749,3022,3155` — 3 shadows (2 of those are white glow halos, not standard black drop shadows — closer to "accent halo" violations).
- `OPS/Views/Review/UnscheduledTaskReviewView.swift:429` — `.shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)` on a review card.
- `OPS/Views/Measurement/DimensionedCaptureView.swift:622` — shadow on a measurement overlay.
- `OPS/Views/Measurement/Components/MeasureLoupe.swift:75` — shadow on a loupe.
- `OPS/Views/Measurement/Components/HelperTextOverlay.swift:55` — shadow on helper text.
- `OPS/Views/JobBoard/TaskTypeSheet.swift:1536` — `.shadow(color: OPSStyle.Colors.primaryAccent.opacity(0.35), radius: 8, y: 2)` — accent-tinted shadow (also an accent misuse).
- `OPS/Views/Components/Common/PushInMessage.swift:197` — `OPSStyle.Colors.shadowColor, radius: 10, x: 0, y: 4` — uses token color but still a shadow on dark.
- `OPS/Views/Inventory/Insights/Components/ConsumptionChart.swift:258` — chart shadow.
- `OPS/Onboarding/Views/Screens/CompanyCodeDisplayView.swift:219`, `CrewCodeShareView.swift:160` — onboarding sheet shadows.
- `OPS/Tutorial/TutorialFlowView.swift:443` — large multi-line shadow block on the lead card.

Defensible exception: floating CTAs (e.g. `OPSFloatingButtonBar`) — spec allows shadows here. None of the above are floating CTAs.

**Recommended fix.** Delete every `.shadow(…)` modifier. Replace any depth communication with `.glassSurface()` / `.glassDense()` modifiers (defined in `Styles/Components/GlassSurface.swift`) plus 1pt hairlines using `OPSStyle.Colors.line` / `glassBorder`. For the deck-builder card stack, this is a measurable visual refactor — every card in `DeckBuilderView` likely needs the glass treatment.

---

## 8. Motion violations  ·  ~528 violations  ·  High

`OPSStyle.Animation` is unambiguous: one curve, no spring (drag-reorder excepted), reduced-motion respected. In practice:

| Subcategory | Count |
|---|---:|
| `.spring(…)` / `withAnimation(.spring(…))` direct call | 109 (plus ~27 indirect via `OPSStyle.Animation.spring` alias) |
| `.easeInOut(…) / .easeIn(…) / .easeOut(…) / .linear(…)` direct call | 391 |
| `withAnimation()` / `withAnimation(.default)` | 5 |
| Bouncy / interactiveSpring / interpolatingSpring | 0 |

Top spring offenders:

- `OPS/Views/Components/Map/ProjectMapView.swift` — 8 spring sites.
- `OPS/Views/Components/Common/PushInMessage.swift` — 7.
- `OPS/Views/Components/Project/ProjectDetailsView.swift` — 6.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift` — 6 direct spring calls (plus 108 ease* calls).
- `OPS/Views/LandingView.swift` — 5.
- `OPS/Wizard/Views/WizardOverlayWindow.swift:181-184` — 4 springs (overlay enter/exit).
- `OPS/Views/JobBoard/JobBoardProjectListView.swift` — 4.
- `OPS/Views/Calendar Tab/Components/CalendarDaySelector.swift` — 4.
- `OPS/Views/SplashScreen.swift:65` — `Animation.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)` on splash (high-visibility first impression).
- `OPS/Views/MainTabView.swift:284,410` — tab switch spring.

Top easing-misuse offenders:

- `OPS/Tutorial/V2/TutorialFlowViewV2.swift` — **108** `.easeIn/.easeOut/.easeInOut` calls (single largest concentration).
- `OPS/Tutorial/TutorialFlowView.swift` — **75** calls.
- `OPS/Views/Components/FloatingActionMenu.swift` — 10.
- `OPS/Tutorial/Steps/InvoiceAndPayStep.swift` — 9.
- `OPS/DeckBuilder/Views/DeckBuilderView.swift` — 7.
- `OPS/Views/Components/Images/PhotoCommentViewer.swift` — 6.

Even `OPSStyle.Animation.fast` and `.faster` (lines 586-587 of `OPSStyle.swift`) are themselves `.easeInOut` / `.easeOut` — they need to be retired in favor of `.hover` / `.panel` / `.page` (the canonical curve).

**Recommended fix.** Two-stage migration:

1. Find/replace `withAnimation(.spring(response: X, dampingFraction: Y))` → `withAnimation(OPSStyle.Animation.panel)` for sheet/overlay enter-exit, `.page` for navigation, `.hover` for hover-equivalents.
2. Find/replace `.easeInOut(duration: T)` → choose the OPSStyle preset whose duration is closest (`.hover` 150ms, `.panel` 200ms, `.page` 250ms, `.flip` 350ms).
3. Drag-reorder exception: keep spring **only** for the `.onDrag` list-reorder gestures; tag those call-sites with `// drag-reorder exception` comments.
4. After migration, **delete** `OPSStyle.Animation.spring` / `.springFast` / `.fast` / `.faster` from `OPSStyle.swift:586-591` so future code can't reach for them.

---

## 9. Accent misuse  ·  conservative ~80–120 confirmed; ~592 total accent usages worth review  ·  High

The rule: `opsAccent` / `primaryAccent` = primary CTA + focus ring **only**. Anything else (icons, dot indicators, decorative shapes, foreground tints, fills not on a CTA) is a violation.

Broad usage counts:

| Usage shape | Count |
|---|---:|
| `.foregroundStyle(…primaryAccent)` / `.foregroundColor(…primaryAccent)` | 516 |
| `.fill(…primaryAccent)` | 76 |
| Total `primaryAccent / opsAccent` references in code | 1,428 |

Most foreground use is on text and icons — not CTA text. Representative misuses:

- `OPS/Tutorial/TutorialFlowView.swift:395,516,527,1258,1518,1558,1630,1650,2510` — `.foregroundStyle(OPSStyle.Colors.primaryAccent)` on icons, chevrons, decorative dots throughout the tutorial.
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift:821,831,898,1063,1705,1836` — same pattern (`.fill(primaryAccent)` on dots and progress shapes).
- `OPS/Tutorial/Steps/SendEstimateStep.swift:54,119` — accent on icon + decorative fill.
- `OPS/Tutorial/Steps/InvoiceAndPayStep.swift:166,220` — accent on dots/fills.
- `OPS/DeckBuilder/Views/AssignmentWheelView.swift:252` — accent fill on wheel segment.
- `OPS/DeckBuilder/Views/SketchCaptureView.swift:379,603,709` — accent fill on sketch tool decorations.
- `OPS/Views/JobBoard/TaskTypeSheet.swift:1536` — accent-tinted *shadow* (also a shadow violation).
- `OPS/Tutorial/V2/TutorialFlowViewV2.swift:1420` — accent on `Image(systemName: "checkmark.circle.fill")` — should be `olive` (success semantic).
- `OPS/Tutorial/Steps/EstimateApprovedStep.swift:141` — accent on `Image(systemName: "arrow.right")` — directional icon, should be `text` or `text2`.

The widespread accent foreground use on selected tab indicators, today-pill calendar highlights, etc., requires a UX call per surface: some are arguably "focus state" (allowed), most are decorative or status (need re-tint to `olive` / `tan` / `text` / `text2`).

**Recommended fix.** Three-bucket triage per call site:

1. **Keep accent** — primary CTA backgrounds, focus rings around inputs, currently-focused/active step indicator. Document with a `// CTA` / `// focus` comment.
2. **Re-tint to status token** — completion/success → `olive`; warning/attention → `tan`; error/cost → `rose` or `brick`.
3. **Re-tint to text/surface token** — icons, chevrons, decorative dots, separator highlights → `text2` / `text3` / `line` / `glassBorder`.

This is the single largest semantic refactor in the audit — the accent color is currently doing the job of "anything important," not "the one CTA."

---

## 10. Mid-grey on canvas  ·  ~13 (non-debug) violations  ·  Low–Medium

The canvas is pure `#000000`. There should be no `Color.gray` / `UIColor.systemGray` / `Color(white: 0.x)` fills sitting on the canvas.

Findings:

- `OPS/Utilities/UIComponents.swift:165` — `.background(Color(white: 0.1))` — used in shared utility code; high-leverage fix.
- `OPS/Views/Calendar Tab/Components/CalendarDaySelector.swift:228` — `Color(white: 0.55)` — personal-event chip color.
- `OPS/Views/Components/Map/ProjectMapAnnotation.swift:198` — `Color.gray.opacity(0.3)`.
- `OPS/Onboarding/Views/OnboardingFlowPreview.swift:67,213,295` — 3 `.background(Color.gray.opacity(0.1))` in onboarding preview.
- `OPS/Onboarding/Views/Screens/CompletionView.swift:96` — `.background(Color.gray.opacity(0.2))`.
- `OPS/Onboarding/Views/Components/OnboardingComponents.swift:52,186,191` — 3 `Color.gray` in onboarding steppers/buttons.
- `OPS/Onboarding/Views/Screens/FieldSetupView.swift:173` — fallback to `Color.gray` when not light-themed.
- `OPS/Measurement/PDFExporter.swift:122,131,151,155,199,223,236` — 7 `UIColor(white: 0.x)` in PDF export (acceptable — PDFs render on white paper, not the OPS canvas).
- `OPS/DeckBuilder/AR/ARLineRenderer.swift:45` — `UIColor(white: 0.6)` for house-edge — AR overlay context.
- `OPS/DeckBuilder/Rendering/DeckRenderer.swift:92,188` — gray fallbacks in deck rendering.
- `OPS/Views/Debug/TaskTestView.swift:31,143,180` — debug-only.
- `OPS/Views/Debug/TaskTypesDebugView.swift:313` — debug-only.
- `OPS/Tests/MapTapGestureTest.swift:117,124` — test file (out of audit scope).

**Recommended fix.** Replace every instance with one of:

- `OPSStyle.Colors.surfaceHover` (5% white) for hover-state row backgrounds,
- `OPSStyle.Colors.fillNeutralDim` (6% white) for subtle track backgrounds,
- `OPSStyle.Colors.line` (10% white) for separators,
- `OPSStyle.Colors.textMute` for muted text/icons,
- For PDFExporter: keep but document as PDF-canvas-only and consider hoisting to a `PDFPalette` namespace so PDFs and the iOS canvas have their own token sets.

---

## Top 10 most-impactful fixes

Numbered by **leverage** — each item, fully resolved, removes the largest number of violations or addresses the highest-visibility surface.

1. **Tutorial system overhaul** (`OPS/Tutorial/V2/TutorialFlowViewV2.swift`, `OPS/Tutorial/TutorialFlowView.swift`). These two files contain the largest single concentrations of violations across the codebase: ~134 padding literals, ~50 font-size literals, ~13 corner-radius literals, 183 easing/spring violations, 19 `Color(hex:)` data values, and the most accent-misuse cases. A focused pass on these two files would eliminate roughly 15–20% of all violations in the audit. Begin by replacing every `.easeIn/.easeOut/.easeInOut` with `OPSStyle.Animation.{hover,panel,page,flip}`, every literal `.padding(.x, N)` and `RoundedRectangle(cornerRadius: N)` with the matching token, and triaging accent uses (most should become `olive` for success, `text2` for icons).

2. **Eliminate `Color(hex:)` duplication** of palette colors (`OPS/Tutorial/TutorialData.swift`, `OPS/DataModels/Enums/PipelineStage+Color.swift`, `OPS/DeckBuilder/3D/DeckSceneBuilder.swift`, `OPS/DeckBuilder/Rendering/DeckShareRenderer.swift`). Every hex in these files maps to an existing token. Delete `PipelineStage+Color.swift` entirely — `OPSStyle.Colors.pipelineStageColor(for:)` is the single source of truth. Then port the SceneKit/PDF call-sites to `UIColor` mirrors of the tokens defined in `OPSStyle`.

3. **Delete deprecated `OPSStyle.Animation.spring / .springFast / .fast / .faster`** (`OPSStyle.swift:586-591`) after migrating call sites. As long as these aliases exist, code can satisfy "uses OPSStyle" while still violating the no-spring rule. Replace with hard compile errors that point migrators to `.hover` / `.panel` / `.page` / `.flip`.

4. **Delete `OPSStyle.Layout.Shadow`** (`OPSStyle.swift:457-463`) after stripping the 30 active `.shadow(…)` call sites. Start with `OPS/DeckBuilder/Views/DeckBuilderView.swift` (10 shadows on the deck card stack) — that single file is 1/3 of the shadow problem. Replace with `.glassSurface()` modifier from `Styles/Components/GlassSurface.swift`.

5. **Kosugi font removal** (`OPS/Views/Components/Common/TaskBadge.swift:25-28`, `OPS/Views/Inventory/InventoryListView.swift:104,108`). Kosugi was retired from the bundle per `Fonts.swift:12`. These 6 call sites are runtime-fragile — they fall back to system font if the resource isn't loaded. Replace with `Font.tagLabel` / `Font.smallCaption` / `Font.metadata`.

6. **Accent triage pass** across the codebase (~592 accent references). Bucket into CTA/focus (keep), status (re-tint to `olive`/`tan`/`rose`), and decorative (re-tint to `text`/`text2`/`line`). Highest priority surfaces: `MainTabView`, `JobBoardView`, `SettingsView`, the tutorial files, `WizardOverlayWindow`. Add lint guidance comment to every retained accent site so the next audit pass can grep for justified uses.

7. **`OPS/Views/JobBoard/TaskTypeSheet.swift`** — single highest-violation file outside the tutorial: 40 `Color(hex:)`, 12 `RoundedRectangle(cornerRadius:)`, 1 accent-tinted shadow, plus padding literals. The whole task-type-color system should consolidate onto a shared helper (similar to `pipelineStageColor(for:)`).

8. **Below-11pt font sweep** (~60 violations). User-facing readability regression on every count. Single-file pass through `Tutorial/`, `DeckBuilder/AR/`, `Views/JobBoard/`, `Views/Books/Components/`, `Map/Views/ProjectPinCard.swift`. Round every literal `<11` to 11pt or replace with `Font.metadata` (11pt). Where genuine space-pressure exists (AR overlays), escalate to design rather than silently keep sub-11.

9. **Touch-target sweep on JobBoard** — `OPS/Views/JobBoard/JobBoardProjectListView.swift`, `ProjectFormSheet.swift`, `JobBoardView.swift`, `ProjectManagementSheets.swift`. Multiple confirmed sub-44pt buttons. Add `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` to each, keeping the visual size with a separate inner frame.

10. **Spacing token migration via codemod**. The 4,673 spacing literals are too many to fix by hand but mechanical to replace: write a one-shot Swift script (or sed pass guarded by AST checks) that maps literal values `{4, 8, 12, 16, 20, 24, 32}` to their corresponding `OPSStyle.Layout.spacingN` tokens. Off-grid values (`10, 14, 15, 18, 22, 28`) get tagged with a comment for manual review. Even a 60% mechanical hit-rate eliminates ~2,800 violations in a single PR.

---

End of audit.
