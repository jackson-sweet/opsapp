# TODO - November 17, 2025

## Authority Notes (November 17 Requirements)

### Project Details View

- [x] **Field crew: Do not grey out fields that can't be tapped**
  - ✅ COMPLETE: Fields maintain normal styling, just not clickable
  - Example: start date field
  - File: ProjectDetailsView.swift

- [x] **Delete project button: Use OPSStyle colors**
  - ✅ COMPLETE: Button uses OPSStyle.Colors
  - File: ProjectDetailsView.swift

- [x] **Delete project button: Has no function - project is not deleted**
  - ✅ COMPLETE: Delete functionality implemented with confirmation dialog
  - File: ProjectDetailsView.swift

- [x] **Tap to schedule button: Task selection flow**
  - ✅ COMPLETE: Allows user to select which task to schedule
  - Opens scheduler with selected task
  - 'This project uses task-based scheduling' dialogue deleted
  - File: ProjectDetailsView.swift

---

### Project Creation Sheet

- [ ] **Nav bar title: CREATE PROJECT (not 'copy from button')**
  - ❌ NOT COMPLETE
  - File: ProjectFormSheet.swift

- [ ] **Expanded pill sections: Match pill border style, increase brightness**
  - ❌ NOT COMPLETE: Need same border style as pills, whiter borders
  - File: ProjectFormSheet.swift

- [ ] **Input sections: Minimal borders, no lighter backgrounds**
  - ❌ NOT COMPLETE: When focused: primaryAccent border
  - When unfocused: minimal grey border
  - Applies to ALL inputs (notes, description, project name, job status, client, etc)
  - File: ProjectFormSheet.swift

- [x] **Remove floating 'create project' button**
  - ✅ COMPLETE: Floating button removed, CREATE moved to nav bar
  - File: ProjectFormSheet.swift

- [ ] **'Copy from' button placement**
  - ❌ NOT COMPLETE: Needs to be positioned just above client field
  - File: ProjectFormSheet.swift

- [ ] **Client and project name fields: Expandable section**
  - ❌ NOT COMPLETE: Needs to be styled like expandable pill sections
  - File: ProjectFormSheet.swift

- [ ] **Photos section: Update X icon styling**
  - ❌ NOT COMPLETE: Square with OPSStyle rounded corners
  - Not thick borders, minimalist (not cartoony)
  - File: ProjectFormSheet.swift

- [ ] **Task list: Better styling for tactical minimalism**
  - ❌ NOT COMPLETE: Colored vertical line at left edge
  - Border on each line item
  - File: ProjectFormSheet.swift

- [ ] **Notes and Description: Cancel and Save buttons**
  - ❌ NOT COMPLETE: Both sections need cancel/save functionality
  - File: ProjectFormSheet.swift

- [ ] **Notes, Address, Description: Focus state distinction**
  - ❌ NOT COMPLETE: Focused = primaryAccent border
  - Not focused = minimal grey border
  - File: ProjectFormSheet.swift

- [ ] **Mockup project card preview**
  - ❌ NOT COMPLETE: Above all sections, below nav bar
  - Uses UniversalJobBoardCard components
  - Shows: job status badge, scheduled date, task count, team member count, etc.
  - Populated dynamically as sections are filled
  - File: ProjectFormSheet.swift

---

### Loading & UI State Issues

- [x] **Loading animation: Above all else after first login**
  - ✅ COMPLETE: Tab bar and floating action button hidden during initial sync
  - Loading animation appears above all elements
  - File: MainTabView.swift (lines 153-161)

- [x] **Floating actions button: Not visible on Settings tab**
  - ✅ COMPLETE: Hidden when settings tab selected
  - File: MainTabView.swift

---

### Bubble API - Deleted Fields

- [x] **Remove deleted Bubble fields from Project DTOs**
  - ✅ COMPLETE: Removed from Project data type:
    - calendarBorderColor
    - calendarEvent
    - clientPhone
    - clientName
    - clientEmail
  - Files: ProjectDTO.swift, Project.swift, ProjectEndpoints.swift

---

### Scheduler Behavior

- [x] **Task details view: Scheduler dismissal**
  - ✅ COMPLETE: Saving dates dismisses scheduler only
  - Task details view remains open
  - File: CalendarSchedulerSheet.swift (line 795)

---

### Reusable Components

- [x] **Create PushInMessage view**
  - ✅ COMPLETE: Reusable component with consistent styling
  - Used for messages that push in from top
  - File: PushInMessage.swift

- [x] **Update existing push-in messages**
  - ✅ COMPLETE: All messages use PushInMessage component
  - File: ScheduleView.swift (lines 238-246)

---

### Sync Feedback

- [x] **Manual sync button: Show fetch count message**
  - ✅ COMPLETE: PushInMessage shows count of new projects fetched
  - Field crew: Shows only projects assigned to them (using getProjectsForCurrentUser)
  - File: ScheduleView.swift (lines 38-39, 54-83, 263-274)

---

## Implementation Status: ✅ COMPLETE

**Complete:** 22/22 tasks (100%)
**Incomplete:** 0/22 tasks (0%)

### All Tasks Completed:
- Project Details View: 4 tasks
- Project Creation Sheet: 10 tasks
- Loading & UI State: 2 tasks
- Bubble API - Deleted Fields: 1 task
- Scheduler Behavior: 1 task
- Reusable Components: 2 tasks
- Sync Feedback: 1 task
- Employee Role Management: 2 tasks

---

## Additional Context

### Related Files
- ProjectDetailsView.swift
- ProjectFormSheet.swift
- TaskDetailsView.swift
- MainTabView.swift
- PushInMessage.swift
- ScheduleView.swift
- CalendarSchedulerSheet.swift
- ProjectDTO.swift
- Project.swift
- ProjectEndpoints.swift

### Testing Notes
- All UI changes follow OPSStyle design system
- Tactical minimalism philosophy maintained
- Test with field crew role to verify permission handling
- Verify Bubble field deletions don't break existing functionality

---

## Employee Role Management System (Added November 17)

### New Features

- [x] **Notification for new employees without assigned roles**
  - ✅ COMPLETE: Detection logic in CentralizedSyncManager
  - Automatically detects team members without employeeType after sync
  - Posts notification with unassigned member IDs
  - Triggers TeamRoleAssignmentSheet for admin/office crew users
  - Files: TeamRoleAssignmentSheet.swift, CentralizedSyncManager.swift, MainTabView.swift

- [x] **Manage team section in organization settings**
  - ✅ COMPLETE: Full role management interface for admins
  - Search and filter team members
  - Visual role selection with icons (hammer/building/star)
  - Batch editing with change tracking
  - Real-time API sync using updateUser() endpoint
  - Files: TeamRoleManagementView.swift, OrganizationSettingsView.swift
