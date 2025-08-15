# CalendarEvent Filtering Strategy

## Problem
We need to efficiently determine which CalendarEvents to display without querying the parent project for each event.

## Solution: Multi-Tiered Approach

### 1. Cached Project EventType
Each CalendarEvent now has a `projectEventType` field that caches the parent project's scheduling mode:

```swift
class CalendarEvent {
    var projectEventType: CalendarEventType? // Cached from parent project
}
```

### 2. Efficient Display Check
CalendarEvents can now determine display eligibility without querying the project:

```swift
var shouldDisplay: Bool {
    if let projectEventType = projectEventType {
        if projectEventType == .project {
            // Show only project-level events
            return type == .project && taskId == nil
        } else {
            // Show only task events
            return type == .task && taskId != nil
        }
    }
    // Fallback logic if cache not available
}
```

### 3. Batch Processing for Calendar View

```swift
// Example: Efficient calendar loading
func loadCalendarEvents() async {
    // 1. Fetch all events for company (single query)
    let events = await fetchCompanyCalendarEvents(companyId: companyId)
    
    // 2. Get unique project IDs
    let projectIds = Set(events.map { $0.projectId })
    
    // 3. Batch fetch projects (single query)
    let projects = await fetchProjects(ids: Array(projectIds))
    
    // 4. Create lookup dictionary
    let projectLookup = Dictionary(uniqueKeysWithValues: 
        projects.map { ($0.id, $0) }
    )
    
    // 5. Update cache and filter in one pass
    let displayableEvents = events.compactMap { event -> CalendarEvent? in
        guard let project = projectLookup[event.projectId] else { 
            return nil 
        }
        
        // Cache the project's eventType
        event.projectEventType = project.eventType
        
        // Return only if should display
        return event.shouldDisplay ? event : nil
    }
    
    return displayableEvents
}
```

## Display Rules Summary

### Traditional Project Scheduling (eventType == .project)
- Show events where:
  - `type == .project`
  - `taskId == nil`
- Hide all task-based events

### Task-Based Scheduling (eventType == .task)
- Show events where:
  - `type == .task`
  - `taskId != nil`
- Hide project-level events

## Performance Benefits

1. **No N+1 Queries**: Batch fetch projects instead of querying for each event
2. **Cached Values**: Store projectEventType to avoid repeated lookups
3. **Single Pass Filtering**: Filter and cache in one iteration
4. **Memory Efficient**: Only store necessary project data in lookup dictionary

## Migration Notes

- Existing projects default to `.project` scheduling mode
- CalendarEvents created before this update will have `projectEventType == nil` and use fallback logic
- The cache will be populated on first access