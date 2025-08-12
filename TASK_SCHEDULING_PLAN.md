# Task-Based Scheduling Implementation Plan
*Version 2.0.0 Architecture*

## Executive Summary
Fundamental restructuring of project scheduling to support granular task management, enabling complex multi-phase projects while maintaining simplicity for basic projects.

## Core Architecture

### Data Model Hierarchy
```
Company
├── defaultProjectColor (hex color for project-level events)
├── TaskTypes (reusable task templates)
│   ├── Color (hex)
│   ├── Display (name)
│   ├── Icon (symbol name)
│   └── isDefault (bool)
└── Projects
    ├── CalendarEvent (if no tasks)
    └── Tasks
        ├── taskType → TaskType
        ├── taskColor (inherited from TaskType)
        ├── taskNotes
        ├── status (Scheduled/In Progress/Completed/Cancelled)
        ├── teamMembers (inherited to CalendarEvent)
        └── CalendarEvent
            ├── startDate
            ├── endDate
            ├── duration
            ├── title (inherited from TaskType.Display)
            ├── color (inherited from Task.taskColor)
            └── teamMembers (inherited from Task)
```

## New Data Models

### Task
```swift
struct Task {
    let id: String
    let calendarEventId: String?  // Optional per requirement
    let companyId: String
    let projectId: String
    let status: TaskStatus  // Scheduled, In Progress, Completed, Cancelled
    let taskColor: String  // Hex color code
    let taskNotes: String?
    let teamMembers: [String]  // User IDs
    let taskTypeId: String  // Reference to TaskType
}
```

### TaskType
```swift
struct TaskType {
    let id: String
    let color: String  // Hex color
    let isDefault: Bool
    let display: String  // Name like "Quote", "Installation"
    let icon: String?  // SF Symbol name
    let companyId: String
}
```

### CalendarEvent
```swift
struct CalendarEvent {
    let id: String
    let color: String  // Hex value
    let companyId: String
    let projectId: String
    let taskId: String?  // Optional - nil means project-level event
    let duration: Int  // Days
    let endDate: Date
    let startDate: Date
    let teamMembers: [String]
    let title: String
    let type: CalendarEventType
}
```

## Inheritance Rules

### Color Inheritance
```
TaskType.Color → Task.taskColor → CalendarEvent.color
OR
Company.defaultProjectColor → CalendarEvent.color (if no task)
```

### Title Inheritance
```
TaskType.Display → CalendarEvent.title (for task events)
OR
Project.title → CalendarEvent.title (for project events)
```

### Team Member Inheritance
```
Task.teamMembers → CalendarEvent.teamMembers (for task events)
OR
Project.teamMembers → CalendarEvent.teamMembers (for project events)
```

## Permission Matrix

| Feature | Admin | Office Crew | Field Crew |
|---------|-------|-------------|------------|
| View Tasks | ✅ | ✅ | ✅ |
| Create Tasks | ✅ | ✅ | ❌ |
| Edit Tasks | ✅ | ✅ | ❌ |
| Delete Tasks | ✅ | ✅ | ❌ |
| Update Task Status | ✅ | ✅ | ✅ |
| Manage TaskTypes | ✅ | ✅ | ❌ |
| Edit Project Settings | ✅ | ✅ | ❌ |
| Edit Default Colors | ✅ | ✅ | ❌ |

## UI/UX Implementation

### Calendar View Updates
- Task events show TaskType icon badge
- Color coding: Task colors vs default project color
- Quick status indicator on calendar cards
- Tap behavior: Show task detail sheet (low detent)

### Project Detail View Structure
```
Project Header
├── Status Badge
├── Title
└── Client Info

Dates Section (computed)
├── Start: First task start date OR project event start
└── End: Last task end date OR project event end

Location/Map Section

Tasks Section (NEW - Above notes)
├── Task Card (Collapsed)
│   ├── TaskType Icon & Name
│   ├── Status Badge
│   └── Progress Indicator
└── Task Card (Expanded)
    ├── All above +
    ├── Team Members
    ├── Start/End Dates
    └── Quick Actions (Start/Complete)

Project Notes Section
Photos Section
Team Section
```

### New Settings: Project Settings
*Admin/Office Crew Only*
```
Project Settings
├── Task Type Management
│   ├── View Default Types (read-only)
│   ├── Create Custom Types
│   ├── Edit Custom Types
│   └── Set Icons & Colors
└── Color Settings
    ├── Default Project Color
    └── Task Type Colors
```

## Sync Strategy

### Sync Types
1. **Full Data Sync**
   - Everything: Company, Projects, Tasks, TaskTypes, CalendarEvents, Users
   - Triggered: Login, manual refresh, major app update

2. **Project Sync**
   - Projects + Tasks + CalendarEvents
   - Triggered: Project refresh, status changes, calendar view

3. **Organization Sync**
   - Company + TaskTypes + Users
   - Triggered: Settings changes, team updates

### Sync Priority (High to Low)
1. CalendarEvents (time-sensitive)
2. Tasks (status updates)
3. Projects
4. TaskTypes (rarely change)
5. Company settings

### Offline Queue Priority
1. Task status changes
2. Task creation/edits
3. Project updates
4. Settings changes

## Implementation Phases

### Phase 1: Data Layer (Week 1)
- [ ] Create Task, TaskType, CalendarEvent models
- [ ] Update Project model with task relationships
- [ ] Implement DTOs for API communication
- [ ] Add sync logic for new objects

### Phase 2: Calendar Integration (Week 2)
- [ ] Update calendar views to show CalendarEvents
- [ ] Implement task event vs project event detection
- [ ] Add color and icon rendering
- [ ] Update date calculations for multi-task projects

### Phase 3: Project Details (Week 3)
- [ ] Add Tasks section to ProjectDetailsView
- [ ] Implement expandable task cards
- [ ] Add quick action buttons
- [ ] Update date display logic

### Phase 4: Task Management (Week 4)
- [ ] Create task detail sheet
- [ ] Implement task creation/editing (Admin/Office)
- [ ] Add status update functionality
- [ ] Build TaskType picker

### Phase 5: Settings & Polish (Week 5)
- [ ] Create Project Settings view
- [ ] Implement TaskType management
- [ ] Add color customization
- [ ] Icon picker for TaskTypes

## Status Update Logic

### Starting a Task
```swift
func startTask(task: Task) {
    // 1. Update task status
    task.status = .inProgress
    
    // 2. Check if first active task
    if project.tasks.filter({ $0.status == .inProgress }).count == 1 {
        project.status = .inProgress
    }
    
    // 3. Queue sync
    syncManager.queueTaskUpdate(task)
}
```

### Completing a Task
```swift
func completeTask(task: Task) {
    // 1. Update task status
    task.status = .completed
    
    // 2. Check if all tasks complete
    if project.tasks.allSatisfy({ $0.status == .completed }) {
        project.status = .completed
    }
    
    // 3. Queue sync
    syncManager.queueTaskUpdate(task)
}
```

## Migration Considerations

### Handling Existing Projects
- Backend will handle data migration
- Mobile app will receive tasks via normal sync
- Gracefully handle projects with/without tasks
- No user action required

### First Task Creation
- When adding first task to scheduled project:
  - Initialize with project's CalendarEvent dates
  - Allow user to modify
  - Delete or hide original project CalendarEvent

## Search & Filtering Updates

### New Search Filters
- Filter by TaskType
- Filter by Task Status
- Binary filter: Has Tasks / No Tasks
- NOT searching task names/notes (keep it simple)

## Future Considerations
*See V2_FEATURES.md for detailed auto-scheduling plans*

- Task dependencies for auto-scheduling
- Display order/manual reordering
- Estimated hours per task
- Time tracking integration
- Gantt chart visualization
- Resource allocation
- Task templates/presets

## Success Metrics
- Reduced time to create multi-phase projects
- Improved visibility into project progress
- Better resource allocation
- Clearer communication with clients
- Simplified scheduling for complex jobs

## Notes
- Maintain backward compatibility
- Keep simple projects simple
- Progressive disclosure (collapsed/expanded views)
- Performance: Lazy load task details
- Accessibility: Clear status indicators

---
*Built by trades, for trades - Making complex projects manageable*