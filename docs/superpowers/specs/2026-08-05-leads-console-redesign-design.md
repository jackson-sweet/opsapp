# LEADS CONSOLE REDESIGN — Design Spec

**Date:** 2026-08-05
**Surface:** ops-ios · LEADS tab · console path only (`.all` view scope). The delegate day sheet (`.assigned` scope) is untouched.
**Initiative name for spawns:** `LEADS CONSOLE`
**Brief (Jackson, 2026-08-05):** inline real-time search; top KPIs occupy too much space / top half inefficient; the zero-state ("0 NEED ACTION / ALL QUIET") and "PIPELINE BY STAGE" areas are too much text and dead space; on open he wants to see what's overdue and what's waiting on him; wants leads organized by recency; cards must show the assignee; filter by assignment; an intentional open → act → browse → manipulate flow.

---

## 1 · Diagnosis of the current console

Vertical budget before the first actionable card (390×844 frame): AppHeader (~60pt) + `LeadsSummary` hero 38pt numeral + breakdown (~90pt) + three bordered KPI tiles (~55pt) + stage distribution bar (~20pt) + `LeadsByStageRow` label + 3-line stage tiles (~90pt) + sticky chip band (~45pt) ≈ **340pt of chrome**. Two of those bands present the same aggregate twice (stage bar AND stage tiles). The zero state renders a 38pt "0" hero plus `// ALL QUIET` — celebration chrome for "nothing to do."

Capability gaps: no search on the surface (universal search is a separate trip), no recency ordering anywhere, no assignee display, no assignment filter. The triage engine (`PipelineViewModel.TriageBuckets`) already computes overdue / due-today / your-move / fresh / waiting — the data Jackson asks to see first already exists; it is presentation and reach that fail.

## 2 · Design intent

One screen, three postures, in priority order:

1. **Open → act.** The band states the workload in one glance; the queue leads with OVERDUE. Nothing above the queue that does not change what the operator does next.
2. **Browse.** Bucket chips (existing) and a demoted, still-reachable by-stage path.
3. **Manipulate.** Persistent inline search, sort (URGENCY / NEWEST / VALUE), crew filter — all visible, none nested behind a "filters" door.

Prominence follows frequency: workload counts (daily) > queue (daily) > search/sort/crew (weekly) > business aggregates (glance) > stage browsing (occasional) > terminal archive (rare).

## 3 · Layout (390pt frame)

### 3.1 Working state (`needActionCount > 0`)

```
┌─────────────────────────────────────────────┐
│ AppHeader   LEADS                  [+] [⌕]  │  ← unchanged (universal search stays)
│                                             │
│ 4 NEED ACTION                               │  ← Mohave-Light 34, tone rule §4.1
│ 2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE       │  ← JBMono-Med 11, toned segments (existing)
│ PIPELINE $86K · OPEN 12 · WON AUG $22.4K    │  ← JBMono-Med 11, text-3 labels/text values
│ ▓▓▓▓▓▒▒▒▒░░░░░░░░░░░        BY STAGE ▸      │  ← 8pt stage bar + affordance, one 44pt target
├─ sticky ────────────────────────────────────┤
│ [⌕ Search leads        ] [URGENCY ▾][CREW ▾]│  ← 40pt row: field flex + 2 menu chips
│ [ALL 12][OVERDUE 2][DUE TODAY 1][YOUR MOVE …│  ← existing TacticalChipRow, unchanged
│ ───────────────────────────────────────────  │  ← hairline (existing)
├─────────────────────────────────────────────┤
│ // OVERDUE · CHASE NOW ────────────────  2  │
│ [LeadTriageCard]                            │
│ …                                           │
```

Band ≈ 110pt (was ~255pt incl. by-stage strip). Sticky band ≈ 92pt (was ~45pt). Net: first card rises ~100pt and every surviving element is unique information.

### 3.2 Quiet state (`needActionCount == 0`, open leads exist)

```
│ // ALL QUIET — NO FOLLOW-UPS DUE            │  ← JBMono-Med 11, `//` mute + label text-3
│ PIPELINE $86K · OPEN 12 · WON AUG $22.4K    │
│ ▓▓▓▓▒▒▒░░░░░░░░░        BY STAGE ▸          │
├─ sticky band, queue as normal ──────────────┤
```

No numeral hero, no breakdown. The WAITING / FRESH queue below carries the remaining content.

### 3.3 Empty pipeline (`openLeadCount == 0`)

Band renders metrics line (`PIPELINE — · OPEN 0 · WON AUG …` per formatting rules) + stage bar hidden (no segments to draw) + no quiet line (the queue's existing `LeadsCaughtUp` block owns the message). No duplication.

### 3.4 Removed outright

- The three bordered KPI tiles (`LeadsSummary.tileRow`) — collapsed into the metrics line.
- `LeadsByStageRow` (label + stage tile strip) — deleted from the console; stage browsing moves behind the stage bar target (§7).
- The 38pt `0 NEED ACTION` zero-hero.

`LeadsWonNudge` stays exactly as is (conditional, actionable). Pull-to-refresh, realtime listeners, deep links, sheets, day-sheet branch: untouched.

## 4 · Command band spec

### 4.1 Need-action hero (working state only)

- `CountUpText`, `Mohave-Light` **34** (down from 38), `NEED ACTION` label JetBrains Mono Medium 11 tracking 1.4 — both existing treatments, existing tone rule: rose while `overdue > 0`, tan while `needAction > 0` (`roseTextM` / `tanTextM`).
- Breakdown line: existing `breakdownSegment` implementation verbatim (toned segments, `·` separators).
- Accessibility: keep the existing combined label ("4 need action, 2 overdue, …").

### 4.2 Metrics line (replaces tiles)

- One line, JetBrains Mono Medium 11, `monospacedDigit`: `PIPELINE $86K · OPEN 12 · WON AUG $22.4K`.
- Labels + `·` separators `text-3`; values `text`; WON value `oliveTextM` when > 0 (carries the tiles' semantic). `BooksFormat.compact` for dollars; `—` when pipeline value is 0. Month label = current month uppercase (existing `monthLabel`).
- Accessibility: one combined element, "Pipeline $86K, 12 open, won $22.4K in August."

### 4.3 Stage bar + BY STAGE affordance

- Existing 8pt stage distribution bar (`stageBar`) unchanged visually; hidden when no open leads.
- New trailing microlabel `BY STAGE ▸` — JetBrains Mono Medium 9.5, tracking 1.2, `text-3`, chevron `text-mute`.
- The bar + label row is **one Button**, min height 44pt (padding extends the target), light impact haptic, pushes the stage browser (§7). Accessibility label: "Pipeline by stage, browse."

### 4.4 Quiet line (quiet state only)

`// ALL QUIET — NO FOLLOW-UPS DUE` — JetBrains Mono Medium 11 tracking 1.4; `// ` in `textMute`, remainder `text-3`. Not a control.

## 5 · Sticky control band

Sticky section header = search row + existing chip row + hairline, all on `background` (existing pinning pattern).

### 5.1 Search field (new house pattern: `LeadsSearchBar`)

- Height **40pt** visual (44pt hit target via padding), radius `sidebarHoverRadius` (6pt bare-input tier per OPSStyle), fill `surfaceInput` (`0.04` white), border `line` 1pt. Focus: border brightens to `rgba(255,255,255,0.20)` — **never accent** (DESIGN.md inputs).
- Leading magnifier: SF `magnifyingglass` 14pt, `text-3`.
- Text: Mohave 15, `text`; placeholder `Search leads` Mohave 15 `text-3`.
- Trailing clear (`xmark.circle.fill` 14pt `text-3`) when non-empty; clears query only, keeps focus.
- Keyboard: `.submitLabel(.search)`, `OPSKeyboardDoneAccessory` if the shared accessory is the house norm for bare fields, `.scrollDismissesKeyboard(.interactively)` on the queue scroll.
- `.autocorrectionDisabled(true)`, `.textInputAutocapitalization(.never)`.
- Filtering is live per keystroke — pure in-memory, no debounce.

### 5.2 Sort chip (menu)

- `Menu` hosting a 36pt-height chip (chip tier, MOBILE.md §4.3): JetBrains Mono Medium 10 tracking 1.2 uppercase, radius 4pt.
- Rest (URGENCY): inactive chip treatment — `text-3` on `0.04` fill, `line` border, label `URGENCY ▾`.
- Non-default (NEWEST / VALUE): active chip treatment — `text` on `0.10` fill, `0.18` border (the TacticalChip selected grammar; **no accent**).
- Menu options exactly: `URGENCY`, `NEWEST`, `VALUE` with checkmark on current. Light impact on change.
- Sort meanings: URGENCY = existing grouped queue. NEWEST = flat, `createdAt` desc. VALUE = flat, `estimatedValue` desc, nil/0 last (ties → newest first).
- Sort is session state (`@State`), resets to URGENCY on tab remount — opening the tab always answers "what needs me" first.

### 5.3 Crew chip (menu) — assignment filter

- Same chip anatomy as sort. Rest: `CREW ▾` inactive. Filtered: selection as label — `MINE ▾` / `UNASSIGNED ▾` / `JASON W ▾` — active treatment.
- Menu: `ALL CREW` · `MINE` · `UNASSIGNED` · divider · one row per roster member (short name, checkmark on current).
- **Roster** = company `User`s (`companyId` match, `deletedAt == nil`, `isActive != false`) ∪ users referenced by any loaded lead's `assignedTo`; ids with no resolvable name are excluded from the menu (their leads remain reachable under ALL CREW; their cards read `UNKNOWN`). Sorted by full name; MINE = `viewModel.currentUserId`.
- **Visibility gate:** the crew chip and all card assignee text render only when the roster (resolvable, active) has **> 1 member**. A solo operator never sees assignment chrome (invisible helpfulness).
- Matching is **lowercased-id** comparison on both sides (`UUID().uuidString` is uppercase; Postgres is lowercase — known dupe-bug gotcha).
- Crew filter is session state, resets on remount.

### 5.4 Composition + interaction rules

- Row: `[search field — flex] [sort chip] [crew chip]`, 8pt gaps, canvas padding `spacing3_5` (matches queue). Solo operators: crew chip absent, field grows.
- **Search suspends browse filters.** While `query` is non-empty: bucket chips and crew filter do not constrain results; the chip row and crew chip render at 40% opacity and ignore taps (`allowsHitTesting(false)`); sort still applies (URGENCY sort during search = flat, bucket order: overdue → dueToday → yourMove → fresh → waitingOnThem → unconverted-won, preserving in-bucket order). Clearing the query restores prior chip + crew state instantly. One rule, zero dead-end "no results because of a hidden filter" traps.
- Bucket chips, when active (no query): unchanged behavior.
- Crew filter composes with bucket chips (AND): `OVERDUE ∩ MINE` etc. Group headers in ALL show the filtered counts.

## 6 · Queue changes

### 6.1 Population

Unchanged for browse modes (open leads via TriageBuckets; unconverted won only via the nudge). **Search population** = every lead the tab owns: all open + unconverted-won leads (terminal lost/discarded stay in the stage browser only).

### 6.2 Search matching (engine contract)

Case- and diacritic-insensitive `contains` over: `displayContactName`, `title`, `descriptionText`, `address`, `contactEmail`, `source`, `shortDisplayId`; phone matching digit-normalized (query digits ⊆ `contactPhone` digits when the query contains ≥3 digits). Multi-token query: every token must match at least one field.

### 6.3 Rendering

- URGENCY + no query: existing grouped `LazyVStack` verbatim.
- NEWEST / VALUE (no query): flat list, no group headers; cards derive tone from `bucket: .all` (existing per-lead urgency path) so urgency stays visible in any order.
- Search active: flat list under one section line `// MATCHES ─── N` (existing `queueSectionHeader` visual grammar, neutral `text-2` tone). Won-unconverted matches render with their existing outcome strip (terminal rendering already handled by `LeadTriageCard`).
- Search empty result: inline block — `0` (Mohave-Light 32 `text-3`) + `// NO MATCHES` (JBMono 10 `textMute` tracking 1.6) + `[ CLEAR SEARCH ]` (JBMono 10, tappable, clears query; 44pt target). No olive check ring (that grammar means "caught up", not "not found").

### 6.4 Assignee on cards

- `LeadTriageCard` meta row gains an assignee token between the stage segments and the source: trailing cluster reads `JASON W · REFERRAL`.
- Assignee text: JetBrains Mono Regular 8.5 tracking 0.7, `text-3` (one step brighter than source's `textMute` — operational vs provenance). `UNASSIGNED` renders `textMute`.
- Rendered only when the visibility gate (§5.3) passes. Name form: first name + space + last-name initial, uppercase (`JASON W`); falls back to full first name alone; unresolvable id → `UNKNOWN` (matches web + detail vocabulary).
- Card API: new optional `assigneeLabel: String?` (nil = hidden). LeadsTabView computes labels once per render from the roster index — cards never query.
- Accessibility: appended to the card label ("…, assigned to Jason W" / "…, unassigned").

## 7 · Stage browsing relocation

- Entry: stage-bar target (§4.3). Push (existing `navigationDestination(item: $footerStage)` route, now fed by the bar) opens `PipelineStageListView`.
- `PipelineStageListView` gains a **scrolling stage tab row** (MOBILE.md §4.2 — this exact use case) pinned under its nav bar: `NEW · n` `QUALIFYING · n` `QUOTING · n` `QUOTED · n` `FOLLOW UP · n` `NEGOTIATION · n` `WON · n` `LOST · n` — JBMono 10/11 tracking, active = `text` + 2pt white underline (never accent), inactive `text-3`, 44pt targets, edge fade masks, light impact on switch. Selecting a tab swaps the list in place (state var, not a new push).
- Entry stage = the stage the bar was showing with the most open leads (ties → pipeline order); `footerStage` becomes the initial selection.
- This ADDS a previously missing capability: WON and LOST are now browsable (terminal rendering already supported by the card; won/lost lists sorted `actualCloseDate` desc then `createdAt` desc).
- iOS 17.6 floor: implement the tab row as a plain `ScrollView(.horizontal)` + buttons; no iOS-18-only scroll APIs.

## 8 · States

| State | Treatment |
|---|---|
| Loading (first) | Existing spinner path, unchanged |
| Loaded, work due | §3.1 |
| Loaded, all quiet | §3.2 |
| No open leads | §3.3 + existing `LeadsCaughtUp` |
| Bucket filter empty | Existing `NONE HERE` block, unchanged |
| Search no matches | §6.3 empty block |
| Offline | Whole surface already renders last fetch; search/sort/crew are pure local — fully functional offline |
| Load error | Existing `loadError` path, unchanged |

## 9 · Motion, haptics, a11y

- All appear/disappear of band segments and list mode swaps: `OPSStyle.Animation.standard` (the one curve), opacity/position only; honor Reduce Motion via existing patterns (no new animation primitives).
- Haptics: light impact on chip/menu selection commits, stage-bar push, stage-tab switch (matches existing chip row + tile behavior). No haptic on keystrokes.
- Contrast: every new text ≥ `text-3` (5.4:1) except decorative `//`/chevrons (`textMute`, decorative-only rule). Search placeholder is `text-3`. 11px floor respected (smallest new text 9.5 JBMono = existing microlabel tier used by section headers; assignee 8.5 matches the existing source metadata tier on these cards).
- VoiceOver: search field labeled "Search leads"; sort chip label "Sort, currently urgency"; crew chip "Crew filter, currently all crew"; chips row unchanged.

**Note on 8.5/9.5pt mono:** these sizes pre-exist on this surface (source tag, section headers). The redesign introduces no NEW sub-11 tier; it reuses the established metadata tiers. Flagged for honesty against the 11px floor rule — the surface's shipped convention wins consistency.

## 10 · Engine + architecture

New pure, nonisolated `LeadsQueryEngine` (no view imports):

```swift
enum LeadSort: String { case urgency, newest, value }
enum CrewFilter: Equatable { case all, mine, unassigned, member(String) }
struct LeadsListControls { var query: String; var sort: LeadSort; var crew: CrewFilter }

static func matches(_ lead: Opportunity, query: String) -> Bool
static func apply(controls:, buckets:, allOwned:, currentUserId:) -> LeadsQueryResult
// LeadsQueryResult: .grouped([(TriageBucket, [Opportunity])]) | .flat([Opportunity], header: FlatHeader)
static func roster(users: [User], leads: [Opportunity], companyId: String) -> [CrewMember]  // gate + menu + index
static func assigneeLabel(for id: String?, roster:) -> String?  // "JASON W" / "UNASSIGNED" / "UNKNOWN"
```

- `LeadsTabView` owns `@State controls`, `@Query allUsers` (already the app pattern), passes results down. `PipelineViewModel` untouched except nothing removed — `LeadsSummary` rewrite consumes existing computeds only.
- No schema, no server, no repository changes. `assignedTo` + `assignmentVersion` already sync on the read path.
- Files: `LeadsSummary.swift` rewritten in place; `LeadsByStageRow.swift` deleted; new `LeadsSearchBar.swift`, `LeadsControlChips.swift` (sort + crew), `LeadsQueryEngine.swift`; `LeadTriageCard.swift` meta-row addition; `PipelineStageListView.swift` tab row; `LeadsTabView.swift` composition.

## 11 · Tests (must exist, must pass)

1. Engine search: name/title/address/email hit; diacritic fold ("Muñoz" ← "munoz"); multi-token AND; phone digit-normalized; shortDisplayId hit; empty query = no-op.
2. Engine sort: NEWEST strict `createdAt` desc; VALUE desc with nil-last + tie → newest; URGENCY passthrough preserves bucket grouping/order.
3. Crew: mine/unassigned/member matching incl. **uppercase-vs-lowercase id** cases; AND-composition with buckets; search-suspension rule returns unfiltered population.
4. Roster: solo company → gate false; active-only filter (`deletedAt`, `isActive == false` excluded); union includes lead-referenced departed id only when resolvable; label forms (JASON W / first-only / UNKNOWN).
5. Band state selection: working / quiet / empty-pipeline branch logic (pure helper).
6. Stage browser: entry-stage pick (max-count, tie → pipeline order); tab data includes WON/LOST with correct counts.
7. Snapshot proofs (harness, not assertions): working band, quiet band, search active w/ matches, NO MATCHES block, NEWEST flat list with assignee labels, stage browser with tabs.

## 12 · Out of scope

Day sheet surface; universal search; web parity (web already has table controls); assignment mutation UX (lives in LeadDetailView); notification rail; any server/schema work; Carbon icon migration.

## 13 · Copy inventory (locked, ops-copywriter)

| Slot | Copy |
|---|---|
| Search placeholder | `Search leads` |
| Sort chip / menu | `URGENCY ▾` · options `URGENCY` / `NEWEST` / `VALUE` |
| Crew chip / menu | `CREW ▾` · options `ALL CREW` / `MINE` / `UNASSIGNED` / names |
| Quiet line | `// ALL QUIET — NO FOLLOW-UPS DUE` |
| Search results header | `// MATCHES ─── N` |
| Search empty | `0` + `// NO MATCHES` + `[ CLEAR SEARCH ]` |
| Stage affordance | `BY STAGE ▸` |
| Card assignee | `JASON W` / `UNASSIGNED` / `UNKNOWN` |

---

# ADDENDUM — Round 2 (2026-08-06)

Jackson's review of the shipped console. Six directives, plus three "what is this?" questions whose answers are the fixes.

## 14 · Card compression (`LeadTriageCard`)

### 14.1 Answers → fixes

| Question | Answer in code | Fix |
|---|---|---|
| "What is the dash in the top right?" | `valueText` returns `—` when `estimatedValue` is nil/0 | Omit the value slot entirely when there is no value. `—` is the rule for a *metric that has a slot* (a KPI line); a scan card should not reserve money space for a lead that has none. |
| "What is the subtitle drawing from, why truncated so fast?" | `jobLine` prefers `descriptionText` (long email-body extract) over `title` (short job name) | **Delete the line.** *(Superseded, Jackson 2026-08-06.)* The first answer was "flip the priority — `title` first, keep one line". Jackson's call on seeing it: the line goes entirely. The queue is scanned by WHO and WHAT'S DUE; a job name the operator has to read is a second reading pass on every row, and the name plus the chase strip already identify the lead. The job is one tap away in the dossier. `jobLine` is deleted with it — no `title` / `descriptionText` fallback survives on the card. |
| "What are the dashed filled lines?" | 6-segment stage progress bar (`metaRow`, 62pt, accent-tinted to `stageIndex`) | **Delete it.** The stage chip already states the stage in words (`QUOTING · 5D`). It was the only accent on the card and it carried zero information the chip lacked. |

### 14.2 New card anatomy

```
┌──────────────────────────────────────────────┐
│ [QUOTING · 5D ▾]                     $14,200 │  value omitted when none
│ Marcus Webb                 DANA W · WEBSITE │  name flexes, meta truncates
│ [→ CHASE · 5D LATE          [HANDLED ✓]]     │  chase strip — unchanged, 44pt
│ ──────────────────────────────────────────── │
│ [CALL] [TEXT] [EMAIL] [VISIT]            [✎] │  actions
└──────────────────────────────────────────────┘
```

- **Meta row is deleted as a band.** `assigneeLabel · source` moves to the trailing edge of the name row (same 8.5 JBMono-Regular / 0.7 tracking / `text-3`+`textMute` treatment). Name takes `layoutPriority(1)`; the meta cluster truncates first.
- **Job subtitle is deleted** *(Jackson 2026-08-06 — see §14.1)*. The card's information bands are stage+value, name+meta, chase strip.
- **Padding:** card inset `.vertical` 15 → 12. Inter-band `spacing2_5` → `spacing2` across the whole stage/name/chase group — a uniform 8pt so the three top bands read as one tight block; the action row keeps its hairline + `spacing2_5` separation, which is the card's only deliberate pause and is what separates reading from doing.
- Net: 7 stacked bands → 4. **Measured: 250pt → 198pt per card** — a 52pt (21%) saving on every row. Both figures are pixel-scanned from the same lead (Cedar Ridge HOA, the first OVERDUE card) in the round-1 and round-2 `console-band-working.png` at the same start row: the card fill `rgb(20,20,21)` spans 750px in round 1 and 595px in round 2 at 3×. Two full cards now clear the fold where round 1 showed one and a sliver. Terminal cards lose the same bar (its olive/neutral variants go with it).

### 14.3 VISIT action

- Fourth text chip in the action row, same `ContactChipButton` grammar: `CALL · TEXT · EMAIL · VISIT` + the log glyph. Four flex chips + one 36pt glyph fits 390pt (≈67pt per chip).
- **Gate: `canConvert && !isTerminal`** — verbatim the gate `LeadDetailView`'s START SITE VISIT menu item uses (line ~671). Hidden, not disabled, when ungated: an operator without convert scope has no visit path anywhere else either.
- Card API: `var onStartSiteVisit: (() -> Void)? = nil` (nil → chip hidden, so day-sheet call sites are untouched). `LeadsTabView` wires it to the existing `activeSiteVisitLead` cover — the same `SiteVisitCaptureView` + convert hand-off the FAB, detail screen and add-lead sheet already drive. `PipelineStageListView` takes a new `onStartSiteVisit: (Opportunity) -> Void` param supplied by `LeadsTabView` at its `navigationDestination`.

## 15 · Search band (`LeadsQueueBand`)

### 15.1 Full-width field + one filter control

- The two menu chips (`URGENCY ▾` / `CREW ▾`) are **replaced by a single trailing filter control**; the search field takes all remaining width.
- Filter control: 40pt height matching the field, `sidebarHoverRadius`, chip fills/borders (rest = `surfaceInput` + `line`; any non-default = `text`@0.10 fill + `text`@0.20 border). Content:
  - **At rest:** `line.3.horizontal.decrease` SF glyph only (square, ~44pt target). The field is genuinely full-width in the common case.
  - **Filtered:** glyph + the active selection(s) inline, joined by `·` — `NEWEST`, `DANA W`, or `NEWEST · DANA W` — JBMono `miniLabelBold` 0.8 tracking, `lineLimit(1)`, truncating tail; the field yields width. State is readable without opening the menu.
- Menu (one `Menu`, two `Section`s with `//`-free plain headers `SORT` and `CREW`): sort rows `URGENCY / NEWEST / VALUE`; crew rows `ALL CREW / MINE / UNASSIGNED / <member shortLabels>`. Checkmark marks the current row in each section (existing `LeadsControlMenuRow`).
- Crew section renders only when the assignment gate is open (roster > 1) — solo operators get a sort-only menu, and the control still reads `NEWEST` when sorted.

### 15.2 Counts on crew rows

- Every crew row carries a count: `ALL CREW · 12`, `MINE · 4`, `UNASSIGNED · 2`, `DANA W · 5`.
- Counted over **all open leads** (`TriageBuckets.all`) — not the active bucket — so the numbers are a stable roster read that does not shift as bucket chips change.
- Engine: `nonisolated static func crewCounts(buckets:currentUserId:roster:) -> LeadsCrewCounts` (`all`, `mine`, `unassigned`, `byMember: [String: Int]`, ids lowercased). TDD, incl. uppercase-id folding and a member with zero leads (renders `· 0`, never hidden — a teammate with nothing assigned is information).

### 15.3 Focus scrolls the band to the top

- `LeadsSearchBar` gains `onFocusChange: (Bool) -> Void`.
- The console `ScrollView` is wrapped in a `ScrollViewReader`; on focus-gained, `withAnimation(OPSStyle.Animation.standard) { proxy.scrollTo(Self.bandAnchorID, anchor: .top) }` so the command band scrolls away and the field sits directly under the header with maximum list visible. No scroll on focus-lost (the operator keeps their position).
- `.scrollDismissesKeyboard(.interactively)` stays.
- Implementation note: this `ScrollView` has no custom `ScrollTargetBehavior`, so the iOS-26 `updateTarget` trap does not apply. Programmatic scroll cannot be asserted from a test-created window (harness limitation) — prove it in the app-host window or with a state-level test of the focus→scroll trigger.

### 15.4 Unchanged

Search-suspends-browse still holds: while searching, the bucket chip row **and** the filter control dim to 40% and stop hit-testing (sort included this round — with sort inside the filter control there is no way to keep it live without a second affordance, and a suspended control that still works is a worse lie than one that visibly waits). Everything else in §5–§7 stands.
