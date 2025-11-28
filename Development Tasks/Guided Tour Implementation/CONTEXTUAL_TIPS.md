# Contextual Tips System

**Status**: Planning Phase
**Created**: November 24, 2025

---

## Overview

Contextual tips are lightweight, non-intrusive hints that appear when users first encounter specific features. Unlike the guided tour, tips appear organically during real usage and can be dismissed with a single tap.

**Key Principles:**
- Show once per feature, then never again (unless user resets)
- One tip at a time (no stacking)
- Mini-spotlight visual (lighter than main tour)
- Tap anywhere to dismiss
- Auto-dismiss after 8 seconds if no interaction
- Can be globally disabled in Settings

---

## Initial Choice Screen

**Location**: Last step of welcome flow, after login
**Purpose**: Let users choose their onboarding experience

### Screen Layout

**Header**: "Choose Your Onboarding"

**Body**:
```
Select how you want to learn OPS.
This choice determines your first experience.
You can change it later in Settings.
```

---

### Option 1: Guided Tour

**Title**: "Guided Tour"

**Description**:
```
90-second walkthrough of core features.
Shows you exactly what you need to know.
Recommended for first-time users.
```

**Action**: Launches role-appropriate tour (Office/Admin or Field Crew)
**Button**: "Start Tour"
**Sets**: `hasCompletedTour = false`, `hasSkippedTour = false`, `contextualTipsEnabled = true`

---

### Option 2: Learn As You Go

**Title**: "Contextual Tips"

**Description**:
```
Tips appear as you discover features.
Learn at your own pace without interruption.
Recommended if you prefer to explore.
```

**Action**: Skips tour, enables contextual tips
**Button**: "Enable Tips"
**Sets**: `hasCompletedTour = false`, `hasSkippedTour = true`, `contextualTipsEnabled = true`

---

### Option 3: No Assistance

**Title**: "Skip All Help"

**Description**:
```
No tours. No tips. Direct access to the app.
You'll figure it out.
Recommended for experienced users.
```

**Action**: Skips tour, disables all tips
**Button**: "Skip"
**Sets**: `hasCompletedTour = false`, `hasSkippedTour = true`, `contextualTipsEnabled = false`

---

**Footer**:
```
Access the tour or tips anytime from Settings → Help.
```

---

## All Contextual Tips (30 Total)

### Priority Legend
- **P0**: Critical gestures - Show these first (hidden, easy to miss)
- **P1**: High-impact features - Important workflow accelerators
- **P2**: Workflow enhancements - Nice to have, improve experience
- **P3**: Basic UI - Self-explanatory but helpful

### Visibility Legend
- **Office**: Office crew and admins see this tip
- **Field**: Field crew sees this tip
- **Office, Field**: Both roles see this tip

---

## P0 - Critical Gestures (8 tips)

### Tip #1: Job Board Sections

**Priority**: P0
**Visibility**: `["office", "field"]`
**Screen**: Job Board View (Dashboard tab)
**Trigger**: First time opening Job Board
**Element**: Section selector (Dashboard/Clients/Projects/Tasks)
**Tip Text**:
```
Navigate between Dashboard, Clients, Projects, and Tasks.

Dashboard shows projects grouped by status.
```
**Dismissal**: User taps any section tab, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_jobBoardSections`
**Reference**: JobBoardView.swift:198-202 (enum JobBoardSection)
**Research Status**: ✅ Verified

---

### Tip #2: Floating + Button

**Priority**: P0
**Visibility**: `["office"]`
**Screen**: Home, Job Board, or Calendar (anywhere floating button appears)
**Trigger**: First time seeing floating + button
**Element**: Floating action button (64x64pt circle, bottom right, 140pt above tab bar)
**Tip Text**:
```
Create projects, clients, tasks, or task types.

Tap to see all options.
```
**Dismissal**: User taps the + button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_floatingActionButton`
**Reference**: FloatingActionMenu.swift:20-144 (visibility lines 20-23, button at bottom right, expands to show 4 options)
**Research Status**: ✅ Verified

---

### Tip #3: Client Search/Creation

**Priority**: P0
**Visibility**: `["office"]`
**Screen**: ProjectFormSheet (create mode)
**Trigger**: First time opening project form
**Element**: Client search TextField
**Tip Text**:
```
Start typing a client name.

Tap "Create" if no match exists to add a new client.
```
**Dismissal**: User types in field OR taps dropdown, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_clientSearch`
**Reference**: ProjectFormSheet.swift:397 (TextField), 424-469 (dropdown)
**Research Status**: ✅ Verified

---

### Tip #5: Week Swipe Gesture

**Priority**: P0
**Visibility**: `["office", "field"]`
**Screen**: Calendar View (Week mode)
**Trigger**: First time opening Calendar
**Element**: Weekday row (CalendarDaySelector)
**Tip Text**:
```
Swipe left or right on the weekday row to cycle through weeks.

Navigate your schedule quickly.
```
**Dismissal**: User performs swipe gesture on weekday row, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_weekSwipe`
**Reference**: CalendarDaySelector.swift:55-82 (DragGesture)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated hand swiping left/right

---

### Tip #9: Calendar Sync Button

**Priority**: P0
**Visibility**: `["office", "field"]`
**Screen**: Calendar View
**Trigger**: First time opening Calendar
**Element**: Refresh button (arrow.clockwise icon, top-right, 44x44pt)
**Tip Text**:
```
Tap to sync your latest projects from the server.

Keep your schedule up to date.
```
**Dismissal**: User taps sync button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_calendarSync`
**Reference**: AppHeader.swift:174-185, ScheduleView.swift:54-82
**Research Status**: ✅ Verified

---

### Tip #12: Long Press Task Card

**Priority**: P0
**Visibility**: `["office", "field"]`
**Screen**: Home View (Event Carousel)
**Trigger**: First time viewing home screen with tasks
**Element**: Event card in carousel
**Tip Text**:
```
Press and hold a task card for 0.6 seconds to open full details.

See location, materials, notes, and team members.
```
**Dismissal**: User performs long press on any task card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_longPressTask`
**Reference**: EventCarousel.swift:289-314 (LongPressGesture, 0.6s duration)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated hand pressing and holding with pulsing effect

---

### Tip #20: Photo Upload Button

**Priority**: P0
**Visibility**: `["office", "field"]`
**Screen**: ProjectDetailsView
**Trigger**: First time opening ProjectDetailsView
**Element**: "ADD PHOTOS" button (full width, blue, with plus.viewfinder icon)
**Tip Text**:
```
Add job site photos to document progress.

Photos sync automatically when online.
```
**Dismissal**: User taps photo upload button OR adds a photo, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_photoUpload`
**Reference**: ProjectDetailsView.swift:1237-1246 (photosSection), 1354-1373 (addPhotosButton)
**Research Status**: ✅ Verified

---

### Tip #21: Task Type Creation

**Priority**: P0 (HIGH PRIORITY)
**Visibility**: `["office"]`
**Screen**: Floating + menu, OR Task Type management screen
**Trigger**: First time accessing task type creation
**Element**: "New Task Type" option in floating + menu (appears with 0.8s animation delay)
**Tip Text**:
```
Create custom task types to organize your work.

Use task types to track different kinds of jobs.
```
**Dismissal**: User taps create task type button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_createTaskType`
**Reference**: TaskTypeSheet.swift:12-30 (sheet with create/edit modes), FloatingActionMenu.swift (New Task Type option)
**Research Status**: ✅ Verified

---

## P1 - High-Impact Features (8 tips)

### Tip #6: Month Pinch Gesture

**Priority**: P1
**Visibility**: `["office", "field"]`
**Screen**: Calendar View (Month mode)
**Trigger**: First time viewing Month mode
**Element**: Calendar grid in MonthGridView
**Tip Text**:
```
Pinch up or down to adjust row height.

See more details or fit more days on screen.
```
**Dismissal**: User performs pinch gesture, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_monthPinch`
**Reference**: MonthGridView.swift:484-491 (MagnificationGesture)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated pinch gesture (two fingers moving together/apart)

---

### Tip #7: Swipe to Change Status (Job Board)

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: Job Board - Projects Tab
**Trigger**: First time viewing Job Board Projects tab
**Element**: First project card in list
**Tip Text**:
```
Swipe left or right on any project card to change its status.

Quick updates without opening the project.
```
**Dismissal**: User performs swipe gesture on any project card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_swipeStatus`
**Reference**: UniversalJobBoardCard.swift:321-328 (DragGesture, 5pt minimum)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated hand swiping left/right, revealed status card appears

---

### Tip #10: Settings Search Bar

**Priority**: P1
**Visibility**: `["office", "field"]`
**Screen**: Settings View
**Trigger**: First time opening Settings
**Element**: Search bar button ("Search settings...")
**Tip Text**:
```
Search for specific settings or ask questions about OPS.

Find what you need quickly.
```
**Dismissal**: User taps search bar, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_settingsSearch`
**Reference**: SettingsView.swift:343-362
**Research Status**: ✅ Verified

---

### Tip #13: Swipe Project Card (Job Board)

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: Job Board - Projects or Dashboard
**Trigger**: First time viewing project cards
**Element**: Project card
**Tip Text**:
```
Swipe left or right to change project status.

Fast status updates keep everyone informed.
```
**Dismissal**: User performs swipe gesture on any project card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_swipeProjectCard`
**Reference**: UniversalJobBoardCard.swift:321-328 (DragGesture)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated swipe with status reveal

---

### Tip #15: Long Press → Reschedule Button

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: Calendar View (Week or Month)
**Trigger**: First time viewing Calendar with projects
**Element**: Project card in calendar
**Tip Text**:
```
Press and hold any project to see the Reschedule button.

Quickly change project dates.
```
**Dismissal**: User performs long press on any project card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_longPressReschedule`
**Reference**: UniversalJobBoardCard.swift:430-447 (long press), 1089-1108 (reschedule logic)
**Research Status**: ✅ Verified from RESEARCH_FINDINGS
**Gesture Animation**: Animated long press with reschedule button appearing

---

### Tip #16: Copy from Project

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: ProjectFormSheet (create mode)
**Trigger**: First time opening project form (after client search tip)
**Element**: "Copy from Project" button at bottom
**Tip Text**:
```
Reuse details from an existing project.

Saves time when creating similar jobs.
```
**Dismissal**: User taps "Copy from Project" button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_copyFromProject`
**Reference**: ProjectFormSheet.swift:229-248 (copy button)
**Research Status**: ✅ Verified

---

### Tip #24: Import from Contacts

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: ClientSheet (create mode)
**Trigger**: First time opening ClientSheet
**Element**: "IMPORT FROM CONTACTS" button (full width, at bottom of form, dark background with border)
**Tip Text**:
```
Import contact info from your phone.

Pull name, phone, email, and address automatically.
```
**Dismissal**: User taps "Import from Contacts" button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_importFromContacts`
**Reference**: ClientSheet.swift:310-328 (button with person.crop.circle icon, only visible in create mode line 309)
**Research Status**: ✅ Verified

---

### Tip #31: Long Press Client (NEW)

**Priority**: P1
**Visibility**: `["office"]`
**Screen**: Job Board - Clients Tab
**Trigger**: First time viewing Clients tab
**Element**: Client card in list
**Tip Text**:
```
Press and hold a client card to see options.

Quick access to client details and actions.
```
**Dismissal**: User performs long press on any client card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_longPressClient`
**Reference**: UniversalJobBoardCard.swift:84-101 (LongPressGesture with 0.3s minimumDuration, opens confirmationDialog with clientActions)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated long press

---

## P2 - Workflow Enhancements (6 tips)

### Tip #11: Tap Task Card (START Button)

**Priority**: P2
**Visibility**: `["office", "field"]`
**Screen**: Home View (Event Carousel)
**Trigger**: First time viewing home with tasks
**Element**: Event card in carousel
**Tip Text**:
```
Tap once to show the START button.

Tap START to begin the task and activate navigation.
```
**Dismissal**: User taps any task card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_tapTaskCard`
**Reference**: EventCarousel.swift:285-288 (onTapGesture), 317-340 (confirmation overlay)
**Research Status**: ✅ Verified

---

### Tip #14: Task Status Update Section

**Priority**: P2
**Visibility**: `["office", "field"]`
**Screen**: TaskDetailsView
**Trigger**: First time opening TaskDetailsView
**Element**: "Update Status" section at bottom
**Tip Text**:
```
Tap any status to update the task.

Keep everyone informed of your progress.
```
**Dismissal**: User taps any status in the list, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_taskStatusUpdate`
**Reference**: TaskDetailsView.swift:496-555 (status section with circle indicators)
**Research Status**: ✅ Verified

---

### Tip #25: Add Sub-Client

**Priority**: P2
**Visibility**: `["office"]`
**Screen**: ClientDetailsView (ContactDetailView)
**Trigger**: First time viewing client details
**Element**: "Add Sub-Client" button or section in client details
**Tip Text**:
```
Add contacts like site supervisors, project managers, or foremen.

Organize all contacts for a general contractor.
```
**Dismissal**: User taps "Add Sub-Client" button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_addSubClient`
**Reference**: SubClientEditSheet.swift:37-50 (sheet for creating/editing sub-clients), SubClientListView.swift (displays sub-clients)
**Research Status**: ✅ Verified

---

### Tip #26: Client Details View

**Priority**: P2
**Visibility**: `["office"]`
**Screen**: Job Board - Clients Tab
**Trigger**: First time viewing Clients tab (after long press tip)
**Element**: Client card in list
**Tip Text**:
```
Tap any client to view full details.

See contact info, projects, and history.
```
**Dismissal**: User taps any client card, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_clientDetails`
**Reference**: UniversalJobBoardCard.swift:81-82 (onTapGesture sets showingDetails = true), 854-856 (opens ContactDetailView for clients)
**Research Status**: ✅ Verified

---

### Tip #27: Calendar Filter

**Priority**: P2
**Visibility**: `["office", "field"]`
**Screen**: Calendar View
**Trigger**: First time opening Calendar (show after sync/search tips)
**Element**: Filter button (funnel icon "line.3.horizontal.decrease.circle" in header, 44x44pt)
**Tip Text**:
```
Filter your schedule by status, team member, or client.

Focus on what matters.
```
**Dismissal**: User taps filter button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_calendarFilter`
**Reference**: AppHeader.swift:149-161 (filter button with optional filter count badge, shows .fill icon when active)
**Research Status**: ✅ Verified

---

### Tip #28: Date Picker

**Priority**: P2
**Visibility**: `["office", "field"]`
**Screen**: Calendar View
**Trigger**: First time viewing Calendar (show after filter tip)
**Element**: Period button (shows "Nov 18-24" or "December")
**Tip Text**:
```
Tap to jump to a specific date.

Quick navigation to any week or month.
```
**Dismissal**: User taps date picker button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_datePicker`
**Reference**: CalendarToggleView.swift:41-75 (period button and date picker)
**Research Status**: ✅ Verified

---

## P3 - Basic UI (8 tips)

### Tip #4: Calendar Toggle (Week/Month)

**Priority**: P3
**Visibility**: `["office", "field"]`
**Screen**: Calendar View
**Trigger**: First time viewing Calendar
**Element**: SegmentedControl with "Week" and "Month" options
**Tip Text**:
```
Switch between Week and Month views.

Calendar opens in Week view by default.
```
**Dismissal**: User taps either Week or Month, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_calendarToggle`
**Reference**: CalendarToggleView.swift:19-34 (SegmentedControl)
**Research Status**: ✅ Verified

---

### Tip #8: Calendar Search Button

**Priority**: P3
**Visibility**: `["office", "field"]`
**Screen**: Calendar View
**Trigger**: First time viewing Calendar
**Element**: Magnifying glass icon button (top-right, 44x44pt)
**Tip Text**:
```
Search for projects by name, client, address, or team member.

Find any job quickly.
```
**Dismissal**: User taps search button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_calendarSearch`
**Reference**: AppHeader.swift:188-193 (magnifyingglass icon button)
**Research Status**: ✅ Verified

---

### Tip #17: Add Task Button

**Priority**: P3
**Visibility**: `["office"]`
**Screen**: ProjectDetailsView
**Trigger**: First time opening ProjectDetailsView
**Element**: "Add" button in Tasks section header
**Tip Text**:
```
Add tasks to break down the project into steps.

Track progress for each part of the job.
```
**Dismissal**: User taps "Add" button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_addTask`
**Reference**: TaskListView.swift:54-73 (Add button)
**Research Status**: ✅ Verified

---

### Tip #18: Drag to Archive

**Priority**: P3
**Visibility**: `["office"]`
**Screen**: Job Board - Dashboard
**Trigger**: First time viewing Dashboard with draggable projects
**Element**: Archive zone (bottom of screen, 100pt height × 200pt width)
**Tip Text**:
```
Press, hold, and drag projects to the archive box at the bottom.

Archive projects for later reference.
```
**Dismissal**: User performs drag to archive gesture, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_dragToArchive`
**Reference**: JobBoardDashboard.swift:273-275 (DragZone.archive), 280-283 (archive zone dimensions)
**Research Status**: ✅ Verified
**Gesture Animation**: Animated drag to bottom with archive box highlight

---

### Tip #19: Team Member Section

**Priority**: P3
**Visibility**: `["office", "field"]`
**Screen**: ProjectDetailsView
**Trigger**: First time opening ProjectDetailsView (even if team list empty)
**Element**: Team Members section/card (SectionCard with crew icon)
**Tip Text**:
```
See all crew members assigned to tasks on this project.

Shows the total team working on the job.
```
**Dismissal**: User scrolls to or interacts with team section, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_teamMemberSection`
**Reference**: ProjectDetailsView.swift:1202-1211 (teamSection using SectionCard with OPSStyle.Icons.crew and ProjectTeamView)
**Research Status**: ✅ Verified

---

### Tip #22: Add Task Notes

**Priority**: P3
**Visibility**: `["office", "field"]`
**Screen**: TaskDetailsView
**Trigger**: First time opening TaskDetailsView (after status update tip)
**Element**: Notes section with "TASK NOTES" header and expandable chevron
**Tip Text**:
```
Add notes to document work details or issues.

Notes are visible to all team members.
```
**Dismissal**: User taps notes field, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_addTaskNotes`
**Reference**: TaskDetailsView.swift:440-465 (notesField with ExpandableNotesView, chevron icon shows expand/collapse state)
**Research Status**: ✅ Verified

---

### Tip #29: Job Board Filter

**Priority**: P3
**Visibility**: `["office"]`
**Screen**: Job Board - Projects or Tasks Tab
**Trigger**: First time viewing Projects or Tasks tab
**Element**: "FILTER & SORT" button with funnel icon (full width row)
**Tip Text**:
```
Filter projects or tasks by status, team, or other criteria.

Focus on specific work.
```
**Dismissal**: User taps filter button, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_jobBoardFilter`
**Reference**: JobBoardView.swift:659-688 (filterButton with "line.3.horizontal.decrease.circle" icon, shows filter count badge when active)
**Research Status**: ✅ Verified

---

### Tip #30: Section Tabs (Job Board)

**Priority**: P3
**Visibility**: `["office"]`
**Screen**: Job Board View
**Trigger**: First time viewing Job Board (after sections tip)
**Element**: Section tabs (Dashboard/Clients/Projects/Tasks)
**Tip Text**:
```
Switch between Dashboard, Clients, Projects, and Tasks views.

Each section organizes your work differently.
```
**Dismissal**: User taps any section tab, OR taps anywhere
**UserDefaults Key**: `hasSeenContextualTip_sectionTabs`
**Reference**: JobBoardView.swift:61-73 (section selector)
**Research Status**: ✅ Verified

---

## Data Models

### ContextualTip

```swift
struct ContextualTip: Identifiable {
    let id: String
    let priority: TipPriority
    let visibilityRoles: [UserRole]  // [.admin, .officeCrew] or [.fieldCrew] or all
    let screen: TipScreen
    let trigger: TipTrigger
    let element: TipTarget
    let tipText: String
    let dismissalCondition: TipDismissal
    let storageKey: String
    let fileReference: String?
    let gestureAnimation: GestureAnimation?
    let tags: Set<TourTag>  // Reuse tour tags
}

enum TipPriority: Int {
    case p0 = 0  // Critical gestures
    case p1 = 1  // High-impact features
    case p2 = 2  // Workflow enhancements
    case p3 = 3  // Basic UI
}

enum TipScreen {
    case home
    case jobBoard(section: JobBoardSection?)
    case calendar
    case projectDetails
    case taskDetails
    case clientDetails
    case projectForm
    case clientForm
    case settings
}

enum TipTrigger {
    case firstVisit  // First time user sees this screen
    case nthVisit(Int)  // After N visits to screen
    case elementVisible  // When specific element becomes visible
}

enum TipDismissal {
    case tapAnywhere
    case performAction(String)  // e.g., "swipe", "longPress", "tapButton"
    case timeout(TimeInterval)
    case combined([TipDismissal])  // Multiple dismissal conditions (OR logic)
}

struct TipTarget {
    let identifier: String  // View identifier or coordinate-based
    let type: TargetType

    enum TargetType {
        case viewIdentifier(String)
        case coordinates(CGRect)
        case dynamicElement(finder: () -> CGRect?)
    }
}
```

### TipState

```swift
struct TipState {
    var contextualTipsEnabled: Bool
    var seenTips: Set<String>  // Tip IDs that have been shown
    var lastTipShownDate: Date?
    var lastTipShownScreen: TipScreen?
}
```

### UserDefaults Storage

```swift
enum TipStorageKeys {
    static let contextualTipsEnabled = "contextualTipsEnabled"  // Bool, default: true
    static let seenTips = "seenContextualTips"  // Set<String>
    static let hasSkippedTour = "hasSkippedTour"  // Bool
    static let hasCompletedTour = "hasCompletedTour"  // Bool
}
```

---

## Visual Specifications

### Mini-Spotlight (Contextual Tips)

**Differences from Main Tour:**

| Aspect | Main Tour | Contextual Tip |
|--------|-----------|----------------|
| Overlay Opacity | 0.85 | 0.6 |
| Spotlight | Hard cutout | Soft radial gradient |
| Dismissal | Next/Skip buttons | Tap anywhere |
| Duration | User-controlled | Auto-dismiss after 8s |
| Progress | Indicator shown | No indicator |
| Blocking | Fully blocks interaction | Lightweight, less intrusive |

### Spotlight Gradients

**Radial Gradient** (for circular elements):
- Center: Transparent
- Edge: Dark overlay (0.6 opacity)
- Radius: Element size + 8pt padding

**Linear Gradient** (for rectangular elements):
- Start: Transparent at element
- End: Dark overlay (0.6 opacity) expanding outward
- Padding: 8pt around element

### Tooltip Styling

```swift
struct ContextualTipTooltip {
    let maxWidth: CGFloat = 280
    let padding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    let cornerRadius: CGFloat = 8
    let backgroundColor: Color = OPSStyle.Colors.cardBackgroundDark
    let textColor: Color = OPSStyle.Colors.primaryText
    let font: Font = OPSStyle.Typography.body
}
```

**No arrow** - Position tooltip in available space near element

---

## Trigger Logic

### Show Contextual Tip When:

1. **Global Check**: `contextualTipsEnabled == true`
2. **Role Check**: Current user role matches tip's `visibilityRoles`
3. **Screen Check**: User is on correct screen
4. **Seen Check**: Tip ID not in `seenTips` set
5. **Cooldown Check**: No other tip shown in last 2 seconds
6. **Priority Check**: No higher-priority tip waiting on this screen

### Priority Queue System

When multiple eligible tips exist on same screen:
1. Filter by priority level (P0 first)
2. Within same priority, show in order defined above (Tip #1, #2, etc.)
3. After dismissal, wait until **next screen visit** to show next tip
4. Never show more than 1 tip per screen visit

---

## Settings Integration

### Settings → Help Section

```
HELP

Guided Tour
Retake the onboarding tour

Contextual Tips [Toggle: ON/OFF]
Show helpful tips as you explore

Reset All Tips
See all tips again from the beginning
```

**Toggle Behavior:**
- **ON**: Tips appear during normal usage
- **OFF**: No tips shown, but tour remains accessible

**Reset All Tips:**
- Clears `seenTips` set
- Shows confirmation: "All tips will appear again. Continue?"
- Does not affect tour completion status

---

## Implementation Notes

### Timing Considerations

1. **Auto-Dismiss**: 8 seconds if no interaction
2. **Cooldown**: 2 seconds between tips (even across screens)
3. **Session Limit**: Maximum 3 tips per app session (to avoid overwhelming)

### Gesture Animations

For gesture-based tips (swipe, long press, pinch, drag):
- Show animated hand performing the gesture
- Loop animation until dismissed
- Use same animation style as main tour

### Tour-Skipper Behavior

Users who choose "Contextual Tips" see ALL tour-feature tips immediately on first encounter:
- No phased rollout
- No waiting for multiple visits
- All P0 tips show on first relevant screen visit
- Creates accelerated learning path for self-directed users

### Field Crew Filtering

**Field Crew See**: 13 tips
- All P0 tips except #2 (Floating +), #3 (Client search), #21 (Task type creation)
- Limited P1 tips (no management features)
- Essential P2 tips only
- Minimal P3 tips

**Office Crew See**: All 30 tips

---

## Research Status Summary

**✅ Verified (30 tips)**: #1, #2, #3, #4, #5, #6, #7, #8, #9, #10, #11, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21, #22, #24, #25, #26, #27, #28, #29, #30, #31

**All Research Complete**: All 30 contextual tips have been thoroughly researched with file locations and line numbers verified.

---

## Next Steps

1. ✅ Complete research for all tips (30/30 verified)
2. ⏳ Define exact tooltip positioning for each tip
3. ⏳ Create gesture animation specs
4. ⏳ Implement TipManager and state management
5. ⏳ Build UI components (mini-spotlight, tooltip)
6. ⏳ Integrate with app navigation flow
7. ⏳ Test with both roles (office and field)
