# AGENT HANDOVER DOCUMENT
**Last Updated:** Dec 18, 2025
**Current Phase:** Phase 4 Complete - View Modifications Done
**Branch:** `feature/interactive-tutorial-system`

---

## QUICK CONTEXT

**What We're Building:** An interactive onboarding tutorial where users learn OPS by doing in a sandbox populated with Top Gun-themed demo data.

**Two Flows:**
- **Company Creator** (~30 sec): Create project, manage status, browse calendar
- **Employee** (~20 sec): View assignments, add notes/photos, complete work

**Spec Files:**
- `Tutorial_Implementation_Spec.md` - Complete UX flow, visual system, state management
- `TopGun_Demo_Database.md` - 5 team members, 5 clients, 15 projects, 36 tasks

---

## CURRENT STATUS

### Completed
- [x] Branch created: `feature/interactive-tutorial-system`
- [x] Specification files reviewed
- [x] Codebase audit completed
- [x] Technical implementation guides created (6 documents)
- [x] **Phase 0: Model Updates** - `hasCompletedAppTutorial` field added
  - `User.swift` - Added property
  - `BubbleFields.User` - Added constant
  - `UserDTO.swift` - Added field, coding key, and mapping
  - Build verified successful
- [x] **Phase 1: Foundation** - COMPLETE
  - Created `OPS/Tutorial/` folder structure (Environment, State, Data, Views, Flows, Wrappers)
  - Built `TutorialEnvironment.swift` - Environment keys for tutorialMode, tutorialPhase, tutorialStateManager
  - Built `TutorialPhase.swift` - Phase enum with 28 phases, tooltip text, flow navigation
  - Built `TutorialStateManager.swift` - ObservableObject state manager with timing, haptics
  - Built `DemoIDs.swift` - All DEMO_ prefix ID constants
  - Built `DemoTeamMembers.swift` - 5 team members with specializations
  - Built `DemoClients.swift` - 5 clients with addresses and coordinates
  - Built `DemoTaskTypes.swift` - 12 task types with colors and icons
  - Built `DemoProjects.swift` - 15 projects with 36 tasks, date calculator
  - Build verified successful
- [x] **Phase 2: Data Layer** - COMPLETE
  - Built `TutorialDemoDataManager.swift` - Full seeding and cleanup implementation
  - Implemented `seedAllDemoData()` - Seeds TaskTypes, Users, Clients, Projects (with Tasks and CalendarEvents)
  - Implemented `cleanupAllDemoData()` - Deletes all DEMO_ prefixed entities in correct order
  - Implemented `assignCurrentUserToTasks(userId:)` - For employee flow assignment
  - Utility methods: `hasDemoData()`, `getDemoDataCounts()` for debugging
  - SwiftData predicates use `starts(with:)` for DEMO_ prefix matching
  - Build verified successful
- [x] **Phase 3: UI Components** - COMPLETE
  - Built `TutorialContainerView.swift` - 80% scaled container with touch passthrough
  - Built `TutorialOverlayView.swift` - Dark overlay with animated cutout + TutorialSpotlight + TutorialHighlightBorder
  - Built `TutorialTooltipView.swift` - Tooltip using TypewriterText animation + PositionedTooltip + TutorialTooltipCard
  - Built `TutorialSwipeIndicator.swift` - Shimmer animation with directional arrows
  - Built `TutorialCompletionView.swift` - Completion screen with conditional time display
  - Built `PreferenceKeys.swift` - Frame capture utilities with TutorialFrameCoordinator
  - Note: TutorialHaptics is embedded in TutorialStateManager.swift (no separate file needed)
  - Build verified successful
- [x] **Phase 4: View Modifications** - COMPLETE
  - Modified `JobBoardDashboard.swift` - Added tutorialMode environment, filters to DEMO_ projects
  - Modified `ProjectFormSheet.swift` - Added tutorialMode, availableClients/availableTeamMembers filter DEMO_ entities
  - Modified `TaskFormSheet.swift` - Added tutorialMode, availableProjects/availableTaskTypes/availableTeamMembers filter DEMO_ entities
  - Modified `FloatingActionMenu.swift` - Added tutorialMode, disables non-project actions (Create Client, Create Task, New Task Type) with opacity/allowsHitTesting
  - Modified `JobBoardProjectListView.swift` - Added tutorialMode, filters to DEMO_ projects
  - Modified `HomeView.swift` - Added tutorialMode, filters calendar events and projects to DEMO_ prefixed items
  - Modified `MonthGridView.swift` - Added tutorialMode, passes to cache.loadEvents for DEMO_ event filtering
  - Modified `ProjectDetailsView.swift` - Added tutorialMode environment property
  - Modified `UniversalJobBoardCard.swift` - Added tutorialMode environment property
  - Build verified successful

### In Progress
- [ ] Nothing currently in progress

### Next Steps (Phase 5 - Tutorial Flow Wrappers)
1. Build `TutorialCreatorFlowWrapper.swift` - Wraps JobBoard tab for company creator flow
2. Build `TutorialEmployeeFlowWrapper.swift` - Wraps Home tab for employee flow
3. Build `TutorialLauncherView.swift` - Entry point that chooses which flow to launch
4. Integrate with onboarding to trigger tutorial for new users

See `06_IMPLEMENTATION_SEQUENCE.md` for complete build order.

---

## CRITICAL NOTES FOR AGENTS

### Status Enums - IMPORTANT
The codebase uses DIFFERENT status enums than the spec:

**Project Status (actual):** `Status` enum in `DataModels/Status.swift`
- `.rfq`, `.estimated`, `.accepted`, `.inProgress`, `.completed`, `.closed`, `.archived`

**Task Status (actual):** `TaskStatus` enum in `DataModels/ProjectTask.swift`
- `.booked`, `.inProgress`, `.completed`, `.cancelled`

**Mapping (SCHEDULED removed):**
- Spec "ACCEPTED" = Code `.accepted`
- Spec "SCHEDULED" = **USE `.accepted`** (not a real status - just means all tasks are future-dated)
- Spec "IN_PROGRESS" = Code `.inProgress`
- Spec "COMPLETED" = Code `.completed`

**Important:** There is NO `.scheduled` status. Projects with all future tasks simply have `.accepted` status.

### TeamMember vs User
- `TeamMember` model is a lightweight display model
- `User` model is the full SwiftData entity used in relationships
- Demo data should create `User` entities, which will be referenced in project/task teamMembers

### Key File Locations
```
OPS/Views/JobBoard/JobBoardDashboard.swift    - Kanban drag-to-status
OPS/Views/JobBoard/ProjectFormSheet.swift     - Create project form
OPS/Views/JobBoard/TaskFormSheet.swift        - Create task form
OPS/Views/Home/HomeView.swift                 - Employee home view
OPS/Views/Components/FloatingActionMenu.swift - FAB with create options
OPS/Views/Calendar Tab/                       - Calendar views
OPS/DataModels/                               - SwiftData models
OPS/Onboarding/Components/TypewriterText.swift - Existing animation component
```

### Existing Gestures
- **Long-press + Drag:** `JobBoardDashboard.swift` lines 298-343 (DirectionalDragCard)
- **Swipe Status:** `UniversalJobBoardCard.swift` has swipeOffset handling
- **Long-press Haptic:** Both files use `UIImpactFeedbackGenerator`

### Naming Conflicts - RESOLVED
- **SwipeDirection:** The codebase has an existing `SwipeDirection` enum in `UniversalJobBoardCard.swift`
- Tutorial uses `TutorialSwipeDirection` to avoid ambiguity
- Located in `OPS/Tutorial/State/TutorialPhase.swift`

### SwiftData Predicate Syntax - IMPORTANT
- SwiftData `#Predicate` does NOT support `hasPrefix()` - use `starts(with:)` instead
- Enum values CANNOT be used directly in predicates - capture in local variable first
- Example:
  ```swift
  let demoPrefix = "DEMO_"
  let inProgressStatus = TaskStatus.inProgress
  let descriptor = FetchDescriptor<ProjectTask>(
      predicate: #Predicate { $0.id.starts(with: demoPrefix) && $0.status == inProgressStatus }
  )
  ```

### Avatar Loading for Demo Users
- Demo user avatars are loaded from asset catalog and stored as `profileImageData`
- Asset names: `pete`, `nick`, `tom`, `mike`, `rick` (in `Assets.xcassets/Images/Demo/`)
- Do NOT use `profileImageURL` for asset names - `UserAvatar` expects valid URLs
- The `seedUsers()` method converts UIImage assets to JPEG Data

### Employee Task Assignment
- `assignCurrentUserToTasks()` intentionally limits to 3 tasks per tutorial spec
- Employee flow only demonstrates 2-3 task interactions
- This is NOT a bug - it's the designed tutorial experience

---

## BLOCKERS / DECISIONS NEEDED

### Resolved
1. **Image Assets:** Available in `Assets.xcassets/Images/Demo/`
   - Project images: `flight_deck_before`, `flight_deck_progress`, `hangar_exterior`, etc.
   - Use asset name directly (e.g., `Image("flight_deck_before")`)

2. **Camera/Photo:** Use production photo picker - NOT mocked
   - User should be able to add photos as they normally would
   - Full camera/library access in tutorial

3. **Team Member Avatars:** Available in `Assets.xcassets/Images/Demo/`
   - Named by first name: `pete`, `nick`, `tom`, `mike`, `rick`
   - Use asset name directly (e.g., `Image("pete")`)

4. **"SCHEDULED" Status:** REMOVED from spec
   - Not a real status in the codebase
   - Projects with future tasks use `.accepted` status
   - Status is computed from task dates, not stored

5. **Tutorial Completion Tracking:** New Bubble field `hasCompletedAppTutorial` on User
   - Field will be added to Bubble User table
   - Must add to local `User` SwiftData model
   - Must add to `BubbleFields.User` constants
   - Must add to `UserDTO` for API sync
   - Check this field to determine if tutorial should show
   - Set to `true` on tutorial completion and sync to Bubble

### Technical Notes
- **Calendar View:** Composed of `MonthGridView.swift` + components in `Calendar Tab/Components/`
- **Status Mapping:** ACCEPTED, IN_PROGRESS, COMPLETED only (no SCHEDULED)

### Unresolved
(None - ready to proceed with implementation)

---

## AGENT INSTRUCTIONS

When you start work:
1. Read this document first
2. Check "Current Status" for what's done
3. Check "Next Steps" for what to do
4. Reference other docs in this folder for details
5. Update this document when you complete work

When you finish work:
1. Update "Current Status" - move items from "In Progress" to "Completed"
2. Update "Next Steps" - remove completed items, add any new ones discovered
3. Add any new blockers or decisions to "Blockers / Decisions Needed"
4. Note any important discoveries in "Critical Notes for Agents"

---

## FILE MANIFEST

### Documentation Files
| File | Purpose |
|------|---------|
| `00_AGENT_HANDOVER.md` | This file - living handover document |
| `01_CODEBASE_AUDIT.md` | Detailed audit of existing views/models/gestures |
| `02_ARCHITECTURE_PLAN.md` | Architecture decisions and patterns |
| `03_DEMO_DATA_IMPLEMENTATION.md` | Demo data seeding/cleanup strategy |
| `04_COMPONENT_INVENTORY.md` | New components to build |
| `05_VIEW_MODIFICATIONS.md` | Existing views needing changes |
| `06_IMPLEMENTATION_SEQUENCE.md` | Ordered build plan |
| `Tutorial_Implementation_Spec.md` | Original UX specification |
| `TopGun_Demo_Database.md` | Demo data content |

### Tutorial System Files (Created)
| File | Purpose |
|------|---------|
| `OPS/Tutorial/Environment/TutorialEnvironment.swift` | Environment keys for tutorialMode |
| `OPS/Tutorial/State/TutorialPhase.swift` | Phase enum with tooltips, flow navigation |
| `OPS/Tutorial/State/TutorialStateManager.swift` | State management, timing, haptics (includes TutorialHaptics) |
| `OPS/Tutorial/Data/DemoIDs.swift` | All DEMO_ prefix ID constants |
| `OPS/Tutorial/Data/DemoTeamMembers.swift` | 5 team members with specializations |
| `OPS/Tutorial/Data/DemoClients.swift` | 5 clients with addresses |
| `OPS/Tutorial/Data/DemoTaskTypes.swift` | 12 task types with colors/icons |
| `OPS/Tutorial/Data/DemoProjects.swift` | 15 projects with 36 tasks |
| `OPS/Tutorial/Data/TutorialDemoDataManager.swift` | SwiftData seeding/cleanup manager |
| `OPS/Tutorial/Views/TutorialContainerView.swift` | 80% scaled container for tutorial content |
| `OPS/Tutorial/Views/TutorialOverlayView.swift` | Dark overlay with cutout + highlight border |
| `OPS/Tutorial/Views/TutorialTooltipView.swift` | Tooltip using TypewriterText animation |
| `OPS/Tutorial/Views/TutorialSwipeIndicator.swift` | Shimmer animation for swipe hints |
| `OPS/Tutorial/Views/TutorialCompletionView.swift` | Completion screen with time display |
| `OPS/Tutorial/Utilities/PreferenceKeys.swift` | Frame capture utilities for cutout positioning |
