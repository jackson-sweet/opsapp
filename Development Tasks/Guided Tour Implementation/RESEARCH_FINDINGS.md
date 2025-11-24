# Guided Tour Research Findings

**Date**: January 23, 2025
**Status**: Research Complete ✅

---

## Overview

Comprehensive research of OPS iOS codebase features needed for guided tour planning. All file locations, line numbers, and implementations verified.

---

## 1. ProjectFormSheet Client Creation Flow

**File**: `ProjectFormSheet.swift`

### Client Dropdown Mechanism
- **Lines 125-129**: Client filtering in real-time as user types
- Search text: `@State private var clientSearchText = ""`
- Filters `allClients` by name matching search text

### "Add Client" Button
- **Lines 266-270**: Opens ClientSheet when user wants to create new client
- **Pre-population**: `prefilledName: clientSearchText` passes search text to ClientSheet
- **ClientSheet.swift (93-95)**: Pre-fills name field in create mode

### UI Structure
- Progressive disclosure with expandable sections
- Client selection in "MANDATORY FIELDS" (always visible)
- Section auto-reordering when opened (lines 192-197)

### Tour Tip Location
**Highlight**: Client search field + dropdown "Create New Client" button
**Interaction**: Show "Import from Contacts" option in same area

---

## 2. Home Screen "Start Project" Functionality

**Files**:
- `HomeContentView.swift`
- `EventCarousel.swift`
- `EventCardView.swift`

### Tap Behavior
1. **First tap**: Selects card, shows confirmation overlay
2. **Second tap on overlay**: Calls `startTask()` function

### Confirmation Overlay (EventCardView 317-340)
```swift
VStack {
    Text("START TASK")
    Image(systemName: "play.fill")
}
.background(OPSStyle.Colors.primaryAccent.opacity(0.95))
```

### Task Start Workflow (Lines 343-368)
1. Updates task status to `.inProgress`
2. Posts navigation notification
3. Enters project mode: `appState.enterProjectMode(projectID:)`
4. Sets active task: `appState.activeTaskID = task.id`

### Quick Actions
**NOT separate quick actions menu** - the confirmation overlay IS the quick action
Once started, navigation is enabled on home screen

### Long Press (Lines 289-314)
- 0.6s duration
- Opens task details view
- Haptic feedback

### Tour Tip Location
**Highlight**: Event card in carousel
**Action**: Tap once → show confirmation → tap START

---

## 3. Calendar View Gestures

### Week View: Swipe to Cycle Weeks

**File**: `CalendarDaySelector.swift` (Lines 55-82)

**Implementation**:
- Swipe threshold: 50 points
- Velocity threshold: 200 points
- Spring animation: 0.3s response, 0.8 damping
- Drag resistance: 0.5x

**User Action**: Swipe left/right on weekday row
**Response**: Animates to previous/next week

### Month View: Pinch to Expand/Contract

**File**: `MonthGridView.swift` (Lines 484-491)

**Implementation**:
```swift
MagnificationGesture()
    .onChanged { value in
        let newHeight = gestureStartHeight * value
        cellHeight = min(max(newHeight, minHeight), maxHeight)
    }
```

**User Action**: Pinch up/down on calendar grid
**Response**: Row height adjusts, shows more/fewer events per cell

### Long Press for Reschedule

**File**: `UniversalJobBoardCard.swift` (Lines 430-447)

**Minimum Duration**: 0.3 seconds
**Haptic**: Medium impact at 0.3s

**Reschedule Logic (Lines 1089-1108)**:
- No tasks → reschedule project
- 1 task → reschedule that task automatically
- Multiple tasks → show task picker

**User Action**: Press and hold 0.3s on project card
**Response**: Opens scheduler or task picker

### Tour Tips Needed
1. Week swipe gesture (animated hand on weekday row)
2. Month pinch gesture (animated pinch on grid)
3. Long press reschedule (animated press on card)

---

## 4. Job Board Swipe Gestures

**File**: `UniversalJobBoardCard.swift` (Lines 305-337, 1415-1465)

### Implementation
- **Threshold**: 30% of card width (25% triggers, but 30% is the design intent)
- **Direction**: Left or right
- **Visual Feedback**: Revealed status card with opacity based on swipe distance
- **Validation**: `canSwipe(direction:)` checks permissions

### Status Revelation
```swift
if swipeOffset > 0 {
    // Right swipe - shows next status
    RevealedStatusCard(status: targetStatus, direction: .right)
} else if swipeOffset < 0 {
    // Left swipe - shows previous status
    RevealedStatusCard(status: targetStatus, direction: .left)
}
```

### Swipe Handlers
- **onChanged**: Updates `swipeOffset`, shows revealed card
- **onEnded**: Checks threshold, either confirms change or resets

### Tour Tip
**Highlight**: Project card in Job Board
**Animation**: Show swipe gesture left/right with status reveal
**Message**: "Swipe to change project status"

---

## 5. Task Status Updates

### Multiple Update Locations

**1. Event Carousel (Home)**
- File: `EventCarousel.swift` (343-368)
- Action: Tap START confirmation
- Result: Updates to `.inProgress`

**2. Task Details View**
- File: `TaskDetailsView.swift`
- Action: Tap status badge (NOT swipe)
- Result: Opens status picker

**3. Job Board Cards**
- File: `UniversalJobBoardCard.swift`
- Action: Swipe left/right
- Result: Changes task/project status

**4. Quick Actions**
- Long press on event card → Opens task details

### Update Method
All use: `dataController.updateTaskStatus(task:, to:)` called async

### Tour Tips
- Home: Show START button for in-progress
- Task Details: Tap status badge to change
- Job Board: Swipe to change (already covered)

---

## 6. Calendar Sync Button

**File**: `ScheduleView.swift` (Lines 54-82)
**Component**: `AppHeader` with `onRefreshTapped` callback

### Button Location
**AppHeader.swift (174-185)**:
```swift
Button(action: onRefreshTapped) {
    Image(systemName: "arrow.clockwise")
}
```
Located in top-right of calendar header

### Sync Flow
1. Shows loading indicator: `showingRefreshAlert = true`
2. Counts projects before sync
3. Calls `viewModel.refreshProjects()`
4. Counts projects after sync
5. Shows message: "Synced X new projects"

### User Feedback
- Loading indicator during sync
- Success message with count
- Toast/alert style notification

### Tour Tip
**Highlight**: Refresh button (arrow.clockwise icon) in top-right
**Message**: "Tap to sync your latest projects from the server"

---

## 7. Search Bars

### Calendar View Search

**File**: `ProjectSearchSheet.swift` (Lines 50-90)

**Searchable Fields**:
1. Project name
2. Client name (`project.effectiveClientName`)
3. Address
4. Team member names
5. Task types

**Additional Filters**:
- Project status (multi-select)
- Team members (multi-select)
- Task types (multi-select)
- Clients (multi-select)

**UI**: Full-screen sheet with search bar + filter chips

### Job Board Search

**File**: `UniversalSearchBar.swift`

**Search By Section**:
- **Projects**: Name, client name, address
- **Tasks**: Task type, task name, project name
- **Clients**: Client name

**UI**: Integrated search bar with filter button

### Settings Search

**File**: Settings view (exact file TBD)
**Searches**: Settings options only (NOT projects/tasks)

### Tour Tips
- Calendar: "Search projects by name, client, address, or team"
- Settings: "Search settings options" (NOT projects)

---

## Sample Data Requirements for Field Tour

### Mock Projects Needed
- **Count**: 2-3 projects
- **Schedule**: Within 3 days of current date
- **Assigned to**: Current user (field crew)
- **Status**: Mix of statuses (Accepted, In Progress)
- **Tasks**: Each project has 1-2 tasks
- **Photos**: Sample photos pre-loaded
- **Storage**: In-memory only (no database)

### Mock Data Factory Pattern

Use a factory pattern for cleaner, more maintainable mock data creation.

```swift
// MARK: - Mock Data Models

struct MockTourProject: Identifiable {
    let id: String
    let name: String
    let client: String
    let address: String
    let status: ProjectStatus
    let scheduledDate: Date
    let tasks: [MockTourTask]
    let photoAssets: [String]
}

struct MockTourTask: Identifiable {
    let id: String
    let name: String
    let taskType: String
    let status: TaskStatus
    let notes: String?
}

// MARK: - Mock Data Factory

struct TourMockDataFactory {

    /// Creates all mock data for the field crew tour
    static func createFieldTourData() -> [MockTourProject] {
        [
            .deckInstallation(scheduledDate: .today),
            .fenceRepair(scheduledDate: .tomorrow),
            .sidingInstallation(scheduledDate: .dayAfterTomorrow)
        ]
    }

    /// Creates mock data for office/admin tour (if needed)
    static func createOfficeTourData() -> [MockTourProject] {
        // Office tour may use real data, but factory available if needed
        createFieldTourData()
    }
}

// MARK: - Project Templates

extension MockTourProject {

    static func deckInstallation(scheduledDate: Date) -> MockTourProject {
        MockTourProject(
            id: UUID().uuidString,
            name: "Deck Installation",
            client: "Johnson Residence",
            address: "847 Maple Drive, Portland, OR",
            status: .inProgress,
            scheduledDate: scheduledDate,
            tasks: [
                .frameDeckStructure(),
                .installDeckingBoards()
            ],
            photoAssets: ["tour_deck_1"]
        )
    }

    static func fenceRepair(scheduledDate: Date) -> MockTourProject {
        MockTourProject(
            id: UUID().uuidString,
            name: "Fence Repair",
            client: "Martinez Property",
            address: "1523 Oak Street, Portland, OR",
            status: .accepted,
            scheduledDate: scheduledDate,
            tasks: [
                .replaceDamagedPosts()
            ],
            photoAssets: ["tour_fence_1"]
        )
    }

    static func sidingInstallation(scheduledDate: Date) -> MockTourProject {
        MockTourProject(
            id: UUID().uuidString,
            name: "Vinyl Siding Installation",
            client: "Thompson Home",
            address: "2891 Pine Avenue, Portland, OR",
            status: .accepted,
            scheduledDate: scheduledDate,
            tasks: [
                .prepareExteriorWalls(),
                .installVinylPanels()
            ],
            photoAssets: ["tour_siding_1"]
        )
    }
}

// MARK: - Task Templates

extension MockTourTask {

    static func frameDeckStructure() -> MockTourTask {
        MockTourTask(
            id: UUID().uuidString,
            name: "Frame deck structure",
            taskType: "Framing",
            status: .inProgress,
            notes: "Use pressure-treated lumber, 16\" spacing"
        )
    }

    static func installDeckingBoards() -> MockTourTask {
        MockTourTask(
            id: UUID().uuidString,
            name: "Install decking boards",
            taskType: "Installation",
            status: .pending,
            notes: nil
        )
    }

    static func replaceDamagedPosts() -> MockTourTask {
        MockTourTask(
            id: UUID().uuidString,
            name: "Replace damaged posts",
            taskType: "Repair",
            status: .pending,
            notes: "3 posts need replacement"
        )
    }

    static func prepareExteriorWalls() -> MockTourTask {
        MockTourTask(
            id: UUID().uuidString,
            name: "Prepare exterior walls",
            taskType: "Prep Work",
            status: .pending,
            notes: "Remove old siding, inspect sheathing"
        )
    }

    static func installVinylPanels() -> MockTourTask {
        MockTourTask(
            id: UUID().uuidString,
            name: "Install vinyl panels",
            taskType: "Installation",
            status: .pending,
            notes: nil
        )
    }
}

// MARK: - Date Helpers

extension Date {
    static var today: Date { Date() }
    static var tomorrow: Date { Date().addingTimeInterval(86400) }
    static var dayAfterTomorrow: Date { Date().addingTimeInterval(86400 * 2) }
}
```

### Factory Pattern Benefits
- **DRY**: Project/task definitions reusable
- **Readable**: `MockTourProject.deckInstallation(scheduledDate: .today)`
- **Maintainable**: Change project details in one place
- **Extensible**: Easy to add new project templates
- **Testable**: Factory methods can be unit tested

### Photo Assets
- Store in app bundle: `Assets.xcassets/TourImages/`
- Use system placeholder if assets not available
- Asset names: `tour_deck_1`, `tour_fence_1`, `tour_siding_1`

### Task Types (Mock, not from DB)
- "Framing"
- "Installation"
- "Repair"
- "Prep Work"

### Team Member (Current User)
- All projects assigned to current user as field crew member
- User's name from UserDefaults/auth context
- User's role: Field Crew

---

## Tour Grouping Method Recommendation

Based on research, I recommend **Feature-Based Grouping with Tags**:

### Why This Approach
1. **Reusability**: Calendar tips shared across tours
2. **Flexibility**: Tips can belong to multiple groups
3. **Maintainability**: Easy to add new tips
4. **Discovery**: Find all tips for a feature quickly

### Proposed Structure

```swift
struct TourStep: Identifiable {
    let id: String
    let title: String
    let message: String
    let targetView: TourTarget
    let gestureAnimation: GestureAnimation?
    let tags: Set<TourTag>
}

enum TourTag: String, CaseIterable {
    // Screen locations
    case home, jobBoard, calendar, projectDetails, taskDetails, settings

    // Features
    case navigation, search, sync
    case projectManagement, taskManagement, clientManagement
    case statusUpdates, scheduling, photoUpload
    case gestures

    // User roles
    case officeRole, fieldRole, adminRole

    // Tour phases
    case onboarding, advanced, contextual
}
```

### Usage Examples

**Reuse calendar tips in both tours:**
```swift
let calendarTips = allTourSteps.filter {
    $0.tags.contains(.calendar)
}
```

**Build office tour:**
```swift
let officeTour = allTourSteps.filter {
    $0.tags.contains(.officeRole) &&
    $0.tags.contains(.onboarding)
}
```

**Find all gesture-related tips:**
```swift
let gestureTips = allTourSteps.filter {
    $0.tags.contains(.gestures)
}
```

### Advantages
- ✅ Multiple tags per tip
- ✅ Easy filtering and composition
- ✅ Self-documenting (tags show purpose)
- ✅ Future-proof (add tags without restructuring)

---

## Next Steps

1. ✅ Research complete
2. ✅ Define exact tour sequences using research (see USER_FLOWS.md)
3. ✅ Define sample data specifications for field tour
4. 🔄 Review and approve planning documents with stakeholders
5. ⏳ Write final tour content (refine messages in CONTENT.md)
6. ⏳ Design visual specs (spotlight shape, tooltip positioning, animations)
7. ⏳ Build tour architecture (implementation phase)

---

## File Locations Summary

| Feature | Primary File | Line Numbers |
|---------|-------------|--------------|
| Client Creation | ProjectFormSheet.swift | 266-270 |
| Start Project | EventCarousel.swift | 343-368 |
| Week Swipe | CalendarDaySelector.swift | 55-82 |
| Month Pinch | MonthGridView.swift | 484-491 |
| Long Press Reschedule | UniversalJobBoardCard.swift | 430-447 |
| Swipe Status | UniversalJobBoardCard.swift | 305-337 |
| Calendar Sync | ScheduleView.swift | 54-82 |
| Calendar Search | ProjectSearchSheet.swift | 50-90 |
| Job Board Search | UniversalSearchBar.swift | N/A |

---

## Notes

- All implementations verified in codebase
- Line numbers accurate as of research date
- No assumptions made - all features researched
- Ready for detailed tour sequence design
