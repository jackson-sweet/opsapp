# Guided Tour - User Flows (CORRECTED)

**Status**: Research Complete
**Created**: January 23, 2025
**Updated**: November 24, 2025

---

## Complete Office/Admin Tour (90 seconds, 15 steps)

### Welcome Screen

**Element**: Full screen overlay
**Visual**: No spotlight (full screen)
**Message**:
```
Welcome to OPS!

Let's show you how to manage projects and coordinate with your team.

This tour takes about 90 seconds. You can skip anytime.

[Start Tour]  [Skip for Now]
```
**User Action**: Tap "Start Tour"
**Next Trigger**: User taps button
**Spotlight**: None (radial gradient not needed for full screen)
**Tags**: `onboarding, officeRole, adminRole`

---

### Step 1: Home Screen

**Element**: Entire home screen area
**Visual**: Radial gradient spotlight centered on screen
**Message**:
```
This is your command center.

See today's active projects and quickly jump to what needs attention.
```
**User Action**: None
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from dark to transparent, centered on home content
**Reference**: HomeContentView.swift, EventCarousel.swift
**Tags**: `home, navigation, onboarding, officeRole, adminRole`

---

### Step 2: Job Board Tab

**Element**: Job Board tab icon in tab bar
**Visual**: Radial gradient spotlight centered on tab icon
**Message**:
```
Tap here to see all your company's work.

The Job Board shows project list, task list, client list, and your dashboard—which functions as your shop's whiteboard with projects grouped by status.
```
**User Action**: Tap Job Board tab (or auto-navigate)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from dark to transparent, centered on tab icon
**Reference**: JobBoardView.swift, tabs: Dashboard, Clients, Projects, Tasks (line 198-202)
**Tags**: `jobBoard, navigation, onboarding, officeRole, adminRole`

---

### Step 3: Create Button

**Element**: Floating "+" button (bottom right)
**Visual**: Radial gradient spotlight centered on button
**Message**:
```
Tap the + button to create projects, clients, tasks, or task types.

We'll focus on creating a new project.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from dark to transparent, centered on floating button
**Reference**: Floating action button in main views
**Tags**: `projectManagement, onboarding, officeRole, adminRole`

---

### Step 4: Open Project Form

**Element**: ProjectFormSheet (now opened)
**Visual**: Radial gradient spotlight on entire form
**Action**: Tour actually opens ProjectFormSheet
**Message**:
```
This is where you create new projects.

Let's see how to quickly add a client.
```
**User Action**: None (tour opens the sheet)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from dark to transparent, centered on form
**Reference**: ProjectFormSheet.swift
**Tags**: `projectManagement, onboarding, officeRole, adminRole`

---

### Step 5: Client Search Field

**Element**: Client search TextField in PROJECT DETAILS section
**Visual**: Linear gradient spotlight from field outward
**Message**:
```
Start typing a client name here.

A dropdown will appear with matching clients or a "Create" button if no matches are found.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from TextField expanding outward
**Reference**: ProjectFormSheet.swift:397 - TextField("Search or create client...")
**Tags**: `clientManagement, projectManagement, onboarding, officeRole, adminRole`

---

### Step 6: Client Dropdown

**Element**: Dropdown area beneath TextField (simulated with text typed)
**Visual**: Linear gradient spotlight on dropdown area
**Message**:
```
When you type, this dropdown shows matching clients.

If no match exists, tap "Create [client name]" to open the client form where you can import contact info from your phone.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next", closes ProjectFormSheet
**Spotlight**: Linear gradient from dropdown expanding outward
**Reference**: ProjectFormSheet.swift:424-469 - dropdown appears when typing
**Note**: After this step, close ProjectFormSheet
**Tags**: `clientManagement, projectManagement, onboarding, officeRole, adminRole`

---

### Step 7: Calendar Tab

**Element**: Calendar tab icon in tab bar
**Visual**: Radial gradient spotlight centered on tab icon
**Message**:
```
Tap here to view your schedule.

Plan your week and see all upcoming job sites.
```
**User Action**: Tap Calendar tab (or auto-navigate)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from dark to transparent, centered on tab icon
**Reference**: ScheduleView.swift
**Tags**: `calendar, scheduling, navigation, onboarding, officeRole, adminRole`

---

### Step 8: Calendar View Toggle

**Element**: SegmentedControl with "Week" and "Month" options
**Visual**: Linear gradient spotlight on toggle control
**Message**:
```
Use this toggle to switch between Week and Month views.

Calendar opens in Week view by default.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from SegmentedControl expanding outward
**Reference**: CalendarToggleView.swift:19-34, SegmentedControl
**Tags**: `calendar, navigation, onboarding, officeRole, adminRole`

---

### Step 9: Week Swipe Gesture

**Element**: Weekday row (CalendarDaySelector)
**Visual**: Linear gradient spotlight on weekday row with animated swipe
**Message**:
```
Swipe left or right on the weekday row to cycle through weeks.

Navigate your schedule quickly with one gesture.
```
**User Action**: None (animated swipe demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from weekday row expanding outward
**Reference**: CalendarDaySelector.swift:55-82, DragGesture
**Gesture Animation**: Animated hand swiping left/right
**Tags**: `calendar, gestures, navigation, onboarding, officeRole, adminRole`

---

### Step 10: Switch to Month View

**Element**: Calendar in month view (switch view mode)
**Action**: Tour switches calendar to month view
**Visual**: Radial gradient spotlight on month grid
**Message**:
```
In Month view, you can see more days at once.

Let's look at a useful gesture for this view.
```
**User Action**: None (tour switches view)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from month grid center
**Reference**: MonthGridView.swift
**Tags**: `calendar, onboarding, officeRole, adminRole`

---

### Step 11: Month Pinch Gesture

**Element**: Calendar grid in month view
**Visual**: Radial gradient spotlight on grid with animated pinch
**Message**:
```
Pinch up or down on the calendar to adjust row height.

See more details or fit more days on screen.
```
**User Action**: None (animated pinch demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from grid center
**Reference**: MonthGridView.swift:484-491, MagnificationGesture
**Gesture Animation**: Animated pinch gesture (two fingers moving together/apart)
**Tags**: `calendar, gestures, onboarding, officeRole, adminRole`

---

### Step 12: Tap Project Card

**Element**: A project card in calendar (month or week view)
**Visual**: Linear gradient spotlight on project card
**Message**:
```
Tap any project to open project details.

See full information, tasks, team members, and updates.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from card expanding outward
**Reference**: Calendar project cards
**Tags**: `calendar, projectManagement, navigation, onboarding, officeRole, adminRole`

---

### Step 13: Calendar Search Button

**Element**: Magnifying glass icon button (top-right, circular, 44x44pt)
**Visual**: Radial gradient spotlight on search button
**Message**:
```
Tap to search for projects by name, client, address, or team member.

Quickly find any job in your schedule.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from button center
**Reference**: AppHeader.swift:188-193, magnifyingglass icon
**Tags**: `calendar, search, onboarding, officeRole, adminRole`

---

### Step 14: Calendar Sync Button

**Element**: Refresh button (arrow.clockwise icon, top-right, circular, 44x44pt)
**Visual**: Radial gradient spotlight on sync button
**Message**:
```
Tap this button to sync your latest projects from the server.

Keep your schedule up to date with the latest changes.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from button center
**Reference**: ScheduleView.swift:54-82, AppHeader.swift:174-185
**Tags**: `calendar, sync, onboarding, officeRole, adminRole`

---

### Step 15: Job Board - Navigate & Swipe Status

**Element**: Job Board Projects section, then a project card
**Action**: Navigate back to Job Board, switch to Projects tab
**Visual**: Linear gradient spotlight on project card with animated swipe
**Message**:
```
Within the Job Board, swipe left or right on any project card to change its status.

Quick status updates keep everyone in sync.
```
**User Action**: None (animated swipe demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from card with animated swipe overlay
**Reference**: UniversalJobBoardCard.swift:321-328, DragGesture with 5pt minimum
**Gesture Animation**: Animated hand swiping left/right on card
**Tags**: `jobBoard, statusUpdates, gestures, onboarding, officeRole, adminRole`

---

### Step 16: Settings Tab

**Element**: Settings tab icon in tab bar
**Visual**: Radial gradient spotlight on tab icon
**Message**:
```
Tap here to access your profile, organization settings, and help resources.
```
**User Action**: Tap Settings tab (or auto-navigate)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from tab icon center
**Reference**: SettingsView.swift
**Tags**: `settings, navigation, onboarding, officeRole, adminRole`

---

### Step 17: Settings Search Bar

**Element**: Search bar button ("Search settings...")
**Visual**: Linear gradient spotlight on search bar
**Message**:
```
Use this search bar to find specific settings or ask questions about using OPS.

Get help when you need it.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from search bar expanding outward
**Reference**: SettingsView.swift:343-362, search button
**Tags**: `settings, search, onboarding, officeRole, adminRole`

---

### Completion Screen

**Element**: Full screen overlay
**Visual**: No spotlight (full screen)
**Message**:
```
You're all set!

You can retake this tour anytime from Settings → Help.

[Get Started]
```
**User Action**: Tap "Get Started"
**Next Trigger**: Tour ends, return to app
**Spotlight**: None
**Tags**: `onboarding, officeRole, adminRole`

---

## Complete Field Crew Tour (45 seconds, 9 steps)

### Welcome Screen

**Element**: Full screen overlay
**Visual**: No spotlight (full screen)
**Message**:
```
Welcome to OPS!

Let's show you how to view your assignments and update your progress.

This tour takes about 45 seconds. You can skip anytime.

[Start Tour]  [Skip for Now]
```
**User Action**: Tap "Start Tour"
**Next Trigger**: User taps button
**Spotlight**: None
**Tags**: `onboarding, fieldRole`

---

### Step 1: Home Screen

**Element**: Event carousel area
**Visual**: Radial gradient spotlight on carousel
**Message**:
```
This is where you'll start each day.

See all your assigned tasks and what's coming up.
```
**User Action**: None
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from carousel center
**Reference**: HomeContentView.swift, EventCarousel.swift
**Note**: Mock data visible (3 sample projects scheduled today/tomorrow/+2 days)
**Tags**: `home, navigation, onboarding, fieldRole`

---

### Step 2: Tap Task Card for START

**Element**: Event card in carousel (using mock "Deck Installation" project)
**Visual**: Linear gradient spotlight on card with tap animation
**Message**:
```
Tap any task card once to show the START button.

Tap START to begin the task and activate navigation to the job site.
```
**User Action**: None (animated tap demonstration showing confirmation overlay)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from card, then radial on confirmation overlay
**Reference**: EventCarousel.swift:285-288 (onTapGesture), 317-340 (confirmation overlay)
**Animation**: Show tap → confirmation overlay appears with "START TASK" text
**Tags**: `home, taskManagement, navigation, onboarding, fieldRole`

---

### Step 3: Long Press for Task Details

**Element**: Same event card
**Visual**: Linear gradient spotlight with long press animation
**Message**:
```
Press and hold a task card for 0.6 seconds to open full task details.

See location, materials needed, notes, and team members.
```
**User Action**: None (animated long press demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from card with pulsing animation
**Reference**: EventCarousel.swift:289-314, LongPressGesture (0.6s duration)
**Gesture Animation**: Animated hand pressing and holding, then TaskDetailsView preview appears
**Tags**: `home, taskManagement, navigation, onboarding, fieldRole`

---

### Step 4: Job Board Tab

**Element**: Job Board tab icon in tab bar
**Visual**: Radial gradient spotlight on tab icon
**Message**:
```
Tap here to see all your assigned projects.

View project cards with status and details.
```
**User Action**: Tap Job Board tab (or auto-navigate)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient from tab icon center
**Reference**: JobBoardView.swift (field crew see Dashboard only, Projects tab for assigned projects)
**Tags**: `jobBoard, navigation, onboarding, fieldRole`

---

### Step 5: Swipe Project Card

**Element**: Project card in Job Board (using mock project)
**Visual**: Linear gradient spotlight with animated swipe
**Message**:
```
Swipe left or right on any project card to quickly change project status.

Or tap the project card to see full project details.
```
**User Action**: None (animated swipe demonstration)
**Next Trigger**: User taps "Next"
**Spotlight**: Linear gradient from card with swipe animation overlay
**Reference**: UniversalJobBoardCard.swift:321-328, DragGesture with 5pt minimum
**Gesture Animation**: Animated hand swiping left/right, revealed status card appears
**Tags**: `jobBoard, statusUpdates, gestures, onboarding, fieldRole`

---

### Step 6: Tap Project → Navigate to Task

**Element**: Project card, then ProjectDetailsView, then task in task list
**Action**: Tour taps project card to open ProjectDetailsView
**Visual**: Linear gradient spotlight on task row in task list
**Message**:
```
Scroll to the task list and tap any task to update its status.
```
**User Action**: None (tour navigates)
**Next Trigger**: User taps "Next", tour taps task to open TaskDetailsView
**Spotlight**: Linear gradient from task row expanding outward
**Reference**: ProjectDetailsView.swift:1433 (TaskListView), TaskListView.swift:108-121 (onTap)
**Tags**: `taskManagement, navigation, onboarding, fieldRole`

---

### Step 7: Update Task Status

**Element**: "Update Status" section at bottom of TaskDetailsView
**Visual**: Linear gradient spotlight on status section
**Message**:
```
Tap the status you want to update to.

Mark tasks as in progress, completed, or on hold to keep everyone informed.
```
**User Action**: None (demonstration)
**Next Trigger**: User taps "Next", closes TaskDetailsView and ProjectDetailsView
**Spotlight**: Linear gradient from status section expanding outward
**Reference**: TaskDetailsView.swift:496-555, status list with circle indicators
**Tags**: `taskManagement, statusUpdates, onboarding, fieldRole`

---

### Step 8: Calendar & Search

**Element**: Calendar tab icon, then search button
**Action**: Navigate to Calendar
**Visual**: Radial spotlight on tab, then search button
**Message**:
```
Use Calendar to see your full schedule and Search to quickly find any job you're assigned to.
```
**User Action**: None (tour briefly shows both)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient on tab, then on search button
**Reference**: ScheduleView.swift, AppHeader.swift:188-193 (search button)
**Tags**: `calendar, search, navigation, onboarding, fieldRole`

---

### Step 9: Settings Tab

**Element**: Settings tab icon, then search bar
**Action**: Navigate to Settings
**Visual**: Radial spotlight on tab, then search bar
**Message**:
```
Access Settings for help resources and search for tips or specific settings.
```
**User Action**: None (tour shows both)
**Next Trigger**: User taps "Next"
**Spotlight**: Radial gradient on tab, then linear on search bar
**Reference**: SettingsView.swift:343-362
**Tags**: `settings, search, navigation, onboarding, fieldRole`

---

### Completion Screen

**Element**: Full screen overlay
**Visual**: No spotlight (full screen)
**Message**:
```
You're ready to go!

Jump in and we'll help you along the way.

[Get Started]
```
**User Action**: Tap "Get Started"
**Next Trigger**: Tour ends, return to app
**Spotlight**: None
**Tags**: `onboarding, fieldRole`

---

## Implementation Notes

### Spotlight Implementation (from TECHNICAL_SPEC.md)
- **Radial Gradient**: For circular/point elements (buttons, icons, tab bar items)
  - Dark (overlay color) at edges → Transparent at center of element
  - Padding: 8pt around element
- **Linear Gradient**: For rectangular elements (cards, rows, text fields)
  - Dark (overlay color) at edges → Transparent expanding from element
  - Padding: 8pt around element

### Gesture Animations
All gesture demonstration steps show animated hand:
- **Swipe**: Hand moving left/right with momentum
- **Long Press**: Hand pressing with pulsing effect for 0.6s
- **Tap**: Quick tap animation
- **Pinch**: Two fingers moving together/apart

### Navigation Flow
- Tour controls all navigation automatically
- User only taps "Next" or "Skip"
- Forms/sheets opened by tour, closed by tour
- Tab switches automated with smooth transitions

### Mock Data (Field Tour Only)
- 3 projects: "Deck Installation" (today), "Fence Repair" (tomorrow), "Vinyl Siding" (+2 days)
- In-memory only, cleared after tour
- See RESEARCH_FINDINGS.md:297-354 for complete mock data specs

### File References
All file locations verified via codebase research:
- EventCarousel.swift:285-340 (tap/long press)
- UniversalJobBoardCard.swift:321-328 (swipe gesture)
- CalendarToggleView.swift:19-34 (view mode toggle)
- CalendarDaySelector.swift:55-82 (week swipe)
- MonthGridView.swift:484-491 (pinch gesture)
- ProjectFormSheet.swift:397, 424-469 (client search/create)
- TaskDetailsView.swift:496-555 (status update section)
- TaskListView.swift:108-121 (task tap handling)
- AppHeader.swift:188-193 (search), 174-185 (sync)
- SettingsView.swift:343-362 (search bar)
