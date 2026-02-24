# CODEBASE AUDIT RESULTS

Complete audit of existing views, models, gestures, and components for tutorial integration.

---

## 1. VIEWS MAPPING TO TUTORIAL STEPS

### Company Creator Flow Views

| Tutorial Step | View File | Path |
|---------------|-----------|------|
| Step 1: Job Board Overview | `JobBoardDashboard.swift` | `OPS/Views/JobBoard/JobBoardDashboard.swift` |
| Step 2: FAB Action Menu | `FloatingActionMenu.swift` | `OPS/Views/Components/FloatingActionMenu.swift` |
| Step 3: Project Creation | `ProjectFormSheet.swift` | `OPS/Views/JobBoard/ProjectFormSheet.swift` |
| Step 4: Task Creation | `TaskFormSheet.swift` | `OPS/Views/JobBoard/TaskFormSheet.swift` |
| Step 5-6: Status Drag | `JobBoardDashboard.swift` | Same as Step 1 |
| Step 7: Project List Swipe | `JobBoardProjectListView.swift` | `OPS/Views/JobBoard/JobBoardProjectListView.swift` |
| Step 8-9: Calendar | `MonthGridView.swift` | `OPS/Views/Calendar Tab/MonthGridView.swift` |

### Employee Flow Views

| Tutorial Step | View File | Path |
|---------------|-----------|------|
| Step 1: Home Overview | `HomeView.swift` | `OPS/Views/Home/HomeView.swift` |
| Step 2-3: Project Details | `ProjectDetailsView.swift` | `OPS/Views/Components/Project/ProjectDetailsView.swift` |
| Step 4-5: Notes/Photos | `ProjectDetailsView.swift` | Same as above |
| Step 6: Complete Project | `ProjectDetailsView.swift` | Same as above |
| Step 7-8: Calendar | `MonthGridView.swift` | `OPS/Views/Calendar Tab/MonthGridView.swift` |

---

## 2. SWIFTDATA MODELS vs DEMO DATABASE

### Project Model
**File:** `OPS/DataModels/Project.swift`

| Demo Field | Model Property | Match? | Notes |
|------------|----------------|--------|-------|
| title | `title: String` | YES | |
| address | `address: String?` | YES | |
| status | `status: Status` | PARTIAL | Different enum values |
| description | `projectDescription: String?` | YES | |
| notes | `notes: String?` | YES | |
| client | `client: Client?` | YES | Relationship |
| teamMembers | `teamMembers: [User]` | YES | Relationship |
| tasks | `tasks: [ProjectTask]` | YES | Relationship |
| images | `projectImagesString: String` | YES | Comma-separated URLs |
| startDate | `startDate: Date?` | YES | |
| endDate | `endDate: Date?` | YES | |

**Status Mapping:**
```swift
// Demo Database → Code
"ACCEPTED"    → .accepted
"SCHEDULED"   → .accepted  // NOT a real status - use .accepted for projects with future tasks
"IN_PROGRESS" → .inProgress
"COMPLETED"   → .completed
```
**Note:** "SCHEDULED" was removed from spec. Projects with all future tasks use `.accepted`.

### ProjectTask Model
**File:** `OPS/DataModels/ProjectTask.swift`

| Demo Field | Model Property | Match? | Notes |
|------------|----------------|--------|-------|
| taskType | `taskType: TaskType?` | YES | Relationship |
| crew | `teamMembers: [User]` | YES | Relationship |
| date | `calendarEvent: CalendarEvent?` | YES | CalendarEvent has dates |
| status | `status: TaskStatus` | PARTIAL | Different enum values |
| notes | `taskNotes: String?` | YES | |

**TaskStatus Mapping:**
```swift
// Demo Database → Code
"BOOKED"      → .booked
"IN_PROGRESS" → .inProgress
"COMPLETED"   → .completed
```

### Client Model
**File:** `OPS/DataModels/Client.swift`

| Demo Field | Model Property | Match? | Notes |
|------------|----------------|--------|-------|
| name | `name: String` | YES | |
| type | N/A | NO | Not in model - ignore |
| address | `address: String?` | YES | |
| email | `email: String?` | YES | |
| phone | `phoneNumber: String?` | YES | |
| latitude | `latitude: Double?` | YES | |
| longitude | `longitude: Double?` | YES | |

### TaskType Model
**File:** `OPS/DataModels/TaskType.swift`

| Demo Field | Model Property | Match? | Notes |
|------------|----------------|--------|-------|
| type name | `display: String` | YES | |
| color | `color: String` | YES | Hex string |
| icon | `icon: String?` | YES | SF Symbol |

### TeamMember / User
**Files:** `OPS/DataModels/TeamMember.swift`, `OPS/DataModels/User.swift`

For demo data, create `User` entities (used in relationships):

| Demo Field | User Property | Match? |
|------------|---------------|--------|
| name | `firstName`, `lastName` | YES |
| specialization | `role` via `UserRole` | PARTIAL |
| avatar | `avatarURL: String?` | YES |

---

## 3. EXISTING GESTURE IMPLEMENTATIONS

### Long-Press + Drag (JobBoardDashboard.swift)

**Location:** Lines 561-752 (`DirectionalDragCard`)

**Implementation:**
```swift
// Long press gesture (line 602-607)
private var longPressGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.3)
        .onEnded { _ in
            triggerLongPress()
        }
}

// Drag gesture (line 577-599)
private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
        .onChanged { value in
            if isLongPressing {
                onDragChanged(project, value.location)
            }
        }
        .onEnded { _ in
            if isLongPressing {
                onDragEnded(project)
            }
        }
}

// Combined gesture (line 610-612)
private var combinedGesture: some Gesture {
    longPressGesture.sequenced(before: dragGesture)
}
```

**Haptic:** Line 722-724
```swift
let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
impactFeedback.impactOccurred()
```

### Swipe-to-Change-Status (UniversalJobBoardCard.swift)

**Location:** Lines 36-44 (state), gesture implementation throughout

**Key State:**
```swift
@State private var swipeOffset: CGFloat = 0
@State private var isChangingStatus = false
@State private var hasTriggeredHaptic = false
@State private var confirmingStatus: Any? = nil
@State private var confirmingDirection: SwipeDirection? = nil
```

**Note:** Full gesture code extends throughout file - primarily uses DragGesture with threshold detection.

### Tab View Page Swipe (JobBoardDashboard.swift)

**Location:** Lines 33-56

```swift
TabView(selection: $currentPageIndex) {
    ForEach(statuses.indices, id: \.self) { index in
        StatusColumn(...)
            .tag(index)
    }
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

---

## 4. EXISTING COMPONENTS TO REUSE

### TypewriterText
**File:** `OPS/Onboarding/Components/TypewriterText.swift`

**Features:**
- Character-by-character typing animation
- Blinking cursor
- Configurable speed, delay, colors
- Space reservation (no layout shift)
- `onComplete` callback

**Usage:**
```swift
TypewriterText(
    "YOUR TEXT HERE",
    font: OPSStyle.Typography.title,
    color: OPSStyle.Colors.primaryText,
    typingSpeed: 30,  // chars per second
    startDelay: 0,
    onComplete: { /* callback */ }
)
```

**Additional Components in Same File:**
- `OnboardingAnimationCoordinator` - Phase-based animation orchestration
- `AnimatedOnboardingHeader` - Title + subtitle with typing
- `PhasedOnboardingHeader` - External coordinator version
- `PhasedLabel` - Labels that type during specific phase
- `PhasedContent` - Content that fades in during phase
- `PhasedPrimaryButton` - Button with typing animation

### FloatingActionMenu
**File:** `OPS/Views/Components/FloatingActionMenu.swift`

**Features:**
- Plus button at bottom-right
- Expands to show: Create Client, Create Project, Create Task, New Task Type
- Animated gradient overlay when open
- Role-based visibility (admin/officeCrew only)

**State:**
```swift
@State private var showCreateMenu = false
@State private var showingCreateProject = false
@State private var showingCreateClient = false
@State private var showingCreateTaskType = false
@State private var showingCreateTask = false
```

### OPSStyle
**File:** `OPS/Styles/OPSStyle.swift`

**Relevant Constants:**
- `OPSStyle.Colors.background` - Main dark background
- `OPSStyle.Colors.primaryText` - White text
- `OPSStyle.Colors.secondaryText` - Gray text
- `OPSStyle.Colors.cardBackgroundDark` - Card backgrounds
- `OPSStyle.Layout.cornerRadius` - Standard corner radius
- `OPSStyle.Typography.*` - All font styles

---

## 5. ENVIRONMENT OBJECTS NEEDED

Views use these environment objects that must be provided:

```swift
@EnvironmentObject private var dataController: DataController
@EnvironmentObject private var appState: AppState
@Environment(\.modelContext) private var modelContext
```

For tutorial mode, will also need:
```swift
@Environment(\.tutorialMode) var tutorialMode: Bool
```

---

## 6. CALENDAR COMPONENTS

**Files in `OPS/Views/Calendar Tab/`:**
- `MonthGridView.swift` - Main month grid calendar
- `Components/CalendarHeaderView.swift` - Header with month/year
- `Components/CalendarDaySelector.swift` - Day selection
- `Components/CalendarEventCard.swift` - Event cards
- `Components/CalendarProjectCard.swift` - Project cards
- `Components/DayCell.swift` - Individual day cells
- `Components/WeekDayCell.swift` - Week day headers
- `Components/CalendarToggleView.swift` - Week/Month toggle

**No explicit CalendarView.swift** - The calendar is composed from these components in parent views.

---

## 7. GAP ANALYSIS

### Missing from Codebase (Need to Build)
1. Tutorial environment flag system
2. Scaled container wrapper
3. Dark overlay with cutout
4. Swipe indicator shimmer animation
5. Tutorial state manager
6. Demo data manager
7. Tutorial flow orchestrators

### Model Gaps
1. ~~**No "SCHEDULED" status**~~ - RESOLVED: Use `.accepted` for projects with future tasks
2. ~~**Project images**~~ - RESOLVED: Assets available in `Assets.xcassets/Images/Demo/`

### View Gaps
1. **No dedicated CalendarView** - Need to identify where calendar is composed
2. **Employee Home vs Home** - Both use `HomeView.swift`, role handled internally

### Potential Issues
1. **User vs TeamMember confusion** - Demo data must use `User` entities for relationships
2. **CalendarEvent required for task dates** - Tasks don't have direct date properties
3. **Company ID required** - All entities need `companyId` - need to handle for demo data
