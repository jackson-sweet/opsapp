# Recency Suggestions — Project Form & Task Form

Bug 9d5c2535-8cf3-4ea0-9e41-948066392be9 — three related recency improvements that surface "what you just did" inside the creation flows.

## Goal

Cut friction on the three most repeated decisions an operator makes when creating work:

1. **What kind of project is this?** → Suggested projects strip at the top of the project form (one-tap structural clone).
2. **Who's on this task type?** → Team picker sorted by who's recently been on this task type.
3. **What kind of task?** → Task-type picker sorted by what was recently used.

Everything works offline against locally-cached SwiftData. The only Supabase change is one additive column (`projects.created_by`).

## Non-goals

- No change to the existing `CopyFromProjectSheet` field-granular flow — it stays where it is, triggered by the bottom "COPY FROM PROJECT" button. The new strip is the fast path; the existing sheet is the deep path.
- No similarity scoring, no ML, no AI ranking. Pure recency.
- No web parity in this spec — bug is iOS-only.

---

## A. Project form — "Suggested projects" empty-state strip

### Placement

A horizontal scrollable strip pinned **above** the `mandatoryFieldsSection` in [ProjectFormSheet.swift:711](OPS/Views/JobBoard/ProjectFormSheet.swift:711), inside the existing `ScrollView` content, **above** `previewCard`.

The strip is **empty-state-only**:

- Visible when **all** of the following are true:
  - `mode.isCreate` (never on edit)
  - `!tutorialMode` (never during tutorial flows)
  - `title.isEmpty` (user has not typed a project name)
  - `selectedClientId == nil`
  - `localTasks.isEmpty`
- Fades out with `OPSStyle.Animation.standard` when any of those become non-empty.
- Never reappears within the same session, even if user clears the title (avoid flicker).

### Visual

```
┌──────────────────────────────────────────────────────────────┐
│ START FROM RECENT                                            │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                 │
│ │ DECK   │ │ DECK   │ │ FENCE  │ │ KITCHEN│  → scroll        │
│ │ 432    │ │ 419    │ │ 387    │ │ 376    │                 │
│ │ 4 task │ │ 3 task │ │ 2 task │ │ 8 task │                 │
│ │ 2d ago │ │ 5d ago │ │ 1w ago │ │ 2w ago │                 │
│ └────────┘ └────────┘ └────────┘ └────────┘                 │
└──────────────────────────────────────────────────────────────┘
```

- Section header: `START FROM RECENT` (caption bold, `OPSStyle.Colors.secondaryText`, uppercase, JetBrains Mono — matches the existing `COPYING FROM` style in `CopyFromProjectSheet`).
- Cards: 140pt wide × 72pt tall, `cardBackgroundDark` fill, `cardBorder` 1pt stroke, `cardCornerRadius`.
- Card content (top to bottom):
  - Project title, uppercase, `bodyBold`, line-limited to 1 (~14 chars).
  - Task count: `{N} TASK{S}` in `smallCaption` `tertiaryText`. Hidden if zero.
  - Relative recency: `{Nd|Nw|Nmo} AGO` in `smallCaption` `tertiaryText`. Formatted via `RelativeDateTimeFormatter` with abbreviated style.
- Light haptic on tap (`UIImpactFeedbackGenerator(style: .light)`).

### Recency model

- Source: local `@Query private var allProjects: [Project]` already on the form.
- Filter:
  - `createdBy == dataController.currentUser?.id` (skip nil — those are historical pre-migration projects).
  - `deletedAt == nil`.
  - `createdAt != nil` (skip pre-migration rows we couldn't backfill).
- Sort: `createdAt` desc.
- Cap: take the first **5**.
- Tutorial-mode filter: when `tutorialMode`, restrict to projects with `id.hasPrefix("DEMO_")` (mirrors the existing `availableClients` / `availableTeamMembers` pattern, line 46-67).

If the resulting list is empty, the strip does not render. (First-run users see nothing — no empty placeholder.)

### Tap behaviour — structural clone (C2)

One tap = clone the **structure** of the source project, leaving identity-bearing fields blank:

| Field | Action |
|-------|--------|
| `title` | left blank — focus moves to title field after copy |
| `selectedClientId` | left blank |
| `address`, `latitude`, `longitude` | left blank |
| `description` | left blank |
| `notes` | left blank |
| `startDate`, `endDate` | left `nil` |
| `projectImages` | not copied |
| `localTasks` | **copied** — one `LocalTask` per source task with `taskTypeId`, `teamMemberIds`, and `status = .active`. `startDate` / `endDate` reset to `nil`. |
| `isTasksExpanded` | set `true` so user can verify the cloned task list |

After the clone, `focusedField = .title` so the keyboard pops on the title input — the operator's next action is "name it."

Haptic: `UINotificationFeedbackGenerator.success` (matches existing copy-from logic at [CopyFromProjectSheet.swift:459](OPS/Views/JobBoard/CopyFromProjectSheet.swift:459)).

Reuses the existing `handleCopyFromProject` helper at [ProjectFormSheet.swift:1785](OPS/Views/JobBoard/ProjectFormSheet.swift:1785) — we'll add an overload that takes a `Project` directly and constructs the `[String: Any]` dict with only the `tasks` key populated, so the existing apply-logic handles the rest unchanged.

---

## B. Recency model: data layer

### B.1 Supabase migration

```sql
-- migration: 2026_05_10_add_projects_created_by.sql
ALTER TABLE public.projects
  ADD COLUMN created_by uuid REFERENCES auth.users(id);

CREATE INDEX idx_projects_created_by_created_at
  ON public.projects (created_by, created_at DESC)
  WHERE deleted_at IS NULL;

COMMENT ON COLUMN public.projects.created_by IS
  'User who created the project. Populated by app on insert. NULL for projects created before 2026-05-10.';
```

- Additive, nullable, safe per the iOS-sync-constraint memory.
- Backfill: none. Historical rows stay `NULL` and won't appear in the per-user recency strip.
- RLS: existing project policies already gate by `company_id`. No change required — `created_by` is metadata, not authz.

### B.2 SwiftData model — `Project`

Append to [DataModels/Project.swift](OPS/DataModels/Project.swift) after `deletedAt`:

```swift
// Audit — when and by whom this project was created.
// Added 2026-05-10 for recency suggestions. NULL for projects synced
// down before the migration.
var createdAt: Date?
var createdBy: String?
```

Additive SwiftData migration — no schema-version bump needed.

### B.3 DTO — `SupabaseProjectDTO`

Append two optional fields to [CoreEntityDTOs.swift:207](OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift:207):

```swift
let createdAt: String?
let createdBy: String?

// in CodingKeys
case createdAt = "created_at"
case createdBy = "created_by"
```

### B.4 Sync layer

Two changes:

1. **On fetch** ([ProjectRepository.swift:25](OPS/Network/Supabase/Repositories/ProjectRepository.swift:25) etc.) — DTOs already decode the full row, no select-list to update. Round-trip the two new fields through `Project ↔ SupabaseProjectDTO` in the mapper (find `func toProject()` / similar).
2. **On insert** ([ProjectRepository.swift:110](OPS/Network/Supabase/Repositories/ProjectRepository.swift:110)) — the call site that builds the DTO before `.insert(dto)` must set `createdBy = dataController.currentUser?.id` and `createdAt = ISO8601 string for Date()`. Existing `lastSyncedAt`-set logic gives us the model to follow.

We don't update `created_by` on edits — it's immutable after insert. Server-side, we'll **not** add a trigger; the client is responsible. (Trigger would require `auth.uid()` and the app uses service-role-via-RLS-policy patterns elsewhere; staying consistent.)

---

## C. Task form — team picker recency sort (D1)

### Trigger

The team picker is opened from a button in [TaskFormSheet.swift](OPS/Views/JobBoard/TaskFormSheet.swift) at the team-members field; it presents `TeamMemberPickerSheet` (line 1719) with `allTeamMembers: uniqueTeamMembers` ordered by full-name alphabetical (line 437).

### New ordering

Inject the current `selectedTaskTypeId` into `TeamMemberPickerSheet` and pass the local `ProjectTask` collection (or a precomputed recency map). Reorder `allTeamMembers` as:

1. **Tier 1 — recent on this task type.** Members who appear in `teamMemberIds` of any `ProjectTask` where `taskTypeId == selectedTaskTypeId`, sorted by max `createdAt ?? lastSyncedAt` desc.
2. **Tier 2 — never used on this task type.** All remaining members, alphabetical by `fullName`.

If `selectedTaskTypeId == nil` (user opens team picker before picking a task type — possible since fields aren't strict-ordered), the picker falls back to alphabetical-only (current behaviour).

### Implementation sketch

New helper on `DataController` (extension or inline computed):

```swift
/// Returns team member IDs sorted by most recent assignment to the given task type.
/// Members never assigned to this task type are omitted from the result —
/// caller appends them at the bottom in alphabetical order.
func recentTeamMemberIds(forTaskType taskTypeId: String, companyId: String) -> [String] {
    let predicate = #Predicate<ProjectTask> { task in
        task.taskTypeId == taskTypeId &&
        task.companyId == companyId &&
        task.deletedAt == nil
    }
    let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
    guard let tasks = try? modelContext.fetch(descriptor) else { return [] }

    // For each task, walk its team-member IDs and record the most recent date.
    var latest: [String: Date] = [:]
    for task in tasks {
        let stamp = task.createdAt ?? task.lastSyncedAt ?? .distantPast
        for memberId in task.getTeamMemberIds() {
            if (latest[memberId] ?? .distantPast) < stamp {
                latest[memberId] = stamp
            }
        }
    }

    return latest.sorted { $0.value > $1.value }.map { $0.key }
}
```

Caller (in `TaskFormSheet`, at the call site that presents `TeamMemberPickerSheet`):

```swift
let recentIds = dataController.recentTeamMemberIds(
    forTaskType: selectedTaskTypeId ?? "",
    companyId: dataController.currentUser?.companyId ?? ""
)
let recentSet = Set(recentIds)
let recencyIndex = Dictionary(uniqueKeysWithValues: recentIds.enumerated().map { ($1, $0) })

let ordered = fetchedTeamMembers.sorted { a, b in
    let aIsRecent = recentSet.contains(a.id)
    let bIsRecent = recentSet.contains(b.id)
    if aIsRecent != bIsRecent { return aIsRecent }
    if aIsRecent {
        return (recencyIndex[a.id] ?? .max) < (recencyIndex[b.id] ?? .max)
    }
    return a.fullName.localizedCompare(b.fullName) == .orderedAscending
}
```

Pass `ordered` to `TeamMemberPickerSheet` instead of `uniqueTeamMembers`.

### Visual indicator (optional polish — include)

Recent members get a `RECENT` tag (caption, `OPSStyle.Colors.primaryAccent`, 1pt border) to the right of their role line — same pattern as existing inline badges. Stops at the boundary between Tier 1 and Tier 2 so the operator sees where "your usual crew" ends.

---

## D. Task form — task-type picker recency sort (D2)

### Location

The inline expandable picker at [TaskFormSheet.swift:984-1027](OPS/Views/JobBoard/TaskFormSheet.swift:984), currently `availableTaskTypes.sorted(by: { $0.display < $1.display })`.

### New ordering

1. **Tier 1 — recently used task types.** Task types that appear in any `ProjectTask` for the current company. Sorted by max `createdAt ?? lastSyncedAt` desc across all tasks of that type. Cap implicit (whatever's been used).
2. **Tier 2 — never used.** All remaining task types, alphabetical by `display`.

Separator: a thin `OPSStyle.Colors.cardBorder` divider between tiers (visually distinguishes "your usual" from "everything else").

### Implementation sketch

New helper on `DataController`:

```swift
/// Returns task type IDs sorted by most recent use across all tasks in the company.
func recentTaskTypeIds(companyId: String) -> [String] {
    let predicate = #Predicate<ProjectTask> { task in
        task.companyId == companyId &&
        task.deletedAt == nil
    }
    let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
    guard let tasks = try? modelContext.fetch(descriptor) else { return [] }

    var latest: [String: Date] = [:]
    for task in tasks {
        let stamp = task.createdAt ?? task.lastSyncedAt ?? .distantPast
        if (latest[task.taskTypeId] ?? .distantPast) < stamp {
            latest[task.taskTypeId] = stamp
        }
    }
    return latest.sorted { $0.value > $1.value }.map { $0.key }
}
```

Caller, in `TaskFormSheet` body — replace the inline `.sorted(by:)` with a computed property:

```swift
private var orderedAvailableTaskTypes: [TaskType] {
    let recentIds = dataController.recentTaskTypeIds(
        companyId: dataController.currentUser?.companyId ?? ""
    )
    let recentSet = Set(recentIds)
    let recencyIndex = Dictionary(uniqueKeysWithValues: recentIds.enumerated().map { ($1, $0) })

    let recent = availableTaskTypes.filter { recentSet.contains($0.id) }
        .sorted { (recencyIndex[$0.id] ?? .max) < (recencyIndex[$1.id] ?? .max) }
    let rest = availableTaskTypes.filter { !recentSet.contains($0.id) }
        .sorted { $0.display < $1.display }
    return recent + rest
}
```

Use `orderedAvailableTaskTypes` in the `ForEach`, and insert a `Divider` row between the last recent and the first rest item (skip if either side is empty).

---

## E. `ProjectTask.createdAt` (supporting change)

For D1/D2 to give stable ordering, `ProjectTask` benefits from a true `createdAt` instead of falling back to `lastSyncedAt` (which updates on every edit-sync).

The Supabase column already exists (`project_tasks.created_at`). Two additive changes:

- **SwiftData** ([DataModels/ProjectTask.swift](OPS/DataModels/ProjectTask.swift)) — add `var createdAt: Date?` after `deletedAt`.
- **DTO** ([CoreEntityDTOs.swift:247](OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift:247)) — add `let createdAt: String?` and `case createdAt = "created_at"`.

Mapper: round-trip in both directions. On insert, set client-side to current time (server can override via default — `project_tasks.created_at` already defaults to `now()` per typical Supabase convention; client value is a hint, not authoritative).

If `createdAt` is nil after sync (pre-migration row that didn't decode), the helper code falls back to `lastSyncedAt` — already handled in the sketch above.

---

## F. Edge cases

| Scenario | Behaviour |
|----------|-----------|
| First-run user, no projects | Strip hides entirely. No empty state. |
| First-run user, no tasks | Task-type list is fully alphabetical (Tier 2 only). Team picker is fully alphabetical. |
| User has 100 projects | Strip shows top 5. Cards horizontal-scroll if needed (`ScrollView(.horizontal, showsIndicators: false)`). |
| User opens team picker before selecting task type | Fallback to alphabetical. No "recent" tier. |
| Tutorial mode, project form | Strip never appears — `!tutorialMode` gate. Tutorial uses scripted `DEMO_` data. |
| Edit mode | Strip never appears — `mode.isCreate` gate. |
| Cloned project has zero tasks | Clone is a no-op (tasks empty, no other fields populated). Card still tappable — just focuses title without any work. Acceptable. |
| Source project's tasks reference task types the user no longer has access to | `LocalTask.taskTypeId` is just a string — the `TaskType` lookup on render handles missing rows gracefully (existing behaviour). |
| Source task has team members no longer in company | `LocalTask.teamMemberIds` keeps the string IDs; the task-form team-member lookup filters by `availableTeamMembers` and drops missing ones at render. Existing behaviour. |
| Project `createdAt` is `NULL` (pre-migration) | Filter excludes it from the strip. Existing copy-from sheet still works since it uses `lastSyncedAt`. |

---

## G. Files touched

| File | Change |
|------|--------|
| `supabase/migrations/<ts>_add_projects_created_by.sql` | New migration. |
| [OPS/DataModels/Project.swift](OPS/DataModels/Project.swift) | Add `createdAt`, `createdBy` properties. |
| [OPS/DataModels/ProjectTask.swift](OPS/DataModels/ProjectTask.swift) | Add `createdAt` property. |
| [OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift](OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift) | Add fields to `SupabaseProjectDTO` and `SupabaseProjectTaskDTO`. |
| Mappers (Project ↔ DTO, ProjectTask ↔ DTO) | Round-trip new fields. Set on insert. |
| [OPS/Utilities/DataController.swift](OPS/Utilities/DataController.swift) | Two helpers: `recentTeamMemberIds(forTaskType:companyId:)`, `recentTaskTypeIds(companyId:)`. |
| [OPS/Views/JobBoard/ProjectFormSheet.swift](OPS/Views/JobBoard/ProjectFormSheet.swift) | New `recentSuggestionsStrip` view, gated on empty-state. New `cloneStructure(from:)` helper that reuses `handleCopyFromProject`. |
| [OPS/Views/JobBoard/TaskFormSheet.swift](OPS/Views/JobBoard/TaskFormSheet.swift) | `orderedAvailableTaskTypes` computed property; replace inline sort. Pass ordered team-member list to `TeamMemberPickerSheet`. Optionally show `RECENT` tag in the picker rows. |
| [ops-software-bible/](../../../ops-software-bible/) | Update `02_DATA_MODELS.md` and `03_API_AND_SYNC.md` with the new `created_by` / `created_at` fields. |

---

## H. Testing plan

**Unit / SwiftData:**

- `recentTeamMemberIds` returns members in correct order when multiple tasks reference same member with different `createdAt`.
- `recentTaskTypeIds` deduplicates correctly.
- Project model round-trips `createdAt` / `createdBy` through SwiftData.

**Integration (xcodebuild on device):**

- Create a project: `projects.created_by` is populated in Supabase.
- Open project form on a tenant with 5+ projects created by current user: strip shows top 5 by `createdAt`.
- Open project form on a tenant with no projects created by user: strip is absent.
- Type one character into title field: strip animates out.
- Tap a card: tasks copy in; title is empty and focused; keyboard appears.
- Open task form, pick a task type, open team picker: recent assignees on that type appear at top with `RECENT` tag.
- Switch task type in same task form, reopen team picker: order updates.
- Open task type picker with no prior tasks in tenant: full alphabetical, no divider.
- Open task type picker with prior tasks: recent task types appear on top, divider separates from rest.

**Manual edge tests:**

- Tutorial mode: strip never shows (verified at the gate condition).
- Edit mode: strip never shows.
- Offline: all sorts work (SwiftData-only).
- Empty company (single project): strip shows that one project. Task pickers fall back to alphabetical.

---

## I. Rollout

- **Migration:** apply to production Supabase before TestFlight build ships. Safe — additive nullable column.
- **App version:** required for the recency UI; older app versions ignore the new columns (Codable optionals).
- **Backfill:** none. Historical projects stay out of the per-user recency strip until they're recreated.
- **Bible update:** `02_DATA_MODELS.md` (Project schema) + `03_API_AND_SYNC.md` (insert flow) in the same PR.
