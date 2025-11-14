# Query Predicate Update Guide - Soft Delete Support

## Overview

All queries that fetch data models must now exclude soft-deleted records by checking `deletedAt == nil`. This ensures that deleted records are hidden from the UI while being preserved in the database for historical purposes.

## Models Requiring Query Updates

The following models now have `deletedAt: Date?` field:
- Project
- ProjectTask
- CalendarEvent
- Client
- SubClient
- User
- TaskType
- Company

## How to Update Queries

### SwiftUI @Query Syntax

#### OLD (Before soft delete):
```swift
@Query var projects: [Project]
```

#### NEW (With soft delete):
```swift
@Query(filter: #Predicate<Project> { $0.deletedAt == nil })
var projects: [Project]
```

### FetchDescriptor Syntax

#### OLD (Before soft delete):
```swift
let descriptor = FetchDescriptor<Project>()
```

#### NEW (With soft delete):
```swift
let descriptor = FetchDescriptor<Project>(
    predicate: #Predicate { $0.deletedAt == nil }
)
```

### Combined Predicates

If you already have predicates, combine them with the deletedAt check:

#### OLD:
```swift
@Query(filter: #Predicate<Project> { project in
    project.status == .inProgress
})
var activeProjects: [Project]
```

#### NEW:
```swift
@Query(filter: #Predicate<Project> { project in
    project.status == .inProgress && project.deletedAt == nil
})
var activeProjects: [Project]
```

#### OLD (FetchDescriptor):
```swift
let descriptor = FetchDescriptor<Task>(
    predicate: #Predicate { $0.projectId == projectId }
)
```

#### NEW (FetchDescriptor):
```swift
let descriptor = FetchDescriptor<Task>(
    predicate: #Predicate { $0.projectId == projectId && $0.deletedAt == nil }
)
```

## Examples by Model Type

### Projects

```swift
// All projects (excluding deleted)
@Query(filter: #Predicate<Project> { $0.deletedAt == nil })
var projects: [Project]

// Active projects only
@Query(filter: #Predicate<Project> { project in
    project.status == .inProgress && project.deletedAt == nil
})
var activeProjects: [Project]

// Projects for a specific company
@Query(filter: #Predicate<Project> { project in
    project.companyId == companyId && project.deletedAt == nil
})
var companyProjects: [Project]
```

### Tasks

```swift
// All tasks for a project
@Query(filter: #Predicate<ProjectTask> { task in
    task.projectId == projectId && task.deletedAt == nil
})
var projectTasks: [ProjectTask]

// Scheduled tasks only
@Query(filter: #Predicate<ProjectTask> { task in
    task.status == .scheduled && task.deletedAt == nil
})
var scheduledTasks: [ProjectTask]
```

### Calendar Events

```swift
// All calendar events
@Query(filter: #Predicate<CalendarEvent> { $0.deletedAt == nil })
var calendarEvents: [CalendarEvent]

// Active events for a project
@Query(filter: #Predicate<CalendarEvent> { event in
    event.projectId == projectId &&
    event.active == true &&
    event.deletedAt == nil
})
var activeProjectEvents: [CalendarEvent]
```

### Clients

```swift
// All clients
@Query(filter: #Predicate<Client> { $0.deletedAt == nil })
var clients: [Client]

// Clients for a specific company
@Query(filter: #Predicate<Client> { client in
    client.companyId == companyId && client.deletedAt == nil
})
var companyClients: [Client]
```

### Users

```swift
// All active users
@Query(filter: #Predicate<User> { user in
    user.isActive && user.deletedAt == nil
})
var activeUsers: [User]

// Users for a specific company
@Query(filter: #Predicate<User> { user in
    user.companyId == companyId && user.deletedAt == nil
})
var companyUsers: [User]
```

### Task Types

```swift
// All task types for a company
@Query(filter: #Predicate<TaskType> { type in
    type.companyId == companyId && type.deletedAt == nil
})
var taskTypes: [TaskType]

// Default task types only
@Query(filter: #Predicate<TaskType> { type in
    type.isDefault && type.deletedAt == nil
})
var defaultTaskTypes: [TaskType]
```

## Files Likely Requiring Updates

Search for these patterns throughout the Views directory:

### Pattern 1: @Query declarations
```bash
grep -r "@Query" OPS/Views/
```

### Pattern 2: FetchDescriptor usage
```bash
grep -r "FetchDescriptor" OPS/Views/
grep -r "FetchDescriptor" OPS/Utilities/
```

### High-Priority Views to Update:

1. **HomeView.swift** - Main project list
2. **CalendarView.swift** - Calendar events
3. **JobBoardView.swift** - Active tasks
4. **ProjectDetailsView.swift** - Project tasks
5. **ClientListView.swift** - Client list
6. **TeamMembersView.swift** - User list
7. **TaskSettingsView.swift** - Task types
8. **TaskDetailsView.swift** - Task info

## Testing After Updates

After adding predicates, verify:

1. **Deleted items don't appear** - Soft delete a project/task/client and confirm it disappears from lists
2. **Active items still show** - Normal items still display correctly
3. **Counts are correct** - Dashboard counts exclude deleted items
4. **Search works** - Search doesn't find deleted items
5. **Performance** - Queries remain performant with additional predicate

## Migration Strategy

### Phase 1: Critical Views (Do First)
- HomeView (project list)
- CalendarView (calendar events)
- JobBoardView (task board)

### Phase 2: Detail Views
- ProjectDetailsView
- TaskDetailsView
- ClientDetailsView

### Phase 3: Settings & Admin
- TaskSettingsView
- TeamMembersView
- CompanySettingsView

### Phase 4: Secondary Views
- Search views
- Filter views
- Archive views

## Important Notes

1. **Performance**: Adding `deletedAt == nil` to predicates is very efficient - it's a simple null check indexed by SwiftData

2. **Historical Data**: Never hard-delete records unless explicitly required for data cleanup

3. **Debugging**: If a record mysteriously disappears, check if `deletedAt` was accidentally set

4. **Testing**: After each view update, test that soft-deleted items don't appear

## Example PR Changes

When creating a PR for query updates:

```markdown
## Query Predicate Updates for Soft Delete Support

### Changes
- Added `deletedAt == nil` predicate to all @Query declarations
- Updated FetchDescriptor queries to exclude soft-deleted records

### Files Modified
- HomeView.swift: Updated project queries
- CalendarView.swift: Updated calendar event queries
- JobBoardView.swift: Updated task queries
- [etc.]

### Testing
- ✅ Verified deleted projects don't appear in home view
- ✅ Verified deleted tasks removed from job board
- ✅ Verified deleted calendar events hidden
- ✅ Confirmed counts exclude deleted items
```

## Rollback Plan

If issues arise, you can temporarily show deleted items by:

1. Commenting out the `deletedAt == nil` check
2. OR adding a filter toggle in the UI to show/hide deleted items

```swift
// Temporary: Show all items including deleted
@Query var projects: [Project]

// Production: Hide deleted items
@Query(filter: #Predicate<Project> { $0.deletedAt == nil })
var projects: [Project]
```
