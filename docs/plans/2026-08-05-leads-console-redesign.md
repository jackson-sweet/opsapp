# LEADS CONSOLE Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the LEADS tab console per `docs/superpowers/specs/2026-08-05-leads-console-redesign-design.md` — compressed command band, sticky inline search + sort + crew filter, assignee on cards, relocated stage browsing.

**Architecture:** Pure `LeadsQueryEngine` (search/sort/crew/roster, nonisolated, fully unit-tested) feeds a recomposed `LeadsTabView`. `LeadsSummary` is rewritten state-aware; `LeadsByStageRow` is deleted; `PipelineStageListView` gains an in-place stage switcher. `PipelineViewModel` is untouched.

**Tech Stack:** SwiftUI, SwiftData `@Query` (User roster), XCTest. iOS 17.6 deployment floor — no iOS-18-only APIs.

**Design System:** `OPS/Styles/OPSStyle.swift` tokens only; layout/type/tone decisions are LOCKED in the spec (§4–§7, §13). `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md` govern. Zero hardcoded values beyond the pre-existing literal type sizes already conventional on this surface (match neighboring code exactly).

**Required Skills:** `ops-design`, `custom-skills:audit-design-system` (at the end). Copy is LOCKED (spec §13) — do not rewrite strings. Motion: reuse `OPSStyle.Animation.standard` / existing transition patterns ONLY; introduce no new curves, durations, or spring/bounce.

**Execution discipline:**
- Repo: `/Users/jacksonsweet/Projects/OPS/ops-ios`, branch `main` (no new branch). Stage **by file name** only; never `git add -A`. No AI attribution in commits. Conventional commit messages as given per task.
- Preserve existing line endings (several files are CRLF/mixed — do not normalize).
- Before any `xcodebuild`: `ps aux | grep xcodebuild | grep -v grep` — if a sibling build is running, wait or use `-derivedDataPath .dd-leads-console`.
- Fast compile check between tasks: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (device target — NEVER a simulator destination for plain build).
- Tests run on sim: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/<Class>`.
- Never edit sources while an xcodebuild is running (stale-.o wedges).

---

## Wave A — Engine (Agent 1)

### Task 1: LeadsQueryEngine — types + search matching

**Files:**
- Create: `OPS/Utilities/LeadsQueryEngine.swift`
- Test: `OPSTests/Utilities/LeadsQueryEngineTests.swift`

**Contract (spec §6.2, §10):**

```swift
enum LeadSort: String, CaseIterable { case urgency, newest, value }

enum CrewFilter: Equatable {
    case all, mine, unassigned
    case member(String)            // stored lowercased
}

struct LeadsListControls: Equatable {
    var query: String = ""
    var sort: LeadSort = .urgency
    var crew: CrewFilter = .all
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum LeadsQueryEngine {
    /// Case- and diacritic-insensitive multi-token match. Every whitespace-
    /// separated token must hit ≥1 field: displayContactName, title,
    /// descriptionText, address, contactEmail, source, shortDisplayId.
    /// A token containing ≥3 digits also matches when its digits are a
    /// substring of contactPhone's digits.
    nonisolated static func matches(_ lead: Opportunity, query: String) -> Bool
}
```

Fold with `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`. Empty/whitespace query → `true`.

**Steps (TDD):**
1. Write failing tests: name hit, title hit, address hit, email hit, source hit, shortDisplayId hit, diacritic fold (`"Muñoz"` matches query `"munoz"`), multi-token AND (`"dana roof"` requires both), phone `"5551234"` matches formatted `"(555) 123-4567"`, 2-digit token does NOT trigger phone path, empty query passes everything. Use `Opportunity.preview(...)` builders (see `LeadsPreviewSupport.swift` / existing `Opportunity.preview` usage in `LeadTriageCard` previews) — check the actual preview factory signature before writing.
2. Run: `xcodebuild test … -only-testing:OPSTests/LeadsQueryEngineTests` → FAIL (type missing).
3. Implement minimal engine.
4. Re-run → PASS.
5. Commit: `feat(leads): LeadsQueryEngine search matching — folded multi-token + digit phone path`

### Task 2: Engine — sort + apply (population, suspension, composition)

**Files:** modify engine + tests from Task 1.

**Contract (spec §5.2, §5.4, §6.1, §6.3):**

```swift
enum LeadsQueryResult: Equatable {
    case grouped([(bucket: PipelineViewModel.TriageBucket, leads: [Opportunity])])
    case flat([Opportunity])
}

/// - No query: crew filter ANDs into every bucket; URGENCY → .grouped with
///   the existing groupOrder (overdue, dueToday, waitingOnYou, waitingOnThem, fresh —
///   match LeadsTabView.groupOrder exactly) skipping empty buckets;
///   NEWEST → .flat createdAt desc; VALUE → .flat estimatedValue desc,
///   nil-or-zero last, ties createdAt desc.
/// - Query active (isSearching): population = buckets.all + buckets.unconvertedWon,
///   crew + bucket chip SUSPENDED; matches sorted per sort (URGENCY = bucket order:
///   overdue, dueToday, waitingOnYou, fresh, waitingOnThem, then unconvertedWon,
///   preserving in-bucket order) → always .flat.
nonisolated static func apply(
    controls: LeadsListControls,
    buckets: PipelineViewModel.TriageBuckets,
    selectedBucket: PipelineViewModel.TriageBucket,
    currentUserId: String?
) -> LeadsQueryResult

nonisolated static func crewMatches(_ lead: Opportunity, filter: CrewFilter, currentUserId: String?) -> Bool
```

`crewMatches`: lowercase both sides; `.mine` false when `currentUserId` nil; `.unassigned` = nil OR empty/whitespace `assignedTo`.

Note the deliberate asymmetry (documented in spec): grouped browse order is the queue's visual order (waitingOnThem before fresh — matches `LeadsTabView.groupOrder`), search bucket order is triage-priority order (`TriageBuckets.all`). Assert both in tests against those exact sources.

**Steps:** failing tests for every bullet (incl. uppercase `assignedTo` vs lowercase filter id, selectedBucket flattening when a chip is active — mirror `effectiveBucket` fallback-to-ALL when the chosen bucket is empty) → implement → pass → commit `feat(leads): engine apply — sort modes, crew AND, search suspension`.

### Task 3: Engine — roster, gate, assignee labels

**Files:** modify engine + tests.

**Contract (spec §5.3, §6.4):**

```swift
struct CrewMember: Identifiable, Equatable {
    let id: String            // lowercased user id
    let fullName: String
    let shortLabel: String    // "JASON W" (first + last initial, uppercased); first name alone if no last
}

/// Active company users (companyId match, deletedAt == nil, isActive != false)
/// ∪ users referenced by loaded leads' assignedTo — but ONLY ids resolvable to a
/// User row (unresolvable ids are excluded; their cards read UNKNOWN).
/// Sorted by fullName (localizedCaseInsensitive). Dedupe by lowercased id.
nonisolated static func roster(users: [User], leads: [Opportunity], companyId: String?) -> [CrewMember]

/// Gate for ALL assignment chrome (crew chip + card labels): roster.count > 1.
nonisolated static func showsAssignment(roster: [CrewMember]) -> Bool

/// nil when gate closed. "UNASSIGNED" for nil/blank assignedTo. "UNKNOWN" for
/// unresolvable non-nil ids. Else roster shortLabel.
nonisolated static func assigneeLabel(for assignedTo: String?, roster: [CrewMember]) -> String?
```

Careful: `assigneeLabel` takes the gate into account via a `showsAssignment` check at the CALL site (LeadsTabView) — keep the function pure (always resolves); the view passes nil through when gated. Decide in code with a doc comment; test both layers.

**Steps:** failing tests (solo gate false; inactive/deleted excluded; departed-but-referenced included only when a User row exists; uppercase-id lead matches lowercase roster; label forms incl. single-name user; UNKNOWN path; UNASSIGNED path) → implement → pass → commit `feat(leads): engine roster + assignment gate + assignee labels`.

### Task 4: Band-state helper

**Files:** modify engine + tests.

```swift
enum LeadsBandState: Equatable { case working, quiet, emptyPipeline }
/// working when needAction > 0; quiet when needAction == 0 && openLeadCount > 0;
/// emptyPipeline when openLeadCount == 0.
nonisolated static func bandState(needAction: Int, openLeads: Int) -> LeadsBandState
```

Trivial by design — the band render must branch on ONE tested truth, not scattered conditionals. Tests: 3 branches + boundary (needAction>0 while openLeads==0 is impossible upstream but must resolve `.working` — document why). Commit: `feat(leads): band state selector`.

**Wave A gate:** `xcodebuild test … -only-testing:OPSTests/LeadsQueryEngineTests` all green; device-target build green. Report test count + names.

---

## Wave B — Components (Agent 2; sequential after Wave A)

> **Skills note for every Wave B/C task:** spec §4–§7 + §13 are the layout/copy law. OPSStyle tokens: `OPSStyle.Colors.*` (text/text2/text3/textMute, surfaceInput, line, lineSoft, background, roseTextM/tanTextM/oliveTextM, opsAccent — accent ONLY where spec says, which is NOWHERE new), `OPSStyle.Layout.*` (spacing1..spacing4, sidebarHoverRadius, chipMinHeight, touchTargetMin, panelRadius), `OPSStyle.Animation.standard`, fonts via the exact `.custom("JetBrainsMono-Medium"/"Mohave-Light"/…)` patterns neighboring code uses. Match `LeadsSummary`/`LeadTriageCard` conventions per element. Haptics: `UIImpactFeedbackGenerator(style: .light)` on selection commits only.

### Task 5: LeadsSearchBar + LeadsControlChips

**Files:**
- Create: `OPS/Views/Leads/Components/LeadsSearchBar.swift`
- Create: `OPS/Views/Leads/Components/LeadsControlChips.swift`
- Test: none (pure view; previews required)

Spec §5.1–§5.3 verbatim: 40pt field (44pt target), `surfaceInput` fill + `line` border + focus-brighten to `rgba(255,255,255,0.20)` equivalent token (`OPSStyle.Colors` — find the existing brightened-border token; if none exists, `Color.white.opacity(0.20)` is NOT acceptable — check `FormTextField.swift` for the house focus treatment and reuse it), Mohave 15 text, `Search leads` placeholder text-3, magnifier + conditional clear, `.submitLabel(.search)`, autocorrection off, autocap never.

`LeadsControlChips`: `SortChip` (Menu: URGENCY/NEWEST/VALUE, checkmark current) + `CrewChip` (Menu: ALL CREW / MINE / UNASSIGNED / divider / roster shortLabels). Chip anatomy 36pt height min (chip tier), radius `OPSStyle.Layout.tagRadius`-equivalent 4pt token (verify token name in OPSStyle — `sidebarHoverRadius` is 6; find the 4pt tag token; if OPSStyle names it differently use that), JBMono-Medium 10 tracking 1.2 uppercase; rest = inactive chip treatment, non-default = active treatment (mirror `TacticalFilterChips.swift` exactly — read it first and reuse its style constants if extractable without refactor). Labels per spec §13. Menus set bindings; light haptic on change. VoiceOver labels per spec §9.

**House-component rule (memory):** stock SwiftUI `Picker`/`Menu` default *styling* is banned — `Menu` is fine as a host but the visible chip is fully custom, matching TacticalChip.

Steps: build previews for: rest, focused-with-text, sort=NEWEST active, crew=MINE active, solo (no crew chip). Device-target build green. Commit: `feat(leads): search bar + sort/crew control chips`.

### Task 6: LeadsSummary rewrite + LeadsByStageRow deletion

**Files:**
- Rewrite: `OPS/Views/Leads/Triage/LeadsSummary.swift`
- Delete: `OPS/Views/Leads/Triage/LeadsByStageRow.swift`
- Modify: `OPS/Views/Leads/LeadsTabView.swift` (remove the `LeadsByStageRow` usage + its 22pt padding; summary now takes `onByStage: (PipelineStage) -> Void`-style callback — see below)
- Test: `OPSTests/Views/LeadsSummaryLogicTests.swift` only if you extract label-building funcs; otherwise previews.

Per spec §4 + §3: branch on `LeadsQueryEngine.bandState`. Working = hero 34 (`Mohave-Light`, existing CountUpText + tone rule) + existing breakdown + metrics line + bar row. Quiet = quiet line + metrics + bar row. Empty = metrics only (`—` for zero pipeline dollars per formatting law; OPEN 0; WON only when > 0 this month… follow spec §4.2/§3.3 exactly), no bar, no quiet line.

Bar row = one Button (44pt target): existing `stageBar` + trailing `BY STAGE ▸` (JBMono-Medium 9.5 tracking 1.2, text-3, chevron textMute). Callback: `onByStage()` with NO stage argument — LeadsTabView computes the entry stage (Task 8 helper) — keep the summary dumb.

Previews: working / quiet / empty. Delete `LeadsByStageRow.swift` in the same commit as removing its call site (project uses folder-sync — confirm no pbxproj edit needed; if explicit file refs exist, update the project file the way sibling deletions do — check `git log --diff-filter=D --stat -5` for precedent).

Device build green. Commit: `feat(leads): state-aware command band — hero/quiet/empty, metrics line, BY STAGE bar; retire stage tile strip`

### Task 7: LeadTriageCard assignee token

**Files:**
- Modify: `OPS/Views/Leads/Triage/LeadTriageCard.swift` (init + `metaRow`)
- Modify: `OPS/Views/Leads/LeadsPreviewSupport.swift` if preview env needs roster plumbing

New `var assigneeLabel: String? = nil` (default nil → zero visual change anywhere the card is used ungated: day sheet rows don't pass it; stage drill WILL pass it from Task 9). Meta row trailing cluster: `[segments] Spacer [ASSIGNEE][ · SOURCE]` — assignee JBMono-Regular 8.5 tracking 0.7 `text-3` (`UNASSIGNED` → `textMute`), source unchanged. Truncation: assignee `lineLimit(1)` + `layoutPriority` below value/name; source keeps its slot. Accessibility label append per spec §6.4. Update the card previews: two with `assigneeLabel: "JASON W"` / `"UNASSIGNED"`.

Device build green. Commit: `feat(leads): assignee token on triage card meta row`

### Task 8: PipelineStageListView stage switcher

**Files:**
- Modify: `OPS/Views/Leads/PipelineStageListView.swift`
- Test: `OPSTests/Utilities/LeadsQueryEngineTests.swift` — add `entryStage` helper tests

Add to engine (it's list logic): `nonisolated static func entryStage(counts: [(PipelineStage, Int)]) -> PipelineStage` — max open count, ties → pipeline order, all-zero → `.newLead`. Tests first.

View: `@State private var selectedStage: PipelineStage` seeded from the pushed `stage`; scrolling tab row per spec §7 pinned under the nav bar: open stages then WON, LOST; each tab `LABEL · n` JBMono 10/11, active `text` + 2pt white underline (`Rectangle` height 2), inactive `text-3`, 44pt targets, `ScrollView(.horizontal)` + edge fade masks (existing mask pattern — check `TacticalFilterChips`/day-sheet for a fade-mask precedent and copy it; if none exists use a 20pt `LinearGradient` overlay), `ScrollViewReader` to keep the active tab visible, light haptic on switch, animation `OPSStyle.Animation.standard`. Title row + atmosphere re-derive from `selectedStage`. Won/Lost lists: sort `actualCloseDate ?? createdAt` desc (extend the view's local sorted accessor; `viewModel.opportunities(in:)` already returns any stage — verify its sort suits terminal stages; if not, sort locally in the view).

Previews: quoting-active + won-active. Device build green. Commit: `feat(leads): in-place stage switcher on stage list — adds WON/LOST browsing`

---

## Wave C — Composition + proof (Agent 2 continues)

### Task 9: LeadsTabView recomposition

**Files:**
- Modify: `OPS/Views/Leads/LeadsTabView.swift`

1. `@State private var controls = LeadsListControls()`; `@Query` company users (mirror `LeadDetailView`'s `@Query private var allUsers: [User]`); derived `roster`, `showsAssignment`, `assigneeIndex` via engine (compute in one place, e.g. private computed vars).
2. Sticky `queueBand`: search row (`LeadsSearchBar` + chips from Task 5, solo-gate on crew chip) above the existing `TacticalChipRow` + hairline. Chip row + crew chip dim to 40% opacity + `allowsHitTesting(false)` while `controls.isSearching` (spec §5.4) with `OPSStyle.Animation.standard`.
3. `queueBody` branches on `LeadsQueryEngine.apply(...)`: `.grouped` → existing header+card rendering (unchanged); `.flat` → cards only; search-active adds the `// MATCHES ─── N` section line (reuse `queueSectionHeader` visual with neutral tone + count) and the NO MATCHES block (spec §6.3: `0` Mohave-Light 32 text-3, `// NO MATCHES` JBMono 10 textMute tracking 1.6, `[ CLEAR SEARCH ]` JBMono 10 tappable 44pt clearing `controls.query`).
4. Cards receive `assigneeLabel: showsAssignment ? LeadsQueryEngine.assigneeLabel(for: lead.assignedTo, roster: roster) : nil` — both in the queue AND pass-through in `PipelineStageListView` (thread the label closure or index through its init; keep one source).
5. Stage-bar wiring: `LeadsSummary(onByStage:)` → `footerStage = <engine.entryStage from viewModel counts>`.
6. Scroll: `.scrollDismissesKeyboard(.interactively)` on the console ScrollView.
7. Reset rule: controls are plain `@State` → remount resets (MainTabView `.id(selectedTab)` already remounts; verify and note in code comment only if non-obvious).
8. Sort/crew/bucket interplay: selectedBucket continues driving `TacticalChipRow`; engine receives it. Group headers show filtered counts automatically (they render from the applied result groups, not raw buckets) — chips keep raw bucket counts (they describe the queue, not the crew slice; note this in a comment — deliberate).
9. Keep the day-sheet branch untouched; all new state is console-path only.

Type-checker budget: extract `searchRow`, `controlsSection`, `flatQueue`, `noMatchesBlock` as private views/funcs; if the body strains, lift the sticky band into `LeadsQueueBand.swift` (new file) — prefer the lift if LeadsTabView grows past ~1000 lines.

Verification: device build green; run FULL leads test subset: `-only-testing:OPSTests/LeadsQueryEngineTests` plus existing leads/pipeline test classes (`grep -rl "PipelineViewModel\|LeadTriage\|LeadsTab" OPSTests | xargs -n1 basename` to enumerate — run every class named there). Commit: `feat(leads): console recomposition — sticky search band, sort/crew wiring, no-matches state, stage-bar entry`

### Task 10: Snapshot proofs

**Files:**
- Create: `OPSTests/Views/LeadsConsoleSnapshotTests.swift` (pattern: `FixedSizeSnapshot` harness — read `OPSTests/Views/BooksSnapshotTests.swift` + `AppHostWindow.swift` first; UIHostingController + app-host window + `drawHierarchy`, PNGs via xcresult attachments, never ImageRenderer)
- Output: `docs/artifacts/leads-console-redesign/*.png`

Six proofs (spec §11.7): working band; quiet band; search active with matches; NO MATCHES; NEWEST flat with assignee labels; stage browser tabs (won tab included). Seed with `PipelineViewModel.previewLoaded()`-style fixtures + a 3-user roster; remember `PermissionStore` must be the injected env store (shared fails closed in harness). Export: `xcrun xcresulttool export attachments` to the artifacts dir. Run on per-session sim clone if the primary sim is busy.

Commit: `test(leads): console snapshot proofs — band states, search, crew labels, stage tabs`

### Task 11 (Fable, not agent): design-system audit + bible + report

- Run `custom-skills:audit-design-system` over the six touched/created view files.
- Update `ops-software-bible` leads/pipeline section (console layout, search/sort/crew behavior, stage browser) same-session.
- Deliver Jackson plain-language summary + PNGs.
