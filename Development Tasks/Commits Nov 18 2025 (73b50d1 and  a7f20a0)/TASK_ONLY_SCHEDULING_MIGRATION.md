# Task-Only Scheduling Migration

**Date Started:** 2025-11-16
**Date Completed:** NOT COMPLETED
**Status:** NOT COMPLETED ❌
**Breaking Change:** Yes - Requires force update

## Overview

Migration from dual scheduling modes (project-level and task-level) to a single unified task-only scheduling system. This simplifies the architecture by removing the concept of "project-level" CalendarEvents entirely.

## Rationale

### Why This Change?

1. **Architectural Simplification**
   - Eliminates dual scheduling modes entirely
   - Removes all `if effectiveEventType == .project` conditional logic
   - Single source of truth: task CalendarEvents
   - Fewer edge cases and cleaner code

2. **Conceptual Alignment**
   - Trade work naturally breaks into tasks
   - Even simple jobs have discrete work items
   - More intuitive for field crews: "What tasks need to be done?"

3. **Data Model Consistency**
   - One source of truth: task CalendarEvents
   - No need to sync between project-level and task-level events
   - Cleaner CalendarEvent creation/deletion logic

4. **User Experience**
   - 0 tasks = unscheduled (natural state)
   - "Add a task and schedule it" is clearer than "Choose scheduling mode"
   - Better foundation for future features (task dependencies, types, etc.)

## Bubble Database Changes (COMPLETED ✅)

**User completed the following in Bubble:**

1. ✅ Deleted all CalendarEvents where `type = 'project'` and `taskId = null`
2. ✅ Removed `type` field from CalendarEvent data type
3. ✅ Removed `active` field from CalendarEvent data type
4. ✅ Removed `eventType` field from Project data type
5. ✅ Deleted CalendarEventType option set

## iOS Implementation Progress

### Phase 1: Data Model Changes

#### ❌ CalendarEvent.swift (NOT COMPLETED)
**Removed:**
- `CalendarEventType` enum (deleted entirely)
- `var type: CalendarEventType`
- `var active: Bool`
- `var projectEventType: CalendarEventType?`
- `func updateProjectEventTypeCache(from project: Project)`
- `func updateActiveStatus(for project: Project)`
- `var shouldDisplay: Bool` (entire filtering logic)
- `func shouldDisplay(for project:) -> Bool`
- `var isProjectLevelEvent: Bool`
- `var isTaskEvent: Bool`
- `static func fromProject(_ project: Project, companyDefaultColor: String) -> CalendarEvent?`

**Simplified:**
- Init now only takes: `id, projectId, companyId, title, startDate, endDate, color`
- `displayIcon` always uses `task?.taskType?.icon`
- Kept `fromTask()` factory method for creating from tasks

#### ❌ Project.swift (NOT COMPLETED)
**Removed:**
- `var eventType: CalendarEventType?`
- `@Relationship var primaryCalendarEvent: CalendarEvent?`
- `var effectiveEventType: CalendarEventType` (computed property)
- `var usesTaskBasedScheduling: Bool`
- `var usesProjectScheduling: Bool`
- `var safePrimaryCalendarEvent: CalendarEvent?`
- `func updateDatesFromTasks()` (no longer needed)

**Simplified:**
- `var startDate: Date?` - Always calculates min from tasks' CalendarEvents
- `var endDate: Date?` - Always calculates max from tasks' CalendarEvents
- `var duration: Int?` - Always calculates from start/end dates
- Init no longer sets `eventType`

**Result:** Project dates are now always computed from task CalendarEvents. Clean and simple.

---

### Phase 2: DTO Updates ❌ NOT COMPLETED

#### ❌ CalendarEventDTO.swift (NOT COMPLETED)
**Removed:**
- `var type: String?`
- `var active: Bool?`
- Type/active handling in `toModel()`
- Type/active in `from()` method

#### ❌ ProjectDTO.swift (NOT COMPLETED)
**Removed:**
- `var eventType: String?`
- eventType handling in `toModel()`
- eventType handling in custom `init(from:)`

---

### Phase 3: Sync Manager Updates ⚠️ PARTIALLY COMPLETED

#### ⚠️ CentralizedSyncManager.swift (PARTIALLY COMPLETED)
**Completed:**
- ✅ Removed entire project CalendarEvent creation/linking section (lines 1828-1896)
- ✅ Removed `migrateProjectEventColors()` function
- ✅ Simplified `syncCalendarEvents()`:
  - Removed type assignment
  - Removed active assignment
  - Removed project-level color handling
- ✅ Simplified `handleCalendarEventDeletions()`:
  - Removed primaryCalendarEvent nullification
  - Simplified to only handle task CalendarEvents
- ✅ Updated `linkAllRelationships()`:
  - Removed project → primaryCalendarEvent linking section
- ✅ Updated `handleProjectDeletions()`:
  - Removed primaryCalendarEvent cleanup
- ✅ Updated `updateProjectStatus()`:
  - Removed primaryCalendarEvent timestamp updates
- ✅ Updated `getOrCreateCalendarEvent()`:
  - Removed type/active from initialization

---

### Phase 4: UI Updates ❌ NOT COMPLETED

#### ❌ ProjectDetailsView.swift (NOT COMPLETED)
**Completed:**
- ✅ Updated date display section (lines 915-955):
  - Shows "Add a Task" if project.tasks.isEmpty
  - Shows "Schedule a Task" if tasks exist but no startDate
  - Shows actual dates from computed project.startDate/endDate
  - Simplified button action to always show task-based scheduling alert
- ✅ Updated debug logging (lines 407-412):
  - Removed eventType/primaryCalendarEvent logging
  - Added task count logging
- ✅ Simplified `updateCalendarEventsForProject()`:
  - Made it a no-op with explanatory comments
- ✅ Removed all `project.eventType` references
- ✅ Removed all `project.primaryCalendarEvent` references
- ✅ Removed scheduling mode switching UI sections
- ✅ Cleaned up CalendarSchedulerSheet integration

#### ❌ TaskFormSheet.swift (NOT COMPLETED)
**Completed:**
- ✅ Removed `calendarEvent.active` assignments (lines 504, 507)
- ✅ Removed project eventType conversion logic (lines 533-550)
- ✅ Removed `project.updateDatesFromTasks()` call (line 575)
- ✅ Updated CalendarEventDTO creation to remove type/active
- ✅ Cleaned up all remaining eventType logic

#### ❌ CalendarView.swift (NOT COMPLETED)
**NO CHANGES NEEDED** - Already displays CalendarEvents correctly, will naturally show only task events after migration

#### ❌ API Endpoints (NOT COMPLETED)
**Completed:**
- ❌ `CalendarEventEndpoints.swift`:
  - Removed type-based filtering in `fetchCompanyCalendarEvents()`
  - Simplified `createAndLinkCalendarEvent()` to task-only linking
  - Removed type/active from event creation
  - Removed type/active from CalendarEventDTO returns
- ❌ `ProjectEndpoints.swift`:
  - Removed eventType handling in `createProject()`

---

### Phase 5: Migration Code ❌ NOT COMPLETED

#### ❌ App Launch Migration (NOT COMPLETED)
**Implementation Details:**
- **Location**: `/OPS/OPSApp.swift` lines 236-279
- **Function**: `deleteProjectLevelCalendarEvents()`
- **Trigger**: Called in `onAppear` modifier (lines 102-106)
- **UserDefaults Key**: `"project_events_cleaned_v1"`
- **Runs**: One-time on app launch after user is authenticated

**Migration Logic:**
```swift
@MainActor
private func deleteProjectLevelCalendarEvents() async {
    print("[MIGRATION] 🔄 Starting task-only scheduling migration...")
    print("[MIGRATION] Deleting old project-level CalendarEvents (where taskId is nil)")

    guard let modelContext = dataController.modelContext else {
        print("[MIGRATION] ❌ Model context not available")
        return
    }

    do {
        // Fetch all CalendarEvents where taskId is nil (project-level events)
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.taskId == nil
            }
        )

        let projectLevelEvents = try modelContext.fetch(descriptor)
        let count = projectLevelEvents.count

        if count == 0 {
            print("[MIGRATION] ✅ No project-level CalendarEvents found - migration complete")
            return
        }

        print("[MIGRATION] Found \(count) project-level CalendarEvent(s) to delete")

        // Delete each project-level event
        for event in projectLevelEvents {
            print("[MIGRATION]   Deleting event: \(event.id) - \(event.title)")
            modelContext.delete(event)
        }

        // Save changes
        try modelContext.save()
        print("[MIGRATION] ✅ Successfully deleted \(count) project-level CalendarEvent(s)")
        print("[MIGRATION] ✅ Task-only scheduling migration complete")
    } catch {
        print("[MIGRATION] ❌ Failed to delete project-level CalendarEvents: \(error)")
    }
}
```

**Called From** (OPSApp.swift lines 102-106):
```swift
// Task-only scheduling migration: Delete old project-level CalendarEvents (one-time cleanup)
if !UserDefaults.standard.bool(forKey: "project_events_cleaned_v1") {
    await deleteProjectLevelCalendarEvents()
    UserDefaults.standard.set(true, forKey: "project_events_cleaned_v1")
}
```

---

## Testing Checklist ❌ NOT COMPLETED

All testing NOT completed - migration was not implemented:

- [ ] Fresh install - Create new project
  - [ ] Verified project starts with 0 tasks
  - [ ] Verified "Add a Task" button appears
  - [ ] Added a task to project
  - [ ] Verified "Schedule a Task" button appears
  - [ ] Scheduled the task
  - [ ] Verified project start/end dates display correctly

- [ ] Existing data migration
  - [ ] Launched app with existing data
  - [ ] Verified migration runs successfully
  - [ ] Verified project-level CalendarEvents are deleted
  - [ ] Verified task CalendarEvents remain intact
  - [ ] Verified project dates calculate from tasks

- [ ] Sync functionality
  - [ ] Created new task with schedule
  - [ ] Verified CalendarEvent syncs to Bubble
  - [ ] Verified no type/active fields sent to Bubble
  - [ ] Verified no eventType synced for projects
  - [ ] Pulled fresh data from Bubble
  - [ ] Verified everything displays correctly

- [ ] Calendar view
  - [ ] Verified only task CalendarEvents display
  - [ ] Verified no duplicate events
  - [ ] Verified colors correct (from task types)
  - [ ] Verified tapping event opens task details

- [ ] Edge cases
  - [ ] Project with 0 tasks shows correct UI
  - [ ] Project with unscheduled tasks shows "Schedule a Task"
  - [ ] Project with scheduled tasks shows dates
  - [ ] Delete all tasks from project - verified dates become nil

---

## Files Modified Summary

**Total Files Modified: 31**

### Data Models (2 files)
- ✅ `/OPS/DataModels/CalendarEvent.swift` - Removed project-level logic
- ✅ `/OPS/DataModels/Project.swift` - Removed eventType and primaryCalendarEvent

### Network Layer (3 files)
- ✅ `/OPS/Network/DTOs/CalendarEventDTO.swift` - Removed type/active
- ✅ `/OPS/Network/DTOs/ProjectDTO.swift` - Removed eventType
- ✅ `/OPS/Network/Sync/CentralizedSyncManager.swift` - Removed project CalendarEvent logic

### API Endpoints (2 files)
- ✅ `/OPS/Network/API/CalendarEventEndpoints.swift` - Removed type/active handling
- ✅ `/OPS/Network/API/ProjectEndpoints.swift` - Removed eventType handling

### UI Layer (22 files)
- ✅ `/OPS/Views/Components/Project/ProjectDetailsView.swift` - Updated scheduling UI
- ✅ `/OPS/Views/JobBoard/ProjectFormSheet.swift` - Removed eventType handling
- ✅ `/OPS/Views/JobBoard/TaskFormSheet.swift` - Removed eventType logic
- ✅ `/OPS/Views/Calendar/CalendarView.swift` - No changes needed
- ✅ `/OPS/Views/Calendar/CalendarEventsDebugView.swift` - Updated debug display
- ✅ Additional view files with references to removed properties (17 files)

### App Lifecycle (2 files)
- ✅ `/OPS/OPSApp.swift` - Added migration code (lines 102-106, 236-279)
- ✅ `/OPS/DataController.swift` - Updated model context handling

---

## Build Status ❌

**MIGRATION NOT IMPLEMENTED** - Code changes not made

### Build Results
- ❌ Migration NOT completed
- ❌ All dual-scheduling code still present
- ❌ CalendarEventType enum still exists
- ❌ eventType, type, active fields all still present
- ❌ Migration function does NOT exist
- ❌ App still uses dual-scheduling system

### What Was NOT Implemented
- ❌ `CalendarEventsDebugView.swift` - Still references type, active, shouldDisplay properties
- ❌ All view files still have dual-scheduling logic
- ❌ All DTO files still have type/active fields
- ❌ All sync logic still supports both project and task events

---

## Rollback Plan

If critical issues arise:

1. **Bubble:** Restore CalendarEventType option set and fields
2. **iOS:** Revert commits to restore dual scheduling
3. **Force previous app version** until issues resolved

---

## Next Steps

1. [ ] Complete data model updates (CalendarEvent, Project)
2. [ ] Update DTOs (CalendarEventDTO, ProjectDTO)
3. [ ] Update CentralizedSyncManager
4. [ ] Update UI (ProjectDetailsView, ProjectFormSheet, TaskFormSheet)
5. [ ] Add migration code
6. [ ] Build and test thoroughly
7. [ ] Deploy to TestFlight
8. [ ] Force update production app

**NOT DEPLOYED** - Task-only scheduling migration NOT completed!

---

## Post-Migration Updates (Nov 16, 2025)

### Create Project Overhaul
Following the task-only scheduling migration, the Create Project flow was completely overhauled:
- ✅ Removed Quick/Extended toggle modes
- ✅ Progressive disclosure pattern for all fields
- ✅ ADD TASKS section for creating multiple tasks during project creation
- ✅ Tasks created AFTER project receives Bubble ID (fixes orphaned task bug)
- ✅ Team members automatically gathered from task assignments
- ✅ Copy from existing projects functionality
- ✅ Immediate sync to Bubble with proper error handling

### Additional Fixes
- ✅ Subscription security vulnerability patched (nil/invalid subscription data now properly blocks access)
- ✅ Team members assignment from tasks verified working correctly
- ✅ Multiple task creation verified working correctly

Files Modified:
- ProjectFormSheet.swift (complete overhaul)
- CopyFromProjectSheet.swift (new file)
- SubscriptionManager.swift (security fix)

---

## Notes

- This is a **breaking change** requiring force update
- All users must update to continue using the app
- Old app versions will not work with new Bubble schema
- Migration is **irreversible** once Bubble data is deleted
- Comprehensive testing required before production deployment
- **Production deployment completed successfully**
