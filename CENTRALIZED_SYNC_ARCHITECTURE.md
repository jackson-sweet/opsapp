# Centralized Sync Architecture - Design Document

**Date**: November 3, 2025
**Version**: 2.0.2
**Status**: 🎯 Implementation Plan

---

## Overview

This document defines the **single source of truth** for all sync operations in the OPS app. All sync logic is centralized in one file with clearly defined functions for each data type.

### Goals
- ✅ **One place to sync each object type** - Easy to debug
- ✅ **Clear sync triggers** - Know what syncs when
- ✅ **Soft delete support** - Handle deletions properly
- ✅ **Maintainable** - Changes in one place affect entire app
- ✅ **Testable** - Each function can be tested independently

---

## File Structure

### Primary File
**Location**: `OPS/Network/Sync/CentralizedSyncManager.swift`

This single file contains:
- All sync function definitions
- Master sync orchestrators (syncAll, syncAppLaunch)
- Individual data type sync functions
- Deletion handling logic
- Error handling and logging

---

## Master Sync Functions

### 1. syncAll() - Manual Complete Sync

**Purpose**: Called when user taps "Sync" button
**What it does**: Syncs ALL data types from Bubble

```swift
@MainActor
func syncAll() async throws {
    guard !syncInProgress, isConnected else {
        throw SyncError.alreadySyncing
    }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_ALL] 🔄 Starting complete sync...")

    // Sync in dependency order (parents before children)
    try await syncCompany()        // 1. Company info first
    try await syncUsers()          // 2. Users (team members)
    try await syncClients()        // 3. Clients
    try await syncTaskTypes()      // 4. Task types (templates)
    try await syncProjects()       // 5. Projects
    try await syncTasks()          // 6. Tasks (depends on projects)
    try await syncCalendarEvents() // 7. Calendar events (depends on projects/tasks)

    print("[SYNC_ALL] ✅ Complete sync finished")
}
```

**When Called**:
- User taps manual sync button
- Settings → Force Sync
- Pull-to-refresh in calendar/job board

---

### 2. syncAppLaunch() - App Startup Sync

**Purpose**: Called on app launch after authentication
**What it does**: Syncs essential data for app functionality

```swift
@MainActor
func syncAppLaunch() async throws {
    guard !syncInProgress, isConnected else {
        print("[SYNC_LAUNCH] ⚠️ Skipping - not connected or sync in progress")
        return
    }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_LAUNCH] 🚀 Starting app launch sync...")

    // Sync critical data only (prioritize speed)
    try await syncCompany()        // 1. Company & subscription info
    try await syncUsers()          // 2. Team members
    try await syncProjects()       // 3. Projects (with date range optimization)
    try await syncCalendarEvents() // 4. Calendar events for today

    // Background sync less critical data
    Task.detached(priority: .background) {
        try? await self.syncClients()
        try? await self.syncTaskTypes()
        try? await self.syncTasks()
    }

    print("[SYNC_LAUNCH] ✅ App launch sync finished")
}
```

**When Called**:
- App startup after successful authentication
- App returns to foreground after being terminated
- User completes onboarding

---

### 3. syncBackgroundRefresh() - Periodic Refresh

**Purpose**: Called by periodic timer or connectivity restoration
**What it does**: Lightweight refresh of changed data

```swift
@MainActor
func syncBackgroundRefresh() async throws {
    guard !syncInProgress, isConnected else { return }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_BG] 🔄 Background refresh...")

    // Only sync data likely to have changed
    try await syncProjects(sinceDate: lastSyncDate)
    try await syncCalendarEvents(sinceDate: lastSyncDate)
    try await syncTasks(sinceDate: lastSyncDate)

    lastSyncDate = Date()

    print("[SYNC_BG] ✅ Background refresh complete")
}
```

**When Called**:
- Every 3 minutes when pending syncs exist (Layer 3 retry)
- Connection restored (Layer 2 event-driven)
- Background refresh system event

---

## Individual Data Type Sync Functions

### Pattern: All Follow Same Structure

Each sync function follows this pattern:

```swift
@MainActor
func syncDataType() async throws {
    // 1. Fetch from Bubble API
    // 2. Process deletions (soft delete)
    // 3. Upsert (update or insert)
    // 4. Mark as synced
    // 5. Save to database
}
```

---

### syncCompany()

**Purpose**: Sync company information and subscription status

```swift
@MainActor
func syncCompany() async throws {
    print("[SYNC_COMPANY] 📊 Syncing company data...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dto = try await apiService.fetchCompany(id: companyId)

    // 2. Find or create local company
    let company = try await getOrCreateCompany(id: dto.id)

    // 3. Update properties
    company.companyName = dto.companyName
    company.logoURL = dto.logoURL
    company.subscriptionStatus = dto.subscriptionStatus
    company.subscriptionPlan = dto.subscriptionPlan
    company.maxSeats = dto.maxSeats
    // ... all other fields

    // 4. Mark synced
    company.needsSync = false
    company.lastSyncedAt = Date()

    // 5. Save
    try modelContext.save()

    print("[SYNC_COMPANY] ✅ Company synced")
}
```

---

### syncUsers()

**Purpose**: Sync team members for the company

```swift
@MainActor
func syncUsers() async throws {
    print("[SYNC_USERS] 👥 Syncing users...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dtos = try await apiService.fetchCompanyUsers(companyId: companyId)

    // 2. Handle deletions (soft delete)
    let remoteIds = Set(dtos.map { $0.id })
    try await handleUserDeletions(keepingIds: remoteIds)

    // 3. Upsert each user
    for dto in dtos {
        let user = try await getOrCreateUser(id: dto.id)

        // Update from DTO
        user.firstName = dto.firstName
        user.lastName = dto.lastName
        user.email = dto.email
        user.phone = dto.phone
        user.role = dto.employeeType.toUserRole()
        user.userColor = dto.userColor
        user.deletedAt = dto.deletedAt // Soft delete support

        user.needsSync = false
        user.lastSyncedAt = Date()
    }

    // 4. Save all changes
    try modelContext.save()

    print("[SYNC_USERS] ✅ Synced \(dtos.count) users")
}
```

---

### syncClients()

**Purpose**: Sync clients and sub-clients

```swift
@MainActor
func syncClients() async throws {
    print("[SYNC_CLIENTS] 🏢 Syncing clients...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dtos = try await apiService.fetchCompanyClients(companyId: companyId)

    // 2. Handle deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleClientDeletions(keepingIds: remoteIds)

    // 3. Upsert each client
    for dto in dtos {
        let client = try await getOrCreateClient(id: dto.id)

        client.name = dto.name
        client.email = dto.emailAddress
        client.phoneNumber = dto.phoneNumber
        client.address = dto.address?.formattedAddress
        client.latitude = dto.address?.lat
        client.longitude = dto.address?.lng
        client.profileImageURL = dto.avatar
        client.deletedAt = dto.deletedAt // Soft delete

        client.needsSync = false
        client.lastSyncedAt = Date()
    }

    try modelContext.save()

    print("[SYNC_CLIENTS] ✅ Synced \(dtos.count) clients")
}
```

---

### syncTaskTypes()

**Purpose**: Sync task type templates

```swift
@MainActor
func syncTaskTypes() async throws {
    print("[SYNC_TASK_TYPES] 🏷️ Syncing task types...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dtos = try await apiService.fetchCompanyTaskTypes(companyId: companyId)

    // 2. Handle deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleTaskTypeDeletions(keepingIds: remoteIds)

    // 3. Upsert each task type
    for dto in dtos {
        let taskType = try await getOrCreateTaskType(id: dto.id)

        taskType.display = dto.display
        taskType.color = dto.color
        taskType.icon = dto.icon
        taskType.isDefault = dto.isDefault
        taskType.displayOrder = dto.displayOrder
        taskType.deletedAt = dto.deletedAt

        taskType.needsSync = false
        taskType.lastSyncedAt = Date()
    }

    try modelContext.save()

    print("[SYNC_TASK_TYPES] ✅ Synced \(dtos.count) task types")
}
```

---

### syncProjects()

**Purpose**: Sync projects based on user role

```swift
@MainActor
func syncProjects(sinceDate: Date? = nil) async throws {
    print("[SYNC_PROJECTS] 📋 Syncing projects...")

    guard let userId = currentUser?.id else {
        throw SyncError.missingUserId
    }

    // 1. Fetch from Bubble (role-based)
    let dtos: [ProjectDTO]
    if currentUser?.role == .admin || currentUser?.role == .officeCrew {
        // Admin/Office: Get ALL company projects
        dtos = try await apiService.fetchCompanyProjects(
            companyId: currentUser!.companyId,
            sinceDate: sinceDate
        )
    } else {
        // Field Crew: Get only assigned projects
        dtos = try await apiService.fetchUserProjects(
            userId: userId,
            sinceDate: sinceDate
        )
    }

    // 2. Handle deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleProjectDeletions(keepingIds: remoteIds)

    // 3. Upsert each project
    for dto in dtos {
        let project = try await getOrCreateProject(id: dto.id)

        project.title = dto.projectName
        project.address = dto.address?.formattedAddress
        project.latitude = dto.address?.lat
        project.longitude = dto.address?.lng
        project.status = dto.status.toStatus()
        project.startDate = dto.startDate
        project.endDate = dto.completion
        project.duration = dto.duration
        project.eventType = dto.eventType
        project.allDay = dto.allDay
        project.notes = dto.description
        project.deletedAt = dto.deletedAt // Soft delete

        // Handle relationships
        project.clientId = dto.clientId
        project.companyId = dto.companyId
        project.setTeamMemberIds(dto.teamMemberIds ?? [])

        project.needsSync = false
        project.lastSyncedAt = Date()
    }

    try modelContext.save()

    print("[SYNC_PROJECTS] ✅ Synced \(dtos.count) projects")
}
```

---

### syncTasks()

**Purpose**: Sync project tasks

```swift
@MainActor
func syncTasks(sinceDate: Date? = nil) async throws {
    print("[SYNC_TASKS] ✅ Syncing tasks...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dtos = try await apiService.fetchCompanyTasks(
        companyId: companyId,
        sinceDate: sinceDate
    )

    // 2. Handle deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleTaskDeletions(keepingIds: remoteIds)

    // 3. Upsert each task
    for dto in dtos {
        let task = try await getOrCreateTask(id: dto.id)

        task.projectId = dto.projectId
        task.taskTypeId = dto.type
        task.status = TaskStatus(rawValue: dto.status) ?? .scheduled
        task.taskNotes = dto.taskNotes
        task.taskColor = dto.taskColor
        task.displayOrder = dto.taskIndex ?? 0
        task.calendarEventId = dto.calendarEventId
        task.deletedAt = dto.deletedAt

        task.setTeamMemberIds(dto.teamMemberIds ?? [])

        task.needsSync = false
        task.lastSyncedAt = Date()
    }

    try modelContext.save()

    print("[SYNC_TASKS] ✅ Synced \(dtos.count) tasks")
}
```

---

### syncCalendarEvents()

**Purpose**: Sync calendar events

```swift
@MainActor
func syncCalendarEvents(sinceDate: Date? = nil) async throws {
    print("[SYNC_CALENDAR] 📅 Syncing calendar events...")

    guard let companyId = currentUser?.companyId else {
        throw SyncError.missingCompanyId
    }

    // 1. Fetch from Bubble
    let dtos = try await apiService.fetchCompanyCalendarEvents(
        companyId: companyId,
        sinceDate: sinceDate
    )

    // 2. Handle deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleCalendarEventDeletions(keepingIds: remoteIds)

    // 3. Upsert each event
    for dto in dtos {
        guard let event = dto.toModel() else { continue }

        // Find or create
        let existingEvent = try await getOrCreateCalendarEvent(id: dto.id)

        existingEvent.projectId = event.projectId
        existingEvent.taskId = event.taskId
        existingEvent.title = event.title
        existingEvent.color = event.color
        existingEvent.startDate = event.startDate
        existingEvent.endDate = event.endDate
        existingEvent.duration = event.duration
        existingEvent.type = event.type
        existingEvent.active = event.active
        existingEvent.deletedAt = dto.deletedAt

        existingEvent.setTeamMemberIds(dto.teamMemberIds ?? [])

        existingEvent.needsSync = false
        existingEvent.lastSyncedAt = Date()
    }

    try modelContext.save()

    print("[SYNC_CALENDAR] ✅ Synced \(dtos.count) calendar events")
}
```

---

## Soft Delete Implementation

### Model Changes Required

Add to **ALL** models:

```swift
@Model
class Project {
    // ... existing properties ...

    /// Soft delete timestamp - nil means not deleted
    var deletedAt: Date?

    /// Check if record is deleted
    var isDeleted: Bool {
        deletedAt != nil
    }
}
```

### Models to Update

1. ✅ Project
2. ✅ ProjectTask
3. ✅ CalendarEvent
4. ✅ Client
5. ✅ SubClient
6. ✅ TaskType
7. ✅ User
8. ✅ Company (rare, but for completeness)

---

## Deletion Handling Functions

### Pattern: Smart Deletion Logic

```swift
private func handleProjectDeletions(keepingIds: Set<String>) async throws {
    print("[DELETION] 🗑️ Handling project deletions...")

    // Fetch all local projects (including soft-deleted)
    let descriptor = FetchDescriptor<Project>()
    let localProjects = try modelContext.fetch(descriptor)

    var deletedCount = 0

    for project in localProjects {
        // If project not in remote list
        if !keepingIds.contains(project.id) {
            // Only delete if:
            // 1. Not already soft-deleted
            // 2. Was synced recently (within 30 days)
            // 3. Not a historical project (> 1 year old)

            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

            if project.deletedAt == nil &&
               (project.lastSyncedAt ?? .distantPast) > thirtyDaysAgo &&
               (project.startDate ?? .distantPast) > oneYearAgo {

                print("[DELETION] 🗑️ Soft deleting project: \(project.title)")
                project.deletedAt = Date()

                // Cascade soft delete to related records
                for task in project.tasks {
                    task.deletedAt = Date()
                }

                if let calendarEvent = project.primaryCalendarEvent {
                    calendarEvent.deletedAt = Date()
                }

                deletedCount += 1
            }
        }
    }

    print("[DELETION] ✅ Soft deleted \(deletedCount) projects")
}
```

### Other Deletion Handlers

Follow same pattern:
- `handleUserDeletions(keepingIds:)`
- `handleClientDeletions(keepingIds:)`
- `handleTaskDeletions(keepingIds:)`
- `handleTaskTypeDeletions(keepingIds:)`
- `handleCalendarEventDeletions(keepingIds:)`

---

## Query Filtering (Exclude Deleted)

### Default Queries Exclude Deleted

```swift
// Before (shows deleted):
let descriptor = FetchDescriptor<Project>()

// After (excludes deleted):
let descriptor = FetchDescriptor<Project>(
    predicate: #Predicate { $0.deletedAt == nil }
)
```

### Create Helper Extensions

```swift
extension FetchDescriptor where T == Project {
    static var activeOnly: FetchDescriptor<Project> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil })
    }

    static var includingDeleted: FetchDescriptor<Project> {
        FetchDescriptor()
    }
}

// Usage:
let projects = try modelContext.fetch(.activeOnly)
```

---

## DTO Changes Required

Add `deletedAt` to ALL DTOs:

```swift
struct ProjectDTO: Codable {
    // ... existing fields ...
    let deletedAt: String? // ISO 8601 date string

    enum CodingKeys: String, CodingKey {
        // ... existing keys ...
        case deletedAt = "deletedAt"
    }
}
```

---

## Bubble Database Changes

### Add deletedAt Field

For each data type in Bubble:
1. Add field: `deletedAt` (type: date, optional)
2. Update delete workflows to set `deletedAt = current date/time`
3. Keep actual record in database (soft delete)

### Example Bubble Workflow

**Workflow Name**: `delete_project`

**Steps**:
1. Search for Project (filter: _id = URL parameter id)
2. Make changes to Project:
   - Set `deletedAt` to `Current date/time`
3. Return success response

---

## Sync Timing Summary

| Trigger | What Syncs | When |
|---------|-----------|------|
| **Manual Sync Button** | `syncAll()` - Everything | User taps sync |
| **App Launch** | `syncAppLaunch()` - Critical data | After auth |
| **Background Refresh** | `syncBackgroundRefresh()` - Changed data | Every 3 min if pending |
| **Connection Restored** | `syncBackgroundRefresh()` | Network reconnects |
| **User Makes Change** | Specific object sync | Immediate if online |

---

## Error Handling

### Sync Errors

```swift
enum SyncError: Error {
    case notConnected
    case alreadySyncing
    case missingUserId
    case missingCompanyId
    case apiError(Error)
    case dataCorruption
}
```

### Retry Logic

```swift
func syncWithRetry<T>(
    operation: () async throws -> T,
    maxRetries: Int = 3
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error
            print("[SYNC] ⚠️ Attempt \(attempt) failed: \(error)")

            if attempt < maxRetries {
                // Exponential backoff
                let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    throw lastError ?? SyncError.apiError(NSError(domain: "Unknown", code: -1))
}
```

---

## Migration Plan

### Phase 1: Create New CentralizedSyncManager
1. Create new file: `CentralizedSyncManager.swift`
2. Implement all sync functions
3. Add soft delete support to models
4. Update all DTOs with `deletedAt`

### Phase 2: Update Bubble Database
1. Add `deletedAt` field to all data types
2. Update delete workflows to soft delete
3. Test with one data type first (TaskType)

### Phase 3: Switch Sync Calls
1. Update DataController to use new CentralizedSyncManager
2. Replace old sync calls with new centralized calls
3. Test thoroughly

### Phase 4: Cleanup
1. Delete old SyncManager methods
2. Update all query predicates to exclude deleted
3. Archive old sync code

### Phase 5: Testing
1. Test manual sync button
2. Test app launch sync
3. Test deletion sync
4. Test offline → online sync
5. Test each data type individually

---

## Testing Checklist

### Manual Sync Button
- [ ] Tapping sync button calls `syncAll()`
- [ ] All data types sync in correct order
- [ ] Progress indicator shows during sync
- [ ] Success/failure message displayed

### App Launch
- [ ] `syncAppLaunch()` called after authentication
- [ ] Critical data synced first
- [ ] Background sync completes
- [ ] App usable immediately

### Deletion Sync
- [ ] Delete project on Bubble → soft delete in app
- [ ] Deleted projects hidden from views
- [ ] Related tasks/events also soft deleted
- [ ] Historical projects preserved

### Query Filtering
- [ ] Default queries exclude deleted records
- [ ] Deleted projects don't appear in lists
- [ ] Calendar doesn't show deleted events
- [ ] Job board excludes deleted items

---

## Next Steps

1. ✅ Review this architecture document
2. Create `CentralizedSyncManager.swift`
3. Add `deletedAt` to all models
4. Update all DTOs
5. Update Bubble database
6. Implement sync functions
7. Switch to new sync system
8. Test thoroughly
9. Archive old sync code

---

**End of Architecture Document**

Ready for implementation! 🚀
