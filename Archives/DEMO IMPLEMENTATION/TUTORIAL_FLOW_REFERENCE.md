# Tutorial Flow Reference

This document details every step in both tutorial flows, including the tooltip text, required user action, and implementation status.

**Status: IN DEVELOPMENT** - Employee flow being debugged.

**Last Updated:** December 30, 2024 - Employee Flow Debugging

---

## Company Creator Flow (~30 seconds)

For admin/office users who create and manage projects.

| Step | Phase | Tooltip Text | User Action | Trigger | Status |
|------|-------|--------------|-------------|---------|--------|
| 1 | `.jobBoardIntro` | "TAP THE + BUTTON" | Tap FAB (+) button | `TutorialFABTapped` | Done |
| 2 | `.fabTap` | "TAP \"CREATE PROJECT\"" | Tap "Create Project" in menu | `TutorialCreateProjectTapped` | Done |
| 3 | `.projectFormClient` | "SELECT A CLIENT" | Select client from dropdown | `TutorialClientSelected` | Done |
| 4 | `.projectFormName` | "ENTER A PROJECT NAME" | Type project name | `TutorialProjectNameEntered` | Done |
| 5 | `.projectFormAddTask` | "NOW ADD A TASK" | Tap "Add Task" button | `TutorialAddTaskTapped` | Done |
| 6 | `.taskFormType` | "SELECT A TASK TYPE" | Select task type | `TutorialTaskTypeSelected` | Done |
| 7 | `.taskFormCrew` | "ASSIGN A CREW MEMBER" | Select team member | `TutorialCrewAssigned` | Done |
| 8 | `.taskFormDate` | "SET THE DATE" | Confirm date in scheduler | `TutorialDateSet` | Done |
| 9 | `.taskFormDone` | "TAP \"DONE\"" | Save draft task | `TutorialTaskFormDone` | Done |
| 10 | `.projectFormComplete` | "TAP \"CREATE\"" | Tap Create button | `TutorialProjectFormComplete` | Done |
| 11 | `.dragToAccepted` | "PRESS AND HOLD, THEN DRAG RIGHT" | Drag project card | `TutorialDragToAccepted` | Done |
| 12 | `.projectListStatusDemo` | "WATCH THE STATUS UPDATE" | Watch animation | Auto-advances (status animation) | Done |
| 13 | `.projectListSwipe` | "SWIPE THE CARD RIGHT TO CLOSE" | Swipe project right | `TutorialProjectListSwipe` | Done |
| 14 | `.closedProjectsScroll` | "COMPLETE. SCROLL DOWN TO FIND IT." | View closed section | Auto-advances | Done |
| 15 | `.calendarWeek` | "THIS IS YOUR WEEK VIEW" | Scroll week view | `TutorialCalendarWeekScrolled` | Done |
| 16 | `.calendarMonthPrompt` | "TAP \"MONTH\"" | Tap "Month" toggle | `TutorialCalendarMonthTapped` | Done |
| 17 | `.calendarMonth` | "PINCH OUTWARD TO EXPAND" | Explore month view | Auto-advances after 2.0s | Done |
| 18 | `.tutorialSummary` | "THAT'S THE BASICS." | Tap to continue | User dismisses | Done |
| 19 | `.completed` | "YOU'RE READY." | — | Shows completion screen | Done |

**Note:** `.createProjectAction` phase is skipped - flow goes directly from `.fabTap` to `.projectFormClient`.

---

## Employee Flow (~25 seconds)

For field crew members who view and complete assigned work.

| Step | Phase | Tooltip Text | User Action | Trigger | Status |
|------|-------|--------------|-------------|---------|--------|
| 1 | `.homeOverview` | "THESE ARE YOUR JOBS FOR TODAY" | View home | Auto-advances after 1.5s | Done |
| 2 | `.tapProject` | "TAP A JOB CARD, THEN TAP START" | Tap card, then Start | `TutorialProjectTapped` | **Testing** |
| 3 | `.projectStarted` | "JOB STARTED." | Wait | Auto-advances after 1.5s | Pending |
| 4 | `.tapDetails` | "TAP \"DETAILS\" FOR MORE INFO" | Tap Details button | `TutorialDetailsTapped` | Pending |
| 5 | `.addNote` | "TAP TO ADD A NOTE" | Add a note | `TutorialNoteAdded` | Pending |
| 6 | `.addPhoto` | "TAP TO TAKE A PHOTO" | Add a photo | `TutorialPhotoAdded` | Pending |
| 7 | `.completeProject` | "TAP \"COMPLETE\" WHEN DONE" | Tap complete | `TutorialProjectCompleted` | Pending |
| 8 | `.jobBoardBrowse` | "SWIPE LEFT OR RIGHT" | Wait | Auto-advances after 2.0s | Pending |
| 9 | `.calendarWeek` | "THIS IS YOUR WEEK VIEW" | Scroll week view | `TutorialCalendarWeekScrolled` | Pending |
| 10 | `.calendarMonthPrompt` | "TAP \"MONTH\"" | Tap "Month" toggle | `TutorialCalendarMonthTapped` | Pending |
| 11 | `.calendarMonth` | "PINCH OUTWARD TO EXPAND" | Explore | `TutorialCalendarMonthExplored` | Pending |
| 12 | `.tutorialSummary` | "THAT'S THE BASICS." | Tap Done | User taps Done button | Pending |
| 13 | `.completed` | "YOU'RE READY." | — | Shows completion screen | Pending |

**Note:** Steps 9-12 now match the Company Creator flow (steps 15-18).

### Step 2 Dark Overlay Implementation

During `.tapProject` phase, a dark overlay (60% opacity) is displayed:
- **Behind**: The project card carousel
- **In front of**: Map, header, gradient, tab bar

This is achieved by restructuring the HomeContentView ZStack to place the carousel in a separate layer above the overlay.

### Step 4 Details Button

The "Details" button is on the ProjectActionBar that appears when in project mode. User taps it to open ProjectDetailsView where they can add notes/photos.

---

## Implementation Status Summary

### All Phases Fully Implemented

**Company Creator Flow (19 phases)**
- FAB tap and create project menu selection
- All project form phases (client, name, add task, complete)
- All task form phases (type, crew, date, done)
- Drag to accepted
- Status demo animation (auto-advances)
- Project list swipe to close
- Closed projects section (auto-advances)
- All calendar phases (week, month prompt, month)
- Tutorial summary

**Employee Flow (12 phases)**
- All auto-advancing phases
- Project tap and start
- Note and photo addition
- Project completion
- Job board browse
- All calendar phases

---

## Notification Names Reference

All notifications are posted via `NotificationCenter.default.post(name:object:)`:

```swift
// Company Creator Flow
"TutorialFABTapped"              // FAB (+) button tapped (opens menu)
"TutorialCreateProjectTapped"    // "Create Project" menu item tapped
"TutorialClientSelected"         // Client picker
"TutorialProjectNameEntered"     // Project name field
"TutorialAddTaskTapped"          // Add Task button
"TutorialTaskTypeSelected"       // Task type menu
"TutorialCrewAssigned"           // Team member picker
"TutorialDateSet"                // Calendar scheduler
"TutorialTaskFormDone"           // Save draft task
"TutorialProjectFormComplete"    // Complete project form
"TutorialDragToAccepted"         // Drag to Accepted column
"TutorialProjectListSwipe"       // Swipe to close project (via ProjectStatusChanged)
"TutorialCalendarWeekScrolled"   // Calendar week view scrolled
"TutorialCalendarMonthTapped"    // Month toggle tapped
"TutorialCalendarMonthExplored"  // Month view explored (scroll + pinch)

// Employee Flow
"TutorialProjectTapped"          // Home view project tap (via EventCarousel startTask)
"TutorialDetailsTapped"          // Details button tapped on ProjectActionBar
"TutorialNoteAdded"              // Note added
"TutorialPhotoAdded"             // Photo added
"TutorialProjectCompleted"       // Project completed

// Internal (posted by components, listened by wrapper)
"ProjectStatusChanged"           // Status changed via swipe (triggers TutorialProjectListSwipe)
```

---

## Continue Button Phases

These phases show a **"CONTINUE →" button** below the tooltip after a delay:

| Phase | Delay | Purpose |
|-------|-------|---------|
| `.homeOverview` | 1.5s | Let user see Home view UI |
| `.projectStarted` | 1.5s | Acknowledge project started |
| `.jobBoardBrowse` | 2.0s | Show browse hint |
| `.projectListStatusDemo` | 4.0s | Time for status animation |
| `.closedProjectsScroll` | 3.0s | Time to scroll and highlight |

**Behavior:** After the delay, a white "CONTINUE →" button fades in below the tooltip. User must tap it to proceed to the next step. This gives users control over pacing.

**Note:** `.jobBoardIntro` waits for user to tap the FAB button - it does not show Continue button.

---

## Testing Checklist

### Company Creator Flow
- [ ] Tutorial launches from onboarding
- [ ] FAB tap advances phase and opens menu
- [ ] "Create Project" tap advances phase and opens form
- [ ] Client selection advances phase
- [ ] Project name input advances phase
- [ ] Add Task button advances phase
- [ ] Task type selection advances phase
- [ ] Crew selection advances phase
- [ ] Date confirmation advances phase
- [ ] Task done advances phase and closes task form
- [ ] Project complete closes sheet and advances
- [ ] Drag to Accepted advances phase
- [ ] Status demo animation plays and auto-advances
- [ ] Project swipe closes project and advances
- [ ] Closed projects section shown, auto-advances
- [ ] Calendar week shown, scroll advances
- [ ] Month toggle advances phase
- [ ] Month view auto-advances after 2.0s
- [ ] Tutorial summary shown
- [ ] Completion screen shows

### Employee Flow
- [ ] Tutorial launches from onboarding
- [ ] Home overview auto-advances
- [ ] Project tap starts project and advances
- [ ] Project started auto-advances
- [ ] Long press hint auto-advances
- [ ] Add note advances phase
- [ ] Add photo advances phase
- [ ] Complete project advances phase
- [ ] Job board browse auto-advances
- [ ] Calendar phases work
- [ ] Completion screen shows

---

## Files Modified for Tutorial Integration

| File | Tutorial Notifications Added |
|------|------------------------------|
| `FloatingActionMenu.swift` | `TutorialFABTapped`, `TutorialCreateProjectTapped` |
| `HomeView.swift` | `TutorialProjectTapped` (fallback) |
| `EventCarousel.swift` | `TutorialProjectTapped` (primary - via startTask) |
| `ProjectActionBar.swift` | `TutorialDetailsTapped` |
| `HomeContentView.swift` | Dark overlay for `.tapProject` phase |
| `ProjectFormSheet.swift` | `TutorialClientSelected`, `TutorialProjectNameEntered`, `TutorialAddTaskTapped`, `TutorialProjectFormComplete` |
| `TaskFormSheet.swift` | `TutorialCrewAssigned`, `TutorialTaskTypeSelected`, `TutorialDateSet`, `TutorialTaskFormDone` |
| `ProjectDetailsView.swift` | `TutorialNoteAdded`, `TutorialPhotoAdded`, `TutorialProjectCompleted` |
| `JobBoardDashboard.swift` | `TutorialDragToAccepted` |
| `JobBoardProjectListView.swift` | `TutorialProjectListSwipe` (via `ProjectStatusChanged`), `TutorialClosedProjectsViewed` |
| `UniversalJobBoardCard.swift` | `ProjectStatusChanged` (on swipe status change) |
| `ScheduleView.swift` | `TutorialCalendarWeekScrolled`, `TutorialCalendarMonthTapped`, `TutorialCalendarMonthExplored` |
| `CalendarToggleView.swift` | Month button highlight overlay (Session 7) |
| `TutorialEnvironment.swift` | `TutorialPulseModifier` ViewModifier (Session 7) |
| `TutorialDemoDataManager.swift` | User-created project tracking (Session 7) |
| `TutorialLauncherView.swift` | Project cleanup listener (Session 7) |
| `TutorialCreatorFlowWrapper.swift` | `TutorialClosedProjectsViewed` listener (Session 7) |

---

## Key Implementation Notes

1. **Task Form Field Order**: The task form follows Type → Crew → Date order (not Crew → Type → Date as originally specified)

2. **Project Status Swipe**: When user swipes a project card to change status, `UniversalJobBoardCard` posts `ProjectStatusChanged`, which `JobBoardProjectListView` converts to `TutorialProjectListSwipe`

3. **Calendar Month Auto-Advance**: Added in Session 4 - `.calendarMonth` now auto-advances after 2.0s as a fallback (user can still manually advance via scroll+pinch)

4. **Demo Data Company ID**: Demo data uses the current user's company ID (not a hardcoded demo ID) to ensure calendar events appear correctly

5. **Tab Bar Animation**: When entering `.projectListStatusDemo`, the Job Board tab bar animates from "Dashboard" to "Projects" tab

6. **TutorialPulseModifier** (Session 7): Form field highlights use a dedicated ViewModifier that manages its own animation state. This ensures opacity-only pulsing without layout animation artifacts. Applied to all form field labels and borders in ProjectFormSheet and TaskFormSheet.

7. **Step 2 FAB Menu Blocking** (Session 7): During `.fabTap` phase, the FAB menu cannot be closed by tapping the dimmed background. User must tap "Create Project" to proceed. FAB button itself is visually greyed out (0.8 opacity) and non-interactive.

8. **Step 5 Add Tasks Pill** (Session 7): The "ADD TASKS" pill button is disabled (greyed out) until the tutorial reaches `.projectFormAddTask` phase. This prevents users from jumping ahead.

9. **Step 11 Illuminating Arrows** (Session 7): When dragging a project toward "Accepted", three chevron arrows progressively illuminate based on drag progress (25%, 50%, 75% thresholds). Each illumination triggers haptic feedback (light for arrows 1-2, medium for arrow 3). The accepted bar width grows proportionally.

10. **Step 13 Shimmer Effect** (Session 7): Project card shows blue (primaryAccent) shimmer gradient instead of white, with matching blue border. Spotlight highlight is disabled during this phase (card has its own visual feedback).

11. **Step 14 Scroll Animation** (Session 7): Uses ScrollViewReader inside the ScrollView to scroll to `closedProjectsSection` anchor. Auto-advances after 3.5 seconds.

12. **Step 17→18 View Persistence** (Session 7): `.tutorialSummary` phase merged into same switch case as calendar phases to prevent ScheduleView from being recreated (which would reset month view to week).

13. **User-Created Project Cleanup** (Session 7): Projects created during tutorial are tracked via `TutorialProjectFormComplete` notification and deleted on tutorial cleanup, even though they don't have `DEMO_` prefix.

14. **Copy V5 Update** (December 23, 2024): All tutorial copy updated per OPS_TUTORIAL_COPY_V5.md specification:
    - Cover screen: Title changed to "HERE'S HOW OPS WORKS", buttons to "START TUTORIAL" / "SKIP FOR NOW"
    - Tooltips: Shorter, more direct (e.g., "TAP THE + BUTTON" instead of "PRESS THE + BUTTON TO CREATE YOUR FIRST PROJECT")
    - Descriptions: Now explain WHY, not just WHAT (e.g., "These are sample clients. Pick any one—this is just for practice.")
    - Completion screen: Fast time threshold changed from 3 min to 2 min, left-aligned text, subtext with typewriter animation: "Now build your first real project and run your crew right."
