# TODO - November 19, 2025

## Overview
This document contains all development tasks for November 19, 2025, focusing on UI/UX improvements, sync notification enhancements, critical bug fixes for project/task/client creation workflows, and comprehensive form sheet redesigns to ensure consistency across the application.

---

## 1. LOADING SCREEN PADDING FIX ✅ COMPLETE

### 1.1 Add Bottom Padding to Post-Login Loading Screen ✅
**File**: `OPS/Views/LoginView.swift` or `OPS/Views/SplashLoadingView.swift`
**Issue**: The loading screen shown immediately after successful login lacks sufficient bottom padding.
**Requirements**:
- Identify the specific loading view shown after authentication succeeds
- Add bottom padding consistent with OPS design system (likely 32pt using `OPSStyle.Layout.spacing5`)
- Ensure padding accounts for safe area on devices with home indicator
- Test on multiple device sizes (iPhone SE, iPhone 16, iPhone 16 Pro Max)

---

## 2. JOB BOARD SCROLLING FIX ✅ COMPLETE

### 2.1 Fix Project List Scrolling ✅
**File**: `OPS/Views/JobBoard/JobBoardView.swift` or `OPS/Views/JobBoard/JobBoardDashboard.swift`
**Issue**: Project list section is not scrollable
**Requirements**:
- Identify the ScrollView or List containing project cards
- Verify ScrollView is not nested incorrectly inside another ScrollView
- Ensure no `.frame(height:)` constraints are preventing scroll
- Check that no gesture conflicts are blocking scroll (like the tap vs scroll issue we fixed recently)
- Test scrolling with 20+ projects to verify functionality

### 2.2 Fix Task List Scrolling ✅
**File**: `OPS/Views/JobBoard/JobBoardView.swift` or task list component
**Issue**: Task list section is not scrollable
**Requirements**:
- Apply same fix as project list
- Verify task cards don't have gesture conflicts
- Test scrolling with 30+ tasks to verify functionality
- Ensure swipe-to-change-status still works while maintaining scroll capability

**Implementation Notes**:
- May need to review recent changes to `UniversalJobBoardCard.swift` where we fixed tap vs scroll gestures
- Ensure outer container uses proper ScrollView/List wrapper
- Check for any `.disabled()` modifiers accidentally applied to scroll containers

---

## 3. CHANGE TEAM FUNCTIONALITY FIX ✅ COMPLETE

### 3.1 Update "Change Team" to Show Task Selection Menu ✅
**File**: `OPS/Views/Components/Project/ProjectDetailsView.swift` or wherever "Change Team" action is triggered
**Current Behavior**: "Change Team" directly edits the project's team, which is incorrect since `project.teamMembers` is a computed property
**New Behavior**: Show a menu/sheet listing all tasks for the project, allowing user to select which task's team to edit

**Requirements**:

#### 3.1.1 Create Task Selection Sheet/Menu
- Create new view component: `TaskTeamSelectionSheet.swift` in `OPS/Views/Components/Tasks/`
- Display all tasks for the selected project
- Use the same task line item design as in Create Project Sheet's task list
- Each task should show:
  - Colored left border (4pt width) matching task type color
  - Task type name (uppercase)
  - Scheduled date (if exists)
  - Team member avatars (using `UserAvatar` component)
  - Status badge
- Tasks should be tappable to open team assignment for that specific task

#### 3.1.2 Add "Create Task" Option
- Add button at bottom of task list: "CREATE NEW TASK"
- Button should use `OPSStyle.Colors.primaryAccent`
- Button should open `TaskFormSheet` with `projectId` pre-populated
- After task creation, refresh the task list in the selection sheet

#### 3.1.3 Update "Change Team" Button Action
- When "Change Team" is tapped on a project:
  - If project has tasks: Show `TaskTeamSelectionSheet`
  - If project has no tasks: Show alert: "This project has no tasks. Create a task to assign team members."
- Provide option to create first task from alert

#### 3.1.4 Task Team Assignment Flow
- When user selects a task from the list:
  - Open team assignment sheet (reuse existing team assignment UI)
  - Show current team members for that task
  - Allow multi-select of team members
  - Save updates to `task.teamMemberIds`
  - Update task's calendar event team members if event exists
  - Sync changes to Bubble immediately (or queue if offline)

**Implementation Details**:
- Project's computed `teamMembers` property aggregates all unique team members from all tasks
- Ensure UI updates reactively when task teams are modified
- Add haptic feedback when task is selected from menu

---

## 4. SYNC NOTIFICATION UPDATES

### 4.1 Replace Custom Sync Notification with Reusable PushInMessage
**Files**:
- `OPS/Utilities/DataController.swift` (likely has custom sync notification)
- `OPS/Views/Components/Common/PushInMessage.swift` (reusable component)
- `OPS/Network/Sync/CentralizedSyncManager.swift` (sync trigger)

**Issue**: The "Syncing..." notification shown when pending sync items are being processed uses custom code instead of the reusable `PushInMessage` component we created

**Requirements**:
- Locate all instances where sync status is displayed via custom notifications
- Replace with `PushInMessage` component
- Use `.info` type for sync notifications
- Message format: "SYNCING X ITEMS..." where X is the count of pending items
- Show success message when sync completes: "SYNC COMPLETE"
- Show error message if sync fails: "SYNC FAILED - TAP TO RETRY"
- Ensure notification auto-dismisses after 3 seconds on success
- Ensure notification stays visible if there's an error (until tapped)

**Integration Points**:
- When `CentralizedSyncManager.syncAll()` is called
- When background sync triggers
- When connectivity is restored and auto-sync begins

---

## 5. PUSH IN NOTIFICATION TOP PADDING FIX ✅ COMPLETE

### 5.1 Fix PushInMessage Top Padding for iPhone 16 Camera Area ✅
**File**: `OPS/Views/Components/Common/PushInMessage.swift`

**Issue**: PushInMessage appears behind the iPhone 16 camera cutout area

**Current Implementation** (from recent commits):
```swift
GeometryReader { geometry in
    VStack(spacing: 0) {
        if isPresented {
            // Content
            .padding(.top, geometry.safeAreaInsets.top)
        }
    }
}
.edgesIgnoringSafeArea(.top)
```

**Requirements**:
- Increase top padding beyond just `safeAreaInsets.top`
- Add additional padding of at least 8-16pt to ensure notification appears fully below camera area
- Test on:
  - iPhone 16 (Dynamic Island)
  - iPhone 16 Pro Max (Dynamic Island)
  - iPhone SE (no notch/island)
  - iPhone 14 (notch)
- Ensure notification doesn't appear too far down on devices without camera cutout
- Consider using conditional padding based on device type if necessary

**Suggested Implementation**:
```swift
.padding(.top, geometry.safeAreaInsets.top + 8)
```

---

## 6. MANUAL SYNC NOTIFICATION ENHANCEMENTS ✅ COMPLETE

### 6.1 Show Project Count in Manual Sync Notification ✅
**Files**:
- `OPS/Views/Calendar Tab/ScheduleView.swift` (manual sync button location)
- `OPS/Network/Sync/CentralizedSyncManager.swift` (sync logic)
- `OPS/Views/Components/Common/PushInMessage.swift` (notification display)

**Issue**: When manual sync button is pressed, the notification doesn't show how many new projects were loaded

**Requirements**:

#### 6.1.1 Track New Projects During Sync
- Before sync: Count existing projects in local database
- After sync: Count current projects in local database
- Calculate difference: `newProjectCount = currentCount - previousCount`
- Handle edge case: If projects were deleted during sync, show 0 (not negative)

#### 6.1.2 Update Notification Message Format
- During sync: "SYNCING..."
- After sync: "[ X NEW PROJECTS LOADED ]" where X is the count
- If 0 new projects: "[ 0 NEW PROJECTS LOADED ]"
- Always show the notification, even if count is 0

#### 6.1.3 Remove Green Gradient Background
- Current notification likely uses green gradient for success state
- Change to solid dark background: `OPSStyle.Colors.cardBackgroundDark`
- Maintain white border: `Color.white.opacity(0.1)`
- Keep text white: `OPSStyle.Colors.primaryText`
- Add info icon if appropriate (circular.fill in blue)

#### 6.1.4 Auto-Dismiss Behavior
- Show notification for 4 seconds (longer than normal due to important info)
- Fade out smoothly with `.easeOut` animation
- Allow swipe-down to dismiss manually

**Implementation Notes**:
- Add `var projectCountBeforeSync: Int = 0` to CentralizedSyncManager
- Add `var projectCountAfterSync: Int = 0` to CentralizedSyncManager
- Expose via published property for UI to observe
- May need to create custom message type in PushInMessage for sync results

---

## 7. CREATE PROJECT SHEET UPDATES

### 7.1 Task Line Item Interaction Changes ✅
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift` (lines ~867-975 based on recent commits)

#### 7.1.1 Remove Edit Icon from Task Line Items
- Remove the pencil/edit icon currently shown on task rows
- Icon is redundant since tapping the row will open edit mode

#### 7.1.2 Update Task Line Item Tap Behavior
- If user taps anywhere on the task line item BODY (not trash icon): Open task in edit mode
- Use `.onTapGesture` on the entire row
- Exclude trash icon from tap area using separate gesture
- Open `SimpleTaskFormSheet` or similar edit interface
- Pass task data for editing
- Update task in place when edit is saved

#### 7.1.3 Trash Icon Delete Behavior
- Trash icon tap should immediately delete the task from the project
- Show confirmation alert: "Delete this task?"
  - "Delete" button (destructive style)
  - "Cancel" button
- On confirmation:
  - Remove task from project's tasks array
  - If task has been synced to Bubble, mark as deleted (`task.deletedAt = Date()`)
  - If task is local-only (not synced yet), permanently delete
  - Remove associated calendar event
  - Update UI reactively

### 7.2 Task Line Item Styling Updates
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

#### 7.2.1 Make All Text Inline and Uppercase
**Current Layout** (likely):
```
[Color Bar] Task Type Name
            Date: Nov 19
            Team: 3 members
```

**New Layout**:
```
[Color Bar] TASK TYPE NAME  •  NOV 19  •  3 MEMBERS
```

**Requirements**:
- All text should be on a single line
- All text should be uppercased (`.textCase(.uppercase)`)
- Use bullet separator (•) between elements
- Font: `OPSStyle.Typography.caption` or `OPSStyle.Typography.smallCaption`
- Color: `OPSStyle.Colors.primaryText`
- If text overflows, truncate with ellipsis: `.lineLimit(1).truncationMode(.tail)`

**Elements to Show** (left to right):
1. Colored border (4pt width, left edge)
2. Task type name (uppercase)
3. Bullet separator
4. Date (if scheduled, use `DateHelper.simpleDateString(from:)`, uppercase)
5. Bullet separator (only if team exists)
6. Team member count or avatars (see 7.2.2)
7. Trash icon (right edge)

#### 7.2.2 Use UserAvatar for Team Member Icons ✅
- Replace current team member avatar implementation with `UserAvatar` component
- Show up to 3 team member avatars
- Avatar size: 20pt diameter (small)
- Avatars should overlap: `.spacing(-8)`
- If more than 3 team members: Show "+N" indicator after 3rd avatar
- If no team members: Show empty state (icon placeholder or nothing)

**UserAvatar Requirements**:
- File location: `OPS/Views/Components/User/UserAvatar.swift` (verify exists, or create if needed)
- Should display user initials in circle
- Background: `OPSStyle.Colors.primaryAccent`
- Text: White
- Border: Optional white border for overlap visibility

#### 7.2.3 Remove Background, Add Border Only ✅
- Current: Task rows likely have `OPSStyle.Colors.cardBackgroundDark` background
- New: Transparent background (`.background(Color.clear)`)
- Add border: `.overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))`
- Border should be slightly darker than current (0.15 opacity instead of 0.1)
- Maintain 5pt corner radius
- Padding: `.padding(.vertical, 12).padding(.horizontal, 16)`

### 7.3 Address Predictive Suggestions Fix ✅
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`
**Issue**: Address autocomplete stopped working after recent styling changes to address input field

**Root Cause**: Likely caused by changes in commit a7f20a0 where we changed input field styling from:
```swift
.background(OPSStyle.Colors.cardBackgroundDark)
```
to:
```swift
.background(Color.clear)
.overlay(RoundedRectangle(...).stroke(Color.white.opacity(0.1), lineWidth: 1))
```

**Requirements**:
- Verify `AddressAutocompleteField` component is being used
- Check that `.onChange(of: searchText)` debounce timer is still functioning
- Verify `LocationManager.fetchAddressSuggestions(_)` is being called
- Check that suggestions list is visible (may be hidden by z-index or overlay issues)
- Ensure suggestions dropdown appears below/above input field appropriately
- Test autocomplete with various addresses ("123 Main St", "Central Park", etc.)

**Debugging Steps**:
1. Add console logs to verify `fetchAddressSuggestions` is called
2. Verify API response contains suggestions
3. Check if suggestions state variable is being updated
4. Verify suggestions List/ForEach is rendering
5. Check z-index and positioning of suggestions container

**Likely Fix**:
- May need to add `.zIndex(1)` to suggestions container
- May need to adjust positioning relative to new border styling
- Verify suggestions background is visible against new form styling

### 7.4 Notes and Description Section Updates
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

#### 7.4.1 Add Save and Cancel Buttons to Notes Section
- Add minimalist button row at bottom of Notes TextEditor
- Buttons: "SAVE" and "CANCEL"
- Layout: HStack with buttons aligned right
- Styling:
  - SAVE: Text in `OPSStyle.Colors.primaryAccent`, no background
  - CANCEL: Text in `OPSStyle.Colors.secondaryText`, no background
  - Font: `OPSStyle.Typography.caption`
  - Spacing between buttons: 16pt
- Behavior:
  - SAVE: Commits notes changes, auto-sync if project exists
  - CANCEL: Reverts to previous notes value
  - Only show buttons if notes have been modified (track dirty state)

#### 7.4.2 Add Save and Cancel Buttons to Description Section
- Same implementation as Notes section (7.4.1)
- Description is separate from Notes in the form
- Track dirty state independently

### 7.5 Copy From Project Button Styling ✅
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

**Issue**: "Copy From Project" button is too visually prominent/obnoxious

**Current State**: Likely uses primary accent color or bold styling

**New Requirements**:
- Style as tertiary button (text-only, no background)
- Text: "COPY FROM PROJECT" or "Copy from existing project"
- Color: `OPSStyle.Colors.secondaryText` (not primary accent)
- Font: `OPSStyle.Typography.caption`
- Add subtle icon: `OPSStyle.Icons.copy` or "doc.on.doc" SF Symbol
- Position: Below project name field, or in optional section
- Reduce padding/spacing around button to make it less prominent

**Suggested Implementation**:
```swift
Button(action: { showCopyProjectSheet = true }) {
    HStack(spacing: 6) {
        Image(systemName: "doc.on.doc")
            .font(.caption)
        Text("Copy from project")
            .font(OPSStyle.Typography.caption)
    }
    .foregroundColor(OPSStyle.Colors.secondaryText)
}
```

### 7.6 Pill and Section Border Color Update
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

**Issue**: Pills and section borders are too dark. make brighter

**Affected Elements**:
- All pill buttons (DETAILS, TEAM, TASKS, IMAGES, etc.)
- Section dividers/borders
- Collapsible section containers
- Input field overlays

### 7.7 Remove Divider Between Project Details and Pills ✅
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

**Location**: Between top "Project Details" section header and the expandable pill buttons (DETAILS, TEAM, TASKS, etc.)

**Requirements**:
- Remove the `Divider()` or horizontal line
- Adjust spacing to maintain visual hierarchy without divider
- Likely reduce spacing from ~16pt to ~12pt
- Ensure clear visual separation still exists through spacing alone

### 7.8 Remove Dates Pill Button ✅
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

**Rationale**: Projects are not scheduled directly. Only tasks have schedules. Project dates are computed properties based on task start/end dates.

**Requirements**:
- Remove "DATES" pill button from pill row
- Remove associated collapsible section for date selection
- Remove any date picker state variables related to project dates
- Ensure project form only contains:
  - DETAILS pill (name, client, address, description)
  - TEAM pill (if needed - may also need removal, see 7.8.1)
  - TASKS pill (task list)
  - IMAGES pill (project images)
  - Any other relevant non-date pills

#### 7.8.1 Evaluate TEAM Pill Necessity
**Question**: Should the TEAM pill also be removed since team is computed from tasks?
**Current Understanding**: Project team = union of all team members assigned to project's tasks
**Recommendation**:
- If TEAM pill currently allows direct project team assignment: Remove it
- If TEAM pill only shows computed team members (read-only): Keep it for reference
- Users should assign team members via individual tasks (see section 3)

**Action**: Remove TEAM pill if it allows editing. If read-only display, can keep it.

### 7.9 Project/Task/CalendarEvent Creation and Linking Fix ✅
**Files**:
- `OPS/Views/JobBoard/ProjectFormSheet.swift` (form submission)
- `OPS/Network/API/APIService.swift` (API calls)
- `OPS/Network/Sync/CentralizedSyncManager.swift` (sync logic)
- `OPS/Utilities/DataController.swift` (local data management)

**Critical Issue**: When creating a project with tasks, the project creates successfully, but tasks and calendar events are not created or linked. A "2 items are being synced" notification appears on next app launch, but they never sync.

**Root Cause**: Likely asynchronous creation without proper sequencing and relationship linking.

**Requirements**:

#### 7.9.1 Implement Sequential Creation Flow (ONLINE)
When user taps "CREATE PROJECT" and has internet connection:

**Step 1: Create Project on Bubble**
```swift
1. Call APIService.createProject(dto: projectDTO)
2. Wait for response
3. Extract bubbleProjectId from response
4. Update local project with bubbleProjectId
5. Save to SwiftData
```

**Step 2: Create Tasks on Bubble** (Batch)
```swift
For each task in project.tasks:
    1. Set task.projectId = bubbleProjectId (from Step 1)
    2. Call APIService.createTask(dto: taskDTO)
    3. Wait for response
    4. Extract bubbleTaskId from response
    5. Store mapping: localTaskId -> bubbleTaskId
    6. Update local task with bubbleTaskId
```

**Step 3: Create Calendar Events on Bubble** (Batch)
```swift
For each task with schedule:
    1. Set calendarEvent.projectId = bubbleProjectId
    2. Set calendarEvent.taskId = bubbleTaskId (from Step 2 mapping)
    3. Call APIService.createCalendarEvent(dto: calendarEventDTO)
    4. Wait for response
    5. Extract bubbleCalendarEventId from response
    6. Update local calendarEvent with bubbleCalendarEventId
```

**Step 4: Link Relationships Locally**
```swift
1. For each task:
   - task.project = project (SwiftData relationship)
   - task.calendarEvent = correspondingEvent (if scheduled)

2. For each calendarEvent:
   - calendarEvent.project = project
   - calendarEvent.task = correspondingTask

3. Update project:
   - project.tasks = [all created tasks]

4. Update company:
   - company.projects.append(project)
   - company.tasks.append(contentsOf: tasks)
   - company.calendarEvents.append(contentsOf: events)

5. Save SwiftData context
```

**Step 5: Mark as Synced**
```swift
project.needsSync = false
project.lastSyncedAt = Date()

For each task:
    task.needsSync = false
    task.lastSyncedAt = Date()

For each calendarEvent:
    calendarEvent.needsSync = false
    calendarEvent.lastSyncedAt = Date()

Save context
```

#### 7.9.2 Implement Offline Creation Flow
When user taps "CREATE PROJECT" with NO internet connection:

**Step 1: Create All Entities Locally**
```swift
1. Create project in SwiftData (no bubbleId yet)
2. Set project.needsSync = true
3. Set project.syncPriority = 1 (highest)

For each task:
    1. Create task in SwiftData (no bubbleId yet)
    2. Set task.projectId = project.id (local ID)
    3. Set task.needsSync = true
    4. Set task.syncPriority = 1

For each scheduled task:
    1. Create calendarEvent in SwiftData (no bubbleId yet)
    2. Set calendarEvent.projectId = project.id (local ID)
    3. Set calendarEvent.taskId = task.id (local ID)
    4. Set calendarEvent.needsSync = true
    5. Set calendarEvent.syncPriority = 1
```

**Step 2: Link Relationships Locally**
```swift
Same as Step 4 in online flow, but using local IDs
```

**Step 3: Queue for Later Sync**
```swift
1. Add to sync queue with dependencies noted
2. Project must sync before tasks
3. Tasks must sync before calendar events
```

#### 7.9.3 Implement Background Sync Completion (CRITICAL)
When `CentralizedSyncManager.syncAll()` or `syncBackgroundRefresh()` runs:

**For Pending Projects**:
```swift
1. Identify projects with needsSync = true and no Bubble ID
2. Create on Bubble, get bubbleProjectId
3. Update local project.id with bubbleProjectId (OR keep local ID and store external ID separately)
4. Find all tasks with projectId = oldLocalProjectId
5. Update task.projectId = bubbleProjectId
```

**For Pending Tasks**:
```swift
1. Verify parent project exists and is synced
2. If parent project not synced yet, defer task sync
3. Create task on Bubble with correct projectId
4. Get bubbleTaskId
5. Update local task
6. Find all calendarEvents with taskId = oldLocalTaskId
7. Update calendarEvent.taskId = bubbleTaskId
```

**For Pending Calendar Events**:
```swift
1. Verify parent project and task exist and are synced
2. If dependencies not synced, defer event sync
3. Create event on Bubble with correct projectId and taskId
4. Get bubbleCalendarEventId
5. Update local calendarEvent
6. Link to task: task.calendarEvent = event
```

**Critical**: After syncing, re-link all relationships using the new Bubble IDs

#### 7.9.4 Add Loading UI During Creation
- When "CREATE PROJECT" is tapped:
  1. Immediately dismiss ProjectFormSheet
  2. Show `PushInMessage` with loading indicator
  3. Message: "UPLOADING PROJECT..."
  4. Show progress if possible (e.g., "Creating tasks 2/5...")
  5. On success: "PROJECT CREATED"
  6. On error: "ERROR CREATING PROJECT - TAP TO RETRY"

- Use our reusable `PushInMessage` component
- Add retry mechanism if creation fails
- Log all errors with full context for debugging

#### 7.9.5 Add Comprehensive Error Handling
```swift
do {
    // Create project
    let project = try await createProject()

    // Create tasks
    var createdTasks: [ProjectTask] = []
    for taskData in taskDataArray {
        let task = try await createTask(projectId: project.id, data: taskData)
        createdTasks.append(task)
    }

    // Create calendar events
    for task in createdTasks where task.hasSchedule {
        let event = try await createCalendarEvent(projectId: project.id, taskId: task.id)
        task.calendarEvent = event
    }

    // Link everything
    linkRelationships(project: project, tasks: createdTasks)

    // Show success
    showSuccess("PROJECT CREATED")

} catch {
    // Log error
    print("❌ Error creating project: \(error)")

    // Show error to user
    showError("Failed to create project: \(error.localizedDescription)")

    // Offer retry
    showRetryOption()
}
```

#### 7.9.6 Add Debug Logging
Add comprehensive logging throughout creation flow:
```swift
print("📋 [CREATE_PROJECT] Starting project creation: \(projectName)")
print("📋 [CREATE_PROJECT] Project created with ID: \(projectId)")
print("📋 [CREATE_PROJECT] Creating \(tasks.count) tasks...")
print("📋 [CREATE_PROJECT] Task created: \(taskId) for project: \(projectId)")
print("📋 [CREATE_PROJECT] Creating calendar events...")
print("📋 [CREATE_PROJECT] Calendar event created: \(eventId) for task: \(taskId)")
print("📋 [CREATE_PROJECT] Linking relationships...")
print("📋 [CREATE_PROJECT] ✅ Project creation complete")
```

Enable/disable with debug flag in `CentralizedSyncManager.DebugFlags`

---

## 8. CREATE TASK SHEET REDESIGN

### 8.1 Overall Structure Redesign
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Current Structure**: Likely uses collapsing sections similar to old project sheet

**New Requirements**: Match Create Project Sheet structure WITHOUT expanding/collapsing sections
- Remove all collapsible section logic
- Remove pill buttons (DETAILS, TEAM, etc.)
- Place all fields in a single section styled like a section from Create Project Sheet
- Use same input field styling as updated ProjectFormSheet

### 8.2 Add Live Preview Task Card
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`
- the live preview should look like the Universal Job Card for Tasks

**Requirements**:

#### 8.2.1 Create Preview Card Component
- Position: Top of sheet, above all form fields
- Update in real-time as user fills form
- Use Universal Job Board Card layout. 

#### 8.2.2 Preview Card Styling
- Match Universal Job Card for Task


#### 8.2.3 Live Update Binding
Preview card should update when user changes:
- Task type (updates color bar and type name)
- Status (updates status badge)
- Project selection (updates project name displayed)
- Date selection (updates date display)
- Team selection (updates team avatars)

### 8.3 Remove Custom Title Section
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Requirement**: Remove any "Custom Title" or "Task Title" input field
- Tasks use task type name as display title
- No custom titles needed
- Remove state variable and UI for custom title

### 8.4 Task Type Selection - Make Dropdown Picker
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Current State**: Possibly a button that opens a sheet, or a menu button

**New Requirements**:

#### 8.4.1 Dropdown Picker Style
- Use SwiftUI `Menu` or `Picker` depending on consistency with ProjectFormSheet pickers
- Display: Shows currently selected task type name
- Tap behavior: Opens dropdown list inline (not sheet modal)
- List items:
  - Show task type color dot (12pt circle) before name
  - Task type name in uppercase
  - Checkmark next to selected type
  - Default types: QUOTE, WORK, SERVICE CALL, INSPECTION, FOLLOW UP
  - Custom company types if any exist

#### 8.4.2 Remove Colored Icon Next to Task Type
- Current: Likely shows task type icon with color
- New: Remove icon, use colored LEFT BORDER instead
- Border: 4pt width vertical bar on left edge of picker button
- Border color: Selected task type's color
- This matches the preview card and maintains consistency

#### 8.4.3 Picker Styling
- Make the picker look like the other inputs. no background color. grey borders that are primaryAccent when the input is focused.

**Layout**:
```
[Color Bar]  TASK TYPE NAME                          ⌄
```

### 8.5 Team Selection - Make Dropdown Picker
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Current State**: Possibly opens a separate sheet for multi-select

**New Requirements**:

#### 8.5.1 Dropdown Picker Style
Option A: If single-select is acceptable:
- Use `Menu` or `Picker` with team member list
- Show selected team member(s) with avatar(s)
- Tap to open dropdown

Option B: If multi-select is required (RECOMMENDED):
- Button that opens an inline multi-select list or sheet
- Display selected team members as `UserAvatar` components
- Up to 3 avatars visible, "+N" if more
- Tap to open team selection interface

#### 8.5.2 Team Display in Picker Button
- Show `UserAvatar` components for selected members
- Avatar size: 24pt diameter
- Overlapping style: `.spacing(-8)`
- Max 3 visible, "+N" for additional
- If no team selected: Show placeholder "Select team members"

#### 8.5.3 Styling
- Same styling as task type picker (8.4.3)
- No colored left border for team picker
- Height: same as other inputs

### 8.6 Single Section Layout
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Requirements**: Place all fields in one section with consistent styling matching Create Project Sheet sections. Give each input a title.

#### 8.6.1 Section Headers
- Format: "TASK DETAILS", "SCHEDULING", "TEAM" (uppercase)
- Font: `OPSStyle.Typography.captionBold`
- Color: `OPSStyle.Colors.secondaryText`

#### 8.6.2 Field Spacing
- Vertical spacing between fields within section: 16pt
- Consistent padding for all input fields: `.padding(.vertical, 12).padding(.horizontal, 16)`
- All fields use same border styling: `Color.white.opacity(0.15)`

### 8.7 Navigation Bar Title Font Fix
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Issue**: Navigation bar title doesn't use OPSStyle font

**Requirements**:
- Title text: "CREATE TASK" or "EDIT TASK" (uppercase)
- Font: `OPSStyle.Typography.bodyBold`
- Color: `OPSStyle.Colors.primaryText`
- Use `.toolbar` with `.principal` placement

**Implementation**:
```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        Text("CREATE TASK")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    ToolbarItem(placement: .navigationBarLeading) {
        Button("CANCEL") {
            dismiss()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    ToolbarItem(placement: .navigationBarTrailing) {
        Button("CREATE") {
            createTask()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
    }
}
```

### 8.8 Project Selection Field
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Requirements**:
- If task is standalone (not created from project context): Show project search/selection
- If task is created from ProjectFormSheet or ProjectDetailsView: Pre-populate and lock project field
- Search functionality: Use existing project search logic
- Display: Show project name and status badge
- Styling: Match other input fields

### 8.9 Notes Field
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

**Requirements**:
- Use `TextEditor` for multi-line support
- Min height: 80pt
- Max height: 200pt (scrollable beyond)
- Background: `Color.clear`
- Border: `Color.white.opacity(0.15)`, 1pt width
- `.scrollContentBackground(.hidden)` to maintain styling
- Placeholder: "Add notes..." (shown when empty using ZStack overlay)

---

## 9. CREATE CLIENT SHEET REDESIGN

### 9.1 Overall Structure Redesign
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Current Structure**: Uses separate sections with different styling

**New Requirements**: Match Create Project Sheet and Create Task Sheet structure
- Remove all collapsible section logic if present
- Remove pill buttons if any exist
- Place all fields in a single scrollable form
- Use section headers with `OPSStyle.Typography.captionBold` and `OPSStyle.Colors.secondaryText`
- Maintain consistent spacing: 24pt between sections
- Use same input field styling as updated ProjectFormSheet and TaskFormSheet

### 9.2 Import From Contacts Button Styling Update
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Issue**: "Import From Contacts" button should match 'Copy from project button' in Create Project Sheet

### 9.3 Single Section Layout
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**: Place all fields in one section, styled like the sections in create project sheet

**Section Structure**:
```
CLIENT PREVIEW CARD
(spacing: 24pt)

AVATAR INPUT

CLIENT DETAILS
- Client Name (text field)
- Import from contacts button (de-emphasized)
- Email (text field)
- Phone (text field)
- Address (text field with autocomplete)
- Notes (TextEditor)

(bottom spacing: 24pt)
```

#### 9.3.1 Section Headers
- just one section header required
- but have title over each input

#### 9.3.2 Field Styling
- All input fields use consistent styling:
  - Background: `Color.clear`
  - Border: `.overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))`
  - Padding: `.padding(.vertical, 12).padding(.horizontal, 16)`
  - Min height: 44pt (touch target)
- Vertical spacing between fields: 16pt

#### 9.3.3 Input Fields
**Client Name**:
- Placeholder: "Client name"
- Required field
- Auto-capitalize words
- Font: `OPSStyle.Typography.body`

**Email**:
- Placeholder: "Email Address"
- Keyboard type: `.emailAddress`
- Auto-capitalize: none
- Autocorrect: disabled
- Font: `OPSStyle.Typography.body`

**Phone**:
- Placeholder: "Phone Number"
- Keyboard type: `.phonePad`
- Font: `OPSStyle.Typography.body`
- Optional formatting as user types

**Address**:
- Use existing address autocomplete component
- Placeholder: "Start typing address..."
- Show suggestions dropdown
- Font: `OPSStyle.Typography.body`
- make sure this is formatted to match other input (no background color, same border color as others, border color is primaryAccent when focused)

**Notes**:
- Use `TextEditor` for multi-line support
- Min height: 80pt
- Max height: 200pt (scrollable beyond)
- Background: `Color.clear`
- Border: `Color.white.opacity(0.15)`, 1pt width
- `.scrollContentBackground(.hidden)`
- Placeholder: "Add notes..." (shown when empty using ZStack overlay)
- make sure you add a minimalist save and cancel button that become visible when the user is typing (this applies to notes and description sections in create project and create task views as well)

### 9.4 Add Client Avatar Uploader ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**: Add avatar upload capability for client profile picture

#### 9.4.1 Create Avatar Upload Section
**Position**: At top of form, within CLIENT DETAILS section, or as separate AVATAR section

**Component to Use**: Reuse existing uploader element (likely `ProfileImageUploader.swift` or `ImagePicker.swift`)

**Layout**:
```
[Avatar Circle]  TAP TO ADD PHOTO
                 or
                 CHANGE PHOTO (if image exists)
```

#### 9.4.2 Avatar Upload Functionality
- Tap circle to open image picker
- Options:
  - Take Photo (camera)
  - Choose from Photos (library)
  - Remove Photo (if exists)
- Image handling:
  - Crop to square
  - Resize to 512x512 or similar
  - Upload to S3 (if online) or queue for later (if offline)
  - Store URL in `client.profileImageURL`
  - Cache locally for immediate display
- Show upload progress indicator
- Show success/error states

#### 9.4.3 Avatar Upload Styling
- Circle size: 80pt diameter (larger than user avatars since it's the focus)
- Border: `Color.white.opacity(0.2)`, 2pt width
- Background (if no image): `OPSStyle.Colors.cardBackgroundDark`
- Placeholder icon (if no image): "building.2" or "person.crop.circle" SF Symbol in `OPSStyle.Colors.tertiaryText`
- Upload button styling:
  - Text: "TAP TO ADD PHOTO" or "CHANGE PHOTO"
  - Font: `OPSStyle.Typography.caption`
  - Color: `OPSStyle.Colors.secondaryText`
  - Position: Below or beside avatar circle

**Implementation Approach**:
```swift
@State private var clientImage: UIImage?
@State private var showImagePicker = false
@State private var imageSource: ImagePicker.SourceType = .photoLibrary

// Avatar section
VStack(spacing: 12) {
    // Avatar circle
    Button(action: { showImagePicker = true }) {
        if let image = clientImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
        } else {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "building.2")
                        .font(.system(size: 32))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                )
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
        }
    }

    // Upload text
    Text(clientImage == nil ? "TAP TO ADD PHOTO" : "CHANGE PHOTO")
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.secondaryText)
}
.sheet(isPresented: $showImagePicker) {
    ImagePicker(image: $clientImage, sourceType: imageSource)
}
```

### 9.5 Update Client Preview Card ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Current State**: Based on recent commit a7f20a0, preview card exists at top of form (lines 79, 435-495)

**Requirements**: Add UserAvatar element to preview card

#### 9.5.1 Preview Card Layout Update
**Current Layout** (likely):
```
┌─────────────────────────────────┐
│ PREVIEW                         │
│                                 │
│ Client Name                     │
│ email@example.com               │
│ (555) 123-4567                  │
│ 123 Main St, City, State        │
└─────────────────────────────────┘
```

**New Layout**:
```
┌─────────────────────────────────┐
│ PREVIEW                         │
│                                 │
│ Client Name            [Avatar] │
│ email@example.com               │
│ (555) 123-4567                  │
│ 123 Main St, City, State        │
└─────────────────────────────────┘
```

#### 9.5.2 UserAvatar Integration
**Component**: Use existing `UserAvatar` component
**File**: `OPS/Views/Components/User/UserAvatar.swift` (verify exists)

**Requirements**:
- Position: Right side of preview card, aligned with client name
- Size: 48pt diameter (medium size for preview)
- Image source: `clientImage` or `client.profileImageURL`
- Fallback: If no image available, UserAvatar shows default avatar
  - Default avatar: Building icon or initials from client name
  - Background: `OPSStyle.Colors.primaryAccent`
  - Text/Icon: White

**UserAvatar Properties**:
- `imageURL: String?` - Client's profile image URL
- `initials: String?` - First letter of client name (e.g., "A" for "ABC Company")
- `size: CGFloat` - 48pt for preview card
- `showDefaultAvatar: Bool` - true (always show something)
- `defaultIcon: String?` - "building.2" for clients (instead of person icon)

#### 9.5.3 Live Update Preview Avatar
- Preview avatar should update in real-time when:
  - User selects image via avatar uploader
  - User changes client name (updates initials)
  - User imports from contacts (loads contact photo if available)
- Avatar opacity: 0.7 (same as preview card to indicate preview state)

**Implementation**:
```swift
// In preview card view
HStack(alignment: .top) {
    VStack(alignment: .leading, spacing: 8) {
        Text(clientName.isEmpty ? "Client Name" : clientName)
            .font(OPSStyle.Typography.title)
            .foregroundColor(OPSStyle.Colors.primaryText)

        if !email.isEmpty {
            Text(email)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        if !phone.isEmpty {
            Text(phone)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        if !address.isEmpty {
            Text(address)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    Spacer()

    // Avatar on right side
    UserAvatar(
        imageURL: clientImageURL,
        initials: String(clientName.prefix(1)),
        size: 48,
        showDefaultAvatar: true,
        defaultIcon: "building.2"
    )
    .opacity(0.7) // Preview state
}
.padding(.vertical, 14)
.padding(.horizontal, 16)
```

### 9.6 Navigation Bar Title ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**: Ensure navigation bar uses OPSStyle font
- Title text: "CREATE CLIENT" or "EDIT CLIENT" (uppercase)
- Font: `OPSStyle.Typography.bodyBold`
- Color: `OPSStyle.Colors.primaryText`
- Use `.toolbar` with `.principal` placement

**Implementation**:
```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        Text(isEditMode ? "EDIT CLIENT" : "CREATE CLIENT")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    ToolbarItem(placement: .navigationBarLeading) {
        Button("CANCEL") {
            dismiss()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    ToolbarItem(placement: .navigationBarTrailing) {
        Button(isEditMode ? "SAVE" : "CREATE") {
            saveClient()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
        .disabled(clientName.isEmpty) // Require name
    }
}
```

### 9.7 Form Validation ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**:
- Client name: Required (disable CREATE button if empty)
- Email: Optional, but validate format if provided
- Phone: Optional, but validate format if provided
- Address: Optional
- Notes: Optional

**Email Validation**:
```swift
var isValidEmail: Bool {
    if email.isEmpty { return true } // Optional field
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: email)
}
```

**Phone Validation**:
```swift
var isValidPhone: Bool {
    if phone.isEmpty { return true } // Optional field
    let phoneRegex = "^[0-9+\\s()\\-]{7,}$"
    let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
    return phonePredicate.evaluate(with: phone)
}
```

**Show validation errors**:
- If email invalid: Show red border and error text below field
- If phone invalid: Show red border and error text below field
- Validation should occur on blur or form submission attempt

### 9.8 Import From Contacts Integration ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**: Verify import from contacts functionality works correctly

**Current Implementation** (from commit a7f20a0):
- Button exists to import from contacts
- Should use CNContactPickerViewController
- Should NOT copy from existing clients (different from "copy from project")

**Import Behavior**:
1. User taps "Import from contacts"
2. iOS Contacts picker opens
3. User selects a contact
4. Populate form fields:
   - Name: Contact's organization name (if available) or full name
   - Email: Primary email address
   - Phone: Primary phone number
   - Address: Primary address (formatted)
   - Avatar: Contact's profile image (if available)
5. User can edit imported data before saving
6. Create button becomes active once name is populated

**Permissions**:
- Request Contacts permission if not already granted
- Handle permission denial gracefully with alert explaining why access is needed
- Provide option to open Settings if permission denied

### 9.9 Client Creation and Sync Flow ✅
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

**Requirements**: Similar to project creation flow (section 7.9), but simpler

#### 9.9.1 Online Client Creation
1. Validate form fields
2. Upload avatar image to S3 (if provided)
3. Create client DTO with image URL
4. Call `APIService.createClient(dto:)`
5. Wait for response with bubbleClientId
6. Update local client with bubbleClientId
7. Mark as synced: `client.needsSync = false`, `client.lastSyncedAt = Date()`
8. Save to SwiftData
9. Add to company.clients array
10. Dismiss sheet
11. Show success notification: "CLIENT CREATED"

#### 9.9.2 Offline Client Creation
1. Create client locally with local ID
2. Store avatar image locally (ImageFileManager)
3. Set `client.needsSync = true`, `client.syncPriority = 2`
4. Save to SwiftData
5. Queue avatar upload for later
6. Dismiss sheet
7. Show notification: "CLIENT SAVED (WILL SYNC WHEN ONLINE)"

#### 9.9.3 Background Sync
- When sync runs and finds client with `needsSync = true`:
  1. Upload avatar if not uploaded yet
  2. Create client on Bubble
  3. Update local client with bubbleClientId
  4. Mark as synced
  5. Save changes

---

## IMPLEMENTATION PRIORITIES

### Priority 1 (Critical - Blocking Issues)
1. **7.9** - Project/Task/CalendarEvent creation and linking fix
2. **2.1, 2.2** - Job board scrolling fix
3. **3.1** - Change team functionality fix

### Priority 2 (High - User-Facing Issues)
1. **6.1** - Manual sync notification enhancements
2. **7.1, 7.2, 7.3** - Task line item updates in ProjectFormSheet
3. **8.1-8.9** - Create Task Sheet redesign
4. **9.1-9.9** - Create Client Sheet redesign
5. **5.1** - Push In notification top padding fix

### Priority 3 (Medium - Polish)
1. **7.4** - Notes/Description save/cancel buttons
2. **7.5** - Copy From Project button styling
3. **7.6** - Pill and section border color
4. **7.7** - Remove divider
5. **7.8** - Remove dates pill
6. **9.2** - Import From Contacts button styling
7. **1.1** - Loading screen padding

### Priority 4 (Low - Nice to Have)
1. **4.1** - Replace custom sync notification with reusable component

---

## TESTING CHECKLIST

### Pre-Implementation Testing
- [ ] Verify current scrolling behavior on Job Board (projects and tasks)
- [ ] Test current address autocomplete functionality
- [ ] Document current "Change Team" behavior
- [ ] Test project creation with tasks (verify current broken state)

### Post-Implementation Testing
- [ ] Job Board scrolling works with 30+ items
- [ ] Change Team opens task selection menu correctly
- [ ] PushInMessage appears below camera cutout on iPhone 16
- [ ] Manual sync shows "[ X NEW PROJECTS LOADED ]"
- [ ] Project with tasks creates successfully with all relationships linked
- [ ] Offline project creation queues properly and syncs on reconnect
- [ ] Address autocomplete suggests addresses as user types in Project and Client sheets
- [ ] Task line items display inline uppercase text
- [ ] Task line items use UserAvatar component
- [ ] Trash icon deletes task with confirmation
- [ ] Tap on task line item opens edit mode
- [ ] Create Task Sheet matches Create Project Sheet styling
- [ ] Create Task Sheet preview card updates in real-time
- [ ] Create Client Sheet matches Create Project and Task Sheet styling
- [ ] Client preview card shows UserAvatar on right side
- [ ] Client preview avatar updates when image selected or name changed
- [ ] Client avatar uploader works (camera and photo library)
- [ ] Import from Contacts populates client form correctly
- [ ] Import from Contacts loads contact photo into avatar
- [ ] Client creation works online (with avatar upload to S3)
- [ ] Client creation works offline (queued for sync)
- [ ] All dropdown pickers work consistently across all sheets
- [ ] Notes section save/cancel buttons function correctly
- [ ] All border colors are visible in bright conditions
- [ ] Form validation works correctly (email and phone formats)

### Device Testing
- [ ] iPhone SE (smallest screen)
- [ ] iPhone 14 (notch)
- [ ] iPhone 16 (Dynamic Island)
- [ ] iPhone 16 Pro Max (largest screen)

### Connection Testing
- [ ] Create project with tasks ONLINE - verify immediate creation
- [ ] Create project with tasks OFFLINE - verify queued for sync
- [ ] Reconnect after offline creation - verify sync completes and links correctly

---

## NOTES

- All changes should adhere to OPS Design System (CLAUDE.md)
- Maintain 56pt touch targets for primary actions (field-friendly)
- Use OPSStyle constants for all colors, fonts, and spacing
- Test in bright outdoor conditions (field use case)
- Add comprehensive console logging for debugging
- Use haptic feedback for confirmations and status changes
- Ensure all changes work offline with proper sync queuing

---

**Created**: November 19, 2025
**Status**: Ready for Implementation
**Sections**: 9 major sections (60+ enumerated sub-tasks)
**Estimated Complexity**: High (particularly sections 7.9 and 9.9 - creation/sync flows)
**Estimated Time**: 3-4 development sessions

---

## TESTING RESULTS - November 19, 2025

### 1. Loading Screen Padding Fix
**Status**: ❌ Needs More Work
**Issue**: Needs more padding - add 24pt to the bottom
**File**: `OPS/Views/LoginView.swift` or `OPS/Views/SplashLoadingView.swift`

### 2. Job Board Scrolling Fix
**Status**: ❌ Still Broken
**Issue**: Still does not register scrolling. This issue arose when we tried to fix scroll gesture being incorrectly registered as a tap gesture.
**Files**: `OPS/Views/JobBoard/JobBoardProjectListView.swift`, `OPS/Views/JobBoard/JobBoardView.swift`

### 3. Change Team Functionality
**Status**: ✅ Works Well
**Notes**: No issues found

### 4. Sync Restored Notification
**Status**: ❌ Not Working
**Issue**: There is only the 'syncing' badge upon reconnection. No push in notification.
**File**: `OPS/ContentView.swift`

### 5. Push In Notification Top Padding
**Status**: ❌ Still Blocked
**Issue**: Still blocked by camera area. Make sure you are adding top padding.
**File**: `OPS/Views/Components/Common/PushInMessage.swift`

### 6. Manual Sync Notification
**Status**: ⚠️ Mostly Correct
**Issue**: Remove the X button. The notification auto dismisses.
**File**: `OPS/Views/Components/Common/PushInMessage.swift`

### 7. Task Line Items (Create Project Sheet)
**Status**: ⚠️ Multiple Issues
**Issues**:
- There should be spacing between the line items
- Border is being cut off by the rounded corners
- **CRITICAL**: After editing the task, changes are not saved
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

