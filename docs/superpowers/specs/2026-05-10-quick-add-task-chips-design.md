# Quick Add — Task Chips on Project Details

Bug `e3996ac3-4180-4bdf-9423-f1d3b0c7b6de` — ProjectDetails feature_request.

> "Create suggested actions (like if user commonly adds 'rail install' task with Jake Strickler assigned, then allow user to add that with one tap)"

## Goal

On the **Project Details → Details tab**, surface up to **3** one-tap chips for the company's most-repeated `(task type + crew)` combinations. Tap = the task is created on the current project immediately, no form sheet. The full form remains reachable via the existing ADD TASK row for anything that isn't a frequent setup.

## Non-goals

- No personal vs company split. Trades crews share habits (`rail install + Jake`) — suggestions are company-wide.
- No similarity scoring across project types. `Project` doesn't carry a `projectKind` field yet (the `ops-web-kind-type` worktree is in flight). When that ships, scope can be narrowed in a follow-up; for now, scope is company-wide.
- No new Supabase tables, no edge functions, no Postgres functions. All compute is on-device against synced `ProjectTask` rows.
- No ML, no embeddings, no AI ranking. Frequency × recency decay only.
- No web parity (this is the iOS-only bug).

## Coordination with parallel session

A parallel terminal is implementing `2026-05-10-recency-suggestions-design.md` (different bug, project-form + task-form picker recency). That session adds `projects.created_by`, `Project.createdAt/createdBy`, and `ProjectTask.createdAt`, plus two `DataController` helpers (`recentTeamMemberIds`, `recentTaskTypeIds`).

This spec **does not** depend on those additions. The suggestion engine here:
- reads `ProjectTask.lastSyncedAt` as the recency stamp (falls back gracefully if `createdAt` doesn't exist yet),
- lives in a new file (`TaskSuggestionEngine.swift`) — no edits to `DataController.swift`,
- modifies only `DetailsTabView.swift`'s `TaskListSection` on the view side — no edits to `TaskFormSheet.swift` or `ProjectFormSheet.swift`.

Result: zero file overlap with the parallel session. If they land first, I get cleaner timestamps for free.

---

## A. Surface

### Placement

A horizontal scrollable chip rail, **inside** the existing TASKS card on the Details tab, between the last task divider and the `ADD TASK` row. Renders only when:

- `canEdit == true` (admin/permission gate, mirrors ADD TASK gate at [DetailsTabView.swift:580](OPS/Views/Components/Project/Tabs/DetailsTabView.swift:580)),
- the engine returns ≥1 suggestion that isn't already on the current project,
- the user has not dismissed all suggestions for this project,
- `!tutorialMode`.

If the engine returns nothing, the rail collapses to zero height and is omitted — no empty state, no placeholder.

### Visual

```
┌─ TASKS ────────────────────────────────────────────────────┐
│  ▣ Demo                            Jake +1      Mon May 12 │
│  ────────────────────────────────────────────────────────  │
│  ▣ Frame                           Marco        Tue May 13 │
│  ────────────────────────────────────────────────────────  │
│  QUICK ADD                                                  │
│  ┌──────────────────┐ ┌──────────────────┐ ┌────────────┐  │
│  │ ▣ RAIL INSTALL   │ │ ▣ SITE PREP      │ │ ▣ DEMO     │  │
│  │   ●● JAKE +1     │ │   ● JEN          │ │   ●● JAKE  │  │
│  └──────────────────┘ └──────────────────┘ └────────────┘  │
│  ────────────────────────────────────────────────────────  │
│  + ADD TASK                                                 │
└─────────────────────────────────────────────────────────────┘
```

**Rail header:** `QUICK ADD`, `OPSStyle.Typography.smallCaption`, `OPSStyle.Colors.tertiaryText`, uppercase. Padding: `16pt` horizontal, `12pt` top, `8pt` bottom. Subdued — not pushy.

**Chip:**
- Frame: ~160pt wide, 56pt tall, `OPSStyle.Layout.cardCornerRadius` (10pt), `OPSStyle.Colors.cardBackground` fill, hairline border `OPSStyle.Colors.cardBorder` 1pt.
- Left edge: 3pt colored bar in the task-type's `taskType.color` (mirrors `TaskLineItem`'s left rail). Anchors the chip to the task type visually.
- Row 1: task type display name, `OPSStyle.Typography.bodyBold`, uppercase, `OPSStyle.Colors.primaryText`, line-limit 1, truncate tail.
- Row 2: up to 2 stacked-overlap avatars (16pt each, -4pt overlap, 1.5pt `cardBackgroundDark` ring), then `JAKE`/`JAKE +N` text in `OPSStyle.Typography.smallCaption`, `OPSStyle.Colors.secondaryText`. If 0 team members on the suggestion, second row reads `UNASSIGNED` (`tertiaryText`).
- Spacing between chips: `OPSStyle.Layout.spacing2` (8pt).
- Rail uses `ScrollView(.horizontal, showsIndicators: false)` with `16pt` leading/trailing inset.

**Tap (primary action):**
- Haptic: `UIImpactFeedbackGenerator(style: .medium)` (matches "commit/confirm" tier per `OPS/CLAUDE.md`).
- Creates the task immediately:
  - new `ProjectTask` with `id = UUID().lowercased()`, `projectId = project.id`, `companyId = project.companyId`, `taskTypeId = suggestion.taskTypeId`, `taskColor = suggestion.taskColor`, `status = .active`.
  - `teamMemberIds` set from suggestion (`setTeamMemberIds(_:)`).
  - `teamMembers` relationship hydrated from local `User` fetch by id (same pattern as `TaskFormSheet.saveTask` line 1467-1473).
  - `displayOrder` = max existing displayOrder + 1.
  - No dates, no notes, no dependency overrides — minimum viable task. User can long-press the row later to schedule.
- Calls `dataController.createTask(dto:)` to push to Supabase via sync engine (same path as `TaskFormSheet`).
- Suggestion is removed from the rail (it now exists on the project, so the dedup filter drops it).
- Subtle slide-down animation as the new `TaskBadge` row appears in the list above. Uses `OPSStyle.Animation.standard`.

**Long-press (escape hatch):**
- Haptic: light impact.
- Opens `TaskFormSheet(mode: .create, preselectedProjectId:)` with the suggestion's task type + team members preselected so the user can tweak dates/notes before committing. (Implementation: pass a new `prefilled` parameter — see § Implementation.)

**Swipe-left on chip:**
- Haptic: light impact.
- Dismisses just this suggestion for just this project. Stored locally; never synced. The chip slides out (`OPSStyle.Animation.fast`); rail re-renders without it.
- A small "UNDO" toast at the bottom for 4s lets the user re-add it. (V1: skip undo to keep scope tight — let user reopen the project to reset session memory if they tap by mistake.)

### Empty state path

When `project.tasks.isEmpty` (no tasks yet on the project), the existing TASKS card still renders the section header + ADD TASK row. The Quick Add rail slots between them with the same visual treatment — no special "empty" copy, since the chips ARE the empty-state guidance. The user sees:

```
┌─ TASKS ─────────────────────────────────────┐
│  QUICK ADD                                   │
│  ┌──────────────┐ ┌──────────────┐          │
│  │ RAIL INSTALL │ │ SITE PREP    │  →       │
│  │ ●● JAKE +1   │ │ ● JEN        │          │
│  └──────────────┘ └──────────────┘          │
│  ────────────────────────────────────────   │
│  + ADD TASK                                  │
└──────────────────────────────────────────────┘
```

If the engine has no suggestions at all (brand-new company), the rail is omitted. The card is just the section header + ADD TASK row — current behavior, unchanged.

---

## B. Signal model

### Definitions

A **suggestion key** is the tuple `(taskTypeId, sortedTeamMemberIds)`. Two tasks count as the same suggestion if and only if they share the task type AND the exact same crew composition (order-insensitive). This matches the user's mental model: "rail install with Jake" is different from "rail install with Marco" — both are valid suggestions and may both surface if both are frequent.

A task with zero team members is its own valid suggestion key — useful for unassigned-by-default work types (e.g. inspections).

### Source set

```swift
let predicate = #Predicate<ProjectTask> { task in
    task.companyId == companyId &&
    task.deletedAt == nil
}
```

No status filter — we count cancelled tasks the same as completed, because a cancelled `rail install + Jake` task is still evidence the operator was about to create that setup. Status is the user's reaction to the task, not the suggestion signal.

### Recency window

60 days. Read `task.lastSyncedAt ?? .distantPast` as the recency stamp. (If the parallel session lands first and adds `task.createdAt`, swap the read site in one line — see § Implementation.)

### Frequency threshold

A suggestion key must appear **≥ 2 times** in the source set to qualify. Two is enough — three was too aggressive for small crews; this is a tool for solo operators with one helper, not just for large GCs.

### Ranking

For each qualifying key:

```
score = sum(exp(-days_ago / 30)) over all occurrences in window
```

This rewards both raw frequency (more occurrences → higher sum) and recency (recent occurrences get higher weight via the half-life-style decay). Two occurrences yesterday will outrank five occurrences from 50 days ago.

Tiebreak by most-recent occurrence timestamp desc, then by alphabetical task-type display name (stable ordering across renders).

### Dedup against current project

Drop any suggestion whose `(taskTypeId, sortedTeamMemberIds)` already exists on the current project (in `project.tasks` where `deletedAt == nil`, ignoring status). No duplicate-of-existing-task on the same project.

### Cap

Take the **top 3** after ranking and dedup. Three keeps the rail at one visible row on a standard iPhone width without horizontal scrolling for most operators; 4th+ scroll into view.

### Dismissals

Per-project local-only suppression:

- Key: `quickadd.dismissed.<projectId>` in `UserDefaults.standard`.
- Value: `[String]` of dismissed suggestion-key hashes.
- Suggestion-key hash: SHA-256 of `taskTypeId + ":" + sortedTeamMemberIds.joined(",")`, base64.
- Filter applied after ranking, before cap.
- Never synced. Reset on app delete or via Settings → Reset App (not exposed in v1).

This is intentionally narrow scope. A "rail install + Jake" the user dismissed on Project A still surfaces on Project B — because it might be the right call there. The dismissal is a per-context "not on this job," not a global "stop suggesting."

### Refresh

The rail is computed on each `body` evaluation. Cheap — engine reads from SwiftData in-process, no network. SwiftData's `@Query` on `project.tasks` triggers re-evaluation when a new task is added, so the dedup pass naturally drops the just-created suggestion. No manual invalidation needed.

---

## C. Implementation

### C.1 New file — `TaskSuggestionEngine.swift`

Path: `OPS/Utilities/TaskSuggestionEngine.swift`.

```swift
import Foundation
import SwiftData

/// Output of TaskSuggestionEngine — one row in the Quick Add rail.
struct TaskSuggestion: Identifiable, Hashable {
    let taskTypeId: String
    let teamMemberIds: [String]   // sorted ascending; canonical form
    let score: Double             // frequency × recency decay
    let mostRecentAt: Date

    /// Stable id for SwiftUI ForEach diffing.
    var id: String { keyHash }

    /// SHA-256 of `taskTypeId + ":" + teamMemberIds.joined(",")`, base64.
    /// Used as the dismissal key and as the ForEach id.
    var keyHash: String {
        let raw = "\(taskTypeId):\(teamMemberIds.joined(separator: ","))"
        return SHA256Hasher.base64(raw)
    }
}

/// On-device suggestion engine for the Quick Add rail on Project Details.
/// Computes top-N `(taskType, crew)` combinations that the company uses
/// frequently and recently. Pure SwiftData read — no network, no @MainActor
/// requirement on the read path (caller is on @MainActor and passes the
/// context).
struct TaskSuggestionEngine {
    /// Days of history to consider.
    static let windowDays: Int = 60

    /// Minimum number of occurrences in the window for a key to qualify.
    static let minOccurrences: Int = 2

    /// Maximum suggestions returned (caller may show fewer if dedup drops some).
    static let maxResults: Int = 3

    /// Compute top suggestions for a company, excluding any keys already on
    /// the given project. Reads from the provided SwiftData context.
    ///
    /// - Parameters:
    ///   - context: SwiftData model context — caller is responsible for
    ///     calling on @MainActor.
    ///   - companyId: scope.
    ///   - project: dedup target. Any suggestion whose key matches an
    ///     existing non-deleted task on this project is dropped.
    /// - Returns: at most `maxResults` suggestions, ranked descending.
    static func suggestions(
        context: ModelContext,
        companyId: String,
        for project: Project
    ) -> [TaskSuggestion] {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -windowDays, to: Date()
        ) ?? .distantPast

        let predicate = #Predicate<ProjectTask> { task in
            task.companyId == companyId &&
            task.deletedAt == nil
        }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
        guard let tasks = try? context.fetch(descriptor) else { return [] }

        // Build the existing-on-project key set for dedup.
        let existingKeys: Set<String> = Set(
            project.tasks
                .filter { $0.deletedAt == nil }
                .map { key(taskTypeId: $0.taskTypeId, teamIds: $0.getTeamMemberIds()) }
        )

        // Aggregate by suggestion key.
        struct Agg {
            var score: Double = 0
            var mostRecent: Date = .distantPast
            var taskTypeId: String = ""
            var teamMemberIds: [String] = []
        }
        var bucket: [String: Agg] = [:]

        for task in tasks {
            let stamp = task.lastSyncedAt ?? .distantPast
            guard stamp >= cutoff else { continue }

            let sortedIds = task.getTeamMemberIds().sorted()
            let k = key(taskTypeId: task.taskTypeId, teamIds: sortedIds)
            if existingKeys.contains(k) { continue }

            let daysAgo = Calendar.current.dateComponents(
                [.day], from: stamp, to: Date()
            ).day ?? 0
            let weight = exp(-Double(daysAgo) / 30.0)

            var agg = bucket[k] ?? Agg()
            agg.score += weight
            if stamp > agg.mostRecent { agg.mostRecent = stamp }
            agg.taskTypeId = task.taskTypeId
            agg.teamMemberIds = sortedIds
            bucket[k] = agg
        }

        // Build suggestions, filter by min occurrences (proxy: score > 1
        // implies ≥ 2 occurrences within the recency window since each
        // occurrence contributes ≤ 1.0).
        //
        // For the strict ≥ 2 check we re-count occurrences below.
        var counted: [String: Int] = [:]
        for task in tasks {
            let stamp = task.lastSyncedAt ?? .distantPast
            guard stamp >= cutoff else { continue }
            let sortedIds = task.getTeamMemberIds().sorted()
            let k = key(taskTypeId: task.taskTypeId, teamIds: sortedIds)
            counted[k, default: 0] += 1
        }

        let dismissed = dismissedKeys(forProjectId: project.id)

        let suggestions: [TaskSuggestion] = bucket.compactMap { (k, agg) in
            guard (counted[k] ?? 0) >= minOccurrences else { return nil }
            guard !dismissed.contains(k) else { return nil }
            return TaskSuggestion(
                taskTypeId: agg.taskTypeId,
                teamMemberIds: agg.teamMemberIds,
                score: agg.score,
                mostRecentAt: agg.mostRecent
            )
        }
        .sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.mostRecentAt > b.mostRecentAt
        }

        return Array(suggestions.prefix(maxResults))
    }

    // MARK: - Dismissal storage

    static func dismissedKeys(forProjectId projectId: String) -> Set<String> {
        let raw = UserDefaults.standard.stringArray(
            forKey: dismissKey(projectId: projectId)
        ) ?? []
        return Set(raw)
    }

    static func dismiss(_ suggestion: TaskSuggestion, forProjectId projectId: String) {
        var current = Array(dismissedKeys(forProjectId: projectId))
        if !current.contains(suggestion.keyHash) {
            current.append(suggestion.keyHash)
            UserDefaults.standard.set(current, forKey: dismissKey(projectId: projectId))
        }
    }

    // MARK: - Helpers

    private static func key(taskTypeId: String, teamIds: [String]) -> String {
        "\(taskTypeId):\(teamIds.joined(separator: ","))"
    }

    private static func dismissKey(projectId: String) -> String {
        "quickadd.dismissed.\(projectId)"
    }
}

/// Lightweight SHA-256 helper (CryptoKit) — used for stable, short dismissal
/// keys instead of writing the raw composite to UserDefaults.
private enum SHA256Hasher {
    static func base64(_ input: String) -> String {
        // Import via CryptoKit; encapsulated here so the engine file is the
        // only consumer.
        let data = Data(input.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}
```

(`import CryptoKit` at the top of the file. The engine itself doesn't store CryptoKit references — `SHA256Hasher` is private.)

### C.2 New file — `QuickAddSuggestionsRail.swift`

Path: `OPS/Views/Components/Project/QuickAddSuggestionsRail.swift`.

```swift
import SwiftUI
import SwiftData

struct QuickAddSuggestionsRail: View {
    let project: Project
    let canEdit: Bool

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Query private var allTaskTypes: [TaskType]
    @Query private var allUsers: [User]

    /// Refresh trigger: project.tasks changes drive recompute through the
    /// parent view re-rendering; this @State is for dismissal-triggered
    /// refresh within the rail itself.
    @State private var dismissBump: Int = 0

    @State private var prefilledSuggestion: TaskSuggestion? = nil

    private var suggestions: [TaskSuggestion] {
        guard canEdit, !tutorialMode else { return [] }
        guard let context = dataController.modelContext else { return [] }
        let companyId = project.companyId
        guard !companyId.isEmpty else { return [] }
        _ = dismissBump  // tie state to recompute
        return TaskSuggestionEngine.suggestions(
            context: context,
            companyId: companyId,
            for: project
        )
    }

    private var taskTypeById: [String: TaskType] {
        Dictionary(uniqueKeysWithValues: allTaskTypes.map { ($0.id, $0) })
    }

    private var userById: [String: User] {
        Dictionary(uniqueKeysWithValues: allUsers.map { ($0.id, $0) })
    }

    var body: some View {
        let items = suggestions
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("QUICK ADD")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(items) { suggestion in
                            chip(for: suggestion)
                                .transition(
                                    .scale(scale: 0.85).combined(with: .opacity)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .sheet(item: $prefilledSuggestion) { suggestion in
                TaskFormSheet(
                    mode: .create,
                    preselectedProjectId: project.id,
                    prefilledTaskTypeId: suggestion.taskTypeId,
                    prefilledTeamMemberIds: suggestion.teamMemberIds,
                    onSave: { _ in }
                )
                .environmentObject(dataController)
            }
        }
    }

    @ViewBuilder
    private func chip(for suggestion: TaskSuggestion) -> some View {
        let taskType = taskTypeById[suggestion.taskTypeId]
        let displayName = taskType?.display ?? "Task"
        let chipColor = Color(hex: taskType?.color ?? "") ?? OPSStyle.Colors.primaryAccent
        let members: [User] = suggestion.teamMemberIds.compactMap { userById[$0] }

        Button(action: { commit(suggestion) }) {
            HStack(spacing: 0) {
                // Left color bar
                Rectangle()
                    .fill(chipColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        if members.isEmpty {
                            Text("UNASSIGNED")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        } else {
                            HStack(spacing: -4) {
                                ForEach(Array(members.prefix(2)), id: \.id) { m in
                                    UserAvatar(user: m, size: 16)
                                        .overlay(
                                            Circle()
                                                .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 1.5)
                                        )
                                }
                            }
                            Text(memberLabel(members))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: 168, height: 56, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                prefilledSuggestion = suggestion
            } label: {
                Label("Edit Before Adding", systemImage: "pencil")
            }
            Button(role: .destructive) {
                dismiss(suggestion)
            } label: {
                Label("Dismiss Suggestion", systemImage: "xmark.circle")
            }
        }
    }

    private func memberLabel(_ members: [User]) -> String {
        guard let first = members.first else { return "" }
        let firstName = first.firstName.uppercased()
        if members.count == 1 { return firstName }
        return "\(firstName) +\(members.count - 1)"
    }

    // MARK: - Actions

    private func commit(_ suggestion: TaskSuggestion) {
        guard canEdit else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let taskTypeColor = taskTypeById[suggestion.taskTypeId]?.color ?? "#59779F"
        let newTask = ProjectTask(
            id: UUID().uuidString.lowercased(),
            projectId: project.id,
            taskTypeId: suggestion.taskTypeId,
            companyId: project.companyId,
            status: .active,
            taskColor: taskTypeColor
        )
        newTask.setTeamMemberIds(suggestion.teamMemberIds)
        newTask.displayOrder = (project.tasks.map { $0.displayOrder }.max() ?? -1) + 1

        modelContext.insert(newTask)
        newTask.project = project
        if let taskType = taskTypeById[suggestion.taskTypeId] {
            newTask.taskType = taskType
        }

        // Hydrate teamMembers relationship for immediate avatar render.
        let ids = suggestion.teamMemberIds
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in ids.contains(user.id) }
        )
        newTask.teamMembers = (try? modelContext.fetch(descriptor)) ?? []
        newTask.needsSync = true
        try? modelContext.save()

        // Build DTO + enqueue sync (mirrors TaskFormSheet.saveTask path).
        let dto = SupabaseProjectTaskDTO(
            id: newTask.id,
            bubbleId: nil,
            companyId: newTask.companyId,
            projectId: newTask.projectId,
            taskTypeId: newTask.taskTypeId,
            customTitle: nil,
            taskNotes: nil,
            status: newTask.status.rawValue,
            taskColor: newTask.taskColor,
            displayOrder: newTask.displayOrder,
            teamMemberIds: suggestion.teamMemberIds,
            sourceLineItemId: nil,
            sourceEstimateId: nil,
            startDate: nil,
            endDate: nil,
            duration: 0,
            dependencyOverrides: nil,
            startTime: nil,
            endTime: nil,
            deletedAt: nil,
            createdAt: nil
        )

        Task {
            _ = try? await dataController.createTask(dto: dto)
        }
    }

    private func dismiss(_ suggestion: TaskSuggestion) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        TaskSuggestionEngine.dismiss(suggestion, forProjectId: project.id)
        withAnimation(OPSStyle.Animation.fast) {
            dismissBump += 1
        }
    }
}
```

### C.3 Modify — `DetailsTabView.swift`

In `TaskListSection.body`, insert the rail above the ADD TASK divider:

```swift
// Existing: ForEach tasks + dividers ...

// NEW — Quick Add rail (admin only, gated by suggestion availability)
if canEdit {
    QuickAddSuggestionsRail(project: project, canEdit: canEdit)
        .environmentObject(/* injected by parent — already present */)
}

// Add task row (admin only)
if canEdit {
    Rectangle().fill(OPSStyle.Colors.cardBorderSubtle).frame(height: 1).padding(.leading, 16)
    Button(action: onAddTask) { ... }
}
```

The rail's `EmptyView()` return makes it self-collapsing when there are no suggestions — no parent-side gate needed beyond `canEdit`.

### C.4 Modify — `TaskFormSheet.swift` (additive, single init param)

Add two optional prefill params so long-press can pre-fill the form:

```swift
init(
    mode: Mode,
    preselectedProjectId: String? = nil,
    prefilledTaskTypeId: String? = nil,
    prefilledTeamMemberIds: [String]? = nil,
    onSave: @escaping (ProjectTask) -> Void
) {
    self.mode = mode
    self.preselectedProjectId = preselectedProjectId
    self.onSave = onSave
    self.onSaveDraft = nil
    _selectedTaskTypeId = State(initialValue: prefilledTaskTypeId)
    _selectedTeamMemberIds = State(initialValue: Set(prefilledTeamMemberIds ?? []))
}
```

`_selectedTaskTypeId` and `_selectedTeamMemberIds` are existing `@State` fields — initializing them in the new path doesn't touch the existing init at line 228 (we add an overload). The other existing init signatures stay unchanged.

**File overlap note:** This is the only edit to `TaskFormSheet.swift`. The parallel session (`recency-suggestions-design.md`) also touches this file for picker recency, but in a different code block (line 984 and 1719). Merge conflict risk: low — adjacent edits at most, no overlapping lines.

---

## D. Edge cases

| Scenario | Behavior |
|----------|----------|
| Brand-new company, < 2 tasks total | Engine returns []. Rail collapses. Card looks identical to current. |
| User just added a task that matched a suggestion | Engine dedups against `project.tasks` — that key drops out. The other 2 chips remain. |
| Task type for a suggestion was deleted/archived | `taskTypeById[suggestion.taskTypeId]` returns nil → chip uses fallback color + "Task" label. Best to skip entirely: in `body`, filter out suggestions whose `taskTypeById[id] == nil`. |
| Team member for a suggestion left the company | `userById[id]` returns nil → that avatar is dropped silently. The label degrades gracefully ("UNASSIGNED" if all dropped). |
| Tutorial mode | `tutorialMode == true` short-circuits to []. Tutorial uses scripted demo tasks; recency would surface them and confuse onboarding. |
| Read-only role (`canEdit == false`) | Rail returns []. Mirrors ADD TASK row gating. |
| All suggestions dismissed | Engine returns []. Rail collapses. |
| User long-presses → opens form → cancels | No state change. Suggestion stays. |
| Engine read fails (context unavailable) | Returns []. Rail collapses. No error UI. |
| `companyId` empty string | Returns []. Defensive — shouldn't happen for a real user. |
| Offline at create-time | `createTask(dto:)` enqueues sync operation locally. SwiftData write succeeds. Rail re-renders without the just-created suggestion. Sync drains when online. |
| Duplicate create (user double-taps) | `dataController.createTask(dto:)` is idempotent on `id` (lines 4548-4555). But two distinct IDs is the bigger risk — guard the button with `isSubmitting` state? V1 skip; the medium haptic + immediate row insert gives clear feedback the tap registered. |

---

## E. Files touched

| File | Change | Lines (rough) |
|------|--------|---------------|
| `OPS/Utilities/TaskSuggestionEngine.swift` | New file. ~150 lines. | +150 |
| `OPS/Views/Components/Project/QuickAddSuggestionsRail.swift` | New file. ~180 lines. | +180 |
| `OPS/Views/Components/Project/Tabs/DetailsTabView.swift` | Insert rail in `TaskListSection.body` above ADD TASK divider. | +4 |
| `OPS/Views/JobBoard/TaskFormSheet.swift` | Add overloaded init with `prefilledTaskTypeId` + `prefilledTeamMemberIds`. | +12 |
| `ops-software-bible/02_DATA_MODELS.md` or `07_SPECIALIZED_FEATURES.md` | Document the engine + dismissal storage. | +30 |

No Supabase migration. No new tables. No edits to `DataController.swift`. No edits to `ProjectFormSheet.swift`.

---

## F. Testing

**Unit (logic-only, no SwiftData):**
- (Skip — engine is tightly coupled to SwiftData fetch. Cover via integration.)

**Integration (xcodebuild device build, real SwiftData):**
- Seed a project with 4 historical tasks: `(rail install, [Jake])` × 3, `(demo, [Marco, Jen])` × 2, all within last 30 days. Open Project Details on a different project of the same company → rail shows 2 chips, ranked rail-install first.
- Tap rail-install chip → task appears in the list, rail re-renders without rail-install (dedup).
- Long-press rail-install chip → context menu shows Edit/Dismiss. Tap Edit → `TaskFormSheet` opens with task type + Jake preselected.
- Long-press rail-install chip → Dismiss → chip disappears. Force-quit + reopen project → chip still absent.
- Open a different project of same company → rail-install reappears (dismissal is per-project).
- Set `canEdit = false` (read-only role) → rail absent.
- Tutorial mode → rail absent.
- Brand-new company (0 historical tasks) → rail absent.
- Add a task manually (not via chip) that matches a suggestion → suggestion drops out on next render.

**Manual:**
- Test on a real iPhone with gloves — chip touch targets are 168×56pt, well over the 60×60 OPS minimum.
- Test in sunlight — chip border + 3pt color bar provide enough edge contrast against the card background.
- Test offline — chip tap creates task locally, sync queued.

---

## G. Rollout

- No migration. No phased rollout. App-side only.
- Bible update: append a "Task Suggestions" subsection to `ops-software-bible/07_SPECIALIZED_FEATURES.md` (notification rail is already documented there; this fits the same "specialized feature" register).
- App version: required for the rail to appear; older versions are unaffected (no schema changes).
- Bug closure: `bug_reports.e3996ac3-…` → `status='resolved'`, `resolved_at=now()`, `fixed_at=now()`, `fix_notes` summarizes the engine + rail.

---

## H. Future / follow-up

- When `Project.projectKind` lands (the `ops-web-kind-type` worktree), narrow the source set: `WHERE projects.kind_id = current.kind_id` to surface kind-specific habits. Engine signature gains a `kindId: String?` parameter; existing callers pass nil for behavior identical to today.
- A "RECENT" tag on the task-form team picker could be wired to the same `TaskSuggestionEngine` once both ship — but the parallel session is already building that path with its own helpers. No double-work.
- Undo toast on dismiss can come in v2 if user feedback indicates the dismissal is too easy to misfire.
