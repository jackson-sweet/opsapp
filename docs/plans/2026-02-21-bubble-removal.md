# Bubble Removal — Full Supabase Cutover

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Delete all Bubble/APIService code from the iOS app and make SupabaseSyncManager the sole sync engine, so the feature branch builds and runs with zero Bubble dependencies.

**Architecture:** SupabaseSyncManager already exists with matching public API. DataController currently routes through `syncManager` (CentralizedSyncManager) and `apiService` (APIService). We delete both, promote SupabaseSyncManager to `syncManager`, add missing CRUD methods to repositories, and rewrite every call site. Views that created Bubble DTOs (TaskDTO, CalendarEventDTO) will instead call SupabaseSyncManager methods that internally use Supabase repositories.

**Tech Stack:** Supabase Swift SDK, SwiftData, existing repositories in `OPS/Network/Supabase/Repositories/`

---

## Sprint 1: Delete Bubble Files + Swap Sync Manager Type

**Goal:** Remove all Bubble-only files and change DataController to use SupabaseSyncManager as `syncManager`. This will cause many compile errors — that's expected. Subsequent sprints fix them.

### Task 1.1: Delete Bubble files (22 files)

**Delete these files:**

```
OPS/Network/API/APIService.swift
OPS/Network/API/APIError.swift
OPS/Network/API/BubbleFields.swift
OPS/Network/DTOs/AppMessageDTO.swift
OPS/Network/DTOs/CalendarEventDTO.swift
OPS/Network/DTOs/ClientDTO.swift
OPS/Network/DTOs/CompanyDTO.swift
OPS/Network/DTOs/OpsContactDTO.swift
OPS/Network/DTOs/ProjectDTO.swift
OPS/Network/DTOs/SubClientDTO.swift
OPS/Network/DTOs/TaskDTO.swift
OPS/Network/DTOs/TaskStatusOptionDTO.swift
OPS/Network/DTOs/TaskTypeDTO.swift
OPS/Network/DTOs/UserDTO.swift
OPS/Network/Endpoints/CalendarEventEndpoints.swift
OPS/Network/Endpoints/ClientEndpoints.swift
OPS/Network/Endpoints/CompanyEndpoints.swift
OPS/Network/Endpoints/ProjectEndpoints.swift
OPS/Network/Endpoints/TaskEndpoints.swift
OPS/Network/Endpoints/TaskTypeEndpoints.swift
OPS/Network/Endpoints/UserEndpoints.swift
OPS/Network/Sync/CentralizedSyncManager.swift
OPS/Utilities/SyncManagerFlag.swift
```

Also remove references from the Xcode project file (pbxproj).

### Task 1.2: Swap sync manager in DataController

**File:** `OPS/Utilities/DataController.swift`

**Changes:**
1. Remove `let apiService: APIService` property
2. Remove `var syncManager: CentralizedSyncManager!` — rename `supabaseSyncManager` to `syncManager` and change type to `SupabaseSyncManager!`
3. Remove APIService initialization from `init()`
4. In `setupModelContext()`: remove CentralizedSyncManager init, rename SupabaseSyncManager assignment to `self.syncManager`
5. Remove `apiService` parameter from ImageSyncManager init (it accepts but never uses it — change ImageSyncManager init to drop it)
6. Update `syncStatePublisher` subscription to use the renamed property

### Task 1.3: Fix ImageSyncManager init signature

**File:** `OPS/Network/ImageSyncManager.swift`

Remove the `apiService: APIService` parameter and `private let apiService: APIService` property (it's never used).

### Task 1.4: Commit

```
git add -A && git commit -m "chore: delete Bubble files, swap to SupabaseSyncManager"
```

---

## Sprint 2: Add Missing Repository Methods

**Goal:** The existing repositories have fetch/upsert/updateStatus/softDelete. DataController and views need additional CRUD operations. Add them now so Sprint 3 call site rewrites compile.

### Task 2.1: Add missing ProjectRepository methods

**File:** `OPS/Network/Supabase/Repositories/ProjectRepository.swift`

**Add these methods:**
- `updateDates(_ projectId: String, startDate: Date?, endDate: Date?)` — updates `start_date`, `end_date`, `updated_at`
- `updateAddress(_ projectId: String, address: String)` — updates `address`, `updated_at`
- `updateTeamMembers(_ projectId: String, memberIds: [String])` — updates `team_member_ids`, `updated_at`
- `updateFields(_ projectId: String, fields: [String: AnyJSON])` — generic field update with `updated_at`

### Task 2.2: Add missing TaskRepository methods

**File:** `OPS/Network/Supabase/Repositories/TaskRepository.swift`

**Add these methods:**
- `create(_ dto: SupabaseProjectTaskDTO) async throws -> SupabaseProjectTaskDTO` — insert and return
- `updateFields(_ taskId: String, fields: [String: AnyJSON])` — generic update
- `updateTeamMembers(_ taskId: String, memberIds: [String])` — updates `team_member_ids`, `updated_at`

### Task 2.3: Add missing CalendarEventRepository methods

**File:** `OPS/Network/Supabase/Repositories/CalendarEventRepository.swift`

**Add these methods:**
- `create(_ dto: SupabaseCalendarEventDTO) async throws -> SupabaseCalendarEventDTO` — insert and return
- `update(_ id: String, fields: [String: AnyJSON])` — generic field update
- `updateTeamMembers(_ id: String, memberIds: [String])` — updates `team_member_ids`, `updated_at`

### Task 2.4: Add missing UserRepository methods

**File:** `OPS/Network/Supabase/Repositories/UserRepository.swift`

**Add these methods:**
- `updateFields(userId: String, fields: [String: AnyJSON])` — generic field update with `updated_at`

### Task 2.5: Add missing CompanyRepository methods

**File:** `OPS/Network/Supabase/Repositories/CompanyRepository.swift`

Already has `update(companyId:updates:)` and `updateSeatedEmployees(companyId:userIds:)`. May need:
- `fetchUsers(companyId: String) async throws -> [SupabaseUserDTO]` — fetch company's users (currently in UserRepository — just confirm it's accessible)

### Task 2.6: Commit

```
git add -A && git commit -m "feat: add missing CRUD methods to Supabase repositories"
```

---

## Sprint 3: Add Missing SupabaseSyncManager Methods

**Goal:** SupabaseSyncManager needs methods that views/DataController call but which currently only exist on CentralizedSyncManager or go through apiService directly.

### Task 3.1: Add write operations to SupabaseSyncManager

**File:** `OPS/Network/Sync/SupabaseSyncManager.swift`

**Add these methods (following the existing pattern of optimistic local update + Supabase push):**

1. `updateProjectDates(projectId: String, startDate: Date?, endDate: Date?)` — local update + repo.updateDates
2. `updateProjectAddress(projectId: String, address: String)` — local update + repo.updateAddress
3. `updateProjectTeamMembers(projectId: String, memberIds: [String])` — local update + repo.updateTeamMembers
4. `updateTaskFields(taskId: String, updates: [String: Any])` — local update + repo.updateFields
5. `updateTaskTeamMembers(taskId: String, memberIds: [String])` — local update + repo.updateTeamMembers
6. `createTask(dto: SupabaseProjectTaskDTO) async throws -> String` — insert locally + create on Supabase, return ID
7. `deleteTask(taskId: String)` — soft delete locally + repo.softDelete
8. `createCalendarEvent(dto: SupabaseCalendarEventDTO) async throws -> String` — insert + create, return ID
9. `deleteCalendarEvent(eventId: String)` — soft delete locally + repo.softDelete
10. `updateCalendarEvent(eventId: String, fields: [String: AnyJSON])` — local update + repo.update
11. `updateCalendarEventTeamMembers(eventId: String, memberIds: [String])` — local + repo.updateTeamMembers
12. `updateUserFields(userId: String, fields: [String: AnyJSON])` — local + repo.updateFields
13. `updateCompanyFields(companyId: String, fields: [String: String])` — local + companyRepo.update
14. `updateCompanySeatedEmployees(companyId: String, userIds: [String])` — local + companyRepo.updateSeatedEmployees
15. `deleteClient(clientId: String)` — soft delete + repo.softDelete
16. `deleteUser(userId: String)` — soft delete + repo.softDelete
17. `fetchUser(id: String) async throws -> User?` — fetch from Supabase, upsert locally, return
18. `fetchCompany(id: String) async throws -> Company?` — fetch from Supabase, upsert locally, return
19. `updateClient(clientId: String, fields: [String: String])` — local + repo update

### Task 3.2: Add OpsContact sync support

**File:** `OPS/Network/Sync/SupabaseSyncManager.swift`

The app fetches OpsContacts for the contact list. Add:
- `fetchOpsContacts(companyId: String) async throws -> [OpsContact]` — query Supabase `ops_contacts` table

This may also need a lightweight `OpsContactRepository.swift` if one doesn't exist.

### Task 3.3: Commit

```
git add -A && git commit -m "feat: add missing CRUD and write methods to SupabaseSyncManager"
```

---

## Sprint 4: Rewrite DataController

**Goal:** DataController has ~36 direct `apiService.xxx()` calls. Replace each with the equivalent SupabaseSyncManager or repository call.

### Task 4.1: Remove apiService references from DataController

**File:** `OPS/Utilities/DataController.swift`

For each `apiService.xxx()` call, replace with the equivalent `syncManager.xxx()` call:

| Old call | New call |
|----------|----------|
| `apiService.fetchCompany(id:)` | `syncManager.fetchCompany(id:)` |
| `apiService.fetchUser(id:)` | `syncManager.fetchUser(id:)` |
| `apiService.fetchProject(id:)` | Fetch from local SwiftData (project is already synced) |
| `apiService.updateProjectStatus(id:status:)` | `syncManager.updateProjectStatus(projectId:status:)` |
| `apiService.updateProjectDates(...)` | `syncManager.updateProjectDates(projectId:startDate:endDate:)` |
| `apiService.updateProjectNotes(id:notes:)` | `syncManager.updateProjectNotes(projectId:notes:)` |
| `apiService.updateProject(id:updates:)` | `syncManager.updateProjectAddress(projectId:address:)` (for address updates) |
| `apiService.updateProjectTeamMembers(projectId:teamMemberIds:)` | `syncManager.updateProjectTeamMembers(projectId:memberIds:)` |
| `apiService.updateTaskStatus(id:status:)` | `syncManager.updateTaskStatus(taskId:status:)` |
| `apiService.updateTask(id:updates:)` | `syncManager.updateTaskFields(taskId:updates:)` |
| `apiService.updateTaskTeamMembers(id:teamMemberIds:)` | `syncManager.updateTaskTeamMembers(taskId:memberIds:)` |
| `apiService.createTask(dto)` | `syncManager.createTask(dto:)` |
| `apiService.deleteTask(id:)` | `syncManager.deleteTask(taskId:)` |
| `apiService.deleteCalendarEvent(id:)` | `syncManager.deleteCalendarEvent(eventId:)` |
| `apiService.updateCalendarEvent(id:updates:)` | `syncManager.updateCalendarEvent(eventId:fields:)` |
| `apiService.updateCalendarEventTeamMembers(id:teamMemberIds:)` | `syncManager.updateCalendarEventTeamMembers(eventId:memberIds:)` |
| `apiService.updateUser(userId:fields:)` | `syncManager.updateUserFields(userId:fields:)` |
| `apiService.updateCompanyFields(companyId:fields:)` | `syncManager.updateCompanyFields(companyId:fields:)` |
| `apiService.updateCompanySeatedEmployees(companyId:userIds:)` | `syncManager.updateCompanySeatedEmployees(companyId:userIds:)` |
| `apiService.fetchCompanyUsers(companyId:)` | `syncManager.syncUsers()` then read from SwiftData |
| `apiService.deleteUser(id:)` | `syncManager.deleteUser(userId:)` |
| `apiService.deleteClient(id:)` | `syncManager.deleteClient(clientId:)` |
| `apiService.updateClientContact(...)` | `syncManager.updateClientContact(clientId:name:email:phone:address:)` |
| `apiService.updateClient(...)` | `syncManager.updateClient(clientId:fields:)` |
| `apiService.fetchTaskStatusOptions(companyId:)` | Remove — task status options come from the enum, not API |
| `apiService.executeRequest(...)` for OpsContacts | `syncManager.fetchOpsContacts(companyId:)` |
| `apiService.fetchUserProjectsForDate(...)` | Query local SwiftData directly |

### Task 4.2: Commit

```
git add -A && git commit -m "refactor: rewrite DataController to use SupabaseSyncManager"
```

---

## Sprint 5: Rewrite View-Level API Calls

**Goal:** Views that directly create Bubble DTOs (TaskDTO, CalendarEventDTO) or call apiService need rewriting.

### Task 5.1: Rewrite ProjectFormSheet

**File:** `OPS/Views/JobBoard/ProjectFormSheet.swift`

- Replace `TaskDTO(...)` creation + `apiService.createTask()` with `syncManager.createTask(dto:)` using `SupabaseProjectTaskDTO`
- Replace `CalendarEventDTO(...)` creation + `apiService.createAndLinkCalendarEvent()` with `syncManager.createCalendarEvent(dto:)` using `SupabaseCalendarEventDTO`

### Task 5.2: Rewrite TaskFormSheet

**File:** `OPS/Views/JobBoard/TaskFormSheet.swift`

- Replace `TaskDTO.from(task)` + `apiService.createTask()` with `syncManager.createTask(dto:)`
- Replace `CalendarEventDTO(...)` + `apiService.createAndLinkCalendarEvent()` with `syncManager.createCalendarEvent(dto:)`

### Task 5.3: Rewrite TaskDetailsView

**File:** `OPS/Views/Components/Project/TaskDetailsView.swift`

- Replace `CalendarEventDTO(...)` + `apiService.createAndLinkCalendarEvent()` with `syncManager.createCalendarEvent(dto:)`
- Replace `apiService.updateProjectStatus()` calls with `syncManager.updateProjectStatus()`

### Task 5.4: Rewrite TaskListView

**File:** `OPS/Views/Components/Tasks/TaskListView.swift`

- Replace `CalendarEventDTO(...)` + `apiService.createAndLinkCalendarEvent()` with `syncManager.createCalendarEvent(dto:)`
- Replace `apiService.deleteCalendarEvent/deleteTask/updateProjectDates` with syncManager equivalents

### Task 5.5: Rewrite HomeContentView + HomeView

**Files:** `OPS/Views/Home/HomeContentView.swift`, `OPS/Views/Home/HomeView.swift`

- Replace `apiService.startProject()` / `apiService.updateProjectStatus()` with `syncManager.updateProjectStatus()`

### Task 5.6: Rewrite ContactDetailView

**File:** `OPS/Views/Components/User/ContactDetailView.swift`

- All syncManager calls already go through `syncManager.updateClientContact()`, `syncManager.createSubClient()`, etc.
- Just fix any remaining `apiService` references (deleteSubClient, manualFullSync)

### Task 5.7: Rewrite ManageTeamView + team views

**Files:**
- `OPS/Views/Settings/Organization/ManageTeamView.swift`
- `OPS/Views/Components/Team/TeamRoleManagementView.swift`
- `OPS/Views/Components/Team/TeamRoleAssignmentSheet.swift`

- Replace `apiService.updateUser(userId:fields:)` with `syncManager.updateUserFields(userId:fields:)`
- Replace BubbleFields references with Supabase column names

### Task 5.8: Rewrite OnboardingManager + OnboardingViewModel

**Files:**
- `OPS/Onboarding/Manager/OnboardingManager.swift`
- `OPS/Onboarding/ViewModels/OnboardingViewModel.swift`

- Replace `apiService.updateUser(userId:fields:)` with `syncManager.updateUserFields(userId:fields:)`
- Replace BubbleFields references with Supabase column names

### Task 5.9: Rewrite remaining files

**Files:**
- `OPS/Views/Settings/Organization/OrganizationDetailsView.swift` — `apiService.updateCompanyFields` → `syncManager.updateCompanyFields`
- `OPS/Utilities/SubscriptionManager.swift` — `apiService.updateCompanyFields/updateCompanySeatedEmployees` → syncManager equivalents
- `OPS/Tutorial/Flows/TutorialLauncherView.swift` — `apiService.updateUser` → `syncManager.updateUserFields`
- `OPS/Views/Subscription/SeatManagementView.swift` (if it references apiService)
- `OPS/Utilities/DataHealthManager.swift` — replace `apiService.fetchBubbleObjects` with Supabase query or syncManager call
- `OPS/Utilities/NotificationManager.swift` — replace `BubbleFields.User.deviceToken` with the Supabase column name `"device_token"`
- `OPS/Views/Components/User/ProjectTeamView.swift` — replace BubbleFields references
- `OPS/Views/Components/Common/UnassignedRolesOverlay.swift` — replace BubbleFields references
- `OPS/Network/Services/AppMessageService.swift` — uses AppMessageDTO, may need a Supabase equivalent or removal

### Task 5.10: Delete or gut debug views

**Files:**
- `OPS/Views/Debug/APICallsDebugView.swift` — DELETE (entirely Bubble API testing)
- `OPS/Views/Debug/CalendarEventsDebugView.swift` — remove apiService calls, keep local data display
- `OPS/Views/Debug/RelinkCalendarEventsView.swift` — remove apiService calls or delete
- `OPS/Views/Debug/RelinkTasksToProjectsView.swift` — remove apiService calls or delete
- `OPS/Views/Debug/TaskListDebugView.swift` — remove apiService calls, keep local data display
- `OPS/Views/Debug/TaskTypesDebugView.swift` — remove apiService calls, keep local data display

### Task 5.11: Commit

```
git add -A && git commit -m "refactor: rewrite all view-level calls to use Supabase"
```

---

## Sprint 6: Build, Fix, Verify

### Task 6.1: Build and fix all remaining compile errors

```
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Fix any remaining type mismatches, missing imports, or broken references iteratively until BUILD SUCCEEDED.

### Task 6.2: Clean up empty directories

Remove `OPS/Network/DTOs/` and `OPS/Network/Endpoints/` directories if empty. Remove `OPS/Network/API/` directory.

### Task 6.3: Final commit

```
git add -A && git commit -m "chore: fix remaining compile errors after Bubble removal"
```

---

## Key Mapping Reference

### BubbleFields → Supabase Column Names

| BubbleFields constant | Supabase column |
|---|---|
| `BubbleFields.User.firstName` | `first_name` |
| `BubbleFields.User.lastName` | `last_name` |
| `BubbleFields.User.email` | `email` |
| `BubbleFields.User.phone` | `phone` |
| `BubbleFields.User.role` | `role` |
| `BubbleFields.User.userType` | `user_type` |
| `BubbleFields.User.deviceToken` | `device_token` |
| `BubbleFields.User.hasCompletedAppOnboarding` | `has_completed_app_onboarding` |
| `BubbleFields.User.hasCompletedAppTutorial` | `has_completed_app_tutorial` |
| `BubbleFields.User.profileImage` | `profile_image_url` |
| `BubbleFields.Company.seatedEmployeeIds` | `seated_employee_ids` |
| `BubbleFields.Company.subscriptionStatus` | `subscription_status` |
| `BubbleFields.Project.status` | `status` |
| `BubbleFields.Project.teamMembers` | `team_member_ids` |

### Bubble DTO → Supabase DTO

| Bubble DTO | Supabase DTO | Notes |
|---|---|---|
| `TaskDTO` | `SupabaseProjectTaskDTO` | Different column names (task_notes, custom_title, task_color) |
| `CalendarEventDTO` | `SupabaseCalendarEventDTO` | No task_id column — linkage via project_tasks.calendar_event_id |
| `ProjectDTO` | `SupabaseProjectDTO` | |
| `ClientDTO` | `SupabaseClientDTO` | phone_number (not phone) |
| `SubClientDTO` | `SupabaseSubClientDTO` | phone_number (not phone) |
| `UserDTO` | `SupabaseUserDTO` | |
| `CompanyDTO` | `SupabaseCompanyDTO` | |
| `TaskTypeDTO` | `SupabaseTaskTypeDTO` | Table: task_types_v2 |
| `AppMessageDTO` | (needs new DTO or removal) | |
| `OpsContactDTO` | (needs new DTO or query) | |
| `TaskStatusOptionDTO` | (remove — use enum) | |

---

## Risk Notes

- **CalendarEvent task linkage**: Bubble has `task_id` on calendar_events. Supabase does NOT — the FK is `calendar_event_id` on `project_tasks`. Any code that sets `calendarEvent.taskId` from a DTO needs review.
- **Team member IDs**: Stored as `team_member_ids` array in Supabase, not a Bubble list field. The SupabaseDTO uses `[String]?` which maps correctly.
- **BubbleFields scattered references**: Some views use BubbleFields constants for field names. All must be replaced with Supabase snake_case column names.
- **AppMessageService**: Uses AppMessageDTO which maps to a Bubble type. Either create a Supabase `app_messages` table query or remove the feature temporarily.
- **Debug views**: Several debug views are 100% Bubble API testing. Safest to delete them entirely.
