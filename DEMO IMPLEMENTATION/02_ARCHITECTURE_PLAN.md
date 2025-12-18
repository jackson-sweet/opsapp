# ARCHITECTURE PLAN

Technical architecture for the interactive tutorial system.

---

## 1. WRAPPER/DECORATOR PATTERN

### Approach
Create thin wrapper views that compose real views rather than modifying them directly.

**Benefits:**
- Real views remain unchanged
- Tutorial logic centralized in wrappers
- Easy to remove tutorial system later
- Changes to real views propagate automatically

### Example Structure
```swift
// Tutorial wrapper
struct TutorialJobBoardWrapper: View {
    @ObservedObject var tutorialManager: TutorialStateManager

    var body: some View {
        ZStack {
            // Real view with tutorial mode injected
            JobBoardDashboard()
                .environment(\.tutorialMode, true)

            // Tutorial overlay
            TutorialOverlayView(cutoutFrame: tutorialManager.currentCutout)

            // Swipe indicator (when needed)
            if tutorialManager.showSwipeHint {
                TutorialSwipeIndicator(direction: tutorialManager.swipeDirection)
            }
        }
    }
}
```

---

## 2. ENVIRONMENT FLAG SYSTEM

### Definition
**File to Create:** `OPS/Tutorial/Environment/TutorialEnvironment.swift`

```swift
import SwiftUI

// MARK: - Tutorial Mode Environment Key
struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }
}

// MARK: - Tutorial Phase Environment Key (optional, for fine-grained control)
struct TutorialPhaseKey: EnvironmentKey {
    static let defaultValue: TutorialPhase? = nil
}

extension EnvironmentValues {
    var tutorialPhase: TutorialPhase? {
        get { self[TutorialPhaseKey.self] }
        set { self[TutorialPhaseKey.self] = newValue }
    }
}
```

### Usage in Existing Views
```swift
struct JobBoardDashboard: View {
    @Environment(\.tutorialMode) private var tutorialMode

    var body: some View {
        // Existing view code...

        // Conditional behavior
        if tutorialMode {
            // Use demo data instead of real data
            // Disable certain interactions
        }
    }
}
```

---

## 3. STATE MANAGEMENT

### TutorialStateManager
**File to Create:** `OPS/Tutorial/State/TutorialStateManager.swift`

```swift
import SwiftUI
import Combine

@MainActor
class TutorialStateManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentPhase: TutorialPhase = .notStarted
    @Published var isActive: Bool = false
    @Published var showSwipeHint: Bool = false
    @Published var swipeDirection: SwipeDirection = .right
    @Published var currentCutout: CGRect = .zero
    @Published var tooltipText: String = ""
    @Published var showTooltip: Bool = false

    // MARK: - Timing
    @Published var startTime: Date?
    @Published var completionTime: TimeInterval?

    // MARK: - Flow Type
    let flowType: TutorialFlowType

    // MARK: - Computed Properties
    var formattedTime: String {
        guard let time = completionTime else { return "" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var showTimeInCompletion: Bool {
        guard let time = completionTime else { return false }
        return time < 180 // Under 3 minutes
    }

    // MARK: - Initialization
    init(flowType: TutorialFlowType) {
        self.flowType = flowType
    }

    // MARK: - Lifecycle
    func start() {
        isActive = true
        startTime = Date()
        currentPhase = flowType == .companyCreator ? .jobBoardIntro : .homeOverview
        updateTooltip()
    }

    func advancePhase() {
        currentPhase = currentPhase.next(for: flowType) ?? .completed
        updateTooltip()

        if currentPhase == .completed {
            complete()
        }
    }

    func complete() {
        guard let start = startTime else { return }
        completionTime = Date().timeIntervalSince(start)
        isActive = false
    }

    // MARK: - Tooltip Management
    private func updateTooltip() {
        tooltipText = currentPhase.tooltipText
        showTooltip = !tooltipText.isEmpty
    }

    // MARK: - Cutout Management
    func setCutout(for frame: CGRect) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentCutout = frame
        }
    }
}
```

### TutorialPhase Enum
```swift
enum TutorialPhase: Int, CaseIterable {
    case notStarted = 0

    // Company Creator Phases
    case jobBoardIntro
    case fabTap
    case createProjectAction
    case projectFormClient
    case projectFormName
    case projectFormAddTask
    case taskFormCrew
    case taskFormType
    case taskFormDate
    case taskFormDone
    case projectFormComplete
    case dragToAccepted
    case statusProgressionInProgress
    case statusProgressionCompleted
    case projectListSwipe
    case calendarWeek
    case calendarMonthPrompt
    case calendarMonth

    // Employee Phases (shared phases after homeOverview)
    case homeOverview
    case tapProject
    case projectStarted
    case longPressDetails
    case addNote
    case addPhoto
    case completeProject
    case jobBoardBrowse

    // Shared completion
    case completed

    var tooltipText: String {
        switch self {
        case .notStarted: return ""
        case .jobBoardIntro: return "TAP THE + TO CREATE YOUR FIRST PROJECT"
        case .fabTap: return "TAP CREATE PROJECT"
        case .createProjectAction: return "TAP CREATE PROJECT"
        case .projectFormClient: return "SELECT A CLIENT"
        case .projectFormName: return "NAME YOUR PROJECT"
        case .projectFormAddTask: return "ADD A TASK"
        case .taskFormCrew: return "ASSIGN YOUR CREW"
        case .taskFormType: return "PICK THE WORK TYPE"
        case .taskFormDate: return "SET THE DATE"
        case .taskFormDone: return "TAP DONE"
        case .projectFormComplete: return "TAP COMPLETE TO CREATE PROJECT"
        case .dragToAccepted: return "DRAG YOUR PROJECT TO ACCEPTED"
        case .statusProgressionInProgress: return "YOUR CREW STARTED. STATUS UPDATES AUTOMATICALLY."
        case .statusProgressionCompleted: return "JOB DONE. NOW CLOSE IT OUT."
        case .projectListSwipe: return "SWIPE TO ADVANCE STATUS"
        case .calendarWeek: return "YOUR WEEK AT A GLANCE. SCROLL, TAP, RESCHEDULE."
        case .calendarMonthPrompt: return "TAP MONTH TO SEE THE BIG PICTURE"
        case .calendarMonth: return "PINCH TO EXPAND. TAP A DAY TO SEE DETAILS."
        case .homeOverview: return "YOUR JOBS FOR TODAY. TAP TO START."
        case .tapProject: return "TAP TO START PROJECT"
        case .projectStarted: return "PROJECT STARTED. NOW CHECK THE DETAILS."
        case .longPressDetails: return "LONG PRESS FOR PROJECT DETAILS"
        case .addNote: return "ADD A NOTE FOR YOUR CREW"
        case .addPhoto: return "SNAP A PHOTO OF YOUR WORK"
        case .completeProject: return "TAP COMPLETE WHEN YOU'RE DONE"
        case .jobBoardBrowse: return "SWIPE TO SEE ALL YOUR JOBS BY STATUS"
        case .completed: return "YOU'RE READY."
        }
    }

    func next(for flowType: TutorialFlowType) -> TutorialPhase? {
        // Returns next phase based on flow type
        // Implementation depends on flow
    }
}

enum TutorialFlowType {
    case companyCreator
    case employee
}

enum SwipeDirection {
    case left, right, up, down
}
```

---

## 4. DEMO DATA LIFECYCLE

### Seeding Strategy
1. Generate unique IDs with "DEMO_" prefix for easy identification
2. Create all entities in a single transaction
3. Calculate dates relative to current date at seed time
4. Store demo company ID for filtering

### Detection Strategy
```swift
extension Project {
    var isDemoData: Bool {
        return id.hasPrefix("DEMO_")
    }
}

extension DataController {
    func fetchDemoProjects() -> [Project] {
        // Fetch only DEMO_ prefixed projects
    }

    func fetchRealProjects() -> [Project] {
        // Exclude DEMO_ prefixed projects
    }
}
```

### Cleanup Strategy
```swift
class TutorialDemoDataManager {
    func cleanupDemoData(context: ModelContext) async {
        // Delete all entities with DEMO_ prefix
        // Order: Tasks → CalendarEvents → Projects → Clients → TaskTypes → Users
    }
}
```

---

## 5. VIEW HIERARCHY FOR TUTORIAL

```
TutorialRootView
├── TutorialContainerView (80% scale + positioning)
│   ├── TutorialOverlayView (dark mask with cutout)
│   └── [Content View] (JobBoardDashboard, ProjectFormSheet, etc.)
├── TutorialSwipeIndicator (when showing swipe hints)
└── TutorialTooltipView (TypewriterText at bottom)
```

### Container View Scaling
```swift
struct TutorialContainerView<Content: View>: View {
    let content: Content

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                content
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height * 0.75
                    )
                    .scaleEffect(0.8)
                    .frame(
                        width: geometry.size.width * 0.8,
                        height: geometry.size.height * 0.6
                    )
                    .clipped()

                Spacer() // Space for tooltip
            }
        }
    }
}
```

### Touch Mapping for Scaled Content
```swift
// Touches in scaled container need coordinate transformation
extension View {
    func tutorialTouchMapping(scale: CGFloat) -> some View {
        self.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    // Transform coordinates: actual = touch / scale
                    let actualLocation = CGPoint(
                        x: value.location.x / scale,
                        y: value.location.y / scale
                    )
                }
        )
    }
}
```

---

## 6. INTEGRATION POINT

### Where Tutorial Starts
In `ReadyScreen.swift`, after billing info and before Welcome Guide:

```swift
// In ReadyScreen or OnboardingContainer
if shouldShowTutorial {
    TutorialRootView(
        flowType: userType == .company ? .companyCreator : .employee,
        onComplete: {
            // Proceed to Welcome Guide
            manager.advanceToWelcomeGuide()
        }
    )
}
```

### OnboardingManager Integration
Add new phase to `OnboardingManager`:
```swift
enum OnboardingScreen {
    // ... existing cases
    case tutorial  // New - between ready and welcome guide
}
```

---

## 7. FOLDER STRUCTURE

```
OPS/Tutorial/
├── Environment/
│   └── TutorialEnvironment.swift
├── State/
│   ├── TutorialStateManager.swift
│   └── TutorialPhase.swift
├── Data/
│   ├── TutorialDemoDataManager.swift
│   ├── DemoTeamMembers.swift
│   ├── DemoClients.swift
│   ├── DemoTaskTypes.swift
│   └── DemoProjects.swift
├── Views/
│   ├── TutorialRootView.swift
│   ├── TutorialContainerView.swift
│   ├── TutorialOverlayView.swift
│   ├── TutorialSwipeIndicator.swift
│   ├── TutorialTooltipView.swift
│   └── TutorialCompletionView.swift
├── Flows/
│   ├── CompanyTutorialFlow.swift
│   └── EmployeeTutorialFlow.swift
└── Wrappers/
    ├── TutorialJobBoardWrapper.swift
    ├── TutorialProjectFormWrapper.swift
    ├── TutorialCalendarWrapper.swift
    └── TutorialHomeWrapper.swift
```

---

## 8. HAPTIC FEEDBACK PATTERN

Centralized haptic helper:
```swift
struct TutorialHaptics {
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
```

Usage per action type:
| Action | Haptic |
|--------|--------|
| Tap interactive element | `lightTap()` |
| Long press recognized | `mediumImpact()` |
| Drag drop successful | `mediumImpact()` |
| Swipe action complete | `success()` |
| Project created | `success()` |
| Tutorial complete | `success()` |
