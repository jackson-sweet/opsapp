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
    ├── eventType (CalendarEventType: "Task" or "Project", defaults to "Project")
    ├── CalendarEvent (if eventType == "Project")
    └── Tasks (if eventType == "Task")
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

### Project eventType Field
```swift
// Added to existing Project model
var eventType: CalendarEventType // "Task" or "Project"
```
- **Purpose**: Determines scheduling mode for the project
- **Default**: "Project" (traditional single-event scheduling)
- **"Task"**: Enables task-based scheduling with multiple calendar events
- **Migration**: All existing projects default to "Project" mode

### Task
```swift
struct Task {
    let id: String ("_id" in Bubble)
    let calendarEventId: String? ("calendarEventId" in Bubble)
    let companyId: String? ("companyId" in Bubble)
    let completionDate: String? ("completionDate" in Bubble)
    let projectId: String? ("projectID" in Bubble - note capital ID)
    let scheduledDate: String? ("scheduledDate" in Bubble)
    let status: String? ("status" in Bubble - may be nil)
    let taskColor: String? ("taskColor" in Bubble - defaults to company.defaultProjectColor if nil)
    let taskIndex: Int? ("taskIndex" in Bubble - display order)
    let taskNotes: String? ("taskNotes" in Bubble)
    let teamMembers: [String]? ("Team Members" in Bubble)
    let type: String? ("type" in Bubble - references TaskType)
}
```

### TaskType
```swift
struct TaskType {
    let id: String ("_id" in Bubble)
    let color: String ("Color" in Bubble)
    let display: String ("Display" in Bubble - name like "Quote", "Work", "Service Call", "Inspection", "Follow Up")
    let isDefault: Bool? ("isDefault" in Bubble - yes/no field)
    
    // Note: TaskType is actually an Option Set in Bubble with these options:
    // - Quote
    // - Work
    // - Service Call
    // - Inspection
    // - Follow Up
}
```

### CalendarEvent
```swift
struct CalendarEvent {
    let id: String ("_id" in Bubble)
    let color: String? ("Color" in Bubble)
    let companyId: String? ("companyId" in Bubble - lowercase 'c')
    let duration: Int? ("Duration" in Bubble)
    let endDate: String? ("End Date" in Bubble)
    let projectId: String? ("projectId" in Bubble - lowercase 'p')
    let startDate: String? ("Start Date" in Bubble)
    let taskId: String? ("taskId" in Bubble - lowercase 't')
    let teamMembers: [String]? ("Team Members" in Bubble)
    let title: String? ("Title" in Bubble)
    let type: String? ("Type" in Bubble - CalendarEventType: "project" or "task")
}
```

### CalendarEvent Display Rules
```swift
// Which CalendarEvents to display for a project:

if project.eventType == "Project" {
    // Traditional scheduling mode
    // Show events where:
    // - projectId == project.id
    // - type == "project"
    // - taskId == nil
} else if project.eventType == "Task" {
    // Task-based scheduling mode
    // Show events where:
    // - projectId == project.id
    // - type == "task"
    // - taskId != nil
}
```

## API Field Mapping Notes

### Bubble API Considerations
1. **Field Naming**: Bubble uses exact case-sensitive field names:
   - Task: "projectID" (capital ID), "companyId" (lowercase c)
   - CalendarEvent: "companyId", "projectId", "taskId" (all lowercase first letter)
   - Type name: "calendarevent" (all lowercase) for API endpoints
2. **Missing Fields**: Many fields may be nil/missing in Bubble responses - handle gracefully
3. **TaskType Scope**: TaskType is an Option Set in Bubble with predefined options (Quote, Work, Service Call, Inspection, Follow Up)
4. **Task Status**: Option Set with values: Scheduled, In Progress, Completed, Cancelled
5. **Color Defaults**: When taskColor is nil, use company.defaultProjectColor
6. **Date Fields**: Task has scheduledDate and completionDate; CalendarEvent has Start Date and End Date

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