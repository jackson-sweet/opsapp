# Track J+: Action-Based Data Operations

**Track ID**: J+ (Enhanced Track J from V1)
**Effort**: 6-8 hours
**Impact**: High - Centralizes 99 direct save() calls, consistent sync behavior
**Prerequisites**: None (independent track)

---

## Concept

Original Track J focused on consolidating direct `modelContext.save()` calls into DataController methods. Track J+ enhances this with an **action-based pattern** that separates "what" (the action) from "how" (the handler).

### Benefits Over Simple CRUD

1. **Single entry point**: All data operations go through `perform(_:)`
2. **Consistent error handling**: Handle all errors in one place
3. **Logging/audit trail**: Log every action automatically
4. **Undo support**: Actions can be reversible
5. **Sync coordination**: Automatically trigger sync after mutations
6. **Testing**: Actions can be unit tested in isolation

---

## Architecture

### DataAction Enum

**File**: `OPS/Utilities/DataController/DataAction.swift`

```swift
import Foundation

/// All data operations in the app, expressed as actions
enum DataAction {
    // MARK: - Project Actions
    case createProject(Project)
    case updateProject(Project)
    case deleteProject(Project)
    case updateProjectStatus(Project, Status)
    case assignTeamToProject(Project, [String])

    // MARK: - Task Actions
    case createTask(ProjectTask)
    case updateTask(ProjectTask)
    case deleteTask(ProjectTask)
    case updateTaskStatus(ProjectTask, TaskStatusOption)
    case assignTeamToTask(ProjectTask, [String])

    // MARK: - Client Actions
    case createClient(Client)
    case updateClient(Client)
    case deleteClient(Client)
    case reassignClientProjects(from: Client, to: Client)

    // MARK: - Calendar Event Actions
    case createCalendarEvent(CalendarEvent)
    case updateCalendarEvent(CalendarEvent)
    case deleteCalendarEvent(CalendarEvent)

    // MARK: - Task Type Actions
    case createTaskType(TaskType)
    case updateTaskType(TaskType)
    case deleteTaskType(TaskType)
    case reassignTaskTypesTasks(from: TaskType, to: TaskType)

    // MARK: - Batch Actions
    case batchUpdateProjectStatuses([Project], Status)
    case batchDeleteTasks([ProjectTask])

    // MARK: - Action Metadata
    var description: String {
        switch self {
        case .createProject(let p): return "Create project: \(p.title ?? "untitled")"
        case .updateProject(let p): return "Update project: \(p.title ?? "untitled")"
        case .deleteProject(let p): return "Delete project: \(p.title ?? "untitled")"
        case .updateProjectStatus(let p, let s): return "Update project \(p.title ?? "untitled") status to \(s.rawValue)"
        case .assignTeamToProject(let p, let ids): return "Assign \(ids.count) members to \(p.title ?? "untitled")"
        case .createTask(let t): return "Create task: \(t.title ?? "untitled")"
        case .updateTask(let t): return "Update task: \(t.title ?? "untitled")"
        case .deleteTask(let t): return "Delete task: \(t.title ?? "untitled")"
        case .updateTaskStatus(let t, let s): return "Update task \(t.title ?? "untitled") status to \(s.name ?? "unknown")"
        case .assignTeamToTask(let t, let ids): return "Assign \(ids.count) members to \(t.title ?? "untitled")"
        case .createClient(let c): return "Create client: \(c.name)"
        case .updateClient(let c): return "Update client: \(c.name)"
        case .deleteClient(let c): return "Delete client: \(c.name)"
        case .reassignClientProjects(let from, let to): return "Reassign projects from \(from.name) to \(to.name)"
        case .createCalendarEvent: return "Create calendar event"
        case .updateCalendarEvent: return "Update calendar event"
        case .deleteCalendarEvent: return "Delete calendar event"
        case .createTaskType(let tt): return "Create task type: \(tt.name)"
        case .updateTaskType(let tt): return "Update task type: \(tt.name)"
        case .deleteTaskType(let tt): return "Delete task type: \(tt.name)"
        case .reassignTaskTypesTasks(let from, let to): return "Reassign tasks from \(from.name) to \(to.name)"
        case .batchUpdateProjectStatuses(let projects, let s): return "Batch update \(projects.count) projects to \(s.rawValue)"
        case .batchDeleteTasks(let tasks): return "Batch delete \(tasks.count) tasks"
        }
    }

    var requiresSync: Bool {
        switch self {
        case .createProject, .updateProject, .deleteProject,
             .createTask, .updateTask, .deleteTask,
             .createClient, .updateClient, .deleteClient,
             .createCalendarEvent, .updateCalendarEvent, .deleteCalendarEvent,
             .createTaskType, .updateTaskType, .deleteTaskType,
             .updateProjectStatus, .updateTaskStatus,
             .assignTeamToProject, .assignTeamToTask,
             .reassignClientProjects, .reassignTaskTypesTasks,
             .batchUpdateProjectStatuses, .batchDeleteTasks:
            return true
        }
    }

    var syncPriority: Int {
        switch self {
        case .deleteProject, .deleteTask, .deleteClient, .deleteTaskType, .deleteCalendarEvent:
            return 5 // High priority - deletions should sync immediately
        case .updateProjectStatus, .updateTaskStatus:
            return 4 // Status changes are important
        case .createProject, .createTask, .createClient, .createTaskType, .createCalendarEvent:
            return 3 // Creates are normal priority
        default:
            return 2 // Updates are lower priority
        }
    }
}
```

---

## Action Handler

**File**: `OPS/Utilities/DataController/DataController+Actions.swift`

```swift
import SwiftUI
import SwiftData

extension DataController {

    /// Perform a data action with automatic sync, error handling, and logging
    ///
    /// Usage:
    /// ```swift
    /// try await dataController.perform(.createProject(newProject))
    /// try await dataController.perform(.updateTaskStatus(task, newStatus))
    /// ```
    @MainActor
    func perform(_ action: DataAction) async throws {
        // Log action
        print("[DataAction] Performing: \(action.description)")

        do {
            // Execute action-specific logic
            try await executeAction(action)

            // Save to SwiftData
            try modelContext?.save()

            // Trigger sync if needed
            if action.requiresSync {
                await triggerSync(priority: action.syncPriority)
            }

            print("[DataAction] Completed: \(action.description)")

        } catch {
            print("[DataAction] Failed: \(action.description) - \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Action Execution

    @MainActor
    private func executeAction(_ action: DataAction) async throws {
        switch action {
        // MARK: Project Actions
        case .createProject(let project):
            modelContext?.insert(project)
            project.needsSync = true
            project.syncPriority = action.syncPriority

        case .updateProject(let project):
            project.needsSync = true
            project.syncPriority = action.syncPriority
            project.modifiedAt = Date()

        case .deleteProject(let project):
            project.deletedAt = Date()
            project.needsSync = true
            project.syncPriority = action.syncPriority

        case .updateProjectStatus(let project, let status):
            project.status = status
            project.needsSync = true
            project.syncPriority = action.syncPriority

            // Auto-set timestamps based on status
            if status == .inProgress && project.startDate == nil {
                project.startDate = Date()
            }
            if status == .completed && project.completedAt == nil {
                project.completedAt = Date()
            }

        case .assignTeamToProject(let project, let memberIds):
            project.teamMemberIds = memberIds
            project.needsSync = true
            project.syncPriority = action.syncPriority

        // MARK: Task Actions
        case .createTask(let task):
            modelContext?.insert(task)
            task.needsSync = true
            task.syncPriority = action.syncPriority

        case .updateTask(let task):
            task.needsSync = true
            task.syncPriority = action.syncPriority
            task.modifiedAt = Date()

        case .deleteTask(let task):
            task.deletedAt = Date()
            task.needsSync = true
            task.syncPriority = action.syncPriority

        case .updateTaskStatus(let task, let status):
            task.status = status
            task.needsSync = true
            task.syncPriority = action.syncPriority

            // Auto-set completed timestamp
            if status.isCompletedStatus && task.completedAt == nil {
                task.completedAt = Date()
            }

        case .assignTeamToTask(let task, let memberIds):
            task.assignedUserIds = memberIds
            task.needsSync = true
            task.syncPriority = action.syncPriority

        // MARK: Client Actions
        case .createClient(let client):
            modelContext?.insert(client)
            client.needsSync = true

        case .updateClient(let client):
            client.needsSync = true
            client.modifiedAt = Date()

        case .deleteClient(let client):
            client.deletedAt = Date()
            client.needsSync = true

        case .reassignClientProjects(let fromClient, let toClient):
            for project in fromClient.projects {
                project.client = toClient
                project.clientId = toClient.id
                project.needsSync = true
            }

        // MARK: Calendar Event Actions
        case .createCalendarEvent(let event):
            modelContext?.insert(event)
            event.needsSync = true

        case .updateCalendarEvent(let event):
            event.needsSync = true
            event.modifiedAt = Date()

        case .deleteCalendarEvent(let event):
            event.deletedAt = Date()
            event.needsSync = true

        // MARK: Task Type Actions
        case .createTaskType(let taskType):
            modelContext?.insert(taskType)
            taskType.needsSync = true

        case .updateTaskType(let taskType):
            taskType.needsSync = true
            taskType.modifiedAt = Date()

        case .deleteTaskType(let taskType):
            taskType.deletedAt = Date()
            taskType.needsSync = true

        case .reassignTaskTypesTasks(let fromType, let toType):
            for task in fromType.tasks {
                task.taskType = toType
                task.taskTypeId = toType.id
                task.needsSync = true
            }

        // MARK: Batch Actions
        case .batchUpdateProjectStatuses(let projects, let status):
            for project in projects {
                project.status = status
                project.needsSync = true
                project.syncPriority = action.syncPriority
            }

        case .batchDeleteTasks(let tasks):
            let now = Date()
            for task in tasks {
                task.deletedAt = now
                task.needsSync = true
                task.syncPriority = action.syncPriority
            }
        }
    }

    // MARK: - Sync Triggering

    @MainActor
    private func triggerSync(priority: Int) async {
        // High priority actions trigger immediate sync
        if priority >= 4 {
            Task {
                try? await syncManager?.syncAll(forceRefresh: false)
            }
        } else {
            // Lower priority actions use debounced sync
            syncManager?.scheduleDebouncedSync()
        }
    }
}
```

---

## Migration Guide

### Before (Direct Save)

```swift
// ProjectDetailsView.swift
func updateStatus(_ newStatus: Status) {
    project.status = newStatus
    project.needsSync = true
    project.syncPriority = 3

    if newStatus == .inProgress && project.startDate == nil {
        project.startDate = Date()
    }

    try? modelContext.save()

    Task {
        try? await syncManager.syncProjects(forceRefresh: false)
    }
}
```

### After (Action-Based)

```swift
// ProjectDetailsView.swift
func updateStatus(_ newStatus: Status) {
    Task {
        try? await dataController.perform(.updateProjectStatus(project, newStatus))
    }
}
```

**Lines saved per call**: ~10-15 lines
**Total files to migrate**: ~30 files with 99 direct save() calls

---

## Implementation Plan

### Phase 1: Create Action Infrastructure (2 hours)

1. Create `OPS/Utilities/DataController/DataAction.swift`
2. Create `OPS/Utilities/DataController/DataController+Actions.swift`
3. Build and verify no compilation errors

### Phase 2: Migrate Project Operations (2 hours)

Files to migrate:
1. ProjectFormSheet.swift - create/update project
2. ProjectDetailsView.swift - update status, delete
3. ProjectActionBar.swift - status changes
4. JobBoardView.swift - project operations
5. HomeView.swift - quick actions

### Phase 3: Migrate Task Operations (1.5 hours)

Files to migrate:
1. TaskFormSheet.swift - create/update task
2. TaskDetailsView.swift - update status, delete
3. TaskListView.swift - quick actions
4. TaskCompletionChecklistSheet.swift - status updates

### Phase 4: Migrate Client/Other Operations (1.5 hours)

Files to migrate:
1. ClientSheet.swift - create/update client
2. DeletionSheet usage sites - delete operations
3. TaskTypeSheet.swift - task type operations
4. CalendarSchedulerSheet.swift - event operations

### Phase 5: Remove Old Methods (1 hour)

1. Remove `ProjectsViewModel.updateProjectStatus()` (duplicate)
2. Remove direct `modelContext.save()` calls
3. Update any remaining direct `needsSync = true` assignments
4. Verify all operations go through `perform(_:)`

---

## Verification

### Before Migration

```bash
# Count direct save calls
grep -r "modelContext\.save\(\)" OPS/Views OPS/ViewModels | wc -l
# Expected: 99+

# Count direct needsSync assignments
grep -r "needsSync = true" OPS/Views OPS/ViewModels | wc -l
# Expected: 25+
```

### After Migration

```bash
# Direct save calls (should be 0 in Views/ViewModels)
grep -r "modelContext\.save\(\)" OPS/Views OPS/ViewModels | wc -l
# Expected: 0

# Action-based calls
grep -r "dataController\.perform\(" OPS/Views OPS/ViewModels | wc -l
# Expected: 60+
```

### Manual Testing

1. Create a project - verify it syncs
2. Update project status - verify it syncs
3. Delete a task - verify soft delete + sync
4. Batch operations - verify all items sync
5. Check console logs for `[DataAction]` entries

---

## Error Handling

The `perform(_:)` method provides centralized error handling:

```swift
// In views, wrap in do-catch for user feedback
func saveProject() {
    Task {
        do {
            try await dataController.perform(.createProject(project))
            dismiss()
        } catch {
            appState.showError(error.localizedDescription)
        }
    }
}
```

For fire-and-forget operations:
```swift
// Quick status update - errors logged but not shown
Task {
    try? await dataController.perform(.updateProjectStatus(project, .inProgress))
}
```

---

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| Direct save() calls | 99 | 0 |
| needsSync assignments | 25+ scattered | 1 location |
| Sync trigger points | 30+ | 1 |
| Error handling | Inconsistent | Centralized |
| Logging | None/inconsistent | Automatic |
| Lines of data code | ~600 | ~200 |

---

## Handover Notes

When completing Track J+, document in LIVE_HANDOVER.md:

1. Which DataAction cases were implemented
2. How many files were migrated
3. Any actions that needed special handling
4. Sync behavior observations
5. Edge cases discovered

---

**Next**: After Track J+, consider Track L (DataController refactoring) to organize the DataController file structure.
