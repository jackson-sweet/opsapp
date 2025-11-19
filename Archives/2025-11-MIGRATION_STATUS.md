# Migration Status - Task-Only Scheduling Migration

## 🚀 TASK-ONLY SCHEDULING MIGRATION (November 18, 2025)

### Status: **IN PROGRESS** - Awaiting Final Build Verification

### Overview:
Complete removal of dual-scheduling system (project-level vs task-level calendar events) to unified task-only scheduling architecture.

---

# Sync Migration Status - CentralizedSyncManager

## ✅ COMPLETED WORK

### 1. All DTOs Updated with Soft Delete Support
- ✅ UserDTO - Added `deletedAt` field with parsing
- ✅ ClientDTO - Added `deletedAt` field with parsing
- ✅ SubClientDTO - Added `deletedAt` field with parsing
- ✅ TaskTypeDTO - Added `deletedAt` field with parsing
- ✅ CompanyDTO - Added `deletedAt` field with parsing
- ✅ ProjectDTO - Already had `deletedAt`
- ✅ TaskDTO - Already had `deletedAt`
- ✅ CalendarEventDTO - Already had `deletedAt`

### 2. All Data Models Updated with Soft Delete
- ✅ User - Has `deletedAt: Date?`
- ✅ Client - Has `deletedAt: Date?`
- ✅ SubClient - Has `deletedAt: Date?`
- ✅ TaskType - Has `deletedAt: Date?`
- ✅ Company - Has `deletedAt: Date?`
- ✅ Project - Has `deletedAt: Date?`
- ✅ ProjectTask - Has `deletedAt: Date?`
- ✅ CalendarEvent - Has `deletedAt: Date?`

### 3. CentralizedSyncManager Created
- ✅ All sync operations consolidated into single file
- ✅ Master sync functions: `syncAll()`, `syncAppLaunch()`, `syncBackgroundRefresh()`
- ✅ Individual sync functions for each data type
- ✅ Update operations for individual records
- ✅ Create/delete operations for sub-clients
- ✅ Smart soft delete logic (30-day window)
- ✅ UI feedback properties (`hasError`, `statusText`, `progress`)
- ✅ Sync state publisher for UI updates
- ✅ Background sync trigger method
- ✅ Comprehensive inline documentation with view references

### 4. DataController Migrated
- ✅ Changed `syncManager` type from `SyncManager` to `CentralizedSyncManager`
- ✅ Updated initialization to use `CentralizedSyncManager`
- ✅ All method signatures remain compatible

### 5. View References Updated
- ✅ TaskDetailsView - Changed `id:` to `taskId:` for updateTaskNotes
- ✅ ContactDetailView - Removed unnecessary return value handling for updateClientContact
- ✅ ContactDetailView - Updated createSubClient to use model return type instead of DTO

### 6. ProjectsViewModel Updated
- ✅ Changed to use `CentralizedSyncManager` instead of `SyncManager`

### 7. Old SyncManager Deprecated
- ✅ Renamed to `SyncManager_OLD.swift`
- ✅ Added deprecation notice: `@available(*, deprecated)`
- ✅ Updated class name to `SyncManager_OLD`

### 8. Comprehensive Documentation Created
- ✅ SYNC_MIGRATION_GUIDE.md - Complete migration guide with examples
- ✅ QUERY_PREDICATE_GUIDE.md - Guide for adding `deletedAt` predicates to queries
- ✅ Both guides include testing checklists and rollback plans

## ✅ ALL COMPILATION ERRORS FIXED

**BUILD STATUS: SUCCEEDED** 🎉

All implementation bugs in CentralizedSyncManager have been fixed:

### Fixed Error Categories:

#### 1. DTO Property Access Errors
CentralizedSyncManager incorrectly accesses DTO properties directly instead of using the DTO's `toModel()` method:

**Problem**: `dto.companyId` (doesn't exist on DTO)
**Solution**: Use `dto.toModel()` then access model properties

**Affected Lines in CentralizedSyncManager.swift**:
- Line 222: Company companyId access
- Line 223: CompanyDTO logoURL access (should use `logo?.url`)
- Line 285-286: UserDTO firstName/lastName (use `nameFirst`, `nameLast`)
- Line 387: TaskTypeDTO icon (doesn't exist in DTO, set during toModel())
- Line 445: ProjectDTO companyId (use `company?.stringValue`)
- Line 453: ProjectDTO clientId (use `client`)
- Line 458: ProjectDTO teamMemberIds (use `teamMembers`)
- Line 796-797: SubClientDTO email/phone (use `emailAddress`, `phoneNumber`)

#### 2. String to Date Assignment Errors
Trying to assign String? to Date? without parsing:

**Affected Lines**:
- Line 304, 350, 392, 441, 442, 463, 513, 570

**Solution**: Use ISO8601DateFormatter to parse strings to dates

#### 3. API Method Signature Mismatches
Calling API methods with incorrect parameters:

**Examples**:
- Line 731: `updateUser` - Check correct parameters
- Line 765, 792: Parameter mismatches
- Line 823: `updateSubClient` - Verify method exists in APIService
- Line 859: `deleteSubClient` - Check parameter label
- Line 1005, 1248: TaskType/Company API calls - Verify signatures

#### 4. Missing deletedAt in DTO Constructors
- TaskDTO.from() - Line 135
- SyncManager_OLD - Lines 1031, 1065, 3350 (can ignore since deprecated)

## ✅ ALL FIXES COMPLETED

All errors have been successfully fixed:
1. ✅ Fixed DTO property access throughout CentralizedSyncManager
2. ✅ Added ISO8601DateFormatter parsing for all deletedAt fields
3. ✅ Updated all API method calls to match correct signatures
4. ✅ Added missing `deletedAt` parameters to all DTO constructors
5. ✅ Added `performOnboardingSync()` method for onboarding flow
6. ✅ Fixed all async/await and error handling in view files
7. ✅ Updated all `forceSyncProjects()` calls to `manualFullSync()`
8. ✅ Fixed all `refreshSingleClient()` calls to use new signature
9. ✅ Fixed model initializer calls in helper functions

**PROJECT NOW BUILDS SUCCESSFULLY** ✅

## 🔥 CRITICAL BUG FIXES - Manual Sync Data Loss Issue

**Date:** 2025-11-03

### Problem Discovered:
When users tapped the manual sync button in Calendar View, ALL projects and tasks would disappear from the database, and the user's role would reset to Field Crew.

### Root Causes Identified:

#### 1. EmployeeType Conversion Bug (BubbleFields.swift)
**Issue:** The `toSwiftEnum()` function was checking for wrong values from Bubble API
- **Expected by code:** `"Office"`, `"Crew"`, `"Foreman"`, `"Admin"`
- **Actually sent by Bubble:** `"Office Crew"`, `"Field Crew"`, `"Admin"`
- **Result:** All Office Crew users defaulted to Field Crew role

**Fix:** Updated `BubbleFields.EmployeeType` to check for actual Bubble values:
```swift
case officeCrew: return .officeCrew  // "Office Crew" from Bubble
case fieldCrew: return .fieldCrew    // "Field Crew" from Bubble
case admin: return .admin            // "Admin" from Bubble
```

#### 2. Missing Company Admin Check (CentralizedSyncManager.syncUsers)
**Issue:** `syncUsers()` wasn't checking `company.adminIds` to determine admin status
- Users in `company.adminIds` array should get `.admin` role
- Code only checked API's `employeeType` field (which may be nil or wrong)
- No fallback when `employeeType` was missing

**Fix:** Added three-tier role assignment logic matching `UserDTO.toModel()`:
1. First check if user is in `company.adminIds` → `.admin` role
2. Then check API's `employeeType` → convert using fixed conversion
3. Finally default to `.fieldCrew` if both missing

#### 3. Cascading Data Loss
**The Chain Reaction:**
1. User taps manual sync in Calendar View
2. `syncAll()` runs → `syncUsers()` executes
3. `syncUsers()` incorrectly sets admin user to `.fieldCrew` role (due to bugs above)
4. `syncProjects()` executes immediately after
5. `syncProjects()` checks user role - sees `.fieldCrew`
6. Fetches only user-assigned projects (3 projects) instead of all company projects (96 projects)
7. Deletion logic sees 93 "missing" projects and soft-deletes them ❌
8. All data appears to vanish from the app

### Files Changed:
- `BubbleFields.swift:51-66` - Fixed EmployeeType values to match Bubble
- `CentralizedSyncManager.swift:386-440` - Added company admin ID checking and proper role assignment
- `BUBBLE_FIELD_MAPPINGS.md:335-342` - Updated documentation with actual Bubble values
- `syncCalendarEvents()` - Fixed to use company's defaultProjectColor for project events

### Impact:
- ✅ User roles preserved correctly during sync
- ✅ Admin users maintain admin access to all company projects
- ✅ Office Crew users correctly identified and given proper access
- ✅ Manual sync no longer deletes data
- ✅ Calendar events display with correct company colors

**PROJECT NOW BUILDS SUCCESSFULLY** ✅

## 📋 TASK-ONLY SCHEDULING MIGRATION - COMPLETED PHASES

### Phase 1: Data Models ✅
- ✅ CalendarEvent.swift - Removed CalendarEventType enum, type, active, and all dual-scheduling properties
- ✅ Project.swift - Removed eventType, primaryCalendarEvent, scheduling mode properties
- ✅ Project.swift - Added computedStartDate and computedEndDate as computed properties from tasks

### Phase 2: DTOs ✅
- ✅ CalendarEventDTO.swift - Removed type and active fields
- ✅ ProjectDTO.swift - Removed eventType field

### Phase 3: Sync Manager ✅
- ✅ CentralizedSyncManager.swift - Removed eventType assignment, simplified CalendarEvent creation
- ✅ CentralizedSyncManager.swift - Removed migrateProjectEventColors() function

### Phase 4: API & UI ✅
- ✅ CalendarEventEndpoints.swift - Simplified to task-only linking
- ✅ ProjectEndpoints.swift - Removed eventType syncing
- ✅ ProjectDetailsView.swift - Removed scheduling mode badge and switching UI
- ✅ TaskFormSheet.swift - Removed eventType conversion logic
- ✅ ProjectFormSheet.swift - Removed createCalendarEventForProject
- ✅ DataController.swift - Replaced SortDescriptor(\.startDate) with in-memory sorting comments

### Phase 5: Migration Code ✅
- ✅ OPSApp.swift - Added deleteProjectLevelCalendarEvents() with UserDefaults flag

### Compilation Error Fixes ✅
- ✅ TaskListView.swift - Removed usesTaskBasedScheduling checks, fixed CalendarEventDTO init
- ✅ ProjectTeamView.swift - Removed usesTaskBasedScheduling check
- ✅ CalendarEventsDebugView.swift - Removed CalendarEvent.fromProject() call
- ✅ ProjectDetailsCard.swift - Removed event.type checks
- ✅ ProjectSearchFilterView.swift - Removed scheduling type filter code
- ✅ ProjectManagementSheets.swift - Removed updateProjectEventTypeCache calls
- ✅ RelinkCalendarEventsView.swift - Fixed for task-only events

### Current Status: ⏳ AWAITING BUILD VERIFICATION
Running clean build to verify all compilation errors resolved...

---

## 📋 NEXT STEPS (Original Sync Migration)

1. ✅ **Fix Compilation Errors** - COMPLETED
   - All DTO property access fixed
   - All API method signatures corrected
   - All async/await issues resolved
   - BUILD SUCCEEDED ✅

2. **Testing** (NEXT STEP - RECOMMENDED)
   - Test app launches successfully
   - Test manual sync works (Settings sync button)
   - Test background sync works
   - Test individual operations (update status, notes, etc.)
   - Test onboarding sync flow
   - Test project/task CRUD operations

3. **Add Query Predicates** (1-2 hours)
   - Use QUERY_PREDICATE_GUIDE.md
   - Add `deletedAt == nil` to all @Query declarations
   - Test that deleted items don't appear

4. **Delete SyncManager_OLD** (5 minutes)
   - Only after thorough testing
   - Verify no references remain

5. **Final Testing** (30 minutes)
   - Full sync test
   - Soft delete test
   - Query predicate test
   - Performance check

## 🎯 WHAT'S BEEN ACCOMPLISHED

The **architectural refactoring is 100% complete**:
- ✅ Centralized sync system designed and implemented
- ✅ Soft delete support added to all layers (Models, DTOs)
- ✅ DataController migrated
- ✅ All sync operations consolidated
- ✅ Comprehensive documentation created

What remains are **implementation bugs** (property name mismatches, API signature fixes) that are straightforward to fix. These are not design flaws - just details that need correction.

## 💡 KEY ACHIEVEMENTS

1. **Single Source of Truth**: All sync logic now in one file (`CentralizedSyncManager.swift`)
2. **Easy Debugging**: Each object type has ONE sync function
3. **Soft Delete**: Historical data preserved with `deletedAt` field
4. **Comprehensive Docs**: Migration guide and query guide created
5. **Backwards Compatible**: Old SyncManager preserved for rollback if needed

The foundation is solid - just needs the implementation details fixed to compile.
