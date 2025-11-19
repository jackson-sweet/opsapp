# DEPRECATED - CalendarEvent Architecture & Filtering Strategy

**DEPRECATION NOTICE**
**Date Archived:** 2025-11-16
**Reason:** This document describes filtering between project-level and task-level CalendarEvents
**Current System:** Task-only scheduling - All CalendarEvents now have taskId, no filtering needed
**See:** `/Development Tasks/TASK_ONLY_SCHEDULING_MIGRATION.md` for migration details

---

**THIS INFORMATION IS NO LONGER ACCURATE - PRESERVED FOR HISTORICAL REFERENCE ONLY**

---

## Core Architecture
CalendarEvents are the single source of truth for all calendar display and date management in the OPS app.

## Problem Solved
We need to efficiently determine which CalendarEvents to display without querying the parent project for each event, while maintaining a unified calendar display regardless of scheduling mode.

## Solution: CalendarEvent-Centric Architecture

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

## Implementation Updates (Latest)

### CalendarEvent-Centric Display
- **Calendar View**: Now fetches and displays CalendarEvents instead of Projects directly
- **Project Data**: Projects are loaded to provide rich detail data (photos, notes, etc.)
- **Date Management**: CalendarEvents are the single source of truth for all dates
- **Relationships**:
  - Project has `primaryCalendarEvent` for project-based scheduling
  - Task has `calendarEvent` for task-based scheduling
  - Dates sync bidirectionally between entities

### Calendar Event Sync Strategy
- Calendar events are now synced during project sync operations
- This ensures the calendar is always populated with current data
- Events are never created locally - only synced from Bubble
- Date changes in CalendarEvents propagate to Projects/Tasks automatically

### Task Updates
- **Real-time Sync**: Task status and notes changes sync immediately to API
- **API Methods**:
  - `updateTaskStatus(id: String, status: String)` - Updates task status
  - `updateTaskNotes(id: String, notes: String)` - Updates task notes
- **Offline Support**: Changes marked with `needsSync` flag for retry when online

### Task Type Fetching Strategy
- Task types are fetched by specific IDs rather than fetching all
- When syncing tasks, only unknown task types are fetched
- Reduces API calls and improves performance

### Removed Restrictions
- All companies now have access to task features
- No conditional checks for task functionality
- Simplifies code and prevents bugs from feature flags

## Data Flow

1. **API → CalendarEvents**: Bubble creates CalendarEvents when projects/tasks are created
2. **CalendarEvents → Display**: Calendar view shows CalendarEvents with their dates
3. **CalendarEvents → Projects/Tasks**: Dates sync from CalendarEvents to related entities
4. **UI Changes → API**: Task status/notes changes sync immediately to Bubble
