# OPS INTERACTIVE TUTORIAL - IMPLEMENTATION SPEC

Complete specification for Phase 2 onboarding tutorial. Hand off to Claude Code for implementation.

---

## OVERVIEW

**Purpose:** Interactive, learn-by-doing tutorial that teaches users OPS in under 3 minutes.

**Timing:** Occurs after Ready screen, before Welcome Guide.

**Two Flows:**
- Company Creator: ~30 seconds (project creation, status management, calendar)
- Employee: ~20 seconds (view assignments, project details, complete work)

**Demo Data:** Top Gun themed sandbox - see `TopGun_Demo_Database.md`

---

## ARCHITECTURE

### Approach: Wrapper + Environment Flags

1. Create thin wrapper views that compose real views
2. Inject `@Environment(\.tutorialMode)` for simple conditional logic
3. Tutorial logic stays centralized in wrappers
4. Real view changes propagate automatically

### Key Components to Build

```
Tutorial/
├── TutorialContainerView.swift      // 80% scaled container + tooltip area
├── TutorialOverlayView.swift        // Dark overlay with interactive cutout
├── TutorialSwipeIndicator.swift     // Slide-to-unlock ripple animation
├── TutorialStateManager.swift       // Phase tracking, stopwatch, completion
├── TutorialDemoDataManager.swift    // Seed/cleanup Top Gun data
├── CompanyTutorialFlow.swift        // Company creator step orchestration
├── EmployeeTutorialFlow.swift       // Employee step orchestration
└── TutorialCompletionView.swift     // Final message with time
```

### Environment Flag

```swift
struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }
}
```

---

## VISUAL SYSTEM

### Scaled Container

- Main tutorial content renders at 80% scale within a container
- Container centered vertically with space below for tooltip
- Use `scaleEffect(0.8)` with frame constraints
- Touch events must map correctly to scaled content

```swift
TutorialContainerView {
    // Actual view content at 80% scale
}
.frame(height: UIScreen.main.bounds.height * 0.75)

// Tooltip area below
TutorialTooltipView(text: currentStep.tooltipText)
```

### Dark Overlay System

- 60% black overlay covers entire container
- Interactive element revealed via cutout (full brightness, receives touches)
- Non-target elements: dimmed, non-interactive

```swift
struct TutorialOverlayView: View {
    let cutoutFrame: CGRect  // Frame of interactive element
    
    var body: some View {
        Color.black.opacity(0.6)
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .frame(width: cutoutFrame.width, height: cutoutFrame.height)
                            .position(x: cutoutFrame.midX, y: cutoutFrame.midY)
                            .blendMode(.destinationOut)
                    )
            )
            .allowsHitTesting(false)
    }
}
```

### Swipe Indicator (Slide-to-Unlock Style)

- Animated gradient ripple in swipe direction
- Pulses 2-3 times, then holds subtle hint
- Use shimmer effect similar to iOS slide-to-unlock

```swift
struct TutorialSwipeIndicator: View {
    let direction: SwipeDirection  // .left, .right, .up, .down
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.4), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerOffset)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: shimmerOffset)
        .onAppear { shimmerOffset = 200 }
    }
}
```

### TypewriterText Tooltip

- Reuse existing `TypewriterText` component from onboarding
- Fixed position at bottom of screen, below container
- No "Next" button except final Complete button

---

## COMPANY CREATOR FLOW (7 Steps)

### Step 1: Job Board Overview
**View:** JobBoardDashboardView (mockup with placeholder cards)
**Overlay Target:** FAB button
**Tooltip:** "TAP THE + TO CREATE YOUR FIRST PROJECT"
**Action:** User taps FAB
**Haptic:** Light impact on tap

### Step 2: FAB Action Menu
**View:** FAB action menu expanded
**Overlay Target:** "Create Project" action only
**Other Actions:** 40% opacity, non-interactive
**Tooltip:** "TAP CREATE PROJECT"
**Action:** User taps Create Project
**Haptic:** Light impact

### Step 3: Project Creation Form
**View:** ProjectFormSheet (full opacity, no overlay)
**Pre-filled:** Nothing
**Available Data:** Top Gun clients, team members from demo database
**Tooltip Sequence:**
1. "SELECT A CLIENT" → User picks client
2. "NAME YOUR PROJECT" → User types name
3. "ADD A TASK" → User taps add task button

### Step 4: Task Creation
**View:** TaskFormSheet opens
**Tooltip Sequence:**
1. "ASSIGN YOUR CREW" → User selects team member(s)
2. "PICK THE WORK TYPE" → User selects task type
3. "SET THE DATE" → User picks date
4. "TAP DONE" → User completes task
**After:** Return to ProjectFormSheet
**Tooltip:** "TAP COMPLETE TO CREATE PROJECT"
**Action:** User taps Complete
**Haptic:** Success notification

### Step 5: Project List Status Demo
**View:** JobBoardProjectListView (forced switch from dashboard)
**Tooltip:** "WATCH: YOUR PROJECT MOVES THROUGH STATUSES"
**Animation Sequence:**
1. Project status set to ACCEPTED (immediate)
2. Wait 1.5 seconds
3. Status animates to IN_PROGRESS (with haptic)
4. Wait 1.5 seconds
5. Status animates to COMPLETED (with haptic)
**Advance:** Auto-advances after animation (4 second delay)

### Step 6: Project List Swipe
**View:** JobBoardProjectListView
**Swipe Indicator:** Leftward shimmer
**Tooltip:** "SWIPE LEFT TO CLOSE OUT THE PROJECT"
**Action:** User swipes project card to change status to CLOSED
**Haptic:** Success notification
**Advance:** User action required (swipe to close)

### Step 7: Closed Projects Scroll
**View:** JobBoardProjectListView (stays on same view)
**Tooltip:** "EXCELLENT! CLOSED PROJECTS APPEAR AT THE BOTTOM. SCROLL DOWN TO SEE THEM."
**Highlight:** CLOSED section button highlighted with pulsing accent border
**Advance:** Auto-advances after 3 seconds
**Transition:** Switches to Calendar tab

### Step 8: Calendar Week View
**View:** CalendarView (week mode) with Top Gun demo data
**Disabled:** Filter, search, refresh buttons (greyed out)
**Enabled:** Scrolling through week/day list
**Tooltip:** "YOUR WEEK AT A GLANCE. SCROLL TO EXPLORE."
**Advance Trigger:** User scrolls in the week view (detects scroll offset change > 10px)
**Next:** Shows month prompt

### Step 9: Calendar Month Prompt
**View:** CalendarView (week mode)
**Overlay Target:** Segmented picker (Week/Month toggle)
**Tooltip:** "TAP MONTH TO SEE THE BIG PICTURE"
**Action:** User taps Month segment
**Advance:** User action required (tap month toggle)

### Step 10: Calendar Month View
**View:** CalendarView (month mode)
**Tooltip:** "PINCH TO EXPAND. SCROLL TO EXPLORE."
**User Must:**
- Scroll through months (detects scroll offset change > 30px)
- AND pinch to expand/collapse rows (detects magnification change > 0.1)
**Advance Trigger:** Both scroll AND pinch detected
**Next:** Shows tutorial summary

### Step 11: Tutorial Summary
**View:** CalendarView (month mode) with floating DONE button
**Tooltip:** "THAT'S ALL IT TAKES. LET'S GO."
**Button:** White "DONE" button at bottom of screen
**Action:** User taps DONE button
**Advance:** User action required (tap DONE)
**Haptic:** Success notification
**Transition:** Tutorial completion screen

---

## EMPLOYEE FLOW (6 Steps)

### Pre-Setup
Dynamically add current user to 2-3 demo tasks for today:
- 1 task with status allowing "start" action
- 1-2 additional tasks showing on today's schedule

### Step 1: Home Screen Overview
**View:** EmployeeHomeView with demo tasks in carousel
**Overlay Target:** First project card in carousel
**Tooltip:** "YOUR JOBS FOR TODAY. TAP TO START."
**Action:** User taps project card
**Haptic:** Light impact

### Step 2: Start Project
**View:** Project card expands/highlights
**Tooltip:** "PROJECT STARTED. NOW CHECK THE DETAILS."
**Action:** Automatic transition

### Step 3: Project Details
**Overlay Target:** Project card in carousel
**Tooltip:** "LONG PRESS FOR PROJECT DETAILS"
**Action:** User long-presses
**View:** ProjectDetailView opens
**Haptic:** Medium impact

### Step 4: Add Note
**View:** ProjectDetailView
**Overlay Target:** Add note button/field
**Tooltip:** "ADD A NOTE FOR YOUR CREW"
**Action:** User taps, types brief note, saves
**Haptic:** Light impact

### Step 5: Add Photo
**Overlay Target:** Add photo button
**Tooltip:** "SNAP A PHOTO OF YOUR WORK"
**Action:** User taps (mock camera or photo picker)
**Note:** May need to mock this for tutorial sandbox
**Haptic:** Light impact

### Step 6: Complete Project
**View:** Close ProjectDetailView, return to home
**Overlay Target:** Complete button in project actions
**Tooltip:** "TAP COMPLETE WHEN YOU'RE DONE"
**Action:** User taps Complete
**Haptic:** Success notification

### Step 7: Job Board Browse
**View:** JobBoardView (employee version)
**Swipe Indicator:** Horizontal shimmer
**Tooltip:** "SWIPE TO SEE ALL YOUR JOBS BY STATUS"
**Action:** User swipes through status containers
**After:** Complete button appears

### Step 8: Calendar (Same as Company)
Follow Company flow Steps 8-9 for calendar week/month views.

---

## STOPWATCH & COMPLETION

### Stopwatch
```swift
class TutorialStateManager: ObservableObject {
    @Published var currentPhase: TutorialPhase = .notStarted
    @Published var startTime: Date?
    @Published var completionTime: TimeInterval?
    
    func startTutorial() {
        startTime = Date()
        currentPhase = .step1
    }
    
    func completeTutorial() {
        guard let start = startTime else { return }
        completionTime = Date().timeIntervalSince(start)
        currentPhase = .completed
    }
    
    var formattedTime: String {
        guard let time = completionTime else { return "" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var showTimeInCompletion: Bool {
        guard let time = completionTime else { return false }
        return time < 180  // 3 minutes
    }
}
```

### Completion Message

**Under 3 minutes:**
```
DONE IN [1:32]. NOW WE'RE TALKING.
```

**Over 3 minutes:**
```
DONE. LET'S GET TO WORK.
```

### Completion View
```swift
struct TutorialCompletionView: View {
    @ObservedObject var stateManager: TutorialStateManager
    
    var body: some View {
        VStack(spacing: 24) {
            if stateManager.showTimeInCompletion {
                Text("DONE IN \(stateManager.formattedTime). NOW WE'RE TALKING.")
                    .font(.title2)
                    .fontWeight(.bold)
            } else {
                Text("DONE. LET'S GET TO WORK.")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Button("LET'S GO") {
                // Dismiss tutorial, proceed to Welcome Guide
            }
            .buttonStyle(OPSPrimaryButtonStyle())
        }
    }
}
```

---

## DEMO DATA MANAGEMENT

### Seeding
```swift
class TutorialDemoDataManager {
    func seedDemoData() async {
        // Create team members (if not using existing)
        // Create clients
        // Create projects with tasks
        // Dates calculated relative to Date()
        // Reference: TopGun_Demo_Database.md
    }
    
    func addUserToTasks(userId: String) {
        // For employee flow: assign current user to 2-3 today tasks
    }
}
```

### Cleanup
```swift
func cleanupDemoData() async {
    // Delete all demo projects/tasks/clients
    // Or mark as hidden if using flags
    // Called when tutorial completes or user exits
}
```

### Date Calculation
All dates from `TopGun_Demo_Database.md` are relative:
- `current - N days` → `Calendar.current.date(byAdding: .day, value: -N, to: Date())`
- `current` → `Date()` (today)
- `current + N days` → `Calendar.current.date(byAdding: .day, value: N, to: Date())`

---

## STATE MANAGEMENT

### Tutorial Phases (Company)
```swift
enum TutorialPhase: String, CaseIterable {
    case notStarted

    // Job Board FAB Flow
    case jobBoardIntro              // Step 1: Highlight FAB
    case fabTap                     // Step 2: FAB menu open, highlight Create Project

    // Project Form Flow
    case projectFormClient          // Step 3a: Select client
    case projectFormName            // Step 3b: Enter project name
    case projectFormAddTask         // Step 3c: Tap Add Task

    // Task Form Flow
    case taskFormType               // Step 4a: Select task type
    case taskFormCrew               // Step 4b: Select crew
    case taskFormDate               // Step 4c: Set dates
    case taskFormDone               // Step 4d: Tap Done
    case projectFormComplete        // Step 4e: Tap Create

    // Project List Flow
    case projectListStatusDemo      // Step 5: Watch status animate
    case projectListSwipe           // Step 6: Swipe to close
    case closedProjectsScroll       // Step 7: See closed projects section

    // Calendar Flow
    case calendarWeek               // Step 8: Scroll week view
    case calendarMonthPrompt        // Step 9: Tap month toggle
    case calendarMonth              // Step 10: Scroll AND pinch month view
    case tutorialSummary            // Step 11: Final summary with DONE button

    case completed
}
```

### Tutorial Phases (Employee)
```swift
enum EmployeeTutorialPhase: Int, CaseIterable {
    case notStarted = 0
    case homeOverview
    case tapProject
    case longPressDetails
    case addNote
    case addPhoto
    case completeProject
    case jobBoardBrowse
    case calendarWeek
    case calendarMonth
    case completed
}
```

### Persistence
- No persistence needed
- Force-quit → restart from beginning
- Tutorial short enough this is acceptable

---

## HAPTIC FEEDBACK

| Action | Haptic Type |
|--------|-------------|
| Tap interactive element | `.lightImpact` |
| Long press recognized | `.mediumImpact` |
| Drag drop successful | `.mediumImpact` |
| Swipe action complete | `.success` |
| Project created | `.success` |
| Tutorial complete | `.success` |

```swift
let impactLight = UIImpactFeedbackGenerator(style: .light)
let impactMedium = UIImpactFeedbackGenerator(style: .medium)
let notificationSuccess = UINotificationFeedbackGenerator()

// Usage
impactLight.impactOccurred()
notificationSuccess.notificationOccurred(.success)
```

---

## VIEW MODIFICATIONS NEEDED

### Existing Views to Modify

1. **JobBoardDashboardView**
   - Accept `@Environment(\.tutorialMode)`
   - When true: use demo data source, disable non-tutorial interactions

2. **ProjectFormSheet**
   - Accept tutorial mode
   - When true: only show Top Gun clients/team members

3. **TaskFormSheet**
   - Accept tutorial mode
   - When true: only show demo task types

4. **CalendarView**
   - Accept tutorial mode
   - When true: disable filter/search/refresh, use demo data

5. **ProjectListView**
   - Accept tutorial mode
   - When true: show only demo projects

6. **EmployeeHomeView**
   - Accept tutorial mode
   - When true: show user-assigned demo tasks

---

## TUTORIAL HIGHLIGHT SYSTEM

### Centralized Style Configuration
All highlight styles are defined in `TutorialHighlightStyle` (TutorialEnvironment.swift):
```swift
struct TutorialHighlightStyle {
    static let color: Color = OPSStyle.Colors.primaryAccent
    static let lineWidth: CGFloat = 3
    static let pulseOpacity: (min: Double, max: Double) = (0.5, 1.0)
    static let pulseDuration: TimeInterval = 0.6
    static let pulseScale: (min: CGFloat, max: CGFloat) = (1.0, 1.05)
    static let padding: CGFloat = 4
}
```

### View Modifiers
```swift
// Rectangular highlight (for cards, buttons, fields)
.tutorialHighlight(for: .projectFormClient, cornerRadius: 12)

// Circular highlight (for FAB button)
.tutorialHighlightCircle(for: .jobBoardIntro)
```

### Environment Values Required
Views must receive both environment values to show highlights:
```swift
.environment(\.tutorialMode, true)
.environment(\.tutorialPhase, stateManager.currentPhase)
```

---

## NOTIFICATION FLOW

### User Action → Phase Advance Notifications
| Notification Name | Posted By | Advances Phase |
|-------------------|-----------|----------------|
| `TutorialFABTapped` | FloatingActionMenu | `.jobBoardIntro` → `.fabTap` |
| `TutorialCreateProjectTapped` | FloatingActionMenu | `.fabTap` → `.projectFormClient` |
| `TutorialProjectFormComplete` | ProjectFormSheet | `.projectFormComplete` → `.projectListStatusDemo` |
| `TutorialProjectListSwipe` | JobBoardProjectListView | `.projectListSwipe` → `.closedProjectsScroll` |
| `TutorialCalendarWeekScrolled` | ScheduleView | `.calendarWeek` → `.calendarMonthPrompt` |
| `TutorialCalendarMonthTapped` | ScheduleView | `.calendarMonthPrompt` → `.calendarMonth` |
| `TutorialCalendarMonthExplored` | ScheduleView | `.calendarMonth` → `.tutorialSummary` |

### Internal Detection Notifications
| Notification Name | Posted By | Purpose |
|-------------------|-----------|---------|
| `CalendarWeekViewScrolled` | ProjectListView | Detected scroll in week view |
| `CalendarMonthViewScrolled` | MonthGridView | Detected scroll in month view |
| `CalendarMonthViewPinched` | MonthGridView | Detected pinch gesture |
| `ProjectStatusChanged` | UniversalJobBoardCard | Detected swipe status change |

---

## DISABLED ELEMENTS DURING TUTORIAL

### Globally Disabled
- Tab bar navigation
- Settings access
- Any navigation outside tutorial flow

### Calendar Specific
- Filter button
- Search button
- Refresh button

### Visual Treatment for Disabled
- 40% opacity
- `allowsHitTesting(false)`

---

## FILES REFERENCE

- **Demo Database:** `TopGun_Demo_Database.md`
- **Project Images:** To be provided in Assets folder (per-project images, referenced in amended database)

---

## IMPLEMENTATION ORDER

1. **TutorialStateManager** - Phase tracking, stopwatch
2. **TutorialContainerView** - 80% scaled container
3. **TutorialOverlayView** - Dark overlay with cutout
4. **TutorialSwipeIndicator** - Shimmer animation
5. **TutorialDemoDataManager** - Seed Top Gun data
6. **CompanyTutorialFlow** - Orchestrate company steps
7. **EmployeeTutorialFlow** - Orchestrate employee steps
8. **View modifications** - Add tutorial mode to existing views
9. **TutorialCompletionView** - Final screen with time
10. **Integration** - Wire into onboarding flow after Ready screen

---

## TESTING CHECKLIST

- [ ] Tutorial starts after Ready screen
- [ ] Stopwatch starts on first interaction
- [ ] Each step advances only after correct action
- [ ] Overlay correctly highlights target elements
- [ ] Swipe indicators animate in correct direction
- [ ] Haptics fire on all interactions
- [ ] Demo data populates with correct relative dates
- [ ] Calendar shows demo projects correctly
- [ ] Force-quit restarts tutorial from beginning
- [ ] Completion time displays if under 3 min
- [ ] Completion message shows without time if over 3 min
- [ ] Demo data cleaned up after completion
- [ ] Proceeds to Welcome Guide after completion
