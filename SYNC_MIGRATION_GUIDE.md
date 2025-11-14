# Sync Migration Guide - CentralizedSyncManager

## Migration Status

### ✅ Completed
- All sync operations migrated to `CentralizedSyncManager.swift`
- `SyncManager.swift` renamed to `SyncManager_OLD.swift` with deprecation notice
- `DataController` updated to use `CentralizedSyncManager`
- All model classes have `deletedAt: Date?` field for soft delete support
- DTOs updated with `deletedAt` field (ProjectDTO, TaskDTO, CalendarEventDTO complete)

### ⚠️ Pending
- Update view references to use new method signatures (see below)
- Update queries to exclude deleted records (`deletedAt == nil`)
- Complete DTOs with `deletedAt`: UserDTO, ClientDTO, TaskTypeDTO, CompanyDTO
- Delete `SyncManager_OLD.swift` after testing

## View References Requiring Updates

### Method Signature Changes

#### 1. updateProjectStatus
**Old:** `syncManager.updateProjectStatus(projectId:status:forceSync:)`
**New:** `syncManager.updateProjectStatus(projectId:status:forceSync:)`
**Status:** ✅ No change required

**Files to Check:**
- `/Views/Home/HomeContentView.swift:122`
- `/Views/Home/HomeView.swift:291`
- `/Views/Components/Project/TaskDetailsView.swift:1144`
- `/Views/Components/Project/ProjectActionBar.swift:231`

#### 2. updateTaskNotes
**Old:** `syncManager.updateTaskNotes(id:notes:)`
**New:** `syncManager.updateTaskNotes(taskId:notes:)`
**Status:** ⚠️ Parameter name changed from `id` to `taskId`

**Files to Update:**
- `/Views/Components/Project/TaskDetailsView.swift:1126`
  ```swift
  // OLD:
  try await syncManager.updateTaskNotes(id: task.id, notes: task.taskNotes ?? "")

  // NEW:
  try await syncManager.updateTaskNotes(taskId: task.id, notes: task.taskNotes ?? "")
  ```

#### 3. updateTaskStatus
**Old:** `syncManager.updateTaskStatus(id:status:)` (async throws)
**New:** `syncManager.updateTaskStatus(taskId:status:)` (async throws)
**Status:** ⚠️ Parameter name changed from `id` to `taskId`

**Note:** TaskDetailsView and other views may need updating if they call this method directly.

#### 4. updateClientContact
**Old:** `syncManager.updateClientContact(clientId:name:email:phone:address:)` → returns Client?
**New:** `syncManager.updateClientContact(clientId:name:email:phone:address:)` → returns void (async throws)
**Status:** ⚠️ Return type changed

**Files to Update:**
- `/Views/Components/User/ContactDetailView.swift:1247`
  ```swift
  // OLD:
  let updatedClient = try await syncManager.updateClientContact(...)

  // NEW:
  try await syncManager.updateClientContact(...)
  // Client is updated in place, no return value
  ```

#### 5. createSubClient
**Old:** `syncManager.createSubClient(...)` → returns SubClientDTO
**New:** `syncManager.createSubClient(...)` → returns SubClient
**Status:** ⚠️ Return type changed from DTO to Model

**Files to Update:**
- `/Views/Components/User/ContactDetailView.swift:1312`
  ```swift
  // OLD:
  let subClientDTO = try await syncManager.createSubClient(...)
  // Then convert DTO to model

  // NEW:
  let subClient = try await syncManager.createSubClient(...)
  // Already returns model
  ```

#### 6. syncCompanyTaskTypes
**Old:** `syncManager.syncCompanyTaskTypes(companyId:)`
**New:** `syncManager.syncCompanyTaskTypes(companyId:)`
**Status:** ✅ No change required

**Files to Check:**
- `/Views/Settings/TaskSettingsView.swift:197`
- `/Views/Debug/TaskTestView.swift:498`

#### 7. syncProjectTasks
**Old:** `syncManager.syncProjectTasks(projectId:)`
**New:** `syncManager.syncProjectTasks(projectId:)`
**Status:** ✅ No change required

**Files to Check:**
- `/Views/Debug/TaskTestView.swift:536`

#### 8. syncCompanyTeamMembers
**Old:** `syncManager.syncCompanyTeamMembers(company)` - takes Company object
**New:** `syncManager.syncCompanyTeamMembers(company)` - wrapper method handles Company object
**Status:** ✅ Backwards compatible

**Files to Check:**
- `/Views/Components/User/CompanyTeamMembersListView.swift:61`

## DataController Integration

### ✅ Completed Updates
```swift
// Property declaration (line 50)
var syncManager: CentralizedSyncManager!  // Changed from SyncManager

// Initialization (line 166)
self.syncManager = CentralizedSyncManager(
    modelContext: modelContext,
    apiService: apiService,
    connectivityMonitor: connectivityMonitor
)
```

### Methods Already Compatible
- `triggerBackgroundSync(forceProjectSync:)` ✅
- `syncStatePublisher` ✅
- `manualFullSync(companyId:)` ✅
- `syncCompanyTeamMembers(_ company:)` ✅
- `syncUser(_ user:)` ✅
- `addNonExistentUserId()` ✅

## Query Updates Needed

All queries fetching data must exclude soft-deleted records:

```swift
// OLD:
let descriptor = FetchDescriptor<Project>()

// NEW:
let descriptor = FetchDescriptor<Project>(
    predicate: #Predicate { $0.deletedAt == nil }
)
```

**Files Requiring Query Updates:**
- Any view using `@Query` for Project, ProjectTask, CalendarEvent, Client, SubClient, User, TaskType, Company
- Search for `@Query` and `FetchDescriptor` throughout the Views directory

## Consolidated Operations

### updateUser()
**Consolidated From:**
- `updateUserName()`
- `updateUserPhone()`

**New Signature:**
```swift
func updateUser(userId: String, firstName: String?, lastName: String?, phone: String?) async throws
```

**Migration:**
```swift
// OLD:
syncManager.updateUserName(user, firstName: "John", lastName: "Doe")
syncManager.updateUserPhone(user, phone: "555-1234")

// NEW:
try await syncManager.updateUser(
    userId: user.id,
    firstName: "John",
    lastName: "Doe",
    phone: "555-1234"
)
```

### manualFullSync()
**Consolidated From:**
- `manualFullSync(companyId:)`
- `forceSyncProjects()`

**New Signature:**
```swift
func manualFullSync(companyId: String? = nil) async throws
// companyId parameter deprecated but kept for backwards compatibility
```

## New UI Feedback Properties

CentralizedSyncManager provides real-time sync status:

```swift
@Published var hasError: Bool = false
@Published var statusText: String = "Ready"
@Published var progress: Double = 0.0
@Published var totalCount: Int = 0
```

**Usage Example:**
```swift
// In a view
@EnvironmentObject var dataController: DataController

var body: some View {
    VStack {
        if dataController.syncManager.hasError {
            Text("Sync Error")
        }
        Text(dataController.syncManager.statusText)
        ProgressView(value: dataController.syncManager.progress,
                     total: Double(dataController.syncManager.totalCount))
    }
}
```

## Testing Checklist

Before deleting SyncManager_OLD.swift:

- [ ] Build succeeds without errors
- [ ] Manual sync works (`syncAll()`)
- [ ] App launch sync works (`syncAppLaunch()`)
- [ ] Background sync works (`triggerBackgroundSync()`)
- [ ] Individual object updates work (project status, task notes, etc.)
- [ ] Soft delete works (deleted records marked with `deletedAt`)
- [ ] Queries exclude deleted records
- [ ] Team member sync works
- [ ] Task type sync works
- [ ] Client operations work (create, edit, delete sub-clients)
- [ ] Profile image upload works
- [ ] Sync state publisher updates UI correctly

## Rollback Plan

If issues arise:

1. Revert DataController changes:
   ```swift
   var syncManager: SyncManager_OLD!

   self.syncManager = SyncManager_OLD(
       modelContext: modelContext,
       apiService: apiService,
       connectivityMonitor: connectivityMonitor,
       userIdProvider: userIdProvider
   )
   ```

2. Rename back: `SyncManager_OLD.swift` → `SyncManager.swift`

3. Remove `@available(*, deprecated)` annotation

4. Keep CentralizedSyncManager for future migration
