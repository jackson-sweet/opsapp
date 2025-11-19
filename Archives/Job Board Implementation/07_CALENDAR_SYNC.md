# Calendar Event Synchronization

## Overview
Calendar events are the backbone of scheduling in OPS. This document details how calendar events are created, managed, and synchronized based on project scheduling modes.

## Data Model Updates

### CalendarEvent Model Enhancement
```swift
@Model
final class CalendarEvent: Identifiable {
    var id: String
    var projectId: String?
    var taskId: String?
    var eventType: CalendarEventType
    var startDate: Date
    var endDate: Date
    var duration: Int?
    var allDay: Bool
    var active: Bool // NEW FIELD - Controls visibility
    var title: String
    var description: String?
    var location: String?
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    // Computed property for display logic
    var shouldDisplay: Bool {
        // Only show active events
        guard active else { return false }
        
        // Additional display logic based on parent project
        if let project = project {
            // If project is task-based, only show task events
            if project.eventType == .task {
                return eventType == .task
            }
            // If project is project-based, only show project event
            else {
                return eventType == .project
            }
        }
        
        return true
    }
}
```

### CalendarEventDTO Update
```swift
struct CalendarEventDTO: Codable {
    let _id: String
    let project_id_text: String?
    let task_id_text: String?
    let event_type_text: String
    let start_date_date: String
    let end_date_date: String
    let duration_number: Int?
    let all_day_boolean: Bool
    let active_boolean: Bool // NEW FIELD
    let title_text: String
    let description_text: String?
    let location_text: String?
    let Modified_Date: String?
    
    func toCalendarEvent() -> CalendarEvent {
        let event = CalendarEvent(
            id: _id,
            projectId: project_id_text,
            taskId: task_id_text,
            eventType: CalendarEventType(rawValue: event_type_text) ?? .project,
            startDate: DateFormatter.bubble.date(from: start_date_date) ?? Date(),
            endDate: DateFormatter.bubble.date(from: end_date_date) ?? Date(),
            duration: duration_number,
            allDay: all_day_boolean,
            active: active_boolean, // Map new field
            title: title_text,
            description: description_text,
            location: location_text
        )
        return event
    }
}
```

## Event Creation Logic

### Project-Based Scheduling
```swift
func createProjectCalendarEvent(for project: Project) async throws -> CalendarEvent {
    let calendarEvent = CalendarEvent(
        id: UUID().uuidString,
        projectId: project.id,
        taskId: nil,
        eventType: .project,
        startDate: project.startDate ?? Date(),
        endDate: project.endDate ?? Date().addingTimeInterval(86400),
        duration: project.duration,
        allDay: project.allDay,
        active: true, // Project events start active
        title: project.title,
        description: project.projectDescription,
        location: project.address
    )
    
    // Create in Bubble
    let dto = calendarEvent.toDTO()
    let createdEvent = try await APIService.createCalendarEvent(dto)
    
    // Link to project
    project.primaryCalendarEvent = createdEvent
    
    return createdEvent
}
```

### Task-Based Scheduling
```swift
func createTaskCalendarEvent(for task: ProjectTask, in project: Project) async throws -> CalendarEvent {
    let calendarEvent = CalendarEvent(
        id: UUID().uuidString,
        projectId: project.id,
        taskId: task.id,
        eventType: .task,
        startDate: task.startDate ?? Date(),
        endDate: task.endDate ?? Date().addingTimeInterval(3600),
        duration: task.duration,
        allDay: task.allDay,
        active: project.eventType == .task, // Active only if project is task-based
        title: "\(project.title): \(task.taskType?.display ?? "Task")",
        description: task.taskNotes,
        location: project.address
    )
    
    // Create in Bubble
    let dto = calendarEvent.toDTO()
    let createdEvent = try await APIService.createCalendarEvent(dto)
    
    // Link to task
    task.calendarEvent = createdEvent
    
    // Update project dates if task-based
    if project.eventType == .task {
        updateProjectDatesFromTasks(project)
    }
    
    return createdEvent
}
```

## Scheduling Mode Conversion

### Converting Project → Task-Based
```swift
func convertToTaskBasedScheduling(project: Project) async throws {
    // Step 1: Update project scheduling mode
    project.eventType = .task
    
    // Step 2: Deactivate project's calendar event
    if let projectEvent = project.primaryCalendarEvent {
        projectEvent.active = false
        projectEvent.needsSync = true
    }
    
    // Step 3: Activate all task calendar events
    for task in project.tasks {
        if let taskEvent = task.calendarEvent {
            taskEvent.active = true
            taskEvent.needsSync = true
        }
    }
    
    // Step 4: Update project dates from tasks
    updateProjectDatesFromTasks(project)
    
    // Step 5: Sync to Bubble
    try await APIService.updateProjectSchedulingMode(
        projectId: project.id,
        mode: .task,
        calendarEventUpdates: gatherCalendarEventUpdates(project)
    )
}
```

### Converting Task → Project-Based
```swift
func convertToProjectBasedScheduling(project: Project) async throws {
    // Step 1: Update project scheduling mode
    project.eventType = .project
    
    // Step 2: Ensure project has a calendar event
    if project.primaryCalendarEvent == nil {
        let newEvent = try await createProjectCalendarEvent(for: project)
        project.primaryCalendarEvent = newEvent
    } else if let projectEvent = project.primaryCalendarEvent {
        // Reactivate existing event
        projectEvent.active = true
        projectEvent.needsSync = true
    }
    
    // Step 3: Deactivate all task calendar events
    for task in project.tasks {
        if let taskEvent = task.calendarEvent {
            taskEvent.active = false
            taskEvent.needsSync = true
        }
    }
    
    // Step 4: Sync to Bubble
    try await APIService.updateProjectSchedulingMode(
        projectId: project.id,
        mode: .project,
        calendarEventUpdates: gatherCalendarEventUpdates(project)
    )
}
```

## Date Calculation Logic

### Update Project Dates from Tasks
```swift
func updateProjectDatesFromTasks(_ project: Project) {
    guard project.eventType == .task else { return }
    
    // Get all active task events
    let activeTaskEvents = project.tasks.compactMap { task in
        task.calendarEvent?.active == true ? task.calendarEvent : nil
    }
    
    guard !activeTaskEvents.isEmpty else {
        // No active tasks - clear project dates
        project.startDate = nil
        project.endDate = nil
        project.duration = nil
        return
    }
    
    // Find earliest start and latest end
    let startDates = activeTaskEvents.map { $0.startDate }
    let endDates = activeTaskEvents.map { $0.endDate }
    
    if let earliestStart = startDates.min(),
       let latestEnd = endDates.max() {
        project.startDate = earliestStart
        project.endDate = latestEnd
        
        // Calculate duration in days
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: earliestStart, to: latestEnd).day ?? 1
        project.duration = max(1, days)
        
        // Mark for sync
        project.needsSync = true
    }
}
```

### Task Date Change Handler
```swift
func handleTaskDateChange(task: ProjectTask, project: Project) {
    guard project.eventType == .task else { return }
    
    // Update task's calendar event
    if let calendarEvent = task.calendarEvent {
        calendarEvent.startDate = task.startDate ?? Date()
        calendarEvent.endDate = task.endDate ?? Date()
        calendarEvent.needsSync = true
    }
    
    // Recalculate project dates
    updateProjectDatesFromTasks(project)
    
    // Queue for sync
    dataController.syncManager?.queueSync(for: task)
    dataController.syncManager?.queueSync(for: project)
}
```

## Sync Strategy

### Batch Calendar Event Updates
```swift
struct CalendarEventBatchUpdate {
    let projectId: String
    let updates: [CalendarEventUpdate]
    
    struct CalendarEventUpdate {
        let eventId: String
        let active: Bool
        let startDate: Date?
        let endDate: Date?
    }
}

func syncCalendarEventBatch(_ batch: CalendarEventBatchUpdate) async throws {
    try await APIService.updateCalendarEventBatch(batch)
    
    // Update local cache
    for update in batch.updates {
        if let event = dataController.getCalendarEvent(id: update.eventId) {
            event.active = update.active
            if let start = update.startDate {
                event.startDate = start
            }
            if let end = update.endDate {
                event.endDate = end
            }
            event.lastSyncedAt = Date()
            event.needsSync = false
        }
    }
}
```

### Sync Priority
```swift
enum SyncPriority: Int {
    case immediate = 3  // User-initiated changes
    case high = 2      // Active event changes
    case normal = 1    // Inactive event changes
    case low = 0       // Metadata updates
}

func determineSyncPriority(for event: CalendarEvent) -> SyncPriority {
    // Active events get higher priority
    if event.active {
        // Today's events get immediate priority
        if Calendar.current.isDateInToday(event.startDate) {
            return .immediate
        }
        // This week's events get high priority
        if event.startDate < Date().addingTimeInterval(604800) {
            return .high
        }
        return .normal
    }
    return .low
}
```

## Calendar View Integration

### Filtering Active Events
```swift
extension CalendarViewModel {
    func loadCalendarEvents(for date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Only fetch active events
        let predicate = #Predicate<CalendarEvent> { event in
            event.active == true &&
            event.startDate < dayEnd &&
            event.endDate >= dayStart
        }
        
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate)]
        )
        
        do {
            let events = try modelContext.fetch(descriptor)
            self.eventsForDate[date] = events.filter { $0.shouldDisplay }
        } catch {
            print("Error fetching calendar events: \(error)")
        }
    }
}
```

### Display Logic
```swift
struct CalendarEventCard: View {
    let event: CalendarEvent
    
    var body: some View {
        // Only render if event should be displayed
        if event.shouldDisplay {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Event type indicator
                    Image(systemName: event.eventType == .project ? "calendar" : "checkmark.circle")
                        .foregroundColor(eventTypeColor)
                    
                    Text(event.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Active indicator (for debugging)
                    #if DEBUG
                    if !event.active {
                        Text("INACTIVE")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                    }
                    #endif
                }
                
                // Rest of card content...
            }
            .cardStyle()
        }
    }
}
```

## Migration Strategy

### Adding Active Field to Existing Events
```swift
func migrateCalendarEventsToIncludeActiveField() async {
    let descriptor = FetchDescriptor<CalendarEvent>()
    
    do {
        let allEvents = try modelContext.fetch(descriptor)
        
        for event in allEvents {
            // If active field is nil (migration case), set based on logic
            if event.active == nil {
                // Default all existing events to active
                event.active = true
                event.needsSync = true
            }
        }
        
        try modelContext.save()
        
        // Queue batch sync
        await syncAllCalendarEventActiveStates()
        
    } catch {
        print("Migration error: \(error)")
    }
}
```