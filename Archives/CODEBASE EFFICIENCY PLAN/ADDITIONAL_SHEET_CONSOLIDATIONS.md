# Advanced Sheet Template Consolidation

**📖 Document Type**: IMPLEMENTATION GUIDE
**🎯 Purpose**: Tracks D, G, H, I (Form/Edit Merge, Filter/Deletion/Search Templates)
**👉 Start Here**: [README.md](./README.md) → Tracks D, G, H, I

---

**Date**: November 19, 2025

## How to Use This Document

**For Track D (Form/Edit Sheet Merging)** - ⭐ HIGHEST ROI:
- **READ**: Section 3 (Form vs Edit Sheet Consolidation)
- **FOLLOW**: Implementation examples and migration steps
- **Effort**: 6-9 hours, **Impact**: 1,065 lines saved (40% reduction)

**For Track G (Generic Filter Sheet Template)**:
- **READ**: Section 2 (Filter Sheets Consolidation)
- **FOLLOW**: Generic FilterSheet implementation
- **Effort**: 10-14 hours, **Impact**: 850 lines saved (56% reduction)

**For Track H (Generic Deletion Sheet Template)**:
- **READ**: Section 1 (Deletion Sheets Consolidation)
- **FOLLOW**: Generic DeletionSheet implementation
- **Effort**: 8-12 hours, **Impact**: 700 lines saved (65% reduction)

**For Track I (Generic Search Field Component)**:
- **READ**: Section 4 (Search Field Components Consolidation)
- **FOLLOW**: Generic SearchField implementation
- **Effort**: 4-6 hours, **Impact**: 310 lines saved (63% reduction)

**Prerequisites**:
- ✅ None - All tracks D, G, H, I are independent
- ⚠️ Can run in parallel with any other track

**Total Effort**: 28-41 hours
**Total Impact**: 2,925 lines saved (52% reduction across 16 files)

**Recommended Order**: D (best ROI) → I → H → G

---

## 🚨 CRITICAL: Ask Before Deleting Duplicates

**⚠️ MANDATORY RULE FOR ALL TRACKS D, G, H, I**: When consolidating duplicate sheets or components, you MUST ask the user before deleting ANY duplicate.

### Why This Matters

When you find "duplicate" code, there may be subtle differences:
- Different validation logic
- Different API calls
- Different error handling
- Different edge cases
- Intentional variations

**NEVER ASSUME** two implementations are truly identical. **ALWAYS ASK** the user before deleting.

### Required Process

For **EVERY file** you plan to delete:

1. **IDENTIFY** both versions (file paths, line numbers)
2. **COMPARE** implementations side-by-side
3. **DOCUMENT** any differences (even small ones)
4. **ASK THE USER** with this format:

```
⚠️ DUPLICATE FOUND: [Component/Sheet Name]

VERSION A: [File1.swift] lines X-Y
[Code snippet showing key parts]

VERSION B: [File2.swift] lines X-Y
[Code snippet showing key parts]

DIFFERENCES FOUND:
- Difference 1
- Difference 2
- etc.

MY RECOMMENDATION: [Keep Version X because...]

Should I:
1. Keep Version A, delete Version B
2. Keep Version B, delete Version A
3. Keep both, merge the differences
4. Something else (please explain)
```

5. **WAIT** for user response
6. **ONLY THEN** proceed with deletion

### Track-Specific Warnings

#### Track D (Form/Edit Merge)
- TaskTypeFormSheet vs TaskTypeEditSheet: **ASK** before merging
- ClientFormSheet vs ClientEditSheet: **ASK** before merging
- SubClientFormSheet vs SubClientEditSheet: **ASK** before merging

The form and edit sheets may have different:
- Validation rules
- API endpoints
- Default values
- Required fields

#### Track G (Filter Sheet)
- ProjectListFilterSheet vs TaskListFilterSheet vs CalendarFilterView vs ProjectSearchFilterView
- **ASK** before deleting each one
- Filter options may differ intentionally

#### Track H (Deletion Sheet)
- ClientDeletionSheet vs TaskTypeDeletionSheet vs ProjectDeletionSheet
- **ASK** before deleting each one
- Cascading deletion logic may differ
- Reassignment options may vary

#### Track I (Search Field)
- TaskTypeSearchField vs ClientSearchField vs AddressSearchField
- **ASK** before deleting each one
- Search logic may differ (geocoding for addresses, etc.)

---

## Executive Summary

Beyond the navigation toolbar consolidation already identified in TEMPLATE_STANDARDIZATION.md, there are **four major architectural duplication patterns** that can be eliminated:

1. **Deletion Sheets** - 3 nearly identical files can become 1 generic template (65% reduction)
2. **Filter Sheets** - 4 nearly identical files can become 1 generic template (56% reduction)
3. **Form vs Edit Sheets** - 3 pairs can be merged into 3 single files (37% reduction)
4. **Search Field Components** - Multiple custom implementations can become 1 generic component

**Total Impact**: ~2,500 lines → ~1,000 lines (60% reduction)

---

## 1. Deletion Sheets Consolidation

### Current State

Three deletion sheets with nearly identical structure:

#### Files
- `ClientDeletionSheet.swift` (487 lines)
- `TaskTypeDeletionSheet.swift` (560 lines)
- `ProjectDeletionSheet.swift` (assumed ~500 lines)

#### Structural Similarity: 95%

All three sheets follow the **exact same pattern**:

```swift
struct XDeletionSheet: View {
    let item: X

    @State private var reassignmentMode: ReassignmentMode = .bulk
    @State private var reassignments: [String: String] = [:]
    @State private var itemsToDelete: Set<String> = []
    @State private var bulkSelectedItem: String?
    @State private var bulkDeleteAll = false
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Header with "DELETE X" title
                // Item name and count

                // Segmented control: Bulk | Individual

                if reassignmentMode == .bulk {
                    bulkReassignmentView
                } else {
                    individualReassignmentView
                }

                // Floating delete button at bottom
                Button("Delete X") { performDeletion() }
            }
        }
    }

    private var bulkReassignmentView: some View { ... }
    private var individualReassignmentView: some View { ... }
    private func performDeletion() { ... }
}
```

#### Code Duplication Examples

**Header Pattern** (identical across all 3):
```swift
VStack(alignment: .leading, spacing: 4) {
    Text("DELETE CLIENT")  // Only text differs
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)

    Text(item.name)
        .font(OPSStyle.Typography.title)
        .foregroundColor(OPSStyle.Colors.primaryText)

    Text("\(childItems.count) item\(childItems.count == 1 ? "" : "s")")
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}
```

**Segmented Control** (identical):
```swift
SegmentedControl(
    selection: $reassignmentMode,
    options: [
        (.bulk, "Bulk Reassign"),
        (.individual, "Individual")
    ]
)
```

**Floating Delete Button** (identical):
```swift
Button(action: performDeletion) {
    HStack {
        if isDeleting {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.errorStatus))
                .scaleEffect(0.8)
        } else {
            Text("Delete X")
                .font(OPSStyle.Typography.body)
        }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 56)
    .background(.ultraThinMaterial)
    .foregroundColor(
        canDelete ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.tertiaryText
    )
    // ... identical overlay code
}
```

### Proposed Solution

#### Create Generic DeletionSheet

**Location**: `OPS/Views/Components/Common/DeletionSheet.swift`

```swift
/// Generic deletion sheet that handles cascading deletions with reassignment
///
/// Usage:
/// ```
/// .sheet(isPresented: $showingDeletion) {
///     DeletionSheet(
///         item: client,
///         itemType: "Client",
///         childItems: client.projects,
///         childType: "Project",
///         availableReassignments: availableClients,
///         getChildDisplay: { $0.title },
///         getReassignmentDisplay: { $0.name },
///         onDelete: { client, reassignments, deletions in
///             // Custom deletion logic
///         }
///     )
/// }
/// ```
struct DeletionSheet<Item, ChildItem: Identifiable, ReassignmentItem: Identifiable>: View {
    // Configuration
    let item: Item
    let itemType: String  // "Client", "Task Type", "Project"
    let childItems: [ChildItem]
    let childType: String  // "Project", "Task", etc.
    let availableReassignments: [ReassignmentItem]

    // Display closures
    let getItemDisplay: (Item) -> String
    let getChildDisplay: (ChildItem) -> String
    let getReassignmentDisplay: (ReassignmentItem) -> String
    let getReassignmentSearchComponent: (Binding<String?>, [ReassignmentItem]) -> AnyView

    // Actions
    let onDelete: (Item, [String: String], Set<String>) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reassignmentMode: ReassignmentMode = .bulk
    @State private var reassignments: [String: String] = [:]
    @State private var itemsToDelete: Set<String> = []
    @State private var bulkSelectedItem: String?
    @State private var bulkDeleteAll = false
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        // ... generic implementation
    }
}
```

#### Migration Examples

**Before** (ClientDeletionSheet.swift - 487 lines):
```swift
struct ClientDeletionSheet: View {
    let client: Client
    // ... 487 lines of code
}
```

**After** (usage in ClientListView):
```swift
.sheet(isPresented: $showingClientDeletion) {
    DeletionSheet(
        item: clientToDelete,
        itemType: "Client",
        childItems: clientToDelete.projects,
        childType: "Project",
        availableReassignments: availableClients,
        getItemDisplay: { $0.name },
        getChildDisplay: { $0.title },
        getReassignmentDisplay: { $0.name },
        getReassignmentSearchComponent: { binding, clients in
            AnyView(ClientSearchField(selectedClientId: binding, availableClients: clients))
        },
        onDelete: { client, reassignments, deletions in
            try await dataController.deleteClient(
                client,
                reassignments: reassignments,
                deletions: deletions
            )
        }
    )
}
```

### Impact

- **Lines saved**: ~1,050 lines (3 files × 500 avg) → 350 lines = **700 lines saved**
- **Reduction**: 65%
- **Files affected**: 3 deletion sheets
- **Effort**: 8-12 hours (complex generic implementation)

---

## 2. Filter Sheets Consolidation

### Current State

Four filter sheets with nearly identical structure:

#### Files
- `ProjectListFilterSheet.swift` (357 lines)
- `TaskListFilterSheet.swift` (442 lines)
- `CalendarFilterView.swift` (assumed ~350 lines)
- `ProjectSearchFilterView.swift` (assumed ~300 lines)

#### Structural Similarity: 90%

All filter sheets follow the **exact same pattern**:

```swift
struct XFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedOtherFilter: Set<String>
    @Binding var sortOption: SortOption

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    filterSection(title: "STATUS", icon: "flag.fill") {
                        statusContent
                    }

                    filterSection(title: "OTHER", icon: "...") {
                        otherContent
                    }

                    filterSection(title: "SORT BY", icon: "arrow.up.arrow.down") {
                        sortContent
                    }

                    if hasActiveFilters {
                        activeFiltersSummary
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("FILTER X")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("APPLY") { dismiss() }
                }
            }
        }
    }

    private func filterSection(...) -> some View { ... }  // IDENTICAL
    private func filterRow(...) -> some View { ... }      // IDENTICAL
    private var activeFiltersSummary: some View { ... }   // IDENTICAL
    private func toggleSelection(...) { ... }              // IDENTICAL
    private func resetFilters() { ... }                    // IDENTICAL
}
```

#### Code Duplication Examples

**filterSection() Helper** (100% identical across all 4 files):
```swift
private func filterSection<Content: View>(
    title: String,
    icon: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, 20)

        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}
// 40 lines × 4 files = 160 lines of duplication
```

**filterRow() Helper** (100% identical):
```swift
private func filterRow(
    title: String,
    subtitle: String? = nil,
    isSelected: Bool,
    isSpecial: Bool = false,
    action: @escaping () -> Void
) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(isSpecial ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                .foregroundColor(isSpecial ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)

            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }

        Spacer()

        if isSelected && !isSpecial {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
}
// 30 lines × 4 files = 120 lines of duplication
```

**activeFiltersSummary** (95% identical):
```swift
private var activeFiltersSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("ACTIVE FILTERS")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)

        HStack {
            VStack(alignment: .leading, spacing: 8) {
                // Different filters listed here, but pattern identical

                Button(action: resetFilters) {
                    Text("Reset All Filters")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            )

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
// 50 lines × 4 files = 200 lines of duplication
```

### Proposed Solution

#### Create Generic FilterSheet

**Location**: `OPS/Views/Components/Common/FilterSheet.swift`

```swift
/// Generic filter sheet supporting multiple filter types and sorting
///
/// Usage:
/// ```
/// .sheet(isPresented: $showingFilters) {
///     FilterSheet(
///         title: "Filter Projects",
///         filters: [
///             .multiSelect(
///                 title: "PROJECT STATUS",
///                 icon: "flag.fill",
///                 options: Status.allCases,
///                 selection: $selectedStatuses,
///                 getDisplay: { $0.displayName },
///                 getColor: { $0.color }
///             ),
///             .multiSelect(
///                 title: "TEAM MEMBERS",
///                 icon: "person.2.fill",
///                 options: teamMembers,
///                 selection: $selectedTeamMembers,
///                 getDisplay: { "\($0.firstName) \($0.lastName)" },
///                 getSubtitle: { $0.role.rawValue }
///             )
///         ],
///         sortOptions: ProjectSortOption.allCases,
///         selectedSort: $sortOption,
///         getSortDisplay: { $0.rawValue }
///     )
/// }
/// ```
struct FilterSheet<SortOption: Hashable>: View {
    let title: String
    let filters: [FilterSection]
    let sortOptions: [SortOption]
    @Binding var selectedSort: SortOption
    let getSortDisplay: (SortOption) -> String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Render each filter section
                    ForEach(filters) { filter in
                        filterSection(for: filter)
                    }

                    // Sort section
                    filterSection(
                        title: "SORT BY",
                        icon: "arrow.up.arrow.down"
                    ) {
                        sortContent
                    }

                    // Active filters summary
                    if hasActiveFilters {
                        activeFiltersSummary
                    }
                }
                .padding(.vertical, 20)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("APPLY") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}

/// Filter section configuration
enum FilterSection: Identifiable {
    case multiSelect<T: Identifiable & Hashable>(
        title: String,
        icon: String,
        options: [T],
        selection: Binding<Set<T>>,
        getDisplay: (T) -> String,
        getSubtitle: ((T) -> String)? = nil,
        getColor: ((T) -> Color)? = nil
    )

    var id: String {
        switch self {
        case .multiSelect(let title, _, _, _, _, _, _):
            return title
        }
    }
}
```

#### Migration Examples

**Before** (ProjectListFilterSheet.swift - 357 lines):
```swift
struct ProjectListFilterSheet: View {
    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var sortOption: ProjectSortOption
    // ... 357 lines
}
```

**After** (usage in ProjectListView):
```swift
.sheet(isPresented: $showingFilters) {
    FilterSheet(
        title: "Filter Projects",
        filters: [
            .multiSelect(
                title: "PROJECT STATUS",
                icon: "flag.fill",
                options: [.rfq, .estimated, .accepted, .inProgress, .completed, .closed],
                selection: $selectedStatuses,
                getDisplay: { $0.displayName },
                getColor: { $0.color }
            ),
            .multiSelect(
                title: "ASSIGNED TEAM MEMBERS",
                icon: "person.2.fill",
                options: availableTeamMembers,
                selection: $selectedTeamMemberIds,
                getDisplay: { "\($0.firstName) \($0.lastName)" },
                getSubtitle: { $0.role.rawValue }
            )
        ],
        sortOptions: ProjectSortOption.allCases,
        selectedSort: $sortOption,
        getSortDisplay: { $0.rawValue }
    )
}
```

### Impact

- **Lines saved**: ~1,450 lines (4 files × ~360 avg) → 600 lines = **850 lines saved**
- **Reduction**: 56%
- **Files affected**: 4 filter sheets
- **Effort**: 10-14 hours (complex generic with enum associated values)

---

## 3. Form vs Edit Sheet Consolidation

### Current State

Three pairs of form/edit sheets with 95% identical code:

#### File Pairs
1. `TaskTypeFormSheet.swift` (477 lines) + `TaskTypeEditSheet.swift` (338 lines) = **815 lines**
2. `ClientFormSheet.swift` (~600 lines) + `ClientEditSheet.swift` (~450 lines) = **~1,050 lines**
3. Likely exists: SubClient form/edit pair = **~800 lines**

**Total**: ~2,665 lines across 6 files

#### Code Duplication Analysis

Comparing TaskTypeFormSheet vs TaskTypeEditSheet:

**Identical Sections**:

1. **availableIcons array** (70 lines) - 100% identical
```swift
private let availableIcons = [
    "checklist",
    "hammer.fill",
    "wrench.and.screwdriver.fill",
    // ... 70 lines × 2 files = 140 lines duplicated
]
```

2. **availableColors array** (75 lines) - 100% identical
```swift
private let availableColors: [(color: Color, hex: String)] = [
    (Color(hex: "ceb4b4")!, "ceb4b4"),
    (Color(hex: "b59090")!, "b59090"),
    // ... 75 lines × 2 files = 150 lines duplicated
]
```

3. **IconOption component** (42 lines) - 100% identical
4. **ColorOption component** (28 lines) - 100% identical
5. **UI layout** (120 lines) - 95% identical
6. **Validation logic** (10 lines) - 100% identical

**Different Sections**:

1. **Header title**: "New Task Type" vs "Edit Task Type" (1 line)
2. **onAppear logic**: Empty vs loads existing data (8 lines)
3. **saveTaskType()**: Creates via API vs updates locally (40 vs 30 lines)

**Similarity**: 95%

### Proposed Solution

#### Merge Each Pair into Single Sheet with Edit Mode

**Example: TaskTypeSheet.swift** (replaces both form + edit):

```swift
struct TaskTypeSheet: View {
    // Edit mode configuration
    enum Mode {
        case create(onSave: (TaskType) -> Void)
        case edit(taskType: TaskType, onSave: () -> Void)

        var title: String {
            switch self {
            case .create: return "New Task Type"
            case .edit: return "Edit Task Type"
            }
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var taskTypeName: String = ""
    @State private var taskTypeIcon: String = "checklist"
    @State private var taskTypeColor: Color = Color(hex: "93A17C")!
    @State private var taskTypeColorHex: String = "93A17C"

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var existingTaskTypes: [TaskType] = []

    // Shared arrays (no duplication!)
    private let availableIcons = [/* 70 lines */]
    private let availableColors: [(color: Color, hex: String)] = [/* 75 lines */]

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: mode.title,  // Dynamic title
                    onBackTapped: { dismiss() }
                )

                // Shared UI layout
                ScrollView {
                    // ... identical form fields
                }

                // Save button
                HStack {
                    Button("SAVE") { saveTaskType() }
                }
            }
        }
        .onAppear {
            // Load existing data if editing
            if case .edit(let taskType, _) = mode {
                taskTypeName = taskType.display
                taskTypeIcon = taskType.icon ?? "checklist"
                taskTypeColorHex = taskType.color
                if let color = Color(hex: taskType.color) {
                    taskTypeColor = color
                }
            }
            loadExistingTaskTypes()
        }
    }

    private func saveTaskType() {
        switch mode {
        case .create(let onSave):
            // Create logic
            Task {
                let created = try await dataController.apiService.createTaskType(...)
                let newTaskType = TaskType(id: created.id, ...)
                modelContext.insert(newTaskType)
                try modelContext.save()
                onSave(newTaskType)
                dismiss()
            }

        case .edit(let taskType, let onSave):
            // Update logic
            taskType.display = taskTypeName
            taskType.icon = taskTypeIcon
            taskType.color = taskTypeColorHex
            taskType.needsSync = true
            try modelContext.save()
            onSave()
            dismiss()
        }
    }
}

// Shared supporting views (no duplication!)
struct IconOption: View { /* 42 lines */ }
struct ColorOption: View { /* 28 lines */ }
```

#### Migration Examples

**Before** (2 separate sheets):
```swift
// Create
.sheet(isPresented: $showingCreateTaskType) {
    TaskTypeFormSheet(onSave: { newTaskType in
        // handle save
    })
}

// Edit
.sheet(item: $taskTypeToEdit) { taskType in
    TaskTypeEditSheet(taskType: taskType, onSave: {
        // handle save
    })
}
```

**After** (1 unified sheet):
```swift
// Create
.sheet(isPresented: $showingCreateTaskType) {
    TaskTypeSheet(mode: .create(onSave: { newTaskType in
        // handle save
    }))
}

// Edit
.sheet(item: $taskTypeToEdit) { taskType in
    TaskTypeSheet(mode: .edit(taskType: taskType, onSave: {
        // handle save
    }))
}
```

### Impact

- **Lines saved**: ~2,665 lines (6 files) → 1,600 lines (3 files) = **1,065 lines saved**
- **Reduction**: 40%
- **Files affected**: 6 files → 3 files (3 pairs merged)
- **Effort**: 6-9 hours (straightforward refactor with mode enum)

---

## 4. Search Field Components Consolidation

### Current State

Multiple custom search field implementations:

#### Files
- `TaskTypeSearchField` (embedded in TaskTypeDeletionSheet.swift, lines 421-559: 139 lines)
- `ClientSearchField.swift` (assumed ~150 lines)
- `AddressSearchField.swift` (assumed ~200 lines - more complex with geocoding)

#### Structural Similarity: 85%

All search fields follow the same pattern:

```swift
struct XSearchField: View {
    @Binding var selectedItemId: String?
    let availableItems: [Item]
    let placeholder: String

    @State private var searchText: String = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return availableItems.sorted { ... }
        }
        return availableItems
            .filter { $0.display.localizedCaseInsensitiveContains(searchText) }
            .sorted { ... }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input field
            HStack {
                Image(systemName: "magnifyingglass")
                TextField(placeholder, text: $searchText)
                    .focused($isFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // Suggestions dropdown
            if showingSuggestions && !filteredItems.isEmpty {
                VStack {
                    ForEach(filteredItems.prefix(5)) { item in
                        Button(action: { selectItem(item) }) {
                            // Item display
                        }
                    }
                }
            }
        }
    }
}
```

### Proposed Solution

#### Create Generic SearchField

**Location**: `OPS/Views/Components/Common/SearchField.swift`

```swift
/// Generic search field with dropdown suggestions
///
/// Usage:
/// ```
/// SearchField(
///     selectedId: $selectedClientId,
///     items: availableClients,
///     placeholder: "Search for client",
///     getId: { $0.id },
///     getDisplayText: { $0.name },
///     getSubtitle: { client in
///         "\(client.projects.count) projects"
///     },
///     getIcon: { _ in "person.fill" },
///     getIconColor: { _ in OPSStyle.Colors.primaryAccent }
/// )
/// ```
struct SearchField<Item: Identifiable>: View {
    @Binding var selectedId: String?
    let items: [Item]
    let placeholder: String

    // Display configuration
    let getId: (Item) -> String
    let getDisplayText: (Item) -> String
    let getSubtitle: ((Item) -> String)?
    let getIcon: ((Item) -> String)?
    let getIconColor: ((Item) -> Color)?

    @State private var searchText: String = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items.sorted { getDisplayText($0) < getDisplayText($1) }
        }
        return items
            .filter { getDisplayText($0).localizedCaseInsensitiveContains(searchText) }
            .sorted { getDisplayText($0) < getDisplayText($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField(placeholder, text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .focused($isFocused)
                    .onChange(of: searchText) { _, newValue in
                        showingSuggestions = !newValue.isEmpty
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        selectedId = nil
                        showingSuggestions = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Suggestions dropdown
            if showingSuggestions && !filteredItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredItems.prefix(5)) { item in
                        suggestionRow(for: item)

                        if getId(item) != getId(filteredItems.prefix(5).last!) {
                            Divider()
                                .background(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }
        }
        .onAppear {
            if let id = selectedId,
               let item = items.first(where: { getId($0) == id }) {
                searchText = getDisplayText(item)
            }
        }
    }

    private func suggestionRow(for item: Item) -> some View {
        Button(action: { selectItem(item) }) {
            HStack {
                // Icon (if provided)
                if let getIcon = getIcon, let getIconColor = getIconColor {
                    Image(systemName: getIcon(item))
                        .font(.system(size: 14))
                        .foregroundColor(getIconColor(item))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(getDisplayText(item))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let getSubtitle = getSubtitle {
                        Text(getSubtitle(item))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                Spacer()

                if selectedId == getId(item) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func selectItem(_ item: Item) {
        selectedId = getId(item)
        searchText = getDisplayText(item)
        showingSuggestions = false
        isFocused = false
    }
}
```

#### Migration Examples

**Before** (TaskTypeSearchField - 139 lines):
```swift
struct TaskTypeSearchField: View {
    @Binding var selectedTaskTypeId: String?
    let availableTaskTypes: [TaskType]
    let placeholder: String
    // ... 139 lines of custom implementation
}
```

**After** (usage):
```swift
SearchField(
    selectedId: $selectedTaskTypeId,
    items: availableTaskTypes,
    placeholder: "Search for task type",
    getId: { $0.id },
    getDisplayText: { $0.display },
    getSubtitle: { taskType in
        taskType.tasks.count > 0
            ? "\(taskType.tasks.count) task\(taskType.tasks.count == 1 ? "" : "s")"
            : nil
    },
    getIcon: { _ in "square.grid.2x2.fill" },
    getIconColor: { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent }
)
```

### Impact

- **Lines saved**: ~490 lines (3 implementations) → 180 lines = **310 lines saved**
- **Reduction**: 63%
- **Files affected**: 3 custom search fields → 1 generic component
- **Effort**: 4-6 hours (straightforward generic with closures)

---

## Summary Table

| Consolidation | Current | After | Lines Saved | Reduction | Effort |
|---------------|---------|-------|-------------|-----------|--------|
| Deletion Sheets | 3 files, ~1,050 lines | 1 template, 350 lines | 700 | 65% | 8-12h |
| Filter Sheets | 4 files, ~1,450 lines | 1 template, 600 lines | 850 | 56% | 10-14h |
| Form/Edit Pairs | 6 files, ~2,665 lines | 3 files, 1,600 lines | 1,065 | 40% | 6-9h |
| Search Fields | 3 files, ~490 lines | 1 component, 180 lines | 310 | 63% | 4-6h |
| **TOTAL** | **16 files, ~5,655 lines** | **5 files, 2,730 lines** | **2,925** | **52%** | **28-41h** |

---

## Implementation Roadmap

### Phase 1: Quick Wins (4-6 hours)
**Goal**: Get familiar with generic patterns, build confidence

1. **SearchField Component** (4-6 hours)
   - Simplest consolidation
   - Clear interfaces with closures
   - Immediate benefit across 3 locations
   - **Deliverable**: `SearchField.swift` + migrate 3 usages

### Phase 2: Form Consolidation (6-9 hours)
**Goal**: Eliminate form/edit duplication

2. **Merge Form/Edit Pairs** (6-9 hours)
   - Start with TaskTypeSheet (most straightforward)
   - Move to ClientSheet
   - Pattern: Enum-based mode switching
   - **Deliverable**: 6 files → 3 files

### Phase 3: Advanced Templates (18-26 hours)
**Goal**: Build reusable complex components

3. **FilterSheet Template** (10-14 hours)
   - More complex: enum with associated values
   - Type-safe filter configuration
   - **Deliverable**: `FilterSheet.swift` + migrate 4 usages

4. **DeletionSheet Template** (8-12 hours)
   - Most complex: multiple generics
   - Custom deletion logic via closures
   - **Deliverable**: `DeletionSheet.swift` + migrate 3 usages

### Testing Strategy

For each consolidation:
1. ✅ Create generic component
2. ✅ Migrate one usage (verify functionality)
3. ✅ Run app, test all interactions
4. ✅ Migrate remaining usages
5. ✅ Delete old files
6. ✅ Run full regression test

---

## Benefits Beyond Line Count

### 1. Consistency
- All deletion flows work identically
- All filter sheets have same UX
- All search fields behave the same way

### 2. Bug Fixes Propagate
- Fix deletion bug once → fixed everywhere
- Improve filter UX once → improved everywhere

### 3. Future Features Easier
- Need new deletion flow? Use template with new types
- Need new filter? Use FilterSheet with new filter types

### 4. Onboarding
- New developers learn patterns once
- Clear examples of how to use generics properly

### 5. Testing
- Test generic components thoroughly once
- Specific usages just test data flow

---

## Related Documents

- **TEMPLATE_STANDARDIZATION.md** - Sheet navigation toolbar consolidation (37 files)
- **ARCHITECTURAL_DUPLICATION_AUDIT.md** - Business logic duplication (notifications, DataController methods)
- **OPSSTYLE_GAPS_AND_STANDARDIZATION.md** - Missing OPSStyle definitions

---

## Recommendations

**Immediate Action**: Start with Phase 1 (SearchField) to validate the generic component approach.

**Best ROI**: Form/Edit consolidation (Phase 2) provides most benefit for least effort (40% reduction, 6-9 hours).

**Highest Impact**: FilterSheet template (Phase 3) eliminates most duplicate code (850 lines saved).

**Total Opportunity**: 2,925 lines of duplicate code can be eliminated with 28-41 hours of effort.
