# TODO - November 16, 2025

### Task-Only Scheduling Migration
- [ ] **Fix fatal error when opening task list**
  - Issue: SwiftData couldn't sort by Project.startDate (computed property)
  - Solution: Removed SortDescriptor from FetchDescriptor, sort in-memory instead
  - Files: DataController.swift, ProjectsViewModel.swift

- [x] **Fix job card address layout**
  - Issue: Address overlapping date/team text, not constrained to 35% width
  - Solution: Added maxWidth constraint, removed fixedSize, proper shrinking behavior
  - File: UniversalJobBoardCard.swift:535-574
  - Also fixed: Ellipsis positioning (aligned to bottom baseline)

- [ ] **Delete scheduling type section from Settings**
  - Removed: NavigationLink to SchedulingTypeExplanationView
  - File: ProjectSettingsView.swift:84-94

### Job Board Enhancements
- [x] **Make Actions icon visible on all screens** ✅ *Completed: Nov 18, 2025*
  - Created reusable FloatingActionMenu component
  - Moved to MainTabView level to persist across tab changes
  - Role-based visibility: Office Crew and Admin only
  - Consistent position across all tabs (no rebuilding on tab change)
  - Files: FloatingActionMenu.swift, MainTabView.swift:147-149
  - Removed from individual views: HomeView.swift, ScheduleView.swift, JobBoardView.swift

- [x] **Fix false tap registration during vertical scrolling** ✅ *Completed: Nov 18, 2025*
  - Issue: Job board cards opened details when user scrolled vertically
  - Solution: Replaced onTapGesture with simultaneousGesture(DragGesture) that detects drag distance
  - Only triggers details view if drag distance < 10 points (distinguishes tap from scroll)
  - Applied to: Client cards, Project cards, and Task cards
  - File: UniversalJobBoardCard.swift:41,81-98,264-281,467-484

### Calendar Filter Improvements
- [x] **Improve client section with pagination** ✅ *Completed: Nov 18, 2025*
  - Client section now shows only 5 results at a time
  - Defaults to most recent 5 clients (sorted by createdAt)
  - Added "Show More" button to load 5 additional clients at a time
  - Search resets pagination back to 5 results
  - Added createdAt property to Client model
  - Updated ClientDTO to parse Created Date from Bubble API
  - Files: CalendarFilterView.swift:29,347-398,404-428, Client.swift:39,63, ClientDTO.swift:114-118

### Major Feature - Create Project Overhaul
- [ ] **Removed Quick/Extended toggle modes**
  - Deleted CreationMode enum and creationMode state
  - Removed mode toggle UI component
  - All fields now follow progressive disclosure pattern
  - File: ProjectFormSheet.swift

- [x] **Created OptionalSectionPill component**
  - Pill-styled buttons for collapsed optional sections
  - FlowLayout for automatic wrapping
  - Icons and labels for each section type
  - Files: OptionalSectionPill.swift (new)

- [ ] **Restructured form with mandatory and optional sections**
  - Mandatory fields (always visible): Client, Project Name, Job Status
  - Optional expandable sections: Site Address, Description, Notes, Task Type, Dates, Team Members, Photos
  - Address moved from mandatory to optional
  - Visual divider between mandatory and optional sections
  - File: ProjectFormSheet.swift

- [ ] **Added delete/clear functionality to optional sections**
  - Minus button (top right) on expanded sections
  - Clears section data and collapses section
  - Haptic feedback on delete
  - All sections support onDelete: address, description, notes, task type, dates, team, photos
  - File: ProjectFormSheet.swift, ExpandableSection component

- [x] **Built CopyFromProjectSheet component**
  - Searchable project list sorted by last sync date
  - Project cards show title, client, status badge, and address
  - Field selection checklist (only shows fields with data)
  - Overwrite warnings for populated fields
  - Multi-source copy support (can copy from multiple projects)
  - File: CopyFromProjectSheet.swift (new)

- [ ] **Integrated copy functionality**
  - "COPY FROM..." button in toolbar (create mode only)
  - Tracks populated fields for overwrite warnings
  - Auto-expands sections when copying data into them
  - Animated section expansion with spring animation
  - Haptic feedback on successful copy
  - File: ProjectFormSheet.swift:158-172,211-217,878-934

- [ ] **Implemented ADD TASKS feature**
  - Removed TASK TYPE pill (single task type selection)
  - Created ADD TASKS expandable section for multiple task creation
  - Tasks stored locally during project creation
  - Created SimpleTaskFormSheet for task type selection and custom titles
  - Task list shows all added tasks with edit/delete capability
  - Tasks created after project save with custom titles or task type display names
  - Updated createTask function to support custom task titles
  - Files: ProjectFormSheet.swift (localTasks state, tasksSection, SimpleTaskFormSheet component, createTask function)

## Completed ✅

### Bug Fixes
- [ ] **Fix haptic feedback simulator hangs**
  - Issue: UIImpactFeedbackGenerator and UINotificationFeedbackGenerator cause 8-second hangs in iOS Simulator
  - Error: `AVHapticClient.mm:1232 ... ERROR: Async XPC call for 'setupConnectionWithOptions:error:' (client ID 0x0) failed: Couldn't communicate with a helper application.`
  - Solution: Wrap all haptic feedback calls with `#if !targetEnvironment(simulator)` checks
  - Files fixed:
    - ProjectFormSheet.swift (7 instances)
    - CopyFromProjectSheet.swift (1 instance)
  - Note: 28 other files have haptic feedback and may need same fix if user encounters hangs elsewhere

- [x] **Fix task/calendar event immediate sync** ✅ *Completed: Nov 18, 2025*
  - Issue: Tasks and calendar events were marked for background sync instead of syncing immediately
  - Solution: Rewrote createTask function to sync immediately to Bubble, only set needsSync = true on failure
  - Verified linking: Task→Project, CalendarEvent→Task, CalendarEvent→Company all use PATCH requests
  - Files: ProjectFormSheet.swift:1256-1406

- [ ] **Remove deprecated project-level calendar events**
  - Issue: Old createCalendarEventForProject was still being called
  - Solution: Removed function and all calls - task-only scheduling is now enforced
  - File: ProjectFormSheet.swift

- [x] **Fix subscription security vulnerability** ✅ *Completed: Nov 18, 2025*
  - Issue: Companies with nil/invalid subscription data were granted access
  - Solution: Implemented comprehensive 5-layer validation in shouldLockoutUser()
    - Check for nil subscription status
    - Check for invalid subscription enum values
    - Check for invalid maxSeats (≤0)
    - Check if seated employees exceed maxSeats
    - For trial status, validate trial end date exists
  - File: SubscriptionManager.swift:183-250
  - Impact: Critical security fix - unauthorized access now properly blocked

- [ ] **Fix team members not assigned to project**
  - Issue: Team members not added to project.teamMembers during creation
  - Solution: Gather all unique team member IDs from all tasks and assign to project
  - Implementation: Set<String> collects unique IDs from localTasks, filter allTeamMembers, map to User objects
  - File: ProjectFormSheet.swift:1058-1078
  - Verified: Team members now correctly assigned from task assignments

## In Progress 🔄

## TODO 📋

## Notes

- Future feature ideas are tracked in [FUTURE.md](./FUTURE.md)
