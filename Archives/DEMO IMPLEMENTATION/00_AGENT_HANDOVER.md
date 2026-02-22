# AGENT HANDOVER DOCUMENT
**Last Updated:** Dec 19, 2025
**Current Phase:** Phase 8 Complete - Phase Advancement Triggers Implemented
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

## 🚨 CRITICAL: UI REDESIGN REQUIRED

### Problem Discovered During Testing

The original approach used a **scaled-down phone-shaped container** (80% scale, iPhone 16 aspect ratio) to display the tutorial. During testing, we discovered critical usability issues:

1. **Touch targets too small** - Scaling the UI makes buttons/controls harder to tap
2. **Text illegible** - Scaled text is difficult to read
3. **Cramped experience** - Doesn't feel like the real app
4. **Sheet presentation issues** - iOS sheets escape the container (fixed with custom overlay, but adds complexity)

### New Approach: Full-Screen Tutorial

**Decision:** Display the tutorial at **full screen with floating overlays** instead of in a scaled container.

**How it works:**
- App UI displays at **native full-screen size** (no scaling)
- **Dark overlay with spotlight cutout** highlights current target element
- **Floating tooltip card** appears at bottom of screen
- Same tutorial flow logic, just different presentation layer

**Benefits:**
- Normal touch targets (same as production app)
- Legible text (no scaling)
- Natural feel (user learns the real UI)
- Simpler code (no container/scaling complexity)
- Native sheets work normally

### Implementation Changes Required

| Component | Current State | Required Change |
|-----------|---------------|-----------------|
| `TutorialContainerView.swift` | iPhone-shaped scaled container | **DELETE or repurpose** - no longer needed |
| `TutorialCreatorFlowWrapper.swift` | Wraps content in container | Show content full-screen with overlay |
| `TutorialEmployeeFlowWrapper.swift` | Wraps content in container | Show content full-screen with overlay |
| `TutorialSpotlight` | Works correctly | Keep as-is |
| `TutorialTooltipCard` | Works correctly | Keep as-is, position at screen bottom |
| `TutorialSheetOverlay.swift` | Custom sheet in container | May not be needed if using native sheets |

---

## CURRENT STATUS

### Completed
- [x] Branch created: `feature/interactive-tutorial-system`
- [x] Specification files reviewed
- [x] Codebase audit completed
- [x] Technical implementation guides created (6 documents)
- [x] **Phase 0: Model Updates** - `hasCompletedAppTutorial` field added
- [x] **Phase 1: Foundation** - Core tutorial infrastructure
- [x] **Phase 2: Data Layer** - Demo data seeding/cleanup
- [x] **Phase 3: UI Components** - Overlay, tooltip, swipe indicator, completion view
- [x] **Phase 4: View Modifications** - tutorialMode filtering in production views
- [x] **Phase 5: Tutorial Flow Wrappers** - Creator and Employee flow wrappers
- [x] **Phase 6: Onboarding Integration** - Tutorial integrated into onboarding flow
  - Tutorial shows for new users after Ready screen
  - Tutorial shows for returning users who haven't completed it
  - `hasCompletedAppTutorial` check works correctly

### Testing Results (Phase 6)
- [x] Tutorial launches correctly from onboarding flow
- [x] Tutorial launches for returning users without completion
- [x] FAB tap advances the phase correctly
- [x] Custom sheet overlay animates within container
- [x] Pulsing border animation removed (was distracting)
- [⚠️] **ISSUE:** Scaled container makes UI unusable (small touch targets, illegible text)

### Completed (Phase 7)
- [x] **Full-Screen UI Redesign** - COMPLETE
  - Refactored `TutorialCreatorFlowWrapper.swift` - Full-screen content with floating overlays
  - Refactored `TutorialEmployeeFlowWrapper.swift` - Same full-screen pattern
  - Deleted `TutorialContainerView.swift` - No longer needed
  - Deleted `TutorialSheetOverlay.swift` - Using native sheets
  - Modified `FloatingActionMenu.swift` - Posts notification in tutorial mode
  - Build verified successful

### Completed (Phase 8)
- [x] **Phase Advancement Triggers** - COMPLETE
  - Created `TutorialInlineSheet.swift` - Custom sheet that stays in view hierarchy
  - Created `TutorialCollapsibleTooltip.swift` - Top-positioned, expandable tooltip
  - Updated both flow wrappers with new tooltip and sheet components
  - Added NotificationCenter observers for all phase transitions
  - Modified `ProjectFormSheet.swift` - Client, name, add task, complete notifications
  - Modified `TaskFormSheet.swift` - Crew, type, date, done notifications
  - Modified `ScheduleView.swift` - Calendar week/month view notifications
  - Modified `TeamMemberPickerSheet` - Added tutorialMode environment
  - Build verified successful

### What Works (All Components)
1. **TutorialStateManager** - Phase progression, timing, haptics all work
2. **TutorialPhase enum** - All 28 phases defined with tooltips
3. **TutorialSpotlight** - Dark overlay with cutout works correctly
4. **TutorialCollapsibleTooltip** - Top-positioned, expandable with typewriter animation
5. **TutorialInlineSheet** - Custom sheet overlay that stays in view hierarchy
6. **TutorialSwipeIndicator** - Directional hints work
7. **TutorialCompletionView** - End screen works
8. **TutorialDemoDataManager** - Data seeding/cleanup works
9. **Demo data definitions** - All Top Gun content defined
10. **tutorialMode environment** - Filtering in production views works
11. **Onboarding integration** - Tutorial triggers correctly
12. **Phase advancement triggers** - NotificationCenter-based phase progression

### Next Steps (Phase 9 - Testing & Polish)
1. Test full Company Creator flow end-to-end
2. Test full Employee flow end-to-end
3. Verify demo data filtering works in all views
4. Add any missing spotlight frame captures for visual highlighting
5. Test completion flow and hasCompletedAppTutorial persistence

---

## CURRENT ARCHITECTURE

```
TutorialLauncherView
├── Seeds demo data
├── Detects flow type (creator vs employee)
└── Launches appropriate wrapper

TutorialCreatorFlowWrapper (FULL-SCREEN)
├── ZStack with 6 layers:
│   ├── Layer 1: Full-screen content (JobBoardView, ScheduleView, etc.)
│   ├── Layer 2: FAB overlay (GeometryReader for frame capture)
│   ├── Layer 3: TutorialSpotlight overlay (dark + cutout)
│   ├── Layer 4: TutorialSwipeIndicator (directional hints)
│   ├── Layer 5: TutorialInlineSheet (custom sheet that stays in hierarchy)
│   └── Layer 6: TutorialCollapsibleTooltip (top-positioned, expandable)
├── NotificationCenter observers for all phase transitions
└── stateManager controls phase progression

TutorialEmployeeFlowWrapper (FULL-SCREEN)
├── Same 6-layer ZStack pattern
├── HomeView and JobBoardView content
└── NotificationCenter observers for employee flow phases
```

## NOTIFICATION-BASED PHASE ADVANCEMENT

All phase transitions are handled via NotificationCenter:

| Notification Name | Source View | Phase Triggered |
|-------------------|-------------|-----------------|
| `TutorialCreateProjectTapped` | FloatingActionMenu | .fabTap → .createProjectAction |
| `TutorialClientSelected` | ProjectFormSheet | .projectFormClient → .projectFormName |
| `TutorialProjectNameEntered` | ProjectFormSheet | .projectFormName → .projectFormAddTask |
| `TutorialAddTaskTapped` | ProjectFormSheet | .projectFormAddTask → .taskFormCrew |
| `TutorialCrewAssigned` | TeamMemberPickerSheet | .taskFormCrew → .taskFormType |
| `TutorialTaskTypeSelected` | TaskFormSheet | .taskFormType → .taskFormDate |
| `TutorialDateSet` | TaskFormSheet | .taskFormDate → .taskFormDone |
| `TutorialTaskFormDone` | TaskFormSheet | .taskFormDone → .projectFormComplete |
| `TutorialProjectFormComplete` | ProjectFormSheet | .projectFormComplete → .dragToAccepted |
| `TutorialCalendarWeekViewed` | ScheduleView | .calendarWeek → .calendarMonthPrompt |
| `TutorialCalendarMonthTapped` | ScheduleView | .calendarMonthPrompt → .calendarMonth |
| `TutorialCalendarMonthExplored` | ScheduleView | .calendarMonth → .completed |

---

## CRITICAL NOTES FOR AGENTS

### Status Enums - IMPORTANT
The codebase uses DIFFERENT status enums than the spec:

**Project Status (actual):** `Status` enum in `DataModels/Status.swift`
- `.rfq`, `.estimated`, `.accepted`, `.inProgress`, `.completed`, `.closed`, `.archived`

**Task Status (actual):** `TaskStatus` enum in `DataModels/ProjectTask.swift`
- `.booked`, `.inProgress`, `.completed`, `.cancelled`

**Important:** There is NO `.scheduled` status. Projects with all future tasks simply have `.accepted` status.

### Key File Locations
```
OPS/Views/JobBoard/JobBoardDashboard.swift    - Kanban drag-to-status
OPS/Views/JobBoard/ProjectFormSheet.swift     - Create project form
OPS/Views/JobBoard/TaskFormSheet.swift        - Create task form
OPS/Views/Home/HomeView.swift                 - Employee home view
OPS/Views/Components/FloatingActionMenu.swift - FAB with create options
OPS/Views/Calendar Tab/                       - Calendar views
OPS/DataModels/                               - SwiftData models
```

### tutorialMode Environment
All production views that need demo data filtering already have:
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

This filters to show only DEMO_ prefixed data during tutorial.

### SwiftData Predicate Syntax
- Use `starts(with:)` not `hasPrefix()`
- Capture enum values in local variables before using in predicates

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

### Tutorial System Files
| File | Status | Purpose |
|------|--------|---------|
| `TutorialEnvironment.swift` | ✅ Active | Environment keys for tutorialMode |
| `TutorialPhase.swift` | ✅ Active | Phase enum with tooltips, flow navigation |
| `TutorialStateManager.swift` | ✅ Active | State management, timing, haptics |
| `DemoIDs.swift` | ✅ Active | All DEMO_ prefix ID constants |
| `DemoTeamMembers.swift` | ✅ Active | 5 team members with specializations |
| `DemoClients.swift` | ✅ Active | 5 clients with addresses |
| `DemoTaskTypes.swift` | ✅ Active | 12 task types with colors/icons |
| `DemoProjects.swift` | ✅ Active | 15 projects with 36 tasks |
| `TutorialDemoDataManager.swift` | ✅ Active | SwiftData seeding/cleanup manager |
| `TutorialOverlayView.swift` | ✅ Active | Dark overlay with cutout + highlight |
| `TutorialTooltipView.swift` | ✅ Active | Tooltip with typewriter animation |
| `TutorialCollapsibleTooltip.swift` | ✅ Active | Top-positioned, expandable tooltip |
| `TutorialInlineSheet.swift` | ✅ Active | Custom sheet that stays in view hierarchy |
| `TutorialSwipeIndicator.swift` | ✅ Active | Shimmer animation for swipe hints |
| `TutorialCompletionView.swift` | ✅ Active | Completion screen with time display |
| `PreferenceKeys.swift` | ✅ Active | Frame capture utilities |
| `TutorialCreatorFlowWrapper.swift` | ✅ Active | Full-screen wrapper with 6-layer ZStack |
| `TutorialEmployeeFlowWrapper.swift` | ✅ Active | Full-screen wrapper for employee flow |
| `TutorialLauncherView.swift` | ✅ Active | Entry point for tutorial |
| `TutorialContainerView.swift` | ❌ Deleted | Was scaled container - no longer needed |
| `TutorialSheetOverlay.swift` | ❌ Deleted | Was custom sheet - using native sheets |

### Files Modified for Onboarding Integration
| File | Changes |
|------|---------|
| `OnboardingState.swift` | Added `.tutorial` case |
| `OnboardingManager.swift` | Tutorial navigation logic |
| `OnboardingContainer.swift` | Routes to TutorialLauncherView |
| `LoginView.swift` | AppState environment object |
| `OnboardingPreviewView.swift` | AppState environment object |
| `ContentView.swift` | Tutorial check for returning users |
| `FloatingActionMenu.swift` | Posts notification in tutorial mode for project creation |

### Files Modified for Phase Advancement (Phase 8)
| File | Changes |
|------|---------|
| `ProjectFormSheet.swift` | Tutorial notifications for client, name, add task, complete |
| `TaskFormSheet.swift` | Tutorial notifications for crew, type, date, done |
| `TeamMemberPickerSheet` | Added tutorialMode environment for crew assignment |
| `ScheduleView.swift` | Tutorial notifications for calendar week/month views |

---

## AGENT INSTRUCTIONS

**Current State:** Phase 8 complete - Phase advancement triggers implemented

**What's Working:**
- Full-screen tutorial UI with 6-layer ZStack architecture
- Collapsible tooltip at top of screen with typewriter animation
- Custom inline sheet that allows tooltip to stay visible
- NotificationCenter-based phase advancement for all form interactions
- Calendar view notifications for week/month phases
- Auto-advancing phases for intro screens

**Next Steps (Phase 9 - Testing & Polish):**

1. **Test full Company Creator flow**
   - New user: Onboarding → Tutorial → Main App
   - Verify each phase advances correctly
   - Check tooltip text matches current phase

2. **Test full Employee flow**
   - Same onboarding path with employee user
   - Verify home view and project interaction phases

3. **Wire up remaining spotlight frames**
   - FAB frame is captured ✅
   - Project card frames need wiring for drag-to-accepted
   - Form field frames for visual highlighting

4. **Verify demo data**
   - Seeding works correctly
   - Cleanup removes all DEMO_ data
   - Demo projects appear in Job Board with tutorialMode filter

5. **Test completion flow**
   - hasCompletedAppTutorial flag is set
   - Tutorial doesn't show again after completion
   - Completion screen displays correctly

**Key Principle:** The tutorial should feel exactly like using the real app, just with guidance overlays.
