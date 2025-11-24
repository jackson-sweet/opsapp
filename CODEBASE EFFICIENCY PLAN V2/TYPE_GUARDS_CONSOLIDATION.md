# Track T: Type Guards Consolidation

**Track ID**: T (New in V2)
**Effort**: 3-4 hours
**Impact**: Medium - Centralizes validation logic, improves readability
**Prerequisites**: None (independent track)

---

## Concept

Apple's codebase uses type guards extensively (`isNavigationItem()`, `isShelfAction()`) for safe type narrowing. OPS has scattered optional chaining and nil checks that should be centralized into named, reusable functions.

### Benefits

1. **Self-documenting code**: `isActiveProject(project)` vs `project.status != .completed && project.status != .cancelled && project.deletedAt == nil`
2. **Single source of truth**: Business rules defined once
3. **Easier maintenance**: Change validation in one place
4. **Better testing**: Guards can be unit tested
5. **Reduced bugs**: Consistent validation everywhere

---

## T1: Project Type Guards

### Current Pattern (Scattered)

Found in 15+ files:
```swift
// Different variations of "is this project active?"
if project.status != .completed && project.status != .cancelled { }
if project.deletedAt == nil { }
if project.status == .inProgress || project.status == .accepted { }
if !project.isCompleted && !project.isCancelled { }
```

### Proposed Guards

**File**: `OPS/Utilities/TypeGuards/ProjectGuards.swift`

```swift
import Foundation

// MARK: - Project Status Guards

/// Returns true if project is in an active state (not completed/cancelled/deleted)
func isActiveProject(_ project: Project?) -> Bool {
    guard let project = project else { return false }
    guard project.deletedAt == nil else { return false }
    return project.status != .completed && project.status != .cancelled
}

/// Returns true if project is visible in lists (not soft-deleted)
func isVisibleProject(_ project: Project?) -> Bool {
    guard let project = project else { return false }
    return project.deletedAt == nil
}

/// Returns true if project can be edited by the current user
func canEditProject(_ project: Project?, user: User?) -> Bool {
    guard let project = project, let user = user else { return false }
    guard project.deletedAt == nil else { return false }

    // Admins and office crew can edit any project
    if user.role == .admin || user.role == .officeCrew { return true }

    // Field crew can only edit projects they're assigned to
    if user.role == .fieldCrew {
        return project.teamMemberIds?.contains(user.id) ?? false
    }

    return false
}

/// Returns true if project can be deleted
func canDeleteProject(_ project: Project?, user: User?) -> Bool {
    guard let project = project, let user = user else { return false }
    guard project.deletedAt == nil else { return false }

    // Only admins can delete projects
    return user.role == .admin
}

/// Returns true if project has valid scheduling data
func hasValidSchedule(_ project: Project?) -> Bool {
    guard let project = project else { return false }
    return project.computedStartDate != nil || project.computedEndDate != nil
}

/// Returns true if project has a valid client
func hasValidClient(_ project: Project?) -> Bool {
    guard let project = project else { return false }
    return project.client != nil && project.clientId != nil
}

/// Returns true if project needs sync
func needsSync(_ project: Project?) -> Bool {
    guard let project = project else { return false }
    return project.needsSync == true
}
```

### Migration Examples

**Before**:
```swift
// JobBoardView.swift line 145
let activeProjects = projects.filter {
    $0.deletedAt == nil &&
    $0.status != .completed &&
    $0.status != .cancelled
}
```

**After**:
```swift
let activeProjects = projects.filter { isActiveProject($0) }
```

**Before**:
```swift
// ProjectDetailsView.swift line 234
if project.deletedAt == nil && (user.role == .admin || user.role == .officeCrew ||
   (user.role == .fieldCrew && project.teamMemberIds?.contains(user.id) == true)) {
    showEditButton = true
}
```

**After**:
```swift
showEditButton = canEditProject(project, user: user)
```

---

## T2: Task Type Guards

### Current Pattern

Found in 10+ files:
```swift
if task.status != .completed && task.deletedAt == nil { }
if task.isComplete { } // computed property, but inconsistent usage
if task.dueDate != nil && task.dueDate! < Date() { } // overdue check
```

### Proposed Guards

**File**: `OPS/Utilities/TypeGuards/TaskGuards.swift`

```swift
import Foundation

// MARK: - Task Status Guards

/// Returns true if task is in an active state
func isActiveTask(_ task: ProjectTask?) -> Bool {
    guard let task = task else { return false }
    guard task.deletedAt == nil else { return false }
    return task.status != .completed && task.status != .cancelled
}

/// Returns true if task is visible in lists
func isVisibleTask(_ task: ProjectTask?) -> Bool {
    guard let task = task else { return false }
    return task.deletedAt == nil
}

/// Returns true if task is overdue
func isOverdueTask(_ task: ProjectTask?) -> Bool {
    guard let task = task else { return false }
    guard isActiveTask(task) else { return false }
    guard let dueDate = task.dueDate else { return false }
    return dueDate < Date()
}

/// Returns true if task is due today
func isDueToday(_ task: ProjectTask?) -> Bool {
    guard let task = task else { return false }
    guard let dueDate = task.dueDate else { return false }
    return Calendar.current.isDateInToday(dueDate)
}

/// Returns true if task can be edited by user
func canEditTask(_ task: ProjectTask?, user: User?) -> Bool {
    guard let task = task, let user = user else { return false }
    guard task.deletedAt == nil else { return false }

    // Admin and office crew can edit any task
    if user.role == .admin || user.role == .officeCrew { return true }

    // Field crew can edit tasks on projects they're assigned to
    if user.role == .fieldCrew {
        return task.project?.teamMemberIds?.contains(user.id) ?? false
    }

    return false
}

/// Returns true if task can have status changed by user
func canChangeTaskStatus(_ task: ProjectTask?, user: User?) -> Bool {
    guard let task = task, let user = user else { return false }
    guard task.deletedAt == nil else { return false }

    // All authenticated users can change task status on assigned projects
    if user.role == .fieldCrew {
        return task.project?.teamMemberIds?.contains(user.id) ?? false
    }

    return true
}
```

---

## T3: User/Permission Guards

### Current Pattern

```swift
if user.role == .admin { }
if user.role == .admin || user.role == .officeCrew { }
if dataController.currentUser?.role != .fieldCrew { }
```

### Proposed Guards

**File**: `OPS/Utilities/TypeGuards/UserGuards.swift`

```swift
import Foundation

// MARK: - User Permission Guards

/// Returns true if user is an admin
func isAdmin(_ user: User?) -> Bool {
    user?.role == .admin
}

/// Returns true if user has office-level access (admin or office crew)
func hasOfficeAccess(_ user: User?) -> Bool {
    guard let user = user else { return false }
    return user.role == .admin || user.role == .officeCrew
}

/// Returns true if user is field crew
func isFieldCrew(_ user: User?) -> Bool {
    user?.role == .fieldCrew
}

/// Returns true if user can manage team members
func canManageTeam(_ user: User?) -> Bool {
    guard let user = user else { return false }
    return user.role == .admin
}

/// Returns true if user can access settings
func canAccessSettings(_ user: User?) -> Bool {
    guard let user = user else { return false }
    return user.role == .admin || user.role == .officeCrew
}

/// Returns true if user can create projects
func canCreateProjects(_ user: User?) -> Bool {
    guard let user = user else { return false }
    return user.role == .admin || user.role == .officeCrew
}

/// Returns true if user is authenticated and valid
func isValidUser(_ user: User?) -> Bool {
    guard let user = user else { return false }
    return !user.id.isEmpty && user.companyId != nil
}
```

---

## T4: Calendar Event Guards

### Proposed Guards

**File**: `OPS/Utilities/TypeGuards/CalendarEventGuards.swift`

```swift
import Foundation

// MARK: - Calendar Event Guards

/// Returns true if event should be displayed based on project scheduling mode
func shouldDisplayEvent(_ event: CalendarEvent?) -> Bool {
    guard let event = event else { return false }
    guard event.deletedAt == nil else { return false }

    // Use the model's shouldDisplay computed property
    return event.shouldDisplay
}

/// Returns true if event is in the given date range
func isEventInRange(_ event: CalendarEvent?, start: Date, end: Date) -> Bool {
    guard let event = event else { return false }
    guard let eventStart = event.startDate else { return false }

    let eventEnd = event.endDate ?? eventStart
    return eventStart <= end && eventEnd >= start
}

/// Returns true if event is today
func isEventToday(_ event: CalendarEvent?) -> Bool {
    guard let event = event else { return false }
    guard let startDate = event.startDate else { return false }
    return Calendar.current.isDateInToday(startDate)
}
```

---

## Implementation Plan

### Phase 1: Create Guard Files (1 hour)

1. Create `OPS/Utilities/TypeGuards/` folder
2. Create ProjectGuards.swift
3. Create TaskGuards.swift
4. Create UserGuards.swift
5. Create CalendarEventGuards.swift
6. Build and verify

### Phase 2: Migrate High-Impact Files (1.5 hours)

Priority order:
1. JobBoardView.swift - filter active projects
2. HomeView.swift - filter displayed projects
3. CalendarViewModel.swift - event filtering
4. ProjectDetailsView.swift - permission checks
5. TaskDetailsView.swift - permission checks

### Phase 3: Migrate Remaining Files (1 hour)

6. TaskListView.swift
7. ClientListView.swift
8. Settings views (permission checks)
9. Form sheets (validation)

### Phase 4: Documentation (30 min)

1. Add TypeGuards section to COMPONENTS.md
2. Document each guard with example usage
3. Update LIVE_HANDOVER.md

---

## Verification

### Pattern Search (Before)

```bash
# Count scattered validation patterns
grep -r "deletedAt == nil" OPS/Views | wc -l
grep -r "\.status != \.completed" OPS/Views | wc -l
grep -r "role == \.admin" OPS/Views | wc -l
```

### Pattern Search (After)

```bash
# Should see significant reduction after migration
grep -r "isActiveProject\|isVisibleProject\|canEditProject" OPS/Views | wc -l
grep -r "isActiveTask\|canEditTask" OPS/Views | wc -l
grep -r "isAdmin\|hasOfficeAccess" OPS/Views | wc -l
```

### Manual Test

1. Filter projects in Job Board - verify only active shown
2. Check edit permissions - verify correct buttons shown/hidden
3. Change user role - verify permissions update

---

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| Validation patterns | 60+ scattered | 20 centralized guards |
| Lines of validation code | ~180 | ~80 |
| Permission check consistency | Varies | 100% consistent |
| Bug potential | High (copy/paste) | Low (single source) |

---

## Handover Notes

When completing Track T, document in LIVE_HANDOVER.md:

1. Which guard files were created
2. How many files were migrated
3. Any business rules discovered during migration
4. Edge cases that needed special handling
5. Guards that might need additional parameters

---

**Next**: After Track T, consider Track J+ (Action-Based Operations) to centralize data operations.
